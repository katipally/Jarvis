import SwiftUI

/// What the floating glass tray below the notch is showing. One slot, four
/// contents: the Home composer, the "Back to latest" affordance while browsing
/// history, the Stop control while the agent works, and "Continue" for an open
/// History conversation.
enum NotchTrayMode: Equatable {
    case hidden
    case composer
    case stop
    case continueChat
    /// Browsing up through the current session: the composer collapses into a
    /// "jump to newest" pill until the transcript is back at the bottom.
    case backToLatest
}

/// The detached Liquid-Glass pill that lives BELOW the notch's bottom border. It
/// slides out from behind the body on open and retracts on tab-switch/close
/// (that motion is owned by `NotchView`). Real macOS 26 glass — no custom blur.
struct NotchTray: View {
    let mode: NotchTrayMode
    @Bindable var chat: ChatStore
    var voice: VoiceController?
    var onContinue: () -> Void = {}
    /// Jump the transcript back to the newest message (the "Latest" pill).
    var onBackToLatest: () -> Void = {}

    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stopDimmed = false

    var body: some View {
        Group {
            switch mode {
            case .composer: composer
            case .stop: stopPill
            case .continueChat:
                actionPill(icon: "arrow.uturn.left", label: "Continue",
                           action: onContinue)
            case .backToLatest:
                // No Esc binding here — Esc should close the notch, not scroll.
                actionPill(icon: "arrow.down", label: "Latest", cancelShortcut: false,
                           action: onBackToLatest)
            case .hidden: EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $chat.input,
                prompt: Text("Ask anything…").foregroundStyle(.secondary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.jarvisBody)
            .lineLimit(1...3) // grows to 3 lines, then the text scrolls inside
            .focused($inputFocused)
            .onChange(of: chat.input) { chat.draftChanged() }
            // Return sends; Shift+Return inserts a newline (the field grows).
            // No .onSubmit — it would also fire on Shift+Return and send.
            .onKeyPress(.return) {
                if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                send()
                return .handled
            }
            .frame(maxWidth: .infinity)

            if let voice {
                Button { voice.toggle() } label: {
                    Image(systemName: voice.phase == .listening ? "stop.circle.fill" : "mic.fill")
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(voice.phase == .listening ? Color.jarvisError : .secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: voice.phase == .listening)
                .help("Hold Option to talk, or click to dictate")
                .accessibilityLabel(voice.phase == .listening ? "Stop dictation" : "Start dictation")
            }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(chat.canSend ? .white : .white.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .trayGlass()
        .onAppear { inputFocused = true }
    }

    private func send() {
        chat.send()
        inputFocused = true
    }

    // MARK: - Stop

    private var stopPill: some View {
        Button { chat.interrupt() } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Stop")
                    .font(.jarvisCaption.weight(.medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .trayGlass()
            .opacity(stopDimmed ? 0.6 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel("Stop response")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                stopDimmed = true
            }
        }
    }

    // MARK: - Action pills (Back to latest / Continue)

    private func actionPill(icon: String, label: String, cancelShortcut: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.jarvisCaption.weight(.medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .trayGlass()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .keyboardShortcut(cancelShortcut ? .cancelAction : nil)
        .accessibilityLabel(label)
    }
}

private extension View {
    /// Apple-style Liquid Glass capsule with a crisp adaptive rim + a soft float
    /// shadow, so the pill reads clearly over any desktop (the bare glassEffect
    /// edge is too faint on dark backgrounds — the "blends in" complaint).
    func trayGlass() -> some View {
        glassEffect(.regular, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
    }
}
