"""
TEN Agent WebSocket endpoint for low-latency conversational AI.
Handles text-in/text-out with streaming responses optimized for voice.
Integrated with LangGraph for robust agentic behavior.
"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from langchain_core.messages import HumanMessage, AIMessage
from agents.graph import agent_graph
from core.logger import setup_logger
import json
import asyncio
from typing import Optional, Dict, Any, List
from datetime import datetime

router = APIRouter()
logger = setup_logger(__name__)

# Jarvis system prompt - casual, human-like with Mac control
JARVIS_VOICE_PERSONA = """You are Jarvis, a chill AI assistant with full macOS control.

PERSONALITY:
- Casual, friendly, like talking to a smart friend
- Keep it short - 1-2 sentences max (this is spoken aloud)
- Use natural speech: "Yeah", "Got it", "Sure thing", "No problem", "Alright"
- NO formal language - avoid "sir", "certainly", "indeed", "I shall"
- Be helpful without being stiff or robotic

SPEECH RULES:
- No formatting, lists, bullets, markdown
- Use contractions: "I'll", "you're", "that's", "can't", "won't"
- Sound human and relaxed, not like a butler

EXAMPLES:
"Open Safari" → "Opening Safari."
"Play music on Spotify" → "Playing Spotify."
"What time is it?" → "It's 3:30."
"How are you?" → "I'm good! What's up?"
"""


class ConversationSession:
    """Manages a single conversation session."""
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.messages = []
        self.created_at = datetime.now()
        self.last_activity = datetime.now()
    
    def add_message(self, role: str, content: str):
        self.messages.append({"role": role, "content": content})
        self.last_activity = datetime.now()
        # Keep context manageable (last 20 messages)
        if len(self.messages) > 20:
            self.messages = self.messages[-20:]
            
    def get_langchain_messages(self) -> List[Any]:
        """Convert session history to LangChain format."""
        lc_messages = []
        for msg in self.messages:
            if msg["role"] == "user":
                lc_messages.append(HumanMessage(content=msg["content"]))
            elif msg["role"] == "assistant":
                lc_messages.append(AIMessage(content=msg["content"]))
        return lc_messages


# Active sessions
sessions: Dict[str, ConversationSession] = {}


@router.websocket("/ws/conversation")
async def conversation_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for real-time conversation.
    Uses LangGraph for agentic execution.
    """
    await websocket.accept()
    session_id = None
    current_task: Optional[asyncio.Task] = None
    
    logger.info("New conversation WebSocket connection established")
    
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_text()
            message = json.loads(data)
            msg_type = message.get("type", "text")
            
            if msg_type == "interrupt":
                # Cancel current response generation
                if current_task and not current_task.done():
                    logger.info("Interrupting current task")
                    current_task.cancel()
                    await websocket.send_json({"type": "interrupted"})
                continue
            
            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})
                continue
            
            if msg_type == "text":
                content = message.get("content", "").strip()
                if not content:
                    continue
                
                # Get or create session
                session_id = message.get("session_id", session_id or "default")
                if session_id not in sessions:
                    sessions[session_id] = ConversationSession(session_id)
                
                session = sessions[session_id]
                
                # Import chat history from focus mode if provided
                chat_history = message.get("chat_history", [])
                if chat_history and not session.messages:
                    for hist_msg in chat_history:
                        session.add_message(hist_msg.get("role", "user"), hist_msg.get("content", ""))
                
                # Add user message
                session.add_message("user", content)
                
                # Cancel any existing task
                if current_task and not current_task.done():
                    current_task.cancel()
                
                # Start streaming response via LangGraph
                current_task = asyncio.create_task(
                    stream_agent_response(websocket, session, content)
                )
            
            elif msg_type == "clear":
                if session_id and session_id in sessions:
                    sessions[session_id].messages = []
                    await websocket.send_json({"type": "cleared"})
            
            elif msg_type == "end":
                break
    
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: session={session_id}")
    except Exception as e:
        logger.error(f"WebSocket error in session {session_id}: {e}", exc_info=True)
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass
    finally:
        if current_task and not current_task.done():
            current_task.cancel()


async def stream_agent_response(websocket: WebSocket, session: ConversationSession, user_input: str):
    """Stream response from LangGraph agent."""
    try:
        logger.info(f"Streaming agent response for: {user_input[:50]}...")
        await websocket.send_json({"type": "text_start"})
        
        # Prepare graph inputs
        lc_messages = session.get_langchain_messages()
        inputs = {
            "messages": lc_messages,
            "system_prompt": JARVIS_VOICE_PERSONA
        }
        
        full_response = ""
        sentence_buffer = ""
        
        # Stream events from the graph
        async for event in agent_graph.astream_events(inputs, version="v1"):
            kind = event["event"]
            
            # 1. Handle Chat Model Streaming (Tokens)
            if kind == "on_chat_model_stream":
                content = event["data"]["chunk"].content
                if content and isinstance(content, str):
                    full_response += content
                    sentence_buffer += content
                    
                    # Send chunks
                    await websocket.send_json({
                        "type": "text_delta",
                        "content": content
                    })
                    
                    # Sentence detection for TTS pacing
                    if any(sentence_buffer.rstrip().endswith(p) for p in ['.', '?', '!', ';"']):
                        await websocket.send_json({
                            "type": "sentence_end",
                            "sentence": sentence_buffer.strip()
                        })
                        sentence_buffer = ""
                        # Yield to event loop to allow interrupts
                        await asyncio.sleep(0.01)

            # 2. Handle Tool execution start (UI Feedback)
            elif kind == "on_tool_start":
                tool_name = event["name"]
                logger.info(f"Agent using tool: {tool_name}")
                await websocket.send_json({
                    "type": "tool_start",
                    "tool": tool_name
                })
            
            # 3. Handle Tool output
            elif kind == "on_tool_end":
                logger.info(f"Tool {event['name']} finished")

        # Flush remaining buffer
        if sentence_buffer.strip():
            await websocket.send_json({
                "type": "sentence_end",
                "sentence": sentence_buffer.strip()
            })
            
        # Update session history
        if full_response:
            session.add_message("assistant", full_response)
            logger.info(f"Agent response complete: {full_response[:100]}...")
            
            await websocket.send_json({
                "type": "text_done",
                "full_text": full_response
            })
        else:
            # Fallback if no response generated (rare)
            await websocket.send_json({
                "type": "text_done",
                "full_text": "I'm listening."
            })

    except asyncio.CancelledError:
        logger.info("Agent streaming cancelled")
        raise
    except Exception as e:
        logger.error(f"Error in agent stream: {e}", exc_info=True)
        await websocket.send_json({
            "type": "error",
            "message": f"I encountered an error: {str(e)}"
        })


@router.get("/conversation/sessions")
async def list_sessions():
    return {
        "sessions": [
            {
                "session_id": s.session_id,
                "message_count": len(s.messages),
                "last_activity": s.last_activity.isoformat()
            }
            for s in sessions.values()
        ]
    }


@router.delete("/conversation/session/{session_id}")
async def delete_session(session_id: str):
    if session_id in sessions:
        del sessions[session_id]
        return {"status": "deleted"}
    return {"status": "not_found"}
