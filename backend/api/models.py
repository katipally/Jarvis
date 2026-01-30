"""
Jarvis API Models

Pydantic models for API requests and responses with unified stream schema.
"""

from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any, Literal
from enum import Enum


# ============== Enums ==============

class AgentMode(str, Enum):
    """Agent execution modes."""
    REASONING = "reasoning"
    FAST = "fast"


class Intent(str, Enum):
    """Classified user intents."""
    QUESTION = "question"
    ACTION = "action"
    MIXED = "mixed"
    UNKNOWN = "unknown"


class PlanStepStatus(str, Enum):
    """Status of a plan step."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class StreamEventType(str, Enum):
    """Types of streaming events."""
    CONTENT = "content"
    REASONING = "reasoning"
    THINKING = "thinking"
    PLAN = "plan"
    PLAN_STEP_UPDATE = "plan_step_update"
    TOOL = "tool"
    TOOL_RESULT = "tool_result"
    AUDIO = "audio"
    TRANSCRIPT = "transcript"
    SENTENCE_END = "sentence_end"
    INTENT = "intent"
    MODE = "mode"
    ERROR = "error"
    DONE = "done"


# ============== Request Models ==============

class ChatMessage(BaseModel):
    """A single chat message."""
    role: Literal["user", "assistant", "system"] = Field(..., description="Message role")
    content: str = Field(..., description="Message content")


class ChatRequest(BaseModel):
    """Request for chat endpoints."""
    messages: List[ChatMessage] = Field(..., description="Conversation messages")
    file_ids: Optional[List[str]] = Field(None, description="Attached file IDs for RAG")
    conversation_id: Optional[str] = Field(None, description="Conversation ID for context")
    mode: AgentMode = Field(AgentMode.REASONING, description="Agent mode: reasoning or fast")
    include_reasoning: bool = Field(True, description="Include reasoning in response")
    include_plan: bool = Field(True, description="Include plan in response (reasoning mode)")
    
    class Config:
        use_enum_values = True


class VoiceRequest(BaseModel):
    """Request for voice/conversation endpoints."""
    audio_data: Optional[str] = Field(None, description="Base64 encoded audio data")
    text: Optional[str] = Field(None, description="Text transcript (if already transcribed)")
    session_id: str = Field(..., description="Voice session ID")
    conversation_id: Optional[str] = Field(None, description="Associated conversation ID")
    mode: AgentMode = Field(AgentMode.FAST, description="Agent mode (usually fast for voice)")
    
    class Config:
        use_enum_values = True


# ============== Response Models ==============

class PlanStep(BaseModel):
    """A step in the execution plan."""
    id: str = Field(..., description="Unique step ID")
    description: str = Field(..., description="Step description")
    status: PlanStepStatus = Field(PlanStepStatus.PENDING, description="Step status")
    tool_name: Optional[str] = Field(None, description="Tool used for this step")
    tool_args: Optional[Dict[str, Any]] = Field(None, description="Tool arguments")
    result: Optional[str] = Field(None, description="Step result")
    error: Optional[str] = Field(None, description="Error message if failed")
    
    class Config:
        use_enum_values = True


class TokenUsage(BaseModel):
    """Token usage statistics."""
    prompt: int = Field(0, description="Prompt tokens")
    completion: int = Field(0, description="Completion tokens")
    total: int = Field(0, description="Total tokens")


class ChatResponse(BaseModel):
    """Response for non-streaming chat."""
    message: str = Field(..., description="Response message content")
    conversation_id: str = Field(..., description="Conversation ID")
    reasoning: Optional[List[str]] = Field(None, description="Reasoning steps")
    plan: Optional[List[PlanStep]] = Field(None, description="Execution plan")
    intent: Optional[Intent] = Field(None, description="Classified intent")
    mode: AgentMode = Field(AgentMode.REASONING, description="Mode used")
    tokens: Optional[TokenUsage] = Field(None, description="Token usage")
    
    class Config:
        use_enum_values = True


# ============== Stream Event Models ==============

class ContentEvent(BaseModel):
    """Content streaming event."""
    type: Literal["content"] = "content"
    text: str = Field(..., description="Text content chunk")
    is_complete: bool = Field(False, description="Whether this is the final content chunk")


class ReasoningEvent(BaseModel):
    """Reasoning/thinking streaming event."""
    type: Literal["reasoning"] = "reasoning"
    content: str = Field(..., description="Reasoning step content")


class ThinkingEvent(BaseModel):
    """Extended thinking event (chain of thought)."""
    type: Literal["thinking"] = "thinking"
    content: str = Field(..., description="Thinking content")
    is_complete: bool = Field(False, description="Whether thinking is complete")


class PlanEvent(BaseModel):
    """Plan creation event."""
    type: Literal["plan"] = "plan"
    steps: List[PlanStep] = Field(..., description="Plan steps")
    summary: str = Field("", description="Plan summary")
    status: Literal["started", "in_progress", "completed", "failed"] = "started"


class PlanStepUpdateEvent(BaseModel):
    """Plan step status update event."""
    type: Literal["plan_step_update"] = "plan_step_update"
    step_id: str = Field(..., description="Step ID being updated")
    status: PlanStepStatus = Field(..., description="New status")
    result: Optional[str] = Field(None, description="Step result")
    error: Optional[str] = Field(None, description="Error if failed")
    
    class Config:
        use_enum_values = True


class ToolEvent(BaseModel):
    """Tool call event."""
    type: Literal["tool"] = "tool"
    tool_name: str = Field(..., description="Tool being called")
    tool_args: Dict[str, Any] = Field(default_factory=dict, description="Tool arguments")
    tool_call_id: Optional[str] = Field(None, description="Tool call ID")


class ToolResultEvent(BaseModel):
    """Tool result event."""
    type: Literal["tool_result"] = "tool_result"
    tool_name: str = Field(..., description="Tool that was called")
    tool_call_id: Optional[str] = Field(None, description="Tool call ID")
    result: str = Field(..., description="Tool execution result")
    success: bool = Field(True, description="Whether tool execution succeeded")


class IntentEvent(BaseModel):
    """Intent classification event."""
    type: Literal["intent"] = "intent"
    intent: Intent = Field(..., description="Classified intent")
    confidence: float = Field(..., description="Classification confidence")
    
    class Config:
        use_enum_values = True


class ModeEvent(BaseModel):
    """Mode selection event."""
    type: Literal["mode"] = "mode"
    mode: AgentMode = Field(..., description="Selected mode")
    reason: Optional[str] = Field(None, description="Reason for mode selection")
    
    class Config:
        use_enum_values = True


class ErrorEvent(BaseModel):
    """Error event."""
    type: Literal["error"] = "error"
    error: str = Field(..., description="Error message")
    code: Optional[str] = Field(None, description="Error code")
    recoverable: bool = Field(True, description="Whether error is recoverable")


class DoneEvent(BaseModel):
    """Stream completion event."""
    type: Literal["done"] = "done"
    conversation_id: str = Field(..., description="Conversation ID")
    message_id: Optional[str] = Field(None, description="Message ID")
    tokens: TokenUsage = Field(default_factory=TokenUsage, description="Token usage")
    cost: Optional[float] = Field(None, description="Estimated cost in USD")
    reasoning_count: int = Field(0, description="Number of reasoning steps")
    tool_count: int = Field(0, description="Number of tool calls")


# ============== Voice/Audio Events ==============

class AudioEvent(BaseModel):
    """Audio streaming event (TTS output)."""
    type: Literal["audio"] = "audio"
    data: str = Field(..., description="Base64 encoded audio data")
    format: str = Field("pcm", description="Audio format")
    sample_rate: int = Field(24000, description="Sample rate in Hz")


class TranscriptEvent(BaseModel):
    """Speech transcript event (STT output)."""
    type: Literal["transcript"] = "transcript"
    text: str = Field(..., description="Transcribed text")
    is_final: bool = Field(False, description="Whether this is a final transcript")
    confidence: float = Field(1.0, description="Transcription confidence")


class SentenceEndEvent(BaseModel):
    """Sentence boundary event for TTS pacing."""
    type: Literal["sentence_end"] = "sentence_end"
    sentence_index: int = Field(..., description="Index of completed sentence")


# ============== File Upload ==============

class FileUploadResponse(BaseModel):
    """Response for file upload."""
    file_id: str = Field(..., description="Unique file ID")
    file_name: str = Field(..., description="Original file name")
    file_size: int = Field(..., description="File size in bytes")
    file_type: str = Field(..., description="MIME type")
    processed: bool = Field(..., description="Whether processing completed")
    message: str = Field(..., description="Status message")


# ============== Health Check ==============

class HealthResponse(BaseModel):
    """Health check response."""
    status: str = Field(..., description="Service status")
    version: str = Field(..., description="API version")
    chroma_db: Dict[str, Any] = Field(default_factory=dict, description="ChromaDB status")
    agent_config: Optional[Dict[str, Any]] = Field(None, description="Agent configuration")


# ============== Conversation Management ==============

class ConversationSummary(BaseModel):
    """Summary of a conversation."""
    id: str = Field(..., description="Conversation ID")
    title: str = Field(..., description="Conversation title")
    created_at: str = Field(..., description="Creation timestamp")
    updated_at: str = Field(..., description="Last update timestamp")
    message_count: int = Field(0, description="Number of messages")
    mode: Optional[AgentMode] = Field(None, description="Last used mode")
    
    class Config:
        use_enum_values = True


class ConversationDetail(BaseModel):
    """Full conversation with messages."""
    id: str = Field(..., description="Conversation ID")
    title: str = Field(..., description="Conversation title")
    created_at: str = Field(..., description="Creation timestamp")
    updated_at: str = Field(..., description="Last update timestamp")
    messages: List[ChatMessage] = Field(default_factory=list, description="Conversation messages")
    mode: Optional[AgentMode] = Field(None, description="Last used mode")
    
    class Config:
        use_enum_values = True
