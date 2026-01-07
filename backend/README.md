# Jarvis AI Assistant - Backend

Modern AI assistant backend with **Mac Control capabilities** via AppleScript.

Built with FastAPI, LangGraph, and GPT-5-nano.

## Quick Start

```bash
# Setup
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configure
cp .env.example .env
# Edit .env: OPENAI_API_KEY=sk-...

# Run
python main.py
```

Server starts at `http://localhost:8000`

## Features

### Core
- ✅ GPT-5-nano with streaming responses
- ✅ LangGraph orchestration
- ✅ ChromaDB RAG system
- ✅ DuckDuckGo web search
- ✅ Multi-format file processing

### Mac Automation (NEW)
- ✅ **56 pre-built AppleScript automations**
- ✅ App control (open, quit, switch)
- ✅ System control (volume, dark mode, notifications)
- ✅ Media control (Music app)
- ✅ Browser control (Safari, Chrome)
- ✅ Productivity (Calendar, Reminders, Notes)
- ✅ Safety guardrails (blocks delete/remove operations)

## API Endpoints

### Chat (Streaming)
```
POST /api/chat/stream
{"messages": [{"role": "user", "content": "Open Safari"}]}
```

### File Upload
```
POST /api/files/upload
Content-Type: multipart/form-data
```

### Health
```
GET /health
```

## Architecture

```
backend/
├── main.py                    # FastAPI entry
├── core/                      # Core utilities
│   ├── config.py              # Configuration
│   ├── chroma_client.py       # Vector DB
│   └── logger.py              # Logging
├── agents/                    # LangGraph agents
│   ├── graph.py               # Agent workflow
│   ├── tools.py               # All tools (including Mac automation)
│   └── state.py               # Agent state
├── api/routes/                # API endpoints
│   ├── chat.py                # Chat streaming
│   └── files.py               # File upload
└── services/
    ├── mac_automation/        # Mac control (NEW)
    │   ├── executor.py        # AppleScript executor + guardrails
    │   └── scripts.py         # 56 pre-built scripts
    ├── file_processor/        # File processing
    └── search_service.py      # Web search
```

## Mac Automation Tools

| Tool | Description |
|------|-------------|
| `run_mac_script` | Execute pre-defined scripts (preferred) |
| `execute_applescript` | Run custom AppleScript |
| `execute_shell_command` | Run shell commands |
| `get_available_mac_scripts` | List available scripts |

### Script Categories
- **system**: Battery, WiFi, volume, dark mode, notifications
- **apps**: Open, quit, list running, switch focus
- **media**: Music play/pause/skip, current track
- **browser**: Safari/Chrome URL control
- **finder**: Create folders, open files
- **productivity**: Calendar, reminders, notes

### Safety Guardrails
The following operations are **always blocked**:
- `delete`, `remove`, `trash` commands
- `rm`, `rmdir` shell commands
- Keychain/password access
- System shutdown/restart

## Development

```bash
pytest           # Run tests
black .          # Format code
mypy .           # Type check
```
