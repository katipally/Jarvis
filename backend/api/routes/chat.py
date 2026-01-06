from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from api.models import ChatRequest
from langchain_core.messages import HumanMessage, SystemMessage
from agents.graph import agent_graph
from core.logger import setup_logger
from core.chroma_client import chroma_client
from core.rate_limiter import rate_limiter
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
            # Get the last user message
            user_message = next((msg.content for msg in reversed(request.messages) if msg.role == "user"), "")
            
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
            
            reasoning_items = []
            content_buffer = ""
            total_tokens = 0
            
            async for event in agent_graph.astream(initial_state, stream_mode="updates"):
                for node_name, node_output in event.items():
                    if "messages" in node_output:
                        for message in node_output["messages"]:
                            if hasattr(message, "content") and message.content:
                                content_buffer += message.content
                                yield f"data: {json.dumps({'type': 'content', 'content': message.content})}\n\n"
                                await asyncio.sleep(0.01)
                            
                            # Extract token usage if available
                            if hasattr(message, "response_metadata"):
                                metadata = message.response_metadata
                                if "token_usage" in metadata:
                                    total_tokens = metadata["token_usage"].get("total_tokens", 0)
                                elif "usage" in metadata:
                                    total_tokens = metadata["usage"].get("total_tokens", 0)
                            
                            if hasattr(message, "tool_calls") and message.tool_calls:
                                for tool_call in message.tool_calls:
                                    tool_name = tool_call['name']
                                    tool_args = tool_call.get('args', {})
                                    
                                    # Generate descriptive text for Mac automation tools
                                    if tool_name == "run_mac_script":
                                        script_id = tool_args.get('script_id', 'unknown')
                                        reasoning_text = f"🖥️ Running Mac script: {script_id}"
                                    elif tool_name == "execute_applescript":
                                        reasoning_text = "🖥️ Executing custom AppleScript"
                                    elif tool_name == "execute_shell_command":
                                        cmd = tool_args.get('command', '')[:50]
                                        reasoning_text = f"💻 Running shell command: {cmd}..."
                                    elif tool_name == "get_available_mac_scripts":
                                        reasoning_text = "📋 Getting available automation scripts"
                                    else:
                                        reasoning_text = f"Using tool: {tool_name}"
                                    
                                    reasoning_items.append(reasoning_text)
                                    yield f"data: {json.dumps({'type': 'reasoning', 'content': reasoning_text})}\n\n"
                                    yield f"data: {json.dumps({'type': 'tool', 'tool_name': tool_name, 'tool_args': tool_args})}\n\n"
                    
                    if node_name == "tools":
                        reasoning_items.append("Processing tool results...")
                        yield f"data: {json.dumps({'type': 'reasoning', 'content': 'Processing tool results...'})}\n\n"
            
            # Estimate tokens if not available (roughly 4 chars per token)
            if total_tokens == 0:
                total_tokens = (len(content_buffer) + len(user_message)) // 4
            
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
