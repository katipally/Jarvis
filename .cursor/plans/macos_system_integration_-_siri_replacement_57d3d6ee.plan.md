---
name: macOS 26 Focus Mode - Complete AI Agent System Control
overview: Complete implementation plan for Focus Mode that transforms Jarvis into a Siri replacement with master control over macOS. Includes Dynamic Island-style menu bar integration, floating chat window, and AI agent control via Accessibility API, AppleScript, and Vision - all without interrupting user's mouse/keyboard.
todos: []
---

# macOS 26 Focus Mode - Complete AI Agent System Control

## Overview

Transform Jarvis into a **Siri replacement** with **master control over macOS 26**. Focus Mode provides:

1. **Dynamic Island Integration**: App minimizes into a pill-shaped element near the camera notch in the menu bar
2. **Floating Chat Window**: Expands from the pill into a square chat window, always on top
3. **All Existing Features**: Chat, file processing, markdown, branching - everything preserved
4. **Master System Control**: Direct control via Accessibility API, AppleScript, Vision framework
5. **Non-Intrusive**: Controls Mac WITHOUT interrupting user's mouse/keyboard
6. **Clean Screenshots**: Excludes Jarvis window when capturing screen for analysis
7. **One-Time Permissions**: Request all permissions once via system dialogs

References:

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Liquid Glass Design](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [macOS 26 Features](https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/)

---

## Architecture Overview

```javascript
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FRONTEND (SwiftUI + AppKit)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────────────────────────┐ │
│  │   Main App      │    │              FOCUS MODE                          │ │
│  │   (Existing)    │    │  ┌─────────────────────────────────────────────┐ │ │
│  │                 │    │  │ Dynamic Island Pill (Menu Bar)               │ │ │
│  │ • Chat UI       │    │  │ • Shows near camera notch                    │ │ │
│  │ • Conversations │◄──►│  │ • Click expands to floating window          │ │ │
│  │ • File Upload   │    │  │ • Live Activities for status                │ │ │
│  │ • Markdown      │    │  └────────────────┬────────────────────────────┘ │ │
│  │ • Branching     │    │                   │ expand/collapse              │ │
│  │ • Settings      │    │  ┌────────────────▼────────────────────────────┐ │ │
│  └─────────────────┘    │  │ Floating Chat Window (NSPanel)               │ │ │
│                         │  │ • Always on top (.floating level)           │ │ │
│                         │  │ • Liquid Glass design                        │ │ │
│                         │  │ • All chat features included                 │ │ │
│                         │  │ • System control commands                    │ │ │
│                         │  └────────────────┬────────────────────────────┘ │ │
│                         └───────────────────┼───────────────────────────────┘ │
└─────────────────────────────────────────────┼───────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼───────────────────────────────┐
│                         SYSTEM CONTROL SERVICES                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────────┐│
│  │ Accessibility API │  │   AppleScript/JXA │  │     Screen Capture        ││
│  │   (AXUIElement)   │  │                   │  │  (CGWindowListCopy...)    ││
│  │                   │  │                   │  │                           ││
│  │ • Click buttons   │  │ • Complex actions │  │ • Exclude Jarvis window   ││
│  │ • Set text values │  │ • App automation  │  │ • Full screen capture     ││
│  │ • Read UI state   │  │ • System commands │  │ • Window-specific capture ││
│  │ • Window control  │  │ • File operations │  │ • Send to Vision/GPT-4V   ││
│  └─────────┬─────────┘  └─────────┬─────────┘  └─────────────┬─────────────┘│
│            │                      │                          │               │
│  ┌─────────▼──────────────────────▼──────────────────────────▼─────────────┐│
│  │                    App Management Service                                ││
│  │  • NSWorkspace.shared - List/Open/Activate apps                         ││
│  │  • NSRunningApplication - Get running apps, terminate/force quit        ││
│  │  • CGWindowListCopyWindowInfo - Window enumeration                      ││
│  └──────────────────────────────────┬──────────────────────────────────────┘│
└─────────────────────────────────────┼───────────────────────────────────────┘
                                      │ API calls
┌─────────────────────────────────────▼───────────────────────────────────────┐
│                           BACKEND (FastAPI + LangGraph)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │
│  │   Chat API      │    │   Focus Mode    │    │   System Control        │  │
│  │   (Existing)    │    │   API           │    │   Tools                 │  │
│  │                 │    │                 │    │                         │  │
│  │ • /chat         │    │ • /focus/action │    │ • open_application      │  │
│  │ • /upload       │    │ • /focus/screen │    │ • list_running_apps     │  │
│  │ • /conversations│    │ • /focus/status │    │ • close_application     │  │
│  └────────┬────────┘    └────────┬────────┘    │ • click_ui_element      │  │
│           │                      │             │ • type_text             │  │
│           └──────────┬───────────┘             │ • analyze_screen        │  │
│                      │                         │ • execute_script        │  │
│  ┌───────────────────▼─────────────────────┐   │ • get_window_info       │  │
│  │         LangGraph Agent                  │   └────────────┬────────────┘  │
│  │  • Uses system control tools             │◄───────────────┘              │
│  │  • Vision analysis with GPT-4V           │                               │
│  │  • Reasoning before actions              │                               │
│  │  • Multi-step task execution             │                               │
│  └──────────────────────────────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Frontend - Focus Mode Tab & UI Structure

### 1.1 Tab Navigation with Focus Mode

**File**: `frontend/JarvisAI/JarvisAI/ContentView.swift`Add a tab view to switch between main Assistant and Focus Mode:

```swift
import SwiftUI

struct MainTabView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var focusModeManager = FocusModeManager.shared
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some View {
        TabView {
            // Tab 1: Existing Assistant (unchanged)
            ContentView()
                .tabItem {
                    Label("Assistant", systemImage: "bubble.left.and.bubble.right")
                }
            
            // Tab 2: Focus Mode (new)
            FocusModeTabView()
                .tabItem {
                    Label("Focus", systemImage: "target")
                }
        }
        .preferredColorScheme(appTheme == .system ? nil : (appTheme == .dark ? .dark : .light))
    }
}
```



### 1.2 Focus Mode Tab View

**File**: `frontend/JarvisAI/JarvisAI/Views/FocusMode/FocusModeTabView.swift`Initial activation screen with Liquid Glass design:

```swift
import SwiftUI

struct FocusModeTabView: View {
    @StateObject private var focusModeManager = FocusModeManager.shared
    @State private var showPermissionSetup = false
    
