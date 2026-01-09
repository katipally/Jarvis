from typing import Literal
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
from .state import AgentState
from .tools import get_tools
from core.config import settings
from core.logger import setup_logger

logger = setup_logger(__name__)


def create_agent_graph():
    """Create the LangGraph agent workflow."""
    
    llm = ChatOpenAI(
        model=settings.OPENAI_MODEL,
        api_key=settings.OPENAI_API_KEY,
        streaming=True
    )
    
    tools = get_tools()
    llm_with_tools = llm.bind_tools(tools)
    
    def should_continue(state: AgentState) -> Literal["tools", "end"]:
        """Determine if we should use tools or end."""
        messages = state["messages"]
        last_message = messages[-1]
        
        if hasattr(last_message, "tool_calls") and last_message.tool_calls:
            return "tools"
        return "end"
    
    async def call_model(state: AgentState):
        """Call the LLM with current state."""
        messages = state["messages"]
        
        system_message = SystemMessage(content="""You are Jarvis, an advanced AI assistant built for macOS with full system control capabilities.

You can control the Mac through AppleScript automation - opening apps, controlling media, managing files, and much more.

## Core Capabilities:

### Knowledge & Search
- **search_knowledge_base**: Search user's document index
- **web_search**: Real-time internet search
- **process_uploaded_file**: Analyze uploaded documents

### Mac Control (AppleScript)
- **run_mac_script**: Execute pre-defined automation scripts (PREFERRED - use this first)
- **execute_applescript**: Run custom AppleScript code
- **execute_shell_command**: Execute shell/terminal commands
- **get_available_mac_scripts**: Discover available automation scripts

## Mac Automation Guidelines:

1. **Always prefer run_mac_script** with pre-defined scripts - they are tested and reliable.
2. **Use execute_applescript** only for custom needs not covered by pre-defined scripts.
3. **Never hallucinate AppleScript syntax** - if unsure, use get_available_mac_scripts to see what's available.

### Common Script IDs (use with run_mac_script):
**System**: system_get_battery, system_get_wifi, system_toggle_dark_mode, system_set_volume, system_mute, system_notification, system_say
**Apps**: app_open, app_quit, app_list_running, app_get_frontmost
**Media**: music_play, music_pause, music_next, music_current_track
**Browser**: safari_open_url, safari_get_url, chrome_open_url
**Files**: finder_new_window, finder_create_folder, finder_open_file
**Productivity**: calendar_today_events, reminders_create, reminders_list, notes_create
**Utilities**: clipboard_get, clipboard_set, terminal_new_tab

### Parameters Format:
When a script needs parameters, pass them as a dict:
- system_set_volume: {"volume_level": "50"}
- app_open: {"app_name": "Safari"}
- safari_open_url: {"url": "https://google.com"}
- system_notification: {"title": "Jarvis", "message": "Task complete!"}

## CRITICAL SAFETY RULE:
You CANNOT perform any delete, remove, trash, or destructive operations. These are blocked at the system level.
If a user asks to delete something, explain that this is blocked for safety and suggest alternatives.

## Response Style:
- Be concise and action-oriented
- When performing Mac actions, briefly explain what you're doing
- Use Markdown for formatting
- For multi-step tasks, execute them sequentially and report results

Current Environment: macOS
Mode: Full Mac Control Enabled""")
        
        full_messages = [system_message] + list(messages)
        
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
    
    graph = workflow.compile()
    
    logger.info("Agent graph created successfully")
    return graph


agent_graph = create_agent_graph()
