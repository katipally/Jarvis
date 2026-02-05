# JARVIS AI - Complete System Design

> **Version:** 5.2 Final | **Date:** February 3, 2026  
> **Document:** Part 2 of 4 - UI/UX Design (Enhanced)

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Window System](#2-window-system)
3. [Chat Mode - Complete Design](#3-chat-mode---complete-design)
4. [Ray Mode - Complete Design](#4-ray-mode---complete-design)
5. [Conversation Mode - Complete Design](#5-conversation-mode---complete-design)
6. [Focus Mode - Complete Design](#6-focus-mode---complete-design)
7. [Shared Components](#7-shared-components)
8. [Animations & Interactions](#8-animations--interactions)
9. [Accessibility](#9-accessibility)
10. [Settings UI](#10-settings-ui) (6 tabs: General, Models, Voice, Hotkeys, Privacy, Advanced)
11. [Menu Bar](#11-menu-bar)
12. [Onboarding Flow](#12-onboarding-flow)
13. [Error States](#13-error-states)

---

# 1. Design Philosophy

## 1.1 Core Design Principles

### Principle 1: Native First

**What this means:**
Jarvis should feel like an Apple-built app, not a third-party tool. Users should be able to use it without learning new patterns.

**How we achieve it:**
- Use only Apple system colors (no custom hex codes)
- Follow Human Interface Guidelines spacing (8pt grid)
- Use SF Symbols for ALL icons
- Apply Liquid Glass materials where appropriate
- Match macOS window behavior exactly

### Principle 2: Familiarity Through Convention

**What this means:**
Each mode follows a familiar paradigm that users already know.

| Mode | Paradigm | Users Know From |
|------|----------|-----------------|
| Chat | iMessage | Millions of users daily |
| Ray | Spotlight | Every Mac user |
| Voice | Siri 2026 | iOS/macOS Siri |
| Focus | Copilot | Developers |

### Principle 3: Progressive Disclosure

**What this means:**
Simple tasks should be simple. Complexity is revealed only when needed.

**Examples:**
- Ray mode: Type "open safari" → Just works
- Chat mode: Complex explanation → Shows plan, step progress
- Focus mode: Basic question → Brief answer. Complex question → Full analysis

### Principle 4: Contextual Minimalism

**What this means:**
Show only what's relevant to the current task. Remove visual noise.

**Examples:**
- Voice mode: Just edge glow + transcript (no buttons, menus)
- Ray mode: Search bar + results. Nothing else
- Focus mode: Small panel that doesn't cover work

## 1.2 Design Tokens

```swift
// frontend/Core/Theme.swift

import SwiftUI

/// Design tokens for consistent styling across all modes
enum Theme {
    
    // MARK: - Spacing (8pt Grid)
    /// Apple uses an 8-point grid system
    /// All spacing should be multiples of 8
    
    /// 4pt - Minimal spacing (icon to text, tight groups)
    static let spacingXS: CGFloat = 4
    
    /// 8pt - Small spacing (related items)
    static let spacingS: CGFloat = 8
    
    /// 12pt - Medium-small (content gaps)
    static let spacingM: CGFloat = 12
    
    /// 16pt - Medium (section spacing)
    static let spacingL: CGFloat = 16
    
    /// 24pt - Large (major sections)
    static let spacingXL: CGFloat = 24
    
    /// 32pt - Extra large (view paddings)
    static let spacingXXL: CGFloat = 32
    
    // MARK: - Corner Radii
    /// Consistent rounding throughout the app
    
    /// 4pt - Small elements (buttons in groups)
    static let radiusSmall: CGFloat = 4
    
    /// 8pt - Standard elements (cards, inputs)
    static let radiusMedium: CGFloat = 8
    
    /// 12pt - Larger cards, panels
    static let radiusLarge: CGFloat = 12
    
    /// 16pt - Windows, modals
    static let radiusXLarge: CGFloat = 16
    
    /// 20pt - Major containers
    static let radiusXXLarge: CGFloat = 20
    
    // MARK: - Typography
    /// System fonts with semantic naming
    
    /// Large title (window headers)
    static let fontLargeTitle: Font = .largeTitle
    
    /// Title (section headers)
    static let fontTitle: Font = .title2
    
    /// Headline (important text)
    static let fontHeadline: Font = .headline
    
    /// Body (main content)
    static let fontBody: Font = .body
    
    /// Caption (secondary info, timestamps)
    static let fontCaption: Font = .caption
    
    /// Input search text (Ray mode)
    static let fontSearch: Font = .title2
    
    // MARK: - Animation Durations
    /// Consistent animation timing
    
    /// Fast response (button press, toggles)
    static let animationFast: Double = 0.15
    
    /// Standard transitions
    static let animationNormal: Double = 0.25
    
    /// Slower, more dramatic (window appear)
    static let animationSlow: Double = 0.35
    
    /// Spring animation for bouncy feel
    static let springAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    
    // MARK: - Shadows
    /// Consistent shadow styles
    
    /// Subtle shadow for cards
    static func shadowSubtle() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    /// Medium shadow for floating elements
    static func shadowMedium() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
    
    /// Heavy shadow for overlays
    static func shadowHeavy() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.25), radius: 30, y: 15)
    }
}
```

## 1.3 macOS 26 Liquid Glass Design System

> [!IMPORTANT]
> macOS 26 introduces **Liquid Glass**, a new design language that ALL Jarvis UI must follow. This uses the built-in `glassEffect` modifier for translucent, light-refracting surfaces.

### Liquid Glass Principles

| Principle | Description | Implementation |
|-----------|-------------|----------------|
| **Translucency** | Surfaces refract and reflect content behind them | `.glassEffect(.regular)` |
| **Depth** | Layered glass creates hierarchy | `GlassEffectContainer` |
| **Motion** | Glass responds to light and movement | Built-in animations |
| **Harmony** | Glass adapts to surroundings | Auto color scheme |

### SwiftUI Implementation

```swift
// frontend/Core/LiquidGlass.swift

import SwiftUI

/// macOS 26 Liquid Glass helpers and modifiers
///
/// Usage:
///   anyView.jarvisGlass()  // Standard glass panel
///   anyView.jarvisPill()   // Pill-shaped input
///   anyView.jarvisHUD()    // Floating HUD window

extension View {
    /// Standard Liquid Glass panel effect
    func jarvisGlass() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }
    
    /// Pill-shaped Liquid Glass for inputs (Spotlight/iMessage style)
    func jarvisPill() -> some View {
        self
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular)
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
    }
    
    /// Clear glass for HUD elements (Ray mode)
    func jarvisHUD() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusXXLarge)
                    .fill(.ultraThinMaterial)
                    .glassEffect(.clear)  // Maximum transparency
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusXXLarge)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
    }
}

/// Container for coordinating multiple glass elements
/// Use when you have multiple glass shapes that should reflect each other
struct JarvisGlassContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GlassEffectContainer {
            content
        }
    }
}
```

## 1.4 SF Symbols 7 Usage

> [!TIP]
> SF Symbols 7 provides **6,000+ icons** with 9 weights and 3 scales. Use these exclusively - never create custom icons.

### Jarvis Icon Mapping

| Function | SF Symbol | Usage |
|----------|-----------|-------|
| **Chat** | `bubble.left.fill` | Mode icon, messages |
| **Voice** | `waveform` | Voice mode, audio indicator |
| **Ray** | `magnifyingglass` | Search, Ray mode |
| **Focus** | `eye.fill` | Focus mode, context |
| **Send** | `arrow.up.circle.fill` | Send message |
| **Mic** | `mic.fill` | Voice input |
| **Add** | `plus` | Add attachment |
| **Settings** | `gearshape` | Configuration |
| **Close** | `xmark.circle.fill` | Dismiss |
| **Success** | `checkmark.circle.fill` | Step complete |
| **Running** | `arrow.trianglehead.2.counterclockwise` | In progress |
| **Error** | `exclamationmark.triangle.fill` | Error state |
| **Plan** | `list.bullet.clipboard` | Execution plan |

### SF Symbols 7 Features

```swift
// frontend/Core/JarvisIcons.swift

import SwiftUI

/// Centralized SF Symbol references with macOS 26 effects
enum JarvisIcons {
    
    // MARK: - Mode Icons
    static let chat = Image(systemName: "bubble.left.fill")
    static let voice = Image(systemName: "waveform")
    static let ray = Image(systemName: "magnifyingglass")
    static let focus = Image(systemName: "eye.fill")
    
    // MARK: - Action Icons
    static let send = Image(systemName: "arrow.up.circle.fill")
    static let mic = Image(systemName: "mic.fill")
    static let add = Image(systemName: "plus")
    static let close = Image(systemName: "xmark.circle.fill")
    
    // MARK: - Status Icons
    static let success = Image(systemName: "checkmark.circle.fill")
    static let running = Image(systemName: "arrow.trianglehead.2.counterclockwise")
    static let error = Image(systemName: "exclamationmark.triangle.fill")
    static let pending = Image(systemName: "circle")
}

/// SF Symbols 7 animated icon view with Magic Replace
struct AnimatedIcon: View {
    let from: String
    let to: String
    let isActive: Bool
    
    var body: some View {
        Image(systemName: isActive ? to : from)
            .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
            .symbolEffect(.bounce, value: isActive)
    }
}

/// Icon that shows send or mic based on text state
/// Uses SF Symbols 7 Magic Replace for smooth morphing
struct SendMicIcon: View {
    let hasText: Bool
    
    var body: some View {
        Image(systemName: hasText ? "arrow.up.circle.fill" : "mic.fill")
            .font(.title2)
            .foregroundStyle(hasText ? .blue : .secondary)
            .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
            .symbolEffect(.bounce, value: hasText)
    }
}
```

## 1.5 Apple Native Components

> [!NOTE]
> Use Apple's built-in components whenever possible. This ensures consistent UX and reduces implementation time.

### Standard Components to Use

| Component | SwiftUI | macOS 26 Feature |
|-----------|---------|------------------|
| **Text Field** | `TextField` | Auto-glass in panels |
| **Button** | `Button` | Built-in hover states |
| **List** | `List` | Native selection, scroll |
| **ScrollView** | `ScrollView` | Rubber-banding, indicators |
| **Menu** | `Menu` | Native popover |
| **Toggle** | `Toggle` | Native switch |
| **Slider** | `Slider` | Native track |
| **Progress** | `ProgressView` | Determinate/indeterminate |
| **Picker** | `Picker` | Segmented/wheel styles |
| **Sheet** | `.sheet()` | Native modal with glass |
| **Popover** | `.popover()` | Native popover with arrow |

### Material Types

```swift
// Use these system materials - they auto-adapt to light/dark mode

.ultraThinMaterial    // Maximum blur, minimal tint (Ray mode)
.thinMaterial         // High blur (Focus panel)  
.regularMaterial      // Standard (Chat bubbles)
.thickMaterial        // Less blur (sidebars)
.ultraThickMaterial   // Minimal blur (backgrounds)
```

---

# 2. Window System

## 2.1 Window Types and Sizes

Jarvis uses **floating windows**, NOT fullscreen overlays. This is critical for maintaining desktop context.

| Mode | Window Type | Size | Position | Resizable |
|------|-------------|------|----------|-----------|
| Chat | Standard | 700×500 | User choice | Yes |
| Focus | Panel | 400×300 | Bottom-right | No |
| Ray | HUD | 680×auto | Top-center | No |
| Voice | Overlay | N/A | Edge glow | N/A |

## 2.2 Why These Window Types?

### Chat Mode → Standard Window

**Rationale:**
- Users want to resize for long conversations
- May want to move out of the way
- Can minimize/hide like any app
- Sidebar needs reasonable width

**Window Level:** Normal (same level as other apps)

### Focus Mode → Panel

**Rationale:**
- Should float above work but not block much
- Fixed size keeps it unobtrusive
- Bottom-right is least intrusive corner
- Doesn't cover toolbars/menus

**Window Level:** Floating (above normal windows)

### Ray Mode → HUD Window

**Rationale:**
- Spotlight pattern: appears above everything
- Centered horizontally for easy reading
- Near top for quick eye movement
- Auto-height based on results

**Window Level:** Status (above almost everything)

### Voice Mode → Overlay

**Rationale:**
- Voice doesn't need a window
- Edge glow indicates state
- Transcript in center is transient
- User's desktop stays visible

**Implementation:** Full-screen transparent overlay

## 2.3 Window Implementation

```swift
// frontend/Core/WindowManager.swift

import SwiftUI
import AppKit

/// Manages all Jarvis windows
///
/// Responsibilities:
/// 1. Create windows of correct type and size
/// 2. Position windows correctly
/// 3. Handle show/hide transitions
/// 4. Manage window levels
/// 5. **ENSURE MUTUAL EXCLUSIVITY** - only ONE mode active at a time
class WindowManager: ObservableObject {
    
    /// Shared instance for global access
    static let shared = WindowManager()
    
    // Window references
    private var chatWindow: NSWindow?
    private var focusWindow: NSWindow?
    private var rayWindow: NSWindow?
    private var voiceOverlay: NSWindow?
    
    /// Currently active mode (only one can be active)
    @Published private(set) var activeMode: JarvisMode? = nil
    
    // MARK: - Mode Mutual Exclusivity
    
    /// Closes any currently active mode before opening a new one.
    /// This ensures only ONE mode is ever visible at a time.
    private func closeActiveMode() {
        switch activeMode {
        case .chat:
            chatWindow?.orderOut(nil)
        case .focus:
            focusWindow?.orderOut(nil)
        case .ray:
            rayWindow?.orderOut(nil)
        case .conversation:
            hideVoiceOverlay()
        case .none:
            break
        }
        activeMode = nil
    }
    
    // MARK: - Chat Window
    
    /// Opens the main Chat window (CLOSES any other active mode first)
    /// - Message area
    /// - Input bar at bottom
    func showChatWindow() {
        closeActiveMode()  // ← Ensure only one mode active
        
        if chatWindow == nil {
            // Create hosting view
            let content = ChatModeView()
            let hostingView = NSHostingView(rootView: content)
            
            // Configure window
            chatWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            chatWindow?.contentView = hostingView
            chatWindow?.title = "Jarvis"
            chatWindow?.minSize = NSSize(width: 500, height: 400)
            chatWindow?.maxSize = NSSize(width: 1200, height: 900)
            
            // Enable Liquid Glass
            chatWindow?.contentView?.wantsLayer = true
            
            // Center on first show
            chatWindow?.center()
        }
        
        chatWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        activeMode = .chat  // ← Track active mode
    
    // MARK: - Focus Window
    
    /// Opens the Focus panel in bottom-right
    ///
    /// Panel characteristics:
    /// - Floats above other windows
    /// - Fixed size (400×300)
    /// - Positioned in bottom-right corner
    /// - Semi-transparent/glass effect
    func showFocusWindow() {
        closeActiveMode()  // ← Close other modes first
        
        if focusWindow == nil {
            let content = FocusModeView()
            let hostingView = NSHostingView(rootView: content)
            
            // Use panel for floating behavior
            focusWindow = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            focusWindow?.contentView = hostingView
            focusWindow?.title = "Jarvis Focus"
            
            // Float above other windows
            focusWindow?.level = .floating
            
            // Doesn't become key (user keeps typing in their app)
            (focusWindow as? NSPanel)?.becomesKeyOnlyIfNeeded = true
            
            // Position in bottom-right
            positionFocusWindow()
        }
        
        focusWindow?.makeKeyAndOrderFront(nil)
        activeMode = .focus  // ← Track active mode
    }
    
    /// Positions Focus window in bottom-right corner
    private func positionFocusWindow() {
        guard let window = focusWindow,
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        
        let x = screenFrame.maxX - windowSize.width - 20  // 20pt margin
        let y = screenFrame.minY + 20  // 20pt from bottom
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Ray Window
    
    /// Opens the Spotlight-style Ray window
    ///
    /// HUD window characteristics:
    /// - No title bar
    /// - Centered horizontally at top
    /// - Auto-height based on content
    /// - Dismisses on click outside
    func showRayWindow() {
        closeActiveMode()  // ← Close other modes first
        
        if rayWindow == nil {
            let content = RayModeView()
            let hostingView = NSHostingView(rootView: content)
            
            // HUD-style window
            rayWindow = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 60),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            rayWindow?.contentView = hostingView
            
            // Above everything except screen savers
            rayWindow?.level = .statusBar
            
            // Transparent background (glass effect provides visuals)
            rayWindow?.isOpaque = false
            rayWindow?.backgroundColor = .clear
            
            // Can appear over fullscreen apps
            rayWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // Position
            positionRayWindow()
        }
        
        rayWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        activeMode = .ray  // ← Track active mode
    }
    
    /// Positions Ray window centered, near top
    private func positionRayWindow() {
        guard let window = rayWindow,
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.frame
        let windowSize = window.frame.size
        
        let x = (screenFrame.width - windowSize.width) / 2
        let y = screenFrame.height - windowSize.height - 150  // 150pt from top
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    /// Updates Ray window height based on content
    func updateRayWindowHeight(_ height: CGFloat) {
        guard let window = rayWindow else { return }
        
        let currentFrame = window.frame
        let newHeight = min(max(height, 60), 500)  // Min 60, max 500
        
        // Animate height change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().setFrame(
                NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y - (newHeight - currentFrame.height),
                    width: currentFrame.width,
                    height: newHeight
                ),
                display: true
            )
        }
    }
    
    // MARK: - Voice Overlay
    
    /// Shows the full-screen voice overlay with edge glow
    func showVoiceOverlay() {
        closeActiveMode()  // ← Close other modes first
        
        if voiceOverlay == nil {
            let content = ConversationModeView()
            let hostingView = NSHostingView(rootView: content)
            
            // Full-screen overlay
            voiceOverlay = NSWindow(
                contentRect: NSScreen.main?.frame ?? .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            voiceOverlay?.contentView = hostingView
            voiceOverlay?.level = .screenSaver  // Above everything
            voiceOverlay?.isOpaque = false
            voiceOverlay?.backgroundColor = .clear
            voiceOverlay?.ignoresMouseEvents = false
        }
        
        voiceOverlay?.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        voiceOverlay?.makeKeyAndOrderFront(nil)
        activeMode = .conversation  // ← Track active mode
    }
    
    /// Hides voice overlay with fade out
    func hideVoiceOverlay() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            voiceOverlay?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.voiceOverlay?.orderOut(nil)
            self?.voiceOverlay?.alphaValue = 1  // Reset for next show
        }
    }
}
```

---

# 3. Chat Mode - Complete Design

## 3.1 Layout Overview

Chat mode follows the **iMessage paradigm** exactly:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●              Jarvis                                             ─ □ × │
├────────────────────┬────────────────────────────────────────────────────────┤
│                    │                                                        │
│   HISTORY SIDEBAR  │                    MESSAGE AREA                        │
│      (200px)       │                   (500px wide)                         │
│                    │                                                        │
│                    │  Messages scroll vertically                            │
│                    │  User messages: right-aligned, blue                    │
│                    │  AI messages: left-aligned, gray                       │
│                    │                                                        │
│  Shows all history │                                                        │
│  from all modes    │  Plan cards appear inline with messages               │
│  with mode icons   │                                                        │
│                    │                                                        │
│  💬 = Chat         │                                                        │
│  🎤 = Voice        │                                                        │
│  ⚡ = Ray          │                                                        │
│  👁 = Focus        │                                                        │
│                    ├────────────────────────────────────────────────────────┤
│                    │                                                        │
│  [+ New Chat]      │   ┌─────────────────────────────────────────────────┐  │
│                    │   │ ⊕ │ Message Jarvis...                    │ 🎤│↑│  │
│                    │   └─────────────────────────────────────────────────┘  │
│                    │                                                        │
│                    │   iMessage-style input pill                            │
└────────────────────┴────────────────────────────────────────────────────────┘
```

## 3.2 Sidebar Design

**Purpose:** Shows conversation history from ALL modes, allowing users to:
1. See what they've discussed
2. Click to scroll to that conversation
3. Identify which mode each conversation was in

```swift
// frontend/Views/Components/HistorySidebar.swift

import SwiftUI

/// Sidebar showing conversation history from all modes
///
/// Design decisions:
/// 1. 200px width - enough for titles without wasting space
/// 2. Mode icons show origin (chat, voice, ray, focus)
/// 3. Relative timestamps ("2 hours ago")
/// 4. New Chat button at bottom
struct HistorySidebar: View {
    
    /// Session manager with all history
    @Environment(SessionManager.self) var sessions
    
    /// Currently selected history item
    @State private var selectedId: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            sidebarHeader
            
            Divider()
            
            // History list
            historyList
            
            Divider()
            
            // New chat button
            newChatButton
        }
        .frame(width: 200)
        .background(JarvisColors.surface)
    }
    
    // MARK: - Header
    
    private var sidebarHeader: some View {
        HStack {
            Text("History")
                .font(Theme.fontHeadline)
            
            Spacer()
            
            // Search button (optional)
            Button {
                // Future: open search
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
    }
    
    // MARK: - History List
    
    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spacingXS) {
                ForEach(sessions.active?.get_history_for_sidebar() ?? []) { item in
                    HistoryRow(
                        item: item,
                        isSelected: item.id == selectedId
                    )
                    .onTapGesture {
                        selectedId = item.id
                        sessions.scrollToMessage(item.id)
                    }
                }
            }
            .padding(Theme.spacingS)
        }
    }
    
    // MARK: - New Chat Button
    
    private var newChatButton: some View {
        Button {
            sessions.createNew()
            selectedId = nil
        } label: {
            Label("New Chat", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(JarvisColors.interactive)
        .padding(Theme.spacingM)
    }
}

// MARK: - History Row

/// Single row in history sidebar
///
/// Shows:
/// - Mode icon (color-coded)
/// - Title (first line of message, truncated)
/// - Relative timestamp
struct HistoryRow: View {
    let item: HistoryItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: Theme.spacingS) {
            // Mode icon
            modeIcon
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.fontBody)
                    .lineLimit(1)
                
                Text(item.relativeTime)
                    .font(Theme.fontCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, Theme.spacingS)
        .padding(.vertical, Theme.spacingS)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(JarvisColors.interactive.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
    }
    
    /// Icon based on mode with appropriate color
    private var modeIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundStyle(iconColor)
            .frame(width: 20)
    }
    
    private var iconName: String {
        switch item.mode {
        case "chat": return "bubble.left.fill"
        case "conversation": return "waveform"
        case "ray": return "bolt.fill"
        case "focus": return "eye.fill"
        default: return "bubble.left"
        }
    }
    
    private var iconColor: Color {
        switch item.mode {
        case "chat": return JarvisColors.interactive
        case "conversation": return JarvisColors.success
        case "ray": return JarvisColors.interactive
        case "focus": return JarvisColors.accent
        default: return .secondary
        }
    }
}
```

## 3.3 Input Bar - iMessage Style

The input bar is the **most frequently used UI element**. It must be:
1. Familiar (iMessage pattern)
2. Efficient (keyboard shortcuts)
3. Clear (obvious mic/send toggle)

**Layout: `[+] [TextField...] [🎤/↑]`**

```swift
// frontend/Views/Components/iMessageInputBar.swift

import SwiftUI

/// iMessage-style input bar for Chat mode
///
/// Layout:
/// ┌────────────────────────────────────────────────────┐
/// │ ⊕ │ Message Jarvis...                        │ 🎤 │ ← When empty
/// │ ⊕ │ Hello, I need help with...               │ ↑  │ ← When has text
/// └────────────────────────────────────────────────────┘
///
/// Key behaviors:
/// 1. + button: Opens file picker for attachments
/// 2. Text field: Multi-line, expands up to 5 lines
/// 3. Mic button: Shown when empty, starts voice input
/// 4. Send button: Shown when has text, sends message
/// 5. ⌘ + Enter: Also sends message
struct iMessageInputBar: View {
    
    /// Current input text
    @Binding var text: String
    
    /// Called when user taps send
    let onSend: () -> Void
    
    /// Called when user taps + button
    let onAddFile: () -> Void
    
    /// Called when user taps mic (starts voice input)
    let onStartVoice: () -> Void
    
    /// Tracks if text field is focused
    @FocusState private var isFocused: Bool
    
    /// Whether there's text to send
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        HStack(spacing: Theme.spacingS) {
            // ADD BUTTON (left of pill)
            addButton
            
            // INPUT PILL
            inputPill
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
    }
    
    // MARK: - Add Button
    
    /// + button for adding files/images
    private var addButton: some View {
        Button(action: onAddFile) {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .foregroundStyle(JarvisColors.interactive)
        }
        .buttonStyle(.plain)
        .help("Add files")
    }
    
    // MARK: - Input Pill
    
    /// The main input container (text field + send/mic)
    private var inputPill: some View {
        HStack(spacing: Theme.spacingS) {
            // TEXT FIELD
            TextField("Message Jarvis...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)  // Expands up to 5 lines
                .focused($isFocused)
                .onSubmit {
                    // Enter sends if has text
                    if hasText { sendMessage() }
                }
            
            // SEND / MIC BUTTON
            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(pillBackground)
    }
    
    /// The mic or send button depending on text state
    ///
    /// Animation: Uses SF Symbol magic replace transition
    /// for smooth morph between mic and arrow
    private var actionButton: some View {
        Button {
            if hasText {
                sendMessage()
            } else {
                onStartVoice()
            }
        } label: {
            Image(systemName: hasText ? "arrow.up.circle.fill" : "mic.fill")
                .font(.title2)
                .foregroundStyle(hasText ? JarvisColors.interactive : .secondary)
                // Magic crossfade animation between icons
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                // Bounce when state changes
                .symbolEffect(.bounce, value: hasText)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)  // ⌘ + Enter
    }
    
    /// Pill background - macOS 26 Liquid Glass capsule
    ///
    /// Uses the new glassEffect modifier for translucent,
    /// light-refracting appearance matching Spotlight aesthetic
    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .glassEffect(.regular)  // ← macOS 26 Liquid Glass
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
    }
    
    /// Sends message and clears input
    private func sendMessage() {
        onSend()
        text = ""
    }
}
```

## 3.4 Message Bubbles

Messages use the **iMessage convention**:
- User: Right-aligned, blue background, white text
- AI: Left-aligned, gray background, dark text

```swift
// frontend/Views/Components/MessageBubble.swift

import SwiftUI

/// Single message bubble in chat
///
/// Design matches iMessage:
/// - User messages: Right side, blue, white text
/// - AI messages: Left side, gray, dark text
/// - Bubbles have asymmetric corners (tail on sender side)
struct MessageBubble: View {
    let message: Message
    
    /// User messages are styled differently
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacingS) {
            // Left spacer for user messages (pushes right)
            if isUser { Spacer(minLength: 60) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                messageContent
                
                // Timestamp
                timestamp
            }
            .frame(maxWidth: 500, alignment: isUser ? .trailing : .leading)
            
            // Right spacer for AI messages (pushes left)
            if !isUser { Spacer(minLength: 60) }
        }
    }
    
    // MARK: - Message Content
    
    private var messageContent: some View {
        Text(message.content)
            .textSelection(.enabled)  // Allow copying
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleShape)
            .foregroundStyle(isUser ? .white : .primary)
    }
    
    /// Bubble shape with asymmetric corners
    ///
    /// User bubbles: Large radii except bottom-right (small, creates "tail")
    /// AI bubbles: Large radii except bottom-left (small, creates "tail")
    @ViewBuilder
    private var bubbleShape: some View {
        if isUser {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 4,  // Small radius = tail
                topTrailingRadius: 18
            )
            .fill(JarvisColors.userBubble)
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 4,  // Small radius = tail
                bottomTrailingRadius: 18,
                topTrailingRadius: 18
            )
            .fill(JarvisColors.assistantBubble)
        }
    }
    
    // MARK: - Timestamp
    
    private var timestamp: some View {
        Text(message.formattedTime)
            .font(Theme.fontCaption)
            .foregroundStyle(.secondary)
    }
}
```

## 3.5 Plan Card

When Jarvis executes a multi-step task, a **Plan Card** shows progress inline.

```swift
// frontend/Views/Components/PlanCard.swift

import SwiftUI

/// Shows execution plan with step-by-step progress
///
/// Appears inline in chat when Jarvis executes a multi-step task
/// Updates in real-time as steps complete
struct PlanCard: View {
    let plan: Plan
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            // Header
            header
            
            Divider()
                .padding(.vertical, Theme.spacingXS)
            
            // Steps
            ForEach(plan.steps) { step in
                PlanStepRow(step: step)
            }
        }
        .padding(Theme.spacingM)
        .background(cardBackground)
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "list.clipboard")
                .foregroundStyle(JarvisColors.interactive)
            
            Text(plan.summary)
                .font(Theme.fontHeadline)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .fill(JarvisColors.surface)
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

/// Single step in a plan
///
/// States:
/// - pending: Gray circle, secondary text
/// - running: Blue dotted circle (rotating), primary text, spinner
/// - completed: Green checkmark (bounces), primary text, "Done"
/// - failed: Red X (bounces), primary text, "Failed"
struct PlanStepRow: View {
    let step: PlanStep
    
    var body: some View {
        HStack(spacing: Theme.spacingS) {
            // Status icon
            statusIcon
                .frame(width: 20)
            
            // Description
            Text(step.description)
                .font(Theme.fontBody)
                .foregroundStyle(step.status == "pending" ? .secondary : .primary)
            
            Spacer()
            
            // Status indicator
            statusIndicator
        }
        .padding(.vertical, Theme.spacingXS)
    }
    
    /// Animated status icon
    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(JarvisColors.success)
                .symbolEffect(.bounce, value: step.status)
        
        case "running":
            Image(systemName: "circle.dotted")
                .foregroundStyle(JarvisColors.interactive)
                .symbolEffect(.rotate, isActive: true)
        
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(JarvisColors.error)
                .symbolEffect(.bounce, value: step.status)
        
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
    
    /// Status text or spinner
    @ViewBuilder
    private var statusIndicator: some View {
        switch step.status {
        case "running":
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Running")
                    .font(Theme.fontCaption)
                    .foregroundStyle(.secondary)
            }
        
        case "completed":
            Text("Done")
                .font(Theme.fontCaption)
                .foregroundStyle(JarvisColors.success)
        
        case "failed":
            Text("Failed")
                .font(Theme.fontCaption)
                .foregroundStyle(JarvisColors.error)
        
        default:
            EmptyView()
        }
    }
}
```

## 3.6 Complete Chat Mode View

```swift
// frontend/Views/ChatModeView.swift

import SwiftUI

/// Main Chat mode view with sidebar and messages
struct ChatModeView: View {
    @Environment(SessionManager.self) var sessions
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            HistorySidebar()
        } detail: {
            // Main content
            VStack(spacing: 0) {
                // Messages
                messageList
                
                Divider()
                
                // Input
                iMessageInputBar(
                    text: $viewModel.inputText,
                    onSend: { viewModel.send() },
                    onAddFile: { viewModel.showFilePicker = true },
                    onStartVoice: { viewModel.startVoiceInput() }
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.spacingM) {
                    ForEach(sessions.active?.messages ?? []) { message in
                        if message.role == .system { EmptyView() }
                        else {
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        // Show plan after message if applicable
                        if let plan = message.plan {
                            PlanCard(plan: plan)
                                .padding(.horizontal, 60)
                        }
                    }
                }
                .padding(Theme.spacingL)
            }
            .onChange(of: sessions.active?.messages.count) { _, _ in
                // Auto-scroll to bottom on new messages
                if let lastId = sessions.active?.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}
```

---

# 4. Ray Mode - Complete Design

## 4.1 Design Philosophy

Ray mode is **Spotlight for AI**:
- Appears instantly (⌘ + Space)
- Type naturally, get results
- Execute and dismiss
- Never blocks workflow

## 4.2 Layout

```
┌────────────────────────────────────────────────────────────────────┐
│ 🔍  open safari                                                [⌘] │ ← Search
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ 🌐 Safari                                         ➜ Open App │ │ ← Selected
│  │    Web Browser                           [blue background]    │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ 🔍 Search "open safari" on web                  ➜ Web Search │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ 📁 ~/Projects/Safari-Extension                    ➜ Folder   │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ 🤖 Ask Jarvis about Safari                        ➜ AI Chat  │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
                           [esc to dismiss]
```

## 4.3 Implementation

```swift
// frontend/Views/RayModeView.swift

import SwiftUI

/// Spotlight-style quick command interface
///
/// Key behaviors:
/// 1. Search field auto-focused on appear
/// 2. Results filtered as you type
/// 3. Arrow keys navigate results
/// 4. Enter executes selected
/// 5. Escape dismisses
struct RayModeView: View {
    @StateObject private var vm = RayViewModel()
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search input
            searchField
            
            // Results (if any)
            if !vm.results.isEmpty {
                Divider()
                resultsList
            }
        }
        .frame(width: 680)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusXXLarge))
        .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
        .onAppear { isSearchFocused = true }
        // Keyboard navigation
        .onKeyPress(.upArrow) { vm.selectPrevious(); return .handled }
        .onKeyPress(.downArrow) { vm.selectNext(); return .handled }
        .onKeyPress(.return) { vm.executeSelected(); return .handled }
        .onKeyPress(.escape) { vm.dismiss(); return .handled }
    }
    
    // MARK: - Search Field
    
    private var searchField: some View {
        HStack(spacing: Theme.spacingM) {
            // Magnifying glass icon
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: vm.query.isEmpty)
            
            // Text field
            TextField("", text: $vm.query, prompt: placeholderText)
                .textFieldStyle(.plain)
                .font(Theme.fontSearch)
                .focused($isSearchFocused)
                .onSubmit { vm.executeSelected() }
            
            // Hotkey indicator
            hotkeyBadge
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, 14)
    }
    
    private var placeholderText: Text {
        Text("Search or type a command...")
            .foregroundStyle(.secondary)
    }
    
    private var hotkeyBadge: some View {
        Text("⌘")
            .font(Theme.fontCaption)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
    
    // MARK: - Results List
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(vm.results.enumerated()), id: \.1.id) { idx, result in
                    RayResultRow(
                        result: result,
                        isSelected: idx == vm.selectedIndex
                    )
                    .onTapGesture { vm.execute(result) }
                }
            }
            .padding(Theme.spacingS)
        }
        .frame(maxHeight: 400)
    }
}

