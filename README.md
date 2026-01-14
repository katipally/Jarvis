# 🤖 Jarvis AI Assistant

**The Ultimate macOS AI Assistant** — Combining the best of ChatGPT, Siri, Claude, Cursor & Cluely

✅ Voice Conversation | ✅ Screen Understanding | ✅ Mac Control | ✅ Accessibility APIs | ✅ Local LLM Support | ✅ Native macOS UI

---

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)
![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg)
![Scripts](https://img.shields.io/badge/AppleScripts-75+-purple.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 🚀 Overview

Jarvis is a cutting-edge AI assistant that combines voice conversation, computer vision, screen understanding, and deep Mac automation capabilities. Built with Swift 6/SwiftUI for the frontend and FastAPI/LangGraph for the backend, Jarvis offers a truly multimodal experience with support for local LLMs via Ollama.

**What makes Jarvis unique:**
- 🖥️ **Deep macOS Integration** — 75+ AppleScripts + Accessibility APIs
- 👁️ **Screen Understanding** — Capture & analyze any screen, window, or selection
- 🎯 **Always-on-Top Focus Mode** — Like Cluely, but with full AI capabilities
- 🔒 **Privacy-First** — Local LLM support, no cloud dependency required

## ✨ Key Features

### 🎙️ Voice Conversation Mode
- Natural voice interaction with interruption handling
- Wake word detection — "Hey Jarvis" always listening
- Streaming TTS with premium voices
- Hands-free and push-to-talk modes
- Context-aware conversations with memory

### 👁️ Vision & Screen Understanding
- **Full screen capture** — Analyze entire display
- **Window capture** — Screenshot active window
- **Selection capture** — Capture specific regions
- **Multi-display support** — Handle multiple monitors
- **Accessibility inspection** — Read UI elements, buttons, text fields
- **Document processing** — PDF, images, text with OCR

### 🖥️ Mac Automation (75+ Scripts)

```
┌─────────────────────────────────────────────────────────────────┐
│                 Mac Automation Categories                        │
├──────────────┬──────────────┬──────────────┬───────────────────┤
│   SYSTEM     │    APPS      │   BROWSER    │   PRODUCTIVITY    │
│ • Battery    │ • Open/Quit  │ • Safari     │ • Calendar        │
│ • Volume     │ • List Apps  │ • Chrome     │ • Reminders       │
│ • Dark Mode  │ • Frontmost  │ • URLs/Tabs  │ • Notes           │
│ • WiFi Info  │ • Hide/Show  │ • Navigation │ • Mail            │
│ • Brightness │ • Switch     │              │ • Messages        │
├──────────────┼──────────────┼──────────────┼───────────────────┤
│   FINDER     │    MEDIA     │  UTILITIES   │   ACCESSIBILITY   │
│ • Navigate   │ • Play/Pause │ • Clipboard  │ • UI Elements     │
│ • Create     │ • Next/Prev  │ • Terminal   │ • Window Info     │
│ • Open Files │ • Track Info │ • Spotlight  │ • Click Buttons   │
│ • Selection  │ • Playlists  │ • Spaces     │ • Type Text       │
│              │              │              │ • Menu Bars       │
├──────────────┴──────────────┴──────────────┴───────────────────┤
│                    SCREEN CAPTURE & VISION                       │
│ • Full Screen  • Window  • Selection  • Multi-Display  • OCR    │
└─────────────────────────────────────────────────────────────────┘
```

### 🎯 Interface Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Focus Mode** | Always-on-top floating panel | Quick access while working |
| **Chat Mode** | Full-window conversational UI | Deep conversations |
| **Conversation Mode** | Voice-first interface | Hands-free interaction |

### 🔒 Safety & Privacy
- On-device processing with Ollama
- **Blocked destructive operations** — Cannot delete files
- No password/keychain access
- Local data storage option
- Transparent data usage

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Jarvis AI Architecture                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Swift 6 / SwiftUI Frontend                  │   │
│  │  ┌──────────┬──────────┬──────────┬────────────────┐    │   │
│  │  │ Chat     │ Focus    │ Voice    │ Settings      │    │   │
│  │  │ Mode     │ Panel    │ Conv.    │ Panel         │    │   │
│  │  └──────────┴──────────┴──────────┴────────────────┘    │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │ Services: Audio | Speech | Streaming | API        │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │ HTTP/SSE/WebSocket                 │
│  ┌─────────────────────────▼───────────────────────────────┐   │
│  │                  FastAPI Backend                         │   │
│  │  ┌──────────┬──────────┬──────────┬────────────────┐    │   │
│  │  │ Chat API │Voice API │Files API │  WebSocket    │    │   │
│  │  └──────────┴──────────┴──────────┴────────────────┘    │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                    │
│  ┌─────────────────────────▼───────────────────────────────┐   │
│  │               LangGraph Agent Orchestrator               │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │              Tool Router / Planner                │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │  ┌────────┬────────┬────────┬────────┬────────────┐    │   │
│  │  │ OpenAI │ Ollama │ChromaDB│  Web   │    Mac     │    │   │
│  │  │  API   │ Local  │  RAG   │ Search │ Automation │    │   │
│  │  └────────┴────────┴────────┴────────┴────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Mac Automation Layer (75+ Scripts)          │   │
│  │  ┌──────────┬──────────┬──────────┬────────────────┐    │   │
│  │  │ System   │   Apps   │  Screen  │ Accessibility │    │   │
│  │  │ Control  │  Control │  Capture │   UI Control  │    │   │
│  │  └──────────┴──────────┴──────────┴────────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **macOS** 13.0+ (Ventura or later)
- **Python** 3.11+
- **Xcode** 15.0+
- **OpenAI API Key** (for GPT models)
- **Ollama** (optional, for local LLMs)

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
# Edit .env with your OPENAI_API_KEY

# Start server
python main.py
```

Backend runs on `http://localhost:8000`

### 2. Frontend Setup

```bash
cd frontend/JarvisAI

# Open in Xcode
open JarvisAI.xcodeproj

# Build and Run (⌘R)
```

### 3. Ollama Setup (Optional)

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull models
ollama pull llama3.2
ollama pull llava

# Start Ollama
ollama serve
```

## 📁 Project Structure

```
Jarvis/
├── backend/                    # FastAPI Python Backend
│   ├── main.py                # Application entry
│   ├── api/
│   │   └── routes/            # REST endpoints
│   │       ├── chat.py        # Chat streaming
│   │       ├── files.py       # File uploads
│   │       └── conversation.py # Voice handling
│   ├── agents/
│   │   ├── graph.py           # LangGraph workflow
│   │   ├── tools.py           # AI tool definitions
│   │   └── state.py           # Agent state
│   ├── services/
│   │   ├── mac_automation/    # AppleScript engine
│   │   │   ├── executor.py    # Safe script execution
│   │   │   └── scripts.py     # 75+ pre-built scripts
│   │   ├── file_processor/    # Document processing
│   │   └── search_service.py  # Web search
│   └── core/
│       ├── config.py          # Settings
│       ├── openai_client.py   # OpenAI integration
│       └── chroma_client.py   # Vector DB
│
├── frontend/                   # Swift/SwiftUI Frontend
│   └── JarvisAI/
│       ├── JarvisAIApp.swift  # App entry + Focus Panel
│       ├── Views/
│       │   ├── ChatView.swift
│       │   ├── FocusPanelView.swift
│       │   ├── UnifiedPanelView.swift
│       │   └── ConversationModeView.swift
│       ├── ViewModels/
│       │   ├── ChatViewModel.swift
│       │   └── ConversationViewModel.swift
│       └── Services/
│           ├── APIService.swift
│           ├── StreamingService.swift
│           ├── AudioPipeline.swift
│           ├── SpeechRecognitionService.swift
│           └── SpeechSynthesisService.swift
│
├── JARVIS_FEATURES.md         # Full feature roadmap
└── README.md                  # This file
```

## 🎯 Usage Examples

### Voice Commands
```
"Hey Jarvis, what's my battery level?"
"Hey Jarvis, open Safari and go to github.com"
"Hey Jarvis, set volume to 50%"
"Hey Jarvis, what apps are running?"
"Hey Jarvis, toggle dark mode"
```

### Screen Understanding
```
"Take a screenshot and tell me what you see"
"What's the title of my current window?"
"What buttons are visible on screen?"
"Read the text in the focused field"
```

### Mac Automation
```
"Create a folder called 'Projects' on my desktop"
"Play the next song"
"What's on my calendar today?"
"Send a notification saying 'Meeting in 5 minutes'"
"Open Terminal and run ls"
```

## ⚙️ Configuration

### Backend (.env)
```env
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o
OLLAMA_BASE_URL=http://localhost:11434
CHROMA_DB_PATH=./chroma_db
MAX_FILE_SIZE=10485760
```

## 🔧 Available Tools

The AI has access to these tool categories:

| Tool | Description |
|------|-------------|
| `run_mac_script` | Execute pre-built AppleScripts |
| `execute_applescript` | Run custom AppleScript code |
| `execute_shell_command` | Safe shell commands |
| `search_knowledge_base` | Search uploaded documents |
| `web_search` | Internet search via DuckDuckGo |
| `process_uploaded_file` | Analyze files |

## 🛡️ Safety Guardrails

Jarvis blocks all destructive operations:
- ❌ Delete/remove/trash files
- ❌ Empty trash
- ❌ Format/erase disks
- ❌ Shutdown/restart system
- ❌ Access keychain/passwords
- ❌ Modify security settings

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Microphone not working | System Preferences → Privacy → Microphone |
| Screen capture fails | Grant screen recording permission |
| Ollama not connecting | Run `ollama serve` |
| Backend won't start | Check port 8000 is free |

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

<div align="center">
  <p><strong>Jarvis</strong> — Your AI-powered Mac companion</p>
  <p>Built with Swift, Python, LangGraph & ❤️</p>
</div>
