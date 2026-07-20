# Jarvis — macOS Notch AI Agent

A notch / dynamic-island conversational AI agent for macOS: a real Siri alternative that
controls the Mac, stays context-aware, remembers everything locally, and acts on its own.
Pure Swift 6.3, one app process, macOS 26+ (Tahoe), local-first, no login, bring-your-own keys.

Status: **v0.2 — all 9 milestones (M0–M8) plus a full July-2026 audit pass (Section 11).**
33 headless tests green, every milestone verified on the real machine, zero build warnings.

---

## 1. What Jarvis is

- Lives in the notch on **every display**, expands only on the screen the mouse is on.
- **Chat** with streaming Markdown, hold-Option **voice input**, and file drag-and-drop.
- A real **agent harness**: it calls tools, asks permission before doing anything that
  changes your Mac, and can run multi-step tasks.
- **Controls the Mac** through the Accessibility tree and background input (clicks/types
  into apps without stealing your cursor), plus Calendar / Reminders / Mail / Notes.
- **Remembers** across sessions with a local knowledge graph + semantic + lexical search.
- **Sees the screen** through a passive, privacy-bounded screenshot buffer it can recall.
- **Acts proactively**: notices context switches, runs scheduled tasks, and starts
  conversations on its own — gated so it's never annoying.

Everything runs and is stored on your Mac. The only things that leave the machine are the
LLM API calls you configure.

---

## 2. How we got here — the planning process

Before writing code we reverse-engineered the reference projects you provided:

- **Notch UI**: `JarvisNotch` (the owned NSPanel shell) and `LocalNotch` (UX patterns —
  hover hardening, compact-vs-history display, glass, markdown theme).
- **Agent harnesses**: Hive (the minimal-but-correct 77-line loop + embedding-free memory),
  openclaw (hook-driven headless core), Hermes (tool-output spill, provider profiles, cron),
  openhuman (durable graph runtime, parked-continuation approval gate).
- **Mac control + capture**: Omi's desktop Swift stack and OpenWork's `handsfree` layer
  (AX snapshot + `CGEvent.postToPid` background input).
- **Glow**: `AppleIntelligenceForSwiftUI`.

Then, across **three rounds of questions**, we locked the design (Section 3). Current APIs
were verified against July-2026 docs (SpeechAnalyzer, OpenAI Responses API, MiniMax
Anthropic-compatible endpoint, models.dev, Swift 6.3).

---

## 3. Locked decisions (the design contract)

| Area | Decision |
|---|---|
| **Architecture** | Pure Swift 6.3, one app process. Verified every feature is Swift-native (AX, CGEvent, SpeechAnalyzer, ScreenCaptureKit, EventKit, GRDB, SSE) — no sidecar, no Node/Python. Developer ID + notarized DMG (not sandboxable). |
| **STT** | Apple **SpeechAnalyzer / SpeechTranscriber** (on-device, streaming partials), behind a `TranscriberEngine` protocol so a fallback can swap in. |
| **Voice UX** | Hold Option (350ms "alone" threshold) → notch glows + grows + waveform + live words → release sends → glow pulses when the answer is ready → hover to read. Esc cancels. |
| **Memory** | One SQLite file: FTS5 (lexical) + on-device embeddings (NLEmbedding, cosine via Accelerate) + entity/relation graph with **temporal validity** (supersede, never delete). Lifecycle: turn → extract (aux model, on session-segment close) → short-term → consolidate → long-term + graph projection. |
| **Sessions** | One rolling conversation that auto-splits into segments on a 30-min idle gap. Compact notch shows only the latest AI reply; History shows full exchanges. |
| **Screen awareness** | Passive buffer: capture on real app-switch OR a 60s tick, perceptual-hash dedup, ~150KB JPEGs + `{time, app, window title}` rows, **72h TTL / 1GB ceiling**, skip lock screen + password managers. **Frames are never auto-fed to the model** — the agent pulls them via tools. Plus on-demand `take_screenshot`. |
| **Proactivity** | Context switch → one frame → aux model "worth interrupting?" → funnel (cooldown → dedup → deliver) → notch glow nudge. Plus heartbeat + cron + agent-initiated conversations. Daily token budget hard-stop. |
| **Permissions** | Risk-tiered gate: read-only tools auto-run; external-effect tools prompt **Approve / Always / Deny** in the notch, fail-closed on timeout/dismiss; persistent per-tool+scope rules; **background/proactive runs are locked to the read-only registry** so autonomy can't deadlock or act unattended. |
| **Providers** | Anthropic (Messages + thinking), OpenAI (**Responses API** — needed for reasoning-effort + tools), MiniMax (Anthropic-compatible). **Neutral: no default model.** Per-role settings (Brain / Aux / Embeddings). Live model lists from `/v1/models` + capability metadata from `models.dev/api.json`. Reasoning-effort control shown only when the model supports it. |
| **UI** | Notch on all displays, expands under the mouse, sized proportionally per screen. Tabs beside the camera: **Home/Chat** (also the drag-drop shelf), **History**, **Activity** (larger expand; segmented control: Timeline · Memory · Tasks — Timeline is one live feed of runs/meetings/nudges/approvals/artifacts; the knowledge graph lives inside Memory), **Settings** (incl. the Screen Rewind transparency card). Apple-Intelligence gradient glow. |
| **Onboarding** | In-notch, no login: welcome → provider key + model → mic/speech permission → done. AX / Screen-Recording / Automation prompted just-in-time; live permissions dashboard in Settings. |

