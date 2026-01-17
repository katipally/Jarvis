from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from api.models import ChatRequest
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
from agents.graph import agent_graph, get_agent_config
from core.logger import setup_logger
from core.chroma_client import chroma_client
from core.rate_limiter import rate_limiter
from core.config import settings
import json
import asyncio

router = APIRouter()
logger = setup_logger(__name__)


@router.post("/chat/stream")
async def chat_stream(request: ChatRequest, http_request: Request):
    """Stream chat responses with reasoning."""
    
    # Rate limiting
    client_ip = http_request.client.host if http_request.client else "unknown"
    is_allowed, message = rate_limiter.is_allowed(client_ip)
    if not is_allowed:
        raise HTTPException(status_code=429, detail=message)
    
    async def event_generator():
        try:
            # Build full conversation history from request
            conversation_messages = []
            
            # Build context from attached files if any
            file_context = {}
            file_context_text = ""
            if request.file_ids:
                logger.info(f"Processing file_ids: {request.file_ids}")
                file_context = await chroma_client.get_documents_by_file_ids(request.file_ids)
                logger.info(f"Retrieved file_context: {bool(file_context)}, keys: {list(file_context.keys()) if file_context else []}")
                
                # Format file context for injection into system message
                if file_context:
                    file_context_text = "\n\n## IMPORTANT - Uploaded File Content:\n\n"
                    file_context_text += "The user has uploaded the following file(s). Use this content to answer their questions:\n\n"
                    for file_id, chunks in file_context.items():
                        if chunks:
                            file_name = chunks[0]["metadata"].get("file_name", "Unknown")
                            file_type = chunks[0]["metadata"].get("file_type", "Unknown")
                            file_context_text += f"### 📄 File: {file_name} (Type: {file_type})\n"
                            file_context_text += f"File ID: {file_id}\n\n"
                            full_content = ""
                            for i, chunk in enumerate(chunks[:10]):  # Up to 10 chunks
                                full_content += chunk['content'] + "\n\n"
                            file_context_text += f"**Content:**\n{full_content[:3000]}\n\n"
                        else:
                            file_context_text += f"### File ID: {file_id}\n(No content retrieved - file may still be processing)\n\n"
                else:
                    # File IDs provided but no content found
                    file_context_text = "\n\n## Note: File Upload\n\n"
                    file_context_text += f"The user uploaded file(s) with IDs: {', '.join(request.file_ids)}\n"
                    file_context_text += "However, the file content could not be retrieved. The file may still be processing.\n\n"
            
            # Add file context as system message if available
            if file_context_text:
                system_context = SystemMessage(
                    content=f"You have access to the following file context. Use this information to answer questions about these files.\n{file_context_text}"
                )
                conversation_messages.append(system_context)
            
            # Convert all conversation messages to LangChain format
            # This preserves the full conversation history including tool results
            for msg in request.messages:
                if msg.role == "user":
                    conversation_messages.append(HumanMessage(content=msg.content))
                elif msg.role == "assistant":
                    conversation_messages.append(AIMessage(content=msg.content))
            
            initial_state = {
                "messages": conversation_messages,
                "reasoning": [],
                "tool_calls": [],
                "file_context": file_context,
                "rag_results": [],
                "search_results": [],
                "next_action": ""
            }
            
            reasoning_items = []
            content_buffer = ""
            total_tokens = 0
            
            # Get agent config for recursion limit
            agent_config = get_agent_config()
            run_config = {"recursion_limit": agent_config["recursion_limit"]}
            
            async for msg, metadata in agent_graph.astream(initial_state, stream_mode="messages", config=run_config):
                # Process message chunks (tokens)
                if hasattr(msg, "content") and msg.content:
                    content = msg.content
                    content_buffer += content
                    yield f"data: {json.dumps({'type': 'content', 'content': content})}\n\n"
                    # Small yield to event loop
                    await asyncio.sleep(0.001)
                
                # Extract token usage if available (usually in final chunk)
                if hasattr(msg, "response_metadata"):
                    meta = msg.response_metadata
                    if "token_usage" in meta:
                        total_tokens = meta["token_usage"].get("total_tokens", 0)
                    elif "usage" in meta:
                        total_tokens = meta["usage"].get("total_tokens", 0)
                
                # Handle tool calls being generated
                if hasattr(msg, "tool_calls") and msg.tool_calls:
                    for tool_call in msg.tool_calls:
                        tool_name = tool_call.get('name', 'unknown')
                        tool_args = tool_call.get('args', {})
                        
                        # We only want to notify on the *final* tool call construction usually, 
                        # but streaming gives us partials. Ideally we detect when it's "done".
                        # For simple UI feedback, logging the tool name is often enough.
                        if tool_name and tool_name != "unknown":
                            # Avoid spamming tool events for every token of the tool args
                            # Simple heuristic: send if we haven't sent this tool usage yet
                            # (This is tricky with streaming, simplified here)
                            pass 
            
            # Estimate tokens if not available
            if total_tokens == 0:
                all_content = content_buffer + "".join([msg.content for msg in conversation_messages])
                total_tokens = len(all_content) // 4
            
            yield f"data: {json.dumps({'type': 'done', 'reasoning_count': len(reasoning_items), 'token_count': total_tokens})}\n\n"
        
        except Exception as e:
            logger.error(f"Error in chat stream: {str(e)}", exc_info=True)
            error_message = str(e)
            # Provide user-friendly error messages
            if "OpenAI" in error_message or "API" in error_message:
                error_message = "Unable to connect to AI service. Please check your API key and internet connection."
            elif "timeout" in error_message.lower():
                error_message = "Request timed out. Please try again."
            elif "rate limit" in error_message.lower():
                error_message = "Rate limit exceeded. Please wait a moment and try again."
            else:
                error_message = f"An error occurred: {error_message}"
            
            yield f"data: {json.dumps({'type': 'error', 'error': error_message})}\n\n"
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        }
    )


