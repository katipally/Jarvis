import SwiftUI

@main
struct JarvisAIApp: App {
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        // Main Chat Window
        WindowGroup {
            ContentView()
                .environmentObject(appState)
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
                Button("Chat Mode") {
                    appState.currentMode = .chat
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Focus Mode") {
                    appState.currentMode = .focus
                    appState.showFocusPanel = true
                }
                .keyboardShortcut("2", modifiers: .command)
                
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
        
        // Menu Bar Extra for Focus Mode
        MenuBarExtra {
            FocusPanelView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.currentMode == .focus ? "sparkles" : "brain.head.profile")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        Settings {
            SettingsWindowView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentMode: AppMode = .chat
    @Published var showFocusPanel: Bool = false
    
    private init() {}
}

enum AppMode: String, CaseIterable {
    case chat = "Chat"
    case focus = "Focus"
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .focus: return "sparkles"
        }
    }
}

// MARK: - Settings Window View (wrapper for SettingsView)
struct SettingsWindowView: View {
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}