// MARK: - Result Row

/// Single result row in Ray mode
struct RayResultRow: View {
    let result: RayResult
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: Theme.spacingM) {
            // Icon
            Image(systemName: result.icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(isSelected ? .white : JarvisColors.interactive)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(Theme.fontBody)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(Theme.fontCaption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            
            Spacer()
            
            // Action label
            Text(result.actionLabel)
                .font(Theme.fontCaption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        Capsule().fill(.white.opacity(0.2))
                    }
                }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(JarvisColors.interactive)
            }
        }
        .contentShape(Rectangle())
    }
}
```

---

# 5. Conversation Mode - Complete Design

## 5.1 Siri 2026 Style

Apple's 2026 Siri uses **edge glow** around the entire screen, not a floating orb. The glow:
- Pulses with audio input level
- Changes color based on state
- Creates ethereal, futuristic feel

**Colors:**
- GREEN = Listening to user
- BLUE = Processing or Speaking

## 5.2 Implementation

```swift
// frontend/Views/ConversationModeView.swift

import SwiftUI

/// Voice conversation interface with edge glow
///
/// No window - just fullscreen overlay with:
/// 1. Dim background (sees desktop through)
/// 2. Animated edge glow
/// 3. Centered transcription card
/// 4. Tap anywhere to cancel
struct ConversationModeView: View {
    @StateObject private var vm = VoiceViewModel()
    