@router.post("/chat")
async def chat(request: ChatRequest):
    """Non-streaming chat endpoint."""
    try:
        # Get the last user message
        user_message = next((msg.content for msg in reversed(request.messages) if msg.role == "user"), "")
        
        # Build context from attached files if any
        file_context = {}
        file_context_text = ""
        if request.file_ids:
            file_context = await chroma_client.get_documents_by_file_ids(request.file_ids)
            
            # Format file context for injection into system message
            if file_context:
                file_context_text = "\n\n## Attached Files Context:\n\n"
                for file_id, chunks in file_context.items():
                    file_name = chunks[0]["metadata"].get("file_name", file_id) if chunks else file_id
                    file_context_text += f"### File: {file_name}\n"
                    for i, chunk in enumerate(chunks[:5]):  # Limit to first 5 chunks per file
                        file_context_text += f"\n**Chunk {i+1}:**\n{chunk['content'][:500]}\n"
                    file_context_text += "\n"
        
        # Build messages with file context if available
        messages = []
        if file_context_text:
            system_context = SystemMessage(
                content=f"You have access to the following file context. Use this information to answer questions about these files.\n{file_context_text}"
            )
            messages.append(system_context)
        
        messages.append(HumanMessage(content=user_message))
        
        initial_state = {
            "messages": messages,
            "reasoning": [],
            "tool_calls": [],
            "file_context": file_context,
            "rag_results": [],
            "search_results": [],
            "next_action": ""
        }
        
        result = await agent_graph.ainvoke(initial_state)
        
        response_message = result["messages"][-1].content
        
        return {
            "message": response_message,
            "reasoning": result.get("reasoning", []),
            "conversation_id": request.conversation_id or "default"
        }
    
    except Exception as e:
        logger.error(f"Error in chat: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
