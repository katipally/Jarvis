---
name: Jarvis Complete Blueprint
overview: A comprehensive system blueprint for rebuilding Jarvis as a unified, modern AI assistant that combines the best patterns from Agent Zero, Cognee, Pipecat, Liquid Glass, and other leading AI frameworks. This document covers architecture, technology stack, data flows, UI/UX design, and complete system specifications.
todos:
  - id: phase-1-agent
    content: "Phase 1: Core Agent Refactor - Implement new LangGraph state schema, intent classifier, planning node, unified streaming"
    status: completed
  - id: phase-2-memory
    content: "Phase 2: Memory System - Set up knowledge graph, entity extraction, hybrid search, memory consolidation"
    status: completed
  - id: phase-3-voice
    content: "Phase 3: Voice Pipeline - Integrate Deepgram STT, Chatterbox TTS, VAD, interruption handling"
    status: completed
  - id: phase-4-ui
    content: "Phase 4: UI/UX Refresh - Full Liquid Glass design system, Plan Stepper, mode selector, animations"
    status: completed
  - id: phase-5-integration
    content: "Phase 5: Integration & Polish - E2E testing, performance optimization, accessibility, documentation"
    status: in_progress
isProject: false
---

# Jarvis: Complete System Blueprint

**Version:** 2.0 | **Date:** January 2026 | **Status:** Design Phase

---

## Executive Summary

This blueprint defines the complete architecture for Jarvis, a unified AI assistant that combines:

- **Agent Zero's** multi-agent orchestration and persistent memory
- **Cognee's** knowledge graph for semantic understanding
- **Pipecat's** real-time voice pipeline
- **Chatterbox's** high-quality TTS
- **Liquid Glass** design language for iOS/macOS 26
- **Goose's** MCP tool integration pattern
- **OpenManus's** browser automation

The result: One Jarvis, multiple interaction surfaces (Chat, Focus, Conversation, Ray), unified memory, intent-aware planning, and seamless tool orchestration.

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           INTERACTION SURFACES                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │    Chat     │  │    Focus    │  │ Conversation│  │     Ray     │            │
│  │  (Window)   │  │   (Panel)   │  │   (Voice)   │  │ (Spotlight) │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
└─────────┼────────────────┼────────────────┼────────────────┼────────────────────┘
          │                │                │                │
          └────────────────┴────────┬───────┴────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────────────┐
│                         UNIFIED FRONTEND LAYER                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  JarvisCore (Shared State Manager)                                       │    │
│  │  • SessionManager: conversation_id, mode (reasoning/fast)               │    │
│  │  • MemoryBridge: connects to backend memory system                      │    │
│  │  • StreamClient: unified SSE/WebSocket client                           │    │
│  │  • PlanRenderer: displays plans and step completions                    │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐   │
│  │   VoicePipeline      │  │   DesignSystem       │  │   ToolVisualizer     │   │
│  │   (Pipecat-style)    │  │   (Liquid Glass)     │  │   (Plan + Steps)     │   │
│  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                          HTTP/SSE + WebSocket
                                    │
