"""
Jarvis Agent Graph

LangGraph-based agent workflow with:
- Intent classification (question/action/mixed)
- Planning node for reasoning mode
- Step-by-step execution with status updates
- Memory context loading
- Guardrails and safety limits
"""

from typing import Literal, Dict, Any, List, Optional
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode
from langchain_openai import ChatOpenAI
from langchain_core.messages import (
    HumanMessage, AIMessage, SystemMessage, ToolMessage, BaseMessage
)
from langchain_core.prompts import ChatPromptTemplate
import json
import uuid
from datetime import datetime

from .state import JarvisState, PlanStep, create_initial_state
from .tools import get_tools
from .guardrails import AgentMonitor, create_monitor
from core.config import settings
from core.logger import setup_logger

logger = setup_logger(__name__)


# ============== Configuration ==============
# These are now adaptive defaults, not hard limits
AGENT_CONFIG = {
    "base_tool_limit": 15,  # Adaptive base
    "max_tool_limit": 30,   # Absolute max
    "max_consecutive_errors": 3,
    "recursion_limit": 100,
    "planning_model": settings.OPENAI_MODEL,
    "fast_model": getattr(settings, 'OPENAI_FAST_MODEL', 'gpt-4o-mini'),
    "reasoning_model": settings.OPENAI_MODEL,
}

# Legacy alias
AGENT_CONFIG["max_tool_calls"] = AGENT_CONFIG["max_tool_limit"]


# ============== Intent Classification ==============

INTENT_CLASSIFIER_PROMPT = """You are an intent classifier for an AI assistant. Analyze the user's message and classify their intent.

Classify into ONE of these categories:
- "question": User is asking for information, explanation, or clarification. No actions needed.
- "action": User wants you to DO something (open apps, search web, control Mac, create files, etc.)
- "mixed": User wants BOTH information AND actions (e.g., "What's the weather and open my calendar")

Also assess:
- confidence: How confident you are (0.0 to 1.0)
- complexity: Is this simple (1-2 steps) or complex (3+ steps)?

Respond in JSON format:
{
  "intent": "question" | "action" | "mixed",
  "confidence": 0.0-1.0,
  "complexity": "simple" | "complex",
  "reasoning": "Brief explanation of classification"
}

Examples:
- "What's the weather in NYC?" → {"intent": "question", "confidence": 0.95, "complexity": "simple", "reasoning": "Information request only"}
- "Open Safari" → {"intent": "action", "confidence": 0.98, "complexity": "simple", "reasoning": "Single action request"}
- "Search for AI news on YouTube and summarize the top video" → {"intent": "action", "confidence": 0.95, "complexity": "complex", "reasoning": "Multi-step browser automation"}
- "What's 2+2?" → {"intent": "question", "confidence": 0.99, "complexity": "simple", "reasoning": "Simple calculation question"}
"""


# ============== Planner Prompt ==============

PLANNER_PROMPT = """You are a planning assistant for Jarvis, a macOS AI assistant. Create a step-by-step plan to accomplish the user's request.

Current context:
- Mode: {mode}
- Intent: {intent}
- Available tools: {tool_names}

Create a plan with clear, actionable steps. Each step should:
1. Have a brief, clear description
2. Specify which tool will be used (if any)
3. Be atomic (one action per step)

Respond in JSON format:
{{
  "summary": "Brief description of what we're doing",
  "steps": [
    {{
      "description": "What this step does",
      "tool_name": "tool_name or null",
      "tool_args_hint": "Brief description of expected arguments"
    }}
  ]
}}

Guidelines:
- For simple tasks: 1-3 steps max
- For complex tasks: Up to 6 steps
- Always verify results when doing browser/app automation
- Include a final step to summarize or confirm completion

User request: {user_message}
"""


# ============== System Prompts ==============

