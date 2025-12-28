from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any


class ChatMessage(BaseModel):
    role: str = Field(..., description="Role: 'user' or 'assistant'")
    content: str = Field(..., description="Message content")


class ChatRequest(BaseModel):
    messages: List[ChatMessage] = Field(..., description="Conversation messages")
    file_ids: Optional[List[str]] = Field(None, description="Attached file IDs")
    conversation_id: Optional[str] = Field(None, description="Conversation ID for context")
    include_reasoning: bool = Field(True, description="Include reasoning in response")


class ChatResponse(BaseModel):
    message: str
    reasoning: Optional[List[str]] = None
    conversation_id: str


class FileUploadResponse(BaseModel):
    file_id: str
    file_name: str
    file_size: int
    file_type: str
    processed: bool
    message: str


class HealthResponse(BaseModel):
    status: str
    version: str
    chroma_db: Dict[str, Any]