┌───────────────────────────────────▼─────────────────────────────────────────────┐
│                              BACKEND API GATEWAY                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  FastAPI Server                                                          │    │
│  │  • /api/chat/stream (SSE) - Text interactions                           │    │
│  │  • /api/ws/conversation (WebSocket) - Voice interactions                │    │
│  │  • /api/sessions/* - Session management                                 │    │
│  │  • /api/memory/* - Memory operations                                    │    │
│  │  • /api/tools/* - Tool registry and execution                           │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────────────┐
│                           JARVIS AGENT CORE                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  LangGraph Orchestrator                                                  │    │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                │    │
│  │  │ Intent Router │→ │    Planner    │→ │   Executor    │                │    │
│  │  │ (Q/A/Mixed)   │  │ (Reasoning)   │  │ (Tool Loop)   │                │    │
│  │  └───────────────┘  └───────────────┘  └───────────────┘                │    │
│  │                              │                                            │    │
│  │  ┌───────────────────────────▼────────────────────────────────────────┐  │    │
│  │  │  State: mode, intent, plan[], messages, memory_context, tool_calls │  │    │
│  │  └────────────────────────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────────────┐
│   MEMORY LAYER      │  │     TOOL LAYER      │  │     VOICE LAYER             │
│   (Cognee-style)    │  │     (MCP-based)     │  │     (Pipecat-style)         │
│ ┌─────────────────┐ │  │ ┌─────────────────┐ │  │ ┌─────────────────────────┐ │
│ │ Knowledge Graph │ │  │ │ Mac Automation  │ │  │ │ STT (Whisper/Deepgram)  │ │
│ │ (Neo4j/Chroma)  │ │  │ │ Browser Control │ │  │ │ TTS (Chatterbox)        │ │
│ │                 │ │  │ │ File Processor  │ │  │ │ VAD (Silero)            │ │
│ │ - Entities      │ │  │ │ Web Search      │ │  │ │ Interruption Handler    │ │
│ │ - Relations     │ │  │ │ Calendar/Mail   │ │  │ │ Audio Pipeline          │ │
│ │ - Embeddings    │ │  │ │ MCP Servers     │ │  │ └─────────────────────────┘ │
│ └─────────────────┘ │  │ └─────────────────┘ │  └─────────────────────────────┘
│ ┌─────────────────┐ │  └─────────────────────┘
│ │ Session Memory  │ │
│ │ (Redis/SQLite)  │ │
│ └─────────────────┘ │
└─────────────────────┘
```

---

## 2. Technology Stack

### 2.1 Backend Stack


| Component               | Technology                     | Purpose                                        | Reference  |
| ----------------------- | ------------------------------ | ---------------------------------------------- | ---------- |
| **Framework**           | FastAPI 0.115+                 | Async API, WebSocket, SSE                      | Current    |
| **Agent Orchestration** | LangGraph 0.3+                 | State graphs, checkpointing, durable execution | Agent Zero |
| **LLM**                 | OpenAI GPT-5 / Claude Opus 4.5 | Primary reasoning model                        | -          |
| **Fast Model**          | GPT-5-nano / Claude Haiku      | Quick responses, intent classification         | -          |
| **Embeddings**          | OpenAI text-embedding-3-large  | Semantic search                                | -          |
| **Vector Store**        | ChromaDB / Qdrant              | Embedding storage and retrieval                | Current    |
| **Graph Store**         | Neo4j / NetworkX               | Knowledge graph relationships                  | Cognee     |
| **Relational DB**       | SQLite / PostgreSQL            | Conversations, sessions, metadata              | Current    |
| **Cache**               | Redis                          | Session state, rate limiting, checkpoints      | LangGraph  |
| **Voice STT**           | Deepgram / Whisper             | Real-time transcription                        | Pipecat    |
| **Voice TTS**           | Chatterbox Turbo               | High-quality speech synthesis                  | Chatterbox |
| **Voice VAD**           | Silero VAD                     | Voice activity detection                       | Pipecat    |
| **Tool Protocol**       | MCP (Model Context Protocol)   | Extensible tool integration                    | Goose      |
| **Browser**             | Playwright / Vibium            | Browser automation                             | Vibium     |


### 2.2 Frontend Stack (macOS/iOS)


| Component         | Technology              | Purpose                   | Reference       |
| ----------------- | ----------------------- | ------------------------- | --------------- |
| **UI Framework**  | SwiftUI 6.0             | Declarative UI            | Current         |
| **Design System** | Liquid Glass            | iOS 26 material design    | Apple WWDC 2025 |
| **Architecture**  | MVVM + Coordinators     | State management          | Current         |
| **Networking**    | URLSession              | SSE/WebSocket client      | Current         |
| **Audio**         | AVFoundation + AudioKit | Audio capture/playback    | Pipecat         |
| **Speech**        | Speech Framework        | Fallback STT              | Current         |
| **Notifications** | UserNotifications       | System alerts             | Current         |
| **Accessibility** | Accessibility APIs      | Screen readers, VoiceOver | Apple           |


---

## 3. Agent System Design

### 3.1 Single Agent, Multiple Modes

```
┌─────────────────────────────────────────────────────────────────┐
│                     JARVIS AGENT                                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    MODE SELECTOR                         │    │
│  │  ┌─────────────────┐    ┌─────────────────────────────┐ │    │
│  │  │   REASONING     │    │         FAST               │ │    │
│  │  │                 │    │                             │ │    │
│  │  │ • Complex tasks │    │ • Simple Q&A               │ │    │
│  │  │ • Multi-step    │    │ • Single action            │ │    │
│  │  │ • Planning      │    │ • Quick lookup             │ │    │
│  │  │ • Tool chains   │    │ • Voice responses          │ │    │
│  │  │ • Verification  │    │ • Ray quick results        │ │    │
│  │  │                 │    │                             │ │    │
│  │  │ GPT-5 / Opus    │    │ GPT-5-nano / Haiku         │ │    │
│  │  │ High tokens     │    │ Low tokens                 │ │    │
│  │  │ ~2-5s latency   │    │ ~200-500ms latency         │ │    │
│  │  └─────────────────┘    └─────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   INTENT CLASSIFIER                      │    │
│  │                                                          │    │
│  │  User Input → [Classify] → Question | Action | Mixed    │    │
│  │                                                          │    │
│  │  Question: "What's the weather?" → Fast mode, answer    │    │
│  │  Action: "Open Safari and search..." → Reasoning, plan  │    │
│  │  Mixed: "What's the weather and open my calendar?"      │    │
│  │         → Reasoning, plan with answer + action steps    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 LangGraph State Schema

```python
from typing import TypedDict, Literal, Optional, List
from langgraph.graph import add_messages

class PlanStep(TypedDict):
    id: str
    description: str
    status: Literal["pending", "running", "completed", "failed"]
    tool_name: Optional[str]
    result: Optional[str]

class JarvisState(TypedDict):
    # Core
    messages: Annotated[list, add_messages]
    conversation_id: str
    
    # Mode & Intent
    mode: Literal["reasoning", "fast"]
    intent: Literal["question", "action", "mixed"]
    
    # Planning (Reasoning mode)
    plan: List[PlanStep]
    current_step_index: int
    
    # Memory Context (Cognee-style)
    memory_context: dict  # Retrieved from knowledge graph
    session_memory: dict  # Current session facts
    
    # Tool State
    tool_calls: list
    pending_tools: list
    
    # RAG Context
    file_context: list
    rag_results: list
    search_results: list
    
    # Voice (for Conversation mode)
    voice_config: dict  # TTS voice, speed, etc.
    
    # Guardrails
    tool_call_count: int
    error_count: int
```

### 3.3 LangGraph Workflow

```
                    ┌─────────────────┐
                    │      START      │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Load Memory    │ ← Query knowledge graph
                    │  Context        │   for relevant entities
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Classify Intent │ ← Fast model determines
                    │ & Select Mode   │   question/action/mixed
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
    ┌─────────▼─────┐ ┌──────▼──────┐ ┌────▼─────────┐
    │   QUESTION    │ │    ACTION   │ │    MIXED     │
    │   (Fast)      │ │  (Reasoning)│ │  (Reasoning) │
    └───────┬───────┘ └──────┬──────┘ └──────┬───────┘
            │                │               │
    ┌───────▼───────┐ ┌──────▼──────┐ ┌──────▼───────┐
    │  Direct LLM   │ │   Planner   │ │   Planner    │
    │   Answer      │ │  (Generate  │ │  (Generate   │
    │               │ │   Plan)     │ │   Plan)      │
    └───────┬───────┘ └──────┬──────┘ └──────┬───────┘
            │                │               │
            │         ┌──────▼──────┐ ┌──────▼───────┐
            │         │  Executor   │ │  Executor    │
            │         │  (Run Step) │ │  (Run Step)  │
            │         └──────┬──────┘ └──────┬───────┘
            │                │               │
            │         ┌──────▼──────────────▼┐
            │         │   Should Continue?   │
            │         │   (check step status)│
            │         └──────────┬───────────┘
            │                    │
            │         ┌──Yes─────┴─────No───┐
            │         ▼                     ▼
            │   [Loop to Executor]   ┌──────────┐
            │                        │ Summarize│
            │                        └────┬─────┘
            │                             │
            └──────────────┬──────────────┘
                           │
                  ┌────────▼────────┐
                  │  Update Memory  │ ← Store new facts
                  │  & Respond      │   in knowledge graph
                  └────────┬────────┘
                           │
                  ┌────────▼────────┐
                  │      END        │
                  └─────────────────┘
```

---

## 4. Memory System (Cognee-Inspired)

### 4.1 Dual-Store Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      JARVIS MEMORY SYSTEM                        │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  KNOWLEDGE GRAPH (Neo4j)                 │    │
│  │                                                          │    │
│  │  ┌─────────┐    ┌─────────┐    ┌─────────┐              │    │
│  │  │ Entity  │───▶│Relation │───▶│ Entity  │              │    │
│  │  │ "User"  │    │"works_at"│   │"Company"│              │    │
│  │  └─────────┘    └─────────┘    └─────────┘              │    │
│  │                                                          │    │
│  │  • Entities: People, Places, Concepts, Files, Actions   │    │
│  │  • Relations: works_at, mentioned_in, related_to, etc.  │    │
│  │  • Properties: timestamps, confidence, source           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  VECTOR STORE (ChromaDB)                 │    │
│  │                                                          │    │
│  │  ┌──────────────────────────────────────────────────┐   │    │
│  │  │ Collection: jarvis_memory                         │   │    │
│  │  │                                                   │   │    │
│  │  │ Document → Embedding → Metadata                   │   │    │
│  │  │ "User prefers..." → [0.12, ...] → {type: pref}   │   │    │
│  │  └──────────────────────────────────────────────────┘   │    │
│  │                                                          │    │
│  │  Collections:                                            │    │
│  │  • jarvis_memory - Long-term facts and preferences      │    │
│  │  • jarvis_documents - Uploaded file chunks              │    │
│  │  • jarvis_conversations - Past conversation summaries   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                SESSION STORE (Redis/SQLite)              │    │
│  │                                                          │    │
│  │  • Current conversation context                         │    │
│  │  • LangGraph checkpoints (for resumability)             │    │
│  │  • Temporary tool results                                │    │
│  │  • Rate limiting state                                   │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Memory Operations

```python
# Memory API (backend/services/memory_service.py)

class MemoryService:
    async def remember(self, fact: str, metadata: dict) -> str:
        """Store a fact in both vector and graph stores"""
        # 1. Extract entities and relations using LLM
        # 2. Create/update graph nodes
        # 3. Generate embedding and store in vector DB
        
    async def recall(self, query: str, k: int = 5) -> MemoryContext:
        """Retrieve relevant context using hybrid search"""
        # 1. Vector similarity search
        # 2. Graph traversal from matched entities
        # 3. Merge and rank results
        
    async def forget(self, entity_id: str) -> bool:
        """Remove information (for privacy/correction)"""
        
    async def consolidate(self, session_id: str) -> None:
        """End-of-session: extract key facts and store"""
```

---

## 5. Tool System (MCP-Based)

### 5.1 Tool Registry Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      MCP TOOL REGISTRY                           │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    BUILT-IN TOOLS                        │    │
│  │                                                          │    │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐           │    │
│  │  │ knowledge  │ │ web_search │ │ calculator │           │    │
│  │  │ .recall()  │ │ .search()  │ │ .compute() │           │    │
│  │  │ .remember()│ │ .scrape()  │ │            │           │    │
│  │  └────────────┘ └────────────┘ └────────────┘           │    │
│  │                                                          │    │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐           │    │
│  │  │   files    │ │  calendar  │ │   email    │           │    │
│  │  │ .read()    │ │ .events()  │ │ .send()    │           │    │
│  │  │ .write()   │ │ .create()  │ │ .search()  │           │    │
│  │  │ .search()  │ │ .remind()  │ │ .draft()   │           │    │
│  │  └────────────┘ └────────────┘ └────────────┘           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  MAC AUTOMATION TOOLS                    │    │
│  │                                                          │    │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐           │    │
│  │  │   apps     │ │  windows   │ │   input    │           │    │
│  │  │ .launch()  │ │ .list()    │ │ .type()    │           │    │
│  │  │ .quit()    │ │ .focus()   │ │ .click()   │           │    │
│  │  │ .list()    │ │ .resize()  │ │ .shortcut()│           │    │
│  │  └────────────┘ └────────────┘ └────────────┘           │    │
│  │                                                          │    │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐           │    │
│  │  │ applescript│ │  shell     │ │ shortcuts  │           │    │
│  │  │ .run()     │ │ .execute() │ │ .run()     │           │    │
│  │  │            │ │            │ │ .list()    │           │    │
│  │  └────────────┘ └────────────┘ └────────────┘           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   BROWSER TOOLS (Vibium)                 │    │
│  │                                                          │    │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐           │    │
│  │  │  browser   │ │   page     │ │  elements  │           │    │
│  │  │ .launch()  │ │ .goto()    │ │ .find()    │           │    │
│  │  │ .close()   │ │ .content() │ │ .click()   │           │    │
│  │  │ .tabs()    │ │ .screenshot()│ .fill()   │           │    │
│  │  └────────────┘ └────────────┘ └────────────┘           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   MCP SERVER CONNECTIONS                 │    │
│  │                                                          │    │
│  │  External MCP servers can be connected dynamically:      │    │
│  │  • Slack MCP Server → messaging tools                   │    │
│  │  • GitHub MCP Server → repo management                  │    │
│  │  • Custom MCP Servers → user-defined tools              │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Tool Execution with Safety

```python
class ToolExecutor:
    # Safety guardrails (inspired by Agent Zero)
    BLOCKED_PATTERNS = [
        r"rm\s+-rf",
        r"sudo\s+rm",
        r"format\s+",
        r"delete.*keychain",
        r"system.*shutdown",
    ]
    
    MAX_TOOL_CALLS = 25
    MAX_CONSECUTIVE_ERRORS = 3
    TIMEOUT_SECONDS = 30
    
    async def execute(self, tool_name: str, params: dict, state: JarvisState) -> ToolResult:
        # 1. Check guardrails
        # 2. Log tool call for audit
        # 3. Execute with timeout
        # 4. Update state with result
        # 5. Stream progress to frontend
```

---

## 6. Voice Pipeline (Pipecat-Inspired)

### 6.1 Voice Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    JARVIS VOICE PIPELINE                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                     INPUT PIPELINE                       │    │
│  │                                                          │    │
│  │  Microphone → VAD → STT (Streaming) → Text              │    │
│  │      │         │         │                               │    │
│  │      ▼         ▼         ▼                               │    │
│  │  [Audio]  [Speech    [Deepgram/                          │    │
│  │  Buffer    Detected]  Whisper]                           │    │
│  │                                                          │    │
│  │  Features:                                               │    │
│  │  • Silero VAD for accurate speech detection              │    │
│  │  • Noise suppression (Krisp/Koala)                       │    │
│  │  • Streaming transcription with partial results          │    │
│  │  • Endpoint detection (user stopped speaking)            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    OUTPUT PIPELINE                       │    │
│  │                                                          │    │
│  │  LLM Response → Sentence Split → TTS → Audio Stream     │    │
│  │       │              │             │          │          │    │
│  │       ▼              ▼             ▼          ▼          │    │
│  │  [Streaming   [Natural       [Chatterbox  [Low-latency  │    │
│  │   Tokens]     Breaks]        Turbo]       Playback]     │    │
│  │                                                          │    │
│  │  Features:                                               │    │
│  │  • Sentence-boundary TTS for natural pacing              │    │
│  │  • <200ms latency with Chatterbox Turbo                 │    │
│  │  • Emotion control and paralinguistic tags               │    │
│  │  • Voice cloning from reference audio                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 INTERRUPTION HANDLING                    │    │
│  │                                                          │    │
│  │  User speaks while Jarvis speaking:                      │    │
│  │  1. VAD detects speech → flag interruption               │    │
│  │  2. Cancel TTS playback immediately (<50ms)              │    │
│  │  3. Cancel pending LLM generation                        │    │
│  │  4. Save context sync point (last spoken sentence)       │    │
│  │  5. Process new user input                               │    │
│  │  6. Resume with awareness of interrupted context         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Voice Configuration

```python
class VoiceConfig:
    # STT Configuration
    stt_provider: Literal["deepgram", "whisper", "apple"] = "deepgram"
    stt_model: str = "nova-2"
    stt_language: str = "en-US"
    
    # TTS Configuration  
    tts_provider: Literal["chatterbox", "elevenlabs", "apple"] = "chatterbox"
    tts_model: str = "chatterbox-turbo"
    tts_voice_id: Optional[str] = None  # For voice cloning
    tts_speed: float = 1.0
    tts_emotion: float = 0.5  # 0=monotone, 1=expressive
    
    # VAD Configuration
    vad_threshold: float = 0.5
    vad_min_speech_ms: int = 250
    vad_silence_ms: int = 500
    
    # Pipeline Configuration
    enable_noise_suppression: bool = True
    enable_interruption: bool = True
    sentence_boundary_streaming: bool = True
```

---

## 7. UI/UX Design System

### 7.1 Liquid Glass Foundation

```
┌─────────────────────────────────────────────────────────────────┐
│                   LIQUID GLASS DESIGN SYSTEM                     │
│                   (iOS/macOS 26 Native)                          │
│                                                                  │
│  CORE PRINCIPLES:                                                │
│  • Glass surfaces float above content, never on content         │
│  • Navigation layer = glass; content layer = solid              │
│  • Morphing transitions between related glass elements          │
│  • Adaptive contrast based on background                        │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    GLASS VARIANTS                        │    │
│  │                                                          │    │
│  │  .regular     │  Default, medium transparency           │    │
│  │               │  Use for: toolbars, buttons, nav bars   │    │
│  │               │                                          │    │
│  │  .clear       │  High transparency, for media overlays  │    │
│  │               │  Use for: floating controls over photos │    │
│  │               │                                          │    │
│  │  .identity    │  No effect (conditional disable)        │    │
│  │               │  Use for: accessibility fallback        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    GLASS MODIFIERS                       │    │
│  │                                                          │    │
│  │  .tint(Color)     │  Semantic color (primary actions)   │    │
│  │  .interactive()   │  Press feedback, shimmer, bounce    │    │
│  │                                                          │    │
│  │  Example:                                                │    │
│  │  .glassEffect(.regular.tint(.blue).interactive())       │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Color Palette

```swift
// MARK: - Jarvis Color System

struct JarvisColors {
    // Primary Brand Colors
    static let primary = Color(hex: "#6366F1")        // Indigo
    static let primaryLight = Color(hex: "#818CF8")   // Light Indigo
    static let primaryDark = Color(hex: "#4F46E5")    // Dark Indigo
    
    // Accent Colors (Siri-inspired gradient)
    static let accentPurple = Color(hex: "#A855F7")   // Purple
    static let accentBlue = Color(hex: "#3B82F6")     // Blue
    static let accentPink = Color(hex: "#EC4899")     // Pink
    static let accentTeal = Color(hex: "#14B8A6")     // Teal
    
    // Semantic Colors
    static let success = Color(hex: "#22C55E")        // Green
    static let warning = Color(hex: "#F59E0B")        // Amber
    static let error = Color(hex: "#EF4444")          // Red
    static let info = Color(hex: "#3B82F6")           // Blue
    
    // Surface Colors (Dark Theme)
    static let backgroundPrimary = Color(hex: "#0A0A0F")
    static let backgroundSecondary = Color(hex: "#111118")
    static let surfaceElevated = Color(hex: "#1A1A24")
    static let surfaceOverlay = Color.white.opacity(0.05)
    
    // Surface Colors (Light Theme)
    static let backgroundPrimaryLight = Color(hex: "#FAFAFA")
    static let backgroundSecondaryLight = Color(hex: "#F5F5F5")
    
    // Text Colors
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let textDisabled = Color.white.opacity(0.30)
    
    // Glass Effects
    static let glassStroke = Color.white.opacity(0.15)
    static let glassHighlight = Color.white.opacity(0.20)
    static let glassShadow = Color.black.opacity(0.25)
    
    // Message Bubbles
    static let userBubble = Color(hex: "#6366F1")
    static let assistantBubble = Color(hex: "#1E1E2E")
    static let systemBubble = Color(hex: "#14B8A6").opacity(0.15)
    
    // Mode Indicators
    static let reasoningMode = Color(hex: "#A855F7")  // Purple for "thinking"
    static let fastMode = Color(hex: "#22C55E")       // Green for "quick"
    static let voiceActive = Color(hex: "#EC4899")    // Pink for "listening"
    
    // Gradients
    static var siriGradient: LinearGradient {
        LinearGradient(
            colors: [accentPurple, accentBlue, accentPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var planStepGradient: LinearGradient {
        LinearGradient(
            colors: [primary, accentTeal],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
```

### 7.3 Typography

```swift
// MARK: - Jarvis Typography

struct JarvisTypography {
    // Display (Hero text)
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 24, weight: .semibold, design: .rounded)
    
    // Headlines
    static let headlineLarge = Font.system(size: 20, weight: .semibold)
    static let headlineMedium = Font.system(size: 17, weight: .semibold)
    static let headlineSmall = Font.system(size: 15, weight: .semibold)
    
    // Body
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    
    // Labels
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
    
    // Code/Mono
    static let codeLarge = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let codeMedium = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let codeSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
}
```

### 7.4 Component Library

```
┌─────────────────────────────────────────────────────────────────┐
│                    JARVIS COMPONENT LIBRARY                      │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   GLASS CARD                             │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │    │    │
│  │  │ ░  [Icon]  Title Text                        ░ │    │    │
│  │  │ ░          Subtitle or description           ░ │    │    │
│  │  │ ░                                            ░ │    │    │
│  │  │ ░  Content area with proper padding          ░ │    │    │
│  │  │ ░                                            ░ │    │    │
│  │  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  │  • Corner radius: 16px (containerConcentric)            │    │
│  │  • Border: 0.5px white @ 15% opacity                    │    │
│  │  • Shadow: 10px blur, black @ 10%                       │    │
│  │  • Background: ultraThinMaterial @ 70%                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   GLASS BUTTON                           │    │
│  │                                                          │    │
│  │  ┌─────────────────┐  ┌─────────────────┐               │    │
│  │  │  ░░ Label ░░░░  │  │  ░░ [●] ░░░░░░  │               │    │
│  │  └─────────────────┘  └─────────────────┘               │    │
│  │     Primary              Icon-only                       │    │
│  │                                                          │    │
│  │  States: default, hover, pressed, disabled               │    │
│  │  Styles: .glass (translucent), .glassProminent (opaque)  │    │
│  │  Shapes: capsule, circle, roundedRect                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   MESSAGE BUBBLE                         │    │
│  │                                                          │    │
│  │  User Message (right-aligned):                          │    │
│  │                    ┌─────────────────────────┐          │    │
│  │                    │  Message content here   │ ◀ Blue   │    │
│  │                    │  with tail on right     │          │    │
│  │                    └─────────────────────────┘          │    │
│  │                                                          │    │
│  │  Assistant Message (left-aligned):                      │    │
│  │  ┌─────────────────────────────────────────┐            │    │
│  │  │  [▼ Reasoning]                          │ ◀ Glass   │    │
│  │  │  Response content with markdown         │            │    │
│  │  │  support and code highlighting          │            │    │
│  │  └─────────────────────────────────────────┘            │    │
│  │                                                          │    │
│  │  • User: solid primary color, white text                │    │
│  │  • Assistant: glass background, reasoning dropdown      │    │
│  │  • Animations: slide-in, fade-in for streaming          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   PLAN STEPPER                           │    │
│  │                                                          │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │  ◉────●────●────○────○                            │  │    │
│  │  │  │    │    │    │    │                            │  │    │
│  │  │  ✓    ✓    ◐    ○    ○                            │  │    │
│  │  │  Done Done Run  Wait Wait                         │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                          │    │
│  │  Step States:                                           │    │
│  │  • Pending (○): gray, no fill                           │    │
│  │  • Running (◐): animated gradient, pulsing              │    │
│  │  • Completed (✓): green fill, checkmark                 │    │
│  │  • Failed (✗): red fill, X icon                         │    │
│  │                                                          │    │
│  │  Animations: Step-by-step reveal, progress fill         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   SIRI BLOB (Voice)                      │    │
│  │                                                          │    │
│  │           ┌─────────────────────────┐                   │    │
│  │           │     ╭─────────────╮     │                   │    │
│  │           │   ╭─┘ ░░░░░░░░░░ └─╮   │                   │    │
│  │           │  ╭┘ ░░░░░░░░░░░░░░ ╰╮  │                   │    │
│  │           │  │ ░░░░░░░░░░░░░░░░ │  │                   │    │
│  │           │  ╰╮ ░░░░░░░░░░░░░░ ╭╯  │                   │    │
│  │           │   ╰─╮ ░░░░░░░░░░ ╭─╯   │                   │    │
│  │           │     ╰─────────────╯     │                   │    │
│  │           └─────────────────────────┘                   │    │
│  │                                                          │    │
│  │  States:                                                │    │
│  │  • Idle: subtle breathing animation                     │    │
│  │  • Listening: audio-reactive expansion                  │    │
│  │  • Processing: smooth gradient rotation                 │    │
│  │  • Speaking: output-level reactive pulsing              │    │
│  │                                                          │    │
│  │  Colors: Purple → Blue → Pink gradient (SiriColors)     │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 7.5 Interaction Surface Designs

```
┌─────────────────────────────────────────────────────────────────┐
│               SURFACE 1: CHAT (Main Window)                      │
│                                                                  │
│  ┌──────────┬──────────────────────────────────────────────┐    │
│  │ SIDEBAR  │                CHAT AREA                      │    │
│  │          │                                               │    │
│  │ [🔍]     │  ┌──────────────────────────────────┐        │    │
│  │          │  │  Conversation Title        [⚙️]  │        │    │
│  │ ────────│  └──────────────────────────────────┘        │    │
│  │          │                                               │    │
│  │ Today    │  ┌─────────────────────────────────────────┐ │    │
│  │ ○ Chat 1 │  │                                         │ │    │
│  │ ○ Chat 2 │  │     💬 MESSAGE BUBBLES                  │ │    │
│  │          │  │     (scrollable area)                   │ │    │
│  │ Yesterday│  │                                         │ │    │
│  │ ○ Chat 3 │  │     [Reasoning dropdown]                │ │    │
│  │ ○ Chat 4 │  │     [Plan stepper when active]          │ │    │
│  │          │  │                                         │ │    │
│  │          │  └─────────────────────────────────────────┘ │    │
│  │          │                                               │    │
│  │ [+ New]  │  ┌─────────────────────────────────────────┐ │    │
│  │          │  │ [📎] Type a message...     [Mode▾] [↑] │ │    │
│  │          │  └─────────────────────────────────────────┘ │    │
│  └──────────┴──────────────────────────────────────────────┘    │
│                                                                  │
│  Features:                                                       │
│  • Sidebar: conversation list with search and grouping          │
│  • Mode selector: Reasoning/Fast toggle                         │
│  • File attachments: drag-drop or button                        │
│  • Token/cost display: optional footer                          │
│  • Window size: ~1200x800 default                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│               SURFACE 2: FOCUS (Floating Panel)                  │
│                                                                  │
│  ┌──────────────────────────────────────────────────┐           │
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │           │
│  │ ░ [Focus] [Conversation]               [─] [x] ░ │           │
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │           │
│  │ ░                                              ░ │           │
│  │ ░    When Focus tab active:                   ░ │           │
│  │ ░    ┌─────────────────────────────────┐      ░ │           │
│  │ ░    │ Compact message bubbles         │      ░ │           │
│  │ ░    │ with quick replies              │      ░ │           │
│  │ ░    └─────────────────────────────────┘      ░ │           │
│  │ ░                                              ░ │           │
│  │ ░    When Conversation tab active:            ░ │           │
│  │ ░    ┌─────────────────────────────────┐      ░ │           │
│  │ ░    │     ╭─────────────╮             │      ░ │           │
│  │ ░    │   ╭─┘ SIRI BLOB  └─╮           │      ░ │           │
│  │ ░    │   ╰───────────────╯             │      ░ │           │
│  │ ░    │                                 │      ░ │           │
│  │ ░    │   "Listening..."                │      ░ │           │
│  │ ░    │   [Transcript appears here]     │      ░ │           │
│  │ ░    └─────────────────────────────────┘      ░ │           │
│  │ ░                                              ░ │           │
│  │ ░  ┌────────────────────────────────────────┐ ░ │           │
│  │ ░  │ [🎤] Type or speak...          [Mode▾] │ ░ │           │
│  │ ░  └────────────────────────────────────────┘ ░ │           │
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
│  Size: 380w x 520h                                              │
│  Position: Near menu bar, drops down                            │
│  Glass: Full panel is Liquid Glass                              │
│  Hotkey: ⌘+Shift+J or menu bar click                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│               SURFACE 3: RAY (Spotlight-style)                   │
│                                                                  │
│              ┌────────────────────────────────────┐              │
│              │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │              │
│              │ ░ 🔍 Type to search or ask...    ░ │              │
│              │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │              │
│              │ ░                                ░ │              │
│              │ ░  QUICK ACTIONS                 ░ │              │
│              │ ░  ┌──────┐ ┌──────┐ ┌──────┐   ░ │              │
│              │ ░  │ 📱   │ │ 🧮   │ │ 😀   │   ░ │              │
│              │ ░  │ Apps │ │ Calc │ │Emoji │   ░ │              │
│              │ ░  └──────┘ └──────┘ └──────┘   ░ │              │
│              │ ░                                ░ │              │
│              │ ░  RECENT                        ░ │              │
│              │ ░  ○ Safari                     → ░ │              │
│              │ ░  ○ VS Code                    → ░ │              │
│              │ ░  ○ "What's the weather?"     → ░ │              │
│              │ ░                                ░ │              │
│              │ ░  AI RESULTS (when typing)      ░ │              │
│              │ ░  ┌────────────────────────────┐░ │              │
│              │ ░  │ Quick answer appears here │░ │              │
│              │ ░  │ [Open in Chat →]          │░ │              │
│              │ ░  └────────────────────────────┘░ │              │
│              │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │              │
│              └────────────────────────────────────┘              │
│                                                                  │
│  Size: 680w x 480h                                              │
│  Position: Center of screen                                     │
│  Hotkey: ⌘+Space or ⌘+Shift+Space                              │
│  Behavior: Dismiss on blur, keyboard navigation                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7.6 Animation Guidelines

```swift
// MARK: - Jarvis Animation System

struct JarvisAnimations {
    // Standard Durations
    static let instant: Double = 0.1
    static let fast: Double = 0.2
    static let normal: Double = 0.35
    static let slow: Double = 0.5
    
    // Spring Presets
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.7)
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    
    // Glass Morphing
    static let glassMorph = Animation.spring(response: 0.4, dampingFraction: 0.75)
    
    // Plan Step Transitions
    static let stepReveal = Animation.easeOut(duration: 0.3)
    static let stepComplete = Animation.spring(response: 0.3, dampingFraction: 0.6)
    
    // Message Animations
    static let messageAppear = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let streamingPulse = Animation.easeInOut(duration: 0.5).repeatForever()
    
    // Siri Blob
    static let blobIdle = Animation.easeInOut(duration: 2).repeatForever()
    static let blobListening = Animation.easeInOut(duration: 0.3)
    static let blobGradientRotation = Animation.linear(duration: 3).repeatForever()
    
    // Micro-interactions
    static let buttonPress = Animation.spring(response: 0.15, dampingFraction: 0.5)
    static let hoverScale = Animation.easeOut(duration: 0.15)
}

// Usage Examples:
// withAnimation(JarvisAnimations.bouncy) { isExpanded.toggle() }
// .animation(JarvisAnimations.glassMorph, value: selectedTab)
```

---

## 8. Data Flow (End-to-End)

### 8.1 Text Chat Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    TEXT CHAT DATA FLOW                           │
│                                                                  │
│  1. USER INPUT                                                   │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ User types: "Open Safari and search for AI news"       │  │
│     │ Mode: Reasoning (user toggle or auto-detected)         │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  2. FRONTEND → BACKEND (HTTP POST /api/chat/stream)             │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ {                                                       │  │
│     │   "conversation_id": "conv_123",                       │  │
│     │   "message": "Open Safari and search for AI news",     │  │
│     │   "mode": "reasoning",                                 │  │
│     │   "file_ids": []                                       │  │
│     │ }                                                       │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  3. BACKEND PROCESSING                                           │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ a. Load conversation history from DB                   │  │
│     │ b. Query memory service for context                    │  │
│     │ c. Initialize LangGraph with state                     │  │
│     │ d. Classify intent → "action"                          │  │
│     │ e. Generate plan:                                       │  │
│     │    [1] Launch Safari                                    │  │
│     │    [2] Navigate to search engine                       │  │
│     │    [3] Enter search query                               │  │
│     │    [4] Report results                                   │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  4. STREAMING RESPONSE (SSE)                                     │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ event: plan                                             │  │
│     │ data: {"steps": [...], "status": "started"}            │  │
│     │                                                         │  │
│     │ event: plan_step_update                                 │  │
│     │ data: {"step_id": "1", "status": "running"}            │  │
│     │                                                         │  │
│     │ event: tool                                             │  │
│     │ data: {"name": "launch_app", "args": {"app": "Safari"}}│  │
│     │                                                         │  │
│     │ event: plan_step_update                                 │  │
│     │ data: {"step_id": "1", "status": "completed"}          │  │
│     │                                                         │  │
│     │ event: content                                          │  │
│     │ data: {"text": "I've opened Safari and..."}            │  │
│     │                                                         │  │
│     │ event: done                                              │  │
│     │ data: {"tokens": 450, "cost": 0.002}                   │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  5. FRONTEND RENDERING                                           │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ • Plan stepper appears with 4 steps                    │  │
│     │ • Step 1 animates to "running" (pulsing gradient)      │  │
│     │ • Tool indicator shows "Launching Safari..."           │  │
│     │ • Step 1 animates to "completed" (checkmark)           │  │
│     │ • Steps 2-4 execute similarly                          │  │
│     │ • Final response text streams in                       │  │
│     │ • Token count updates in footer                        │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  6. PERSISTENCE                                                  │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ Backend: Save to conversation_db (SQLite)              │  │
│     │ Memory: Store action facts in knowledge graph          │  │
│     │ Frontend: Update local storage cache                   │  │
│     └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Voice Conversation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   VOICE CONVERSATION DATA FLOW                   │
│                                                                  │
│  1. AUDIO INPUT CAPTURE                                          │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ Microphone → Audio Buffer → VAD (Silero)               │  │
│     │ "Speech detected" → Start STT stream                   │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  2. FRONTEND → BACKEND (WebSocket /api/ws/conversation)         │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ Connection established with session_id                 │  │
│     │                                                         │  │
│     │ → {"type": "audio", "data": "<base64_audio_chunk>"}    │  │
│     │                     OR                                  │  │
│     │ → {"type": "transcript", "text": "What time is it"}    │  │
│     │                                                         │  │
│     │ (Interim transcripts sent for UI feedback)             │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  3. BACKEND STT PROCESSING                                       │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ Deepgram/Whisper streaming transcription               │  │
│     │ Endpoint detection (user stopped speaking)             │  │
│     │ Final transcript: "What time is it"                    │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  4. AGENT PROCESSING (Fast Mode for Voice)                      │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ Intent: question → Fast mode                           │  │
│     │ LLM generates response: "It's 3:45 PM"                 │  │
│     │ Response split by sentence boundaries                  │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  5. TTS SYNTHESIS (Chatterbox Turbo)                            │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ Text → Chatterbox Turbo → Audio stream                 │  │
│     │ Latency: <200ms first audio                            │  │
│     │ Streaming: sentence-by-sentence for natural pacing     │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  6. STREAMING RESPONSE (WebSocket)                               │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ ← {"type": "text_delta", "text": "It's "}              │  │
│     │ ← {"type": "text_delta", "text": "3:45 PM"}            │  │
│     │ ← {"type": "sentence_end"}                              │  │
│     │ ← {"type": "audio", "data": "<base64_audio>"}          │  │
│     │ ← {"type": "text_done"}                                 │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  7. FRONTEND PLAYBACK                                            │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ • Siri blob transitions to "speaking" state            │  │
│     │ • Audio plays through speakers                         │  │
│     │ • Transcript appears in UI                             │  │
│     │ • Blob reactive to audio output levels                 │  │
│     └────────────────────────────────────────────────────────┘  │
│                             │                                    │
│                             ▼                                    │
│  8. INTERRUPTION HANDLING (if user speaks)                      │
│     ┌────────────────────────────────────────────────────────┐  │
│     │ VAD detects speech while playing → Interrupt flag      │  │
│     │ → Cancel audio playback (<50ms)                        │  │
│     │ → Cancel pending TTS                                    │  │
│     │ → Send interrupt signal to backend                     │  │
│     │ → Process new user input                               │  │
│     └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. API Specification

### 9.1 Unified Stream Schema

```typescript
// Event types for both SSE and WebSocket

interface StreamEvent {
  type: 
    | "content"           // Text content chunk
    | "reasoning"         // Reasoning/thinking content
    | "plan"              // Full plan structure
    | "plan_step_update"  // Step status change
    | "tool"              // Tool call info
    | "tool_result"       // Tool execution result
    | "audio"             // TTS audio chunk (voice only)
    | "transcript"        // STT transcript (voice only)
    | "sentence_end"      // TTS sentence boundary (voice only)
    | "error"             // Error message
    | "done";             // Stream complete
  data: any;
}

// Content event
interface ContentEvent extends StreamEvent {
  type: "content";
  data: {
    text: string;
    is_complete: boolean;
  };
}

// Plan event
interface PlanEvent extends StreamEvent {
  type: "plan";
  data: {
    steps: PlanStep[];
    status: "started" | "in_progress" | "completed" | "failed";
  };
}

interface PlanStep {
  id: string;
  description: string;
  status: "pending" | "running" | "completed" | "failed";
  tool_name?: string;
  result?: string;
}

// Plan step update event
interface PlanStepUpdateEvent extends StreamEvent {
  type: "plan_step_update";
  data: {
    step_id: string;
    status: "running" | "completed" | "failed";
    result?: string;
    error?: string;
  };
}

// Done event
interface DoneEvent extends StreamEvent {
  type: "done";
  data: {
    conversation_id: string;
    message_id: string;
    tokens: {
      prompt: number;
      completion: number;
      total: number;
    };
    cost?: number;
  };
}
```

### 9.2 REST Endpoints

```
POST   /api/chat/stream          # SSE streaming chat
POST   /api/chat                 # Non-streaming chat
GET    /api/conversations        # List conversations
POST   /api/conversations        # Create conversation
GET    /api/conversations/{id}   # Get conversation details
DELETE /api/conversations/{id}   # Delete conversation
PATCH  /api/conversations/{id}   # Update conversation (rename)

POST   /api/files/upload         # Upload file for RAG
GET    /api/files/{id}           # Get file info
GET    /api/files/{id}/preview   # Get file preview

GET    /api/memory/search        # Search knowledge graph
POST   /api/memory/add           # Add to memory
DELETE /api/memory/{id}          # Remove from memory

GET    /api/tools                # List available tools
GET    /api/tools/{name}         # Get tool schema

WS     /api/ws/conversation      # WebSocket for voice
```

---

## 10. Implementation Phases

### Phase 1: Core Agent Refactor (Backend)

- Implement new LangGraph state schema with mode/intent/plan
- Add intent classification node
- Add planning node for Reasoning mode
- Implement unified stream schema
- Update API routes for new schema

### Phase 2: Memory System (Backend)

- Set up Neo4j/NetworkX for knowledge graph
- Implement entity/relation extraction
- Create hybrid search (vector + graph)
- Add memory consolidation service
- Integrate with agent state

### Phase 3: Voice Pipeline (Backend + Frontend)

- Integrate Deepgram for STT
- Integrate Chatterbox Turbo for TTS
- Implement VAD with interruption handling
- Add sentence-boundary streaming
- Update ConversationViewModel

### Phase 4: UI/UX Refresh (Frontend)

- Implement full Liquid Glass design system
- Create Plan Stepper component
- Update message bubbles with reasoning
- Redesign Siri blob with new animations
- Add mode selector UI

### Phase 5: Integration & Polish

- End-to-end testing
- Performance optimization
- Accessibility audit
- Documentation

---

## 11. References

### Projects Studied

- [Agent Zero](https://github.com/agent0ai/agent-zero) - Multi-agent framework
- [Cognee](https://github.com/topoteretes/cognee) - AI memory
- [Pipecat](https://github.com/pipecat-ai/pipecat) - Voice AI framework
- [Chatterbox](https://github.com/resemble-ai/chatterbox) - TTS
- [Goose](https://github.com/block/goose) - MCP tools
- [OpenManus](https://github.com/FoundationAgents/OpenManus) - Browser automation
- [Vibium](https://github.com/VibiumDev/vibium) - Browser automation
- [Moltbot](https://github.com/moltbot/moltbot) - Personal AI assistant
- [OpenWork](https://github.com/different-ai/openwork) - Agentic workflows
- [LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) - iOS 26 UI

### Technologies

- [LangGraph](https://langchain-ai.github.io/langgraph/) - Agent orchestration
- [MCP](https://modelcontextprotocol.io/) - Tool protocol
- [iOS 26 Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) - Design system
- [Deepgram](https://deepgram.com/) - Speech-to-text
- [FastAPI](https://fastapi.tiangolo.com/) - Backend framework

---

*This blueprint represents the complete system design for Jarvis 2.0. Each component is designed to work together as a cohesive system while remaining modular for independent development and testing.*