    var body: some View {
        ZStack {
            // Liquid Glass background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            if focusModeManager.isActive {
                // When active, show minimal status (main UI is in floating window)
                FocusModeActiveView()
            } else {
                // Activation screen
                FocusModeActivationView(showPermissionSetup: $showPermissionSetup)
            }
        }
        .sheet(isPresented: $showPermissionSetup) {
            PermissionSetupView()
        }
    }
}

struct FocusModeActivationView: View {
    @Binding var showPermissionSetup: Bool
    @StateObject private var focusModeManager = FocusModeManager.shared
    @StateObject private var permissionManager = FocusModePermissionManager.shared
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("Focus Mode")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Control your Mac with AI")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                Text("Minimize to menu bar and control apps, manage windows, understand your screen - all with natural language.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Feature list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "app.badge", title: "Open & close any app")
                FeatureRow(icon: "eye", title: "Understand what's on screen")
                FeatureRow(icon: "list.bullet", title: "List & manage running apps")
                FeatureRow(icon: "cursorarrow.click", title: "Click buttons, enter text")
                FeatureRow(icon: "keyboard", title: "Won't interrupt your input")
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            
            // Activation button
            Button(action: activateFocusMode) {
                HStack {
                    Image(systemName: "power")
                    Text("Enter Focus Mode")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }
    
    private func activateFocusMode() {
        // Check permissions first
        if !permissionManager.allPermissionsGranted {
            showPermissionSetup = true
        } else {
            focusModeManager.activate()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(title)
                .font(.body)
        }
    }
}
```

---

## Phase 2: Dynamic Island / Menu Bar Integration

### 2.1 Focus Mode Manager (Singleton)

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/FocusModeManager.swift`Central manager that handles activation, menu bar, and floating window:

```swift
import SwiftUI
import AppKit
import Combine

@MainActor
class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()
    
    // State
    @Published var isActive: Bool = false
    @Published var isFloatingWindowVisible: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var isProcessing: Bool = false
    
    // Window references
    private var statusItem: NSStatusItem?
    private var floatingWindowController: FloatingWindowController?
    private var popoverController: NSPopover?
    
    // Position near camera notch (right side of menu bar)
    private let menuBarPosition: CGFloat = 0 // Will be calculated
    
    private init() {}
    
    // MARK: - Activation
    
    func activate() {
        guard !isActive else { return }
        
        isActive = true
        
        // 1. Create menu bar item (Dynamic Island pill)
        setupMenuBarItem()
        
        // 2. Hide main app window
        hideMainWindow()
        
        // 3. Show floating window
        showFloatingWindow()
    }
    
    func deactivate() {
        guard isActive else { return }
        
        isActive = false
        
        // 1. Remove menu bar item
        removeMenuBarItem()
        
        // 2. Hide floating window
        hideFloatingWindow()
        
        // 3. Show main app window
        showMainWindow()
    }
    
    // MARK: - Menu Bar (Dynamic Island Pill)
    
    private func setupMenuBarItem() {
        // Create status item near the camera notch area
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Pill-shaped appearance with Liquid Glass effect
            let pillView = DynamicIslandPillView(manager: self)
            let hostingView = NSHostingView(rootView: pillView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 44, height: 22)
            button.addSubview(hostingView)
            button.frame = hostingView.frame
            
            // Click action - toggle floating window
            button.action = #selector(toggleFloatingWindow)
            button.target = self
        }
    }
    
    private func removeMenuBarItem() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    
    @objc private func toggleFloatingWindow() {
        if isFloatingWindowVisible {
            collapseToMenuBar()
        } else {
            expandFromMenuBar()
        }
    }
    
    // MARK: - Floating Window (Expands from Menu Bar)
    
    func showFloatingWindow() {
        if floatingWindowController == nil {
            floatingWindowController = FloatingWindowController()
        }
        
        // Position below menu bar, animate from pill
        floatingWindowController?.showWindow(animateFrom: statusItem?.button)
        isFloatingWindowVisible = true
    }
    
    func hideFloatingWindow() {
        floatingWindowController?.hideWindow(animateTo: statusItem?.button)
        isFloatingWindowVisible = false
    }
    
    func expandFromMenuBar() {
        floatingWindowController?.expand(from: statusItem?.button)
        isFloatingWindowVisible = true
    }
    
    func collapseToMenuBar() {
        floatingWindowController?.collapse(to: statusItem?.button)
        isFloatingWindowVisible = false
    }
    
    // MARK: - Main Window Management
    
    private func hideMainWindow() {
        NSApp.windows.filter { $0.isVisible && $0.title != "Jarvis Focus" }.forEach {
            $0.orderOut(nil)
        }
    }
    
    private func showMainWindow() {
        NSApp.windows.filter { $0.title != "Jarvis Focus" }.forEach {
            $0.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Status Updates
    
    func updateStatus(_ message: String, processing: Bool = false) {
        statusMessage = message
        isProcessing = processing
    }
}
```



### 2.2 Dynamic Island Pill View

**File**: `frontend/JarvisAI/JarvisAI/Views/FocusMode/DynamicIslandPillView.swift`The pill-shaped menu bar element that looks like Dynamic Island:

```swift
import SwiftUI

struct DynamicIslandPillView: View {
    @ObservedObject var manager: FocusModeManager
    @State private var isHovering = false
    @State private var pulseAnimation = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Animated icon
            ZStack {
                if manager.isProcessing {
                    // Processing animation
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                        .onAppear { pulseAnimation = true }
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 14, height: 14)
            
            // Expand on hover to show status
            if isHovering {
                Text(manager.statusMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.black.opacity(0.8))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
```

---

## Phase 3: Floating Chat Window (Always On Top)

### 3.1 Floating Window Controller

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/FloatingWindowController.swift`NSPanel-based floating window that's always on top:

```swift
import AppKit
import SwiftUI

class FloatingWindowController: NSObject {
    private var panel: NSPanel?
    private var contentView: NSHostingView<FloatingChatView>?
    
    // Window size
    private let windowSize = NSSize(width: 400, height: 500)
    private let collapsedSize = NSSize(width: 44, height: 22)
    
    override init() {
        super.init()
        setupPanel()
    }
    
    private func setupPanel() {
        // Create floating panel
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .fullSizeContentView,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )
        
        guard let panel = panel else { return }
        
        // CRITICAL: Always on top of ALL processes
        panel.level = .floating  // NSWindow.Level.floating = 3
        panel.collectionBehavior = [
            .canJoinAllSpaces,      // Visible on all spaces/desktops
            .fullScreenAuxiliary,   // Works in full screen apps
            .stationary             // Doesn't move with spaces
        ]
        
