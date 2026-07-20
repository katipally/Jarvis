import AppKit
import JAgent
import MarkdownUI
import SwiftUI

struct HomeView: View {
    @Bindable var chat: ChatStore
    var voice: VoiceController?
    var meetings: MeetingService?
    /// Reports the height the transcript wants so the notch grows to fit it,
    /// capped by the view model. Home is a plain chat: the full session history,
    /// newest at the bottom, auto-growing to fit then scrolling.
    var onBodyHeightChange: (CGFloat) -> Void = { _ in }
    /// Starts a fresh conversation (the compose button / ⌘N).
    var onNewSession: () -> Void = {}

    @State private var isDropTargeted = false
    @State private var contentHeight: CGFloat = 0
    @State private var accessoriesHeight: CGFloat = 0

    /// Comfortable body height for the greeting (no conversation yet).
    private let greetingBaseHeight: CGFloat = 190

    /// A transcript row that repeats the composer error banner verbatim is
    /// suppressed so the failure renders on a single surface.
    private var visibleMessages: [DisplayMessage] {
        chat.messages.filter { !($0.isError && $0.text == chat.errorText) }
    }

    private func reportBodyHeight() {
        let content = visibleMessages.isEmpty ? greetingBaseHeight : contentHeight
        onBodyHeightChange(content + accessoriesHeight + 16)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let meetings, meetings.isActive {
                MeetingTranscriptCard(appName: meetings.activeAppName, lines: meetings.lines) {
                    meetings.stopMeeting()
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            transcript
            // Transient composing accessories (pending attachments + the single
            // error surface). The composer itself is the floating glass tray
            // below the notch; these stay in the body so they ride the answer.
            accessories
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
        // Compose a fresh conversation. Hidden on the empty greeting (already new).
        .overlay(alignment: .topTrailing) {
            if !visibleMessages.isEmpty {
                Button(action: onNewSession) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.jarvisSurface))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .keyboardShortcut("n", modifiers: .command)
                .help("New conversation (⌘N)")
                .accessibilityLabel("New conversation")
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: isDropTargeted)
        .animation(.snappy, value: visibleMessages.isEmpty)
    }

    /// The full conversation, newest at the bottom. The notch auto-grows to fit
    /// the transcript (capped by the view model); longer histories scroll.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.hasOlderHistory {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.mini)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .onAppear { chat.loadOlderHistory() }
                    }
                    if visibleMessages.isEmpty {
                        GreetingView()
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.96 }
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(visibleMessages) { message in
                            MessageRow(
                                message: message,
                                onRetry: (message.role == .assistant && chat.canRetry
                                          && message.id == chat.latestAssistant?.id)
                                    ? { chat.retryLast() } : nil,
                                onFollowUp: message.isProactive
                                    ? { chat.askFollowUp("Tell me more about that.", from: message.id) } : nil,
                                onDismiss: message.isProactive
                                    ? { chat.dismissProactive(message.id) } : nil
                            )
                        }
                        Color.clear.frame(height: 1).id("bottom-anchor")
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    contentHeight = height
                    reportBodyHeight()
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.2), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
            }
            // Glide to the newest message when a turn starts or a message arrives.
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
            }
            // Follow the growing answer while it streams.
            .onChange(of: contentHeight) { _, _ in
                guard chat.phase == .responding else { return }
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
            // Land at the newest message when the panel first shows.
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
        }
    }

    /// Transient composing accessories shown at the bottom of the body: pending
    /// attachments + the single error surface. The composer itself is the
    /// floating glass tray below the notch; these ride the answer so drag-drop
    /// and errors stay visually attached to the conversation.
    @ViewBuilder
    private var accessories: some View {
        let hasContent = chat.errorText != nil || !chat.attachments.isEmpty
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
        }
        .padding(.top, hasContent ? 8 : 0)
        .animation(.snappy, value: chat.errorText)
        .animation(.snappy, value: chat.attachments)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            accessoriesHeight = height
            reportBodyHeight()
        }
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
}

/// LocalNotch-style idle state: a personal greeting with the live date/time.
private struct GreetingView: View {
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salute = switch hour {
        case 0..<5: "Good night"
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let name = NSFullUserName().components(separatedBy: " ").first ?? ""
        return name.isEmpty ? "\(salute)." : "\(salute), \(name)."
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(greeting)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .font(.jarvisRow)
                    .monospacedDigit()
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            Text("Ask anything, or drop a file to attach")
                .font(.jarvisCaption)
                .foregroundStyle(Color.jarvisTextTertiary)
                .padding(.top, 2)
            Spacer()
        }
        .multilineTextAlignment(.center)
    }
}