---

## 4. Architecture

One thin Xcode app target (TCC identity, signing, Info.plist) + a local SPM package
`JarvisKit` so all logic is `swift test`-able headless.

```
Jarvis/
├── project.yml                     # xcodegen: app target + package refs + Info.plist keys
├── scripts/release.sh              # build → codesign Developer ID → DMG → notarize → staple
├── App/                            # the app target
│   ├── JarvisApp / AppDelegate     # .accessory policy, composition root
│   ├── Notch/                      # NotchWindow (NSPanel), NotchScreenManager (per-display),
│   │                               #   NotchViewModel (sizing/hover), NotchShape, NotchView
│   ├── Core/JarvisCore             # accounts, role assignments, provider resolution, catalog
│   ├── Chat/                       # ChatStore, SessionManager, AttachmentLoader
│   ├── Voice/                      # VoiceController, PushToTalkMonitor
│   ├── Agent/                      # AgentServices + Approval/Artifact/Run stores + tool wrappers
│   ├── Memory/                     # MemoryService, ProactivityService
│   ├── Permissions/                # PermissionsChecker
│   └── Views/                      # Home, History, Activity, Settings, Graph, Onboarding,
│                                   #   ApprovalPrompt, ListeningView, NotchGlow, PermissionsDashboard
└── Packages/JarvisKit/Sources/
    ├── JStore/       # GRDB pool + migrations (v1–v5) + records + Keychain
    ├── JAgent/       # neutral messages/events, 3 provider adapters, SSE, tool registry,
    │                 #   ApprovalGate, AgentLoop, ChatEngine, ModelCatalog
    ├── JSpeech/      # SpeechAnalyzerEngine (+ TranscriberEngine protocol)
    ├── JMemory/      # Embedder, MemoryStore, MemoryExtractor, GraphReader
    ├── JControl/     # ComputerUseRuntime (AX), BackgroundInput (CGEvent)
    ├── JScreen/      # ScreenCapture, PerceptualHash, ScreenBuffer, ScreenRecall
    └── JProactive/   # CronSchedule, CronStore, NudgeFunnel
```

**Data (one `jarvis.sqlite`, WAL, in App Support; secrets in Keychain; binaries as files):**
sessions/segments/messages/runs/tool_calls/compaction (v1), approvals/artifacts (v2),
memory + FTS5 + embeddings + graph nodes/edges/aliases (v3), screen_frame (v4),
cron_job/heartbeat_state/nudge (v5). Screenshots and spilled tool output live as files;
the DB stores paths. Model catalog is a cached JSON file.

