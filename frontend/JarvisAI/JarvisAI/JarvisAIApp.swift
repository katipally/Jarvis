import SwiftUI
import AppKit

@main
struct JarvisAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Main Chat Window
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: NSNotification.Name("NewChat"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleSidebar"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            
            CommandMenu("Mode") {
                Button("Open Focus Mode") {
                    AppDelegate.shared?.openFocusMode()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button("Open Ray Mode") {
                    AppDelegate.shared?.openRayMode()
                }
                .keyboardShortcut(.space, modifiers: [.option])
                
                Button("Open Chat Window") {
                    AppDelegate.shared?.openMainWindow()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Settings...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Conversation") {
                Button("Toggle Input Mode") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleInputMode"), object: nil)
                }
                .keyboardShortcut("m", modifiers: [.control, .option])  // Ctrl+Opt+M for Mode
                
                Button("Calibrate Microphone") {
                    NotificationCenter.default.post(name: NSNotification.Name("StartCalibration"), object: nil)
                }
                .keyboardShortcut("b", modifiers: [.control, .option])  // Ctrl+Opt+B for caliB
                
                Button("Stop Speaking") {
                    NotificationCenter.default.post(name: NSNotification.Name("StopSpeaking"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.control, .option])  // Ctrl+Opt+S for Stop
                
                Divider()
                
                Button("Clear History") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearConversation"), object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])  // Cmd+Shift+Delete
                
                Button("Push to Talk") {
                    NotificationCenter.default.post(name: NSNotification.Name("PushToTalk"), object: nil)
                }
                .keyboardShortcut("r", modifiers: [.control, .option])  // Ctrl+Opt+R for Record
                
                Divider()
                
                Button("Voice Settings") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenVoiceSettings"), object: nil)
                }
                .keyboardShortcut("v", modifiers: [.control, .option])  // Ctrl+Opt+V for Voice
            }
            
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Focus Input") {
                    NotificationCenter.default.post(name: NSNotification.Name("FocusInput"), object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)  // Cmd+L for Line/Focus
            }
        }
        
        // Settings window
        Settings {
            SettingsWindowView()
        }
    }
}

