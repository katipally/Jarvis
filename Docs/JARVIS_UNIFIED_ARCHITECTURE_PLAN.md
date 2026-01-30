# Jarvis: Unified AI Assistant — Architecture & Rework Plan

**Updated:** January 2026  
**Scope:** Reasoning vs Fast modes, single main AI with tools, intent & planning, full wiring (backend, DB, frontend), all surfaces as one Jarvis.

---

## 1. Core Principles (How Jarvis Should Work)

### 1.1 One Jarvis, One Brain

- **Single main agent**: One LangGraph-based “Jarvis” agent is the only AI. It has access to all tools (knowledge base, web search, file processing, Mac automation, browser, UI, etc.) and decides when and how many to use.
- **Tools are sub-capabilities**: Tools are not separate “modes” — they are instruments the main agent uses. The agent can chain multiple tools (e.g. search → open browser → fill form) in one turn when the user intent requires it.
- **Intent understanding**: Jarvis must classify user input as:
  - **Question** (informational): answer from knowledge, RAG, or web search; no Mac actions unless user asks to “open” or “show” something.
  - **Action** (task): perform steps on the Mac (launch app, run shortcut, type, click, navigate, etc.); may require a plan and multiple tools.
  - **Mixed**: e.g. “What’s the weather and open my calendar” → answer + action.
- **Planning when needed**: For multi-step or ambiguous actions, Jarvis should produce an explicit **plan** (ordered steps), execute step-by-step, and **mark steps complete** as they finish — similar to Cursor/Windsurf agentic flows: interpret task → plan → execute → verify.

### 1.2 Two Modes: Reasoning vs Fast

| Mode | When to use | Behavior | Latency / Cost |
|------|-------------|----------|----------------|
| **Reasoning** | Complex questions, multi-step tasks, ambiguous requests, “think step by step” | Explicit planning; chain-of-thought; multiple tool calls; step completion tracking; richer system prompt. | Higher latency, more tokens. |
| **Fast** | Simple Q&A, single action, voice/short reply, Ray quick answer | Minimal planning; direct answer or single tool; optional “thinking budget” cap or no extended reasoning. | Lower latency, fewer tokens. |

- **Implementation**: Same graph, but request carries `mode: "reasoning" | "fast"`. In state, set a flag or inject different instructions (e.g. “Always produce a plan and mark steps” vs “Answer or act directly”). Optionally use a “thinking” model or extended-reasoning capability for Reasoning mode (per 2026 practice: Claude extended thinking, Google AI Mode, OpenAI reasoning models).
- **Surfaces**: User can choose mode in Settings or per-request (e.g. Chat/Focus: toggle; Voice: default Fast; Ray: default Fast with “deep think” option).

### 1.3 Interaction Surfaces Are Just Entry Points

- **Chat** (main window), **Focus** (floating panel), **Conversation** (voice), and **Ray** (Spotlight-style) are **different ways to talk to the same Jarvis**.
- Same backend API, same session/conversation model, same agent and tools. Only transport and UX differ:
  - Chat/Focus: text in, streaming text (+ reasoning + tools + plan/steps).
  - Conversation: voice in, voice out; same agent, possibly Fast mode by default, sentence-boundary streaming for TTS.
  - Ray: text in, quick results or “Open in Chat” for full thread; same agent, same conversation when continued in Chat/Focus.

---

## 2. Target Architecture (Rework)

### 2.1 High-Level

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  INTERACTION SURFACES (same Jarvis)                                         │
│  Chat Window │ Focus Panel │ Conversation (Voice) │ Ray                     │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │  UNIFIED FRONTEND LAYER        │
                    │  • One session / conversation  │
                    │  • One config (API, WS URL)    │
                    │  • Mode: reasoning | fast     │
                    └───────────────┬───────────────┘
                                    │ HTTP/SSE or WebSocket (same contract)
                    ┌───────────────▼───────────────┐
                    │  BACKEND API                   │
                    │  • Session/conversation ID     │
                    │  • mode, plan, steps          │
                    │  • Single stream schema       │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │  JARVIS AGENT (LangGraph)     │
                    │  • Intent: question | action  │
                    │  • Reasoning vs Fast          │
                    │  • Plan → Execute → Complete  │
                    │  • All tools (sub-capabilities)│
                    └───────────────┬───────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
   ┌────▼────┐  ┌─────────────┐  ┌──▼──────────┐  ┌───────────▼────┐
   │ RAG /   │  │ Web Search   │  │ Mac Auto    │  │ File / Browser  │
   │ Chroma  │  │ DuckDuckGo   │  │ Scripts/UI  │  │ Processor       │
   └─────────┘  └─────────────┘  └─────────────┘  └─────────────────┘
                    │
                    ▼
   ┌─────────────────────────────────────────────────────────────────────────┐
   │  PERSISTENCE                                                             │
   │  Backend: conversation_db (SQLite) — source of truth for conversations  │
   │  Frontend: sync or cache from API; same conversation list everywhere     │
   └─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Backend: One Agent, Two Modes, Plan & Steps