def get_system_prompt(state: JarvisState, guardrail_context: str = "") -> str:
    """Generate the system prompt based on current state."""
    mode = state.get("mode", "reasoning")
    intent = state.get("intent", "unknown")
    memory_context_str = ""
    
    # Get memory context if available
    if state.get("memory_context"):
        from .state import MemoryContext
        try:
            mc = state["memory_context"]
            if mc.get("relevant_facts") or mc.get("user_preferences"):
                parts = []
                if mc.get("relevant_facts"):
                    parts.append("### Relevant Memory:\n" + "\n".join(f"- {f}" for f in mc["relevant_facts"][:5]))
                if mc.get("user_preferences"):
                    prefs = [f"- {k}: {v}" for k, v in list(mc["user_preferences"].items())[:5]]
                    parts.append("### User Preferences:\n" + "\n".join(prefs))
                memory_context_str = "\n\n" + "\n\n".join(parts)
        except Exception:
            pass
    
    base_prompt = f"""## JARVIS - AI ASSISTANT FOR macOS

You are Jarvis, an intelligent AI assistant for macOS. You operate in **{mode.upper()} MODE**.

### CURRENT CONTEXT
- Mode: {mode} ({'detailed analysis and planning' if mode == 'reasoning' else 'quick, direct responses'})
- Detected Intent: {intent}
{memory_context_str}

### CORE PRINCIPLES

1. **UNDERSTAND FIRST**: Fully understand what the user wants before acting.
2. **BE CONVERSATIONAL**: For questions, respond naturally like a helpful assistant.
3. **PLAN COMPLEX TASKS**: For actions, think through steps before executing.
4. **VERIFY ACTIONS**: After performing actions, confirm they worked.

### MODE-SPECIFIC BEHAVIOR

{"**REASONING MODE**: Take time to think through the problem. For actions, follow the plan step by step." if mode == 'reasoning' else "**FAST MODE**: Be concise and direct. Minimize steps. Quick answers for questions."}

### TOOL USAGE

You have access to Mac automation tools. Use them when the user wants you to DO something:
- App control: launch_app, quit_app, get_running_apps
- Browser: browser_navigate_to_url, web_page_fill_input, web_page_click_element
- System: get_system_state, execute_shell_command
- Input: type_text, press_keyboard_shortcut

**IMPORTANT**: 
- Don't use tools just to show off - only when needed
- For simple questions, just answer directly
- Maximum {AGENT_CONFIG['max_tool_calls']} tool calls per request

### SAFETY

- Destructive operations (delete, remove, trash) are BLOCKED
- Always explain what you're doing
- Ask for clarification if the request is ambiguous
{guardrail_context}
"""
    return base_prompt


# ============== Graph Nodes ==============

