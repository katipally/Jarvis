import SwiftUI

// MARK: - Main Content View (Chat Window)
struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel, showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 350)
                .background(MacOS26Materials.sidebar)
        } detail: {
            ChatDetailView(viewModel: viewModel, isInputFocused: $isInputFocused)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 700)
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .preferredColorScheme(appTheme == .system ? nil : (appTheme == .dark ? .dark : .light))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewChat"))) { _ in
            DispatchQueue.main.async {
                viewModel.startNewChat()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSidebar"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusInput"))) { _ in
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AskJarvis"))) { notification in
            if let prompt = notification.userInfo?["prompt"] as? String {
                viewModel.inputText = prompt
                isInputFocused = true
                Task {
                    await viewModel.sendMessage()
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("Dismiss") { viewModel.dismissError() }
            if let _ = viewModel.error {
                Button("Retry") {
                    viewModel.dismissError()
                    if let lastError = viewModel.messages.last, lastError.isError {
                        Task { await viewModel.retryFailedMessage(lastError) }
                    }
                }
            }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .frame(width: 1100, height: 750)
}
