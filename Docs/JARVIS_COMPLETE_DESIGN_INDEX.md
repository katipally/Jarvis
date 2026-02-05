# JARVIS AI - Complete System Design

> **Version:** 5.2 | **Date:** February 3, 2026

---

## Document Index

This design document is split into 4 parts for readability. Each part contains comprehensive explanations, rationale, code examples, and diagrams.

| Part | Title | Contents | Lines |
|------|-------|----------|-------|
| [Part 1](./JARVIS_COMPLETE_DESIGN_PART1.md) | Architecture & Core | Vision, tech stack, LLM system, sessions, colors | ~750 |
| [Part 2](./JARVIS_COMPLETE_DESIGN_PART2.md) | UI/UX Design | Design philosophy, all 4 modes, components | ~750 |
| [Part 3](./JARVIS_COMPLETE_DESIGN_PART3.md) | Backend + macOS Integration | Tony, agents, **macOS APIs**, MCP, RAG, memory, voice | ~1800 |
| [Part 4](./JARVIS_COMPLETE_DESIGN_PART4.md) | Scenarios & Implementation | Detailed scenarios, error handling, 10-week plan | ~600 |

### Reference Documents

| Document | Description |
|----------|-------------|
| [MACOS_CAPABILITIES.md](./MACOS_CAPABILITIES.md) | Complete API reference for 50+ macOS capabilities |

---

## Quick Start

1. **Read Part 1** for architecture understanding
2. **Read Part 2** for UI/UX specifications
3. **Read Part 3** for backend + macOS system integration
4. **Read Part 4** for scenarios and implementation timeline

---

## System Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              JARVIS ARCHITECTURE                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         FRONTEND (SwiftUI)                           │   │
│   │                                                                      │   │
│   │   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │   │
│   │   │   Chat   │ │   Ray    │ │  Voice   │ │  Focus   │              │   │
│   │   │  (iMsg)  │ │(Spotlight)│ │(Siri 26) │ │ (Copilot)│              │   │
│   │   └──────────┘ └──────────┘ └──────────┘ └──────────┘              │   │
│   │                              │                                       │   │
│   │                    WebSocket Connection                              │   │
│   └───────────────────────────────────────────────────────────────────────┘   │
│                                   │                                          │
│   ┌───────────────────────────────────────────────────────────────────────┐   │
│   │                         BACKEND (Python)                              │   │
│   │                                                                      │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │                    TONY ORCHESTRATOR                         │   │   │
│   │   │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │   │   │
│   │   │  │ Classify│ │  Plan   │ │ Execute │ │ Respond │           │   │   │
│   │   │  │ (SetFit)│ │  (LLM)  │ │ (Tools) │ │  (LLM)  │           │   │   │
│   │   │  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │   │   │
│   │   └─────────────────────────────────────────────────────────────┘   │   │
│   │                              │                                       │   │
│   │   ┌──────────────────────────────────────────────────────────────┐   │   │
│   │   │                      13 AGENTS (62 Tools)                     │   │   │
│   │   │  AppLifecycle | Browser | WebSearch | SystemControl | ...    │   │   │
│   │   └──────────────────────────────────────────────────────────────┘   │   │
│   │                              │                                       │   │
│   │   ┌────────────┐ ┌────────────┐ ┌────────────┐                     │   │
│   │   │    RAG     │ │   Memory   │ │   Voice    │                     │   │
│   │   │ (E5+Lance) │ │  (Cognee)  │ │ (Pipecat)  │                     │   │
│   │   └────────────┘ └────────────┘ └────────────┘                     │   │
│   └───────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Features

| Feature | Description | Part |
|---------|-------------|------|
| **4 Interaction Modes** | Chat, Ray, Voice, Focus | Part 2 |
| **Flexible LLM** | Ollama (local) + OpenAI (cloud) | Part 1 |
| **13 Agents** | 62 tools for complete Mac control | Part 3 |
| **Hybrid RAG** | Vector + keyword search | Part 3 |
| **GraphRAG Memory** | Cognee for entity relationships | Part 3 |
| **Ultra-low Latency Voice** | ~500ms end-to-end | Part 3 |
| **Apple Native UI** | Liquid Glass, SF Symbols 7 | Part 2 |
| **MCP Architecture** | Dynamic capability discovery | Part 5 |
| **50+ macOS APIs** | Calendar, Contacts, UI Automation, Vision | Part 5 |
| **Agent Skills** | Self-documenting, hot-reloadable capabilities | Part 5 |

---

## Technology Stack

| Layer | Technology | Reason |
|-------|-----------|--------|
| Frontend | SwiftUI | Native macOS, modern patterns |
| Backend | Python + FastAPI | Async, AI ecosystem |
| Communication | WebSocket | Real-time bidirectional |
| LLM | Ollama / OpenAI | Local privacy + cloud power |
| Embeddings | E5-small (384d) | Fast, accurate |
| Vector DB | LanceDB | Local, serverless |
| Graph DB | Cognee | GraphRAG, smart recall |
| Classifier | SetFit | 5ms intent classification |
| Voice | Pipecat + Silero + Piper | Complete voice pipeline |

---

## Implementation Timeline

| Week | Focus | Milestone |
|------|-------|-----------|
| 1-2 | Foundation | WebSocket working |
| 3-4 | Core AI | Intelligent responses |
| 5-6 | UI | All 4 modes visual |
| 7-8 | Agents | Mac control working |
| 9 | Integration | Voice working |
| 10 | Polish | Production ready |

See [Part 4](./JARVIS_COMPLETE_DESIGN_PART4.md#4-implementation-plan) for detailed breakdown.

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 5.2 | Feb 3, 2026 | Added Part 5: macOS System Integration, MCP architecture |
| 5.1 | Feb 1, 2026 | Enhanced with detailed explanations |
| 5.0 | Feb 1, 2026 | Split into 4 parts |
| 4.0 | Jan 31, 2026 | Added UI specifications |
| 3.0 | Jan 30, 2026 | Added agents and tools |
| 2.0 | Jan 29, 2026 | Initial consolidation |