        // Appearance
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false  // IMPORTANT: Stay visible when app loses focus
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        
        // Rounded corners (Liquid Glass style)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 20
        panel.contentView?.layer?.masksToBounds = true
        
        // SwiftUI content
        let chatView = FloatingChatView()
        contentView = NSHostingView(rootView: chatView)
        contentView?.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView?.addSubview(contentView!)
        
        // Position: top-right corner, below menu bar
        positionWindow()
    }
    
    private func positionWindow() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - windowSize.width - 20  // 20pt from right edge
        let y = screenFrame.maxY - windowSize.height - 10 // 10pt below menu bar
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Show/Hide with Animations
    
    func showWindow(animateFrom menuBarButton: NSButton?) {
        guard let panel = panel else { return }
        
        // Start small (collapsed)
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: collapsedSize),
            display: true
        )
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        
        // Animate expansion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            panel.animator().setFrame(
                NSRect(origin: panel.frame.origin, size: windowSize),
                display: true
            )
            panel.animator().alphaValue = 1
        }
    }
    
    func hideWindow(animateTo menuBarButton: NSButton?) {
        guard let panel = panel else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            panel.animator().alphaValue = 0
            panel.animator().setFrame(
                NSRect(origin: panel.frame.origin, size: collapsedSize),
                display: true
            )
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    func expand(from menuBarButton: NSButton?) {
        guard let panel = panel else { return }
        
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            panel.animator().setFrame(
                NSRect(origin: panel.frame.origin, size: windowSize),
                display: true
            )
            panel.animator().alphaValue = 1
        }
    }
    
    func collapse(to menuBarButton: NSButton?) {
        hideWindow(animateTo: menuBarButton)
    }
}
```



### 3.2 Floating Chat View

**File**: `frontend/JarvisAI/JarvisAI/Views/FocusMode/FloatingChatView.swift`The SwiftUI chat interface inside the floating window with ALL existing features:

```swift
import SwiftUI
import MarkdownUI

struct FloatingChatView: View {
    @StateObject private var viewModel = FocusChatViewModel()
    @StateObject private var focusModeManager = FocusModeManager.shared
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""
    
    var body: some View {
        ZStack {
            // Liquid Glass background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack(spacing: 0) {
                // Header
                FloatingChatHeader()
                
                Divider()
                    .background(.white.opacity(0.1))
                
                // Messages (includes ALL existing features)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                FocusMessageRow(
                                    message: message,
                                    viewModel: viewModel
                                )
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                
                // Input area
                FocusInputArea(
                    inputText: $inputText,
                    isInputFocused: $isInputFocused,
                    onSend: sendMessage
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let text = inputText
        inputText = ""
        
        Task {
            await viewModel.sendMessage(text)
        }
    }
}

struct FloatingChatHeader: View {
    @StateObject private var focusModeManager = FocusModeManager.shared
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(focusModeManager.isProcessing ? .orange : .green)
                .frame(width: 8, height: 8)
            
