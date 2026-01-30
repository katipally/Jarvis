"""
Jarvis Chat API Routes

Unified streaming endpoints with:
- Plan events and step updates
- Intent classification events
- Tool execution events
- Reasoning/thinking events
"""

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from api.models import (
    ChatRequest, ChatResponse, AgentMode, TokenUsage,
    PlanStep, PlanStepStatus, StreamEventType
)
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage, ToolMessage
from agents.graph import agent_graph, get_agent_config
from agents.state import JarvisState, create_initial_state
from core.logger import setup_logger
from core.chroma_client import chroma_client
from core.rate_limiter import rate_limiter
from core.config import settings
import json
import asyncio
import uuid
from datetime import datetime

router = APIRouter()
logger = setup_logger(__name__)


def make_sse_event(event_type: str, data: dict) -> str:
    """Format a Server-Sent Event."""
    return f"event: {event_type}\ndata: {json.dumps(data)}\n\n"


def make_data_event(data: dict) -> str:
    """Format a simple data event (legacy format)."""
    return f"data: {json.dumps(data)}\n\n"


@router.post("/chat/stream")
async def chat_stream(request: ChatRequest, http_request: Request):
    """
    Stream chat responses with unified event schema.
    
    Event Types:
    - intent: Intent classification result
    - mode: Mode selection
    - plan: Full plan with steps
    - plan_step_update: Step status changes
    - tool: Tool call information
    - tool_result: Tool execution result
    - reasoning: Reasoning/thinking step
    - content: Response text content
    - error: Error messages
    - done: Stream completion with stats
    """
    
    # Rate limiting
    client_ip = http_request.client.host if http_request.client else "unknown"
    is_allowed, message = rate_limiter.is_allowed(client_ip)
    if not is_allowed:
        raise HTTPException(status_code=429, detail=message)
    
    async def event_generator():
        try:
            conversation_id = request.conversation_id or str(uuid.uuid4())
            mode = request.mode or AgentMode.REASONING
            
            # Build conversation history
            conversation_messages = []
            
            # Process file context if provided
            file_context = {}
            file_context_text = ""
            
            if request.file_ids:
                logger.info(f"Processing file_ids: {request.file_ids}")
                file_context = await chroma_client.get_documents_by_file_ids(request.file_ids)
                
                if file_context:
                    file_context_text = "\n\n## Uploaded File Content:\n\n"
                    for file_id, chunks in file_context.items():
                        if chunks:
                            file_name = chunks[0]["metadata"].get("file_name", "Unknown")
                            file_type = chunks[0]["metadata"].get("file_type", "Unknown")
                            file_context_text += f"### 📄 File: {file_name} (Type: {file_type})\n"
                            full_content = ""
                            for chunk in chunks[:10]:
                                full_content += chunk['content'] + "\n\n"
                            file_context_text += f"**Content:**\n{full_content[:3000]}\n\n"
                    
                    # Add file context as system message
                    conversation_messages.append(SystemMessage(
                        content=f"You have access to the following uploaded files:\n{file_context_text}"
                    ))
            
            # Convert messages to LangChain format
            for msg in request.messages:
                if msg.role == "user":
                    conversation_messages.append(HumanMessage(content=msg.content))
                elif msg.role == "assistant":
                    conversation_messages.append(AIMessage(content=msg.content))
                elif msg.role == "system":
                    conversation_messages.append(SystemMessage(content=msg.content))
            
            # Create initial state
            initial_state: JarvisState = create_initial_state(
                conversation_id=conversation_id,
                messages=conversation_messages,
                mode=mode.value if isinstance(mode, AgentMode) else mode,
                file_context=file_context
            )
            
            # Send mode event
            yield make_data_event({
                "type": "mode",
                "mode": mode.value if isinstance(mode, AgentMode) else mode,
            })
            
            # Tracking variables
            plan_sent = False
            step_statuses = {}  # Track step status to avoid duplicate events
            tool_calls_count = 0
            reasoning_items = []
            content_buffer = ""
            total_tokens = 0
            intent_sent = False
            
            # Get agent config for limits
            agent_config = get_agent_config()
            run_config = {"recursion_limit": agent_config["recursion_limit"]}
            
            # Stream agent execution
            async for event in agent_graph.astream(initial_state, stream_mode="updates", config=run_config):
                for node_name, node_output in event.items():
                    
                    # Handle intent classification
                    if node_name == "classify":
                        intent = node_output.get("intent", "unknown")
                        confidence = node_output.get("intent_confidence", 0.5)
                        
                        if not intent_sent:
                            yield make_data_event({
                                "type": "intent",
                                "intent": intent,
                                "confidence": confidence
                            })
                            intent_sent = True
                        
                        # Add to reasoning
                        if node_output.get("reasoning"):
                            for r in node_output["reasoning"]:
                                reasoning_items.append(r)
                                if request.include_reasoning:
                                    yield make_data_event({
                                        "type": "reasoning",
                                        "content": r
                                    })
                    
                    # Handle plan creation
                    if node_name == "plan":
                        plan = node_output.get("plan", [])
                        plan_summary = node_output.get("plan_summary", "")
                        
                        if plan and not plan_sent and request.include_plan:
                            # Convert to response format
                            plan_steps = []
                            for step in plan:
                                plan_steps.append({
                                    "id": step.get("id", ""),
                                    "description": step.get("description", ""),
                                    "status": step.get("status", "pending"),
                                    "tool_name": step.get("tool_name"),
                                })
                                step_statuses[step.get("id", "")] = step.get("status", "pending")
                            
                            yield make_data_event({
                                "type": "plan",
                                "steps": plan_steps,
                                "summary": plan_summary,
                                "status": "started"
                            })
                            plan_sent = True
                        
                        # Add to reasoning
                        if node_output.get("reasoning"):
                            for r in node_output["reasoning"]:
                                if r not in reasoning_items:
                                    reasoning_items.append(r)
                                    if request.include_reasoning:
                                        yield make_data_event({
                                            "type": "reasoning",
                                            "content": r
                                        })
                    
                    # Handle execution/response
                    if node_name in ["execute", "respond"] and "messages" in node_output:
                        for message in node_output["messages"]:
                            # Handle content streaming
                            if hasattr(message, "content") and message.content:
                                content_buffer += message.content
                                yield make_data_event({
                                    "type": "content",
                                    "text": message.content,
                                    "is_complete": False
                                })
                                await asyncio.sleep(0.01)
                            
                            # Extract token usage
                            if hasattr(message, "response_metadata"):
                                metadata = message.response_metadata
                                if "token_usage" in metadata:
                                    total_tokens = metadata["token_usage"].get("total_tokens", 0)
                                elif "usage" in metadata:
                                    total_tokens = metadata["usage"].get("total_tokens", 0)
                            
                            # Handle tool calls
                            if hasattr(message, "tool_calls") and message.tool_calls:
                                for tool_call in message.tool_calls:
                                    tool_name = tool_call.get('name', 'unknown')
                                    tool_args = tool_call.get('args', {})
                                    tool_call_id = tool_call.get('id', '')
                                    
                                    tool_calls_count += 1
                                    
                                    # Generate reasoning text
                                    reasoning_text = _generate_tool_reasoning(tool_name, tool_args)
                                    reasoning_items.append(reasoning_text)
                                    
                                    if request.include_reasoning:
                                        yield make_data_event({
                                            "type": "reasoning",
                                            "content": reasoning_text
                                        })
                                    
                                    # Send tool event
                                    yield make_data_event({
                                        "type": "tool",
                                        "tool_name": tool_name,
                                        "tool_args": tool_args,
                                        "tool_call_id": tool_call_id
                                    })
                    
                    # Handle plan updates
                    if "plan" in node_output:
                        plan = node_output.get("plan", [])
                        for step in plan:
                            step_id = step.get("id", "")
                            current_status = step.get("status", "pending")
                            
                            # Only send update if status changed
                            if step_id and step_statuses.get(step_id) != current_status:
                                step_statuses[step_id] = current_status
                                
                                yield make_data_event({
                                    "type": "plan_step_update",
                                    "step_id": step_id,
                                    "status": current_status,
                                    "result": step.get("result"),
                                    "error": step.get("error")
                                })
                    
                    # Handle tool results
                    if node_name == "tools":
                        if request.include_reasoning:
                            yield make_data_event({
                                "type": "reasoning",
                                "content": "Processing tool results..."
                            })
                        reasoning_items.append("Processing tool results...")
            
            # Send completion event
            if total_tokens == 0:
                # Estimate tokens if not available
                all_content = content_buffer + "".join([msg.content for msg in conversation_messages if hasattr(msg, 'content')])
                total_tokens = len(all_content) // 4
            
            # Mark all plan steps as completed
            if plan_sent:
                for step_id, status in step_statuses.items():
                    if status == "running":
                        yield make_data_event({
                            "type": "plan_step_update",
                            "step_id": step_id,
                            "status": "completed"
                        })
            
            yield make_data_event({
                "type": "done",
                "conversation_id": conversation_id,
                "tokens": {
                    "prompt": 0,
                    "completion": 0,
                    "total": total_tokens
                },
                "reasoning_count": len(reasoning_items),
                "tool_count": tool_calls_count
            })
            
        except Exception as e:
            logger.error(f"Error in chat stream: {str(e)}", exc_info=True)
            error_message = _format_error_message(str(e))
            yield make_data_event({
                "type": "error",
                "error": error_message,
                "recoverable": True
            })
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        }
    )


