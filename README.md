# 🤖 Jarvis AI Assistant

**Professional AI Assistant for macOS** - Powered by GPT-4o

✅ Real-time streaming chat | ✅ File analysis (PDF, images, code) | ✅ Web search | ✅ RAG database | ✅ macOS liquid glass UI

---

## 📚 **[READ COMPLETE DOCUMENTATION →](COMPLETE_DOCUMENTATION.md)**

**All guides consolidated into one file for easy reference.**

---

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

🧠 **GPT-5-nano Brain** - Powered by OpenAI's latest model with reasoning capabilities  
🔄 **Real-time Streaming** - See responses as they're generated  
💭 **Visible Reasoning** - Understand how the AI thinks  
📁 **Multi-format Files** - Process PDF, images, documents, code  
🗄️ **RAG Memory** - Remember and search uploaded documents  
🌐 **Web Search** - Access current information via DuckDuckGo  
🎨 **Modern UI** - Native macOS app with SwiftUI  
🔧 **LangGraph Orchestration** - Intelligent tool routing and workflow management

## Architecture

```
┌─────────────────────────────────────┐
│     Swift 6 / SwiftUI Frontend      │
│     (macOS Native Application)      │
└─────────────────┬───────────────────┘
                  │ HTTP/SSE
┌─────────────────▼───────────────────┐
│       FastAPI Backend Server        │
│   - REST API & WebSocket endpoints  │
│   - File handling & validation      │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│      LangGraph Orchestrator         │
│   - Agent workflow management       │
│   - Tool routing & coordination     │
└────┬────────────┬──────────┬────────┘
     │            │          │
┌────▼─────┐ ┌───▼────┐ ┌──▼──────┐
│ GPT-5    │ │ Chroma │ │  File   │
│ -nano    │ │   DB   │ │Processor│
└──────────┘ └────────┘ └─────────┘
                         │
                    ┌────▼────┐
                    │DuckDuck │
                    │   Go    │
                    └─────────┘
```

## Quick Start

### Prerequisites

- **macOS** 13.0+ (for frontend)
- **Python** 3.11+
- **Xcode** 15.0+
- **OpenAI API Key** with GPT-5-nano access

### 1. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY

# Run server
python main.py
```

The backend will start on `http://localhost:8000`

### 2. Frontend Setup

```bash
cd frontend/JarvisAI

# Open in Xcode
open JarvisAI.xcodeproj

# Build and Run (⌘R)
```

### 3. Start Chatting!

The app will automatically connect to the local backend.

## Project Structure

```
Jarvis/
├── backend/
│   ├── main.py                    # FastAPI app
│   ├── core/
│   │   ├── config.py              # Configuration
│   │   ├── openai_client.py      # OpenAI integration
│   │   └── chroma_client.py      # Vector DB
│   ├── agents/
│   │   ├── state.py               # Agent state
│   │   ├── tools.py               # Tool definitions
│   │   └── graph.py               # LangGraph workflow
│   ├── api/
│   │   └── routes/                # API endpoints
│   └── services/
│       ├── file_processor/        # File processing
│       └── search_service.py      # Web search
│
├── frontend/
│   └── JarvisAI/
│       ├── Views/                 # SwiftUI views
│       ├── ViewModels/            # Business logic
│       ├── Services/              # API & streaming
│       └── Models/                # Data models
│
└── Docs/
    └── AI_ASSISTANT_IMPLEMENTATION_PLAN.md
```

## API Endpoints

### Health Check
```bash
GET http://localhost:8000/health
```

### Chat (Streaming)
```bash
POST http://localhost:8000/api/chat/stream
Content-Type: application/json

{
  "message": "Hello!",
  "include_reasoning": true
}
```

### File Upload
```bash
POST http://localhost:8000/api/files/upload
Content-Type: multipart/form-data

file: <binary>
```

## Supported File Types

- **Documents**: PDF, DOCX, TXT, MD
- **Code**: PY, JS, JAVA, CPP, C, H
- **Images**: JPG, PNG, GIF, BMP, WEBP, TIFF

## Configuration

### Backend (.env)
```env
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-5-nano
EMBEDDING_MODEL=text-embedding-3-small
CHROMA_DB_PATH=./chroma_db
MAX_FILE_SIZE=10485760
```

### Frontend (Config.swift)
```swift
static let apiBaseURL = "http://localhost:8000/api"
```

## Development

### Backend Testing
```bash
cd backend
pytest
```

### Code Formatting
```bash
# Python
black .
isort .

# Swift (in Xcode)
Editor → Format → Format File
```

## Tools Available to AI

1. **search_knowledge_base** - Search stored documents using semantic similarity
2. **web_search** - Search the internet using DuckDuckGo
3. **process_uploaded_file** - Extract and analyze file content

## Performance

- **First Token**: <500ms
- **Streaming**: >50 tokens/second
- **File Processing**: <5 seconds/page
- **RAG Retrieval**: <200ms

## Cost Estimation

For moderate usage (~10K messages/month):
- **OpenAI API**: ~$1.70/month
- **Infrastructure**: $0 (self-hosted)

## Troubleshooting

### Backend won't start
- Check if port 8000 is available
- Verify OpenAI API key is valid
- Check Python version is 3.11+

### Frontend can't connect
- Ensure backend is running on localhost:8000
- Check firewall settings
- Verify Config.swift has correct URL

### File upload fails
- Check file size (max 10MB)
- Verify file type is supported
- Check backend logs for errors

## Roadmap

- [ ] Voice input/output
- [ ] Multi-user support
- [ ] iOS companion app
- [ ] Browser extension
- [ ] Custom model fine-tuning
- [ ] Advanced analytics dashboard

## Contributing

Contributions welcome! Please read the implementation plan in `Docs/` for architecture details.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- OpenAI for GPT-5-nano
- LangChain team for LangGraph
- ChromaDB team for vector database
- Apple for Swift and SwiftUI

---

**Built with ❤️ using modern AI technologies**
