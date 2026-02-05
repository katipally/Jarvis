# JARVIS AI - Complete System Design

> **Version:** 5.2 Final | **Date:** February 3, 2026  
> **Document:** Part 1 of 4 - Architecture & Core Systems (Enhanced)

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture Deep Dive](#2-architecture-deep-dive)
3. [Technology Stack Rationale](#3-technology-stack-rationale)
4. [Flexible LLM System](#4-flexible-llm-system)
5. [Session Management](#5-session-management)
6. [Apple Color System](#6-apple-color-system)
7. [File Structure](#7-file-structure)

---

# 1. System Overview

## 1.1 What is Jarvis?

Jarvis is a **local-first, modular AI assistant** specifically designed for macOS. Unlike cloud-dependent assistants like Siri, Google Assistant, or Alexa, Jarvis prioritizes:

- **Privacy**: All processing happens on your Mac by default
- **Speed**: No network latency for most operations
- **Control**: You choose which AI models to use
- **Power**: Full access to macOS automation capabilities

### Why Build Jarvis?

Existing AI assistants have limitations:

| Assistant | Limitation |
|-----------|------------|
| **Siri** | Limited capabilities, can't control third-party apps well |
| **ChatGPT** | Cloud-only, no Mac integration |
| **Raycast AI** | Good launcher but limited AI depth |
| **Copilot** | Code-focused, not general purpose |

Jarvis combines the best of all worlds: a powerful AI brain with deep macOS integration and multiple interaction modes.

## 1.2 The Four Modes

Jarvis offers **4 distinct interaction modes**, each optimized for different use cases:

### Chat Mode (⌥C)

**Purpose:** Full conversations with context, history, and detailed responses.

**When to use:**
- Complex questions requiring back-and-forth
- Tasks that need explanation
- Research and learning
- Reviewing past conversations

**Design inspiration:** iMessage - familiar, comfortable, feature-rich.

**Window:** 700×500 pixels, resizable, with sidebar for history.

---

### Ray Mode (⌥R)

**Purpose:** Quick actions and launching without breaking flow.

**When to use:**
- Opening apps quickly
- Running shortcuts
- Quick calculations
- Fast web searches

**Design inspiration:** Spotlight - instant, minimal, powerful.

**Window:** 680 pixels wide, auto-height based on results, centered at top.

---

### Conversation Mode (⌥V)

**Purpose:** Hands-free voice interaction.

**When to use:**
- Working with hands busy (cooking, driving)
- Accessibility needs
- Natural conversation preference
- Quick voice commands

**Design inspiration:** Siri 2026 - edge glow around screen, minimal UI.

**Window:** No window - just edge glow overlay on screen.

---

### Focus Mode (⌥F)

**Purpose:** Context-aware assistance based on what you're doing.

**When to use:**
- Coding (explains code on screen)
- Writing (grammar/style help)
- Research (summarize visible content)
- Any screen-based work

**Design inspiration:** Copilot side panel - small, contextual, helpful.

**Window:** 400×300 pixels, anchored to bottom-right corner.

## 1.3 Core Principles

### Principle 1: Universal LLM Compatibility

**What this means:**
- Jarvis works **identically** with any LLM provider (local or cloud)
- The architecture, streaming, tool calling, and personality are model-agnostic
- The LLM is a swappable backend, not a design constraint
- All data (sessions, memory, knowledge) is stored locally

**Supported Providers:**

| Provider | Type | Setup |
|----------|------|-------|
| Ollama | Local | `ollama serve` |
| OpenAI | Cloud | API key in settings |
| Together/Groq | Cloud | OpenAI-compatible endpoint |
| Anthropic | Cloud | Via adapter |
| Custom | Any | Implement `ModelProvider` protocol |

**Key Point:** Tony orchestrator and all agents work exactly the same regardless of which LLM powers them.

**Trade-offs by Provider:**

| Aspect | Local (Ollama) | Cloud (OpenAI/etc) |
|--------|----------------|-------------------|
| Privacy | Data stays on device | Data sent to cloud |
| Latency | ~100ms faster | Network overhead |
| Quality | Varies by model | GPT-4+ is best |
| Cost | Free (your hardware) | API fees apply |
| Reliability | No internet needed | Requires internet |

### Principle 2: Model Agnostic

**What this means:**
- Jarvis doesn't lock you into any specific LLM
- Dynamically discovers available models from providers
- Switch models anytime via Settings
- Same interface regardless of model

**Supported providers:**
- **Ollama**: Any model installed locally (Llama, Mistral, Qwen, etc.)
- **OpenAI**: GPT-4o, GPT-4 Turbo, GPT-3.5
- **OpenAI-compatible**: Together, Groq, Anthropic proxy, local servers

### Principle 3: Unified Context

**What this means:**
- Information flows between ALL modes
- Ask a question in Chat → Reference it in Voice
- Session history visible across modes
- Memory persists between sessions

**Example flow:**
1. Chat: "I'm working on the authentication system"
2. Voice: "Show me the auth code" → Jarvis knows what "auth" means
3. Ray: "auth tests" → Opens authentication test files

### Principle 4: Native Experience

**What this means:**
- Uses Apple design language exclusively
- System colors that adapt to light/dark mode
- Native animations and interactions
- Feels like a first-party Apple app

### Principle 5: Jarvis Personality

**What this means:**
Jarvis has a **consistent, defined personality** that makes every interaction feel natural and engaging. Unlike generic chatbots, Jarvis has character.

**Jarvis's Personality Traits:**

| Trait | Description | Example |
|-------|-------------|---------|
| **Helpful** | Prioritizes solving user's needs efficiently | "Done! I opened Safari and searched for 'AI news'" |
| **Warm** | Friendly and approachable, never cold or robotic | "Good morning! Ready to help you tackle the day" |
| **Witty** | Occasional light humor, never at user's expense | "I could search the web, but your WiFi seems to have taken a coffee break" |
| **Competent** | Confident but humble, admits limitations | "I'm not able to access your Messages directly, but I can help you draft one" |
| **Concise** | Gets to the point, respects user's time | Prefers "Safari's open" over lengthy explanations |
| **Proactive** | Anticipates needs, offers relevant follow-ups | "I found 10 results. Want me to open the most recent one?" |

**Voice & Language Guidelines:**

```python
# backend/core/personality.py

JARVIS_SYSTEM_PROMPT = """
You are Jarvis, an intelligent macOS assistant with a warm, capable personality.

PERSONALITY CORE:
- Be helpful first, clever second
- Use natural, conversational language
- Match the user's energy (brief input → brief response)
- Show personality through word choice, not excessive commentary
- Never be sycophantic or over-apologetic

RESPONSE STYLE BY MODE:
- Chat Mode: Conversational, can be more detailed and engaging
- Ray Mode: Ultra-concise, action-focused ("Opening Safari")
- Voice Mode: Natural speech, complete sentences, easy to hear
- Focus Mode: Context-aware, tied to what's on screen

TONE EXAMPLES:
✓ "Got it! Safari is now open to GitHub."
✓ "Hmm, that file doesn't seem to exist. Want me to create it?"
✓ "I've set your volume to 50%. Anything else?"
✗ "I would be delighted to assist you with opening Safari!"
✗ "I apologize for any inconvenience, but I cannot..."
✗ "Certainly! I shall now proceed to..."

PERSONALITY ACROSS MODES:
- Same core personality, different formality levels
- Voice Mode: slightly warmer (you're having a conversation)
- Ray Mode: more direct (user wants speed)
- Focus Mode: more technical (user is working)
"""
```

**How Personality is Implemented:**
1. **System Prompt**: Every LLM call includes personality guidelines
2. **Response Templates**: Common actions have pre-defined, personality-aligned responses  
3. **Error Messages**: Friendly explanations, not technical dumps
4. **Mode Adaptation**: Same personality, tuned for context

---

# 2. Architecture Deep Dive

## 2.1 High-Level Architecture

Jarvis follows a **client-server architecture** with clear separation:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER LAYER                                      │
│                                                                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  CHAT MODE   │ │  FOCUS MODE  │ │  VOICE MODE  │ │   RAY MODE   │        │
│  │   700×500    │ │   400×300    │ │  Edge Glow   │ │   680×auto   │        │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘        │
│         │                │                │                │                 │
│         └────────────────┴────────────────┴────────────────┘                 │
│                                   │                                          │
│                        SwiftUI Frontend (macOS 26)                           │
│                                   │                                          │
│                          WebSocket Connection                                │
│                          (localhost:8765)                                    │
│                                   │                                          │
└───────────────────────────────────┼──────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BACKEND LAYER (Python)                             │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         JARVIS TONY ORCHESTRATOR                        │ │
│  │                                                                         │ │
│  │  The "brain" that coordinates all AI operations:                        │ │
│  │  1. Receives user input                                                 │ │
│  │  2. Classifies intent                                                   │ │
│  │  3. Gathers context (session, RAG, memory)                              │ │
│  │  4. Creates execution plan                                              │ │
│  │  5. Executes tools via agents                                           │ │
│  │  6. Generates response                                                  │ │
│  │  7. Stores to memory                                                    │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   Model Manager │  │   RAG Engine    │  │  Memory Store   │              │
│  │  Ollama/OpenAI  │  │  Vector + BM25  │  │ Cognee GraphRAG │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         AGENT REGISTRY                                  │ │
│  │  13 specialized agents with 53 tools for Mac control                   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2.2 Why Client-Server?

**Alternative considered:** Single SwiftUI app with embedded Python.

**Why we chose client-server:**

| Aspect | Embedded | Client-Server (Chosen) |
|--------|----------|------------------------|
| Development | Complex bridging | Clean separation |
| Debugging | Harder | Easy (separate logs) |
| Updates | Full app update | Backend-only updates |
| Memory | Shared, can conflict | Isolated |
| Python ecosystem | Limited access | Full access |

## 2.3 Communication Protocol

Jarvis uses **WebSocket** for real-time bidirectional communication:

**Why WebSocket over REST?**
- **Streaming responses**: LLM output streams token-by-token (users see text appear)
- **Real-time updates**: Plan steps update as they complete
- **Voice**: Continuous audio streaming
- **Lower latency**: No connection overhead per message

> **CRITICAL: Streaming is Mandatory**
> 
> Text responses MUST stream in ALL modes. Users should NEVER wait for a complete
> response before seeing/hearing output. This applies to:
> - Chat Mode: Text appears character-by-character
> - Ray Mode: Results appear as they're found
> - Voice Mode: TTS starts before full response is generated
> - Focus Mode: Text streams into the panel

**Message format:**

```json
// Client → Server
{
  "type": "chat",
  "content": "Open Safari",
  "mode": "chat",
  "session_id": "abc123"
}

// Server → Client (Plan)
{
  "type": "plan",
  "data": {
    "summary": "Opening Safari browser",
    "steps": [
      {"id": "1", "description": "Launch Safari.app", "status": "pending"}
    ]
  }
}

// Server → Client (Step Update)
{
  "type": "step_update",
  "data": {
    "step_id": "1",
    "status": "completed",
    "result": "Safari launched successfully"
  }
}

// Server → Client (Content Stream)
{
  "type": "content",
  "data": {"text": "Done! Safari is now open."}
}
```

---

# 3. Technology Stack Rationale

Every technology choice has a specific reason:

## 3.1 Frontend Technologies

### SwiftUI (macOS 26)

**What it is:** Apple's declarative UI framework

**Why we chose it:**
- Native macOS look and feel
- Built-in dark mode support
- Smooth 60fps animations
- Direct access to macOS APIs (Accessibility, Speech, etc.)
- Liquid Glass API support

**Alternatives considered:**
- Electron: Too heavy, not native feel
- Tauri: Good but Swift better for macOS-specific features
- AppKit: More complex, less modern

### GlassEffectContainer (Liquid Glass)

**What it is:** Apple's new translucent material system in macOS 26

**Why we chose it:**
- Official Apple design language
- Adapts to background content automatically
- Consistent with rest of macOS 26
- Built-in accessibility support

**How it works:**
```swift
// The container automatically applies glass to children
GlassEffectContainer {
    VStack {
        Text("This has glass background")
        Button("So does this")
    }
}
.glassEffect(.regular)  // Applies frosted glass
```

### SF Symbols 7

**What it is:** Apple's icon system with 6,000+ symbols

**Why we chose it:**
- Consistent with macOS
- Built-in animations
- Automatic weight matching with text
- Semantic colors

**Animation capabilities:**
```swift
Image(systemName: "checkmark.circle")
    .symbolEffect(.bounce, value: isComplete)  // Bounces on completion
    
Image(systemName: "arrow.clockwise")
    .symbolEffect(.rotate, isActive: isLoading)  // Spins while loading
```

## 3.2 Backend Technologies

### Python 3.12+

**Why Python:**
- Best AI/ML ecosystem (PyTorch, Transformers, etc.)
- Ollama client library
- LangGraph framework
- Faster development for AI features

**Why 3.12+:**
- Better performance
- Improved type hints
- Better async support

### FastAPI

**What it is:** Modern, fast Python web framework

**Why we chose it:**
- Native async support (critical for AI workloads)
- Built-in WebSocket support
- Automatic OpenAPI documentation
- Type validation with Pydantic

**Performance:** Can handle thousands of concurrent WebSocket connections.

### LangGraph 1.0 (Stable - Oct 2025)

**What it is:** Framework for building LLM-powered workflows

**Why we chose it:**
- **Stable API**: Production-ready release (2.0 expected Q2 2026)
- **Durable execution**: Resume interrupted workflows with checkpointing
- **State management**: Track plan progress across steps
- **Tool calling**: Structured agent execution with `create_agent` API
- **Guardrail nodes**: Built-in content filtering and validation

**How Jarvis uses it:**
- Reasoning and planning workflow
- Multi-step task execution
- Parallel tool calls when possible
- Human-in-the-loop interventions

### SetFit 1.1.3

**What it is:** Few-shot text classification library (verified Feb 2026)

**Why we chose it:**
- **Fast**: ~10-15ms inference in production (with warm cache)
- **Few-shot**: Works with 8-16 examples per class
- **Accurate**: 90%+ accuracy on intent classification
- **Small**: ~50MB model size
- **OpenVINO support**: Hardware acceleration available

**Why not alternatives:**
- Full LLM for classification: 100-500ms, overkill
- Rule-based: Not flexible enough
- Large classifier: Too slow for every message

### E5-small-v2 (Embeddings)

**What it is:** Improved embedding model from Microsoft (intfloat)

**Why we chose it:**
- **384 dimensions**: Good balance of quality and speed
- **Fast**: ~5ms per embedding
- **Better than v1**: Improved performance over E5-small
- **Instruction-tuned**: Use "query:" or "passage:" prefixes
- **Multilingual support**: Available via E5-multilingual-small

**Alternative considered:** OpenAI embeddings
- Better quality but requires API call
- Adds latency and cost
- Breaks local-first principle

### LanceDB

**What it is:** Embedded vector database

**Why we chose it:**
- **Serverless**: No separate database process
- **Local storage**: Files on disk
- **Fast**: Written in Rust
- **Hybrid search**: Vector + keyword

**Why not alternatives:**
- Pinecone/Weaviate: Cloud-based
- Chroma: Good but LanceDB is faster
- pgvector: Requires PostgreSQL

### Cognee

**What it is:** GraphRAG memory system

**Why we chose it:**
- **Entity extraction**: Automatically finds entities
- **Relationship tracking**: Knows how things connect
- **Hybrid search**: Graph + vector
- **Local providers**: Kuzu for graph, LanceDB for vectors

**What it does:**
1. Stores conversation: "I'm working on the auth system"
2. Extracts entities: ["auth system", "working"]
3. Creates relationships: User → working_on → auth_system
4. Later recall: "What am I working on?" → "auth system"

### Pipecat (Latest 2026)

**What it is:** Real-time audio/video AI framework

**Why we chose it:**
- **Realistic latency**: 800-1200ms end-to-end (with streaming optimizations)
- **Streaming**: Process audio as it arrives
- **VAD integration**: Silero VAD v6.2 with smart-turn-v2 detection
- **TTS streaming**: Piper 1.6.1 with LLM streaming support

**Key features:**
- Interruption handling: User speaks → Jarvis stops immediately
- VADController: Independent voice activity state management
- Word timestamps for subtitles

---

# 4. Flexible LLM System

## 4.1 Design Philosophy

Jarvis follows the principle: **"User's choice, not ours."**

We don't decide which LLM is "best" - user chooses based on:
- Privacy needs (local vs cloud)
- Quality requirements (GPT-4 vs smaller models)
- Speed preferences (fast local vs slower cloud)
- Cost constraints (free local vs paid API)

## 4.2 Dynamic Model Discovery

**Problem:** Hardcoding model names is bad because:
- Models change frequently
- User's installed models vary
- API availability changes

**Solution:** Query providers dynamically.

### Ollama Discovery

When user selects Ollama, we query `http://localhost:11434/api/tags`:

```json
{
  "models": [
    {"name": "llama3.2:latest", "size": 4500000000},
    {"name": "mistral:7b", "size": 4100000000},
    {"name": "codellama:13b", "size": 7400000000}
  ]
}
```

We display ONLY what's installed - no "download this model" suggestions.

### OpenAI Discovery

When user provides API key, we query `https://api.openai.com/v1/models`:

```json
{
  "data": [
    {"id": "gpt-4o", "owned_by": "openai"},
    {"id": "gpt-4-turbo", "owned_by": "openai"},
    {"id": "gpt-3.5-turbo", "owned_by": "openai"}
  ]
}
```

We filter to show only chat models (not embeddings, whisper, etc.).

## 4.3 Provider Implementation

```python
# backend/core/model_provider.py

from abc import ABC, abstractmethod
from typing import AsyncIterator
import httpx
import json

class ModelProvider(ABC):
    """
    Abstract base class for LLM providers.
    
    All providers must implement:
    1. list_models() - Discover available models
    2. chat() - Stream chat completions
    3. health_check() - Verify provider is available
    """
    
    @abstractmethod
    async def list_models(self) -> list[dict]:
        """
        Discover available models from this provider.
        
        Returns list of dicts with:
        - id: Model identifier to use in API calls
        - name: Human-readable name
        - size_bytes: Model size (for Ollama)
        - provider: Provider name
        - local: Whether model runs locally
        """
        pass
    
    @abstractmethod
    async def chat(self, model: str, messages: list) -> AsyncIterator[str]:
        """
        Stream chat completion.
        
        Args:
            model: Model ID from list_models()
            messages: List of {"role": "user/assistant/system", "content": "..."}
        
        Yields:
            Text chunks as they're generated
        """
        pass
    
    @abstractmethod
    async def health_check(self) -> bool:
        """Check if provider is available."""
        pass


class OllamaProvider(ModelProvider):
    """
    Local Ollama provider.
    
    Ollama runs models directly on the user's Mac.
    - Free (no API costs)
    - Private (data never leaves device)
    - Fast for small models
    - Requires sufficient RAM
    """
    
    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url
        self.name = "ollama"
    
    async def list_models(self) -> list[dict]:
        """
        Get ONLY models installed on this device.
        
        We call /api/tags which returns all pulled models.
        This ensures we never show models user can't use.
        """
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{self.base_url}/api/tags")
                resp.raise_for_status()
                data = resp.json()
                
                models = []
                for model in data.get("models", []):
                    models.append({
                        "id": model["name"],  # e.g., "llama3.2:latest"
                        "name": model["name"].split(":")[0].title(),  # "Llama3.2"
                        "size_bytes": model.get("size", 0),
                        "size_human": self._format_size(model.get("size", 0)),
                        "modified": model.get("modified_at"),
                        "provider": "ollama",
                        "local": True
                    })
                
                return models
                
        except httpx.ConnectError:
            # Ollama not running
            return []
        except Exception as e:
            print(f"Ollama list_models error: {e}")
            return []
    
    async def chat(self, model: str, messages: list) -> AsyncIterator[str]:
        """
        Stream chat from Ollama.
        
        Ollama streams JSON lines with format:
        {"message": {"content": "Hello"}, "done": false}
        {"message": {"content": " world"}, "done": false}
        {"message": {"content": ""}, "done": true}
        """
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/api/chat",
                json={
                    "model": model,
                    "messages": messages,
                    "stream": True
                },
                timeout=120.0  # Long timeout for slow models
            ) as response:
                async for line in response.aiter_lines():
                    if line:
                        try:
                            data = json.loads(line)
                            if content := data.get("message", {}).get("content"):
                                yield content
                        except json.JSONDecodeError:
                            continue
    
    async def health_check(self) -> bool:
        """Check if Ollama is running."""
        try:
            async with httpx.AsyncClient(timeout=2.0) as client:
                resp = await client.get(f"{self.base_url}/api/tags")
                return resp.status_code == 200
        except Exception:
            return False
    
    def _format_size(self, bytes: int) -> str:
        """Convert bytes to human readable."""
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes < 1024:
                return f"{bytes:.1f} {unit}"
            bytes /= 1024
        return f"{bytes:.1f} TB"


class OpenAICompatibleProvider(ModelProvider):
    """
    OpenAI-compatible API provider.
    
    Works with:
    - OpenAI (api.openai.com)
    - Together AI
    - Groq
    - Any OpenAI-compatible endpoint
    
    Requires API key from user.
    """
    
    def __init__(self, base_url: str, api_key: str, name: str = "openai"):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.name = name
    
    async def list_models(self) -> list[dict]:
        """
        Fetch available models from the API.
        
        We filter to show only chat models (not embedding, tts, etc.)
        """
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(
                    f"{self.base_url}/models",
                    headers={"Authorization": f"Bearer {self.api_key}"}
                )
                resp.raise_for_status()
                data = resp.json()
                
                models = []
                for model in data.get("data", []):
                    # Filter to chat models only
                    if not self._is_chat_model(model["id"]):
                        continue
                    
                    models.append({
                        "id": model["id"],
                        "name": model["id"],
                        "provider": self.name,
                        "local": False,
                        "owned_by": model.get("owned_by", "unknown")
                    })
                
                return models
                
        except Exception as e:
            print(f"OpenAI list_models error: {e}")
            return []
    
    async def chat(self, model: str, messages: list) -> AsyncIterator[str]:
        """
        Stream chat from OpenAI-compatible API.
        
        Uses Server-Sent Events (SSE) format:
        data: {"choices": [{"delta": {"content": "Hello"}}]}
        data: {"choices": [{"delta": {"content": " world"}}]}
        data: [DONE]
        """
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": model,
                    "messages": messages,
                    "stream": True
                },
                timeout=120.0
            ) as response:
                async for line in response.aiter_lines():
                    # SSE format: "data: {...}"
                    if line.startswith("data: ") and line != "data: [DONE]":
                        try:
                            data = json.loads(line[6:])  # Skip "data: "
                            content = (
                                data.get("choices", [{}])[0]
                                .get("delta", {})
                                .get("content")
                            )
                            if content:
                                yield content
                        except json.JSONDecodeError:
                            continue
    
    async def health_check(self) -> bool:
        """Check if API is reachable and key is valid."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    f"{self.base_url}/models",
                    headers={"Authorization": f"Bearer {self.api_key}"}
                )
                return resp.status_code == 200
        except Exception:
            return False
    
    def _is_chat_model(self, model_id: str) -> bool:
        """
        Filter to only show chat-capable models.
        
        Excludes: embeddings, whisper, TTS, DALL-E, etc.
        """
        model_lower = model_id.lower()
        
        # Keywords that indicate chat capability
        chat_keywords = ["gpt", "claude", "llama", "mistral", "chat", "instruct"]
        
        # Keywords that indicate non-chat models
        exclude_keywords = ["embed", "whisper", "tts", "dall-e", "moderation"]
        
        has_chat = any(kw in model_lower for kw in chat_keywords)
        has_exclude = any(kw in model_lower for kw in exclude_keywords)
        
        return has_chat and not has_exclude


class ModelManager:
    """
    Central manager for all LLM providers.
    
    Responsibilities:
    1. Register/unregister providers
    2. Discover models from all providers
    3. Track active model selection
    4. Route generation requests
    """
    
    def __init__(self):
        self.providers: dict[str, ModelProvider] = {}
        self.active_provider: str = None
        self.active_model: str = None
    
    def add_provider(self, name: str, provider: ModelProvider):
        """
        Register a provider.
        
        Called during app startup for Ollama.
        Called when user adds API key for OpenAI.
        """
        self.providers[name] = provider
    
    def remove_provider(self, name: str):
        """
        Unregister a provider.
        
        Called when user removes API key.
        """
        if name in self.providers:
            del self.providers[name]
            
            # If we removed the active provider, clear selection
            if self.active_provider == name:
                self.active_provider = None
                self.active_model = None
    
    async def discover_all_models(self) -> list[dict]:
        """
        Get models from ALL configured providers.
        
        This is called when user opens Settings > Models.
        We aggregate models from all providers into one list.
        """
        all_models = []
        
        for name, provider in self.providers.items():
            try:
                # Only query if provider is healthy
                if await provider.health_check():
                    models = await provider.list_models()
                    
                    # Add provider name so UI knows source
                    for model in models:
                        model["provider_name"] = name
                    
                    all_models.extend(models)
            except Exception as e:
                print(f"Failed to get models from {name}: {e}")
                continue
        
        return all_models
    
    def set_active(self, provider_name: str, model_id: str):
        """
        Set the active model for generation.
        
        Called when user selects a model in Settings.
        """
        if provider_name not in self.providers:
            raise ValueError(f"Unknown provider: {provider_name}")
        
        self.active_provider = provider_name
        self.active_model = model_id
        
        # Persist to settings
        self._save_selection()
    
    async def generate(self, messages: list) -> AsyncIterator[str]:
        """
        Generate using the active model.
        
        This is the main interface used by Tony orchestrator.
        """
        if not self.active_provider or not self.active_model:
            raise ValueError("No active model set. Please select a model in Settings.")
        
        provider = self.providers[self.active_provider]
        
        async for chunk in provider.chat(self.active_model, messages):
            yield chunk
    
    def get_status(self) -> dict:
        """Get current model status for UI."""
        return {
            "active_provider": self.active_provider,
            "active_model": self.active_model,
            "providers_count": len(self.providers),
            "has_selection": self.active_provider is not None
        }
    
    def _save_selection(self):
        """Persist selection to disk (implementation omitted)."""
        pass
```

## 4.4 Settings UI for Model Selection

The Settings UI allows user to:
1. Choose provider (Ollama, OpenAI, Custom)
2. Enter API key (for cloud providers)
3. Select from discovered models
4. Test connection

This is covered in detail in Part 2 (UI/UX).

---

# 5. Session Management

## 5.1 Why Unified Sessions?

**Problem with mode-isolated sessions:**
- Start conversation in Chat about "the API project"
- Switch to Voice: "Show me the API code" → Jarvis doesn't know context
- Switch to Ray: "run api tests" → Jarvis doesn't know which API

**Solution:** Single session spanning all modes.

## 5.2 Session Data Structure

```python
# backend/core/session.py

from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum
from typing import Optional
import uuid

class JarvisMode(str, Enum):
    """The four interaction modes."""
    CHAT = "chat"
    FOCUS = "focus"
    CONVERSATION = "conversation"
    RAY = "ray"

class MessageRole(str, Enum):
    """Who sent the message."""
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"

class SessionMessage(BaseModel):
    """
    A single message in the conversation.
    
    Every message is tagged with its originating mode,
    so we can display the right icon in the sidebar.
    """
    
    # Unique identifier
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    
    # Which mode this message came from
    mode: JarvisMode
    
    # Who sent it
    role: MessageRole
    
    # The actual content
    content: str
    
    # When it was sent
    timestamp: datetime = Field(default_factory=datetime.now)
    
    # Additional data (plan, tool results, etc.)
    metadata: dict = Field(default_factory=dict)
    
    # If this message created a plan
    plan_id: Optional[str] = None
    
    # If tools were called
    tool_calls: list[dict] = Field(default_factory=list)


class SessionContext(BaseModel):
    """
    Shared context state that persists across the session.
    
    This is the "memory" within a single session.
    Different from long-term memory (Cognee) which spans sessions.
    """
    
    # What user is currently working on
    current_topic: Optional[str] = None
    
    # Entities mentioned (names, projects, files, etc.)
    mentioned_entities: list[str] = Field(default_factory=list)
    
    # Recent actions taken (for "undo" or context)
    recent_actions: list[dict] = Field(default_factory=list)
    
    # User preferences learned this session
    user_preferences: dict = Field(default_factory=dict)
    
    # Currently executing plan (if any)
    active_plan: Optional[dict] = None
    
    # Last mode used (for sidebar ordering)
    last_mode: JarvisMode = JarvisMode.CHAT


class JarvisSession:
    """
    Unified session management across all modes.
    
    Key behaviors:
    1. All messages stored together regardless of mode
    2. Context shared between modes
    3. Entities extracted and tracked
    4. Serializable for persistence
    """
    
    def __init__(self, session_id: str = None):
        self.id = session_id or str(uuid.uuid4())
        self.messages: list[SessionMessage] = []
        self.context = SessionContext()
        self.created_at = datetime.now()
        self.updated_at = datetime.now()
    
    def add_message(
        self,
        mode: JarvisMode,
        role: MessageRole,
        content: str,
        metadata: dict = None
    ) -> SessionMessage:
        """
        Add a message from ANY mode.
        
        This is the primary method for recording conversation.
        Mode is tracked so sidebar can show the right icon.
        """
        msg = SessionMessage(
            mode=mode,
            role=role,
            content=content,
            metadata=metadata or {}
        )
        self.messages.append(msg)
        self.updated_at = datetime.now()
        self.context.last_mode = mode
        
        # Extract entities from user messages
        if role == MessageRole.USER:
            self._extract_entities(msg)
        
        return msg
    
    def get_context_for_llm(self, limit: int = 20) -> list[dict]:
        """
        Get recent messages formatted for LLM context.
        
        Includes messages from ALL modes so LLM has full context.
        Mode prefix helps LLM understand interaction pattern.
        """
        recent = self.messages[-limit:]
        
        context_messages = []
        for msg in recent:
            # For non-chat modes, prefix with mode name
            if msg.mode != JarvisMode.CHAT:
                content = f"[{msg.mode.value}] {msg.content}"
            else:
                content = msg.content
            
            context_messages.append({
                "role": msg.role.value,
                "content": content
            })
        
        return context_messages
    
    def get_history_for_sidebar(self) -> list[dict]:
        """
        Get conversation history for sidebar display.
        
        Groups messages into "conversations" by topic/time.
        Each entry has an icon based on originating mode.
        """
        conversations = []
        current_conv = None
        
        for msg in self.messages:
            if msg.role == MessageRole.USER:
                # New conversation if:
                # 1. No current conversation
                # 2. Topic changed (new subject)
                # 3. Time gap > 5 minutes
                # 4. Mode changed
                if current_conv is None or self._is_new_conversation(msg, current_conv):
                    if current_conv:
                        conversations.append(current_conv)
                    
                    current_conv = {
                        "id": msg.id,
                        "title": self._generate_title(msg.content),
                        "mode": msg.mode.value,
                        "timestamp": msg.timestamp,
                        "message_count": 1
                    }
                else:
                    current_conv["message_count"] += 1
        
        if current_conv:
            conversations.append(current_conv)
        
        # Most recent first
        return list(reversed(conversations))
    
    def search_history(self, query: str) -> list[SessionMessage]:
        """
        Search for messages containing query.
        
        Simple text search within current session.
        For cross-session search, use Cognee memory.
        """
        query_lower = query.lower()
        return [
            msg for msg in self.messages
            if query_lower in msg.content.lower()
        ]
    
    def _extract_entities(self, msg: SessionMessage):
        """
        Extract potential entities from message.
        
        Simple heuristic: capitalized words are likely entities.
        Production would use NER (Named Entity Recognition).
        """
        words = msg.content.split()
        for word in words:
            # Skip common words
            if word in ["I", "The", "A", "An", "It", "Is", "Are"]:
                continue
            
            # Capitalized words might be entities
            if len(word) > 2 and word[0].isupper():
                clean = word.strip(".,!?")
                if clean not in self.context.mentioned_entities:
                    self.context.mentioned_entities.append(clean)
                    
                    # Keep list manageable
                    if len(self.context.mentioned_entities) > 50:
                        self.context.mentioned_entities.pop(0)
    
    def _is_new_conversation(self, msg: SessionMessage, conv: dict) -> bool:
        """Determine if this message starts a new conversation."""
        # Time gap > 5 minutes
        time_gap = (msg.timestamp - conv["timestamp"]).seconds > 300
        
        # Different mode
        mode_change = msg.mode.value != conv["mode"]
        
        return time_gap or mode_change
    
    def _generate_title(self, content: str) -> str:
        """Generate a short title from message content."""
        # Take first ~50 chars, truncate at word boundary
        if len(content) <= 50:
            return content
        
        truncated = content[:50]
        last_space = truncated.rfind(" ")
        if last_space > 30:
            return truncated[:last_space] + "..."
        return truncated + "..."
    
    def to_dict(self) -> dict:
        """Serialize for storage."""
        return {
            "id": self.id,
            "messages": [msg.model_dump() for msg in self.messages],
            "context": self.context.model_dump(),
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "JarvisSession":
        """Deserialize from storage."""
        session = cls(session_id=data["id"])
        session.messages = [SessionMessage(**m) for m in data["messages"]]
        session.context = SessionContext(**data["context"])
        session.created_at = datetime.fromisoformat(data["created_at"])
        session.updated_at = datetime.fromisoformat(data["updated_at"])
        return session
```

## 5.3 Cross-Mode Context Example

Here's how context flows between modes:

```
SESSION TIMELINE
────────────────────────────────────────────────────────────

10:00 AM - CHAT MODE
User: "I'm working on the Jarvis project, specifically the voice pipeline"

→ Session stores:
  - topic: "Jarvis project"
  - entities: ["Jarvis", "voice pipeline"]

────────────────────────────────────────────────────────────

10:05 AM - VOICE MODE (user activates microphone)
User: [speaks] "Show me the pipeline code"

→ Context retrieved:
  - LLM sees: "[chat] User was working on Jarvis voice pipeline"
  - Jarvis understands: "pipeline" = "voice pipeline"

→ Action: Opens backend/voice/pipeline.py

────────────────────────────────────────────────────────────

10:10 AM - RAY MODE (user presses ⌘+Space)
User: types "run tests"

→ Context retrieved:
  - Recent entities: ["voice pipeline"]
  - Recent actions: [opened pipeline.py]

→ Jarvis suggests: "Run voice pipeline tests?"
→ User confirms, runs: pytest tests/voice/

────────────────────────────────────────────────────────────

SIDEBAR SHOWS (with mode icons):
💬 Jarvis project help     10:00 AM
🎤 Show pipeline code      10:05 AM  
⚡ Run tests               10:10 AM
```

---

# 6. Apple Color System

## 6.1 Why System Colors?

**Problem with custom colors:**
- Don't adapt to light/dark mode
- May clash with system UI
- Accessibility issues
- Not "Apple native" feeling

**Solution:** Use ONLY Apple's semantic color system.

## 6.2 Color Definitions

```swift
// frontend/Core/JarvisColors.swift

import SwiftUI

/// Jarvis color system - Apple Human Interface Guidelines compliant
///
/// All colors use Apple's semantic system colors which:
/// - Automatically adapt to light/dark mode
/// - Meet accessibility contrast requirements
/// - Match system UI for native feel
enum JarvisColors {
    
    // MARK: - Primary Actions
    
    /// Interactive elements: buttons, links, send button
    ///
    /// Exact values (system provides, we don't hardcode):
    /// - Light mode: #007AFF (Apple Blue)
    /// - Dark mode: #0A84FF
    ///
    /// Usage:
    /// - Send button
    /// - Links in text
    /// - Selected tab indicators
    /// - Primary action buttons
    static let interactive = Color.blue
    
    // MARK: - Status Colors
    
    /// Success states: completed, ready, active listening
    ///
    /// Values:
    /// - Light: #34C759
    /// - Dark: #30D158
    ///
    /// Usage:
    /// - Plan step completed checkmark
    /// - Voice mode listening indicator
    /// - Connection status (connected)
    static let success = Color.green
    
    /// Warning states: in-progress, needs attention
    ///
    /// Values:
    /// - Light: #FF9500
    /// - Dark: #FF9F0A
    ///
    /// Usage:
    /// - Slow model loading
    /// - Network issues (degraded)
    static let warning = Color.orange
    
    /// Error states: failed, disconnected
    ///
    /// Values:
    /// - Light: #FF3B30
    /// - Dark: #FF453A
    ///
    /// Usage:
    /// - Plan step failed X mark
    /// - Error messages
    /// - Destructive action buttons
    static let error = Color.red
    
    /// Accent for special elements
    ///
    /// Usage:
    /// - Focus mode header
    /// - Special highlights
    static let accent = Color.teal
    
    // MARK: - Text Colors
    
    /// Primary text color
    ///
    /// Automatically adapts:
    /// - Light mode: Near-black
    /// - Dark mode: Near-white
    static let textPrimary = Color.primary
    
    /// Secondary/muted text
    ///
    /// Usage:
    /// - Timestamps
    /// - Subtitles
    /// - Placeholder text
    static let textSecondary = Color.secondary
    
    // MARK: - Background Colors
    
    /// Window background
    static let background = Color(nsColor: .windowBackgroundColor)
    
    /// Control/surface background (sidebar, cards)
    static let surface = Color(nsColor: .controlBackgroundColor)
    
    /// Text input field background
    static let inputBackground = Color(nsColor: .textBackgroundColor)
    
    // MARK: - Message Bubbles (iMessage style)
    
    /// User message bubble background (right side)
    ///
    /// Blue like iMessage for "sent" messages
    static let userBubble = Color.blue
    
    /// User message text (white on blue)
    static let userBubbleText = Color.white
    
    /// Assistant message bubble background (left side)
    ///
    /// Subtle gray for "received" messages
    static let assistantBubble = Color.secondary.opacity(0.15)
    
    /// Assistant message text (primary on gray)
    static let assistantBubbleText = Color.primary
    
    // MARK: - Semantic Functions
    
    /// Get color for a status string
    ///
    /// Example:
    /// ```swift
    /// Circle().fill(JarvisColors.forStatus(step.status))
    /// ```
    static func forStatus(_ status: String) -> Color {
        switch status {
        case "completed", "success", "done":
            return success
        case "running", "active", "in_progress":
            return interactive
        case "failed", "error":
            return error
        case "pending", "waiting", "queued":
            return textSecondary
        case "warning":
            return warning
        default:
            return textSecondary
        }
    }
    
    /// Get color for a mode
    ///
    /// Used in sidebar icons for history
    static func forMode(_ mode: JarvisMode) -> Color {
        switch mode {
        case .chat:
            return interactive      // Blue - main mode
        case .focus:
            return accent           // Teal - distinct color
        case .conversation:
            return success          // Green - "active/listening"
        case .ray:
            return interactive      // Blue - action-oriented
        }
    }
}
```

## 6.3 Color Usage Examples

| UI Element | Color | Why |
|------------|-------|-----|
| Send button | `.blue` | Primary action |
| User message bubble | `.blue` | iMessage convention |
| AI message bubble | `.secondary.opacity(0.15)` | Subtle, readable |
| Plan step ✓ | `.green` | Universal "done" |
| Plan step • (running) | `.blue` | Active/in-progress |
| Plan step ✗ | `.red` | Universal "error" |
| Sidebar: Chat icon | `.blue` | Mode color |
| Sidebar: Voice icon | `.green` | Listening state |
| Voice edge glow (listening) | `.green` | Active state |
| Voice edge glow (speaking) | `.blue` | Output state |

---

# 7. File Structure

## 7.1 Complete Directory Layout

```
jarvis/
│
├── backend/                         # Python backend
│   │
│   ├── core/                        # Core orchestration
│   │   ├── __init__.py
│   │   ├── tony.py                  # Main orchestrator
│   │   ├── planner.py               # Reasoning planner
│   │   ├── intent.py                # SetFit classifier
│   │   ├── rag.py                   # Hybrid RAG engine
│   │   ├── model_provider.py        # LLM providers
│   │   ├── session.py               # Session management
│   │   └── error_handling.py        # Error recovery
│   │
│   ├── agents/                      # Tool agents
│   │   ├── __init__.py
│   │   ├── registry.py              # Agent registry
│   │   ├── base.py                  # Base agent class
│   │   ├── knowledge/               # Knowledge base
│   │   ├── web_search/              # Web search
│   │   ├── mac_automation/          # AppleScript/shell
│   │   ├── browser/                 # Browser control
│   │   ├── screen_vision/           # Screen capture/OCR
│   │   ├── app_lifecycle/           # App launch/quit
│   │   ├── window_manager/          # Window control
│   │   ├── input_simulation/        # Keyboard/mouse
│   │   ├── media_control/           # Music control
│   │   ├── file_processing/         # File operations
│   │   ├── system_control/          # System settings
│   │   ├── shortcut_runner/         # macOS Shortcuts
│   │   └── ui_automation/           # Accessibility
│   │
│   ├── memory/                      # Long-term memory
│   │   ├── __init__.py
│   │   └── cognee_memory.py         # GraphRAG memory
│   │
│   ├── voice/                       # Voice pipeline
│   │   ├── __init__.py
│   │   ├── pipeline.py              # Pipecat orchestration
│   │   ├── stt.py                   # Speech-to-text
│   │   └── tts.py                   # Text-to-speech
│   │
│   ├── api/                         # API layer
│   │   ├── __init__.py
│   │   ├── websocket.py             # WebSocket server
│   │   └── routes/                  # REST endpoints
│   │
│   ├── main.py                      # FastAPI app entry
│   ├── requirements.txt             # Dependencies
│   └── pyproject.toml               # Project config
│
├── frontend/                        # SwiftUI frontend
│   └── JarvisAI/
│       │
│       ├── Core/                    # Core utilities
│       │   ├── JarvisColors.swift   # Color system
│       │   ├── Theme.swift          # Fonts, spacing
│       │   └── TonyClient.swift     # WebSocket client
│       │
│       ├── Models/                  # Data models
│       │   ├── Message.swift
│       │   ├── Plan.swift
│       │   ├── Session.swift
│       │   └── RayResult.swift
│       │
│       ├── ViewModels/              # View models
│       │   ├── ChatViewModel.swift
│       │   ├── FocusViewModel.swift
│       │   ├── VoiceViewModel.swift
│       │   ├── RayViewModel.swift
│       │   └── SettingsViewModel.swift
│       │
│       ├── Views/                   # UI views
│       │   ├── ChatModeView.swift
│       │   ├── FocusModeView.swift
│       │   ├── ConversationModeView.swift
│       │   ├── RayModeView.swift
│       │   ├── Settings/
│       │   │   ├── SettingsView.swift
│       │   │   └── ModelSettingsView.swift
│       │   └── Components/
│       │       ├── HistorySidebar.swift
│       │       ├── MessageBubble.swift
│       │       ├── iMessageInputBar.swift
│       │       ├── PlanCard.swift
│       │       ├── RayResultRow.swift
│       │       └── EdgeGlowOverlay.swift
│       │
│       ├── Services/                # System services
│       │   ├── SpeechRecognition.swift
│       │   ├── PermissionManager.swift
│       │   └── HotkeyManager.swift
│       │
│       └── JarvisAIApp.swift        # App entry point
│
├── data/                            # Data storage
│   ├── lancedb/                     # Vector database
│   ├── cognee/                      # Graph memory
│   ├── sessions/                    # Session files
│   └── models/                      # ML models
│
├── scripts/                         # Utility scripts
│   ├── setup.sh                     # Initial setup
│   └── train_intent.py              # Train intent model
│
└── Docs/                            # Documentation
    ├── JARVIS_COMPLETE_DESIGN_INDEX.md
    ├── JARVIS_COMPLETE_DESIGN_PART1.md  (this file)
    ├── JARVIS_COMPLETE_DESIGN_PART2.md
    ├── JARVIS_COMPLETE_DESIGN_PART3.md
    └── JARVIS_COMPLETE_DESIGN_PART4.md
```

---

**Continue to Part 2: UI/UX Design →**
