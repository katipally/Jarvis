import AppKit
import JAgent
import MarkdownUI
import SwiftUI

struct HomeView: View {
    @Bindable var chat: ChatStore
    var voice: VoiceController?
    @State private var isDropTargeted = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            composer
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                if let attachment = AttachmentLoader.load(url: url) {
                    chat.addAttachment(attachment)
                }
            }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .overlay(Text("Drop to attach").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)))
            }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if chat.messages.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Ask Jarvis anything")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                Text("or drop a file to attach")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(chat.messages) { message in
                            MessageRow(message: message).id(message.id)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
                .onChange(of: chat.messages.last?.text) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            if let error = chat.errorText {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !chat.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chat.attachments) { attachment in
                            AttachmentChip(attachment: attachment) { chat.removeAttachment(attachment.id) }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Ask anything…", text: $chat.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                        send()
                        return .handled
                    }

                if let voice, chat.phase != .responding {
                    Button { voice.toggle() } label: {
                        Image(systemName: voice.phase == .listening ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(voice.phase == .listening ? Color(red: 1.0, green: 0.45, blue: 0.45) : .white.opacity(0.7))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("Hold Option to talk, or click to dictate")
                }

                Button(action: primaryAction) {
                    Image(systemName: chat.phase == .responding ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(chat.phase == .responding ? Color.white.opacity(0.85) : (chat.canSend ? .white : .white.opacity(0.25))))
                }
                .buttonStyle(.plain)
                .disabled(chat.phase != .responding && !chat.canSend)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            )
            .padding(.bottom, 2)
        }
        .padding(.top, 6)
        .onAppear { inputFocused = true }
    }

    private func primaryAction() {
        if chat.phase == .responding {
            chat.interrupt()
        } else {
            send()
        }
    }

    private func send() {
        chat.send()
        inputFocused = true
    }
}

private struct MessageRow: View {
    let message: DisplayMessage

    var body: some View {
        switch message.role {
        case .tool:
            ToolRow(message: message)
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 4) {
                    if !message.images.isEmpty {
                        Text("\(message.images.count) image\(message.images.count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.12)))
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if message.isError {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.5))
                } else if message.text.isEmpty && message.isStreaming {
                    ThinkingDots()
                } else {
                    Markdown(message.text)
                        .markdownTheme(.jarvis)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ToolRow: View {
    let message: DisplayMessage

    private var symbol: String {
        switch message.toolState {
        case .done: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        default: "gearshape.fill"
        }
    }

    private var tint: Color {
        switch message.toolState {
        case .done: Color(red: 0.4, green: 0.85, blue: 0.5)
        case .error: Color(red: 1.0, green: 0.5, blue: 0.5)
        default: .white.opacity(0.6)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            if message.toolState == .running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
            }
            Text(message.toolName ?? "tool")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.06)))
    }
}

private struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.isImage ? "photo" : "doc.text")
                .font(.system(size: 10))
            Text(attachment.filename)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.1)))
    }
}

private struct ThinkingDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .scaleEffect(1 + 0.4 * sin(phase + Double(i) * 0.6))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}