@router.post("/chat")
async def chat(request: ChatRequest, http_request: Request) -> ChatResponse:
    """
    Non-streaming chat endpoint.
    
    Returns complete response with optional reasoning and plan.
    """
    
    # Rate limiting
    client_ip = http_request.client.host if http_request.client else "unknown"
    is_allowed, message = rate_limiter.is_allowed(client_ip)
    if not is_allowed:
        raise HTTPException(status_code=429, detail=message)
    
    try:
        conversation_id = request.conversation_id or str(uuid.uuid4())
        mode = request.mode or AgentMode.REASONING
        
        # Build conversation history
        conversation_messages = []
        
        # Process file context
        file_context = {}
        if request.file_ids:
            file_context = await chroma_client.get_documents_by_file_ids(request.file_ids)
            if file_context:
                file_context_text = "\n\n## Uploaded Files:\n\n"
                for file_id, chunks in file_context.items():
                    if chunks:
                        file_name = chunks[0]["metadata"].get("file_name", file_id)
                        file_context_text += f"### File: {file_name}\n"
                        for chunk in chunks[:5]:
                            file_context_text += f"{chunk['content'][:500]}\n"
                
                conversation_messages.append(SystemMessage(content=file_context_text))
        
        # Convert messages
        for msg in request.messages:
            if msg.role == "user":
                conversation_messages.append(HumanMessage(content=msg.content))
            elif msg.role == "assistant":
                conversation_messages.append(AIMessage(content=msg.content))
        
        # Create initial state
        initial_state = create_initial_state(
            conversation_id=conversation_id,
            messages=conversation_messages,
            mode=mode.value if isinstance(mode, AgentMode) else mode,
            file_context=file_context
        )
        
        # Run agent
        agent_config = get_agent_config()
        run_config = {"recursion_limit": agent_config["recursion_limit"]}
        
        result = await agent_graph.ainvoke(initial_state, config=run_config)
        
        # Extract response
        response_content = ""
        if result.get("messages"):
            last_message = result["messages"][-1]
            if hasattr(last_message, "content"):
                response_content = last_message.content
        
        # Build plan if available
        plan_steps = None
        if result.get("plan") and request.include_plan:
            plan_steps = [
                PlanStep(
                    id=step.get("id", ""),
                    description=step.get("description", ""),
                    status=PlanStepStatus(step.get("status", "completed")),
                    tool_name=step.get("tool_name"),
                    result=step.get("result")
                )
                for step in result["plan"]
            ]
        
        return ChatResponse(
            message=response_content,
            conversation_id=conversation_id,
            reasoning=result.get("reasoning") if request.include_reasoning else None,
            plan=plan_steps,
            intent=result.get("intent"),
            mode=mode,
            tokens=TokenUsage(total=result.get("tool_call_count", 0) * 100)  # Rough estimate
        )
        
    except Exception as e:
        logger.error(f"Error in chat: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


def _generate_tool_reasoning(tool_name: str, tool_args: dict) -> str:
    """Generate human-readable reasoning text for a tool call."""
    reasoning_templates = {
        "run_mac_script": "🖥️ Running Mac script: {script_id}",
        "execute_applescript": "🖥️ Executing custom AppleScript",
        "execute_shell_command": "💻 Running shell command: {command}",
        "launch_app": "🚀 Launching {app_name}",
        "quit_app": "❌ Quitting {app_name}",
        "browser_navigate_to_url": "🌐 Navigating to {url}",
        "web_search": "🔍 Searching web for: {query}",
        "search_knowledge_base": "📚 Searching knowledge base: {query}",
        "type_text": "⌨️ Typing text",
        "press_keyboard_shortcut": "⌨️ Pressing {key} with {modifiers}",
        "web_page_click_element": "🖱️ Clicking: {element_text}",
        "web_page_fill_input": "✏️ Filling input field",
        "get_running_apps": "📋 Getting running applications",
        "get_frontmost_app": "👁️ Checking frontmost app",
        "get_system_state": "📊 Getting system state",
        "capture_screen_for_analysis": "📸 Capturing screen",
    }
    
    template = reasoning_templates.get(tool_name, f"Using tool: {tool_name}")
    
    try:
        # Format with available args
        return template.format(**{k: str(v)[:50] for k, v in tool_args.items()})
    except (KeyError, ValueError):
        return template


def _format_error_message(error: str) -> str:
    """Format error message for user display."""
    if "OpenAI" in error or "API" in error:
        return "Unable to connect to AI service. Please check your API key and internet connection."
    elif "timeout" in error.lower():
        return "Request timed out. Please try again."
    elif "rate limit" in error.lower():
        return "Rate limit exceeded. Please wait a moment and try again."
    else:
        return f"An error occurred: {error}"