            Text("Jarvis Focus")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Status message
            Text(focusModeManager.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Collapse button
            Button(action: { focusModeManager.collapseToMenuBar() }) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            // Exit button
            Button(action: { focusModeManager.deactivate() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

struct FocusInputArea: View {
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Text input
            TextField("Ask Jarvis anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .focused(isInputFocused)
                .lineLimit(1...5)
                .onSubmit(onSend)
            
            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        inputText.isEmpty ? .gray : .blue
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }
}
```

---

## Phase 4: System Control Services (Frontend)

### 4.1 Master Control Service

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/SystemControlService.swift`The main service that provides master control over macOS:

```swift
import Foundation
import AppKit
import ApplicationServices

/// Master control service for macOS - provides AI agent control capabilities
actor SystemControlService {
    static let shared = SystemControlService()
    
    // MARK: - App Management
    
    /// List all running applications
    func listRunningApps() async -> [AppInfo] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        return runningApps.compactMap { app -> AppInfo? in
            guard let name = app.localizedName,
                  let bundleId = app.bundleIdentifier else { return nil }
            
            return AppInfo(
                name: name,
                bundleIdentifier: bundleId,
                isActive: app.isActive,
                isHidden: app.isHidden,
                processIdentifier: app.processIdentifier
            )
        }
    }
    
    /// Open an application by name or bundle ID
    func openApp(nameOrBundleId: String) async throws -> Bool {
        let workspace = NSWorkspace.shared
        
        // Try by bundle ID first
        if let appURL = workspace.urlForApplication(withBundleIdentifier: nameOrBundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await workspace.openApplication(at: appURL, configuration: config)
            return true
        }
        
        // Try by name
        let apps = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil
        )
        
        if let appURL = apps.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased()
                .contains(nameOrBundleId.lowercased())
        }) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await workspace.openApplication(at: appURL, configuration: config)
            return true
        }
        
        throw SystemControlError.appNotFound(nameOrBundleId)
    }
    
    /// Close/quit an application (graceful)
    func closeApp(nameOrBundleId: String) async throws -> Bool {
        let app = findRunningApp(nameOrBundleId: nameOrBundleId)
        guard let app = app else {
            throw SystemControlError.appNotFound(nameOrBundleId)
        }
        
        return app.terminate()
    }
    
    /// Force quit an application
    func forceQuitApp(nameOrBundleId: String) async throws -> Bool {
        let app = findRunningApp(nameOrBundleId: nameOrBundleId)
        guard let app = app else {
            throw SystemControlError.appNotFound(nameOrBundleId)
        }
        
        return app.forceTerminate()
    }
    
    private func findRunningApp(nameOrBundleId: String) -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        return runningApps.first { app in
            app.bundleIdentifier?.lowercased() == nameOrBundleId.lowercased() ||
            app.localizedName?.lowercased().contains(nameOrBundleId.lowercased()) == true
        }
    }
    
    // MARK: - Screen Capture (Excluding Jarvis Window)
    
    /// Capture screen excluding Jarvis window for clean analysis
    func captureScreenExcludingJarvis() async throws -> CGImage {
        // Get all windows
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        
        // Find Jarvis window IDs to exclude
        let jarvisWindowIds = windowList
            .filter { info in
                let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
                return ownerName.contains("Jarvis") || ownerName.contains("JarvisAI")
            }
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        
        // Create window list excluding Jarvis
        let excludeSet = Set(jarvisWindowIds)
        let windowsToCapture = windowList
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
            .filter { !excludeSet.contains($0) }
        
        // Capture screen
        guard let screen = NSScreen.main else {
            throw SystemControlError.screenCaptureError("No main screen")
        }
        
        let screenRect = screen.frame
        
        // Use CGWindowListCreateImage with specific windows
        guard let image = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenBelowWindow,
            jarvisWindowIds.first ?? kCGNullWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else {
            throw SystemControlError.screenCaptureError("Failed to capture")
        }
        
        return image
    }
    
    /// Get PNG data of screen capture
    func getScreenCapturePNG() async throws -> Data {
        let image = try await captureScreenExcludingJarvis()
        
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw SystemControlError.screenCaptureError("Failed to convert to PNG")
        }
        
        return pngData
    }
}

// MARK: - Data Types

struct AppInfo: Codable {
    let name: String
    let bundleIdentifier: String
    let isActive: Bool
    let isHidden: Bool
    let processIdentifier: pid_t
}

enum SystemControlError: Error {
    case appNotFound(String)
    case accessibilityNotEnabled
    case scriptError(String)
    case screenCaptureError(String)
    case elementNotFound(String)
}
```



### 4.2 Accessibility Control Service

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/AccessibilityControlService.swift`Direct UI control via Accessibility API (no mouse/keyboard simulation):

```swift
import Foundation
import ApplicationServices
import AppKit

/// Direct UI control via Accessibility API - no mouse/keyboard simulation
actor AccessibilityControlService {
    static let shared = AccessibilityControlService()
    
    // MARK: - Permission Check
    
    func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Direct UI Control (No Mouse/Keyboard Simulation)
    
    /// Click a button by label in an application
    func clickButton(
        inApp bundleId: String,
        buttonLabel: String
    ) async throws -> Bool {
        let app = try getAppElement(bundleId: bundleId)
        
        // Find button by label
        guard let button = try findElement(
            in: app,
            role: kAXButtonRole,
            identifier: buttonLabel
        ) else {
            throw SystemControlError.elementNotFound("Button '\(buttonLabel)' not found")
        }
        
        // Perform click action directly via Accessibility API
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return result == .success
    }
    
    /// Set text in a text field
    func setText(
        inApp bundleId: String,
        fieldIdentifier: String,
        text: String
    ) async throws -> Bool {
        let app = try getAppElement(bundleId: bundleId)
        
        // Find text field
        guard let textField = try findElement(
            in: app,
            role: kAXTextFieldRole,
            identifier: fieldIdentifier
        ) else {
            throw SystemControlError.elementNotFound("Text field '\(fieldIdentifier)' not found")
        }
        
        // Set value directly via Accessibility API (no typing simulation)
        let result = AXUIElementSetAttributeValue(
            textField,
            kAXValueAttribute as CFString,
            text as CFString
        )
        
        return result == .success
    }
    
    /// Get text from a text field
    func getText(
        inApp bundleId: String,
        fieldIdentifier: String
    ) async throws -> String {
        let app = try getAppElement(bundleId: bundleId)
        
        guard let textField = try findElement(
            in: app,
            role: kAXTextFieldRole,
            identifier: fieldIdentifier
        ) else {
            throw SystemControlError.elementNotFound("Text field '\(fieldIdentifier)' not found")
        }
        
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(textField, kAXValueAttribute as CFString, &value)
        
        return value as? String ?? ""
    }
    
    /// Get all UI elements in an app (for analysis)
    func getUIHierarchy(inApp bundleId: String) async throws -> [UIElementInfo] {
        let app = try getAppElement(bundleId: bundleId)
        return try traverseElements(app, depth: 0, maxDepth: 5)
    }
    
    // MARK: - Window Control
    
    /// Bring app window to front
    func activateApp(bundleId: String) async throws -> Bool {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId }) else {
            throw SystemControlError.appNotFound(bundleId)
        }
        
        return app.activate()
    }
    
    /// Minimize app window
    func minimizeWindow(inApp bundleId: String) async throws -> Bool {
        let app = try getAppElement(bundleId: bundleId)
        
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        
        guard let windowArray = windows as? [AXUIElement],
              let firstWindow = windowArray.first else {
            throw SystemControlError.elementNotFound("No windows found")
        }
        
        let result = AXUIElementSetAttributeValue(
            firstWindow,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
        
        return result == .success
    }
    
    // MARK: - Helper Methods
    
    private func getAppElement(bundleId: String) throws -> AXUIElement {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId }) else {
            throw SystemControlError.appNotFound(bundleId)
        }
        
        return AXUIElementCreateApplication(app.processIdentifier)
    }
    
    private func findElement(
        in parent: AXUIElement,
        role: String,
        identifier: String
    ) throws -> AXUIElement? {
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &children)
        
        guard let childArray = children as? [AXUIElement] else { return nil }
        
        for child in childArray {
            // Check role
            var childRole: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole)
            
            if (childRole as? String) == role {
                // Check title/description/identifier
                var title: CFTypeRef?
                var description: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &description)
                
                let titleStr = title as? String ?? ""
                let descStr = description as? String ?? ""
                
                if titleStr.lowercased().contains(identifier.lowercased()) ||
                   descStr.lowercased().contains(identifier.lowercased()) {
                    return child
                }
            }
            
            // Recurse into children
            if let found = try findElement(in: child, role: role, identifier: identifier) {
                return found
            }
        }
        
        return nil
    }
    
    private func traverseElements(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) throws -> [UIElementInfo] {
        guard depth < maxDepth else { return [] }
        
        var result: [UIElementInfo] = []
        
        // Get element info
        var role: CFTypeRef?
        var title: CFTypeRef?
        var value: CFTypeRef?
        var position: CFTypeRef?
        var size: CFTypeRef?
        
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
        
        let info = UIElementInfo(
            role: role as? String ?? "unknown",
            title: title as? String,
            value: value as? String,
            depth: depth
        )
        result.append(info)
        
        // Get children
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        if let childArray = children as? [AXUIElement] {
            for child in childArray {
                result.append(contentsOf: try traverseElements(child, depth: depth + 1, maxDepth: maxDepth))
            }
        }
        
        return result
    }
}

struct UIElementInfo: Codable {
    let role: String
    let title: String?
    let value: String?
    let depth: Int
}
```



### 4.3 AppleScript Service

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/AppleScriptService.swift`For complex automation that Accessibility API can't do:

```swift
import Foundation
import AppKit

/// AppleScript execution for complex automation
actor AppleScriptService {
    static let shared = AppleScriptService()
    
    // MARK: - Script Execution
    
    func executeScript(_ script: String) async throws -> String {
        var error: NSDictionary?
        
        guard let appleScript = NSAppleScript(source: script) else {
            throw SystemControlError.scriptError("Invalid script")
        }
        
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw SystemControlError.scriptError(errorMessage)
        }
        
        return result.stringValue ?? ""
    }
    
    // MARK: - Predefined Actions
    
    /// Open URL in default browser
    func openURL(_ urlString: String) async throws -> String {
        let script = """
        tell application "System Events"
            open location "\(urlString)"
        end tell
        return "Opened URL: \(urlString)"
        """
        return try await executeScript(script)
    }
    
    /// Search in browser
    func searchInBrowser(query: String) async throws -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let script = """
        tell application "Safari"
            activate
            open location "https://www.google.com/search?q=\(encodedQuery)"
        end tell
        return "Searching for: \(query)"
        """
        return try await executeScript(script)
    }
    
    /// Get frontmost app name
    func getFrontmostApp() async throws -> String {
        let script = """
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
            return frontApp
        end tell
        """
        return try await executeScript(script)
    }
    
    /// Get all window names
    func getAllWindows() async throws -> String {
        let script = """
        tell application "System Events"
            set windowList to ""
            repeat with proc in (every process whose background only is false)
                set appName to name of proc
                repeat with win in (every window of proc)
                    set winName to name of win
                    set windowList to windowList & appName & ": " & winName & linefeed
                end repeat
            end repeat
            return windowList
        end tell
        """
        return try await executeScript(script)
    }
    
    /// Type text in frontmost app (only when needed, uses clipboard)
    func typeText(_ text: String) async throws -> String {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        // Set new clipboard content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Paste via AppleScript
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        return "Text entered"
        """
        let result = try await executeScript(script)
        
        // Restore clipboard after a delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
        
        return result
    }
}
```

---

## Phase 5: Permission Management

### 5.1 Permission Manager

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/FocusModePermissionManager.swift`One-time permission request flow:

```swift
import Foundation
import AppKit
import ApplicationServices
import AVFoundation

@MainActor
class FocusModePermissionManager: ObservableObject {
    static let shared = FocusModePermissionManager()
    
    @Published var accessibilityGranted: Bool = false
    @Published var screenRecordingGranted: Bool = false
    @Published var automationGranted: Bool = false
    
    var allPermissionsGranted: Bool {
        accessibilityGranted && screenRecordingGranted
    }
    
    private init() {
        checkPermissions()
    }
    
    // MARK: - Check Permissions
    
    func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        // Automation is granted per-app, check when needed
    }
    
    // MARK: - Request Permissions
    
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
```



### 5.2 Permission Setup View

**File**: `frontend/JarvisAI/JarvisAI/Views/FocusMode/PermissionSetupView.swift`One-time setup flow for all permissions:

```swift
import SwiftUI

struct PermissionSetupView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var permissionManager = FocusModePermissionManager.shared
    @State private var currentStep = 0
    
    let steps = ["Accessibility", "Screen Recording", "Complete"]
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal, 40)
            
            // Content for current step
            Group {
                switch currentStep {
                case 0:
                    AccessibilityPermissionView(
                        isGranted: permissionManager.accessibilityGranted,
                        onRequest: {
                            permissionManager.requestAccessibility()
                        },
                        onOpenSettings: {
                            permissionManager.openAccessibilitySettings()
                        }
                    )
                case 1:
                    ScreenRecordingPermissionView(
                        isGranted: permissionManager.screenRecordingGranted,
                        onRequest: {
                            permissionManager.requestScreenRecording()
                        },
                        onOpenSettings: {
                            permissionManager.openScreenRecordingSettings()
                        }
                    )
                case 2:
                    PermissionCompleteView()
                default:
                    EmptyView()
                }
            }
            
            Spacer()
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                } else {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .padding(24)
        .frame(width: 500, height: 450)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            permissionManager.checkPermissions()
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0: return permissionManager.accessibilityGranted
        case 1: return permissionManager.screenRecordingGranted
        default: return true
        }
    }
}

struct AccessibilityPermissionView: View {
    let isGranted: Bool
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "hand.raised.circle")
                .font(.system(size: 60))
                .foregroundStyle(isGranted ? .green : .blue)
            
            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Required to click buttons, enter text, and control apps without using your mouse or keyboard.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            if !isGranted {
                Button("Request Permission") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open System Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
            } else {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

struct ScreenRecordingPermissionView: View {
    let isGranted: Bool
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                .font(.system(size: 60))
                .foregroundStyle(isGranted ? .green : .blue)
            
            Text("Screen Recording Permission")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Required to see and understand what's on your screen. Jarvis will exclude itself from screenshots.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            if !isGranted {
                Button("Request Permission") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open System Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
            } else {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

struct PermissionCompleteView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("All Set!")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Jarvis now has the permissions needed to control your Mac. You can start using Focus Mode.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureCheckRow(text: "Control apps without interrupting your input")
                FeatureCheckRow(text: "See and understand your screen")
                FeatureCheckRow(text: "Open, close, and manage applications")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct FeatureCheckRow: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.body)
        }
    }
}
```

---

## Phase 6: Backend - System Control Tools

### 6.1 Focus Mode Tools

**File**: `backend/agents/focus_mode_tools.py`Tools for the AI agent to control macOS:

```python
from typing import List, Dict, Any, Optional
from langchain_core.tools import tool
from pydantic import BaseModel, Field
from core.logger import setup_logger
import httpx
import base64

logger = setup_logger(__name__)

# Frontend API base URL (the Swift app exposes these endpoints)
FRONTEND_API_BASE = "http://localhost:8081"  # Local bridge API


@tool
async def list_running_applications() -> str:
    """
    List all currently running applications on the Mac.
    
    Returns:
        A formatted list of running applications with their names and states.
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{FRONTEND_API_BASE}/system/apps/running")
            apps = response.json()
            
            if not apps:
                return "No applications are currently running."
            
            result = "## Running Applications:\n\n"
            for app in apps:
                status = "🟢 Active" if app.get("isActive") else "⚪ Background"
                result += f"- **{app['name']}** ({status})\n"
                result += f"  Bundle ID: `{app['bundleIdentifier']}`\n\n"
            
            return result
    except Exception as e:
        logger.error(f"Error listing apps: {e}")
        return f"Error listing applications: {str(e)}"


@tool
async def open_application(app_name: str) -> str:
    """
    Open an application by name or bundle identifier.
    
    Args:
        app_name: The name of the app (e.g., "Safari", "Chrome") or bundle ID
    
    Returns:
        Success or error message
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{FRONTEND_API_BASE}/system/apps/open",
                json={"app_name": app_name}
            )
            result = response.json()
            
            if result.get("success"):
                return f"✅ Successfully opened {app_name}"
            else:
                return f"❌ Failed to open {app_name}: {result.get('error', 'Unknown error')}"
    except Exception as e:
        logger.error(f"Error opening app: {e}")
        return f"Error opening application: {str(e)}"