    var body: some View {
        ZStack {
            // Dimmed background - tap to cancel
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { vm.cancel() }
            
            // Edge glow
            EdgeGlowOverlay(
                color: glowColor,
                intensity: vm.audioLevel,
                isActive: vm.isActive
            )
            .ignoresSafeArea()
            
            // Center content
            centerContent
        }
    }
    
    // MARK: - Center Content
    
    private var centerContent: some View {
        VStack(spacing: Theme.spacingXL) {
            // Status text
            Text(statusText)
                .font(Theme.fontTitle)
                .foregroundStyle(.white.opacity(0.8))
            
            // Transcription (what user said)
            if !vm.transcription.isEmpty {
                transcriptionCard
            }
            
            // Response (what Jarvis is saying)
            if let response = vm.currentResponse, vm.isSpeaking {
                responseCard(response)
            }
        }
    }
    
    private var transcriptionCard: some View {
        Text(vm.transcription)
            .font(.title2)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: 500)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusLarge))
    }
    
    private func responseCard(_ text: String) -> some View {
        Text(text)
            .font(Theme.fontBody)
            .foregroundStyle(.white.opacity(0.9))
            .padding(Theme.spacingL)
            .frame(maxWidth: 400)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
    }
    
    // MARK: - State-Based Properties
    
    private var glowColor: Color {
        if vm.isSpeaking { return .blue }
        if vm.isProcessing { return .blue.opacity(0.7) }
        return .green  // Listening
    }
    
    private var statusText: String {
        if vm.isSpeaking { return "Speaking..." }
        if vm.isProcessing { return "Thinking..." }
        return "Listening..."
    }
}