- **State** (extend `AgentState`):
  - `mode: "reasoning" | "fast"` (from request).
  - `intent: "question" | "action" | "mixed"` (optional; can be inferred by agent).
  - `plan: List[PlanStep]` — ordered steps; each step has `id`, `description`, `status: "pending" | "running" | "completed" | "failed"`.
  - Existing: `messages`, `system_prompt`, `file_context`, etc.

- **Graph behavior**:
  - **Reasoning**: System prompt instructs agent to (1) infer intent, (2) if action/multi-step, output a plan (steps), (3) execute one step at a time, (4) after each tool result, update step status to completed/failed and continue or summarize.
  - **Fast**: System prompt instructs agent to answer or act directly; no mandatory plan; minimal tool use.
  - **Tools**: Unchanged; agent continues to call one or many tools as needed. Plan is a structured output or a dedicated “submit_plan” / “step_complete” mechanism (e.g. tool that updates plan state, or special message type).

- **Streaming**: One event schema for all surfaces (e.g. `content`, `reasoning`, `plan`, `plan_step_update`, `tool`, `sentence_end` for TTS, `done`, `error`). Chat/SSE and WebSocket both emit these; frontend renders plan and step completion in Chat/Focus, and can simplify for Voice/Ray.

### 2.3 Intent & Planning (Cursor/Windsurf Style)

- **Interpret**: From user message, agent decides question vs action vs mixed.
- **Plan** (Reasoning mode, for actions): Produce ordered steps, e.g.  
  “1. Get frontmost app. 2. Open Safari. 3. Navigate to URL. 4. Fill search box.”
- **Execute**: Invoke tools step by step; after each tool result, mark that step completed (or failed) and stream `plan_step_update`.
- **Verify**: Optionally use tools like `get_frontmost_app`, `browser_get_page_info` to confirm before moving on.
- **Complete**: When all steps done or user task satisfied, send final summary and mark plan complete.

Implementation options:
- **Option A**: Agent outputs a “plan” as structured content (e.g. JSON or markdown list); a lightweight “planner” node parses it into `state["plan"]`; execution node runs tools and updates step status.
- **Option B**: Agent emits tool calls; a “plan” is derived from the sequence of tool calls (each tool call = one step); backend tracks step index and streams `plan_step_update` as tools finish.
- **Option C**: Dedicated “create_plan” tool that the agent calls with a list of steps; then “execute_step” or normal tools; “mark_step_done” tool or automatic update when a tool returns success.

Recommendation: Start with **Option B** (derive plan from tool-call sequence) to avoid changing model output format; later add Option A or C for explicit user-visible plans.

### 2.4 Persistence & Wiring

- **Backend**:
  - Every chat/voice request includes `conversation_id` (or create one). Load last N messages from `conversation_db` when present; after each assistant turn, append messages to `conversation_db`. WebSocket sessions keyed by `conversation_id` so reconnects resume same thread.
  - One streaming endpoint (or two with same event schema): e.g. `POST /api/chat/stream` and `WS /api/ws/conversation` both accept `conversation_id`, `mode`, and same semantics; both persist to `conversation_db`.

- **Frontend**:
  - **Single conversation store**: One “current conversation” ID and list of conversations; Chat, Focus, Conversation, and Ray all read/write this. Conversation list can sync from backend `GET /api/conversations` or stay local-first with optional sync.
  - **Config**: All URLs (API base, WebSocket) from Config; no hardcoded `127.0.0.1` or `localhost` in ConversationViewModel.
  - **Plan & steps UI**: In Chat/Focus, show plan (if present) and step status (pending/running/completed/failed); “mark when completed” = backend sends `plan_step_update`, frontend updates step list.

### 2.5 Modes (Chat, Focus, Conversation, Ray) — Wired

