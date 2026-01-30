"""
Jarvis Agent State Schema

Unified state schema supporting:
- Reasoning and Fast modes
- Intent classification (question/action/mixed)
- Step-by-step planning with status tracking
- Memory context from knowledge graph
- Voice configuration for conversation mode
"""

from typing import TypedDict, Annotated, Sequence, List, Dict, Any, Optional, Literal
from langchain_core.messages import BaseMessage
from langgraph.graph.message import add_messages
from dataclasses import dataclass, field
from datetime import datetime
import uuid


# ============== Plan Step Definition ==============

@dataclass
class PlanStep:
    """A single step in an execution plan."""
    id: str
    description: str
    status: Literal["pending", "running", "completed", "failed", "skipped"] = "pending"
    tool_name: Optional[str] = None
    tool_args: Optional[Dict[str, Any]] = None
    result: Optional[str] = None
    error: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "id": self.id,
            "description": self.description,
            "status": self.status,
            "tool_name": self.tool_name,
            "tool_args": self.tool_args,
            "result": self.result,
            "error": self.error,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PlanStep":
        """Create from dictionary."""
        return cls(
            id=data.get("id", str(uuid.uuid4())),
            description=data["description"],
            status=data.get("status", "pending"),
            tool_name=data.get("tool_name"),
            tool_args=data.get("tool_args"),
            result=data.get("result"),
            error=data.get("error"),
            started_at=datetime.fromisoformat(data["started_at"]) if data.get("started_at") else None,
            completed_at=datetime.fromisoformat(data["completed_at"]) if data.get("completed_at") else None,
        )


# ============== Voice Configuration ==============

@dataclass
class VoiceConfig:
    """Voice pipeline configuration."""
    # STT Configuration
    stt_provider: Literal["deepgram", "whisper", "apple"] = "apple"
    stt_model: str = "nova-2"
    stt_language: str = "en-US"
    
    # TTS Configuration
    tts_provider: Literal["chatterbox", "elevenlabs", "apple"] = "apple"
    tts_model: str = "default"
    tts_voice_id: Optional[str] = None
    tts_speed: float = 1.0
    tts_emotion: float = 0.5  # 0=monotone, 1=expressive
    
    # VAD Configuration
    vad_threshold: float = 0.5
    vad_min_speech_ms: int = 250
    vad_silence_ms: int = 500
    
    # Pipeline Configuration
    enable_noise_suppression: bool = True
    enable_interruption: bool = True
    sentence_boundary_streaming: bool = True
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "stt_provider": self.stt_provider,
            "stt_model": self.stt_model,
            "stt_language": self.stt_language,
            "tts_provider": self.tts_provider,
            "tts_model": self.tts_model,
            "tts_voice_id": self.tts_voice_id,
            "tts_speed": self.tts_speed,
            "tts_emotion": self.tts_emotion,
            "vad_threshold": self.vad_threshold,
            "vad_min_speech_ms": self.vad_min_speech_ms,
            "vad_silence_ms": self.vad_silence_ms,
            "enable_noise_suppression": self.enable_noise_suppression,
            "enable_interruption": self.enable_interruption,
            "sentence_boundary_streaming": self.sentence_boundary_streaming,
        }


# ============== Memory Context ==============

@dataclass
class MemoryContext:
    """Context retrieved from memory system."""
    entities: List[Dict[str, Any]] = field(default_factory=list)
    relations: List[Dict[str, Any]] = field(default_factory=list)
    relevant_facts: List[str] = field(default_factory=list)
    user_preferences: Dict[str, Any] = field(default_factory=dict)
    recent_topics: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "entities": self.entities,
            "relations": self.relations,
            "relevant_facts": self.relevant_facts,
            "user_preferences": self.user_preferences,
            "recent_topics": self.recent_topics,
        }
    
    def to_context_string(self) -> str:
        """Convert to a string for inclusion in system prompt."""
        parts = []
        
        if self.relevant_facts:
            parts.append("### Relevant Memory:\n" + "\n".join(f"- {f}" for f in self.relevant_facts[:5]))
        
        if self.user_preferences:
            prefs = [f"- {k}: {v}" for k, v in list(self.user_preferences.items())[:5]]
            parts.append("### User Preferences:\n" + "\n".join(prefs))
        
        if self.recent_topics:
            parts.append(f"### Recent Topics: {', '.join(self.recent_topics[:5])}")
        
        return "\n\n".join(parts) if parts else ""


# ============== Jarvis Agent State ==============