// MARK: - Edge Glow Overlay

/// Animated edge glow around the entire screen
///
/// Creates Siri 2026 effect with:
/// - Gradient rotating around edges
/// - Intensity based on audio level
/// - Color for state (green/blue)
struct EdgeGlowOverlay: View {
    let color: Color
    let intensity: Float  // 0.0 to 1.0
    let isActive: Bool
    
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(phase),
                        endAngle: .degrees(phase + 360)
                    ),
                    lineWidth: lineWidth
                )
                .blur(radius: blurRadius)
                .opacity(isActive ? 1 : 0)
        }
        .animation(rotationAnimation, value: phase)
        .onAppear { phase = 360 }
    }
    
    /// Gradient colors - alternating opacity for flow effect
    private var gradientColors: [Color] {
        [
            color.opacity(0.8),
            color.opacity(0.4),
            color.opacity(0.8),
            color.opacity(0.4),
            color.opacity(0.8)
        ]
    }
    
    /// Line width grows with audio level
    private var lineWidth: CGFloat {
        4 + CGFloat(intensity) * 4  // 4-8pt
    }
    
    /// Blur grows with audio level
    private var blurRadius: CGFloat {
        10 + CGFloat(intensity) * 10  // 10-20pt
    }
    
    /// Continuous rotation animation
    private var rotationAnimation: Animation {
        .linear(duration: 3).repeatForever(autoreverses: false)
    }
}
```

---

# 6. Focus Mode - Complete Design

## 6.1 Concept

Focus mode is a **contextual assistant** that:
1. Analyzes what you're doing (via screen capture)
2. Proactively offers relevant help
3. Provides a compact interface for questions
4. Never interrupts workflow

## 6.2 Implementation

```swift
// frontend/Views/FocusModeView.swift

