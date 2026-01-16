# 🖥️ Jarvis Mac Control Documentation

## Complete Guide to macOS Automation Capabilities

This document provides comprehensive documentation of all Mac control features, scripts, techniques, and tools used by Jarvis to automate macOS.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Backend Tools (Python)](#backend-tools-python)
4. [Frontend Services (Swift)](#frontend-services-swift)
5. [AppleScript Library](#applescript-library)
6. [Security & Permissions](#security--permissions)
7. [Usage Examples](#usage-examples)

---

## Overview

Jarvis uses a multi-layered approach to Mac automation:

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Backend** | Python + AppleScript/JXA | Execute automation scripts via `osascript` |
| **Frontend** | Swift + Accessibility APIs | Direct system integration via native APIs |
| **AI Agent** | LangGraph + OpenAI | Reason about tasks and select appropriate tools |

### Key Capabilities
- **43 AI Tools** for Mac automation
- **100+ AppleScript templates** for common tasks
- **6 Swift services** for native macOS integration
- **Safety guardrails** blocking destructive operations

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Jarvis Mac Control Flow                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  User Request: "Open Safari and search for something"            │
│                           │                                      │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              AI Agent (LangGraph)                        │    │
│  │  • Understands intent                                    │    │
│  │  • Plans steps dynamically                               │    │
│  │  • Selects appropriate tools                             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│           ┌───────────────┼───────────────┐                     │
│           ▼               ▼               ▼                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ Pre-built   │  │  Custom     │  │  Browser    │              │
│  │ Scripts     │  │ AppleScript │  │  Tools      │              │
│  │ (100+)      │  │             │  │             │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│           │               │               │                     │
│           └───────────────┼───────────────┘                     │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │           MacAutomationService (executor.py)             │    │
│  │  • Safety guardrails                                     │    │
│  │  • Script execution via osascript                        │    │
│  │  • Timeout handling                                      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    macOS System                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Backend Tools (Python)

### Location: `backend/agents/tools.py`

### Tool Categories

#### 1. Knowledge & Search
| Tool | Description |
|------|-------------|
| `search_knowledge_base` | Search uploaded documents in ChromaDB |
| `web_search` | Internet search via DuckDuckGo |
| `process_uploaded_file` | Analyze and store file content |

#### 2. Mac Automation - Basic
| Tool | Description |
|------|-------------|
| `run_mac_script` | Execute pre-built AppleScript by ID |
| `execute_applescript` | Run custom AppleScript code |
| `execute_shell_command` | Run shell commands (with guardrails) |
| `get_available_mac_scripts` | List all available pre-built scripts |

#### 3. App Lifecycle
| Tool | Description |
|------|-------------|
| `launch_app` | Open an application by name |
| `quit_app` | Close an application |
| `hide_app` | Hide an application |
| `get_running_apps` | List all running applications |
| `get_frontmost_app` | Get the currently active app |

#### 4. Window Management
| Tool | Description |
|------|-------------|
| `manage_window` | Move, resize, maximize, minimize windows |

#### 5. Input Simulation
| Tool | Description |
|------|-------------|
| `click_at_position` | Click at x,y screen coordinates |
| `type_text` | Type text into focused field |
| `press_keyboard_shortcut` | Press key combinations (Cmd+C, etc.) |

#### 6. UI Accessibility
| Tool | Description |
|------|-------------|
| `get_ui_elements` | Get clickable elements in current app |
| `click_ui_element` | Click a button/element by name |

#### 7. Browser Automation
| Tool | Description |
|------|-------------|
| `browser_navigate_to_url` | Go to any URL in Safari/Chrome |
| `browser_focus_address_bar` | Focus the URL bar (Cmd+L) |
| `browser_new_tab` | Open a new browser tab |
| `browser_scroll` | Scroll page up/down |
| `browser_search_on_page` | Find text on page (Cmd+F) |
| `browser_click_link_by_text` | Click links by visible text |
| `browser_type_in_search_box` | Type in search inputs |
| `browser_get_page_info` | Get page title, URL, headings |
| `browser_submit_form` | Press Enter to submit |

#### 8. Web Page Interaction (General Purpose)
| Tool | Description |
|------|-------------|
| `web_page_get_interactive_elements` | Get all clickable elements on page |
| `web_page_click_element` | Click element by text content |
| `web_page_get_text_content` | Read page content |
| `web_page_fill_input` | Fill any input field |
| `web_page_execute_action` | Common actions (submit, back, scroll) |

#### 9. Screen Understanding
| Tool | Description |
|------|-------------|
| `capture_screen_for_analysis` | Take screenshot + get window info |
| `wait_seconds` | Wait between actions |
| `get_screen_text_content` | Read visible text from screen |
| `verify_app_is_frontmost` | Check if app is active |

#### 10. System & Utilities
| Tool | Description |
|------|-------------|
| `get_system_state` | Battery, volume, display info |
| `open_file_or_url` | Open files or URLs |
| `reveal_in_finder` | Show file in Finder |
| `get_current_media_info` | Get now playing info |
| `send_system_notification` | Display macOS notification |
| `run_shortcut` | Execute Shortcuts app shortcut |
| `list_shortcuts` | List available shortcuts |

---

## Frontend Services (Swift)

### Location: `frontend/JarvisAI/JarvisAI/Services/MacControl/`

### 1. AccessibilityService.swift
**Purpose**: Direct interaction with UI elements via Accessibility APIs (AXUIElement)

**Key Features**:
- Find elements by role, title, or description
- Click buttons, menu items, checkboxes
- Set text field values directly
- Inspect UI element hierarchy
- Get element positions and frames

**Key Methods**:
```swift
func getApplicationElement(name: String) -> AXUIElement?
func findElements(in element: AXUIElement, withRole: String) -> [AXUIElement]
func clickElement(appName: String, elementDescription: String) -> String
func clickMenuItem(appName: String, menuPath: [String]) -> String
func getAllButtons(for element: AXUIElement) -> [AXUIElement]
func getElementInfo(_ element: AXUIElement) -> ElementInfo?
```

### 2. InputSimulator.swift
**Purpose**: Simulate mouse and keyboard input via CGEvent API

**Key Features**:
- Mouse clicks (single, double, right-click)
- Mouse movement and dragging
- Keyboard typing with proper character mapping
- Keyboard shortcuts with modifiers
- Scroll wheel simulation

**Key Methods**:
```swift
func clickAt(x: CGFloat, y: CGFloat)
func doubleClickAt(x: CGFloat, y: CGFloat)
func rightClickAt(x: CGFloat, y: CGFloat)
func moveMouse(to point: CGPoint)
func dragFrom(_ start: CGPoint, to end: CGPoint)
func typeText(_ text: String)
func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags)
func scroll(deltaY: Int32)
```

### 3. WorkspaceMonitor.swift
**Purpose**: Monitor and control application lifecycle via NSWorkspace

**Key Features**:
- Track app launches and terminations
- Monitor app activation and hiding
- Open files with specific applications
- Get running applications list
- Manage file operations

**Key Methods**:
```swift
func launchApp(bundleIdentifier: String) -> Bool
func launchApp(name: String) -> Bool
func quitApp(bundleIdentifier: String) -> Bool
func hideApp(bundleIdentifier: String)
func unhideApp(bundleIdentifier: String)
func openFile(path: String) -> Bool
func revealInFinder(path: String)
```

### 4. ShortcutsService.swift
**Purpose**: Integration with macOS Shortcuts app

**Key Features**:
- List available shortcuts
- Run shortcuts by name
- Pass input to shortcuts
- Get shortcut execution results

**Key Methods**:
```swift
func listShortcuts() async -> [ShortcutInfo]
func runShortcut(name: String, input: String?) async -> String
```

### 5. SystemNotificationService.swift
**Purpose**: Monitor and respond to system-wide notifications

**Key Features**:
- Media change notifications (Music, Spotify)
- Screen lock/unlock events
- Display configuration changes
- Power source changes
- Bluetooth state changes
- Appearance (dark/light mode) changes

**Monitored Events**:
```swift
// Media
com.apple.Music.playerInfo
com.spotify.client.PlaybackStateChanged

// System
com.apple.screenIsLocked
com.apple.screenIsUnlocked
AppleInterfaceThemeChangedNotification
com.apple.system.config.network_change
```

### 6. GlobalHotkeyService.swift
**Purpose**: Register and handle global keyboard shortcuts

**Key Features**:
- Register global hotkeys (Carbon API)
- Monitor keyboard events (CGEvent tap)
- Predefined Jarvis hotkeys
- Modifier key support

**Default Hotkeys**:
| Shortcut | Action |
|----------|--------|
| ⌘⇧J | Toggle Jarvis |
| ⌘⇧Space | Quick Query |
| ⌘⇧F | Toggle Focus Mode |
| ⌘⇧C | Quick Capture |
| ⌘⇧V | Voice Command |

---

## AppleScript Library

### Location: `backend/services/mac_automation/scripts.py`

### Script Categories

#### System (15 scripts)
| Script ID | Description |
|-----------|-------------|
| `system_get_info` | Get computer name, OS version, user |
| `system_get_battery` | Get battery percentage |
| `system_get_wifi` | Get connected WiFi network |
| `system_get_disk_space` | Get available disk space |
| `system_get_volume` | Get current volume level |
| `system_set_volume` | Set volume (0-100) |
| `system_toggle_mute` | Toggle audio mute |
| `system_toggle_dark_mode` | Toggle dark/light mode |
| `system_get_dark_mode` | Check if dark mode is on |
| `system_get_screen_brightness` | Get display brightness |
| `system_set_screen_brightness` | Set display brightness |
| `system_sleep_display` | Put display to sleep |
| `system_prevent_sleep` | Prevent system sleep |
| `system_allow_sleep` | Allow system sleep |
| `system_get_uptime` | Get system uptime |

#### Apps (12 scripts)
| Script ID | Description |
|-----------|-------------|
| `app_open` | Open application by name |
| `app_quit` | Quit application |
| `app_quit_all` | Quit all applications |
| `app_hide` | Hide application |
| `app_unhide` | Unhide application |
| `app_list_running` | List running apps |
| `app_get_frontmost` | Get frontmost app name |
| `app_activate` | Bring app to front |
| `app_is_running` | Check if app is running |
| `app_get_windows` | Get app's window list |
| `app_minimize_all` | Minimize all windows |
| `app_close_window` | Close front window |

#### Finder (10 scripts)
| Script ID | Description |
|-----------|-------------|
| `finder_new_window` | Open new Finder window |
| `finder_go_to_folder` | Navigate to folder path |
| `finder_get_selection` | Get selected files |
| `finder_new_folder` | Create new folder |
| `finder_get_desktop_path` | Get desktop path |
| `finder_reveal_file` | Reveal file in Finder |
| `finder_empty_trash` | Empty trash (blocked) |
| `finder_get_folder_contents` | List folder contents |
| `finder_copy_file` | Copy file to destination |
| `finder_move_file` | Move file to destination |

#### Browser (15 scripts)
| Script ID | Description |
|-----------|-------------|
| `safari_open_url` | Open URL in Safari |
| `safari_get_url` | Get current URL |
| `safari_get_title` | Get page title |
| `safari_new_tab` | Open new tab |
| `safari_close_tab` | Close current tab |
| `safari_reload` | Reload page |
| `safari_back` | Go back |
| `safari_forward` | Go forward |
| `safari_search` | Search in address bar |
| `chrome_open_url` | Open URL in Chrome |
| `chrome_get_url` | Get current Chrome URL |
| `chrome_new_tab` | New Chrome tab |
| `chrome_close_tab` | Close Chrome tab |
| `browser_get_tabs` | Get all open tabs |
| `browser_close_all_tabs` | Close all tabs |

#### Media (12 scripts)
| Script ID | Description |
|-----------|-------------|
| `music_play_pause` | Toggle play/pause |
| `music_next` | Next track |
| `music_previous` | Previous track |
| `music_get_track` | Get current track info |
| `music_set_volume` | Set Music volume |
| `music_get_playlists` | List playlists |
| `music_play_playlist` | Play specific playlist |
| `spotify_play_pause` | Spotify play/pause |
| `spotify_next` | Spotify next track |
| `spotify_previous` | Spotify previous |
| `spotify_get_track` | Get Spotify track info |
| `media_system_play_pause` | System media key |

#### Productivity (18 scripts)
| Script ID | Description |
|-----------|-------------|
| `calendar_get_events` | Get today's events |
| `calendar_create_event` | Create calendar event |
| `reminders_get_lists` | Get reminder lists |
| `reminders_get_items` | Get reminders |
| `reminders_create` | Create reminder |
| `reminders_complete` | Mark reminder done |
| `notes_create` | Create new note |
| `notes_get_folders` | Get note folders |
| `notes_search` | Search notes |
| `mail_get_unread` | Get unread count |
| `mail_check` | Check for new mail |
| `mail_compose` | Open compose window |
| `messages_send` | Send iMessage |
| `messages_get_chats` | Get recent chats |

#### Utilities (10 scripts)
| Script ID | Description |
|-----------|-------------|
| `clipboard_get` | Get clipboard content |
| `clipboard_set` | Set clipboard content |
| `terminal_run` | Run terminal command |
| `terminal_new_window` | New terminal window |
| `spotlight_search` | Open Spotlight search |
| `notification_send` | Send notification |
| `screenshot_full` | Full screen capture |
| `screenshot_selection` | Selection capture |
| `screenshot_window` | Window capture |
| `say_text` | Text-to-speech |

#### Window Management (8 scripts)
| Script ID | Description |
|-----------|-------------|
| `window_maximize` | Maximize window |
| `window_minimize` | Minimize window |
| `window_move` | Move window to x,y |
| `window_resize` | Resize window |
| `window_center` | Center window |
| `window_fullscreen` | Toggle fullscreen |
| `window_get_bounds` | Get window bounds |
| `window_arrange` | Arrange windows |

---

## Security & Permissions

### Required Permissions (Info.plist)

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Jarvis needs to control apps for automation</string>

<key>NSAccessibilityUsageDescription</key>
<string>Jarvis needs accessibility access for UI automation</string>

<key>NSInputMonitoringUsageDescription</key>
<string>Jarvis needs to simulate keyboard/mouse</string>

<key>NSScreenCaptureUsageDescription</key>
<string>Jarvis needs screen capture for visual understanding</string>
```

### Blocked Operations (Safety Guardrails)

The following patterns are blocked by `MacAutomationService`:

```python
BLOCKED_PATTERNS = [
    # File deletion
    r'\bdelete\b', r'\bremove\b', r'\btrash\b',
    r'\bermpty\s+trash\b', r'\bmove\s+.*\s+to\s+trash\b',
    r'rm\s+-', r'rmdir\b', r'unlink\b',
    
    # System modification
    r'\bformat\b.*\bdisk\b', r'\berase\b.*\bdisk\b',
    r'\bshutdown\b', r'\brestart\b.*\bsystem\b',
    r'sudo\s+rm\b', r'sudo\s+shutdown', r'sudo\s+reboot',
    
    # Security/Privacy
    r'\bkeychain\b', r'\bpassword\b', r'\bsecurity\s+',
    r'\bcredential\b', r'System\s+Preferences.*Security',
    
    # Dangerous shell
    r'>\s*/dev/', r'mkfs\b', r'dd\s+if=',
]
```

### Permission Setup

1. **System Settings → Privacy & Security**:
   - **Accessibility**: Required for UI automation
   - **Input Monitoring**: Required for keyboard/mouse simulation
   - **Screen Recording**: Required for screen capture
   - **Automation**: Required for AppleScript control

---

## Usage Examples

### Basic App Control
```
"Open Safari"                    → launch_app("Safari")
"Close Notes"                    → quit_app("Notes")
"What apps are running?"         → get_running_apps()
"What's the frontmost app?"      → get_frontmost_app()
```

### Browser Automation
```
"Go to github.com"               → browser_navigate_to_url("github.com")
"Search for Python tutorials"    → web_page_fill_input("Python tutorials") + submit
"Scroll down"                    → browser_scroll("down")
"Click the Sign In button"       → web_page_click_element("Sign In")
```

### System Control
```
"What's my battery level?"       → run_mac_script("system_get_battery")
"Set volume to 50%"              → run_mac_script("system_set_volume", {"level": 50})
"Toggle dark mode"               → run_mac_script("system_toggle_dark_mode")
"What WiFi am I on?"             → run_mac_script("system_get_wifi")
```

### Input Simulation
```
"Type hello world"               → type_text("hello world")
"Press Cmd+C"                    → press_keyboard_shortcut("cmd+c")
"Click at 500, 300"              → click_at_position(500, 300)
```

### UI Automation
```
"Get UI elements in Finder"      → get_ui_elements("Finder")
"Click the Back button"          → click_ui_element("Finder", "Back")
"What buttons are visible?"      → web_page_get_interactive_elements()
```

### Media Control
```
"Play/pause music"               → run_mac_script("music_play_pause")
"Next track"                     → run_mac_script("music_next")
"What's playing?"                → get_current_media_info()
```

### Productivity
```
"What's on my calendar today?"   → run_mac_script("calendar_get_events")
"Create a reminder to call mom"  → run_mac_script("reminders_create", {...})
"Check my email"                 → run_mac_script("mail_get_unread")
```

### Window Management
```
"Maximize this window"           → manage_window("maximize")
"Move window to top left"        → manage_window("move", {"x": 0, "y": 0})
"Minimize all windows"           → run_mac_script("app_minimize_all")
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Accessibility permission required" | Grant in System Settings → Privacy & Security → Accessibility |
| "Script blocked for safety" | Operation contains blocked pattern (delete, trash, etc.) |
| "Could not find application" | Check app name spelling, ensure app is installed |
| "Element not found" | Use `get_ui_elements` first to see available elements |
| "Timeout executing script" | Script took too long, try simpler approach |

---

## API Reference

### MacAutomationService (Python)

```python
class MacAutomationService:
    async def execute_applescript(script: str, timeout: int = 30) -> ExecutionResult
    async def execute_jxa(script: str, timeout: int = 30) -> ExecutionResult
    async def execute_shell(command: str, timeout: int = 30) -> ExecutionResult
```

### ExecutionResult

```python
@dataclass
class ExecutionResult:
    success: bool
    output: str
    error: Optional[str]
    blocked: bool
    blocked_reason: Optional[str]
```

---

*Last Updated: January 2026*
*Tools: 43 | Scripts: 100+ | Swift Services: 6*