struct MessageRow: View {
    let message: DisplayMessage
    /// "Try again" — re-sends the exchange; only set on Home's last assistant row.
    var onRetry: (() -> Void)? = nil
    /// Inline actions for a proactive nudge (Tell me more / Dismiss).
    var onFollowUp: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    /// Reasoning timing, measured live from this row's stream (nil for restored
    /// history, where the elapsed time can't be reconstructed).
    @State private var thinkingStartedAt: Date?
    @State private var thinkingDuration: TimeInterval?

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }

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
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.jarvisSurfaceActive)
                                    .strokeBorder(Color.jarvisStroke, lineWidth: 1)
                            )
                            .contextMenu {
                                Button("Copy", action: copyText)
                            }
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                if !message.thinking.isEmpty {
                    ThinkingDisclosure(text: message.thinking, duration: thinkingDuration)
                }
                if message.isError {
                    Label(message.text, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.jarvisError)
                } else if !message.text.isEmpty {
                    Markdown(message.text)
                        .markdownTheme(.jarvis)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy", action: copyText)
                            if let onRetry {
                                Button("Try again", action: onRetry)
                            }
                        }
                } else if message.isStreaming {
                    ThinkingDots()
                }
                if message.isStopped {
                    Label("Stopped", systemImage: "stop.circle")
                        .font(.jarvisFootnote)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 2)
                }
                if message.isProactive, onFollowUp != nil {
                    HStack(spacing: 12) {
                        Button { onFollowUp?() } label: {
                            Label("Tell me more", systemImage: "arrow.turn.down.right").font(.jarvisCaption)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.jarvisAccent).pointerStyle(.link)
                        Button { onDismiss?() } label: {
                            Text("Dismiss").font(.jarvisCaption)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.jarvisTextTertiary).pointerStyle(.link)
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                if !message.thinking.isEmpty, thinkingStartedAt == nil { thinkingStartedAt = Date() }
            }
            .onChange(of: message.thinking.isEmpty) { _, isEmpty in
                if !isEmpty, thinkingStartedAt == nil { thinkingStartedAt = Date() }
            }
            .onChange(of: message.text.isEmpty) { _, textEmpty in
                if !textEmpty, thinkingDuration == nil, let start = thinkingStartedAt {
                    thinkingDuration = Date.now.timeIntervalSince(start)
                }
            }
        }
    }
}

private struct ToolRow: View {
    let message: DisplayMessage

    @State private var expanded = false
    @State private var startedAt = Date()
    /// Frozen elapsed once the tool finishes, so the timing survives after the
    /// live timer stops. Only set when this row observed the running→done edge.
    @State private var finishedElapsed: TimeInterval?

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
                        .foregroundStyle(.white.opacity(0.8))
                    if message.toolState == .running {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .font(.jarvisFootnote)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                    } else if let finishedElapsed {
                        Text(Self.durationText(finishedElapsed))
                            .font(.jarvisFootnote)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.jarvisSurface)
                .strokeBorder(Color.jarvisStroke, lineWidth: 1)
        )
        .onChange(of: message.toolState) { old, new in
            if old == .running, new == .done || new == .error, finishedElapsed == nil {
                finishedElapsed = Date.now.timeIntervalSince(startedAt)
            }
        }
    }

    private static func durationText(_ t: TimeInterval) -> String {
        if t < 1 { return "<1s" }
        if t < 60 { return String(format: "%.0fs", t) }
        return "\(Int(t) / 60)m \(Int(t) % 60)s"
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

/// Collapsed reasoning shown above an answer. `DisplayMessage.thinking` is
/// captured while streaming but was never surfaced; this reveals it on demand.
private struct ThinkingDisclosure: View {
    let text: String
    var duration: TimeInterval?

    @State private var expanded = false

    private var title: String {
        if let duration, duration >= 0.5 {
            return "Thought for \(Int(duration.rounded()))s"
        }
        return "Thought process"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                Text(text)
                    .font(.jarvisCaption)
                    .foregroundStyle(.white.opacity(0.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(.system(size: 9))
                Text(title)
                    .font(.jarvisCaption.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.5))
        }
        .disclosureGroupStyle(ThinkingDisclosureStyle())
    }
}

/// A rotating chevron instead of the platform disclosure triangle, matching the
/// notch's tool rows.
private struct ThinkingDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
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
