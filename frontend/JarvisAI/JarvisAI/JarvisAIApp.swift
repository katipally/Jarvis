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
            
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Focus Input") {
                    NotificationCenter.default.post(name: NSNotification.Name("FocusInput"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
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
    var popover: NSPopover?
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMenuBar()
        setupNotifications()
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
        
        // Create popover with Control Center style
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 380, height: 520)
        popover?.behavior = .transient
        popover?.animates = true
        
        // Use appearance matching system
        popover?.appearance = NSAppearance(named: .vibrantDark)
        
        let hostingController = NSHostingController(rootView: FocusPanelView())
        hostingController.view.layer?.cornerRadius = 12
        popover?.contentViewController = hostingController
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
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            closeFocusPanel()
        } else {
            openFocusPanel(relativeTo: button)
        }
    }
    
    // Track the main window for reliable restoration
    private var mainWindowRef: NSWindow?
    
    private func openFocusPanel(relativeTo button: NSStatusBarButton) {
        guard let popover = popover else { return }
        
        // Find and store reference to main chat window before minimizing
        for window in NSApp.windows {
            if window.isVisible && window.canBecomeMain && isMainChatWindow(window) {
                mainWindowRef = window
                window.miniaturize(nil)
            }
        }
        
        // Show popover below the menu bar button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Make popover key window for immediate interaction
        popover.contentViewController?.view.window?.makeKey()
        
        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                // Check if click is outside popover
                if let popoverWindow = popover.contentViewController?.view.window {
                    let clickLocation = event.locationInWindow
                    if !popoverWindow.frame.contains(NSEvent.mouseLocation) {
                        self?.closeFocusPanel()
                    }
                }
            }
        }
    }
    
    private func closeFocusPanel() {
        popover?.performClose(nil)
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
    
    @objc func handleOpenFocusMode() {
        guard let button = statusItem?.button else { return }
        
        if let popover = popover, !popover.isShown {
            openFocusPanel(relativeTo: button)
        }
    }
    
    func openFocusMode() {
        guard let button = statusItem?.button else { return }
        
        // Close if already open
        if let popover = popover, popover.isShown {
            return
        }
        
        openFocusPanel(relativeTo: button)
    }
    
    func openMainWindow() {
        // Close focus panel first
        closeFocusPanel()
        
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
    
    /// Check if window is the main chat window (not popover, settings, or menu bar item)
    private func isMainChatWindow(_ window: NSWindow) -> Bool {
        // Exclude popover windows
        if window == popover?.contentViewController?.view.window {
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
    }
}

// MARK: - Settings Window View
struct SettingsWindowView: View {
    @ObservedObject private var viewModel = SharedChatViewModel.shared.viewModel
    
    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}
