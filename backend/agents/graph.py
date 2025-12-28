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
        
        system_message = SystemMessage(content="""You are Jarvis, an intelligent AI assistant.
        
You have access to several tools:
- search_knowledge_base: Search stored documents and files
- web_search: Search the internet for current information
- process_uploaded_file: Process and analyze uploaded files

Use these tools when appropriate to provide accurate, helpful responses.
Think step by step and explain your reasoning clearly.""")
        
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
