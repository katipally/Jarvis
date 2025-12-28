import SwiftUI

@main
struct JarvisAIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 750)
        .commands {
            // Replace default New
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: NSNotification.Name("NewChat"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            // Sidebar toggle
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleSidebar"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            
            // Edit menu additions
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
            SettingsView(viewModel: ChatViewModel())
        }
    }
}
