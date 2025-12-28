import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // New Chat Button
            newChatButton
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 12)
            
            // Conversations List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        currentChatItem
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // Settings Button
            Divider()
                .background(Color.white.opacity(0.1))
            
            settingsButton
        }
        .background(.ultraThinMaterial)
    }
    
    private var newChatButton: some View {
        Button(action: { viewModel.startNewChat() }) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                Text("New Chat")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.2, green: 0.6, blue: 0.6).opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.2, green: 0.6, blue: 0.6).opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
    
    private var emptyState: some View {
        Text("No conversations yet")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
    
    private var currentChatItem: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: "message.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.6))
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Chat")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    
                    Text("Just now")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.2, green: 0.6, blue: 0.6).opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var settingsButton: some View {
        Button(action: {
            NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
        }) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                Text("Settings")
                    .font(.system(size: 14))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SidebarView(viewModel: ChatViewModel())
        .frame(width: 280, height: 600)
}
