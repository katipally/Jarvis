import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MacOS26Materials.chatBackground
                
                VStack(spacing: 0) {
                    if viewModel.messages.isEmpty {
                        EmptyStateView(viewModel: viewModel, isInputFocused: $isInputFocused)
                    } else {
                        MessagesListView(
                            viewModel: viewModel,
                            isInputFocused: $isInputFocused,
                            containerWidth: geometry.size.width
                        )
                    }
                }
                
                // iMessage-style Bottom Input Area
                VStack {
                    Spacer()
                    FloatingInputBar(viewModel: viewModel, isInputFocused: $isInputFocused)
                        .padding(.horizontal, calculateHorizontalPadding(for: geometry.size.width))
                        .padding(.bottom, 24)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Only show token count when active
                if viewModel.currentTokenCount > 0 || viewModel.isLoading {
                    HStack(spacing: 4) {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                        Text("\(viewModel.currentTokenCount) tokens")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .navigationTitle(viewModel.currentConversationId != nil ?
            viewModel.conversations.first(where: { $0.id == viewModel.currentConversationId })?.title ?? "Chat" : "New Chat")
    }
    
    private func calculateHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width > 1200 { return (width - 900) / 2 }
        else if width > 900 { return (width - 750) / 2 }
        else if width > 700 { return 40 }
        else { return 16 }
    }
}
