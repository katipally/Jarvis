# 🤖 Jarvis AI Assistant

**Multimodal AI Assistant with Full macOS Control** - Your intelligent companion for Mac automation and productivity

✅ Voice Conversation | ✅ Vision Analysis | ✅ Mac Control | ✅ Multimodal Files | ✅ Local LLM Support | ✅ Native macOS UI

---

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)
![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 🚀 Overview

Jarvis is a cutting-edge AI assistant that combines voice conversation, computer vision, and Mac automation capabilities. Built with Swift 6/SwiftUI for the frontend and FastAPI/LangGraph for the backend, Jarvis offers a truly multimodal experience with support for local LLMs via Ollama.

## ✨ Key Features

### 🎙️ **Voice Conversation Mode**
- **Natural voice interaction** with interruption handling
- **Wake word detection** - "Hey Jarvis" always listening
- **Streaming TTS** with premium voices
- **Hands-free and push-to-talk modes**
- **Context-aware conversations** with memory

### 👁️ **Vision & Multimodal**
- **Screen capture analysis** - "What's on my screen?"
- **Image understanding** with GPT-5-nano vision
- **Document processing** (PDF, images, text)
- **OCR text extraction** from images
- **Real-time visual context** during conversations

### 🖥️ **Mac Automation**
- **56 pre-built automation scripts**
- **App control** (open, quit, switch)
- **System settings** (volume, brightness, dark mode)
- **Browser automation** (Safari control)
- **File management** (create, open, navigate)
- **Productivity tools** (calendar, reminders, notes)

### 🤖 **AI Model Support**
- **GPT-5-nano** (OpenAI) - Primary model
- **Local LLMs** via Ollama integration
- **Vision models** (LLaVA, Llama3.2-Vision)
- **Embedding models** for RAG
- **Model switching** without app restart

### 🎯 **Interface Modes**
- **Focus Mode** - Always-on-top floating panel
- **Chat Mode** - Full-window conversational UI
- **Conversation Mode** - Voice-first interface
- **Unified sidebar** with conversation history

### 🔒 **Safety & Privacy**
- **On-device processing** when possible
- **Blocked destructive operations**
- **No password/keychain access**
- **Local data storage** option
- **Transparent data usage**

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Swift 6 / SwiftUI Frontend                 │
│  ┌──────────┬──────────┬──────────┬──────────────────┐   │
│  │Chat Mode │Focus Mode│Voice Conv │  Vision Panel   │   │
│  └──────────┴──────────┴──────────┴──────────────────┘   │
│  ┌────────────────────────────────────────────────────┐   │
│  │  Vision Service | Ollama Service | Audio Pipeline │   │
│  └────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────┘
                          │ HTTP/WebSocket
┌─────────────────────────▼───────────────────────────────┐
│                FastAPI Backend Server                    │
│  ┌──────────┬──────────┬──────────┬──────────────────┐   │
│  │Chat API  │Vision API│Ollama API│  WebSocket WS   │   │
│  └──────────┴──────────┴──────────┴──────────────────┘   │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│              LangGraph Orchestrator                      │
│  ┌──────────┬──────────┬──────────┬──────────────────┐   │
│  │OpenAI API│Ollama LLM│Chroma DB │Mac Automation   │   │
│  │GPT-5-nano│Local     │RAG Memory│AppleScript      │   │
│  └──────────┴──────────┴──────────┴──────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **macOS** 13.0+ (for ScreenCaptureKit and modern features)
- **Python** 3.11+
- **Xcode** 15.0+
- **OpenAI API Key** (for GPT-5-nano)
- **Ollama** (optional, for local LLMs)

### 1. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment file
cp .env.example .env
# Edit .env with your API keys

# Start the server
python main.py
```

### 2. Frontend Setup

```bash
# Open in Xcode
open frontend/JarvisAI/JarvisAI.xcodeproj

# Build and run from Xcode (⌘+R)
```

### 3. Ollama Setup (Optional)

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull recommended models
ollama pull llama3.2
ollama pull llava
ollama pull all-minilm

# Start Ollama
ollama serve
```

## 📋 Configuration

### Backend (.env)

```env
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_MODEL=gpt-5-nano

# Ollama Configuration
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.2

# Vision Settings
VISION_MODEL=gpt-5-nano
MAX_IMAGE_SIZE=2048

# Audio Settings
SAMPLE_RATE=16000
CHANNELS=1

# Storage
UPLOAD_DIR=./uploads
CHROMA_DB_PATH=./data/chroma
```

### Frontend (Info.plist)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Jarvis needs microphone access for voice commands</string>
<key>NSScreenCaptureDescription</key>
<string>Jarvis needs screen access for vision features</string>
```

## 🎯 Usage Examples

### Voice Commands

```
"Hey Jarvis, what's the weather like?"
"Hey Jarvis, open Safari and go to apple.com"
"Hey Jarvis, set volume to 50%"
"Hey Jarvis, what's on my screen right now?"
"Hey Jarvis, create a new folder named 'Project' on desktop"
```

### Vision Features

```
# Analyze uploaded image
"Explain what's in this image"

# Screen capture
"Take a screenshot and explain what you see"

# Document analysis
"Summarize this PDF document"
"Extract text from this image"
```

### Mac Automation

```
"Open Spotify and play my liked songs"
"Create a new note with meeting summary"
"Open Terminal and navigate to project folder"
"Set up a split view with Notes and Safari"
"Take a screenshot and save to desktop"
```

## 🔧 Advanced Features

### Custom Automation Scripts

Create custom AppleScript actions in `backend/services/mac_automation/scripts/`:

```applescript
-- Custom script example
on run argv
    set action to item 1 of argv
    if action is "custom_action" then
        -- Your custom logic here
        return "Action completed successfully"
    end if
end run
```

### Model Configuration

Switch between AI models dynamically:

```swift
// Use OpenAI
await ollamaService.setModel("gpt-5-nano")

// Use local model
await ollamaService.setModel("llama3.2")

// Use vision model
await ollamaService.setModel("llava")
```

### Memory Management

Configure RAG memory settings:

```python
# In backend/core/config.py
MEMORY_CONFIG = {
    "max_conversations": 1000,
    "context_window": 10000,
    "embedding_model": "all-minilm",
    "similarity_threshold": 0.7
}
```

## 🛠️ Development

### Project Structure

```
Jarvis/
├── backend/                 # FastAPI server
│   ├── api/                # API routes
│   │   ├── routes/         # Endpoint definitions
│   │   └── websocket/      # WebSocket handlers
│   ├── core/               # Core utilities
│   │   ├── config.py       # Configuration
│   │   └── logger.py       # Logging setup
│   ├── services/           # Business logic
│   │   ├── mac_automation/ # AppleScript execution
│   │   ├── ollama.py       # Local LLM client
│   │   └── vision.py       # Vision processing
│   └── agents/             # LangGraph agents
│       ├── graph.py        # Agent workflow
│       └── tools.py        # Available tools
├── frontend/               # Swift/SwiftUI app
│   └── JarvisAI/
│       ├── Services/       # Network and utilities
│       │   ├── VisionService.swift
│       │   ├── OllamaService.swift
│       │   └── ScreenCaptureService.swift
│       ├── ViewModels/     # MVVM view models
│       ├── Views/          # SwiftUI views
│       └── Models/         # Data models
└── docs/                   # Documentation
```

### Adding New Features

1. **Backend**: Create new route in `api/routes/`
2. **Frontend**: Add service in `Services/`
3. **UI**: Create view in `Views/`
4. **Testing**: Add unit tests in `Tests/`

### Debug Mode

Enable debug logging:

```bash
# Backend
export LOG_LEVEL=DEBUG
python main.py

# Frontend
# In Xcode: Product → Scheme → Edit Scheme → Run → Arguments
# Add: -XCTDebugEnabled
```

## 🐛 Troubleshooting

### Common Issues

1. **Microphone not working**
   - Check System Preferences → Privacy → Microphone
   - Ensure Jarvis is listed and enabled

2. **Screen capture fails**
   - Grant screen recording permission in System Preferences
   - Restart app after permission change

3. **Ollama connection error**
   - Ensure Ollama is running: `ollama serve`
   - Check if port 11434 is available

4. **Voice recognition poor**
   - Use external microphone for better quality
   - Calibrate in quiet environment

### Error Codes

| Code | Description | Solution |
|------|-------------|----------|
| E001 | Microphone permission denied | Grant microphone access |
| E002 | Screen recording denied | Grant screen recording permission |
| E003 | Ollama not connected | Start Ollama service |
| E004 | API key invalid | Check .env configuration |
| E005 | Model not found | Download required model |

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **OpenAI** for GPT-5-nano API
- **Ollama** for local LLM support
- **Apple** for ScreenCaptureKit and AVFoundation
- **LangChain** for agent framework
- **FastAPI** for backend framework

## 📞 Support

- 📧 Email: support@jarvis-ai.com
- 💬 Discord: [Join our community](https://discord.gg/jarvis)
- 📖 Docs: [jarvis-ai.com/docs](https://jarvis-ai.com/docs)

---

<div align="center">
  <p>Made with ❤️ by the Jarvis Team</p>
  <p>⭐ If you like this project, give us a star!</p>
</div>