@tool
async def close_application(app_name: str, force: bool = False) -> str:
    """
    Close or force quit an application.
    
    Args:
        app_name: The name of the app to close
        force: If True, force quit the app (use for unresponsive apps)
    
    Returns:
        Success or error message
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{FRONTEND_API_BASE}/system/apps/close",
                json={"app_name": app_name, "force": force}
            )
            result = response.json()
            
            action = "force quit" if force else "closed"
            if result.get("success"):
                return f"✅ Successfully {action} {app_name}"
            else:
                return f"❌ Failed to {action} {app_name}: {result.get('error', 'Unknown error')}"
    except Exception as e:
        logger.error(f"Error closing app: {e}")
        return f"Error closing application: {str(e)}"


@tool
async def analyze_screen(question: Optional[str] = None) -> str:
    """
    Capture and analyze the current screen content (excluding Jarvis window).
    Uses vision AI to understand what's displayed.
    
    Args:
        question: Optional specific question about the screen content
    
    Returns:
        Description of what's on the screen
    """
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Get screen capture from frontend (excludes Jarvis window)
            response = await client.get(f"{FRONTEND_API_BASE}/system/screen/capture")
            capture_data = response.json()
            
            if not capture_data.get("success"):
                return f"Error capturing screen: {capture_data.get('error')}"
            
            # Analyze with GPT-4V
            from core.openai_client import openai_client
            
            prompt = question or "Describe what you see on this screen. What applications are visible? What is the user currently doing?"
            
            messages = [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": f"You are analyzing a macOS screen. The Jarvis assistant window has been excluded from this capture, so you're seeing only the user's other applications and content.\n\nQuestion: {prompt}"
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/png;base64,{capture_data['image_base64']}"
                            }
                        }
                    ]
                }
            ]
            
            response = await openai_client.client.chat.completions.create(
                model="gpt-4o",
                messages=messages,
                max_completion_tokens=1000
            )
            
            return f"## Screen Analysis:\n\n{response.choices[0].message.content}"
    except Exception as e:
        logger.error(f"Error analyzing screen: {e}")
        return f"Error analyzing screen: {str(e)}"


@tool
async def click_button(app_name: str, button_label: str) -> str:
    """
    Click a button in an application using the Accessibility API.
    This does NOT simulate mouse clicks - it directly triggers the button action.
    
    Args:
        app_name: The application containing the button
        button_label: The label/text of the button to click
    
    Returns:
        Success or error message
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{FRONTEND_API_BASE}/system/ui/click",
                json={"app_name": app_name, "button_label": button_label}
            )
            result = response.json()
            
            if result.get("success"):
                return f"✅ Clicked button '{button_label}' in {app_name}"
            else:
                return f"❌ Could not click button: {result.get('error', 'Button not found')}"
    except Exception as e:
        logger.error(f"Error clicking button: {e}")
        return f"Error clicking button: {str(e)}"


@tool
async def enter_text(app_name: str, field_identifier: str, text: str) -> str:
    """
    Enter text into a text field using the Accessibility API.
    This does NOT simulate keyboard input - it directly sets the field value.
    
    Args:
        app_name: The application containing the text field
        field_identifier: The identifier/label of the text field
        text: The text to enter
    
    Returns:
        Success or error message
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{FRONTEND_API_BASE}/system/ui/setText",
                json={
                    "app_name": app_name,
                    "field_identifier": field_identifier,
                    "text": text
                }
            )
            result = response.json()
            
            if result.get("success"):
                return f"✅ Entered text into '{field_identifier}' in {app_name}"
            else:
                return f"❌ Could not enter text: {result.get('error', 'Field not found')}"
    except Exception as e:
        logger.error(f"Error entering text: {e}")
        return f"Error entering text: {str(e)}"


@tool
async def execute_applescript(script_description: str) -> str:
    """
    Execute an AppleScript command for complex automation tasks.
    Use this for actions that can't be done via the Accessibility API.
    
    Args:
        script_description: Description of what the script should do
    
    Returns:
        Result of the script execution
    """
    # Map descriptions to safe, predefined scripts
    safe_scripts = {
        "open_url": "openURL",
        "search_web": "searchWeb",
        "get_frontmost_app": "getFrontmostApp",
        "get_all_windows": "getAllWindows",
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{FRONTEND_API_BASE}/system/script/execute",
                json={"script_description": script_description}
            )
            result = response.json()
            
            if result.get("success"):
                return f"✅ Script executed:\n{result.get('output', '')}"
            else:
                return f"❌ Script error: {result.get('error', 'Unknown error')}"
    except Exception as e:
        logger.error(f"Error executing script: {e}")
        return f"Error executing script: {str(e)}"


@tool
async def get_ui_hierarchy(app_name: str) -> str:
    """
    Get the UI element hierarchy of an application.
    Useful for understanding what buttons, fields, and controls are available.
    
    Args:
        app_name: The application to analyze
    
    Returns:
        Structured list of UI elements
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{FRONTEND_API_BASE}/system/ui/hierarchy",
                params={"app_name": app_name}
            )
            result = response.json()
            
            if not result.get("elements"):
                return f"No UI elements found for {app_name}"
            
            output = f"## UI Hierarchy for {app_name}:\n\n"
            for elem in result["elements"][:50]:  # Limit to 50 elements
                indent = "  " * elem.get("depth", 0)
                role = elem.get("role", "unknown")
                title = elem.get("title", "")
                output += f"{indent}- [{role}] {title}\n"
            
            return output
    except Exception as e:
        logger.error(f"Error getting UI hierarchy: {e}")
        return f"Error getting UI hierarchy: {str(e)}"


def get_focus_mode_tools():
    """Return list of Focus Mode tools for the agent."""
    return [
        list_running_applications,
        open_application,
        close_application,
        analyze_screen,
        click_button,
        enter_text,
        execute_applescript,
        get_ui_hierarchy,
    ]
