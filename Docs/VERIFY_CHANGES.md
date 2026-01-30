# Jarvis v2.0 - Complete Verification Guide

This comprehensive guide covers all features implemented in the Jarvis v2.0 revamp and how to manually test each one.

---

## Quick Start

### 1. Start the Backend
```bash
cd backend
source venv/bin/activate  # if using venv
python main.py
```

**Expected output:**
```
ChromaDB initialized with collections: jarvis_knowledge, jarvis_memory
Jarvis agent graph created successfully
Conversation database initialized
Uvicorn running on http://0.0.0.0:8000
```

### 2. Build & Run Frontend
1. Open `frontend/JarvisAI/JarvisAI.xcodeproj` in Xcode
2. **Product → Clean Build Folder** (⇧⌘K)
3. **Product → Build** (⌘B)
4. **Product → Run** (⌘R)

---

## Feature Verification Checklist

### 🎛️ 1. Mode Selector (Reasoning vs Fast)

| What | How to Test | Expected |
|------|-------------|----------|
| Mode pills visible | Look above the message input | Two pills: **Reasoning** (purple), **Fast** (green) |
| Mode selection | Tap each pill | Selected pill highlights with color fill |
| Mode sent to backend | Send a message, check server logs | Log shows `mode: reasoning` or `mode: fast` |
| Fast mode behavior | Select Fast, send "Open Safari" | Faster response, may skip planning for simple tasks |

**Test message:** "What is 2+2?" (should work in both modes)

---

### 📋 2. Intent Classification

| What | How to Test | Expected |
|------|-------------|----------|
| Question intent | Send "What is Python?" | Intent badge shows **Question** |
| Action intent | Send "Open Safari" | Intent badge shows **Action** |
| Mixed intent | Send "What's the weather and open Calendar" | Intent badge shows **Mixed** |
| Confidence | Check badge | Shows percentage (e.g. "Action 90%") |

**Test messages:**
- Question: "Explain machine learning"
- Action: "Search YouTube for cat videos"
- Mixed: "What time is it and set a reminder"

---

### 📊 3. Plan Stepper (Live Updates)

| What | How to Test | Expected |
|------|-------------|----------|
| Plan appears | Send "Open Safari and search for AI news" | Plan stepper shows above message content |
| Step count | Check header | Shows "1/4" or similar (current/total) |
| Summary | Check plan header | Brief description like "Open Safari and search..." |
| Live status | Watch during execution | Steps update: pending (○) → running (●) → completed (✓) |
| Step details | Expand plan | Shows tool name for each step (e.g. `launch_app`) |
| Focus mode | Open Focus panel (menu bar) | Plan stepper works in Focus mode too |
| Stable display | Watch UI during updates | No flickering, smooth transitions |

**Test messages (trigger planning):**
- "Open Safari and go to YouTube"
- "Search the web for latest macOS news"
- "Open Finder and create a new folder called Test"

**What to watch:**
1. Plan stepper appears DURING streaming (not just at end)
2. Step 1 becomes "running" when first tool starts
3. Step 1 becomes "completed", Step 2 becomes "running"
4. All steps show "completed" at end
5. Progress bar animates smoothly
6. No flickering when steps update

**Focus Mode Testing:**
1. Click Jarvis icon in menu bar to open Focus panel
2. Send an action like "Open Safari"
3. Compact Plan Stepper should appear in Focus panel
4. Progress bar and step status work identically

---

### 🧠 4. Reasoning/Thinking Steps

| What | How to Test | Expected |
|------|-------------|----------|
| Dropdown appears | Send action message | "Thinking Steps · N" dropdown below message |
| Expand reasoning | Click the dropdown | Shows numbered reasoning steps |
| Tool usage | Send "Search the web for X" | Reasoning shows "🔧 Using tool: web_search" |
| Step icons | Check expanded view | Different icons for search, tool, result steps |

**Test message:** "Open Safari and search for Python tutorials"

---

### 🛡️ 5. Adaptive Guardrails (Anti-Hallucination)

| What | How to Test | Expected |
|------|-------------|----------|
| Loop detection | Try to trigger a loop | Agent detects and stops with explanation |
| Progress tracking | Send complex task | Backend logs show progress |
| Graceful completion | Reach tool limit | Agent summarizes rather than hard-stopping |
| Context injection | Send multi-step task | Agent mentions remaining steps/progress |

**How to trigger guardrails:**
1. Send a task that might loop: "Keep searching until you find the perfect result"
2. Send a complex task: "Open Safari, go to YouTube, search for AI, click the first video, and summarize it"
3. Watch backend logs for: `Adaptive guardrail triggered`, `Loop detected`, or `Extended tool limit`

**Expected behavior:**
- Agent stops gracefully with summary
- Logs show: "Loop detected: repeated 'tool_name' 3 times"
- Agent doesn't just cut off mid-sentence

**Adaptive features:**
- Base limit: 15 tool calls (can extend if making progress)
- Loop detection: Same tool+args 3+ times = loop
- Stagnation: No progress for 5+ iterations
- Graceful guidance: Agent told to wrap up, not hard-stopped

---

### 🎨 6. Liquid Glass UI Design

| What | How to Test | Expected |
|------|-------------|----------|
| Glass effects | Look at message bubbles | Subtle blur/transparency |
| Color scheme | Check dark mode | Uses JarvisColors (purple primary, glass strokes) |
| Mode colors | Select different modes | Reasoning = purple, Fast = green |
| Animations | Interact with UI | Smooth spring animations |

**Visual elements to verify:**
- Message bubbles have rounded corners (22px)
- Glass stroke on elevated surfaces
- Purple/green gradient on mode indicators
- Smooth expand/collapse on reasoning dropdown

---

### 💾 7. Memory System

