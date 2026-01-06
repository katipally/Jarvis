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
                // Token count and Focus mode button - consistent styling
                HStack(spacing: 8) {
                    // Token counter pill
                    if viewModel.currentTokenCount > 0 || viewModel.isLoading || viewModel.totalTokensUsed > 0 {
                        HStack(spacing: 5) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 9))
                            }
                            Text("\(viewModel.currentTokenCount > 0 ? viewModel.currentTokenCount : viewModel.totalTokensUsed)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                    }
                    
                    // Focus Mode button - matching style
                    Button(action: openFocusMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.compress.vertical")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Focus Mode (⇧⌘F)")
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
    
    private func openFocusMode() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenFocusMode"), object: nil)
    }
}