import SwiftUI

/// Small floating panel for contextual assistance
///
/// Positioned in bottom-right corner
/// Analyzes active application and offers help
struct FocusModeView: View {
    @StateObject private var vm = FocusViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingM) {
                    // Context awareness
                    if let context = vm.screenContext {
                        contextCard(context)
                    }
                    
                    // Quick actions
                    if !vm.suggestedActions.isEmpty {
                        quickActions
                    }
                    
                    // Recent messages (compact)
                    ForEach(vm.messages.suffix(5)) { msg in
                        CompactMessageRow(message: msg)
                    }
                }
                .padding(Theme.spacingM)
            }
            
            Divider()
            
            // Input
            iMessageInputBar(
                text: $vm.inputText,
                onSend: { vm.send() },
                onAddFile: {},
                onStartVoice: { vm.startVoice() }
            )
        }
        .frame(width: 400, height: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusLarge))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Image(systemName: "eye.fill")
                .foregroundStyle(JarvisColors.accent)
            
            Text("Focus Mode")
                .font(Theme.fontHeadline)
            
            Spacer()
            
            // What app we're watching
            if let app = vm.activeApp {
                Text(app)
                    .font(Theme.fontCaption)
                    .foregroundStyle(.secondary)
            }
            
            // Close button
            Button { vm.dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacingM)
    }
    
    // MARK: - Context Card
    
    private func contextCard(_ context: String) -> some View {
        Text(context)
            .font(Theme.fontBody)
            .padding(Theme.spacingM)
            .background(JarvisColors.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }
    
    // MARK: - Quick Actions
    
    private var quickActions: some View {
        HStack(spacing: Theme.spacingS) {
            ForEach(vm.suggestedActions) { action in
                Button(action.title) {
                    vm.executeAction(action)
                }
                .buttonStyle(.bordered)
                .tint(JarvisColors.interactive)
            }
        }
    }
}