```



### 6.2 Focus Mode API Routes

**File**: `backend/api/routes/focus_mode.py`API endpoints for Focus Mode:

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from core.logger import setup_logger
from agents.focus_mode_tools import get_focus_mode_tools

logger = setup_logger(__name__)
router = APIRouter(prefix="/focus-mode", tags=["focus-mode"])


class FocusModeActionRequest(BaseModel):
    message: str
    include_screen_analysis: bool = False


class FocusModeActionResponse(BaseModel):
    response: str
    actions_taken: List[str] = []
    success: bool = True


@router.post("/action", response_model=FocusModeActionResponse)
async def execute_focus_mode_action(request: FocusModeActionRequest):
    """
    Execute a Focus Mode action based on user message.
    The agent will determine what system actions to take.
    """
    try:
        from agents.graph import create_focus_mode_graph
        
        # Create Focus Mode graph with system control tools
        graph = create_focus_mode_graph()
        
        # Prepare input
        inputs = {
            "messages": [{"role": "user", "content": request.message}],
            "include_screen": request.include_screen_analysis
        }
        
        # Execute agent
        result = await graph.ainvoke(inputs)
        
        return FocusModeActionResponse(
            response=result.get("response", ""),
            actions_taken=result.get("actions", []),
            success=True
        )
    except Exception as e:
        logger.error(f"Focus mode action error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/status")
async def get_focus_mode_status():
    """Get current Focus Mode status."""
    return {
        "active": True,
        "permissions": {
            "accessibility": True,
            "screen_recording": True
        }
    }
```



### 6.3 Focus Mode Agent Graph

**File**: `backend/agents/graph.py` (add function)Add Focus Mode graph with system control capabilities:

```python
def create_focus_mode_graph():
    """Create a LangGraph agent with Focus Mode (system control) capabilities."""
    from langchain_openai import ChatOpenAI
    from langgraph.prebuilt import create_react_agent
    from agents.focus_mode_tools import get_focus_mode_tools
    
    # Use GPT-4o for better reasoning about system control
    llm = ChatOpenAI(
        model="gpt-4o",
        temperature=0,
        streaming=True
    )
    
    # System prompt for Focus Mode
    system_message = """You are Jarvis in Focus Mode - an AI assistant with DIRECT CONTROL over macOS.

You have the following capabilities:

1. **App Management**
    - List all running applications
    - Open any application by name
    - Close or force quit applications

2. **Screen Understanding**
    - Capture and analyze what's on screen (your window is excluded)
    - Understand context and help users with what they're working on

3. **Direct UI Control** (via Accessibility API, NOT mouse/keyboard simulation)
    - Click buttons in any app
    - Enter text into fields
    - Read UI element values

4. **Automation** (via AppleScript)
    - Complex multi-step automation
    - System-level commands

IMPORTANT RULES:
- You control the Mac DIRECTLY without simulating mouse/keyboard - the user can continue using their input devices
- When capturing the screen, your Jarvis window is automatically excluded
- Before clicking buttons or entering text, use get_ui_hierarchy to understand the available UI elements
- Use analyze_screen to understand what the user is seeing before taking actions
- Always confirm before taking destructive actions (like force quitting apps)

When the user asks you to do something:
1. Understand the request
2. Use the appropriate tools
3. Report what you did and the result

Examples:
- "Open Safari" → Use open_application("Safari")
- "What's on my screen?" → Use analyze_screen()
- "Close all browsers" → List apps, identify browsers, close each one
- "List running apps" → Use list_running_applications()
"""

    # Get tools
    tools = get_focus_mode_tools()
    
    # Create agent
    agent = create_react_agent(
        llm,
        tools,
        state_modifier=system_message
    )
    
    return agent
```

---

## Phase 7: Frontend-Backend Bridge API

### 7.1 Local Bridge Server

**File**: `frontend/JarvisAI/JarvisAI/Services/FocusMode/LocalBridgeServer.swift`Local HTTP server that exposes system control to backend:

```swift
import Foundation
import Swifter

/// Local HTTP server that bridges backend AI to macOS system controls
class LocalBridgeServer {
    static let shared = LocalBridgeServer()
    
    private var server: HttpServer?
    private let port: UInt16 = 8081
    
    private init() {}
    
    func start() {
        server = HttpServer()
        
        setupRoutes()
        
        do {
            try server?.start(port, forceIPv4: true)
            print("Bridge server running on port \(port)")
        } catch {
            print("Failed to start bridge server: \(error)")
        }
    }
    
    func stop() {
        server?.stop()
    }
    
    private func setupRoutes() {
        guard let server = server else { return }
        
        // List running apps
        server.GET["/system/apps/running"] = { _ in
            Task {
                let apps = await SystemControlService.shared.listRunningApps()
                return .ok(.json(apps))
            }
            // Synchronous fallback
            return .ok(.json([]))
        }
        
        // Open app
        server.POST["/system/apps/open"] = { request in
            let json = try? JSONDecoder().decode(
                OpenAppRequest.self,
                from: Data(request.body)
            )
            guard let appName = json?.app_name else {
                return .badRequest(.text("Missing app_name"))
            }
            
            Task {
                do {
                    let success = try await SystemControlService.shared.openApp(
                        nameOrBundleId: appName
                    )
                    return .ok(.json(["success": success]))
                } catch {
                    return .ok(.json(["success": false, "error": error.localizedDescription]))
                }
            }
            return .accepted
        }
        
        // Close app
        server.POST["/system/apps/close"] = { request in
            let json = try? JSONDecoder().decode(
                CloseAppRequest.self,
                from: Data(request.body)
            )
            guard let appName = json?.app_name else {
                return .badRequest(.text("Missing app_name"))
            }
            
            Task {
                do {
                    let success = try await SystemControlService.shared.closeApp(
                        nameOrBundleId: appName
                    )
                    return .ok(.json(["success": success]))
                } catch {
                    return .ok(.json(["success": false, "error": error.localizedDescription]))
                }
            }
            return .accepted
        }
        
        // Screen capture
        server.GET["/system/screen/capture"] = { _ in
            Task {
                do {
                    let imageData = try await SystemControlService.shared.getScreenCapturePNG()
                    let base64 = imageData.base64EncodedString()
                    return .ok(.json(["success": true, "image_base64": base64]))
                } catch {
                    return .ok(.json(["success": false, "error": error.localizedDescription]))
                }
            }
            return .accepted
        }
        
        // Click UI element
        server.POST["/system/ui/click"] = { request in
            let json = try? JSONDecoder().decode(
                ClickRequest.self,
                from: Data(request.body)
            )
            guard let appName = json?.app_name,
                  let buttonLabel = json?.button_label else {
                return .badRequest(.text("Missing parameters"))
            }
            
            Task {
                do {
                    let success = try await AccessibilityControlService.shared.clickButton(
                        inApp: appName,
                        buttonLabel: buttonLabel
                    )
                    return .ok(.json(["success": success]))
                } catch {
                    return .ok(.json(["success": false, "error": error.localizedDescription]))
                }
            }
            return .accepted
        }
        
        // Set text in field
        server.POST["/system/ui/setText"] = { request in
            let json = try? JSONDecoder().decode(
                SetTextRequest.self,
                from: Data(request.body)
            )
            guard let appName = json?.app_name,
                  let fieldId = json?.field_identifier,
                  let text = json?.text else {
                return .badRequest(.text("Missing parameters"))
            }
            
            Task {
                do {
                    let success = try await AccessibilityControlService.shared.setText(
                        inApp: appName,
                        fieldIdentifier: fieldId,
                        text: text
                    )
                    return .ok(.json(["success": success]))
                } catch {
                    return .ok(.json(["success": false, "error": error.localizedDescription]))
                }
            }
            return .accepted
        }
        
        // Get UI hierarchy
        server.GET["/system/ui/hierarchy"] = { request in
            guard let appName = request.queryParams.first(where: { $0.0 == "app_name" })?.1 else {
                return .badRequest(.text("Missing app_name"))
            }
            
            Task {
                do {
                    let elements = try await AccessibilityControlService.shared.getUIHierarchy(
                        inApp: appName
                    )
                    return .ok(.json(["elements": elements]))
                } catch {
                    return .ok(.json(["elements": [], "error": error.localizedDescription]))
                }
            }
            return .accepted
        }
    }
}

// Request models
struct OpenAppRequest: Codable {
    let app_name: String
}

struct CloseAppRequest: Codable {
    let app_name: String
    let force: Bool?
}

struct ClickRequest: Codable {
    let app_name: String
    let button_label: String
}

struct SetTextRequest: Codable {
    let app_name: String
    let field_identifier: String
    let text: String
}
```