class JarvisState(TypedDict):
    """
    Unified state schema for the Jarvis agent.
    
    Supports:
    - Dual modes: reasoning (detailed, multi-step) and fast (quick responses)
    - Intent classification: question, action, or mixed
    - Step-by-step planning with real-time status updates
    - Memory integration (Cognee-style)
    - Voice configuration (Pipecat-style)
    """
    
    # ===== Core Message State =====
    messages: Annotated[Sequence[BaseMessage], add_messages]
    conversation_id: str
    
    # ===== Mode & Intent =====
    mode: Literal["reasoning", "fast"]
    intent: Literal["question", "action", "mixed", "unknown"]
    intent_confidence: float  # 0.0 to 1.0
    
    # ===== Planning (Reasoning Mode) =====
    plan: List[Dict[str, Any]]  # List of PlanStep.to_dict()
    current_step_index: int
    plan_summary: str  # Brief description of overall plan
    
    # ===== Memory Context (Cognee-style) =====
    memory_context: Dict[str, Any]  # MemoryContext.to_dict()
    session_memory: Dict[str, Any]  # Facts learned in this session
    
    # ===== Tool State =====
    tool_calls: List[Dict[str, Any]]
    pending_tools: List[str]
    tool_call_count: int
    
    # ===== RAG & Search Context =====
    file_context: Dict[str, Any]
    rag_results: List[Dict[str, Any]]
    search_results: List[Dict[str, Any]]
    
    # ===== Voice (Conversation Mode) =====
    voice_config: Dict[str, Any]  # VoiceConfig.to_dict()
    is_voice_session: bool
    
    # ===== Reasoning & Output =====
    reasoning: List[str]  # Chain of thought steps
    thinking: str  # Current thinking/reasoning text
    
    # ===== Guardrails (Adaptive) =====
    error_count: int
    consecutive_errors: int
    tool_history: List[Dict[str, Any]]  # For loop/stagnation detection
    guardrail_context: str  # Injected context from monitor
    should_stop: bool  # Signal from adaptive monitor
    stop_reason: str  # Why we should stop
    
    # ===== Routing =====
    next_action: Literal["classify", "plan", "execute", "respond", "end"]
    should_stream_plan: bool  # Whether to stream plan updates


# ============== State Factory Functions ==============

def create_initial_state(
    conversation_id: str,
    messages: Sequence[BaseMessage],
    mode: Literal["reasoning", "fast"] = "reasoning",
    is_voice: bool = False,
    file_context: Optional[Dict[str, Any]] = None,
) -> JarvisState:
    """Create initial state for a new agent invocation."""
    return JarvisState(
        # Core
        messages=list(messages),
        conversation_id=conversation_id,
        
        # Mode & Intent
        mode=mode,
        intent="unknown",
        intent_confidence=0.0,
        
        # Planning
        plan=[],
        current_step_index=0,
        plan_summary="",
        
        # Memory
        memory_context=MemoryContext().to_dict(),
        session_memory={},
        
        # Tools
        tool_calls=[],
        pending_tools=[],
        tool_call_count=0,
        
        # RAG & Search
        file_context=file_context or {},
        rag_results=[],
        search_results=[],
        
        # Voice
        voice_config=VoiceConfig().to_dict(),
        is_voice_session=is_voice,
        
        # Reasoning
        reasoning=[],
        thinking="",
        
        # Guardrails (Adaptive)
        error_count=0,
        consecutive_errors=0,
        tool_history=[],
        guardrail_context="",
        should_stop=False,
        stop_reason="",
        
        # Routing
        next_action="classify",
        should_stream_plan=True,
    )


def get_current_plan_step(state: JarvisState) -> Optional[PlanStep]:
    """Get the current plan step being executed."""
    if not state["plan"]:
        return None
    
    idx = state["current_step_index"]
    if idx < 0 or idx >= len(state["plan"]):
        return None
    
    return PlanStep.from_dict(state["plan"][idx])


def update_plan_step(
    state: JarvisState,
    step_id: str,
    status: Literal["pending", "running", "completed", "failed", "skipped"],
    result: Optional[str] = None,
    error: Optional[str] = None
) -> JarvisState:
    """Update a plan step's status."""
    updated_plan = []
    for step_dict in state["plan"]:
        if step_dict["id"] == step_id:
            step_dict = step_dict.copy()
            step_dict["status"] = status
            if result:
                step_dict["result"] = result
            if error:
                step_dict["error"] = error
            if status == "running":
                step_dict["started_at"] = datetime.now().isoformat()
            elif status in ["completed", "failed"]:
                step_dict["completed_at"] = datetime.now().isoformat()
        updated_plan.append(step_dict)
    
    return {**state, "plan": updated_plan}


# ============== Legacy Compatibility ==============

# Keep the old AgentState for backward compatibility during transition
class AgentState(TypedDict):
    """Legacy state schema - use JarvisState for new code."""
    messages: Annotated[Sequence[BaseMessage], add_messages]
    system_prompt: str
    reasoning: List[str]
    tool_calls: List[Dict[str, Any]]
    file_context: Dict[str, Any]
    rag_results: List[Dict[str, Any]]
    search_results: List[Dict[str, Any]]
    next_action: str