def create_jarvis_graph():
    """Create the Jarvis agent workflow graph."""
    
    # Initialize models
    reasoning_llm = ChatOpenAI(
        model=AGENT_CONFIG["reasoning_model"],
        api_key=settings.OPENAI_API_KEY,
        streaming=True
    )
    
    fast_llm = ChatOpenAI(
        model=AGENT_CONFIG["fast_model"],
        api_key=settings.OPENAI_API_KEY,
        streaming=True,
        temperature=0.3
    )
    
    classifier_llm = ChatOpenAI(
        model=AGENT_CONFIG["fast_model"],
        api_key=settings.OPENAI_API_KEY,
        temperature=0.1
    )
    
    tools = get_tools()
    tool_names = [t.name for t in tools]
    
    # Bind tools to both LLMs
    reasoning_llm_with_tools = reasoning_llm.bind_tools(tools)
    fast_llm_with_tools = fast_llm.bind_tools(tools)
    
    # ===== Node: Intent Classification =====
    async def classify_intent(state: JarvisState) -> Dict[str, Any]:
        """Classify user intent as question, action, or mixed."""
        messages = state["messages"]
        
        # Get the last user message
        user_message = ""
        for msg in reversed(messages):
            if isinstance(msg, HumanMessage):
                user_message = msg.content
                break
        
        if not user_message:
            return {
                "intent": "question",
                "intent_confidence": 0.5,
                "next_action": "respond"
            }
        
        # Quick heuristic for obvious cases
        action_keywords = ["open", "launch", "start", "run", "close", "quit", "search for", 
                         "play", "pause", "stop", "click", "type", "navigate", "go to",
                         "create", "make", "set", "change", "toggle", "send", "write"]
        
        user_lower = user_message.lower()
        has_action_words = any(kw in user_lower for kw in action_keywords)
        
        # For fast mode or simple questions, skip LLM classification
        if state.get("mode") == "fast" and not has_action_words:
            return {
                "intent": "question",
                "intent_confidence": 0.8,
                "next_action": "respond"
            }
        
        try:
            # Use LLM for classification
            classification_messages = [
                SystemMessage(content=INTENT_CLASSIFIER_PROMPT),
                HumanMessage(content=f"Classify this message: {user_message}")
            ]
            
            response = await classifier_llm.ainvoke(classification_messages)
            
            # Parse JSON response
            content = response.content
            # Extract JSON if wrapped in markdown
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            
            result = json.loads(content.strip())
            
            intent = result.get("intent", "question")
            confidence = result.get("confidence", 0.7)
            complexity = result.get("complexity", "simple")
            
            # Determine next action based on intent and mode
            if intent == "question":
                next_action = "respond"
            elif state.get("mode") == "fast" and complexity == "simple":
                next_action = "respond"  # Fast mode skips planning for simple actions
            else:
                next_action = "plan"
            
            logger.info(f"Intent classified: {intent} (confidence: {confidence}, complexity: {complexity})")
            
            return {
                "intent": intent,
                "intent_confidence": confidence,
                "next_action": next_action,
                "reasoning": [f"Intent: {intent} ({result.get('reasoning', 'N/A')})"]
            }
            
        except Exception as e:
            logger.error(f"Intent classification error: {e}")
            # Fallback based on heuristics
            return {
                "intent": "action" if has_action_words else "question",
                "intent_confidence": 0.6,
                "next_action": "plan" if has_action_words else "respond"
            }
    
    # ===== Node: Create Plan =====
    async def create_plan(state: JarvisState) -> Dict[str, Any]:
        """Create a step-by-step plan for action/mixed intents."""
        messages = state["messages"]
        
        # Get the last user message
        user_message = ""
        for msg in reversed(messages):
            if isinstance(msg, HumanMessage):
                user_message = msg.content
                break
        
        try:
            # Generate plan using LLM
            plan_prompt = PLANNER_PROMPT.format(
                mode=state.get("mode", "reasoning"),
                intent=state.get("intent", "action"),
                tool_names=", ".join(tool_names[:20]),
                user_message=user_message
            )
            
            plan_messages = [
                SystemMessage(content=plan_prompt),
                HumanMessage(content="Create a plan for this request.")
            ]
            
            response = await classifier_llm.ainvoke(plan_messages)
            
            # Parse JSON response
            content = response.content
            if "```json" in content:
                content = content.split("```json")[1].split("```")[0]
            elif "```" in content:
                content = content.split("```")[1].split("```")[0]
            
            result = json.loads(content.strip())
            
            # Convert to PlanStep format
            plan_steps = []
            for i, step in enumerate(result.get("steps", [])):
                plan_step = PlanStep(
                    id=f"step_{i+1}",
                    description=step.get("description", f"Step {i+1}"),
                    tool_name=step.get("tool_name"),
                    status="pending"
                )
                plan_steps.append(plan_step.to_dict())
            
            logger.info(f"Plan created with {len(plan_steps)} steps")
            
            return {
                "plan": plan_steps,
                "plan_summary": result.get("summary", "Executing user request"),
                "current_step_index": 0,
                "next_action": "execute",
                "should_stream_plan": True,
                "reasoning": state.get("reasoning", []) + [f"Plan: {result.get('summary', 'Created plan')}"]
            }
            
        except Exception as e:
            logger.error(f"Plan creation error: {e}")
            # Create a simple single-step plan
            plan_step = PlanStep(
                id="step_1",
                description="Execute user request",
                status="pending"
            )
            return {
                "plan": [plan_step.to_dict()],
                "plan_summary": "Processing request",
                "current_step_index": 0,
                "next_action": "execute"
            }
    
    # ===== Node: Execute (Call Model with Tools) =====
    async def execute_step(state: JarvisState) -> Dict[str, Any]:
        """Execute the current step using the LLM with tools."""
        messages = list(state["messages"])
        mode = state.get("mode", "reasoning")
        plan = list(state.get("plan", []))
        current_idx = state.get("current_step_index", 0)
        tool_history = list(state.get("tool_history", []))
        
        # If we just returned from tools, mark current step completed and advance
        last_msg = messages[-1] if messages else None
        if last_msg and isinstance(last_msg, ToolMessage) and plan and current_idx < len(plan):
            plan = [dict(s) for s in plan]
            plan[current_idx]["status"] = "completed"
            current_idx += 1
        
        # Select model based on mode
        llm = reasoning_llm_with_tools if mode == "reasoning" else fast_llm_with_tools
        
        # === ADAPTIVE GUARDRAILS ===
        # Create monitor and analyze current state
        monitor = create_monitor()
        monitor.set_task(
            task=messages[0].content if messages and hasattr(messages[0], 'content') else "",
            plan_steps=len(plan)
        )
        monitor.plan_steps_completed = sum(1 for s in plan if s.get("status") == "completed")
        monitor.tool_history = tool_history  # Restore history
        monitor.consecutive_errors = state.get("consecutive_errors", 0)
        
        # Check if we should continue
        should_continue, stop_reason, guidance = monitor.should_continue()
        
        if not should_continue:
            logger.warning(f"Adaptive guardrail triggered: {stop_reason}")
            # Return a message asking to wrap up
            wrap_up_msg = AIMessage(content=f"I need to wrap up now. {guidance}\n\n{stop_reason}")
            return {
                "messages": [wrap_up_msg],
                "should_stop": True,
                "stop_reason": stop_reason,
                "reasoning": state.get("reasoning", []) + [f"⚠️ {stop_reason}"],
            }
        
        # Get adaptive context to inject
        guardrail_context = monitor.get_context_injection()
        
        # Build system message with current context
        system_content = get_system_prompt(state, guardrail_context)
        
        # Add plan context if available
        if plan and current_idx < len(plan):
            current_step = plan[current_idx]
            plan_context = f"\n\n### CURRENT PLAN\n"
            for i, step in enumerate(plan):
                status_icon = "✓" if step["status"] == "completed" else "→" if step["status"] == "running" else "○"
                plan_context += f"{status_icon} Step {i+1}: {step['description']}\n"
            plan_context += f"\n**Currently executing Step {current_idx + 1}**: {current_step['description']}"
            system_content += plan_context
        
        system_message = SystemMessage(content=system_content)
        
        # Filter messages and add system
        filtered_messages = [msg for msg in messages if not isinstance(msg, SystemMessage)]
        full_messages = [system_message] + filtered_messages
        
        # Invoke LLM
        response = await llm.ainvoke(full_messages)
        
        # Process response
        tool_count = state.get("tool_call_count", 0)
        new_tool_count = tool_count
        reasoning = list(state.get("reasoning", []))
        new_tool_history = list(tool_history)
        
        # Track tool calls for loop detection
        if hasattr(response, "tool_calls") and response.tool_calls:
            new_tool_count += len(response.tool_calls)
            for tool_call in response.tool_calls:
                tool_name = tool_call.get('name', 'unknown')
                tool_args = tool_call.get('args', {})
                reasoning.append(f"Using tool: {tool_name}")
                
                # Record for loop detection
                import hashlib, json as json_mod
                args_hash = hashlib.md5(json_mod.dumps(tool_args, sort_keys=True, default=str).encode()).hexdigest()[:8]
                new_tool_history.append({
                    "tool_name": tool_name,
                    "args_hash": args_hash,
                    "timestamp": datetime.now().isoformat()
                })
        
        # Update step status if we have a plan (mark current step as running)
        updated_plan = [dict(s) for s in plan] if plan else []
        if updated_plan and current_idx < len(updated_plan):
            updated_plan[current_idx]["status"] = "running"
        
        return {
            "messages": [response],
            "tool_call_count": new_tool_count,
            "reasoning": reasoning,
            "plan": updated_plan,
            "current_step_index": current_idx,
            "tool_history": new_tool_history,
            "guardrail_context": guardrail_context,
        }
    
    # ===== Node: Respond (Direct Response) =====
    async def respond_direct(state: JarvisState) -> Dict[str, Any]:
        """Generate a direct response without tools (for questions)."""
        messages = list(state["messages"])
        mode = state.get("mode", "reasoning")
        
        # Select model based on mode
        llm = reasoning_llm if mode == "reasoning" else fast_llm
        
        system_content = get_system_prompt(state)
        system_message = SystemMessage(content=system_content)
        
        filtered_messages = [msg for msg in messages if not isinstance(msg, SystemMessage)]
        full_messages = [system_message] + filtered_messages
        
        response = await llm.ainvoke(full_messages)
        
        return {
            "messages": [response],
            "next_action": "end"
        }
    
    # ===== Routing Functions =====
    def route_after_classify(state: JarvisState) -> str:
        """Route based on classification result."""
        next_action = state.get("next_action", "respond")
        if next_action == "plan":
            return "plan"
        elif next_action == "execute":
            return "execute"
        else:
            return "respond"
    
    def route_after_execute(state: JarvisState) -> str:
        """Determine if we should continue with tools or end."""
        messages = state["messages"]
        last_message = messages[-1] if messages else None
        
        # Check adaptive guardrail signal
        if state.get("should_stop", False):
            logger.info(f"Adaptive guardrail stopped execution: {state.get('stop_reason', 'unknown')}")
            return "end"
        
        # Check if last message has tool calls
        if last_message and hasattr(last_message, "tool_calls") and last_message.tool_calls:
            # Adaptive guardrails: use monitor for smarter limits
            tool_history = state.get("tool_history", [])
            tool_count = len(tool_history)
            
            # Check for loops (same tool+args 3+ times in last 10 calls)
            if len(tool_history) >= 3:
                recent = tool_history[-10:]
                from collections import Counter
                call_keys = [f"{t['tool_name']}:{t['args_hash']}" for t in recent]
                most_common = Counter(call_keys).most_common(1)
                if most_common and most_common[0][1] >= 3:
                    logger.warning(f"Loop detected: {most_common[0][0]} repeated {most_common[0][1]} times")
                    return "end"
            
            # Absolute safety limit (but adaptive allows extension if making progress)
            if tool_count >= AGENT_CONFIG["max_tool_limit"]:
                logger.warning(f"Absolute tool limit reached ({tool_count})")
                return "end"
            
            # Check consecutive errors
            error_count = state.get("consecutive_errors", 0)
            if error_count >= AGENT_CONFIG["max_consecutive_errors"]:
                logger.warning(f"Too many consecutive errors ({error_count})")
                return "end"
            
            return "tools"
        
        return "end"
    
    def after_tools(state: JarvisState) -> Dict[str, Any]:
        """Process after tool execution - update plan step status."""
        messages = state["messages"]
        plan = state.get("plan", [])
        current_idx = state.get("current_step_index", 0)
        
        # Check for errors in tool results
        consecutive_errors = state.get("consecutive_errors", 0)
        
        if messages:
            last_msg = messages[-1]
            if isinstance(last_msg, ToolMessage):
                content = last_msg.content.lower() if isinstance(last_msg.content, str) else ""
                if "error" in content or "failed" in content:
                    consecutive_errors += 1
                else:
                    consecutive_errors = 0
        
        # Update plan step if applicable
        updated_plan = plan
        if plan and current_idx < len(plan):
            updated_plan = [s.copy() for s in plan]
            # Keep running status - will be updated to completed when step finishes
        
        return {
            "consecutive_errors": consecutive_errors,
            "plan": updated_plan
        }
    
    # ===== Build Graph =====
    workflow = StateGraph(JarvisState)
    
    # Add nodes
    workflow.add_node("classify", classify_intent)
    workflow.add_node("plan", create_plan)
    workflow.add_node("execute", execute_step)
    workflow.add_node("respond", respond_direct)
    workflow.add_node("tools", ToolNode(tools))
    
    # Add edges
    workflow.add_edge(START, "classify")
    
    workflow.add_conditional_edges(
        "classify",
        route_after_classify,
        {
            "plan": "plan",
            "execute": "execute",
            "respond": "respond"
        }
    )
    
    workflow.add_edge("plan", "execute")
    
    workflow.add_conditional_edges(
        "execute",
        route_after_execute,
        {
            "tools": "tools",
            "end": END
        }
    )
    
    workflow.add_edge("tools", "execute")
    workflow.add_edge("respond", END)
    
    # Compile
    graph = workflow.compile()
    logger.info("Jarvis agent graph created successfully")
    
    return graph


def get_agent_config() -> Dict[str, Any]:
    """Get the agent configuration."""
    return AGENT_CONFIG


# Create the graph instance
agent_graph = create_jarvis_graph()


# ============== Legacy Support ==============
# Keep create_agent_graph for backward compatibility
def create_agent_graph():
    """Legacy function - returns the new Jarvis graph."""
    return agent_graph
