import SwiftUI

struct FloatingInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            // Attached files preview
            if !viewModel.attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.attachedFiles, id: \.self) { file in
                            AttachmentPill(name: file.lastPathComponent) {
                                viewModel.removeFile(file)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main input bar
            HStack(alignment: .bottom, spacing: 0) {
                // Attach Button - Inside the pill on the left
                Button(action: { viewModel.showFilePicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .padding(.leading, 8)
                .padding(.bottom, 8)
                .fileImporter(
                    isPresented: $viewModel.showFilePicker,
                    allowedContentTypes: [.pdf, .plainText, .image, .png, .jpeg],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        viewModel.attachFiles(urls)
                    }
                }
                
                // Text Input
                TextField("Message", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .disabled(viewModel.isSending)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .onSubmit { sendMessage() }
                
                // Send/Stop Button - Inside the pill on the right
                if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachedFiles.isEmpty || viewModel.isLoading {
                    Button(action: {
                        if viewModel.isLoading { 
                            viewModel.stopGeneration() 
                        } else { 
                            sendMessage() 
                        }
                    }) {
                        Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(viewModel.isLoading ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        }
        .padding(.horizontal, 8)
        .animation(.spring(response: 0.3), value: viewModel.inputText.isEmpty)
        .animation(.spring(response: 0.3), value: viewModel.attachedFiles.count)
    }
    
    private func sendMessage() {
        guard viewModel.canSend else { return }
        Task {
            await viewModel.sendMessage()
            isInputFocused = true
        }
    }
}

struct AttachmentPill: View {
    let name: String
    let onRemove: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var fileIcon: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "paperclip"
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 120)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.blue.opacity(0.1))
        )
        .foregroundStyle(colorScheme == .dark ? .white : .primary)
    }
}
