"""
TEN Agent WebSocket endpoint for low-latency conversational AI.
Handles text-in/text-out with streaming responses optimized for voice.
Now integrated with LangGraph agent for tool support (AppleScript, Mac control, etc.)
"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from openai import AsyncOpenAI
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
from agents.tools import get_tools
from core.config import settings
from core.logger import setup_logger
import json
import asyncio
from typing import Optional
from datetime import datetime

router = APIRouter()
logger = setup_logger(__name__)

# Initialize OpenAI client for direct streaming
client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

# Initialize LangChain LLM with tools for Mac automation
llm_kwargs = {
    "model": settings.OPENAI_MODEL,
    "api_key": settings.OPENAI_API_KEY,
    "streaming": True
}
if not settings.OPENAI_MODEL.startswith("gpt-5"):
    llm_kwargs["temperature"] = 0.7

llm = ChatOpenAI(**llm_kwargs)
tools = get_tools()
llm_with_tools = llm.bind_tools(tools)

# In-memory session storage (in production, use Redis or database)
sessions = {}

# Jarvis system prompt - casual, human-like with Mac control
JARVIS_SYSTEM_PROMPT = """You are Jarvis, a chill AI assistant with full macOS control.

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

MAC CONTROL - You can control this Mac:
- Apps: "Open Safari" → use run_mac_script with app_open
- Music: "Play music" → use run_mac_script with music_play
- Volume: "Turn it up" → use run_mac_script with system_set_volume
- Browser: "Open google" → use run_mac_script with safari_open_url

After actions, respond casually: "Done.", "Got it.", "Safari's open.", "Playing now."

EXAMPLES:
"Open Safari" → "Opening Safari." (use tool)
"Play some music" → "Playing now." (use tool)
"What time is it?" → "It's 3:30."
"How are you?" → "I'm good! What's up?"
"Thanks" → "No problem!" or "You got it."