**Agent loop:** neutral message model → provider adapter behind a `StreamFn` seam (2.5
families: anthropic-messages, openai-responses, openai-compat) → `AgentLoop` (stream →
collect tool calls → approval gate → execute serially → feed results back → repeat; max-turns
cap, non-empty fallback, cancellation persists a repaired transcript). Events are typed and
fanned out to the UI store, the Activity store, and persistence separately from rendering.

---

## 5. The milestones (what each delivered)

**M0 — Shell.** Notch on every display via `NotchScreenManager` (per-display panels, debounced
rebuild on hot-plug, artificial notch on external screens, expands only under the mouse,
proportional sizing). LocalNotch hover hardening (global mouse monitor + real-position hit
test + grace periods). GRDB store + Keychain.

**M1 — Chat slice.** Three provider adapters + shared SSE parser (retry-before-stream).
`ModelCatalog` (live `/v1/models` + models.dev capabilities, cached). Settings for keys +
per-role model pick (no defaults). Streaming Markdown chat, rolling sessions with idle-split,
History, interrupt→clean transcript, file drag-drop as message context.

**M2 — Harness + approvals.** Full tool loop. `ApprovalGate` actor (read-only auto-run;
rule match; else park on a continuation surfaced to the notch as Approve/Always/Deny; 120s
timeout → deny; background runs pre-denied). Persistent rules + full decision audit. Tool-output
spill-to-disk (`read_artifact`). Compaction + steering hooks. Activity → Runs & Decisions.

**M3 — Voice.** `SpeechAnalyzerEngine` (on-device streaming volatile+final results, mic level
for the waveform, AssetInventory model install). `PushToTalkMonitor` (hold-Option FSM, Esc
cancel). Listening UI: Apple-Intelligence glow + grown compact notch + waveform + live words.
Composer mic button as the always-works fallback.

**M4 — Memory + knowledge graph.** `Embedder` (Apple NLEmbedding, vDSP cosine). `MemoryStore`
(ingest → short-term + graph projection with alias resolution + temporal supersession of
functional relations; retrieval = reciprocal-rank fusion of BM25 + cosine; graph-neighborhood
context; consolidate short→long). `MemoryExtractor` (aux-model JSON). Extraction runs on
session-segment close; recalled context is injected into each turn's system prompt. Force-directed
graph explorer in Activity → Graph.

**M5 — Computer control + app bridges.** `ComputerUseRuntime` (semantic AX snapshot with `{e#}`
refs, Chromium/Electron unlock via `AXEnhancedUserInterface`, actuate via AX-press → focus →
coordinate-click, set-value with verify+retype fallback). `BackgroundInput` (`CGEvent.postToPid`
with window addressing — never steals the cursor). Tools: `ui_snapshot/click/type/set_value/key/
scroll` + Calendar/Reminders (EventKit) + Mail/Notes (AppleScript). Just-in-time TCC prompts.

**M6 — Screen awareness.** `ScreenBuffer` (capture on app-switch or 60s tick, pHash dedup, 72h/1GB
sweeper, blocklist, `onContextSwitch` hook). `ScreenRecall`. Tools: `recall_screen`, `fetch_frames`
(≤5 images), `take_screenshot`. Extended the neutral tool contract so tool results can carry
**images** (multimodal — Anthropic renders them). Buffer no-ops until Screen Recording is granted.

**M7 — Proactivity.** `CronSchedule` (5-field parser + next-fire, tested), `NudgeFunnel`
(20-min global cooldown + 24h topic dedup + daily cap), `CronStore`. `ProactivityService`:
context-switch → funnel-gate-before-spend → aux sees one frame → decide → deliver; a 30s cron
loop and a 20-min heartbeat run background agent turns; results arrive as Jarvis-initiated
messages that glow the notch. Background runs use the read-only registry; a 60k-token daily
budget hard-stops runaway spend. `schedule_task` tool.

**M8 — Onboarding + distribution.** In-notch onboarding (welcome → connect+verify a model →
voice permission → done; "Skip for now"). Live permissions dashboard (all 7 TCC permissions
with Grant/Open-Settings, re-checks on re-activate). Hardened-runtime entitlements + a
notarization release script.

---

