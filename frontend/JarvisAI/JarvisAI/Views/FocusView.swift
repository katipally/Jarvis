import SwiftUI
import MarkdownUI

/// FocusView - Legacy full-window focus mode
/// This view provides a windowed focus experience (kept for compatibility)
/// The primary Focus mode is now handled by FocusPanelView in the menu bar
struct FocusView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    init(viewModel: ChatViewModel? = nil) {
        self.viewModel = viewModel ?? SharedChatViewModel.shared.viewModel
    }
    
    var body: some View {
        // Simply embed the FocusPanelView content in a larger frame
        FocusPanelView(viewModel: viewModel)
            .frame(minWidth: 500, minHeight: 500)
    }
}

// MARK: - Preview
#Preview {
    FocusView()
        .frame(width: 700, height: 600)
        .preferredColorScheme(.dark)
}
