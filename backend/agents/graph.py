from typing import Literal
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode
from langchain_openai import ChatOpenAI
from langchain_ollama import ChatOllama
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage, ToolMessage
from .state import AgentState
from .tools import get_tools
from core.config import settings
from core.preferences import preferences_manager
from core.logger import setup_logger

logger = setup_logger(__name__)

# Configuration for agent behavior limits
AGENT_CONFIG = {
    "max_tool_calls": 25,
    "max_consecutive_errors": 3,
    "recursion_limit": 100,
}


def create_agent_graph():
    """Create the LangGraph agent workflow with proper guardrails."""
    
    def count_tool_calls(state: AgentState) -> int:
        """Count total tool calls in the conversation."""
        count = 0
        for msg in state["messages"]:
            if hasattr(msg, "tool_calls") and msg.tool_calls:
                count += len(msg.tool_calls)
        return count
    
    def count_consecutive_errors(state: AgentState) -> int:
        """Count consecutive error messages at the end of conversation."""
        messages = state["messages"]
        error_count = 0
        for msg in reversed(messages):
            if isinstance(msg, ToolMessage):
                content = msg.content.lower() if isinstance(msg.content, str) else ""
                if "error" in content or "failed" in content or "syntax error" in content:
                    error_count += 1
                else:
                    break
            elif isinstance(msg, AIMessage) and not (hasattr(msg, "tool_calls") and msg.tool_calls):
                break
        return error_count
    
    def should_continue(state: AgentState) -> Literal["tools", "end"]:
        """Determine if we should use tools or end with guardrails."""
        messages = state["messages"]
        last_message = messages[-1]
        
        # Check if last message has tool calls
        if not (hasattr(last_message, "tool_calls") and last_message.tool_calls):
            return "end"
        
        # Guardrail 1: Check tool call limit
        tool_count = count_tool_calls(state)
        if tool_count >= AGENT_CONFIG["max_tool_calls"]:
            logger.warning(f"Tool call limit reached ({tool_count}). Stopping agent.")
            return "end"
        
        # Guardrail 2: Check consecutive errors
        error_count = count_consecutive_errors(state)
        if error_count >= AGENT_CONFIG["max_consecutive_errors"]:
            logger.warning(f"Too many consecutive errors ({error_count}). Stopping agent.")
            return "end"
        
        return "tools"
    
    async def call_model(state: AgentState):
        """Call the LLM with current state and guardrails."""
        # Dynamic LLM initialization based on current preferences
        prefs = preferences_manager.get()
        effective_model = prefs.current_model
        
        if prefs.ai_provider == "ollama":
            logger.info(f"Using Ollama Agent: {effective_model}")
            llm = ChatOllama(
                model=effective_model,
                temperature=0,
                num_ctx=8192,       # Reduced context for faster processing (conversation doesn't need 128k)
                num_predict=256,    # Limit max tokens for conversational responses (keeps it short)
                num_batch=512,      # Larger batch size for faster prompt processing
                num_thread=8,       # Use multiple CPU threads
                repeat_penalty=1.1, # Slight penalty to avoid repetition
            )
        else:
            logger.info(f"Using OpenAI Agent: {effective_model}")
            llm = ChatOpenAI(
                model=effective_model,
                api_key=settings.OPENAI_API_KEY,
                streaming=True
            )
        
        tools = get_tools()
        llm_with_tools = llm.bind_tools(tools)
        
        messages = state["messages"]
        
        # Check for guardrail conditions and add context if needed
        tool_count = count_tool_calls(state)
        error_count = count_consecutive_errors(state)
        
        guardrail_context = ""
        if tool_count >= AGENT_CONFIG["max_tool_calls"] - 2:
            guardrail_context = f"\n\n⚠️ IMPORTANT: You have used {tool_count} tool calls. You must complete the task NOW or explain what you've accomplished. Do NOT make more tool calls unless absolutely necessary."
        
        if error_count >= 2:
            guardrail_context += f"\n\n⚠️ WARNING: You have encountered {error_count} consecutive errors. STOP trying the same approach. Either try a completely different method OR explain to the user that the task cannot be completed and why."
        
        # Base operational rules (Always active)
        base_instructions = f"""
## JARVIS - AGENTIC AI ASSISTANT

You are Jarvis, an intelligent AI agent for macOS. You can answer questions, have conversations, AND control the Mac when needed. You are NOT biased toward any specific app or workflow - you reason dynamically based on each user request.

### CORE PRINCIPLES

1. **REASON FIRST, ACT SECOND**
   - Understand what the user actually wants to achieve
   - Consider multiple approaches before choosing one
   - If the request is ambiguous, ASK FOR CLARIFICATION before acting

2. **BE CONVERSATIONAL WHEN APPROPRIATE**
   - Not every request requires Mac automation
   - Answer questions directly when no action is needed
   - Engage naturally like ChatGPT, Siri, or Claude

3. **ASK FOR CLARIFICATION WHEN NEEDED**
   - If the user's intent is unclear, ask a specific question
   - If there are multiple valid interpretations, present options
   - Example: "Do you want me to search in Safari or Chrome?" or "Should I play the first result or let you choose?"

### AGENTIC TASK EXECUTION

When a task DOES require Mac control:

**PHASE 1: UNDERSTAND**
- What is the end goal?
- What information do I need to gather first?
- Are there ambiguities I should clarify?

**PHASE 2: PLAN DYNAMICALLY**
- Break the task into logical steps based on reasoning
- Do NOT follow hardcoded patterns - think about what a human would do
- Adapt the plan based on what you discover

**PHASE 3: EXECUTE & VERIFY**
- Execute ONE step at a time
- After each action, verify it worked (check output, get page info, etc.)
- If something fails, reason about WHY and try an alternative

**PHASE 4: ADAPT OR ESCALATE**
- If unexpected results occur, adapt your approach
- If truly stuck after 2-3 attempts, explain what happened and ask for guidance

### GENERAL-PURPOSE TOOLS

**Understanding the Environment:**
- `get_frontmost_app` - What app is currently active?
- `get_running_apps` - What apps are running?
- `get_ui_elements` - What can I click in the current app?
- `web_page_get_interactive_elements` - What can I interact with on this webpage?
- `web_page_get_text_content` - What does this webpage say?
- `capture_screen_for_analysis` - Take a screenshot to see current state

**App Control:**
- `launch_app` - Open any application
- `quit_app` / `hide_app` - Close or hide apps
- `manage_window` - Resize, move, minimize windows

**Browser Interaction (Works on ANY website):**
- `browser_navigate_to_url` - Go to any URL
- `web_page_fill_input` - Type in any input field
- `web_page_click_element` - Click any element by its text
- `web_page_execute_action` - Common actions (submit, scroll, back, forward, etc.)
- `browser_get_page_info` - Get current page title and URL

**Input Simulation:**
- `type_text` - Type text into any focused field
- `press_keyboard_shortcut` - Press any key combination
- `click_at_position` / `click_ui_element` - Click on screen

**System:**
- `get_system_state` - Battery, volume, display info
- `run_mac_script` - Use pre-built automation scripts
- `execute_applescript` - Custom scripts (only if no pre-built option exists)

### DECISION MAKING

**When to use tools vs just respond:**
- "What's the weather?" → Use `web_search` or answer if you know
- "Open Safari" → Use `launch_app`
- "How do I open Safari?" → Just explain, don't do it
- "Search for X on YouTube" → Reason: need browser, navigate to youtube, search

**When to ask for clarification:**
- Multiple browsers installed → "Which browser should I use?"
- Ambiguous search → "What specifically are you looking for?"
- Unclear intent → "Do you want me to do this, or explain how?"

### SAFETY & LIMITS
- Destructive operations (delete, trash, remove) are BLOCKED
- Stop after {AGENT_CONFIG["max_tool_calls"]} tool calls and summarize progress
- If a tool fails twice with the same error, try a different approach or explain the limitation

### APPLESCRIPT SYNTAX (Only if using execute_applescript)
- Escape double quotes: `"She said \\"Hello\\""`
- Use `try...on error` blocks for stability
{guardrail_context}
"""

        # Get personality from state or use default
        user_persona = state.get("system_prompt", "")
        if not user_persona:
            user_persona = """You are Jarvis, an intelligent AI assistant for macOS. 
You help users by executing tasks on their Mac.
Be concise, professional, and direct."""

        # Combine personality with rules
        full_system_prompt = f"{user_persona}\n\n{base_instructions}"
        
        system_message = SystemMessage(content=full_system_prompt)
        
        # Filter out old system messages to avoid confusion
        filtered_messages = [msg for msg in messages if not isinstance(msg, SystemMessage)]
        full_messages = [system_message] + filtered_messages
        
        response = await llm_with_tools.ainvoke(full_messages)
        
        return {
            "messages": [response],
            "reasoning": state.get("reasoning", [])
        }
    
    workflow = StateGraph(AgentState)
    
    workflow.add_node("agent", call_model)
    workflow.add_node("tools", ToolNode(get_tools()))
    
    workflow.add_edge(START, "agent")
    workflow.add_conditional_edges(
        "agent",
        should_continue,
        {
            "tools": "tools",
            "end": END
        }
    )
    workflow.add_edge("tools", "agent")
    
    # Compile with recursion limit to prevent infinite loops
    graph = workflow.compile()
    
    logger.info("Agent graph created successfully with guardrails")
    return graph


def get_agent_config():
    """Get the agent configuration for use in routes."""
    return AGENT_CONFIG


agent_graph = create_agent_graph()
