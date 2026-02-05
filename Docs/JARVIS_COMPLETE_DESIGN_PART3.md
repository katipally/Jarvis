# JARVIS AI - Complete System Design

> **Version:** 5.2 | **Date:** February 3, 2026  
> **Document:** Part 3 of 5 - Backend Implementation (Enhanced with macOS Integration)

---

## Table of Contents

1. [Tony Orchestrator](#1-tony-orchestrator)
2. [Intent Classification](#2-intent-classification)
3. [Reasoning & Planning](#3-reasoning--planning)
4. [Agent Registry](#4-agent-registry)
5. [All 13 Agents Detailed](#5-all-13-agents-detailed)
6. [macOS System Integration](#6-macos-system-integration)
7. [RAG Engine](#7-rag-engine)
8. [Memory System](#8-memory-system)
9. [Voice Pipeline](#9-voice-pipeline)
10. [API Server](#10-api-server)
11. [Error Handling](#11-error-handling)

---

# 1. Tony Orchestrator

## 1.1 What is Tony?

Tony is the **central brain** of Jarvis - it coordinates all AI operations:
- Receives user input from any mode
- Classifies intent to understand what user wants
- Gathers context from session, RAG, and memory
- Creates an execution plan if needed
- Executes tools via agents
- Generates human-friendly responses
- Stores to long-term memory

**Why "Tony"?** Named after Tony Stark (Iron Man), who created the original Jarvis.

## 1.2 Processing Pipeline

```
 User Input: "Open Safari and search for AI news"
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│                    1. INTENT CLASSIFICATION (~5ms)                │
│                                                                  │
│  SetFit model classifies:                                        │
│  - category: "task_complex" (multi-step)                         │
│  - confidence: 0.95                                              │
│  - requires_planning: true                                       │
│  - complexity: 3                                                 │
│  - agents: ["app_lifecycle", "browser", "web_search"]            │
└──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│                    2. CONTEXT GATHERING (parallel)                │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐          │
│  │   Session   │  │     RAG     │  │     Memory      │          │
│  │   History   │  │   Search    │  │     Recall      │          │
│  └─────────────┘  └─────────────┘  └─────────────────┘          │
│                                                                  │
│  Result: Combined context about user, past conversations,        │
│          relevant documents, and previous interactions           │
└──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│                    3. PLAN CREATION (~200ms)                      │
│                                                                  │
│  LLM creates step-by-step plan:                                  │
│  {                                                               │
│    "summary": "Opening Safari and searching for AI news",        │
│    "steps": [                                                    │
│      {"id": "1", "description": "Launch Safari",                 │
│       "tool": "app_lifecycle.launch_app",                        │
│       "args": {"app_name": "Safari"}},                           │
│      {"id": "2", "description": "Navigate to Google",            │
│       "tool": "browser.navigate_to_url",                         │
│       "args": {"url": "https://google.com"}},                    │
│      {"id": "3", "description": "Search for AI news",            │
│       "tool": "browser.fill_input",                              │
│       "args": {"text": "AI news", "field": "search"}}            │
│    ]                                                             │
│  }                                                               │
│                                                                  │
│  → Plan sent to frontend (shows in UI)                          │
└──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│                    4. PLAN EXECUTION                              │
│                                                                  │
│  For each step:                                                  │
│  1. Mark step as "running" → frontend updates                    │
│  2. Execute tool via agent                                       │
│  3. Mark step as "completed" or "failed"                         │
│  4. Stream update to frontend                                    │
└──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│                    5. RESPONSE GENERATION                         │
│                                                                  │
│  LLM generates human-friendly summary:                           │
│  "Done! I've opened Safari and searched for AI news.             │
│   I found several recent articles. Would you like me to          │
│   open any specific one?"                                        │
└──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────────────────────────┐
│                    6. MEMORY STORAGE                              │
│                                                                  │
│  Store to Cognee:                                                │
│  - What user asked                                               │
│  - What actions were taken                                       │
│  - Extracted entities (Safari, AI news)                          │
│  - Relationship: User → searched_for → AI news                   │
└──────────────────────────────────────────────────────────────────┘
```

## 1.3 Implementation

```python
# backend/core/tony.py

from typing import AsyncIterator
from dataclasses import dataclass
from enum import Enum
import asyncio

from .intent import SetFitClassifier, Intent
from .planner import ReasoningPlanner, Plan
from .rag import RAGEngine
from .session import SessionManager, JarvisMode, MessageRole
from .model_provider import ModelManager
from ..memory.cognee_memory import CogneeMemory
from ..agents.registry import AgentRegistry

class ResponseType(str, Enum):
    """Types of responses Tony can yield."""
    PLAN = "plan"            # Execution plan created
    STEP_UPDATE = "step_update"  # Step status changed
    CONTENT = "content"      # Text content (streaming)
    ERROR = "error"          # Error occurred
    COMPLETE = "complete"    # Processing finished

@dataclass
class TonyResponse:
    """Response yielded during processing."""
    type: ResponseType
    data: dict

class JarvisTony:
    """
    Central orchestrator for all Jarvis AI operations.
    
    Named after Tony Stark, this is the "brain" that:
    1. Understands what user wants (intent classification)
    2. Remembers past conversations (session + memory)
    3. Knows relevant information (RAG)
    4. Plans how to achieve goals (reasoning planner)
    5. Executes actions (agent tools)
    6. Communicates results (response generation)
    """
    
    def __init__(
        self,
        model_manager: ModelManager,
        session_manager: SessionManager
    ):
        # Core dependencies
        self.models = model_manager
        self.sessions = session_manager
        
        # AI components (initialized once, reused)
        self.classifier = SetFitClassifier()  # ~10-15ms inference
        self.planner = ReasoningPlanner()     # Uses LLM
        self.rag = RAGEngine()                # Vector + BM25
        self.memory = CogneeMemory()          # GraphRAG
        self.agents = AgentRegistry()         # 13 agents, 53 tools
    
    async def process(
        self,
        user_input: str,
        mode: JarvisMode,
        session_id: str = None
    ) -> AsyncIterator[TonyResponse]:
        """
        Main processing pipeline.
        
        This is the primary entry point called by the WebSocket handler.
        Yields responses as they're generated for streaming to frontend.
        
        Args:
            user_input: What the user said/typed
            mode: Which UI mode (chat, focus, voice, ray)
            session_id: Optional session ID for continuity
        
        Yields:
            TonyResponse objects for frontend to display
        """
        # Get or create session for context continuity
        session = self.sessions.get_or_create(session_id)
        
        # Store user message in session (tracks cross-mode history)
        session.add_message(mode, MessageRole.USER, user_input)
        
        try:
            # STEP 1: Classify intent (~5ms)
            # Determines what category of request this is
            intent = await self.classifier.classify(user_input)
            
            # STEP 2: Gather context (parallel for speed)
            # Gets session history, RAG results, and memories
            context = await self._gather_context(user_input, session)
            
            # STEP 3: Process based on complexity
            if intent.requires_planning:
                # Complex task: create and execute plan
                async for response in self._execute_with_plan(
                    user_input, intent, context, session
                ):
                    yield response
            else:
                # Simple query: direct LLM response
                async for response in self._direct_response(
                    user_input, context, session
                ):
                    yield response
            
            # Signal completion
            yield TonyResponse(type=ResponseType.COMPLETE, data={})
            
        except Exception as e:
            # Error handling - yield error but don't crash
            yield TonyResponse(
                type=ResponseType.ERROR,
                data={
                    "message": str(e),
                    "recoverable": True  # Frontend can retry
                }
            )
    
    async def _gather_context(self, query: str, session) -> dict:
        """
        Gather all relevant context in parallel.
        
        Three sources:
        1. Session: Recent messages from this conversation
        2. RAG: Relevant documents from knowledge base
        3. Memory: Past conversations and entities from Cognee
        
        Returns combined context dict for LLM.
        """
        # Run all context gathering in parallel
        rag_task = self.rag.retrieve(query, top_k=5)
        memory_task = self.memory.recall(query, limit=5)
        
        rag_results, memory_results = await asyncio.gather(
            rag_task, memory_task,
            return_exceptions=True  # Don't fail if one source fails
        )
        
        return {
            "session": session.get_context_for_llm(limit=10),
            "rag": rag_results if not isinstance(rag_results, Exception) else [],
            "memory": memory_results if not isinstance(memory_results, Exception) else [],
            "entities": session.context.mentioned_entities[-10:]
        }
    
    async def _execute_with_plan(
        self,
        user_input: str,
        intent: Intent,
        context: dict,
        session
    ) -> AsyncIterator[TonyResponse]:
        """Handle complex requests that need a plan."""
        
        # Get tools relevant to this intent
        available_tools = self.agents.get_tools_for_intent(intent)
        
        # Create execution plan
        plan = await self.planner.create_plan(
            user_input=user_input,
            intent=intent,
            context=context,
            available_tools=available_tools
        )
        
        # Send plan to frontend
        yield TonyResponse(type=ResponseType.PLAN, data=plan.model_dump())
        
        # Execute steps and stream updates
        results = []
        for step in plan.steps:
            step.status = "running"
            yield TonyResponse(
                type=ResponseType.STEP_UPDATE,
                data={"step_id": step.id, "status": "running"}
            )
            
            try:
                if step.tool_name:
                    result = await self.agents.execute_tool(
                        step.tool_name, step.tool_args
                    )
                else:
                    result = "Completed"
                
                step.status = "completed"
                step.result = result
                results.append({"step": step.id, "result": result})
                
            except Exception as e:
                step.status = "failed"
                step.result = str(e)
            
            yield TonyResponse(
                type=ResponseType.STEP_UPDATE,
                data={"step_id": step.id, "status": step.status, "result": step.result}
            )
        
        # Generate final response
        async for chunk in self._generate_response(user_input, results):
            yield TonyResponse(type=ResponseType.CONTENT, data={"text": chunk})
    
    async def _direct_response(
        self,
        user_input: str,
        context: dict,
        session
    ) -> AsyncIterator[TonyResponse]:
        """Handle simple queries without tools."""
        
        messages = self._build_messages(user_input, context)
        
        async for chunk in self.models.generate(messages):
            yield TonyResponse(type=ResponseType.CONTENT, data={"text": chunk})
    
    async def _generate_response(
        self,
        user_input: str,
        results: list
    ) -> AsyncIterator[str]:
        """Generate human-friendly response from results."""
        
        results_text = "\n".join([f"- {r['step']}: {r['result']}" for r in results])
        
        messages = [
            {"role": "system", "content": "Summarize what was done concisely."},
            {"role": "user", "content": f"Request: {user_input}\n\nResults:\n{results_text}"}
        ]
        
        async for chunk in self.models.generate(messages):
            yield chunk
    
    def _build_messages(self, user_input: str, context: dict) -> list:
        """Build message list for LLM."""
        system = "You are Jarvis, a helpful macOS AI assistant. Be concise."
        
        messages = [{"role": "system", "content": system}]
        messages.extend(context.get("session", []))
        messages.append({"role": "user", "content": user_input})
        
        return messages
```

---

# 2. Intent Classification

## 2.1 Why SetFit?

**Problem:** Classifying every message takes time. Using a full LLM (100-500ms) is too slow.

**Solution:** SetFit - few-shot learning that's:
- **Ultra-fast**: ~10-15ms inference (with warm cache)
- **Accurate**: 90%+ with 8-16 examples per class
- **Small**: ~50MB model
- **Trainable**: Add new intents easily

## 2.2 Intent Categories

| Intent | Example | Tools Needed |
|--------|---------|-------------|
| `app_launch` | "Open Safari" | app_lifecycle |
| `app_quit` | "Close Chrome" | app_lifecycle |
| `web_search` | "Search for AI news" | web_search |
| `web_navigate` | "Go to github.com" | browser |
| `web_interact` | "Click Sign In" | browser, ui_automation |
| `file_search` | "Find Python files" | file_processing |
| `file_read` | "Read my notes" | file_processing |
| `system_control` | "Set volume to 50%" | system_control |
| `question` | "What is ML?" | knowledge (no tools) |
| `conversation` | "How are you?" | (no tools) |
| `task_complex` | "Open Safari and search" | multiple agents |

## 2.3 Implementation

```python
# backend/core/intent.py

from pydantic import BaseModel
from setfit import SetFitModel
from typing import Optional
import numpy as np

class Intent(BaseModel):
    """Result of intent classification."""
    category: str          # One of the 11 categories
    confidence: float      # 0.0 to 1.0
    requires_planning: bool  # Whether to create a plan
    complexity: int        # 1-5 scale
    suggested_agents: list[str]  # Which agents to use

class SetFitClassifier:
    """
    Ultra-fast intent classification using SetFit.
    
    SetFit uses sentence transformers for few-shot learning.
    Trained on 8-16 examples per class, achieves 90%+ accuracy.
    Inference is ~5ms compared to 100-500ms for LLM classification.
    """
    
    # Intent to agent mapping
    INTENT_AGENTS = {
        "app_launch": ["app_lifecycle"],
        "app_quit": ["app_lifecycle"],
        "web_search": ["web_search"],
        "web_navigate": ["browser"],
        "web_interact": ["browser", "ui_automation"],
        "file_search": ["file_processing"],
        "file_read": ["file_processing"],
        "system_control": ["system_control"],
        "question": ["knowledge"],
        "conversation": [],
        "task_complex": ["*"]  # All agents available
    }
    
    def __init__(self, model_path: str = "models/setfit-intent"):
        try:
            self.model = SetFitModel.from_pretrained(model_path)
        except:
            self.model = SetFitModel.from_pretrained(
                "sentence-transformers/paraphrase-MiniLM-L3-v2"
            )
            self._train_initial()
    
    async def classify(self, text: str) -> Intent:
        """Classify user intent (~5ms)."""
        predictions = self.model.predict([text])
        probabilities = self.model.predict_proba([text])
        
        category = predictions[0]
        confidence = float(np.max(probabilities[0]))
        complexity = self._estimate_complexity(text, category)
        
        return Intent(
            category=category,
            confidence=confidence,
            requires_planning=category not in ["question", "conversation"] or complexity >= 3,
            complexity=complexity,
            suggested_agents=self.INTENT_AGENTS.get(category, [])
        )
    
    def _estimate_complexity(self, text: str, category: str) -> int:
        """Estimate task complexity 1-5."""
        has_and = " and " in text.lower()
        has_then = " then " in text.lower()
        multi_words = ["after", "before", "first", "next"]
        has_multi = any(w in text.lower() for w in multi_words)
        
        complexity = 1
        if len(text.split()) > 10: complexity += 1
        if has_and or has_then: complexity += 1
        if has_multi: complexity += 2
        if category == "task_complex": complexity = max(complexity, 3)
        
        return min(complexity, 5)
    
    def _train_initial(self):
        """Train on seed data."""
        data = [
            ("open safari", "app_launch"),
            ("launch xcode", "app_launch"),
            ("close chrome", "app_quit"),
            ("search for AI news", "web_search"),
            ("go to github.com", "web_navigate"),
            ("click the login button", "web_interact"),
            ("find python files", "file_search"),
            ("read my notes.txt", "file_read"),
            ("set volume to 50%", "system_control"),
            ("what is machine learning", "question"),
            ("how are you", "conversation"),
            ("open safari and search for news", "task_complex"),
        ]
        texts = [t[0] for t in data]
        labels = [t[1] for t in data]
        self.model.fit(texts, labels)
        self.model.save_pretrained("models/setfit-intent")
```

---

# 3. Reasoning & Planning

## 3.1 When Planning is Needed

**Simple requests (no plan):**
- "What's the capital of France?" → Direct LLM answer
- "How are you?" → Direct response

**Complex requests (needs plan):**
- "Open Safari and search for AI news" → 3 steps
- "Find all PDFs and organize by date" → Multiple file operations

## 3.2 Plan Structure

```python
# backend/core/planner.py

from pydantic import BaseModel
from typing import Optional, List

class PlanStep(BaseModel):
    """Single step in execution plan."""
    id: str                          # Unique ID ("1", "2", etc.)
    description: str                 # Human-readable description
    tool_name: Optional[str] = None  # Tool to execute (if any)
    tool_args: dict = {}             # Arguments for tool
    status: str = "pending"          # pending/running/completed/failed
    result: Optional[str] = None     # Execution result

class Plan(BaseModel):
    """Complete execution plan."""
    summary: str           # What we're doing overall
    steps: List[PlanStep]  # Ordered steps
    total_steps: int       # Count for progress

class ReasoningPlanner:
    """
    Creates step-by-step execution plans using LLM.
    
    The planner receives:
    1. User request
    2. Classified intent
    3. Context (session, RAG, memory)
    4. Available tools
    
    And outputs a JSON plan that can be executed step by step.
    
    **UPGRADE (Feb 2026): Uses LangGraph StateGraph for:**
    - Checkpointing (recover from failures)
    - Parallel tool execution (fan-out/fan-in)
    - Time-travel debugging
    """
    
    PLANNER_PROMPT = '''You are a planning assistant. Create a step-by-step plan.

User Request: {user_input}
Intent: {intent}
Available Tools: {tools}

Output a JSON plan with this format:
{{
  "summary": "Brief description of what we'll do",
  "steps": [
    {{"id": "1", "description": "What this step does", "tool_name": "tool.name", "tool_args": {{}}, "can_parallel": false}},
    ...
  ]
}}

Rules:
- Use only the available tools
- Keep plans minimal - fewest steps possible
- tool_args must match the tool's expected parameters
- Set can_parallel: true for steps that don't depend on previous steps
- Output ONLY valid JSON, no explanation'''

    async def create_plan(
        self,
        user_input: str,
        intent,
        context: dict,
        available_tools: list
    ) -> Plan:
        """Create execution plan using LLM."""
        
        # Format tools for prompt
        tools_desc = "\n".join([
            f"- {t.name}: {t.description}"
            for t in available_tools
        ])
        
        prompt = self.PLANNER_PROMPT.format(
            user_input=user_input,
            intent=intent.category,
            tools=tools_desc
        )
        
        # Get plan from LLM
        from ..core.model_provider import get_model_manager
        manager = get_model_manager()
        
        response = ""
        async for chunk in manager.generate([
            {"role": "user", "content": prompt}
        ]):
            response += chunk
        
        # Parse JSON response
        import json
        plan_data = json.loads(response)
        
        return Plan(
            summary=plan_data["summary"],
            steps=[PlanStep(**s) for s in plan_data["steps"]],
            total_steps=len(plan_data["steps"])
        )

## 3.3 LangGraph StateGraph Executor (Feb 2026 Upgrade)

> [!IMPORTANT]
> LangGraph enables **checkpointing, parallel execution, and time-travel debugging** for robust plan execution.

```python
# backend/core/executor.py

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.postgres import PostgresSaver
from typing import TypedDict, Annotated
import operator
import asyncio

class ExecutionState(TypedDict):
    """State passed through the execution graph."""
    plan: Plan
    current_step: int
    results: Annotated[list, operator.add]  # Accumulates from parallel nodes
    errors: list
    thread_id: str

class LangGraphExecutor:
    """
    Executes plans using LangGraph StateGraph.
    
    Features:
    - Checkpointing: Resume from failure
    - Parallel execution: Fan-out independent steps
    - Time-travel: Debug past executions
    
    Usage:
        executor = LangGraphExecutor(registry)
        async for update in executor.execute(plan, thread_id):
            yield update  # Stream to frontend
    """
    
    def __init__(self, agent_registry, db_url: str = None):
        self.registry = agent_registry
        
        # PostgreSQL checkpointing for durability
        if db_url:
            self.checkpointer = PostgresSaver.from_conn_string(db_url)
        else:
            self.checkpointer = None  # In-memory for dev
        
        # Build the execution graph
        self.graph = self._build_graph()
    
    def _build_graph(self) -> StateGraph:
        """Create the LangGraph StateGraph."""
        builder = StateGraph(ExecutionState)
        
        # Nodes
        builder.add_node("analyze_parallelism", self._analyze_parallelism)
        builder.add_node("execute_sequential", self._execute_sequential)
        builder.add_node("execute_parallel", self._execute_parallel)
        builder.add_node("aggregate_results", self._aggregate_results)
        
        # Edges
        builder.set_entry_point("analyze_parallelism")
        builder.add_conditional_edges(
            "analyze_parallelism",
            self._route_execution,
            {
                "sequential": "execute_sequential",
                "parallel": "execute_parallel"
            }
        )
        builder.add_edge("execute_sequential", "aggregate_results")
        builder.add_edge("execute_parallel", "aggregate_results")
        builder.add_conditional_edges(
            "aggregate_results",
            self._check_more_steps,
            {"continue": "analyze_parallelism", "done": END}
        )
        
        return builder.compile(checkpointer=self.checkpointer)
    
    async def _execute_parallel(self, state: ExecutionState) -> ExecutionState:
        """Execute independent steps in parallel (fan-out)."""
        
        # Find steps that can run in parallel
        parallel_steps = [s for s in state["plan"].steps 
                        if s.status == "pending" and s.can_parallel]
        
        async def execute_one(step):
            result = await self.registry.execute_tool(
                step.tool_name, step.tool_args
            )
            return {"step_id": step.id, "result": result}
        
        # Fan-out: run all parallel steps concurrently
        results = await asyncio.gather(
            *[execute_one(step) for step in parallel_steps],
            return_exceptions=True
        )
        
        state["results"] = results
        return state
    
    async def execute(
        self, 
        plan: Plan, 
        thread_id: str
    ) -> AsyncIterator[TonyResponse]:
        """
        Execute plan with streaming updates.
        
        Args:
            plan: The execution plan
            thread_id: Unique ID for checkpointing
        
        Yields:
            TonyResponse with step updates
        """
        config = {"configurable": {"thread_id": thread_id}}
        
        initial_state = {
            "plan": plan,
            "current_step": 0,
            "results": [],
            "errors": [],
            "thread_id": thread_id
        }
        
        # Stream execution through the graph
        async for event in self.graph.astream_events(initial_state, config):
            if event["event"] == "on_chain_end":
                step_result = event["data"].get("output", {})
                yield TonyResponse(
                    type=ResponseType.STEP_UPDATE,
                    data=step_result
                )
```

## 3.4 Universal LLM Provider (Model-Agnostic Design)

> [!NOTE]
> Jarvis works identically with any LLM. All providers implement the same `ModelProvider` protocol.

```python
# backend/core/model_provider.py

from typing import Protocol, AsyncIterator, runtime_checkable
from abc import abstractmethod
import httpx

@runtime_checkable
class ModelProvider(Protocol):
    """
    Protocol for LLM providers.
    
    All providers (local and cloud) implement this interface,
    allowing Jarvis to work identically with any LLM.
    """
    
    @abstractmethod
    async def generate(
        self, 
        messages: list[dict],
        tools: list[dict] = None,
        temperature: float = 0.7
    ) -> AsyncIterator[str]:
        """Stream text tokens from the LLM."""
        ...
    
    @abstractmethod
    async def generate_with_tools(
        self,
        messages: list[dict],
        tools: list[dict]
    ) -> AsyncIterator[dict]:
        """Stream tokens OR tool calls (for function calling)."""
        ...

class OllamaProvider:
    """Local LLM via Ollama."""
    
    def __init__(self, model: str = "llama3.2:latest", base_url: str = "http://localhost:11434"):
        self.model = model
        self.base_url = base_url
    
    async def generate(self, messages: list[dict], tools=None, temperature=0.7) -> AsyncIterator[str]:
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/api/chat",
                json={"model": self.model, "messages": messages, "stream": True},
                timeout=60.0
            ) as response:
                async for line in response.aiter_lines():
                    if line:
                        data = json.loads(line)
                        if chunk := data.get("message", {}).get("content"):
                            yield chunk

class OpenAIProvider:
    """Cloud LLM via OpenAI API."""
    
    def __init__(self, api_key: str, model: str = "gpt-4o"):
        self.api_key = api_key
        self.model = model
        self.base_url = "https://api.openai.com/v1"
    
    async def generate(self, messages: list[dict], tools=None, temperature=0.7) -> AsyncIterator[str]:
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/chat/completions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": True,
                    "temperature": temperature,
                    **({"tools": tools} if tools else {})
                },
                timeout=60.0
            ) as response:
                async for line in response.aiter_lines():
                    if line.startswith("data: ") and line != "data: [DONE]":
                        data = json.loads(line[6:])
                        if chunk := data["choices"][0]["delta"].get("content"):
                            yield chunk
    
    async def generate_with_tools(self, messages: list[dict], tools: list[dict]) -> AsyncIterator[dict]:
        """Stream with function calling support."""
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/chat/completions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "messages": messages,
                    "tools": tools,
                    "stream": True
                }
            ) as response:
                async for line in response.aiter_lines():
                    if line.startswith("data: ") and line != "data: [DONE]":
                        data = json.loads(line[6:])
                        delta = data["choices"][0]["delta"]
                        
                        # Yield text OR tool call
                        if "content" in delta:
                            yield {"type": "text", "content": delta["content"]}
                        elif "tool_calls" in delta:
                            yield {"type": "tool_call", "call": delta["tool_calls"][0]}

class ModelManager:
    """
    Manages LLM providers based on user settings.
    
    Best Practices (2026):
    - 2-3 Model Rule: Fast model for simple, powerful for complex
    - Rate limiting: Token bucket with x-ratelimit headers
    - Caching: Cache similar queries
    - Fallback: Local → Cloud if configured
    """
    
    def __init__(self, settings: Settings):
        self.settings = settings
        self._providers = {}
        self._setup_providers()
    
    def _setup_providers(self):
        # Always try to set up local
        self._providers["local"] = OllamaProvider()
        
        # Set up cloud providers if configured
        if self.settings.openai_key:
            self._providers["openai"] = OpenAIProvider(self.settings.openai_key)
        
        if self.settings.together_key:
            self._providers["together"] = OpenAIProvider(
                api_key=self.settings.together_key,
                base_url="https://api.together.xyz/v1"
            )
    
    def get_provider(self, preference: str = "default") -> ModelProvider:
        """Get provider based on user preference or availability."""
        if preference == "default":
            preference = self.settings.default_provider or "local"
        
        return self._providers.get(preference, self._providers.get("local"))
```

---

# 4. Agent Registry

## 4.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AGENT REGISTRY                              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Agents Dictionary                                            ││
│  │ {                                                            ││
│  │   "app_lifecycle": AppLifecycleAgent,                        ││
│  │   "browser": BrowserAgent,                                   ││
│  │   "web_search": WebSearchAgent,                              ││
│  │   ...                                                        ││
│  │ }                                                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Tools Dictionary                                             ││
│  │ {                                                            ││
│  │   "app_lifecycle.launch_app": ToolDefinition,                ││
│  │   "browser.navigate_to_url": ToolDefinition,                 ││
│  │   ...                                                        ││
│  │ }                                                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Methods:                                                        │
│  - get_tools_for_intent(intent) → relevant tools                │
│  - execute_tool(name, args) → result                            │
│  - list_all_tools() → all available tools                       │
│  - discover_capabilities() → dynamic MCP/skill discovery        │
└─────────────────────────────────────────────────────────────────┘
```

## 4.2 Implementation (Enhanced with MCP)

```python
# backend/agents/registry.py

from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from pathlib import Path
import yaml

@dataclass
class ToolDefinition:
    """Definition of an available tool."""
    name: str           # Full name: "agent.tool_name"
    description: str    # What it does
    parameters: dict    # Expected arguments
    agent_id: str       # Which agent owns this
    permission: Optional[str] = None  # Required macOS permission
    macos_api: Optional[str] = None   # Underlying macOS API used

class AgentRegistry:
    """
    Central registry of all agents and tools.
    
    ENHANCED: Now integrates with MCP servers and skills for
    dynamic capability discovery. Jarvis learns what it can do
    at runtime by reading skill documentation.
    
    Responsibilities:
    1. Load and manage all agent instances
    2. Connect to MCP servers for macOS capabilities
    3. Load self-documenting skills
    4. Track all available tools with their macOS APIs
    5. Route tool execution to correct agent
    6. Filter tools by intent relevance
    7. Check permissions before exposing tools
    """
    
    def __init__(self):
        self.agents: Dict[str, Any] = {}
        self.tools: Dict[str, ToolDefinition] = {}
        self.mcp_servers: Dict[str, Any] = {}
        self.skills: Dict[str, Any] = {}
        self._register_all()
        self._load_skills()
        self._connect_mcp()
    
    def _register_all(self):
        """Import and register all agents."""
        from .knowledge import KnowledgeAgent
        from .web_search import WebSearchAgent
        from .mac_automation import MacAutomationAgent
        from .browser import BrowserAgent
        from .screen_vision import ScreenVisionAgent
        from .app_lifecycle import AppLifecycleAgent
        from .window_manager import WindowManagerAgent
        from .input_simulation import InputSimulationAgent
        from .media_control import MediaControlAgent
        from .file_processing import FileProcessingAgent
        from .system_control import SystemControlAgent
        from .shortcut_runner import ShortcutRunnerAgent
        from .ui_automation import UIAutomationAgent
        from .data_access import DataAccessAgent  # NEW: Calendar, Contacts, etc.
        
        agent_classes = [
            KnowledgeAgent, WebSearchAgent, MacAutomationAgent,
            BrowserAgent, ScreenVisionAgent, AppLifecycleAgent,
            WindowManagerAgent, InputSimulationAgent, MediaControlAgent,
            FileProcessingAgent, SystemControlAgent, ShortcutRunnerAgent,
            UIAutomationAgent, DataAccessAgent
        ]
        
        for cls in agent_classes:
            agent = cls()
            self.agents[agent.id] = agent
            
            for tool in agent.get_tools():
                full_name = f"{agent.id}.{tool.name}"
                self.tools[full_name] = ToolDefinition(
                    name=full_name,
                    description=tool.description,
                    parameters=tool.parameters,
                    agent_id=agent.id,
                    permission=getattr(tool, 'permission', None),
                    macos_api=getattr(tool, 'macos_api', None)
                )
    
    def _load_skills(self):
        """
        Load self-documenting skills from skills/ directory.
        
        Each skill has a SKILL.md that the LLM reads to learn
        what the skill can do - NO HARDCODING REQUIRED.
        """
        skills_dir = Path("skills")
        if not skills_dir.exists():
            return
        
        for skill_path in skills_dir.iterdir():
            if skill_path.is_dir() and (skill_path / "manifest.yaml").exists():
                manifest = yaml.safe_load((skill_path / "manifest.yaml").read_text())
                skill_doc = (skill_path / "SKILL.md").read_text() if (skill_path / "SKILL.md").exists() else ""
                
                self.skills[manifest["name"]] = {
                    "manifest": manifest,
                    "documentation": skill_doc,  # LLM reads this!
                    "triggers": manifest.get("triggers", {}),
                    "permissions": manifest.get("permissions", [])
                }
    
    def _connect_mcp(self):
        """
        Connect to MCP servers for dynamic macOS capabilities.
        
        MCP servers expose tools and resources that Jarvis can use.
        """
        from .mcp import MCPClientHub
        self.mcp_hub = MCPClientHub()
        
        # Connect to macOS capability servers
        self.mcp_hub.connect("macos-data-access")   # Calendar, Contacts, etc.
        self.mcp_hub.connect("macos-ui-automation") # AXUIElement control
        self.mcp_hub.connect("macos-system")        # Volume, WiFi, etc.
    
    def get_skill_context_for_llm(self, relevant_skills: list) -> str:
        """
        Build skill documentation for LLM system prompt.
        
        This is how Jarvis LEARNS its capabilities - by reading
        the skill documentation at runtime, not from hardcoded prompts.
        """
        context = "## Available macOS Capabilities\n\n"
        for name in relevant_skills:
            if skill := self.skills.get(name):
                context += f"### {name}\n{skill['documentation']}\n\n"
        return context
    
    def get_tools_for_intent(self, intent) -> List[ToolDefinition]:
        """Get tools relevant to an intent."""
        if "*" in intent.suggested_agents:
            return list(self.tools.values())
        
        relevant = []
        for agent_id in intent.suggested_agents:
            if agent := self.agents.get(agent_id):
                for tool in agent.get_tools():
                    full_name = f"{agent_id}.{tool.name}"
                    relevant.append(self.tools[full_name])
        return relevant
    
    async def execute_tool(self, tool_name: str, args: dict) -> Any:
        """Execute a tool by name."""
        if tool_name not in self.tools:
            raise ValueError(f"Unknown tool: {tool_name}")
        
        tool_def = self.tools[tool_name]
        agent = self.agents[tool_def.agent_id]
        
        # Check permission before execution
        if tool_def.permission:
            from .permissions import PermissionManager
            if not await PermissionManager().check(tool_def.permission):
                return f"Permission required: {tool_def.permission}"
        
        # Extract just the tool name (without agent prefix)
        short_name = tool_name.split(".")[-1]
        return await agent.execute_tool(short_name, args)
```

---

# 5. All 13 Agents Detailed

## Summary Table

| Agent | Tools | Description |
|-------|-------|-------------|
| Knowledge | 3 | Search/add to knowledge base |
| Web Search | 3 | Search web, news, images |
| Mac Automation | 4 | AppleScript, shell, shortcuts |
| Browser | 6 | Navigate, click, fill, screenshot |
| Screen Vision | 4 | Capture, OCR, find elements |
| App Lifecycle | 5 | Launch, quit, list apps |
| Window Manager | 7 | Focus, resize, tile windows |
| Input Simulation | 5 | Type, click, hotkeys |
| Media Control | 5 | Play/pause, volume, now playing |
| File Processing | 7 | Read, write, search files |
| System Control | 7 | Volume, DND, battery, WiFi |
| Shortcut Runner | 2 | List/run Shortcuts |
| UI Automation | 4 | Find/click UI elements |

**Total: 13 Agents, 53 Tools**

> **Note:** Tool count audited Feb 2026 for realistic scope.

## 5.1 App Lifecycle Agent

```python
# backend/agents/app_lifecycle.py

class AppLifecycleAgent:
    """
    Manages application lifecycle: launch, quit, list.
    
    Uses AppleScript for reliable app control.
    """
    
    id = "app_lifecycle"
    
    async def launch_app(self, app_name: str) -> str:
        """Launch an application by name."""
        script = f'tell application "{app_name}" to activate'
        await self._run_applescript(script)
        return f"{app_name} launched"
    
    async def quit_app(self, app_name: str) -> str:
        """Quit an application."""
        script = f'tell application "{app_name}" to quit'
        await self._run_applescript(script)
        return f"{app_name} quit"
    
    async def is_running(self, app_name: str) -> bool:
        """Check if app is running."""
        script = f'''
        tell application "System Events"
            return (name of processes) contains "{app_name}"
        end tell
        '''
        result = await self._run_applescript(script)
        return result.strip() == "true"
    
    async def list_running(self) -> list:
        """List all running applications."""
        script = '''
        tell application "System Events"
            return name of every process where background only is false
        end tell
        '''
        result = await self._run_applescript(script)
        return result.split(", ")
    
    async def activate(self, app_name: str) -> str:
        """Bring app to front."""
        script = f'tell application "{app_name}" to activate'
        await self._run_applescript(script)
        return f"{app_name} activated"
```

## 5.2 Browser Agent

```python
# backend/agents/browser.py

class BrowserAgent:
    """
    Controls web browsers (Safari, Chrome, Arc).
    
    Uses AppleScript + JavaScript for reliable web control.
    """
    
    id = "browser"
    
    async def navigate(self, url: str, browser: str = "Safari") -> str:
        """Navigate to a URL."""
        if browser == "Safari":
            script = f'''
            tell application "Safari"
                activate
                tell window 1 to set current tab to (make new tab with properties {{URL:"{url}"}})
            end tell
            '''
        else:  # Chrome
            script = f'''
            tell application "Google Chrome"
                activate
                tell window 1 to set active tab index to (make new tab with properties {{URL:"{url}"}})
            end tell
            '''
        await self._run_applescript(script)
        return f"Navigated to {url}"
    
    async def click_element(self, text: str, browser: str = "Safari") -> str:
        """Click element containing text."""
        js = f'''
        var elements = document.querySelectorAll('a, button, input[type="submit"]');
        for (var el of elements) {{
            if (el.textContent.toLowerCase().includes("{text.lower()}")) {{
                el.click();
                break;
            }}
        }}
        '''
        await self._run_javascript(js, browser)
        return f"Clicked element with '{text}'"
    
    async def fill_input(self, text: str, field: str = "", browser: str = "Safari") -> str:
        """Fill an input field."""
        if field:
            js = f'''
            var input = document.querySelector('input[name="{field}"], input[placeholder*="{field}"]');
            if (input) {{ input.value = "{text}"; input.dispatchEvent(new Event('input')); }}
            '''
        else:
            js = f'''
            var input = document.querySelector('input[type="text"], input[type="search"], input:not([type])');
            if (input) {{ input.value = "{text}"; input.dispatchEvent(new Event('input')); }}
            '''
        await self._run_javascript(js, browser)
        return f"Filled input with '{text}'"
    
    async def get_page_content(self, browser: str = "Safari") -> str:
        """Get text content of current page."""
        js = "document.body.innerText"
        content = await self._run_javascript(js, browser)
        return content[:5000]  # Limit size
    
    async def scroll(self, direction: str = "down", amount: int = 500) -> str:
        """Scroll page."""
        y = amount if direction == "down" else -amount
        js = f"window.scrollBy(0, {y})"
        await self._run_javascript(js, "Safari")
        return f"Scrolled {direction}"
    
    async def screenshot(self, browser: str = "Safari") -> str:
        """Take screenshot of browser window."""
        import subprocess
        path = f"/tmp/browser_screenshot_{int(time.time())}.png"
        subprocess.run(["screencapture", "-w", "-x", path])
        return path
```

## 5.3 System Control Agent

```python
# backend/agents/system_control.py

class SystemControlAgent:
    """
    Controls macOS system settings.
    
    Volume, Do Not Disturb, brightness, etc.
    """
    
    id = "system_control"
    
    async def set_volume(self, level: int) -> str:
        """Set volume 0-100."""
        volume = max(0, min(100, level))
        script = f'set volume output volume {volume}'
        await self._run_applescript(script)
        return f"Volume set to {volume}%"
    
    async def get_volume(self) -> int:
        """Get current volume."""
        script = 'output volume of (get volume settings)'
        result = await self._run_applescript(script)
        return int(result)
    
    async def toggle_dnd(self, enabled: bool) -> str:
        """Toggle Do Not Disturb."""
        # macOS 26 Focus mode control
        script = f'''
        tell application "System Events"
            tell process "Control Center"
                -- Access Focus menu
            end tell
        end tell
        '''
        # Implementation varies by macOS version
        return f"Do Not Disturb {'enabled' if enabled else 'disabled'}"
    
    async def get_battery(self) -> dict:
        """Get battery status."""
        import subprocess
        result = subprocess.run(
            ["pmset", "-g", "batt"],
            capture_output=True, text=True
        )
        # Parse: "Now drawing from 'Battery Power'"
        # "Internal Battery: 85%; discharging"
        return {"level": 85, "charging": False}  # Simplified
    
    async def lock_screen(self) -> str:
        """Lock the screen."""
        script = 'tell application "System Events" to key code 12 using {control down, command down}'
        await self._run_applescript(script)
        return "Screen locked"
    
    async def sleep(self) -> str:
        """Put Mac to sleep."""
        script = 'tell application "System Events" to sleep'
        await self._run_applescript(script)
        return "Mac sleeping"
    
    async def get_wifi(self) -> dict:
        """Get WiFi status."""
        import subprocess
        result = subprocess.run(
            ["/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-I"],
            capture_output=True, text=True
        )
        return {"connected": "SSID" in result.stdout, "network": "MyNetwork"}
```

---

# 6. macOS System Integration

> **Reference:** See [MACOS_CAPABILITIES.md](./MACOS_CAPABILITIES.md) for complete API documentation

## 6.1 Architecture Overview

Jarvis integrates with macOS through a **layered architecture** that provides complete system control:

```
┌──────────────────────────────────────────────────────────────────┐
│                    macOS INTEGRATION ARCHITECTURE                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   CAPABILITY LAYER                        │   │
│  │                                                           │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────────┐ │   │
│  │  │  Data   │ │   App   │ │ System  │ │ UI Automation   │ │   │
│  │  │ Access  │ │ Control │ │ Control │ │ (Accessibility) │ │   │
│  │  ├─────────┤ ├─────────┤ ├─────────┤ ├─────────────────┤ │   │
│  │  │Calendar │ │ Launch  │ │ Volume  │ │ Click buttons   │ │   │
│  │  │Contacts │ │ Quit    │ │ Bright  │ │ Fill forms      │ │   │
│  │  │Reminders│ │ Browser │ │ WiFi    │ │ Read UI         │ │   │
│  │  │Mail/Note│ │ Scripts │ │ Power   │ │ Window mgmt     │ │   │
│  │  │Photos   │ │Shortcuts│ │ Focus   │ │ Menu navigation │ │   │
│  │  │Files    │ │         │ │         │ │                 │ │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    API LAYER                              │   │
│  │                                                           │   │
│  │  EventKit · Contacts · PhotoKit · FileManager            │   │
│  │  NSWorkspace · AppleScript · App Intents                 │   │
│  │  AXUIElement · CGEvent · ScreenCaptureKit · Vision       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                 PERMISSION LAYER                          │   │
│  │                                                           │   │
│  │  Calendar · Contacts · Reminders · Photos · Full Disk    │   │
│  │  Accessibility · Screen Recording · Input Monitoring     │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

## 6.2 Data Access Agent

```python
# backend/agents/data_access.py

import subprocess
from datetime import datetime, timedelta
from typing import List, Dict

class DataAccessAgent:
    """
    Accesses macOS user data: Calendar, Contacts, Reminders, Notes, Files.
    
    Uses native frameworks via AppleScript/Python bridges.
    Each tool specifies its required permission.
    """
    
    id = "data_access"
    
    TOOLS = [
        {"name": "calendar_read", "permission": "calendar", "macos_api": "EventKit"},
        {"name": "calendar_create", "permission": "calendar", "macos_api": "EventKit"},
        {"name": "contacts_search", "permission": "contacts", "macos_api": "Contacts"},
        {"name": "reminders_list", "permission": "reminders", "macos_api": "EventKit"},
        {"name": "reminders_create", "permission": "reminders", "macos_api": "EventKit"},
        {"name": "notes_read", "permission": "automation", "macos_api": "AppleScript"},
        {"name": "files_search", "permission": None, "macos_api": "Spotlight"},
        {"name": "clipboard_read", "permission": None, "macos_api": "NSPasteboard"},
        {"name": "location_get", "permission": "location", "macos_api": "CoreLocation"}
    ]
    
    async def calendar_read(self, days: int = 7) -> List[Dict]:
        """
        Read calendar events for next N days.
        
        API: EventKit via AppleScript
        Permission: Calendar access
        """
        script = f'''
        tell application "Calendar"
            set startDate to current date
            set endDate to startDate + ({days} * days)
            set allEvents to {{}}
            repeat with c in calendars
                set evts to (every event of c whose start date >= startDate and start date <= endDate)
                repeat with e in evts
                    set end of allEvents to {{|title|:summary of e, |startDate|:start date of e, |endDate|:end date of e, |location|:location of e}}
                end repeat
            end repeat
            return allEvents
        end tell
        '''
        return await self._run_applescript(script)
    
    async def contacts_search(self, query: str) -> List[Dict]:
        """
        Search contacts by name, email, or phone.
        
        API: Contacts framework via AppleScript
        Permission: Contacts access
        """
        script = f'''
        tell application "Contacts"
            set matchingPeople to every person whose name contains "{query}"
            set results to {{}}
            repeat with p in matchingPeople
                set pInfo to {{|name|:name of p}}
                try
                    set pInfo to pInfo & {{|email|:value of first email of p}}
                end try
                try
                    set pInfo to pInfo & {{|phone|:value of first phone of p}}
                end try
                set end of results to pInfo
            end repeat
            return results
        end tell
        '''
        return await self._run_applescript(script)
    
    async def files_search(self, query: str, file_type: str = None) -> List[str]:
        """
        Search files using Spotlight.
        
        API: NSMetadataQuery (via mdfind CLI)
        Permission: None (uses Spotlight index)
        """
        cmd = ["mdfind"]
        if file_type:
            cmd.extend([f"kMDItemFSName == '*.{file_type}' && kMDItemTextContent == '*{query}*'"])
        else:
            cmd.append(query)
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.stdout.strip().split('\n')[:20]
```

## 6.3 UI Automation Agent (Accessibility API)

This is Jarvis's **SUPERPOWER** - control ANY application's UI:

```python
# backend/agents/ui_automation.py

from ApplicationServices import (
    AXUIElementCreateApplication,
    AXUIElementCopyAttributeValue,
    AXUIElementPerformAction,
    AXUIElementSetAttributeValue
)
import Quartz

class UIAutomationAgent:
    """
    Full UI automation using macOS Accessibility API.
    
    This enables Jarvis to control ANY app - click buttons,
    fill forms, read content, navigate menus - even apps
    without AppleScript support.
    
    Permission Required: Accessibility (System Settings)
    """
    
    id = "ui_automation"
    
    TOOLS = [
        {"name": "find_element", "permission": "accessibility", "macos_api": "AXUIElement"},
        {"name": "click_element", "permission": "accessibility", "macos_api": "AXUIElement"},
        {"name": "type_text", "permission": "accessibility", "macos_api": "CGEvent"},
        {"name": "read_ui", "permission": "accessibility", "macos_api": "AXUIElement"},
        {"name": "navigate_menu", "permission": "accessibility", "macos_api": "AXUIElement"}
    ]
    
    async def click_element(self, app_name: str, element_label: str) -> str:
        """
        Click any button or interactive element.
        
        Args:
            app_name: Target application name
            element_label: Button text or label to click
        
        Returns:
            Confirmation message
        """
        pid = await self._get_app_pid(app_name)
        app_element = AXUIElementCreateApplication(pid)
        
        # Find element recursively
        element = await self._find_element(
            app_element, 
            role="AXButton",
            label=element_label
        )
        
        if element:
            AXUIElementPerformAction(element, "AXPress")
            return f"Clicked '{element_label}' in {app_name}"
        return f"Element '{element_label}' not found"
    
    async def type_text(self, text: str) -> str:
        """
        Type text into the currently focused field.
        
        Uses CGEvent for keyboard simulation.
        """
        for char in text:
            key_down = Quartz.CGEventCreateKeyboardEvent(None, 0, True)
            key_up = Quartz.CGEventCreateKeyboardEvent(None, 0, False)
            Quartz.CGEventKeyboardSetUnicodeString(key_down, len(char), char)
            Quartz.CGEventKeyboardSetUnicodeString(key_up, len(char), char)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_down)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_up)
        return f"Typed: {text}"
    
    async def _find_element(self, element, role=None, label=None):
        """Recursively find UI element by role and label."""
        err, element_role = AXUIElementCopyAttributeValue(element, "AXRole")
        err, element_title = AXUIElementCopyAttributeValue(element, "AXTitle")
        
        if role and str(element_role) == role:
            if label and label.lower() in str(element_title or "").lower():
                return element
        
        err, children = AXUIElementCopyAttributeValue(element, "AXChildren")
        if children:
            for child in children:
                found = await self._find_element(child, role, label)
                if found:
                    return found
        return None
```

## 6.4 Screen Vision Agent

```python
# backend/agents/screen_vision.py

import Vision
import ScreenCaptureKit
from PIL import Image

class ScreenVisionAgent:
    """
    Visual understanding using ScreenCaptureKit + Vision OCR.
    
    Enables Jarvis to "see" what's on screen.
    
    Permission Required: Screen Recording
    """
    
    id = "screen_vision"
    
    TOOLS = [
        {"name": "capture_screen", "permission": "screen_recording", "macos_api": "ScreenCaptureKit"},
        {"name": "extract_text", "permission": "screen_recording", "macos_api": "Vision"},
        {"name": "find_text_location", "permission": "screen_recording", "macos_api": "Vision"},
        {"name": "describe_screen", "permission": "screen_recording", "macos_api": "Vision+LLM"}
    ]
    
    async def extract_text(self, region: dict = None) -> str:
        """
        Extract all text from screen using Vision OCR.
        
        Supports 18+ languages with 99%+ accuracy.
        """
        screenshot = await self._capture()
        
        if region:
            screenshot = self._crop(screenshot, region)
        
        # Vision framework OCR
        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        
        handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(
            screenshot.CGImage(), None
        )
        handler.performRequests_error_([request], None)
        
        observations = request.results()
        text_lines = []
        for obs in observations:
            text_lines.append(obs.topCandidates_(1)[0].string())
        
        return "\n".join(text_lines)
```

## 6.5 Permission Manager

```python
# backend/core/permissions.py

import subprocess
from typing import List, Dict

class PermissionManager:
    """
    Manages macOS permission checking and user guidance.
    
    Jarvis cannot REQUEST permissions - it can only CHECK 
    if they're granted and guide users to enable them.
    """
    
    PERMISSIONS = {
        "accessibility": {
            "check": lambda: subprocess.run(
                ["osascript", "-e", 'tell application "System Events" to return name of every process'],
                capture_output=True
            ).returncode == 0,
            "settings": "Privacy_Accessibility"
        },
        "screen_recording": {
            "check": lambda: True,  # Checked when first used
            "settings": "Privacy_ScreenCapture"
        },
        "calendar": {
            "check": lambda: subprocess.run(
                ["osascript", "-e", 'tell application "Calendar" to return name of calendars'],
                capture_output=True
            ).returncode == 0,
            "settings": "Privacy_Calendars"
        },
        "contacts": {
            "check": lambda: subprocess.run(
                ["osascript", "-e", 'tell application "Contacts" to return count of people'],
                capture_output=True
            ).returncode == 0,
            "settings": "Privacy_Contacts"
        },
        "full_disk_access": {
            "check": lambda: os.access(os.path.expanduser("~/Library/Mail"), os.R_OK),
            "settings": "Privacy_AllFiles"
        }
    }
    
    async def check(self, permission: str) -> bool:
        """Check if permission is granted."""
        if perm := self.PERMISSIONS.get(permission):
            return perm["check"]()
        return True  # Unknown permission, assume granted
    
    async def get_missing(self, required: List[str]) -> List[Dict]:
        """Get list of missing permissions with guidance."""
        missing = []
        for perm in required:
            if not await self.check(perm):
                info = self.PERMISSIONS[perm]
                missing.append({
                    "name": perm,
                    "settings_url": f"x-apple.systempreferences:com.apple.preference.security?{info['settings']}"
                })
        return missing
```

## 6.6 Skills System (Dynamic Capability Discovery)

Skills are **self-documenting capability bundles** that Jarvis learns from at runtime:

```
skills/
├── data_access/
│   ├── SKILL.md           # LLM reads this to learn capabilities
│   ├── manifest.yaml      # Triggers, permissions, tool definitions
│   └── tools.py           # Implementations
├── ui_automation/
│   ├── SKILL.md
│   ├── manifest.yaml
│   └── tools.py
└── screen_vision/
    ├── SKILL.md
    ├── manifest.yaml
    └── tools.py
```

**Example SKILL.md** (LLM reads this):

```markdown
# UI Automation Skill

## What This Skill Does
Control ANY application's UI using the Accessibility API.
Click buttons, fill forms, read content, navigate menus.

## Available Tools
- click_element(app_name, element_label): Click any button
- type_text(text): Type into focused field
- read_ui(app_name): Read all visible text
- navigate_menu(app_name, menu_path): Open menu items

## Required Permission
Accessibility (System Settings > Privacy & Security)
```

**How it works:**
1. Tony orchestrator detects user intent
2. Loads relevant skills based on triggers
3. Injects SKILL.md into LLM system prompt
4. LLM now "knows" what tools are available
5. No hardcoding required!

---

# 7. RAG Engine

## 7.1 Hybrid Search Approach

Jarvis uses **hybrid search** with **reranking** for best-in-class retrieval:

1. **Vector Search**: Semantic similarity using E5-small embeddings
2. **BM25 Search**: Keyword matching for exact terms
3. **Reciprocal Rank Fusion (RRF)**: Combines both rankings
4. **ColBERT Reranking**: Neural reranking for precision (Feb 2026 upgrade)

**Why this pipeline?**
- Vector alone misses exact keywords
- BM25 alone misses semantic meaning
- RRF gets best of both
- ColBERT reranks for final precision boost

> [!TIP]
> ColBERT reranking adds ~50ms latency but improves relevance by ~15%.

## 6.2 Implementation

```python
# backend/core/rag.py

from sentence_transformers import SentenceTransformer
import lancedb
from rank_bm25 import BM25Okapi
import numpy as np

class RAGEngine:
    """
    Hybrid RAG with vector + keyword search.
    
    Uses E5-small for embeddings (384d, fast, accurate).
    Stores in LanceDB (local, serverless).
    Combines with BM25 using Reciprocal Rank Fusion.
    """
    
    def __init__(self, db_path: str = "data/lancedb"):
        self.embedder = SentenceTransformer("intfloat/e5-small-v2")
        self.db = lancedb.connect(db_path)
        self._init_table()
        self.bm25 = None
        self.documents = []
    
    def _init_table(self):
        """Initialize vector table."""
        if "knowledge" not in self.db.table_names():
            import pyarrow as pa
            schema = pa.schema([
                ("id", pa.string()),
                ("text", pa.string()),
                ("source", pa.string()),
                ("vector", pa.list_(pa.float32(), 384)),
            ])
            self.db.create_table("knowledge", schema=schema)
    
    async def add_document(self, text: str, source: str):
        """Add document to knowledge base."""
        import uuid
        
        # Chunk large documents
        chunks = self._chunk_text(text)
        
        for i, chunk in enumerate(chunks):
            vector = self.embedder.encode(f"passage: {chunk}").tolist()
            self.db["knowledge"].add([{
                "id": f"{uuid.uuid4()}_{i}",
                "text": chunk,
                "source": source,
                "vector": vector
            }])
        
        await self._rebuild_bm25()
    
    async def retrieve(self, query: str, top_k: int = 5) -> list:
        """Hybrid retrieval with RRF."""
        
        # Vector search
        query_vec = self.embedder.encode(f"query: {query}").tolist()
        vector_results = self.db["knowledge"].search(query_vec).limit(top_k * 2).to_list()
        
        # BM25 search
        bm25_results = self._bm25_search(query, top_k * 2)
        
        # Reciprocal Rank Fusion
        return self._rrf(vector_results, bm25_results)[:top_k]
    
    def _chunk_text(self, text: str, size: int = 512) -> list:
        """Split text into overlapping chunks."""
        words = text.split()
        chunks = []
        for i in range(0, len(words), size - 50):
            chunks.append(" ".join(words[i:i + size]))
        return chunks
    
    def _bm25_search(self, query: str, k: int) -> list:
        """Keyword search with BM25."""
        if not self.bm25:
            return []
        scores = self.bm25.get_scores(query.lower().split())
        top_idx = np.argsort(scores)[::-1][:k]
        return [self.documents[i] for i in top_idx if scores[i] > 0]
    
    def _rrf(self, vec: list, bm25: list, k: int = 60) -> list:
        """Combine with Reciprocal Rank Fusion."""
        scores = {}
        docs = {}
        
        for rank, doc in enumerate(vec):
            doc_id = doc.get("id", doc["text"][:50])
            scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank + 1)
            docs[doc_id] = doc
        
        for rank, doc in enumerate(bm25):
            doc_id = doc.get("id", doc["text"][:50])
            scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank + 1)
            if doc_id not in docs:
                docs[doc_id] = doc
        
        sorted_ids = sorted(scores.keys(), key=lambda x: scores[x], reverse=True)
        return [{**docs[d], "score": scores[d]} for d in sorted_ids]
    
    async def _rebuild_bm25(self):
        """Rebuild BM25 index."""
        all_docs = self.db["knowledge"].to_list()
        self.documents = all_docs
        tokenized = [d["text"].lower().split() for d in all_docs]
        self.bm25 = BM25Okapi(tokenized) if tokenized else None
```

---

# 7. Memory System

## 7.1 Cognee GraphRAG

**What Cognee does:**
1. Stores conversations
2. Extracts entities automatically (names, projects, topics)
3. Creates relationships (User → works_on → Project)
4. Enables graph + vector search for recall

**Why GraphRAG?**
- "What project am I working on?" → Graph traversal
- "Remember when we discussed APIs?" → Vector search
- Combination is more powerful than either alone

## 7.2 Implementation

```python
# backend/memory/cognee_memory.py

import os
from cognee import Cognee

class CogneeMemory:
    """
    Long-term memory using Cognee GraphRAG.
    
    Automatically extracts entities and relationships.
    Enables recall of past conversations and facts.
    """
    
    def __init__(self, data_path: str = "data/cognee"):
        os.environ["GRAPH_DATABASE_PROVIDER"] = "kuzu"  # Local graph
        os.environ["VECTOR_DATABASE_PROVIDER"] = "lancedb"  # Local vector
        os.environ["COGNEE_DATA_PATH"] = data_path
        self.engine = Cognee()
    
    async def store(self, content: str, metadata: dict = None):
        """
        Store content with automatic entity extraction.
        
        Cognee will:
        1. Parse the content
        2. Extract entities (names, topics, etc.)
        3. Create relationships
        4. Store in graph and vector DB
        """
        try:
            await self.engine.add(content, metadata=metadata or {})
            await self.engine.cognify()  # Process and extract
        except Exception as e:
            print(f"Memory store error: {e}")
    
    async def recall(self, query: str, limit: int = 5) -> list:
        """
        Recall memories using hybrid graph + vector search.
        
        Returns relevant past conversations and extracted facts.
        """
        try:
            results = await self.engine.search(query, limit=limit)
            return [
                {
                    "content": r.content,
                    "entities": getattr(r, "entities", []),
                    "relevance": getattr(r, "score", 0)
                }
                for r in results
            ]
        except Exception as e:
            print(f"Memory recall error: {e}")
            return []
    
    async def get_related(self, entity: str) -> list:
        """Get entities related to a given entity via graph."""
        try:
            return await self.engine.get_graph_neighbors(entity)
        except:
            return []
```

---

# 8. Voice Pipeline

## 8.1 Architecture

```
Audio In → VAD → STT → Tony → TTS → Audio Out
   │         │     │      │      │        │
   │    Silero  Speech-   AI   Piper    Speaker
   │    v6.2   Analyzer       1.6.1
   │    (<1ms)  (45s/34min)  (stream)
   │
   └── Interruption: User speaks → TTS stops immediately
```

> **Latency Budget:**
> - VAD: <1ms (Silero on CPU)
> - STT: 50-200ms (SpeechAnalyzer streaming)
> - Tony: 300-500ms (LLM processing)
> - TTS: Streaming (starts immediately)
> - **Total: 800-1200ms** (realistic)

## 8.2 Implementation

```python
# backend/voice/pipeline.py

from pipecat.vad import SileroVADAnalyzer

class JarvisVoicePipeline:
    """
    Voice pipeline with realistic latency (800-1200ms end-to-end).
    
    Key features:
    - macOS 26 SpeechAnalyzer (55% faster than Whisper)
    - Silero VAD v6.2 for turn detection
    - Piper 1.6.1 streaming TTS
    - Interruption handling
    """
    
    def __init__(self, on_transcription, on_response):
        self.on_transcription = on_transcription
        self.on_response = on_response
        
        self.vad = SileroVADAnalyzer(
            sample_rate=16000,
            min_speech_duration_ms=250,
            min_silence_duration_ms=300,
            threshold=0.5
        )
        
        from .tts import PiperTTS
        from .stt import SpeechAnalyzerSTT  # macOS 26 native
        
        self.tts = PiperTTS()
        self.stt = SpeechAnalyzerSTT()  # 55% faster than Whisper
        
        self.is_listening = False
        self.is_speaking = False
        self.audio_buffer = []
    
    async def process_audio(self, chunk: bytes):
        """Process incoming audio chunk."""
        vad_result = self.vad.analyze(chunk)
        
        if vad_result.is_speech:
            # Interrupt if speaking
            if self.is_speaking:
                await self.stop_speaking()
            
            self.audio_buffer.append(chunk)
            self.is_listening = True
            
        elif self.is_listening and vad_result.is_silence:
            # End of speech
            if len(self.audio_buffer) > 5:
                audio = b"".join(self.audio_buffer)
                text = await self.stt.transcribe(audio)
                if text.strip():
                    await self.on_transcription(text)
            
            self.audio_buffer = []
            self.is_listening = False
    
    async def speak(self, text: str):
        """Stream TTS output."""
        self.is_speaking = True
        async for chunk in self.tts.stream(text):
            if not self.is_speaking:
                break
            await self.on_response(chunk)
        self.is_speaking = False
    
    async def stop_speaking(self):
        """Interrupt TTS."""
        self.is_speaking = False
        await self.tts.stop()
```

---

# 9. API Server

```python
# backend/api/websocket.py

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from contextlib import asynccontextmanager

app = FastAPI()

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    """Main WebSocket handler."""
    await ws.accept()
    
    try:
        while True:
            data = await ws.receive_json()
            
            if data["type"] == "chat":
                async for resp in tony.process(
                    data["content"],
                    JarvisMode(data["mode"]),
                    data.get("session_id")
                ):
                    await ws.send_json({
                        "type": resp.type.value,
                        "data": resp.data
                    })
            
            elif data["type"] == "list_models":
                models = await model_manager.discover_all_models()
                await ws.send_json({"type": "models", "data": {"models": models}})
    
    except WebSocketDisconnect:
        pass
```

---

# 10. Error Handling

## Strategy

| Error | Detection | Recovery |
|-------|-----------|----------|
| Model offline | Health check | Switch provider |
| Tool timeout | 30s limit | Retry once |
| Permission | AppleScript error | Request access |
| Network | HTTP exception | Retry 3x |
| Rate limit | 429 | Backoff |

```python
async def execute_with_retry(func, max_retries=3):
    """Execute with exponential backoff."""
    for attempt in range(max_retries):
        try:
            return await func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            await asyncio.sleep(2 ** attempt)
```

---

**Continue to Part 4: Scenarios & Implementation →**