---

## Phase 8: Implementation Order

### Week 1: Foundation

1. ✅ Tab navigation with Focus Mode tab
2. ✅ Focus Mode activation view
3. ✅ Permission manager and setup flow
4. ✅ Request all permissions via system dialogs

### Week 2: Menu Bar & Window

1. ✅ Dynamic Island pill in menu bar
2. ✅ Floating window (NSPanel, always on top)
3. ✅ Expand/collapse animations
4. ✅ Floating chat view with all existing features

### Week 3: System Control

1. ✅ SystemControlService (app management)
2. ✅ AccessibilityControlService (direct UI control)
3. ✅ AppleScriptService (complex automation)
4. ✅ Screen capture excluding Jarvis window

### Week 4: Backend Integration

1. ✅ Focus Mode tools for LangGraph agent
2. ✅ Focus Mode API routes
3. ✅ Local bridge server
4. ✅ Agent system message for Focus Mode

### Week 5: Polish & Testing

1. Testing with various apps
2. Error handling improvements
3. UI polish with Liquid Glass
4. Documentation

---

## Example User Flows

### Example 1: "Open browser and search for ChatGPT"

```javascript
User: Open browser and search for ChatGPT

Agent thinking:
1. Need to open a browser (Safari or Chrome)
2. Then navigate to search

Actions:
1. open_application("Safari")
2. analyze_screen() - to see Safari is open
3. execute_applescript("search_web: ChatGPT")

Response: ✅ Opened Safari and searched for ChatGPT
```



### Example 2: "List all open apps"

```javascript
User: List all open apps right now

Agent actions:
1. list_running_applications()

Response:
## Running Applications:

- **Safari** (🟢 Active)
- **Finder** (⚪ Background)
- **Messages** (⚪ Background)
- **Spotify** (⚪ Background)
```



### Example 3: "Close Safari and Spotify"

```javascript
User: Close Safari and Spotify

Agent actions:
1. close_application("Safari")
2. close_application("Spotify")

Response: ✅ Closed Safari and Spotify
```



### Example 4: "Explain what's on my screen"

```javascript
User: Explain what's on my screen

Agent actions:
1. analyze_screen()

Response:
## Screen Analysis:

I can see you have:
- **VS Code** in the center with a Python file open
- **Terminal** on the right showing some command output
- **Chrome** with GitHub in a tab (partially visible)

It looks like you're working on a coding project.
```

---

## Files to Create/Modify

### Frontend (SwiftUI)

```javascript
frontend/JarvisAI/JarvisAI/
├── Views/
│   └── FocusMode/
│       ├── FocusModeTabView.swift          (NEW)
│       ├── FocusModeActivationView.swift   (NEW)
│       ├── FloatingChatView.swift          (NEW)
│       ├── DynamicIslandPillView.swift     (NEW)
│       └── PermissionSetupView.swift       (NEW)
├── Services/
│   └── FocusMode/
│       ├── FocusModeManager.swift          (NEW)
│       ├── FloatingWindowController.swift  (NEW)
│       ├── SystemControlService.swift      (NEW)
│       ├── AccessibilityControlService.swift (NEW)
│       ├── AppleScriptService.swift        (NEW)
│       ├── FocusModePermissionManager.swift (NEW)
│       └── LocalBridgeServer.swift         (NEW)
├── ViewModels/
│   └── FocusChatViewModel.swift            (NEW)
├── ContentView.swift                       (MODIFY - add tabs)
└── JarvisAIApp.swift                       (MODIFY - add bridge server start)
```



### Backend (Python)

```javascript
backend/
├── agents/
│   ├── focus_mode_tools.py                 (NEW)
│   └── graph.py                            (MODIFY - add focus mode graph)
├── api/
│   └── routes/
│       └── focus_mode.py                   (NEW)
└── main.py                                 (MODIFY - add focus mode routes)
```

---

## Key Technical Notes

1. **Always On Top**: Use `NSPanel` with `.floating` level and `hidesOnDeactivate = false`
2. **Screen Capture Excluding Jarvis**: Filter windows by owner name before capture
3. **Direct UI Control**: Use `AXUIElementPerformAction` and `AXUIElementSetAttributeValue` - NO CGEvent simulation
4. **Non-Blocking**: All system control runs async, doesn't interrupt user input
5. **Permissions**: One-time setup, stored in system preferences