import SwiftUI

struct MessagesListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    let containerWidth: CGFloat
    
    private var horizontalPadding: CGFloat {
        if containerWidth > 1200 { return (containerWidth - 900) / 2 }
        else if containerWidth > 900 { return (containerWidth - 750) / 2 }
        else if containerWidth > 700 { return 40 }
        else { return 16 }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages.filter { $0.role != .system }) { message in
                        MessageBubbleView(
                            message: message,
                            viewModel: viewModel,
                            isInputFocused: $isInputFocused
                        )
                        .id(message.id)
                    }
                    
                    if viewModel.isLoading && viewModel.messages.last?.role == .user {
                        TypingIndicatorView()
                            .id("typing")
                    }
                    
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
            }
            .scrollIndicators(.automatic)
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isLoading) { _ in
                scrollToBottom(proxy)
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if viewModel.isLoading {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let lastId = viewModel.messages.filter({ $0.role != .system }).last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

struct TypingIndicatorView: View {
    @State private var animate = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(iMessageColors.received(for: colorScheme))
                    .liquidGlass(opacity: 0.6, cornerRadius: 15)
            )
            
            Spacer()
        }
        .padding(.leading, 4)
        .onAppear { animate = true }
    }
}
