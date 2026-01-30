"""
Jarvis Conversation WebSocket endpoint for low-latency conversational AI.

Supports:
- Real-time voice conversation with streaming
- Unified event schema matching chat routes
- Interruption handling
- Session management
"""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
from agents.graph import agent_graph, get_agent_config
from agents.state import JarvisState, create_initial_state
from core.logger import setup_logger
import json
import asyncio
from typing import Optional, Dict, Any, List
from datetime import datetime
import uuid

router = APIRouter()
logger = setup_logger(__name__)


# Voice-optimized persona - casual, concise for TTS
JARVIS_VOICE_PERSONA = """You are Jarvis, a chill AI assistant with full macOS control.

PERSONALITY:
- Casual, friendly, like talking to a smart friend
- Keep it SHORT - 1-2 sentences max (this will be spoken aloud)
- Use natural speech: "Yeah", "Got it", "Sure thing", "No problem", "Alright"
- NO formal language - avoid "sir", "certainly", "indeed", "I shall"
- Be helpful without being stiff or robotic

SPEECH RULES (CRITICAL):
- No formatting, lists, bullets, markdown - plain spoken text only
- Use contractions: "I'll", "you're", "that's", "can't", "won't"
- Sound human and relaxed
- Never say "As an AI" or similar meta-commentary

RESPONSE EXAMPLES:
"Open Safari" → "Opening Safari."
"Play music on Spotify" → "Playing Spotify."
"What time is it?" → "It's 3:30."
"How are you?" → "I'm good! What's up?"
"Search for AI news" → "Searching for AI news now."
"""


class ConversationSession:
    """Manages a single conversation session with memory."""
    
    def __init__(self, session_id: str, conversation_id: Optional[str] = None):
        self.session_id = session_id
        self.conversation_id = conversation_id or str(uuid.uuid4())
        self.messages: List[Dict[str, str]] = []
        self.created_at = datetime.now()
        self.last_activity = datetime.now()
        self.mode = "fast"  # Voice uses fast mode by default
        self.intent_history: List[str] = []
    
    def add_message(self, role: str, content: str):
        """Add a message to session history."""
        self.messages.append({"role": role, "content": content})
        self.last_activity = datetime.now()
        
        # Keep context manageable (last 20 messages)
        if len(self.messages) > 20:
            self.messages = self.messages[-20:]
    
    def get_langchain_messages(self) -> List[Any]:
        """Convert session history to LangChain message format."""
        lc_messages = []
        for msg in self.messages:
            if msg["role"] == "user":
                lc_messages.append(HumanMessage(content=msg["content"]))
            elif msg["role"] == "assistant":
                lc_messages.append(AIMessage(content=msg["content"]))
            elif msg["role"] == "system":
                lc_messages.append(SystemMessage(content=msg["content"]))
        return lc_messages
    
    def to_dict(self) -> Dict[str, Any]:
        """Serialize session for API response."""
        return {
            "session_id": self.session_id,
            "conversation_id": self.conversation_id,
            "message_count": len(self.messages),
            "created_at": self.created_at.isoformat(),
            "last_activity": self.last_activity.isoformat(),
            "mode": self.mode
        }


# Active sessions store
sessions: Dict[str, ConversationSession] = {}


