# Jarvis AI Assistant - Backend

Modern AI assistant backend built with FastAPI, LangGraph, and GPT-5-nano.

## Quick Start

### 1. Setup Environment

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure Environment Variables

```bash
# Copy example env file
cp .env.example .env

# Edit .env and add your OpenAI API key
# OPENAI_API_KEY=sk-...
```

### 3. Run Server

```bash
# Development mode
python main.py

# Or with uvicorn
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## API Endpoints

### Health Check
```
GET /health
```

### Chat (Streaming)
```
POST /api/chat/stream
Content-Type: application/json

{
  "message": "Hello, how are you?",
  "include_reasoning": true
}
```

### Chat (Non-streaming)
```
POST /api/chat
Content-Type: application/json

{
  "message": "Hello, how are you?"
}
```

### File Upload
```
POST /api/files/upload
Content-Type: multipart/form-data

file: <binary data>
```

## Features

- ✅ GPT-5-nano integration with streaming
- ✅ LangGraph orchestration
- ✅ Multi-format file processing (PDF, images, documents)
- ✅ ChromaDB RAG system
- ✅ DuckDuckGo web search
- ✅ Real-time streaming responses
- ✅ Reasoning display support

## Architecture

```
backend/
├── main.py              # FastAPI app entry
├── core/               # Core utilities
│   ├── config.py       # Configuration
│   ├── logger.py       # Logging
│   ├── openai_client.py # OpenAI wrapper
│   └── chroma_client.py # ChromaDB wrapper
├── agents/             # LangGraph agents
│   ├── state.py        # Agent state
│   ├── tools.py        # Tool definitions
│   └── graph.py        # Agent graph
├── api/                # API layer
│   ├── models.py       # Pydantic models
│   └── routes/         # API routes
└── services/           # Business logic
    ├── file_processor/ # File processing
    └── search_service.py # Web search
```

## Development

```bash
# Run tests
pytest

# Format code
black .

# Type checking
mypy .
```