Be natural, brief, and helpful. No robotic or formal responses."""


class ConversationSession:
    """Manages a single conversation session."""
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.messages = []
        self.created_at = datetime.now()
        self.last_activity = datetime.now()
        self.is_active = True
    
    def add_message(self, role: str, content: str):
        self.messages.append({"role": role, "content": content})
        self.last_activity = datetime.now()
        # Keep only last 10 messages for context (memory efficient)
        if len(self.messages) > 10:
            self.messages = self.messages[-10:]
    
    def get_messages_for_api(self):
        return [{"role": "system", "content": JARVIS_SYSTEM_PROMPT}] + self.messages


# Active sessions
sessions: dict[str, ConversationSession] = {}


@router.websocket("/ws/conversation")
async def conversation_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for real-time conversation.
    
    Protocol:
    - Client sends: {"type": "text", "content": "user message", "session_id": "optional"}
    - Client sends: {"type": "interrupt"} to stop current response
    - Server sends: {"type": "text_start"}
    - Server sends: {"type": "text_delta", "content": "chunk"}
    - Server sends: {"type": "text_done", "full_text": "complete response"}
    - Server sends: {"type": "error", "message": "error details"}
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
                    # Add chat history context to session (only on first message)
                    for hist_msg in chat_history:
                        role = hist_msg.get("role", "user")
                        hist_content = hist_msg.get("content", "")
                        if hist_content:
                            session.add_message(role, hist_content)
                    logger.info(f"Imported {len(chat_history)} messages from chat history")
                
                session.add_message("user", content)
                
                # Cancel any existing task
                if current_task and not current_task.done():
                    current_task.cancel()
                
                # Start streaming response
                current_task = asyncio.create_task(
                    stream_response(websocket, session, content)
                )
            
            elif msg_type == "clear":
                # Clear conversation history
                if session_id and session_id in sessions:
                    sessions[session_id].messages = []
                    await websocket.send_json({"type": "cleared"})
            
            elif msg_type == "end":
                # End session
                break
    
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: session={session_id}")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except:
            pass
    finally:
        if current_task and not current_task.done():
            current_task.cancel()


async def stream_response(websocket: WebSocket, session: ConversationSession, user_input: str):
    """Stream response chunks to the client for low-latency TTS with tool support."""
    try:
        logger.info(f"Starting stream response for input: {user_input[:50]}...")
        
        # Signal start
        await websocket.send_json({"type": "text_start"})
        
        # Build LangChain messages
        lc_messages = [SystemMessage(content=JARVIS_SYSTEM_PROMPT)]
        for msg in session.messages:
            if msg["role"] == "user":
                lc_messages.append(HumanMessage(content=msg["content"]))
            elif msg["role"] == "assistant":
                lc_messages.append(AIMessage(content=msg["content"]))
        
        logger.info(f"Messages for LLM: {len(lc_messages)} messages")
        
        full_response = ""
        sentence_buffer = ""
        tool_results = []
        
        # First, check if the LLM wants to use tools
        try:
            response = await llm_with_tools.ainvoke(lc_messages)
            logger.info(f"LLM response received, has tool_calls: {bool(response.tool_calls)}")
            
            # Handle tool calls if any
            if response.tool_calls:
                await websocket.send_json({"type": "tool_start"})
                
                for tool_call in response.tool_calls:
                    tool_name = tool_call['name']
                    tool_args = tool_call.get('args', {})
                    logger.info(f"Executing tool: {tool_name} with args: {tool_args}")
                    
                    # Find and execute the tool
                    tool_result = "Tool not found"
                    for tool in tools:
                        if tool.name == tool_name:
                            try:
                                tool_result = await tool.ainvoke(tool_args)
                            except Exception as te:
                                tool_result = f"Tool error: {str(te)}"
                            break
                    
                    tool_results.append({"tool": tool_name, "result": tool_result})
                    logger.info(f"Tool result: {tool_result[:100]}...")
                
                # Get final response after tool execution
                lc_messages.append(response)
                for tr in tool_results:
                    from langchain_core.messages import ToolMessage
                    lc_messages.append(ToolMessage(content=str(tr["result"]), tool_call_id=response.tool_calls[0]['id']))
                
                final_response = await llm_with_tools.ainvoke(lc_messages)
                full_response = final_response.content if final_response.content else "Done, sir."
            else:
                # No tools needed, use the response directly
                full_response = response.content if response.content else ""
            
        except Exception as e:
            logger.error(f"LLM error: {e}")
            await websocket.send_json({
                "type": "error",
                "message": f"AI error: {str(e)}"
            })
            return
        
        # Stream the response to client
        if full_response:
            # Send word by word for streaming effect
            words = full_response.split()
            for i, word in enumerate(words):
                text = word + (" " if i < len(words) - 1 else "")
                sentence_buffer += text
                
                await websocket.send_json({
                    "type": "text_delta",
                    "content": text
                })
                
                # Send sentence-complete signals for TTS pacing
                if any(sentence_buffer.rstrip().endswith(p) for p in ['.', '?', '!', ';"']):
                    await websocket.send_json({
                        "type": "sentence_end",
                        "sentence": sentence_buffer.strip()
                    })
                    sentence_buffer = ""
                
                await asyncio.sleep(0.02)  # Small delay for streaming effect
        
        logger.info(f"Response complete: {full_response}")
        
        # Send any remaining buffer
        if sentence_buffer.strip():
            await websocket.send_json({
                "type": "sentence_end",
                "sentence": sentence_buffer.strip()
            })
        
        # Add to conversation history
        session.add_message("assistant", full_response)
        
        # Signal completion
        await websocket.send_json({
            "type": "text_done",
            "full_text": full_response,
            "tools_used": [tr["tool"] for tr in tool_results] if tool_results else []
        })
        
    except asyncio.CancelledError:
        logger.info("Response generation cancelled (interrupted)")
        raise
    except Exception as e:
        logger.error(f"Error streaming response: {e}")
        await websocket.send_json({
            "type": "error",
            "message": f"Error generating response: {str(e)}"
        })


@router.get("/conversation/sessions")
async def list_sessions():
    """List active conversation sessions."""
    return {
        "sessions": [
            {
                "session_id": s.session_id,
                "message_count": len(s.messages),
                "created_at": s.created_at.isoformat(),
                "last_activity": s.last_activity.isoformat()
            }
            for s in sessions.values()
        ]
    }


@router.delete("/conversation/session/{session_id}")
async def delete_session(session_id: str):
    """Delete a conversation session."""
    if session_id in sessions:
        del sessions[session_id]
        return {"status": "deleted", "session_id": session_id}
    return {"status": "not_found", "session_id": session_id}