/// Compact message for Focus mode's limited space
struct CompactMessageRow: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            // Role indicator dot
            Circle()
                .fill(message.role == .user ? JarvisColors.interactive : JarvisColors.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            
            Text(message.content)
                .font(Theme.fontCaption)
                .lineLimit(3)
        }
        .padding(.vertical, Theme.spacingXS)
    }
}
```

---

# 7. Shared Components

Components used across multiple modes.

## 7.1 Loading States

```swift
/// Consistent loading indicator
struct LoadingIndicator: View {
    let text: String?
    
    var body: some View {
        HStack(spacing: Theme.spacingS) {
            ProgressView()
            if let text {
                Text(text)
                    .font(Theme.fontCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

## 7.2 Error Views

```swift
/// Inline error message
struct ErrorBanner: View {
    let message: String
    let onRetry: (() -> Void)?
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(JarvisColors.error)
            
            Text(message)
                .font(Theme.fontBody)
            
            Spacer()
            
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(Theme.spacingM)
        .background(JarvisColors.error.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }
}
```

---

# 8. Animations & Interactions

## 8.1 SF Symbols Animations

Jarvis uses SF Symbols 7 animations throughout:

| Element | Animation | Trigger |
|---------|-----------|---------|
| Step completed ✓ | `.bounce` | Status changes to completed |
| Step running ● | `.rotate` | While running |
| Send button | `.replace.magic` | Text appears/disappears |
| Search icon | `.bounce` | Query changes |
| Error icon | `.bounce` | Error occurs |

## 8.2 View Transitions

```swift
// Standard transitions used throughout
extension AnyTransition {
    /// Fade + slide for message appear
    static var messageAppear: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }
    
    /// Scale + fade for results
    static var resultAppear: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        )
    }
}
```

---

# 9. Accessibility

## 9.1 VoiceOver Support

All UI elements have proper accessibility labels:

```swift
MessageBubble(message: msg)
    .accessibilityLabel("\(msg.role == .user ? "You said" : "Jarvis said"): \(msg.content)")
    .accessibilityHint("Message from \(msg.formattedTime)")
```

## 9.2 Keyboard Navigation

All modes fully support keyboard navigation:
- Tab to move between elements
- Arrow keys for lists
- Space/Enter to activate
- Escape to dismiss

## 9.3 High Contrast

Colors adapt automatically via system colors.

---

# 10. Settings UI

> [!IMPORTANT]
> Settings window uses macOS native Form with 6 tabs covering all user customizations.

## 10.1 Settings Window Structure

```
┌─────────────────────────────────────────────────────────────┐
│                      ⚙️ Settings                            │
├──────────┬──────────────────────────────────────────────────┤
│ General  │  [Current Tab Content]                           │
│ Models   │                                                  │
│ Voice    │                                                  │
│ Hotkeys  │                                                  │
│ Privacy  │                                                  │
│ Advanced │                                                  │
└──────────┴──────────────────────────────────────────────────┘
```

## 10.2 All Settings Tabs

```swift
// frontend/Views/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            
            ModelSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }
            
            VoiceSettingsTab()
                .tabItem { Label("Voice", systemImage: "waveform") }
            
            HotkeySettingsTab()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("showInMenuBar") var showInMenuBar = true
    @AppStorage("checkUpdates") var checkUpdates = true
    @AppStorage("defaultMode") var defaultMode = "chat"
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("chatHistoryDays") var chatHistoryDays = 30
    
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Jarvis at login", isOn: $launchAtLogin)
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Check for updates automatically", isOn: $checkUpdates)
            }
            
            Section("Defaults") {
                Picker("Default mode", selection: $defaultMode) {
                    Text("Chat").tag("chat")
                    Text("Ray").tag("ray")
                    Text("Focus").tag("focus")
                }
                
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            
            Section("Data") {
                Picker("Keep chat history for", selection: $chatHistoryDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(-1)
                }
                
                Button("Clear Chat History...", role: .destructive) {
                    // Show confirmation dialog
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Voice Tab

struct VoiceSettingsTab: View {
    @AppStorage("vadSensitivity") var vadSensitivity = 0.5
    @AppStorage("ttsVoice") var ttsVoice = "alloy"
    @AppStorage("sttLanguage") var sttLanguage = "en-US"
    @AppStorage("pushToTalk") var pushToTalk = false
    @AppStorage("voiceActivation") var voiceActivation = true
    
    var body: some View {
        Form {
            Section("Voice Detection") {
                Slider(value: $vadSensitivity, in: 0...1) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Low")
                } maximumValueLabel: {
                    Text("High")
                }
                
                Toggle("Push-to-talk mode", isOn: $pushToTalk)
                Toggle("Voice activation (say \"Hey Jarvis\")", isOn: $voiceActivation)
            }
            
            Section("Text-to-Speech") {
                Picker("Voice", selection: $ttsVoice) {
                    Text("Alloy (Natural)").tag("alloy")
                    Text("Echo (Deep)").tag("echo")
                    Text("Nova (Warm)").tag("nova")
                    Text("Shimmer (Clear)").tag("shimmer")
                }
                
                Button("Preview Voice") {
                    // Play sample
                }
            }
            
            Section("Speech Recognition") {
                Picker("Language", selection: $sttLanguage) {
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Spanish").tag("es-ES")
                    Text("French").tag("fr-FR")
                    Text("German").tag("de-DE")
                    Text("Japanese").tag("ja-JP")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkeys Tab

struct HotkeySettingsTab: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared
    
    var body: some View {
        Form {
            Section {
                Text("All hotkeys use Option (⌥) + key for simplicity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Mode Hotkeys") {
                HotkeyField(
                    label: "Chat Mode",
                    hotkey: $hotkeyManager.chatHotkey,
                    defaultValue: "⌥C"
                )
                HotkeyField(
                    label: "Ray Mode",
                    hotkey: $hotkeyManager.rayHotkey,
                    defaultValue: "⌥R"
                )
                HotkeyField(
                    label: "Voice Mode",
                    hotkey: $hotkeyManager.voiceHotkey,
                    defaultValue: "⌥V"
                )
                HotkeyField(
                    label: "Focus Mode",
                    hotkey: $hotkeyManager.focusHotkey,
                    defaultValue: "⌥F"
                )
            }
            
            Section {
                Button("Restore Defaults") {
                    hotkeyManager.restoreDefaults()
                }
                
                Text("Hotkeys are applied immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: hotkeyManager.chatHotkey) { _, _ in
            hotkeyManager.registerAllHotkeys()  // Re-register on change
        }
    }
}

/// HotkeyManager - Persists and registers global hotkeys
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    @AppStorage("hotkey.chat") var chatHotkey = "⌥C"
    @AppStorage("hotkey.ray") var rayHotkey = "⌥R"
    @AppStorage("hotkey.voice") var voiceHotkey = "⌥V"
    @AppStorage("hotkey.focus") var focusHotkey = "⌥F"
    
    func restoreDefaults() {
        chatHotkey = "⌥C"
        rayHotkey = "⌥R"
        voiceHotkey = "⌥V"
        focusHotkey = "⌥F"
        registerAllHotkeys()
    }
    
    func registerAllHotkeys() {
        // Uses MASShortcut or similar to register system-wide hotkeys
        // Hotkeys are immediately active after registration
    }
}

// MARK: - Privacy Tab

struct PrivacySettingsTab: View {
    @AppStorage("localProcessing") var localProcessing = true
    @AppStorage("sendAnalytics") var sendAnalytics = false
    @AppStorage("storeConversations") var storeConversations = true
    
    var body: some View {
        Form {
            Section("Processing") {
                Toggle("Prefer local processing", isOn: $localProcessing)
                Text("When enabled, Jarvis uses Ollama for all AI processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Data") {
                Toggle("Store conversations locally", isOn: $storeConversations)
                Toggle("Send anonymous usage analytics", isOn: $sendAnalytics)
            }
            
            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    Text("Granted").foregroundStyle(.green)
                }
                
                HStack {
                    Text("Screen Recording")
                    Spacer()
                    Button("Grant Access") {
                        // Open System Settings
                    }
                }
            }
            
            Section {
                Button("Delete All Data...", role: .destructive) {
                    // Show confirmation
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @AppStorage("backendPort") var backendPort = 8765
    @AppStorage("debugMode") var debugMode = false
    @AppStorage("experimentalFeatures") var experimentalFeatures = false
    
    var body: some View {
        Form {
            Section("Backend") {
                TextField("WebSocket Port", value: $backendPort, format: .number)
                Text("Restart required after changing port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Developer") {
                Toggle("Debug mode", isOn: $debugMode)
                Toggle("Experimental features", isOn: $experimentalFeatures)
            }
            
            Section("Troubleshooting") {
                Button("Reset Jarvis...") {
                    // Show confirmation with full reset
                }
                
                Button("Export Logs...") {
                    // Save logs to file
                }
                
                Button("Open Data Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "~/Library/Application Support/Jarvis"))
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

---

# 11. Menu Bar

## 11.1 App Menu Structure

```swift
// frontend/App/JarvisApp.swift

@main
struct JarvisApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Replace default "New Window" with "New Chat"
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { /* Create new session */ }
                    .keyboardShortcut("n")
                
                Button("Open Chat...") { /* Show chat picker */ }
                    .keyboardShortcut("o")
                
                Divider()
                
                Button("Export Chat...") { /* Export current */ }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            
            // Mode switching
            CommandMenu("Mode") {
                Button("Chat Mode") { WindowManager.shared.showChatWindow() }
                    .keyboardShortcut("j")
                
                Button("Ray Mode") { WindowManager.shared.showRayWindow() }
                    // 2x ⌘Space handled by HotkeyManager
                
                Button("Voice Mode") { WindowManager.shared.showVoiceOverlay() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                
                Button("Focus Mode") { WindowManager.shared.showFocusWindow() }
                    .keyboardShortcut("\\")
            }
            
            // View options
            CommandGroup(after: .toolbar) {
                Button("Show Sidebar") { /* Toggle */ }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                
                Button("Show Plan Panel") { /* Toggle */ }
                    .keyboardShortcut("p", modifiers: [.command, .control])
            }
            
            // Help menu additions
            CommandGroup(replacing: .help) {
                Button("Jarvis Help") { /* Open docs */ }
                    .keyboardShortcut("?")
                
                Divider()
                
                Button("Send Feedback...") { /* Open form */ }
                
                Divider()
                
                Button("Reset Jarvis...") { /* Show reset dialog */ }
            }
        }
        
        // Add Settings scene
        Settings {
            SettingsView()
        }
        
        // Menu bar extra
        MenuBarExtra("Jarvis", systemImage: "brain.head.profile") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
```

## 11.2 Menu Bar Status Icon

```swift
// frontend/Views/MenuBar/MenuBarView.swift

struct MenuBarView: View {
    @EnvironmentObject var state: JarvisState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                Circle()
                    .fill(state.isReady ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(state.isReady ? "Jarvis is Ready" : "Connecting...")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Quick actions
            Button {
                WindowManager.shared.showChatWindow()
            } label: {
                Label("Open Chat", systemImage: "bubble.left.fill")
            }
            .keyboardShortcut("j")
            
            Button {
                WindowManager.shared.showRayWindow()
            } label: {
                Label("Open Ray", systemImage: "magnifyingglass")
                Text("⌘Space ×2").foregroundStyle(.secondary)
            }
            
            Button {
                WindowManager.shared.showVoiceOverlay()
            } label: {
                Label("Voice Mode", systemImage: "waveform")
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            
            Button {
                WindowManager.shared.showFocusWindow()
            } label: {
                Label("Focus Mode", systemImage: "eye.fill")
            }
            .keyboardShortcut("\\")
            
            Divider()
            
            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            
            Divider()
            
            Button("Quit Jarvis") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
```

---

# 12. Onboarding Flow

> [!IMPORTANT]
> Onboarding is **optional** and accessible via Settings → General → "Run Setup Assistant".
> It automatically detects already-granted permissions and only prompts for missing ones.

## 12.1 PermissionChecker (Auto-Detection)

```swift
// frontend/Core/PermissionChecker.swift

import Foundation

/// Checks macOS permissions and detects what's already granted
/// Used by onboarding to skip already-completed steps
class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()
    
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false
    @Published var calendarGranted = false
    @Published var contactsGranted = false
    @Published var automationGranted = false
    
    init() {
        refresh()
    }
    
    /// Refresh all permission states - call on app launch and after returning from System Settings
    func refresh() {
        Task {
            await MainActor.run {
                accessibilityGranted = checkAccessibility()
                screenRecordingGranted = checkScreenRecording()
                calendarGranted = checkCalendar()
                contactsGranted = checkContacts()
                automationGranted = checkAutomation()
            }
        }
    }
    
    private func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }
    
    private func checkScreenRecording() -> Bool {
        // Screen recording is checked by attempting a capture
        CGPreflightScreenCaptureAccess()
    }
    
    private func checkCalendar() -> Bool {
        // Check EventKit authorization
        let script = "tell application \"Calendar\" to return name of calendars"
        let result = runAppleScript(script)
        return result != nil
    }
    
    private func checkContacts() -> Bool {
        let script = "tell application \"Contacts\" to return count of people"
        let result = runAppleScript(script)
        return result != nil
    }
    
    private func checkAutomation() -> Bool {
        let script = "tell application \"System Events\" to return name of every process"
        let result = runAppleScript(script)
        return result != nil
    }
    
    /// Returns list of permissions that are NOT yet granted
    var missingPermissions: [PermissionType] {
        var missing: [PermissionType] = []
        if !accessibilityGranted { missing.append(.accessibility) }
        if !screenRecordingGranted { missing.append(.screenRecording) }
        if !automationGranted { missing.append(.automation) }
        return missing
    }
    
    /// True if all required permissions are granted
    var allRequiredGranted: Bool {
        accessibilityGranted && automationGranted
    }
}

enum PermissionType {
    case accessibility
    case screenRecording
    case calendar
    case contacts
    case automation
    
    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .calendar: return "Calendar"
        case .contacts: return "Contacts"
        case .automation: return "Automation"
        }
    }
    
    var isRequired: Bool {
        switch self {
        case .accessibility, .automation: return true
        default: return false
        }
    }
}
```

## 12.2 Optional Onboarding View

```swift
// frontend/Views/Onboarding/OnboardingView.swift

struct OnboardingView: View {
    @StateObject private var permissions = PermissionChecker.shared
    @State private var currentStep = 0
    @Environment(\.dismiss) var dismiss
    
    // Calculate dynamic steps based on what's missing
    private var steps: [OnboardingStep] {
        var steps: [OnboardingStep] = [.welcome]
        
        // Only show permissions step if something is missing
        if !permissions.missingPermissions.isEmpty {
            steps.append(.permissions)
        }
        
        steps.append(.modelSelection)
        steps.append(.completion)
        return steps
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress
            ProgressView(value: Double(currentStep + 1), total: Double(steps.count))
                .padding()
            
            // Dynamic step content
            Group {
                switch steps[currentStep] {
                case .welcome:
                    WelcomeStep(onNext: nextStep)
                case .permissions:
                    PermissionsStep(
                        missingPermissions: permissions.missingPermissions,
                        onNext: nextStep,
                        onRefresh: { permissions.refresh() }
                    )
                case .modelSelection:
                    ModelSelectionStep(onNext: nextStep)
                case .completion:
                    CompletionStep(onComplete: { dismiss() })
                }
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            permissions.refresh()  // Check permissions on open
        }
    }
    
    private func nextStep() {
        if currentStep < steps.count - 1 {
            withAnimation { currentStep += 1 }
        }
    }
}

enum OnboardingStep {
    case welcome, permissions, modelSelection, completion
}

// MARK: - Permissions Step (Only shows missing ones)

struct PermissionsStep: View {
    let missingPermissions: [PermissionType]
    let onNext: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Permissions Needed")
                .font(.title.bold())
            
            Text("Jarvis needs these permissions to help you:")
                .foregroundStyle(.secondary)
            
            // Only show MISSING permissions
            VStack(spacing: 12) {
                ForEach(missingPermissions, id: \.self) { permission in
                    PermissionRow(permission: permission)
                }
            }
            
            if missingPermissions.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All permissions granted!")
                }
            }
            
            Spacer()
            
            HStack {
                Button("Check Again") {
                    onRefresh()
                }
                
                Spacer()
                
                Button("Continue") {
                    onNext()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }
}
```

## 12.3 Adding to General Settings Tab

```swift
// Add to GeneralSettingsTab
Section("Setup") {
    Button("Run Setup Assistant...") {
        // Show onboarding sheet
        showOnboarding = true
    }
    
    Text("Re-run the initial setup wizard.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

---

# 13. Error Handling

> [!IMPORTANT]
> Error handling is **adaptive** and **generic** - not hardcoded for specific errors.
> Every operation has fallbacks. Jarvis should never crash or fail completely.

## 13.1 Adaptive Error System

```swift
// frontend/Core/ErrorHandler.swift

import Foundation

/// Generic error wrapper that adapts to any error type
/// Not hardcoded - works with any Error
struct JarvisError: Identifiable {
    let id = UUID()
    let underlyingError: Error
    let context: ErrorContext
    let timestamp: Date = Date()
    
    /// Computed properties adapt to the error type
    var title: String {
        // Try to get localized description, fall back to generic
        if let localizedError = underlyingError as? LocalizedError {
            return localizedError.errorDescription ?? "Something went wrong"
        }
        return "Something went wrong"
    }
    
    var message: String {
        // Try to get recovery suggestion
        if let localizedError = underlyingError as? LocalizedError {
            return localizedError.recoverySuggestion ?? genericMessage
        }
        return genericMessage
    }
    
    private var genericMessage: String {
        "An unexpected error occurred. Please try again."
    }
    
    var canRetry: Bool {
        context.retryable
    }
    
    var icon: String {
        switch context.category {
        case .network: return "wifi.exclamationmark"
        case .permission: return "lock.fill"
        case .model: return "cpu"
        case .system: return "exclamationmark.triangle"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var iconColor: Color {
        switch context.severity {
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        }
    }
}

struct ErrorContext {
    let category: ErrorCategory
    let severity: ErrorSeverity
    let retryable: Bool
    let fallbackAction: (() -> Void)?
    
    static func from(_ error: Error) -> ErrorContext {
        // Analyze error to determine context
        let nsError = error as NSError
        
        // Network errors
        if nsError.domain == NSURLErrorDomain {
            return ErrorContext(
                category: .network,
                severity: .warning,
                retryable: true,
                fallbackAction: nil
            )
        }
        
        // Permission errors
        if nsError.code == -1719 || nsError.code == -1743 { // AppleScript permission errors
            return ErrorContext(
                category: .permission,
                severity: .warning,
                retryable: false,
                fallbackAction: { openSystemSettings() }
            )
        }
        
        // Default: unknown but recoverable
        return ErrorContext(
            category: .unknown,
            severity: .warning,
            retryable: true,
            fallbackAction: nil
        )
    }
}

enum ErrorCategory {
    case network, permission, model, system, unknown
}

enum ErrorSeverity {
    case info, warning, error
}
```

## 13.2 Robust Error View (Generic)

```swift
// frontend/Views/Components/ErrorView.swift

/// Generic error view that works with ANY error
struct ErrorView: View {
    let error: JarvisError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Adaptive icon
            Image(systemName: error.icon)
                .font(.system(size: 40))
                .foregroundStyle(error.iconColor)
            
            // Adaptive title
            Text(error.title)
                .font(.headline)
            
            // Adaptive message
            Text(error.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            
            HStack(spacing: 12) {
                // Dismiss always available
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                
                // Retry if applicable
                if error.canRetry, let retry = onRetry {
                    Button("Retry", action: retry)
                        .buttonStyle(.borderedProminent)
                }
                
                // Fallback action if available
                if let fallback = error.context.fallbackAction {
                    Button("Fix Issue") {
                        fallback()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

## 13.3 Fallback System

```swift
// frontend/Core/FallbackManager.swift

/// Manages fallbacks for every major operation
class FallbackManager {
    static let shared = FallbackManager()
    
    /// Execute with automatic fallbacks
    func execute<T>(
        primary: () async throws -> T,
        fallbacks: [() async throws -> T],
        onAllFailed: (Error) -> T
    ) async -> T {
        // Try primary
        do {
            return try await primary()
        } catch {
            // Try each fallback in order
            for fallback in fallbacks {
                do {
                    return try await fallback()
                } catch {
                    continue  // Try next fallback
                }
            }
            
            // All failed - use final fallback
            return onAllFailed(error)
        }
    }
}

// Example usage in ModelManager
extension ModelManager {
    func generateWithFallbacks(prompt: String) async -> String {
        await FallbackManager.shared.execute(
            primary: {
                // Try primary model
                try await self.primaryProvider.generate(prompt)
            },
            fallbacks: [
                {
                    // Fallback 1: Try local Ollama
                    try await OllamaProvider().generate(prompt)
                },
                {
                    // Fallback 2: Try cached response
                    try await self.cache.getSimilar(prompt)
                }
            ],
            onAllFailed: { error in
                // Final fallback: Graceful error message
                "I'm having trouble processing that right now. Please try again in a moment."
            }
        )
    }
}
```

## 13.4 Global Error Handler

```swift
// frontend/Core/GlobalErrorHandler.swift

/// Global error handler that catches all unhandled errors
class GlobalErrorHandler: ObservableObject {
    static let shared = GlobalErrorHandler()
    
    @Published var currentError: JarvisError?
    @Published var errorLog: [JarvisError] = []
    
    func handle(_ error: Error, context: String = "") {
        let jarvisError = JarvisError(
            underlyingError: error,
            context: ErrorContext.from(error)
        )
        
        // Log for debugging
        errorLog.append(jarvisError)
        
        // Show to user if not already showing an error
        if currentError == nil {
            currentError = jarvisError
        }
        
        // Log to file for debugging
        logToFile(jarvisError, context: context)
    }
    
    func dismiss() {
        currentError = nil
    }
    
    private func logToFile(_ error: JarvisError, context: String) {
        // Write to ~/Library/Logs/Jarvis/
    }
}

// Apply globally in app
@main
struct JarvisApp: App {
    @StateObject var errorHandler = GlobalErrorHandler.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(errorHandler)
                .overlay {
                    if let error = errorHandler.currentError {
                        ErrorView(
                            error: error,
                            onRetry: nil,
                            onDismiss: { errorHandler.dismiss() }
                        )
                    }
                }
        }
    }
}
```

---

**Continue to Part 3: Backend Implementation →**