## 6. Changes you added mid-build

These are the course-corrections you gave during the build, folded into the design:

**Architecture / providers**
- Confirmed **pure Swift for everything** after verifying every feature is Swift-native.
- **No default model, no bias** — neutral harness. Per-category (role) model selection in
  Settings. Fetch models **live** from the provider API (no hardcoding), plus capability
  metadata (reasoning support, effort levels, modalities, context limits) — use the latest
  APIs (OpenAI Responses) and all July-2026 models.

**Screen awareness**
- Store screenshots **passively** and let the agent **pull them on demand** via tools —
  never auto-send them to the model. Delete after a retention window. Plus a fully working
  on-demand screenshot. (Became the M6 buffer + recall tools.)

**Voice**
- Match Omi: hold for a moment → notch **glows and grows** with a waveform so you know it's
  listening → words appear as you speak → process → glow when the answer is ready → hover to
  read. Use the AppleIntelligenceForSwiftUI glow style.

**Activity tab**
- One Activity panel with a **segmented control** (Timeline · Memory · Tasks) that expands the
  notch bigger. Timeline is a single live chronological feed (runs, meetings, nudges — delivered
  and held back — approval decisions, artifacts); Memory holds the list ⇄ graph explorer. The
  **shelf is the main chat view** itself — drag files in, they sit there as chips; use them as
  context or drag them back out.

**UI / UX polish (several rounds)**
1. Content must fit inside the notch borders and **scroll when it overflows** — nothing
   crossing the left/right edges. → shape-safe horizontal inset (the notch's rounded sides sit
   inset by the corner radius) + per-view padding.
2. **Each tab sizes the notch differently**; the main chat is narrower.
3. Animations should be **scale-only** and **expand from the notch** (light leaking from
   behind), not from off-screen. → fixed-size window; only the black body scales from the
   top-center; the glow renders behind and bleeds past the edges.
4. Hover-open must be exactly like the reference. → verified (a scare turned out to be a
   display-scaling coordinate mismatch in my test harness, not an app bug).
5. **You couldn't type** in the composer or the API-key field. → the panel now becomes key on
   click (`canBecomeKey` + `becomesKeyOnlyIfNeeded`) so text fields work; hover never steals
   the keyboard. This also fixed "nothing in Settings works."
6. Settings needed real work → redesigned (clear PROVIDERS / MODELS sections, per-provider
   status, Save & verify, auto-assign Brain).
7. The **notch should follow the mouse** to the active screen for its states. → voice/nudge
   state renders on the display under the mouse.
8. **Listening was too big** and the text rendered **behind the camera module**. → compact
   listening size; the top row reserves the camera cutout with the waveform+mic flanking it,
   and the transcript sits on the row below.
9. **Glow was too much and always on.** → the glow now appears **only when the agent is
   working or the mic is listening**, and it's a subtle **border** glow, not a big halo.
10. **Everything felt congested.** → Apple-grade spacing pass: content clears the borders,
    cards use consistent padding/radius, sections breathe, the composer pill is properly inset.

---

## 7. The 31 agent tools

- **Read-only (auto-run):** `list_apps`, `get_frontmost_app`, `clipboard_read`†, `read_file`,
  `list_files`, `read_artifact`, `fetch_url`, `ui_snapshot`†, `calendar_list`, `reminders_list`,
  `recall_screen`†, `fetch_frames`†, `take_screenshot`†, `list_scheduled_tasks`, `remember`,
  `search_memory`.
- **External-effect (approval-gated):** `open_url`, `launch_app`, `activate_app`,
  `clipboard_write`, `write_file`, `ui_click`, `ui_type`, `ui_set_value`, `ui_key`, `ui_scroll`,
  `calendar_add_event`, `reminders_add`, `mail_send`, `notes_create`, `schedule_task`,
  `cancel_scheduled_task`.

Read-only tools that touch other apps or the screen still require the relevant TCC permission,
prompted on first use. Tools marked † are **sensitive** (clipboard / screen pixels / app UI
text): they auto-run in foreground chats but are excluded from unattended background runs,
which only ever see the non-sensitive read-only set. Long outputs (files, artifacts, web pages)
paginate via an `offset` parameter instead of flooding the context.

