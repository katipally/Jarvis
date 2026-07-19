import AppKit
import JAgent
import MarkdownUI
import SwiftUI

struct HomeView: View {
    @Bindable var chat: ChatStore
    var voice: VoiceController?
    @State private var isDropTargeted = false
    @FocusState private var inputFocused: Bool

    /// A transcript row that repeats the composer error banner verbatim is
    /// suppressed so the failure renders on a single surface.
    private var visibleMessages: [DisplayMessage] {
        chat.messages.filter { !($0.isError && $0.text == chat.errorText) }
    }

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
                    .overlay(Text("Drop to attach").font(.jarvisRow).foregroundStyle(.white.opacity(0.6)))
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: isDropTargeted)
    }

    @ViewBuilder
    private var transcript: some View {
        if visibleMessages.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .symbolEffect(.breathe)
                    .accessibilityHidden(true)
                Text("Ask Jarvis anything")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Text("or drop a file to attach")
                    .font(.jarvisCaption)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(visibleMessages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let error = chat.errorText {
                errorBanner(error)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !chat.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chat.attachments) { attachment in
                            AttachmentChip(attachment: attachment) { chat.removeAttachment(attachment.id) }
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $chat.input,
                    prompt: Text("Ask anything…").foregroundStyle(.white.opacity(0.45)),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.jarvisBody)
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .onKeyPress(.return) {
                    if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                    send()
                    return .handled
                }

                if let voice {
                    // Stays in layout while responding (disabled + dimmed), so
                    // the composer geometry never jumps.
                    Button { voice.toggle() } label: {
                        Image(systemName: voice.phase == .listening ? "stop.circle.fill" : "mic.fill")
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(voice.phase == .listening ? Color.jarvisError : .white.opacity(0.7))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.phase == .responding)
                    .opacity(chat.phase == .responding ? 0.3 : 1)
                    .animation(.snappy, value: voice.phase == .listening)
                    .help("Hold Option to talk, or click to dictate")
                    .accessibilityLabel(voice.phase == .listening ? "Stop dictation" : "Start dictation")
                }

                Button(action: primaryAction) {
                    Image(systemName: chat.phase == .responding ? "stop.fill" : "arrow.up")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(chat.phase == .responding ? Color.white.opacity(0.85) : (chat.canSend ? .white : .white.opacity(0.25))))
                }
                .buttonStyle(.plain)
                .disabled(chat.phase != .responding && !chat.canSend)
                .accessibilityLabel(chat.phase == .responding ? "Stop response" : "Send message")
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
        .animation(.snappy, value: chat.errorText)
        .animation(.snappy, value: chat.attachments)
        .animation(.snappy, value: chat.phase)
        .onAppear { inputFocused = true }
    }

    /// The single error surface: message + Retry + dismiss, above the composer.
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.jarvisCaption)
                .foregroundStyle(Color.jarvisError)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") { chat.retryLast() }
                .buttonStyle(.plain)
                .font(.jarvisCaption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Button { chat.errorText = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.jarvisError.opacity(0.12)))
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
                        HStack(spacing: 4) {
                            ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                                ImageThumbnail(image: image, size: 44)
                            }
                        }
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.jarvisBody)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.12)))
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if message.isError {
                    Label(message.text, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.jarvisError)
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

    @State private var expanded = false
    @State private var startedAt = Date()

    private var symbol: String {
        switch message.toolState {
        case .done: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        default: "gearshape.fill"
        }
    }

    private var tint: Color {
        switch message.toolState {
        case .done: Color.jarvisSuccess
        case .error: Color.jarvisError
        default: .white.opacity(0.6)
        }
    }

    private var hasOutput: Bool {
        message.toolState != .running && !message.text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasOutput else { return }
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if message.toolState == .running {
                        Image(systemName: "gearshape.fill")
                            .font(.jarvisCaption)
                            .foregroundStyle(.white.opacity(0.6))
                            .symbolEffect(.rotate)
                    } else {
                        Image(systemName: symbol)
                            .symbolRenderingMode(.hierarchical)
                            .font(.jarvisCaption)
                            .foregroundStyle(tint)
                    }
                    Text(message.toolName ?? "tool")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    if message.toolState == .running {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .font(.jarvisFootnote)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    if hasOutput {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, hasOutput {
                ScrollView {
                    Text(message.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
    }
}

/// Renders an ImageSource (base64) as a small rounded thumbnail.
private struct ImageThumbnail: View {
    let image: ImageSource
    var size: CGFloat = 28

    var body: some View {
        if let data = Data(base64Encoded: image.base64Data), let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.jarvisFootnote)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.08)))
        }
    }
}

private struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if let image = attachment.image {
                ImageThumbnail(image: image, size: 22)
            } else {
                Image(systemName: "doc.text")
                    .font(.jarvisFootnote)
            }
            Text(attachment.filename)
                .font(.jarvisCaption)
                .lineLimit(1)
                .frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.1)))
    }
}

private struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0.0

    var body: some View {
        Group {
            if reduceMotion {
                Text("…")
                    .font(.jarvisBody)
                    .foregroundStyle(.white.opacity(0.55))
            } else {
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
        .accessibilityHidden(true)
    }
}