| What | How to Test | Expected |
|------|-------------|----------|
| Memory endpoint | `curl http://localhost:8000/memory/search -X POST -H "Content-Type: application/json" -d '{"query": "test"}'` | Returns matching memories |
| Entity extraction | Backend processes conversations | Logs show entity extraction |
| Knowledge graph | Check logs | NetworkX graph operations logged |

---

### 🎤 8. Voice Pipeline (If Configured)

| What | How to Test | Expected |
|------|-------------|----------|
| Voice endpoint | Check `/docs` at localhost:8000 | Voice routes visible |
| WebSocket | Connect to `/ws/voice` | Connection established |

*Note: Full voice requires STT/TTS API keys (Deepgram, OpenAI, etc.)*

---

## Backend API Verification

### Health Check
```bash
curl http://localhost:8000/health
```
**Expected:** `{"status":"healthy","version":"1.0.0",...}`

### Chat Streaming
```bash
curl -X POST http://localhost:8000/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Open Safari"}],"mode":"reasoning","include_plan":true,"include_reasoning":true}'
```
**Expected:** Stream of SSE events including `type: plan`, `type: reasoning`, `type: content`

### Memory Search
```bash
curl -X POST http://localhost:8000/memory/search \
  -H "Content-Type: application/json" \
  -d '{"query":"test","top_k":5}'
```

---

## Troubleshooting

### Plan not showing?
1. **Check backend logs** - Does "plan" node run? Look for "Plan created with N steps"
2. **Check intent** - Simple questions skip planning (classify → respond)
3. **Clean rebuild** - Xcode: ⇧⌘K then ⌘B
4. **Check streaming** - Frontend must receive `type: plan` event

### Steps not updating live?
1. **Check streaming** - Network tab should show continuous SSE events
2. **Verify plan_step_update events** - Backend should emit these as steps change
3. **Check frontend observer** - ChatViewModel.updateAssistantPlan should fire

### Agent going off track?
1. **Check guardrail logs** - Look for "Adaptive guardrail triggered"
2. **Verify tool_history** - Backend tracks recent tool calls
3. **Check for loops** - Same tool+args 3+ times triggers stop

### Mode selector not visible?
1. **Check FloatingInputView** - Should include `ModeSelectorView`
2. **Verify DesignSystem.swift** - `AgentMode` and `ModeSelectorView` should exist
3. **Clean rebuild** - Remove derived data if needed

---

## Files Changed in v2.0 Revamp

### Backend
| File | Changes |
|------|---------|
| `agents/graph.py` | LangGraph workflow, intent classify, planning, adaptive guardrails |
| `agents/state.py` | JarvisState with plan, mode, tool_history, guardrail fields |
| `agents/guardrails.py` | **NEW** - Adaptive control, loop detection, progress tracking |
| `api/routes/chat.py` | Unified streaming with plan/reasoning events |
| `api/routes/memory.py` | **NEW** - Memory API endpoints |
| `api/routes/voice.py` | **NEW** - Voice pipeline endpoints |
| `api/models.py` | Stream events, plan step status enums |
| `services/memory/` | **NEW** - Knowledge graph, entity extraction, hybrid search |
| `services/voice/` | **NEW** - STT, TTS, VAD services |
| `requirements.txt` | Updated langchain/langgraph versions |

### Frontend
| File | Changes |
|------|---------|
| `Utils/DesignSystem.swift` | JarvisColors, AgentMode, ModeSelectorView, PlanStepperView, PlanStepView |
| `Models/Message.swift` | Plan, planSummary, intent, intentConfidence, mode properties |
| `Services/StreamingService.swift` | Plan event parsing, plan_step_update handling, live updates |
| `ViewModels/ChatViewModel.swift` | Mode selection, plan/summary observers with CombineLatest |
| `Views/FloatingInputView.swift` | ModeSelectorView integration |
| `Views/MessageBubbleView.swift` | Plan stepper, ModeIndicatorBadge, IntentBadge |
| `Views/ReasoningDropdownView.swift` | Enhanced reasoning display with step icons |

---

## Summary of What's New

### Agent System
- ✅ **Dual Modes**: Reasoning (thorough, plans) vs Fast (quick, direct)
- ✅ **Intent Classification**: question/action/mixed with confidence
- ✅ **Step-by-Step Planning**: Creates and streams execution plan
- ✅ **Adaptive Guardrails**: Smart limits, loop detection, graceful completion

### UI/UX
- ✅ **Mode Selector**: Above input, purple/green pills
- ✅ **Plan Stepper**: Live-updating plan with step status
- ✅ **Intent Badge**: Shows detected intent and confidence
- ✅ **Reasoning Dropdown**: Expandable thinking steps
- ✅ **Liquid Glass Design**: Consistent colors, animations, effects

### Backend Services
- ✅ **Memory System**: Knowledge graph + vector store
- ✅ **Voice Pipeline**: STT/TTS/VAD infrastructure
- ✅ **Unified Streaming**: All events through consistent schema

---

## Version Info
- **Jarvis Version:** 2.0
- **LangGraph:** 1.0.7+
- **macOS Target:** 13.0+ (with Liquid Glass on macOS 26 Tahoe)
- **Swift:** 5.x
- **Xcode:** 26.x (with SDK macOS 26.2)
- **Last Updated:** January 29, 2026

## macOS 26 Liquid Glass Integration

Jarvis uses official Apple Liquid Glass APIs from WWDC25:
- `glassEffect` modifier for custom views (macOS 26+)
- `GlassEffectContainer` for grouping glass elements
- Fallback to custom implementation for macOS 13-25
- Capsule-shaped buttons per macOS 26 HIG
- Adaptive material that changes with scroll content

See `Utils/DesignSystem.swift` for implementation details.
