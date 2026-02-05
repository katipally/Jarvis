# JARVIS AI - Complete System Design

> **Version:** 5.2 Final | **Date:** February 3, 2026  
> **Document:** Part 4 of 4 - Scenarios & Implementation (Enhanced)

---

## Table of Contents

1. [Capability List](#1-capability-list)
2. [Detailed Scenarios](#2-detailed-scenarios)
3. [Error Handling & Recovery](#3-error-handling--recovery)
4. [Implementation Plan](#4-implementation-plan)
5. [Quick Reference](#5-quick-reference)

---

# 1. Capability List

## 1.1 Full Capability Matrix (20 Examples)

| # | Command | Agent(s) | Mode | Complexity |
|---|---------|----------|------|------------|
| 1 | "Open Safari" | app_lifecycle | Ray | ⭐ |
| 2 | "Close all Chrome windows" | app_lifecycle, window | Ray | ⭐⭐ |
| 3 | "Search for AI news" | browser, web_search | Ray/Chat | ⭐⭐ |
| 4 | "Set volume to 50%" | system_control | Ray/Voice | ⭐ |
| 5 | "Play/pause music" | media_control | Ray/Voice | ⭐ |
| 6 | "Find Python files in Documents" | file_processing | Chat | ⭐⭐ |
| 7 | "Read my notes.txt" | file_processing | Chat | ⭐⭐ |
| 8 | "Take a screenshot" | screen_vision | Ray | ⭐ |
| 9 | "Click the Sign In button" | ui_automation | Chat | ⭐⭐ |
| 10 | "Tile Safari and Notes" | window_manager | Ray | ⭐⭐ |
| 11 | "Run my 'Morning Setup' shortcut" | shortcut_runner | Ray | ⭐ |
| 12 | "What's on my screen?" | screen_vision | Focus | ⭐⭐ |
| 13 | "Connect to AirPods" | system_control | Ray | ⭐⭐ |
| 14 | "Toggle Dark Mode" | system_control | Ray | ⭐ |
| 15 | "Open github.com in Chrome" | browser | Ray | ⭐ |
| 16 | "Summarize this PDF" | file_processing, knowledge | Focus | ⭐⭐⭐ |
| 17 | "Open Safari, go to Twitter, like the first post" | app, browser, ui | Chat | ⭐⭐⭐⭐ |
| 18 | "Find all meetings tomorrow" | calendar, knowledge | Chat | ⭐⭐ |
| 19 | "Remind me about this page later" | memory, knowledge | Focus | ⭐⭐ |
| 20 | "What did we discuss about Python yesterday?" | memory | Chat | ⭐⭐ |

## 1.2 Complexity Levels Explained

| Level | Meaning | Planning? | Typical Duration |
|-------|---------|-----------|------------------|
| ⭐ | Single tool, instant | No | <1s |
| ⭐⭐ | 1-2 tools, simple | Optional | 1-3s |
| ⭐⭐⭐ | Multiple tools, coordination | Yes | 3-10s |
| ⭐⭐⭐⭐ | Complex workflow, web interaction | Yes | 10-30s |
| ⭐⭐⭐⭐⭐ | Multi-step with decisions | Yes + reasoning | 30s+ |

---

# 2. Detailed Scenarios

## Scenario 1: Quick App Launch (Ray Mode)

**User says:** "open safari"  
**Mode:** Ray

```
┌─────────────────────────────────────────────────────────────────┐
│                         FLOW DIAGRAM                             │
└─────────────────────────────────────────────────────────────────┘

User types "open safari" in Ray
         │
         ▼
┌──────────────────────┐
│ Intent Classification │  ← Category: app_launch
│ (SetFit, ~5ms)       │    Confidence: 0.98
└──────────────────────┘    Planning: false
         │
         ▼
┌──────────────────────┐
│ Direct Execution     │  ← No plan needed
│ (Skip planning)      │
└──────────────────────┘
         │
         ▼
┌──────────────────────┐
│ app_lifecycle.       │  tell application "Safari"
│   launch_app         │      activate
│ (AppleScript)        │  end tell
└──────────────────────┘
         │
         ▼
┌──────────────────────┐
│ Response             │  → "Safari opened"
│ (Ray dismisses)      │    [window appears]
└──────────────────────┘

Total time: ~200ms
```

**Why this is fast:**
1. SetFit classifies in 5ms (vs 100ms+ for LLM)
2. No planning for simple actions
3. AppleScript is native and fast
4. Ray dismisses immediately on success

---

## Scenario 2: Multi-Step Web Task (Chat Mode)

**User says:** "Open Safari, go to GitHub, and search for Python projects"  
**Mode:** Chat

```
┌─────────────────────────────────────────────────────────────────┐
│                         FLOW DIAGRAM                             │
└─────────────────────────────────────────────────────────────────┘

User: "Open Safari, go to GitHub, and search for Python projects"
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. INTENT CLASSIFICATION                                         │
│                                                                  │
│    SetFit detects:                                               │
│    - "and" keyword + multiple actions                            │
│    - Category: task_complex                                      │
│    - requires_planning: true                                     │
│    - Agents: [app_lifecycle, browser]                            │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 2. PLANNING (LLM creates plan)                                   │
│                                                                  │
│    {                                                             │
│      "summary": "Open Safari, navigate to GitHub, search",       │
│      "steps": [                                                  │
│        {"id": "1", "description": "Launch Safari",               │
│         "tool": "app_lifecycle.launch_app",                      │
│         "args": {"app_name": "Safari"}},                         │
│        {"id": "2", "description": "Go to GitHub",                │
│         "tool": "browser.navigate",                              │
│         "args": {"url": "https://github.com"}},                  │
│        {"id": "3", "description": "Search for Python",           │
│         "tool": "browser.fill_input",                            │
│         "args": {"text": "Python projects", "field": "search"}}  │
│      ]                                                           │
│    }                                                             │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼ (Plan sent to UI)
┌──────────────────────────────────────────────────────────────────┐
│                    CHAT UI (Plan Card)                           │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 📋 Open Safari, navigate to GitHub, search                   │ │
│ ├──────────────────────────────────────────────────────────────┤ │
│ │ ○ Step 1: Launch Safari                        [pending]     │ │
│ │ ○ Step 2: Go to GitHub                         [pending]     │ │
│ │ ○ Step 3: Search for Python                    [pending]     │ │
│ └──────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 3. STEP 1 EXECUTION                                              │
│                                                                  │
│    Status → "running" (UI updates, spinner appears)              │
│    Execute: tell application "Safari" to activate               │
│    Status → "completed" (checkmark, green)                       │
│                                                                  │
│    UI shows:                                                     │
│    ✓ Step 1: Launch Safari                       [done]          │
│    ● Step 2: Go to GitHub                        [running]       │
│    ○ Step 3: Search for Python                   [pending]       │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 4. STEP 2 EXECUTION                                              │
│                                                                  │
│    tell application "Safari"                                     │
│        tell window 1                                             │
│            set URL of current tab to "https://github.com"        │
│        end tell                                                  │
│    end tell                                                      │
│                                                                  │
│    Wait for page load (implicit delay)                          │
│    Status → "completed"                                          │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 5. STEP 3 EXECUTION                                              │
│                                                                  │
│    JavaScript injection:                                         │
│    var input = document.querySelector('input[type="text"]');     │
│    input.value = "Python projects";                              │
│    input.form.submit();                                          │
│                                                                  │
│    Status → "completed"                                          │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 6. RESPONSE GENERATION                                           │
│                                                                  │
│    LLM summarizes:                                               │
│    "Done! I've opened Safari, navigated to GitHub, and searched  │
│     for 'Python projects'. The search results are now displayed."│
│                                                                  │
│    UI shows all steps completed + AI response                    │
└──────────────────────────────────────────────────────────────────┘

Total time: ~5-8 seconds
```

---

## Scenario 3: Voice Conversation

**User says (voice):** "What's the weather like today?"  
**Mode:** Conversation (Voice)

```
┌─────────────────────────────────────────────────────────────────┐
│                         VOICE FLOW                               │
└─────────────────────────────────────────────────────────────────┘

User speaks: "What's the weather like today?"
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. VOICE ACTIVITY DETECTION                                      │
│                                                                  │
│    Silero VAD:                                                   │
│    - Detects speech onset in ~50ms                               │
│    - Audio buffered during speech                                │
│    - Speech end detected after 300ms silence                     │
│                                                                  │
│    UI: Edge glow GREEN (listening)                               │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 2. SPEECH TO TEXT                                                │
│                                                                  │
│    Whisper transcribes buffered audio                            │
│    Result: "What's the weather like today?"                      │
│                                                                  │
│    Transcription card appears on screen                          │
│    UI: Edge glow BLUE (processing)                               │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 3. CLASSIFICATION                                                │
│                                                                  │
│    Category: question                                            │
│    No tools needed (or optional: web_search for live weather)    │
│    Simple response path                                          │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 4. RESPONSE GENERATION                                           │
│                                                                  │
│    LLM generates response                                        │
│    (Could integrate weather API for real data)                   │
│                                                                  │
│    Text: "Based on your location, it's currently 72°F and sunny  │
│           in San Francisco with a high of 75°F expected."        │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 5. TEXT TO SPEECH (Streaming)                                    │
│                                                                  │
│    PiperTTS streams audio chunks as generated                    │
│    Starts speaking before full response is ready                 │
│                                                                  │
│    UI: Edge glow BLUE (speaking)                                 │
│    Response card shows text                                      │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 6. INTERRUPTION HANDLING                                         │
│                                                                  │
│    If user speaks during TTS:                                    │
│    - VAD detects new speech                                      │
│    - TTS immediately stops                                       │
│    - New audio buffered                                          │
│    - Cycle repeats                                               │
└──────────────────────────────────────────────────────────────────┘

End-to-end latency: ~500ms (from speech end to speech start)
```

---

## Scenario 4: Focus Mode Context

**User working in:** Xcode (Swift file open)  
**User says:** "Help me fix this error"  
**Mode:** Focus

```
┌─────────────────────────────────────────────────────────────────┐
│                         FOCUS FLOW                               │
└─────────────────────────────────────────────────────────────────┘

User is coding in Xcode, sees error, asks for help
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. CONTEXT GATHERING                                             │
│                                                                  │
│    Focus mode automatically:                                     │
│    - Captures active window (Xcode)                              │
│    - Runs OCR on visible area                                    │
│    - Detects file type (.swift)                                  │
│    - Finds error message in status bar                           │
│                                                                  │
│    Context: {                                                    │
│      "app": "Xcode",                                             │
│      "file": "ViewController.swift",                             │
│      "visible_code": "func viewDidLoad() { ... }",               │
│      "error": "Type 'ContentView' has no member 'body'..."       │
│    }                                                             │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 2. RAG SEARCH                                                    │
│                                                                  │
│    Query: "SwiftUI ContentView body error"                       │
│    Returns relevant docs about:                                  │
│    - SwiftUI View protocol                                       │
│    - body property requirement                                   │
│    - Common mistakes                                             │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 3. LLM ANALYSIS                                                  │
│                                                                  │
│    Given:                                                        │
│    - Screen context (code + error)                               │
│    - RAG results                                                 │
│    - User request                                                │
│                                                                  │
│    Response: "The error indicates your ContentView is missing    │
│    a 'body' property. SwiftUI Views must have a computed         │
│    property 'body' that returns some View. Add:                  │
│                                                                  │
│    var body: some View {                                         │
│        Text('Hello')                                             │
│    }                                                             │
│                                                                  │
│    Would you like me to show where to add this?"                 │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│ 4. FOCUS PANEL DISPLAY                                           │
│                                                                  │
│    ┌──────────────────────────────────┐                         │
│    │ 👁 Focus Mode          Xcode ✕  │                         │
│    ├──────────────────────────────────┤                         │
│    │ I see you're getting an error   │                         │
│    │ about missing 'body' property.  │                         │
│    │                                 │                         │
│    │ Add this to ContentView:        │                         │
│    │ ┌──────────────────────────────┐│                         │
│    │ │var body: some View {         ││                         │
│    │ │    Text("Hello")             ││                         │
│    │ │}                             ││                         │
│    │ └──────────────────────────────┘│                         │
│    │                                 │                         │
│    │ [Copy Code]  [Show in Xcode]   │                         │
│    └──────────────────────────────────┘                         │
│                                                                  │
│    Panel stays small (400×300), doesn't block code               │
└──────────────────────────────────────────────────────────────────┘
```

---

# 3. Error Handling & Recovery

## 3.1 Error Categories

| Category | Example | Detection | Recovery |
|----------|---------|-----------|----------|
| **Model Offline** | Ollama not running | Health check fails | Switch to cloud API |
| **Tool Timeout** | Browser hangs | 30s limit exceeded | Retry once, then fail gracefully |
| **Permission Denied** | Privacy settings | AppleScript error | Prompt user to grant access |
| **Network Error** | No internet | HTTP exception | Retry with backoff |
| **Rate Limit** | OpenAI 429 | Response code | Exponential backoff |
| **Invalid Input** | Unrecognized app | Tool returns error | Ask for clarification |

## 3.2 Graceful Degradation

```python
# Example: Model failover chain

class ModelManager:
    async def generate(self, messages: list) -> AsyncIterator[str]:
        """Try providers in order until one works."""
        
        providers = [
            self._try_ollama,    # First: local (fastest)
            self._try_openai,   # Second: cloud (reliable)
            self._try_fallback  # Third: basic response
        ]
        
        for provider in providers:
            try:
                async for chunk in provider(messages):
                    yield chunk
                return  # Success, exit
            except Exception as e:
                log.warning(f"Provider failed: {e}")
                continue
        
        # All failed
        yield "I'm having trouble processing that. Please check your settings."
```

## 3.3 User Communication

When errors occur, Jarvis:
1. **Never crashes silently** - Always shows a message
2. **Explains what happened** - "I couldn't open that app"
3. **Suggests next steps** - "Would you like to try..."
4. **Logs for debugging** - Full error saved to logs

---

# 4. Implementation Plan

## 4.1 Overview (10 Weeks)

```
Week 1-2: Foundation
Week 3-4: Core AI
Week 5-6: UI Implementation
Week 7-8: Agents & Tools
Week 9: Integration & Voice
Week 10: Polish & Testing
```

## 4.2 Week-by-Week Breakdown

### Week 1-2: Foundation

**Goal:** Project structure, basic connectivity

| Task | Days | Output |
|------|------|--------|
| Set up Python project | 1 | pyproject.toml, structure |
| Set up Swift project | 1 | Xcode project, targets |
| WebSocket server | 2 | FastAPI /ws endpoint |
| WebSocket client | 2 | Swift WebSocketService |
| Health checks | 1 | Connection monitoring |
| Basic message flow | 1 | Send/receive working |

**Milestone:** Frontend can send message, backend echoes it.

### Week 3-4: Core AI

**Goal:** Intelligence without tools

| Task | Days | Output |
|------|------|--------|
| Model provider base | 1 | Abstract class |
| Ollama integration | 2 | OllamaProvider |
| OpenAI integration | 1 | OpenAIProvider |
| Streaming generation | 2 | Async generators |
| SetFit classifier | 2 | Intent detection |
| Reasoning planner | 2 | Plan creation |

**Milestone:** Ask question, get intelligent streamed response.

### Week 5-6: UI Implementation

**Goal:** All 4 modes working visually

| Task | Days | Output |
|------|------|--------|
| Design system | 1 | Theme.swift, colors |
| Window manager | 2 | Window creation/positioning |
| Chat mode UI | 3 | iMessage style complete |
| Ray mode UI | 2 | Spotlight style |
| Conversation overlay | 2 | Edge glow animation |
| Focus panel | 2 | Compact assistant |

**Milestone:** All modes show UI, connect to backend.

### Week 7-8: Agents & Tools

**Goal:** Full Mac control

| Task | Days | Output |
|------|------|--------|
| Agent registry | 1 | Tool discovery |
| App lifecycle agent | 2 | Launch/quit apps |
| Browser agent | 3 | Navigate, click, fill |
| System control | 2 | Volume, DND, etc. |
| File processing | 2 | Read, search files |
| UI automation | 2 | Click any element |

**Milestone:** "Open Safari and search" works end-to-end.

### Week 9: Integration & Voice

**Goal:** Voice works, everything connected

| Task | Days | Output |
|------|------|--------|
| Pipecat integration | 2 | Audio pipeline |
| VAD + STT | 2 | Listen → transcribe |
| TTS streaming | 1 | Speak responses |
| RAG engine | 2 | Hybrid search |
| Memory (Cognee) | 1 | Basic storage |
| Session management | 1 | Cross-mode context |

**Milestone:** Voice conversation works with interruption.

### Week 10: Polish & Testing

**Goal:** Production-ready quality

| Task | Days | Output |
|------|------|--------|
| Error handling | 2 | All edge cases |
| Performance | 1 | <500ms latency |
| Animations | 1 | Smooth transitions |
| Settings UI | 1 | Model selection |
| Testing | 2 | E2E test suite |
| Documentation | 1 | README, setup guide |

**Milestone:** Ready for daily use.

## 4.3 Dependencies Visualization

```
                    ┌─────────────┐
                    │ Foundation  │
                    │ (Week 1-2)  │
                    └─────┬───────┘
                          │
            ┌─────────────┼─────────────┐
            ▼             ▼             ▼
    ┌───────────┐  ┌───────────┐  ┌───────────┐
    │  Core AI  │  │    UI     │  │  Agents   │
    │ (Week 3-4)│  │ (Week 5-6)│  │ (Week 7-8)│
    └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
          │              │              │
          └──────────────┼──────────────┘
                         ▼
               ┌─────────────────┐
               │  Integration    │
               │   (Week 9)      │
               └────────┬────────┘
                        ▼
               ┌─────────────────┐
               │    Polish       │
               │   (Week 10)     │
               └─────────────────┘
```

---

# 5. Quick Reference

## 5.1 Project Structure

```
Jarvis/
├── backend/
│   ├── core/
│   │   ├── tony.py              # Main orchestrator
│   │   ├── intent.py            # SetFit classifier
│   │   ├── planner.py           # Reasoning planner
│   │   ├── rag.py               # Hybrid RAG
│   │   ├── session.py           # Session management
│   │   └── model_provider.py    # LLM abstraction
│   ├── agents/
│   │   ├── registry.py          # Agent registry
│   │   ├── app_lifecycle.py     # App control
│   │   ├── browser.py           # Browser control
│   │   ├── system_control.py    # System settings
│   │   └── ...                  # Other agents
│   ├── memory/
│   │   └── cognee_memory.py     # GraphRAG memory
│   ├── voice/
│   │   ├── pipeline.py          # Voice pipeline
│   │   ├── tts.py               # Piper TTS
│   │   └── stt.py               # Whisper STT
│   ├── api/
│   │   └── websocket.py         # FastAPI server
│   └── main.py                  # Entry point
│
├── frontend/
│   ├── JarvisApp.swift          # App entry
│   ├── Core/
│   │   ├── Theme.swift          # Design tokens
│   │   ├── JarvisColors.swift   # Color system
│   │   └── WindowManager.swift  # Window control
│   ├── Models/
│   │   ├── Message.swift        # Message model
│   │   ├── Plan.swift           # Plan model
│   │   └── Session.swift        # Session model
│   ├── Services/
│   │   ├── WebSocketService.swift
│   │   └── SessionManager.swift
│   └── Views/
│       ├── ChatModeView.swift
│       ├── RayModeView.swift
│       ├── ConversationModeView.swift
│       ├── FocusModeView.swift
│       └── Components/
│           ├── MessageBubble.swift
│           ├── PlanCard.swift
│           ├── iMessageInputBar.swift
│           └── EdgeGlowOverlay.swift
│
└── Docs/
    ├── JARVIS_COMPLETE_DESIGN_INDEX.md
    ├── JARVIS_COMPLETE_DESIGN_PART1.md
    ├── JARVIS_COMPLETE_DESIGN_PART2.md
    ├── JARVIS_COMPLETE_DESIGN_PART3.md
    └── JARVIS_COMPLETE_DESIGN_PART4.md
```

## 5.2 Key Commands

```bash
# Start backend
cd backend && python main.py

# Build frontend
xcodebuild -project frontend/Jarvis.xcodeproj -scheme Jarvis build

# Run tests
pytest backend/tests/
swift test --package-path frontend/
```

## 5.3 Hotkeys

> [!NOTE]
> All Jarvis hotkeys use simple **Option + key** combinations to avoid conflicts with system shortcuts.

| Key | Action | Description |
|-----|--------|-------------|
| `⌥C` | Chat | Full chat interface |
| `⌥R` | Ray | Spotlight-like launcher |
| `⌥V` | Voice | Voice conversation mode |
| `⌥F` | Focus | Context-aware panel |
| `⌥,` | Settings | Open preferences |
| `Escape` | Dismiss | Close current mode |

## 5.4 Technology Stack Summary

| Component | Technology | Why |
|-----------|-----------|-----|
| Frontend | SwiftUI | Native, modern |
| Backend | FastAPI | Async, fast |
| Communication | WebSocket | Real-time, bidirectional |
| LLM | Ollama/OpenAI | Local + cloud |
| Embeddings | E5-small | 384d, accurate |
| Vector DB | LanceDB | Local, serverless |
| Graph DB | Cognee | GraphRAG, entities |
| Classifier | SetFit | 10-15ms inference |
| VAD | Silero | Real-time, accurate |
| TTS | Piper | Fast, streaming |
| STT | Whisper | Accurate |

---

**End of Jarvis Complete System Design**

*This document series provides the complete specification for building Jarvis. Follow the implementation plan, reference the code examples, and iterate based on testing.*