// MARK: - App Delegate for Menu Bar
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var statusItem: NSStatusItem?
    var focusPanel: NSPanel?
    var rayPanel: NSPanel?
    var eventMonitor: Any?
    var rayClickMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMenuBar()
        setupFocusPanel()
        setupRayPanel()
        setupNotifications()
        initializeMacControlServices()
    }
    
    private func initializeMacControlServices() {
        // Initialize workspace monitoring for app lifecycle events
        Task { @MainActor in
            WorkspaceMonitor.shared.startMonitoring()
            SystemNotificationService.shared.startListening()
            
            // Register default Jarvis hotkeys
            GlobalHotkeyService.shared.registerDefaultJarvisHotkeys(
                onActivate: { [weak self] in
                    self?.toggleFocusPanel()
                },
                onFocusMode: { [weak self] in
                    self?.openFocusMode()
                },
                onQuickCapture: {
                    NotificationCenter.default.post(name: NSNotification.Name("QuickCapture"), object: nil)
                },
                onVoiceCommand: {
                    NotificationCenter.default.post(name: NSNotification.Name("PushToTalk"), object: nil)
                },
                onRayMode: { [weak self] in
                    self?.openRayMode()
                }
            )
        }
    }
    
    private func setupMenuBar() {
        // Create status bar item with fixed width for better visibility
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Create a custom attributed string for "J" with proper styling
            let image = createJarvisMenuBarIcon()
            button.image = image
            button.image?.isTemplate = true
            button.action = #selector(toggleFocusPanel)
            button.target = self
            
            // Add tooltip
            button.toolTip = "Jarvis AI - Click to open Focus Mode"
        }
    }
    
    private func setupFocusPanel() {
        // Create floating panel that accepts keyboard input
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure panel to float above all apps AND accept keyboard input
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false  // Don't hide when switching apps
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        
        // CRITICAL: Allow panel to become key window for keyboard input
        panel.becomesKeyOnlyIfNeeded = false
        
        // Set appearance
        panel.appearance = NSAppearance(named: .vibrantDark)
        
        // Hide the traffic light buttons (close, minimize, zoom)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Add SwiftUI content - Unified Panel with Focus/Conversation modes
        let hostingController = NSHostingController(rootView: UnifiedPanelView())
        hostingController.view.layer?.cornerRadius = 12
        hostingController.view.layer?.masksToBounds = true
        hostingController.view.wantsLayer = true
        panel.contentViewController = hostingController
        
        // Position near menu bar on the right side
        positionPanelNearMenuBar(panel)
        
        self.focusPanel = panel
    }
    
    // MARK: - Ray Panel Setup (Spotlight-style, stable like Focus Mode)
    private func setupRayPanel() {
        // Create a Spotlight-style centered panel using custom class for keyboard input
        let panelWidth: CGFloat = 680
        let panelHeight: CGFloat = 480
        
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Configure as stable top-level panel (like Focus Mode)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .vibrantDark)
        
        // Add SwiftUI content
        let hostingController = NSHostingController(rootView: RayPanelView(onDismiss: { [weak self] in
            self?.closeRayPanel()
        }))
        hostingController.view.layer?.cornerRadius = 16
        hostingController.view.layer?.masksToBounds = true
        hostingController.view.wantsLayer = true
        panel.contentViewController = hostingController
        
        // Center on screen
        positionRayPanelCenter(panel)
        
        self.rayPanel = panel
    }
    
    private func positionRayPanelCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.frame
        let panelFrame = panel.frame
        
        // Position in upper-center of screen (like Spotlight)
        let x = (screenFrame.width - panelFrame.width) / 2
        let y = screenFrame.height * 0.65 - panelFrame.height / 2
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    @objc func toggleRayPanel() {
        guard let panel = rayPanel else { return }
        
        if panel.isVisible {
            closeRayPanel()
        } else {
            openRayPanel()
        }
    }
    
    private func openRayPanel() {
        guard let panel = rayPanel else { return }
        
        // Prevent double-open
        guard !panel.isVisible else {
            panel.makeKey()
            return
        }
        
        // Close focus panel if open (clean state transition)
        if focusPanel?.isVisible == true {
            focusPanel?.orderOut(nil)
        }
        
        // Hide main window (like Focus mode does)
        for window in NSApp.windows {
            if window.isVisible && window.canBecomeMain && isMainChatWindow(window) {
                mainWindowRef = window
                window.orderOut(nil)
            }
        }
        
        // Activate app to receive keyboard input
        NSApp.activate(ignoringOtherApps: true)
        
        // Position and show
        positionRayPanelCenter(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        
        // Focus the content view for keyboard input
        DispatchQueue.main.async {
            panel.makeFirstResponder(panel.contentView)
        }
        
        // Notify view to focus search field and reset state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: NSNotification.Name("RayPanelOpened"), object: nil)
        }
    }
    
    func closeRayPanel() {
        guard rayPanel?.isVisible == true else { return }
        
        // Notify view to clear state first
        NotificationCenter.default.post(name: NSNotification.Name("RayPanelClosed"), object: nil)
        
        // Close panel
        rayPanel?.orderOut(nil)
        
        // Restore main window
        DispatchQueue.main.async { [weak self] in
            if let mainWindow = self?.mainWindowRef {
                mainWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func positionPanelNearMenuBar(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 520
        
        // Position in top-right corner, below menu bar
        let x = screenFrame.maxX - panelWidth - 20
        let y = screenFrame.maxY - panelHeight - 10
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func createJarvisMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw circle background
            let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor.labelColor.withAlphaComponent(0.9).setFill()
            circlePath.fill()
            
            // Draw "J" letter
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.windowBackgroundColor,
                .paragraphStyle: paragraphStyle
            ]
            
            let string = "J"
            let stringSize = string.size(withAttributes: attributes)
            let stringRect = NSRect(
                x: (rect.width - stringSize.width) / 2,
                y: (rect.height - stringSize.height) / 2 + 0.5,
                width: stringSize.width,
                height: stringSize.height
            )
            string.draw(in: stringRect, withAttributes: attributes)
            
            return true
        }
        
        image.isTemplate = true
        return image
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenFocusMode),
            name: NSNotification.Name("OpenFocusMode"),
            object: nil
        )
    }
    
    @objc func toggleFocusPanel() {
        guard let panel = focusPanel else { return }
        
        if panel.isVisible {
            closeFocusPanel()
        } else {
            openFocusPanel()
        }
    }
    
    // Track the main window for reliable restoration
    private var mainWindowRef: NSWindow?
    
    private func openFocusPanel() {
        guard let panel = focusPanel else { return }
        
        // Close Ray panel if open (clean mode transition)
        if rayPanel?.isVisible == true {
            rayPanel?.orderOut(nil)
            NotificationCenter.default.post(name: NSNotification.Name("RayPanelClosed"), object: nil)
        }
        
        // Find and store reference to main chat window, then hide it completely
        for window in NSApp.windows {
            if window.isVisible && window.canBecomeMain && isMainChatWindow(window) {
                mainWindowRef = window
                // Use orderOut instead of miniaturize for cleaner transition
                window.orderOut(nil)
            }
        }
        
        // Activate app
        NSApp.activate(ignoringOtherApps: true)
        
        // Position and show the floating panel
        positionPanelNearMenuBar(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }
    
    func closeFocusPanel() {
        focusPanel?.orderOut(nil)
        
        // Restore main window when focus panel closes
        if let mainWindow = mainWindowRef {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func handleOpenFocusMode() {
        if let panel = focusPanel, !panel.isVisible {
            openFocusPanel()
        }
    }
    
    func openFocusMode() {
        // Show panel if not already visible
        if let panel = focusPanel, !panel.isVisible {
            openFocusPanel()
        }
    }
    
    func openRayMode() {
        // Toggle the standalone Ray panel
        toggleRayPanel()
    }
    
    func openMainWindow() {
        // Close focus panel first
        closeFocusPanel()
        
        // Close ray panel if open
        if rayPanel?.isVisible == true {
            rayPanel?.orderOut(nil)
            NotificationCenter.default.post(name: NSNotification.Name("RayPanelClosed"), object: nil)
        }
        
        // Activate app
        NSApp.activate(ignoringOtherApps: true)
        
        // First try to restore the tracked main window
        if let mainWindow = mainWindowRef {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Fallback: find any main chat window
        for window in NSApp.windows {
            if isMainChatWindow(window) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                mainWindowRef = window
                return
            }
        }
        
        // If no window found, try to deminiaturize any minimized window that could be main
        for window in NSApp.windows {
            if window.canBecomeMain && window.isMiniaturized {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
                mainWindowRef = window
                return
            }
        }
    }
    
    /// Check if window is the main chat window (not focus panel, ray panel, settings, or menu bar item)
    private func isMainChatWindow(_ window: NSWindow) -> Bool {
        // Exclude focus panel
        if window == focusPanel {
            return false
        }
        
        // Exclude ray panel
        if window == rayPanel {
            return false
        }
        
        // Exclude tiny windows (menu bar, status items)
        if window.frame.width < 200 || window.frame.height < 200 {
            return false
        }
        
        // Must be able to become main window
        guard window.canBecomeMain else { return false }
        
        // Exclude windows with "Item" in title (menu bar items)
        let title = window.title
        if title.contains("Item") {
            return false
        }
        
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let monitor = rayClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Custom Panel that accepts keyboard input
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // Handle Escape to close
        if event.keyCode == 53 {
            AppDelegate.shared?.closeRayPanel()
            return
        }
        super.keyDown(with: event)
    }
}

