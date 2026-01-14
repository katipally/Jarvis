from typing import Literal
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage, ToolMessage
from .state import AgentState
from .tools import get_tools
from core.config import settings
from core.logger import setup_logger

logger = setup_logger(__name__)

# Configuration for agent behavior limits
AGENT_CONFIG = {
    "max_tool_calls": 10,  # Maximum tool calls per request
    "max_consecutive_errors": 3,  # Stop after this many consecutive errors
    "recursion_limit": 50,  # LangGraph recursion limit
}


def create_agent_graph():
    """Create the LangGraph agent workflow with proper guardrails."""
    
    llm = ChatOpenAI(
        model=settings.OPENAI_MODEL,
        api_key=settings.OPENAI_API_KEY,
        streaming=True
    )
    
    tools = get_tools()
    llm_with_tools = llm.bind_tools(tools)
    
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
## CRITICAL OPERATIONAL RULES:

### 1. TOOL USAGE
- **PREFER** `run_mac_script` over `execute_applescript` whenever possible.
- Only use `execute_applescript` if NO pre-built script exists.
- **NEVER** invent tool parameters. Use exactly what is defined.

### 2. APPLESCIPT SYNTAX (If using custom scripts)
- Escape ALL double quotes inside strings: `set txt to "She said \\"Hello\\""`
- Never end a line with `to` or `set` without a value.
- Use `try...on error` blocks for stability.

### 3. SAFETY & LIMITS
- Destructive operations (delete, trash, remove) are BLOCKED.
- Stop after {AGENT_CONFIG["max_tool_calls"]} tool calls.
- If a tool fails twice, STOP and explain.

### 4. ERROR HANDLING
- If a script fails, explain the error to the user naturally.
- Do not retry the exact same failing script endlessly.
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
    workflow.add_node("tools", ToolNode(tools))
    
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
