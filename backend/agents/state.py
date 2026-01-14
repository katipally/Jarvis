from typing import TypedDict, Annotated, Sequence, List, Dict, Any
from langchain_core.messages import BaseMessage
from langgraph.graph.message import add_messages


class AgentState(TypedDict):
    """State schema for the agent."""
    messages: Annotated[Sequence[BaseMessage], add_messages]
    system_prompt: str  # Custom system prompt/personality override
    reasoning: List[str]
    tool_calls: List[Dict[str, Any]]
    file_context: Dict[str, Any]
    rag_results: List[Dict[str, Any]]
    search_results: List[Dict[str, Any]]
    next_action: str