| Surface | Input | Output | Backend path | Conversation |
|---------|--------|--------|--------------|--------------|
| Chat | Text (+ files) | Stream: content, reasoning, plan, steps, tools | POST /api/chat/stream | Same conversation_id, persisted |
| Focus | Text (+ files) | Same as Chat | Same | Same store as Chat |
| Conversation | Voice | Voice + optional transcript | WS /api/ws/conversation | Same conversation_id, persisted |
| Ray | Text | Quick result or “Open in Chat” | POST /api/chat/stream or same WS | Create/reuse conversation when “Full Chat” |

- All use same `conversation_id` when continuing a thread; backend and (optionally) frontend DB keep one history per conversation.
- Same `mode` (reasoning/fast) available everywhere; default Fast for Voice and Ray.

---

## 3. Implementation Phases (Revised)

### Phase 1 — Reasoning vs Fast & Intent (Backend)

1. Add `mode` and optional `plan` / `plan_steps` to request and state.
2. In graph system prompt, branch on `mode`: Reasoning = “identify intent, plan steps for actions, execute and mark complete”; Fast = “answer or act directly.”
3. Implement “plan as sequence of tool calls”: when in Reasoning mode and agent issues tool calls, backend maps them to steps and streams `plan_step_update` (step index, status) as each tool completes.
4. Extend stream schema: `plan` (full plan when created), `plan_step_update` (step_id/idx, status), keep `content`, `reasoning`, `tool`, `done`, `error`; add `sentence_end` for TTS where needed.

### Phase 2 — One Stream Contract & Persistence

5. Unify WebSocket and SSE event shapes so both can emit plan and step updates; WebSocket continues to send `sentence_end` for voice.
6. Require or create `conversation_id` on every request; load history from `conversation_db`; after response, append messages to DB.
7. Frontend: use Config for WebSocket URL; pass `conversation_id` and `mode` from all surfaces.

### Phase 3 — Frontend: Plan + Steps UI & One Conversation

8. In Chat/Focus: parse and show plan (list of steps); on `plan_step_update`, update step status (pending → running → completed/failed).
9. Single conversation store: current conversation ID shared; Conversation and Ray write/read same store; “Open in Chat” from Ray creates or continues conversation and adds messages.
10. Optional: Sync conversation list from backend; or keep local-only with same IDs as backend when persisting.

### Phase 4 — Polish & Robustness

11. Settings: default mode (Reasoning vs Fast) per surface or global; API URL/WebSocket from Config everywhere.
12. Error handling and retry unified; plan step “failed” with reason; user can retry step or abort.
13. Voice: keep short replies (Fast default), interrupt, re-listen; optional “deep think” that uses Reasoning mode.

---

## 4. References (Jan 2026)

- **Reasoning vs Fast**: Claude extended thinking (thinking budget), Google AI Mode vs Overviews, OpenAI reasoning best practices — reasoning as a controllable resource (correctness vs latency vs cost).
- **Cursor/Windsurf**: Agentic planning = interpret task → plan (implicit or explicit steps) → execute step-by-step → verify; multi-step execution and context assembly.
- **Intent & Planning**: Intent classification (question vs action) upstream; plan reuse and step-wise execution in LLM agents; LangGraph checkpoints for resumable execution.
- **Unified assistant**: Single main agent with multi-tool orchestration; all surfaces as different entry points to the same backend and conversation model.

---

## 5. Summary Table

| Area | Current | Target |
|------|--------|--------|
| **Modes** | None | **Reasoning** (plan, steps, multi-tool) vs **Fast** (direct answer/action) |
| **Intent** | Implicit in prompt | Explicit: **question** vs **action** vs mixed; drive planning |
| **Planning** | Ad hoc in prompt | **Plan** (ordered steps) + **mark completed** per step; streamed to client |
| **Tools** | One agent, many tools | Same; agent uses **multiple tools** as needed; tools = sub-capabilities |
| **Surfaces** | Chat, Focus, Voice, Ray | **Same Jarvis**; different entry points; same backend, DB, conversation |
| **Backend** | Two paths, two prompts | One agent, **mode** in state; one stream schema; **conversation_id** + DB persist |
| **Frontend** | Three VMs, partial sharing | **One conversation store**; plan/steps UI; Config for all URLs |
| **Persistence** | Frontend-only / in-memory WS | **Backend DB** as source of truth; all surfaces use **conversation_id** |

This plan reworks Jarvis into a single, intent-aware, plan-capable AI with Reasoning and Fast modes, all interaction surfaces wired to the same backend and conversation model, with a clear “plan and mark when completed” flow for complex tasks.
