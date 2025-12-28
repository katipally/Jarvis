from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from core.database import conversation_db
from core.logger import setup_logger
import uuid

logger = setup_logger(__name__)
router = APIRouter(prefix="/api/conversations", tags=["conversations"])


class ConversationCreate(BaseModel):
    title: Optional[str] = "New Chat"
    system_prompt: Optional[str] = None
    model: Optional[str] = "gpt-4o"


class ConversationUpdate(BaseModel):
    title: Optional[str] = None
    system_prompt: Optional[str] = None
    model: Optional[str] = None


class MessageCreate(BaseModel):
    role: str
    content: str
    reasoning: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


@router.post("/")
async def create_conversation(data: ConversationCreate):
    """Create a new conversation."""
    conv_id = str(uuid.uuid4())
    
    conversation = conversation_db.create_conversation(
        conv_id=conv_id,
        title=data.title,
        system_prompt=data.system_prompt,
        model=data.model
    )
    
    return conversation


@router.get("/")
async def list_conversations(limit: int = 50):
    """List all conversations."""
    conversations = conversation_db.list_conversations(limit=limit)
    return {"conversations": conversations}


@router.get("/{conversation_id}")
async def get_conversation(conversation_id: str):
    """Get a specific conversation with messages."""
    conversation = conversation_db.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    messages = conversation_db.get_messages(conversation_id)
    
    return {
        "conversation": conversation,
        "messages": messages
    }


@router.patch("/{conversation_id}")
async def update_conversation(conversation_id: str, data: ConversationUpdate):
    """Update conversation metadata."""
    conversation = conversation_db.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    update_data = data.model_dump(exclude_unset=True)
    conversation_db.update_conversation(conversation_id, **update_data)
    
    return {"success": True, "conversation_id": conversation_id}


@router.delete("/{conversation_id}")
async def delete_conversation(conversation_id: str):
    """Delete a conversation."""
    conversation = conversation_db.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    conversation_db.delete_conversation(conversation_id)
    return {"success": True}


@router.post("/{conversation_id}/messages")
async def add_message(conversation_id: str, message: MessageCreate):
    """Add a message to a conversation."""
    conversation = conversation_db.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    message_id = conversation_db.add_message(
        conv_id=conversation_id,
        role=message.role,
        content=message.content,
        reasoning=message.reasoning,
        metadata=message.metadata
    )
    
    return {"success": True, "message_id": message_id}


@router.get("/{conversation_id}/export")
async def export_conversation(conversation_id: str):
    """Export conversation as JSON."""
    data = conversation_db.export_conversation(conversation_id)
    if not data:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    return data
