# Jarvis AI Assistant - Backend

A powerful AI assistant backend built with FastAPI, LangGraph, and modern AI technologies.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         API Gateway (FastAPI)                     │
│  • /api/chat/stream (SSE) - Text chat with streaming             │
│  • /api/ws/conversation (WebSocket) - Voice conversation         │
│  • /api/memory/* - Memory operations                             │
│  • /api/voice/* - Voice pipeline                                 │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│                     Jarvis Agent Core (LangGraph)                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │   Intent    │→ │   Planner   │→ │  Executor   │               │
│  │  Classifier │  │(Reasoning)  │  │ (Tools)     │               │
│  └─────────────┘  └─────────────┘  └─────────────┘               │
└────────────────────────────┬─────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐  ┌─────────────────┐  ┌────────────────────┐
│ Memory Layer  │  │   Tool Layer    │  │   Voice Layer      │
│ • Graph Store │  │ • Mac Automation│  │ • STT (Deepgram)   │
│ • Vector Store│  │ • Browser       │  │ • TTS (OpenAI)     │
│ • Sessions    │  │ • Web Search    │  │ • VAD (Silero)     │
└───────────────┘  └─────────────────┘  └────────────────────┘
```

## Features

### Agent System
- **Dual Modes**: Reasoning (detailed, multi-step) and Fast (quick responses)
- **Intent Classification**: Automatic detection of question/action/mixed intents
- **Step-by-Step Planning**: Visual plan display with real-time status updates
- **Tool Orchestration**: 40+ tools for Mac automation, browser control, and more

### Memory System (Cognee-inspired)
- **Knowledge Graph**: Entity-relation storage using NetworkX (Neo4j ready)
- **Vector Store**: ChromaDB for semantic search
- **Entity Extraction**: Automatic extraction of facts, preferences, and entities
- **Hybrid Search**: Combined graph traversal and vector similarity

### Voice Pipeline (Pipecat-inspired)
- **STT**: Deepgram, OpenAI Whisper, or Apple Speech Framework
- **TTS**: OpenAI, ElevenLabs, or system voices
- **VAD**: Silero VAD for accurate speech detection
- **Interruption Handling**: Natural conversation flow

### Unified Streaming
All responses use a unified event schema:
- `content`: Text content chunks
- `reasoning`: Chain-of-thought steps
- `plan`: Execution plan with steps
- `plan_step_update`: Step status changes
- `tool`: Tool execution events
- `intent`: Intent classification
- `done`: Completion with stats

## Installation

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install dependencies
pip install -r requirements.txt

# Copy environment file
cp .env.example .env

# Edit .env with your API keys
nano .env

# Run the server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## API Reference

### Chat Endpoints

#### POST /api/chat/stream
Stream a chat response with full event schema.

```json
{
  "messages": [{"role": "user", "content": "Open Safari"}],
  "mode": "reasoning",
  "file_ids": [],
  "include_reasoning": true,
  "include_plan": true
}
```

#### WebSocket /api/ws/conversation
Real-time voice conversation.

```json
// Client → Server
{"type": "text", "content": "Hello", "session_id": "..."}

// Server → Client
{"type": "text_delta", "content": "Hi"}
{"type": "sentence_end", "sentence": "Hi there!"}
{"type": "text_done", "full_text": "Hi there!"}
```

### Memory Endpoints

#### GET /api/memory/search
Search memories using hybrid search.

```
GET /api/memory/search?query=user%20preferences&k=5
```

#### POST /api/memory/add
Store a new memory.

```json
{
  "content": "User prefers dark mode",
  "memory_type": "preference",
  "extract_entities": true
}
```

### Voice Endpoints

#### POST /api/voice/tts/synthesize
Synthesize text to speech.

```json
{
  "text": "Hello, I'm Jarvis",
  "voice": "alloy",
  "speed": 1.0
}
```

#### WebSocket /api/ws/voice
Real-time voice processing with STT/TTS.

## Project Structure

```
backend/
├── agents/
│   ├── graph.py        # LangGraph workflow
│   ├── state.py        # State schema
│   └── tools.py        # Tool definitions
├── api/
│   ├── models.py       # Pydantic models
│   └── routes/
│       ├── chat.py     # Chat endpoints
│       ├── conversation.py  # Voice WebSocket
│       ├── memory.py   # Memory endpoints
│       └── voice.py    # Voice endpoints
├── core/
│   ├── config.py       # Settings
│   ├── chroma_client.py  # Vector DB
│   └── logger.py       # Logging
├── services/
│   ├── memory/         # Memory system
│   │   ├── entity_extractor.py
│   │   ├── knowledge_graph.py
│   │   └── memory_service.py
│   ├── voice/          # Voice pipeline
│   │   ├── stt_service.py
│   │   ├── tts_service.py
│   │   ├── vad_service.py
│   │   └── voice_pipeline.py
│   └── mac_automation/  # Mac tools
└── main.py
```

## Configuration

Key environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_API_KEY` | OpenAI API key | Required |
| `OPENAI_MODEL` | Primary model | `gpt-4o` |
| `OPENAI_FAST_MODEL` | Fast mode model | `gpt-4o-mini` |
| `DEEPGRAM_API_KEY` | Deepgram STT | Optional |
| `CHROMA_DB_PATH` | Vector DB path | `./chroma_db` |

## Development

```bash
# Run with auto-reload
uvicorn main:app --reload

# Run tests
pytest

# Format code
black .
isort .
```

## License

MIT License - See LICENSE file for details.
