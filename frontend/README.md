# Jarvis AI Assistant - Frontend

Modern macOS application built with Swift 6 and SwiftUI.

## Requirements

- macOS 13.0+
- Xcode 15.0+
- Swift 6.0

## Setup

### 1. Open Project

```bash
cd frontend/JarvisAI
open JarvisAI.xcodeproj
```

### 2. Configure Backend URL

Edit `JarvisAI/Utils/Config.swift` if your backend is not running on `localhost:8000`.

### 3. Build and Run

- Press `⌘R` in Xcode or
- Product → Run

## Features

- ✅ Real-time streaming chat interface
- ✅ Reasoning display with collapsible dropdown
- ✅ File upload with drag-and-drop
- ✅ Modern, native macOS UI
- ✅ Markdown rendering for responses
- ✅ Dark mode support

## Dependencies

The project uses Swift Package Manager for dependencies:

- **MarkdownUI**: For rendering Markdown formatted responses

## Architecture

```
JarvisAI/
├── JarvisAIApp.swift         # App entry point
├── ContentView.swift          # Main chat interface
├── Views/
│   ├── MessageBubbleView.swift      # Chat message bubbles
│   ├── ReasoningDropdownView.swift  # Reasoning display
│   └── FileUploadView.swift         # File upload UI
├── ViewModels/
│   └── ChatViewModel.swift          # Chat business logic
├── Services/
│   ├── APIService.swift             # API communication
│   └── StreamingService.swift       # SSE streaming handler
├── Models/
│   └── Message.swift                # Data models
└── Utils/
    └── Config.swift                 # Configuration
```

## Keyboard Shortcuts

- `⌘↩` - Send message
- `⌘R` - Reload Xcode project

## Customization

### Change Colors

Edit the color schemes in individual views to match your preferences.

### Change API Endpoint

Edit `Config.swift`:

```swift
static let apiBaseURL = "http://your-server:port/api"
```

## Troubleshooting

**Connection Issues:**
- Ensure the backend is running on `localhost:8000`
- Check firewall settings
- Verify API endpoint in Config.swift

**Build Errors:**
- Clean build folder: Product → Clean Build Folder
- Reset package caches: File → Packages → Reset Package Caches

**File Upload Not Working:**
- Check file size (max 10MB)
- Verify file type is supported
- Check backend logs