@router.websocket("/ws/conversation")
async def conversation_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for real-time voice conversation.
    
    Message Types (Client → Server):
    - text: {"type": "text", "content": "...", "session_id": "..."}
    - audio: {"type": "audio", "data": "<base64>"}  # Future: direct audio
    - transcript: {"type": "transcript", "text": "...", "is_final": true}
    - interrupt: {"type": "interrupt"}
    - ping: {"type": "ping"}
    - clear: {"type": "clear"}
    - end: {"type": "end"}
    
    Message Types (Server → Client):
    - text_start: Start of response
    - text_delta: Streaming text chunk
    - sentence_end: Sentence boundary for TTS
    - text_done: Full response complete
    - tool_start: Tool execution started
    - tool_end: Tool execution finished
    - intent: Classified intent
    - error: Error message
    - interrupted: Interrupt acknowledged
    - pong: Ping response
    """
    await websocket.accept()
    session_id: Optional[str] = None
    current_task: Optional[asyncio.Task] = None
    
    logger.info("New conversation WebSocket connection established")
    
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_text()
            message = json.loads(data)
            msg_type = message.get("type", "text")
            
            # Handle interrupt - cancel current generation
            if msg_type == "interrupt":
                if current_task and not current_task.done():
                    logger.info("Interrupting current task")
                    current_task.cancel()
                    try:
                        await current_task
                    except asyncio.CancelledError:
                        pass
                    await websocket.send_json({
                        "type": "interrupted",
                        "message": "Response cancelled"
                    })
                continue
            
            # Handle ping/pong for connection keepalive
            if msg_type == "ping":
                await websocket.send_json({"type": "pong", "timestamp": datetime.now().isoformat()})
                continue
            
            # Handle text input (can be from STT or direct typing)
            if msg_type in ["text", "transcript"]:
                content = message.get("content") or message.get("text", "")
                content = content.strip()
                
                if not content:
                    continue
                
                # Get or create session
                session_id = message.get("session_id", session_id or str(uuid.uuid4()))
                if session_id not in sessions:
                    sessions[session_id] = ConversationSession(
                        session_id=session_id,
                        conversation_id=message.get("conversation_id")
                    )
                
                session = sessions[session_id]
                
                # Import chat history if provided (e.g., from focus mode)
                chat_history = message.get("chat_history", [])
                if chat_history and not session.messages:
                    for hist_msg in chat_history:
                        session.add_message(
                            hist_msg.get("role", "user"),
                            hist_msg.get("content", "")
                        )
                
                # Add user message
                session.add_message("user", content)
                logger.info(f"Received: {content[:50]}...")
                
                # Cancel any existing generation task
                if current_task and not current_task.done():
                    current_task.cancel()
                    try:
                        await current_task
                    except asyncio.CancelledError:
                        pass
                
                # Start streaming response
                current_task = asyncio.create_task(
                    stream_agent_response(websocket, session, content)
                )
            
            # Handle session clear
            elif msg_type == "clear":
                if session_id and session_id in sessions:
                    sessions[session_id].messages = []
                    await websocket.send_json({
                        "type": "cleared",
                        "session_id": session_id
                    })
            
            # Handle session end
            elif msg_type == "end":
                logger.info(f"Client requested session end: {session_id}")
                break
    
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: session={session_id}")
    except Exception as e:
        logger.error(f"WebSocket error in session {session_id}: {e}", exc_info=True)
        try:
            await websocket.send_json({
                "type": "error",
                "error": str(e),
                "recoverable": True
            })
        except Exception:
            pass
    finally:
        if current_task and not current_task.done():
            current_task.cancel()


async def stream_agent_response(
    websocket: WebSocket,
    session: ConversationSession,
    user_input: str
):
    """
    Stream response from LangGraph agent with unified event schema.
    Optimized for voice: short responses, sentence-by-sentence streaming.
    """
    try:
        logger.info(f"Streaming agent response for: {user_input[:50]}...")
        
        # Signal start of response
        await websocket.send_json({
            "type": "text_start",
            "conversation_id": session.conversation_id
        })
        
        # Prepare agent state
        lc_messages = session.get_langchain_messages()
        
        # Add voice persona as system message
        system_msg = SystemMessage(content=JARVIS_VOICE_PERSONA)
        all_messages = [system_msg] + lc_messages
        
        # Create initial state with fast mode for voice
        initial_state = create_initial_state(
            conversation_id=session.conversation_id,
            messages=all_messages,
            mode="fast",  # Voice uses fast mode
            is_voice=True
        )
        
        # Tracking variables
        full_response = ""
        sentence_buffer = ""
        sentence_index = 0
        tool_count = 0
        intent_sent = False
        
        # Get agent config
        agent_config = get_agent_config()
        run_config = {"recursion_limit": agent_config["recursion_limit"]}
        
        # Stream events from the graph
        async for event in agent_graph.astream_events(initial_state, version="v2", config=run_config):
            event_kind = event.get("event", "")
            event_name = event.get("name", "")
            
            # Handle intent classification
            if event_kind == "on_chain_end" and event_name == "classify":
                output = event.get("data", {}).get("output", {})
                if output.get("intent") and not intent_sent:
                    await websocket.send_json({
                        "type": "intent",
                        "intent": output.get("intent"),
                        "confidence": output.get("intent_confidence", 0.5)
                    })
                    intent_sent = True
            
            # Handle streaming text from model
            if event_kind == "on_chat_model_stream":
                chunk = event.get("data", {}).get("chunk")
                if chunk and hasattr(chunk, "content") and chunk.content:
                    content = chunk.content
                    if isinstance(content, str):
                        full_response += content
                        sentence_buffer += content
                        
                        # Send delta
                        await websocket.send_json({
                            "type": "text_delta",
                            "content": content
                        })
                        
                        # Check for sentence boundaries for TTS pacing
                        sentence_endings = ['. ', '! ', '? ', '."', '!"', '?"', '.\n', '!\n', '?\n']
                        for ending in sentence_endings:
                            if ending in sentence_buffer:
                                parts = sentence_buffer.split(ending, 1)
                                complete_sentence = parts[0] + ending.strip()
                                
                                await websocket.send_json({
                                    "type": "sentence_end",
                                    "sentence": complete_sentence.strip(),
                                    "sentence_index": sentence_index
                                })
                                sentence_index += 1
                                sentence_buffer = parts[1] if len(parts) > 1 else ""
                                
                                # Small yield for interruption handling
                                await asyncio.sleep(0.01)
                                break
            
            # Handle tool execution
            elif event_kind == "on_tool_start":
                tool_name = event.get("name", "unknown")
                tool_input = event.get("data", {}).get("input", {})
                tool_count += 1
                
                logger.info(f"Agent using tool: {tool_name}")
                await websocket.send_json({
                    "type": "tool_start",
                    "tool_name": tool_name,
                    "tool_args": tool_input if isinstance(tool_input, dict) else {}
                })
            
            elif event_kind == "on_tool_end":
                tool_name = event.get("name", "unknown")
                tool_output = event.get("data", {}).get("output", "")
                
                await websocket.send_json({
                    "type": "tool_end",
                    "tool_name": tool_name,
                    "success": "error" not in str(tool_output).lower()
                })
        
        # Flush remaining sentence buffer
        if sentence_buffer.strip():
            await websocket.send_json({
                "type": "sentence_end",
                "sentence": sentence_buffer.strip(),
                "sentence_index": sentence_index
            })
        
        # Update session with assistant response
        if full_response:
            session.add_message("assistant", full_response)
            logger.info(f"Agent response complete: {full_response[:100]}...")
        
        # Send completion event
        await websocket.send_json({
            "type": "text_done",
            "full_text": full_response or "I'm listening.",
            "conversation_id": session.conversation_id,
            "tool_count": tool_count
        })
    
    except asyncio.CancelledError:
        logger.info("Agent streaming cancelled (interrupted)")
        raise
    except Exception as e:
        logger.error(f"Error in agent stream: {e}", exc_info=True)
        await websocket.send_json({
            "type": "error",
            "error": f"I encountered an error: {str(e)}",
            "recoverable": True
        })


# ============== REST API for Session Management ==============

@router.get("/conversation/sessions")
async def list_sessions():
    """List all active conversation sessions."""
    return {
        "sessions": [session.to_dict() for session in sessions.values()],
        "total": len(sessions)
    }


@router.get("/conversation/session/{session_id}")
async def get_session(session_id: str):
    """Get details of a specific session."""
    if session_id not in sessions:
        return {"error": "Session not found", "session_id": session_id}
    
    session = sessions[session_id]
    return {
        **session.to_dict(),
        "messages": session.messages
    }


@router.delete("/conversation/session/{session_id}")
async def delete_session(session_id: str):
    """Delete a conversation session."""
    if session_id in sessions:
        del sessions[session_id]
        return {"status": "deleted", "session_id": session_id}
    return {"status": "not_found", "session_id": session_id}


@router.post("/conversation/session/{session_id}/clear")
async def clear_session(session_id: str):
    """Clear messages in a session without deleting it."""
    if session_id in sessions:
        sessions[session_id].messages = []
        return {"status": "cleared", "session_id": session_id}
    return {"status": "not_found", "session_id": session_id}
