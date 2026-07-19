import AppKit
import JAgent
import MarkdownUI
import SwiftUI

struct HomeView: View {
    @Bindable var chat: ChatStore
    var voice: VoiceController?
    /// Reports the height the body wants (current answer + composer) so the
    /// notch can grow to fit the answer — capped by the view model.
    var onBodyHeightChange: (CGFloat) -> Void = { _ in }
    /// Reports whether the user has scrolled up into history (the panel then
    /// opens to a comfortable reading height).
    var onBrowsingChange: (Bool) -> Void = { _ in }

    @State private var isDropTargeted = false
    @FocusState private var inputFocused: Bool
    @State private var answerHeight: CGFloat = 0
    @State private var composerHeight: CGFloat = 0

    /// Pinned = glued to the latest answer; browsing = reading history.
    private enum ScrollMode { case pinned, browsing }
    @State private var scrollMode: ScrollMode = .pinned
    /// Geometry changes caused by our own panel resizes are ignored until this
    /// instant so the resize can't re-trigger itself (the oscillation bug).
    @State private var suppressGeometryUntil = Date.distantPast
    @State private var lastDistanceFromBottom: CGFloat = 0
    @State private var lastReportedBodyHeight: CGFloat = 0
    @State private var repinTask: Task<Void, Never>?

    /// Comfortable body height for the greeting (no conversation yet).
    private let greetingBaseHeight: CGFloat = 190

    /// A transcript row that repeats the composer error banner verbatim is
    /// suppressed so the failure renders on a single surface.
    private var visibleMessages: [DisplayMessage] {
        chat.messages.filter { !($0.isError && $0.text == chat.errorText) }
    }

    /// Rows after the last user message: the exchange currently "in focus".
    /// Everything before it lives above the fold (scroll up to see).
    private var answerStartIndex: Int? {
        guard !visibleMessages.isEmpty else { return nil }
        guard let lastUser = visibleMessages.lastIndex(where: { $0.role == .user }) else { return 0 }
        let start = lastUser + 1
        return start < visibleMessages.count ? start : nil
    }

    private var priorMessages: ArraySlice<DisplayMessage> {
        visibleMessages[..<(answerStartIndex ?? visibleMessages.count)]
    }

    private var answerMessages: ArraySlice<DisplayMessage> {
        guard let start = answerStartIndex else { return visibleMessages[visibleMessages.endIndex...] }
        return visibleMessages[start...]
    }

    private func reportBodyHeight() {
        // Waiting for the first token of a new answer: hold the current size
        // instead of collapsing and re-growing.
        if chat.phase == .responding, answerMessages.isEmpty { return }
        let content = answerMessages.isEmpty ? greetingBaseHeight : answerHeight
        // +14 covers the inter-row gap above the answer when history precedes it,
        // so the answer's first line never sits inside the top fade.
        let spacingAllowance: CGFloat = priorMessages.isEmpty ? 16 : 30
        let newValue = content + composerHeight + spacingAllowance
        if abs(newValue - lastReportedBodyHeight) > 8 {
            // This report will resize the panel — don't let the resulting
            // geometry churn masquerade as a user scroll.
            lastReportedBodyHeight = newValue
            suppressGeometryUntil = max(suppressGeometryUntil, Date.now.addingTimeInterval(0.45))
        }
        onBodyHeightChange(newValue)
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

    /// Answer-focused transcript: the notch fits the current answer, so only it
    /// is visible; the user's message, earlier exchanges, and older sessions sit
    /// above the fold and appear on scroll-up (iMessage style).
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
                        ForEach(priorMessages) { message in
                            MessageRow(message: message)
                        }
                        // The in-focus exchange: measured as one unit so the panel
                        // can grow to fit exactly this content.
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(answerMessages) { message in
                                MessageRow(message: message)
                            }
                        }
                        .id("live-bottom")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            answerHeight = height
                            reportBodyHeight()
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            // Sending re-pins the view to the incoming answer even if the user
            // had scrolled up into history (iMessage behavior).
            .onChange(of: chat.phase) { _, phase in
                if phase == .responding {
                    scrollMode = .pinned
                    onBrowsingChange(false)
                    suppressGeometryUntil = Date.now.addingTimeInterval(0.5)
                    withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo("live-bottom", anchor: .bottom) }
                }
            }
            // Deterministic pinned/browsing state machine. The panel resizing
            // itself changes the scroll geometry, so raw thresholding oscillates;
            // instead: our own resizes are suppressed, drift while pinned is
            // silently re-pinned, and mode flips need a clear user gesture.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
                    - (geometry.contentOffset.y + geometry.containerSize.height)
            } action: { _, distance in
                lastDistanceFromBottom = distance
                guard Date.now >= suppressGeometryUntil else { return }
                switch scrollMode {
                case .pinned:
                    if distance > 44 {
                        // Real upward scroll: enter browsing and let the panel
                        // open to reading height.
                        scrollMode = .browsing
                        onBrowsingChange(true)
                        suppressGeometryUntil = Date.now.addingTimeInterval(0.5)
                    } else if distance > 6 {
                        // Drift from our own resize/streaming: quietly re-pin.
                        repinTask?.cancel()
                        repinTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            guard !Task.isCancelled, scrollMode == .pinned,
                                  lastDistanceFromBottom > 6 else { return }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { proxy.scrollTo("live-bottom", anchor: .bottom) }
                        }
                    }
                case .browsing:
                    if distance < 6 {
                        // Back at the latest answer: settle, shrink to fit, and
                        // keep the view glued through the shrink.
                        scrollMode = .pinned
                        onBrowsingChange(false)
                        suppressGeometryUntil = Date.now.addingTimeInterval(0.6)
                        withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo("live-bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .mask {
            // Content dissolves at the edges instead of clipping hard. Kept
            // shallow so a tightly-fitted one-line answer isn't dimmed.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.2), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 10)
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
            }
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
                .onChange(of: chat.input) { chat.draftChanged() }
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
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(inputFocused ? 0.28 : 0.16), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: 0.15), value: inputFocused)
        }
        .padding(.top, 4)
        .animation(.snappy, value: chat.errorText)
        .animation(.snappy, value: chat.attachments)
        .animation(.snappy, value: chat.phase)
        .onAppear { inputFocused = true }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            composerHeight = height
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
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text("Ask anything, or drop a file to attach")
                .font(.jarvisCaption)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 2)
            Spacer()
        }
        .multilineTextAlignment(.center)
    }
}

struct MessageRow: View {
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
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.jarvisSurfaceActive)
                                    .strokeBorder(Color.jarvisStroke, lineWidth: 1)
                            )
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
                        .foregroundStyle(.white.opacity(0.8))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.jarvisSurface)
                .strokeBorder(Color.jarvisStroke, lineWidth: 1)
        )
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