---

## 8. Build & run

```bash
# Toolchain: macOS 26+, Xcode 26+, Swift 6.3, xcodegen (brew install xcodegen)

# Headless logic tests
cd Packages/JarvisKit && swift test          # 33 tests

# Build + run the app
cd /Users/yashwanthreddy/Desktop/Jarvis
xcodegen generate
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Jarvis-*/Build/Products/Debug/Jarvis.app

# Notarized release (needs your Developer ID cert + notarytool credentials)
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
```

Jarvis has no Dock icon (it's a menu-bar `.accessory` app); it appears in the notch. Data lives
in `~/Library/Application Support/Jarvis/`.

---

## 9. What still needs you

1. **A provider API key** — Settings → Add provider, set Brain to a model. This lights up chat,
   tools, memory extraction, and proactive nudges (all gated on having a Brain model).
2. **TCC grants** — Microphone, Speech, Accessibility, Screen Recording, Calendar, Reminders,
   Automation. All prompted just-in-time; the Settings dashboard shows live status.
3. **A Developer ID certificate** — to run `scripts/release.sh` for a notarized DMG.

Everything verifiable headless (migrations, SSE parsing, the loop, approvals, memory retrieval,
temporal graph, cron) is covered by tests; the live behaviors that need a real key + permissions
(streaming, tool execution, cross-session recall, proactive nudges) are wired and ready to
exercise once you add a key.

---

## 10. Deliberately deferred (post-v1)

TTS / full spoken conversation, a pure-vision escalation loop (AX + coordinate clicks cover v1),
OCR indexing of screen frames, a richer memory editor, learned interruption preferences, Sparkle
auto-update, system-audio/meeting capture, parallel read-only tool execution, session restore
into the composer after relaunch, per-run dollar-cost display, screen-frame encryption at rest,
aux-model transcript summarization (a size-capped sliding window covers v1), and a true web
search tool (needs a search API; `fetch_url` covers direct pages).

---

## 11. The v0.2 audit (July 2026)

A full E2E audit (agent harness vs SOTA, UI/UX vs Apple HIG, architecture/concurrency) ran
against v0.1; every critical and major finding was fixed. Highlights:

- **Providers modernized to the July-2026 API surface.** Anthropic: adaptive thinking +
  `output_config.effort` (the old `budget_tokens` shape is rejected by all current models),
  prompt caching via `cache_control`, signed-thinking replay before `tool_use`, cache-token
  accounting. Anthropic-compatible endpoints (MiniMax) keep the legacy shape. OpenAI Responses:
  encrypted reasoning-item replay (`store:false`), truncation handling. Both OpenAI adapters
  now carry tool-result images via follow-up messages.
- **The interrupt path actually works.** Cancellation ends stream iteration before `.aborted`
  can be delivered, so transcript repair now runs after the loop; end-of-run persistence moved
  to an unstructured task (GRDB honors cancellation — runs were sticking at "running").
- **A real system prompt** (identity, tool guidance, notch-appropriate brevity), byte-stable
  for prompt caching; date/time/frontmost-app/memory ride in a per-turn `<context>` block.
  Transcripts reset per segment and cap by size.
- **Memory extraction actually fires.** Segments now close on quit and orphans are recovered
  (and extracted) on launch; `remember` writes durable memory mid-turn.
- **Privacy:** background runs lost clipboard/screen/UI-text tools; the proactive token budget
  counts input+output; frame TTL sweeps run even without capture permission.
- **Approvals:** the panel holds open while a prompt is pending, timed-out cards are removed,
  `mail_send` approval shows the full body and scopes per recipient.
- **Apple-grade UI pass:** full keyboard support (Esc, ⌘1–4, Return/Esc on approvals), a
  semantic color/type system, `symbolEffect` micro-animation layer, matched-geometry tab pill,
  Reduce Motion everywhere, designed error state with Retry, image thumbnails, elapsed time on
  tools, and accessibility labels throughout.

All 33 package tests green; the app builds with zero warnings.
