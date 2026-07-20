import SwiftUI

/// Ids for the elements that travel between a compact bar and the open header.
enum MorphID {
    static let camera = "morphCamera"
    static let leftFlank = "morphLeftFlank"
    static let rightFlank = "morphRightFlank"
}

extension View {
    /// Applies a matched-geometry id only when travel is wanted (Reduce Motion
    /// off), so the compact→open morph flows without breaking the reduced path.
    @ViewBuilder
    func morphAnchor(_ id: String, in ns: Namespace.ID, active: Bool) -> some View {
        if active { matchedGeometryEffect(id: id, in: ns) } else { self }
    }
}

struct NotchView: View {
    @Bindable var vm: NotchViewModel
    var core: JarvisCore?
    var chat: ChatStore?
    var voice: VoiceController?
    var meetings: MeetingService?
    @State private var isHovering = false
    @State private var peekText: String?
    @State private var peekDismiss: Task<Void, Never>?
    /// Which History conversation is open in the detail view (drives the tray's
    /// "Continue" slot). Mirrored from HistoryView.
    @State private var historyOpenSegmentID: String?
    /// Bumped when the tray's "Back to latest" pill is tapped.
    @State private var returnToLatestSignal = 0
    @Namespace private var tabPillNamespace
    /// Shared geometry namespace for the compact-bar → open morph: the camera
    /// void and the left/right flanks physically travel into the tab header
    /// (Dynamic Island grammar) instead of crossfading.
    @Namespace private var morphNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVoiceHost: Bool {
        // Voice state renders on the screen where the user is (mouse/active),
        // so it follows them across displays.
        guard let voice else { return false }
        return vm.displayID == voice.activeDisplayID
    }

    private var showsListening: Bool {
        guard let voice, isVoiceHost else { return false }
        return voice.isActive && vm.state == .closed
    }

    // Nudges / meeting / working bars and onboarding render on the primary
    // (built-in) display only. Making them follow the active display would mean
    // tracking the mouse continuously — exactly the idle-CPU cost Step 6 removed
    // — so the notch experience is deliberately anchored to the built-in notch.
    // Voice is the one exception: it already follows the user via activeDisplayID.
    private var isPrimary: Bool { vm.displayID == CGMainDisplayID() }

    private var showsOnboarding: Bool {
        isPrimary && core?.loaded == true && core?.onboardingComplete == false
    }

    private var agentWorking: Bool { chat?.phase == .responding }

    /// The agent is working a FOREGROUND turn: show the compact glowing working
    /// bar (collapsing an open panel too) until the answer streams, then it
    /// expands. Shown on whichever notch is open, else the primary.
    private var showsForegroundWorking: Bool {
        chat?.isWorkingCompact == true && !showsListening && peekText == nil
            && (vm.state == .open || isPrimary)
    }

    /// Jarvis is doing work the closed notch should reflect: a foreground response
    /// (rare while closed) OR a background run's Live Activity.
    private var isBusy: Bool { agentWorking || chat?.liveActivity != nil }

    /// The notch is closed but Jarvis is busy (answering, or an unread proactive
    /// nudge is waiting): show a dim, slow border pulse so activity is visible
    /// without opening the panel. Never fights the listening chrome.
    private var showsClosedActivity: Bool {
        vm.state == .closed && !showsListening
            && (isBusy || chat?.hasUnreadProactive == true)
    }

    /// Glow appears while the agent is working or the mic is listening (only on
    /// the notch the user is looking at — active screen or the open one), while
    /// the panel is open, OR — dimly — while the closed notch works in the
    /// background.
    private var showsGlow: Bool {
        if showsClosedActivity { return true }
        guard isVoiceHost || vm.state == .open else { return false }
        if isBusy { return true }
        if chat?.hasUnreadProactive == true { return true }
        if let voice, voice.showsGlow { return true }
        return false
    }

    // Reduce Motion swaps the scale springs for a plain crossfade-style ease.
    private var openAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : NotchAnimation.open
    }
    private var closeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : NotchAnimation.close
    }
    private var tabAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : NotchAnimation.tab
    }

    /// One spring for the whole morph: the bouncy open spring when expanding to a
    /// panel, the more-damped close spring when collapsing to any compact/closed
    /// presentation. This reproduces the old per-trigger open/close choice exactly
    /// while letting a single `.animation(value: presentation)` drive everything.
    private var morphAnimation: Animation {
        switch presentation {
        case .open, .onboarding: openAnimation
        case .idle, .peek, .meeting, .working, .listening: closeAnimation
        }
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
    }

    private var topCornerRadius: CGFloat {
        vm.state == .open ? NotchMetrics.cornerOpen.top : NotchMetrics.cornerClosed.top
    }
    private var bottomCornerRadius: CGFloat {
        vm.state == .open ? NotchMetrics.cornerOpen.bottom : NotchMetrics.cornerClosed.bottom
    }

    /// Live meeting indicator on the closed notch (primary display only, and
    /// never while the voice chrome owns the bar).
    private var showsMeetingBar: Bool {
        isPrimary && vm.state == .closed && !showsListening && peekText == nil
            && meetings?.isActive == true
    }

    /// Live Activity: Jarvis is working (usually a background run) while closed.
    private var showsWorkingBar: Bool {
        isPrimary && vm.state == .closed && !showsListening && peekText == nil
            && !showsMeetingBar && isBusy
    }

    /// The single source of truth for what the notch is showing. Both the panel
    /// size (below) and the rendered content (`bodyContent`) derive from this one
    /// value via the same ladder, so they can never disagree. The ladder mirrors
    /// the old guard precedence exactly: onboarding → open → listening → peek →
    /// meeting → working → idle.
    private var presentation: NotchPresentation {
        if showsOnboarding { return .onboarding }
        // Foreground working outranks .open so a follow-up collapses the panel
        // to the compact glowing bar, then expands when the answer streams.
        if showsForegroundWorking { return .working }
        if vm.state == .open { return .open(vm.selectedTab) }
        if showsListening, let voice { return .listening(voice.phase) }
        if let peekText, isPrimary { return .peek(peekText) }
        if showsMeetingBar { return .meeting }
        if showsWorkingBar { return .working }
        return .idle
    }

    private var displayedSize: CGSize { vm.size(for: presentation) }

    /// The floating glass tray rides with the open panel and the compact
    /// working bar; every other presentation hides it.
    private var showsTray: Bool {
        guard chat != nil else { return false }
        switch presentation {
        case .open(.home), .working: return true
        case .open(.history): return historyOpenSegmentID != nil
        default: return false
        }
    }

    private var trayMode: NotchTrayMode {
        if chat?.phase == .responding { return .stop }
        switch vm.selectedTab {
        case .home: return vm.homeBrowsingHistory ? .backToLatest : .composer
        case .history: return historyOpenSegmentID != nil ? .continueChat : .hidden
        default: return .hidden
        }
    }

    var body: some View {
        // Fixed window: the black notch body scales within it from the top; the
        // glass tray sits BEHIND it and slides out below on open.
        ZStack(alignment: .top) {
            if let chat, showsTray {
                NotchTray(
                    mode: trayMode,
                    chat: chat,
                    voice: voice,
                    onBackToLatest: { returnToLatestSignal += 1 },
                    onContinue: continueOpenHistory
                )
                .frame(width: max(displayedSize.width - 8, 220))
                .offset(y: displayedSize.height + NotchMetrics.trayGap)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(0)
            }
            notchBody
                .zIndex(1)
        }
        .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
        // The tray's slide + retract share the notch's morph/height timelines so
        // it stays glued to the body's bottom edge as it grows and moves.
        .animation(morphAnimation, value: presentation)
        .animation(tabAnimation, value: vm.homeBodyHeight)
        .preferredColorScheme(.dark)
    }

    private func continueOpenHistory() {
        guard let chat, let id = historyOpenSegmentID else { return }
        chat.continueConversation(segmentID: id)
        withAnimation(tabAnimation) { vm.selectedTab = .home }
    }

    @ViewBuilder
    private var notchBody: some View {
        ZStack(alignment: .top) {
            // Glow is an unclipped sibling behind the body, so it leaks past the edges.
            if showsGlow {
                NotchGlow(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    intensity: showsClosedActivity ? 0.4 : (voice?.phase == .ready ? 1.0 : 0.85),
                    slowPulse: showsClosedActivity
                )
                .frame(width: displayedSize.width, height: displayedSize.height)
                // Tiny even bleed so the border glow peeks from behind the edges.
                .scaleEffect(1.012)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
            }
            clippedBody
        }
        // One morph timeline: every discrete presentation change (open/close, tab
        // switch, listening/peek/meeting/working) animates on a single spring, so
        // size, corner radii, and content stay locked together instead of racing
        // across ten separate implicit animations.
        .animation(morphAnimation, value: presentation)
        // Continuous resize WITHIN .open(.home) rides its OWN timeline, never the
        // morph — this isolation is the seam that keeps the HomeView measured-height
        // loop from reoscillating (Step 4). homeBodyHeight/homeBrowsingHistory are
        // deliberately not part of `presentation`.
        .animation(tabAnimation, value: vm.homeBodyHeight)
        .animation(tabAnimation, value: vm.homeBrowsingHistory)
        .animation(.easeInOut(duration: 0.35), value: showsGlow)
    }

    private var clippedBody: some View {
        bodyContent
            .frame(width: displayedSize.width, height: displayedSize.height, alignment: .top)
            .background(.black)
            .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
            .overlay(alignment: .top) {
                Rectangle().fill(.black).frame(height: 1).padding(.horizontal, topCornerRadius)
            }
            .shadow(color: (vm.state == .open || isHovering) ? .black.opacity(0.7) : .clear, radius: 8)
            .contentShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
            .onHover(perform: handleHover)
            .onTapGesture {
                if showsListening {
                    voice?.endListening() // tap to finish a click-to-dictate session
                    return
                }
                guard vm.state == .closed else { return }
                withAnimation(openAnimation) { vm.open() }
            }
    }

    /// The rendered content — a pure `switch` over the same `presentation` that
    /// drives `displayedSize`, so what's shown and how big it is stay in lockstep.
    @ViewBuilder
    private var bodyContent: some View {
        VStack(spacing: 0) {
            switch presentation {
            case .onboarding:
                if let core {
                    OnboardingView(core: core)
                        .padding(.horizontal, 30).padding(.top, 6).padding(.bottom, 16)
                }
            case .open:
                headerRow.frame(height: vm.closedNotchSize.height, alignment: .top)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Clear the shape's rounded edges (sides inset by ~topCornerRadius)
                    // and add breathing room so content never crowds the border.
                    .padding(.horizontal, 34)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if let chat, let request = chat.agent.presenter.current {
                            ApprovalPrompt(request: request, presenter: chat.agent.presenter)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: chat?.agent.presenter.current?.id)
                    .onExitCommand {
                        withAnimation(closeAnimation) { vm.close() }
                    }
                    .transition(contentTransition)
            case .listening:
                if let voice {
                    ListeningView(voice: voice, cameraWidth: vm.closedNotchSize.width, cameraHeight: vm.closedNotchSize.height, morphNamespace: morphNamespace)
                        .transition(.opacity)
                }
            case .peek(let text):
                ClosedPeekBar(text: text, cameraWidth: vm.closedNotchSize.width, cameraHeight: vm.closedNotchSize.height, morphNamespace: morphNamespace)
                    .transition(.opacity)
            case .meeting:
                if let meetings {
                    ClosedMeetingBar(meetings: meetings, cameraWidth: vm.closedNotchSize.width, cameraHeight: vm.closedNotchSize.height, morphNamespace: morphNamespace)
                        .transition(.opacity)
                }
            case .working:
                // Foreground status (thinking → tool → writing) when a live
                // turn is running; the background Live Activity otherwise.
                ClosedWorkingBar(activity: chat?.foregroundActivity ?? chat?.liveActivity,
                                 cameraWidth: vm.closedNotchSize.width,
                                 cameraHeight: vm.closedNotchSize.height, morphNamespace: morphNamespace)
                    .transition(.opacity)
            case .idle:
                Color.black
            }
        }
        .onChange(of: chat?.agent.presenter.current?.id) { _, newValue in
            // The panel must never auto-close while an approval is pending —
            // a timed-out prompt the user never saw is a silent deny.
            vm.holdOpen = newValue != nil
            if newValue != nil, vm.state == .closed, vm.screenFrame.contains(NSEvent.mouseLocation) {
                withAnimation(openAnimation) { vm.open() }
            }
        }
        .onChange(of: vm.state) { _, newState in
            if newState == .open { chat?.markProactiveRead() }
        }
        // Nudge peek: a fresh proactive message briefly expands the closed
        // notch with its first line (Dynamic Island grammar), then retracts.
        .onChange(of: chat?.proactiveStamp) { _, _ in
            guard isPrimary, vm.state == .closed, !showsListening,
                  let text = chat?.latestProactiveText else { return }
            peekText = text
            peekDismiss?.cancel()
            peekDismiss = Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                peekText = nil
            }
        }
        .onChange(of: vm.state) { _, newState in
            if newState == .open {
                peekDismiss?.cancel()
                peekText = nil
                // The panel opening unmounts the review UI — a review left
                // armed with no visible surface would hijack composer ⏎, so
                // park the transcript in the composer instead.
                voice?.abandonReview()
            }
        }
        .onChange(of: chat?.isWorkingCompact ?? false) { _, compact in
            // The compact working bar just handed off to the answer: if the run
            // began while the notch was closed (voice / push-to-talk), open the
            // panel so the streaming answer is shown, focused.
            guard !compact, chat?.phase == .responding, vm.state == .closed, isPrimary else { return }
            vm.selectedTab = .home
            withAnimation(openAnimation) { vm.open() }
        }
    }

    /// Tabs sit at FIXED offsets beside the camera housing: their distance from
    /// the panel's center never changes, so per-tab width changes can't move
    /// the icons out from under the pointer.
    @ViewBuilder
    private var headerRow: some View {
        if vm.state == .open {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 22) {
                    tabButton(.home)
                    tabButton(.history)
                }
                .morphAnchor(MorphID.leftFlank, in: morphNamespace, active: !reduceMotion)
                Color.clear.frame(width: vm.closedNotchSize.width + NotchMetrics.headerCameraReserve)
                    .morphAnchor(MorphID.camera, in: morphNamespace, active: !reduceMotion)
                HStack(spacing: 22) {
                    tabButton(.activity)
                    tabButton(.settings)
                }
                .morphAnchor(MorphID.rightFlank, in: morphNamespace, active: !reduceMotion)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .transition(.opacity)
        } else {
            Color.black
        }
    }

    private func tabButton(_ tab: NotchViewModel.Tab) -> some View {
        // ⌘1…⌘4 in declaration order.
        let index = NotchViewModel.Tab.allCases.firstIndex(of: tab) ?? 0
        let key = KeyEquivalent(Character("\(index + 1)"))
        return TabButton(
            tab: tab,
            isSelected: vm.selectedTab == tab,
            shortcut: key,
            namespace: tabPillNamespace,
            reduceMotion: reduceMotion
        ) {
            withAnimation(tabAnimation) { vm.selectedTab = tab }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let core, let chat {
            switch vm.selectedTab {
            case .home:
                HomeView(
                    chat: chat, voice: voice, meetings: meetings,
                    onBodyHeightChange: { bodyHeight in
                        // Grow the notch to fit the answer (NotchViewModel caps
                        // at half the screen); ignore sub-4pt jitter.
                        if abs((vm.homeBodyHeight ?? 0) - bodyHeight) > 4 {
                            vm.homeBodyHeight = bodyHeight
                        }
                    },
                    onBrowsingChange: { browsing in vm.homeBrowsingHistory = browsing },
                    returnToLatestSignal: returnToLatestSignal
                )
            case .history:
                HistoryView(
                    sessions: chat.sessions,
                    onContinue: { segmentID in
                        chat.continueConversation(segmentID: segmentID)
                        withAnimation(tabAnimation) { vm.selectedTab = .home }
                    },
                    openSegmentID: $historyOpenSegmentID
                )
            case .activity:
                ActivityView(agent: chat.agent, knowledge: chat.memory, worlds: chat.worlds,
                             graphReader: chat.graphReader,
                             taskStore: TaskStore(database: core.database))
            case .settings:
                SettingsView(core: core, screenBuffer: chat.agent.screenBuffer,
                             knowledge: chat.memory)
            }
        } else {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleHover(_ hovering: Bool) {
        withAnimation(.smooth) { isHovering = hovering }
        if hovering {
            // While the voice chrome owns the bar (listening/review), hovering
            // must not auto-open the panel — opening unmounts the review UI
            // right as the user aims for its Send/Cancel buttons.
            if showsListening { return }
            vm.hoverEntered()
        } else {
            vm.hoverExited()
        }
    }
}

/// Closed-notch nudge peek: bell + the message's first line below the camera.
private struct ClosedPeekBar: View {
    let text: String
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let morphNamespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.jarvisLink)
                    .frame(maxWidth: .infinity)
                    .morphAnchor(MorphID.leftFlank, in: morphNamespace, active: !reduceMotion)
                Color.clear.frame(width: cameraWidth + NotchMetrics.cameraSideReserve)
                    .morphAnchor(MorphID.camera, in: morphNamespace, active: !reduceMotion)
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .morphAnchor(MorphID.rightFlank, in: morphNamespace, active: !reduceMotion)
            }
            .frame(height: cameraHeight)

            Text(text)
                .font(.jarvisCaption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jarvis: \(text)")
    }
}

/// Closed-notch live-meeting indicator: pulsing dot + elapsed time flanking the
/// camera. Tap (or hover) opens the panel as usual.
private struct ClosedMeetingBar: View {
    let meetings: MeetingService
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let morphNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                PulsingDot(color: .jarvisError, animated: !reduceMotion)
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .morphAnchor(MorphID.leftFlank, in: morphNamespace, active: !reduceMotion)
            Color.clear.frame(width: cameraWidth + NotchMetrics.cameraSideReserve)
                .morphAnchor(MorphID.camera, in: morphNamespace, active: !reduceMotion)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(at: context.date))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .morphAnchor(MorphID.rightFlank, in: morphNamespace, active: !reduceMotion)
        }
        .frame(height: cameraHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meeting being transcribed")
    }

    private func elapsed(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(meetings.activeSince ?? now)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A recording-style dot that softly pulses (static under Reduce Motion).
private struct PulsingDot: View {
    let color: Color
    let animated: Bool
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}

/// Closed-notch background-run pulse: Jarvis is answering while closed.
private struct ClosedWorkingBar: View {
    var activity: ChatStore.LiveActivity?
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let morphNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { activity?.title ?? "Working" }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                Image(systemName: activity?.symbol ?? "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.75))
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
                    .morphAnchor(MorphID.leftFlank, in: morphNamespace, active: !reduceMotion)
                Color.clear.frame(width: cameraWidth + NotchMetrics.cameraSideReserve)
                    .morphAnchor(MorphID.camera, in: morphNamespace, active: !reduceMotion)
                ProgressView()
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity)
                    .morphAnchor(MorphID.rightFlank, in: morphNamespace, active: !reduceMotion)
            }
            .frame(height: cameraHeight)

            // The Live Activity's per-step label, below the camera cutout.
            // Two lines so the verbose status ("Searching the web: …") fits.
            Text(title)
                .font(.jarvisCaption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jarvis: \(title)")
        // Crossfade the label + swap the symbol as each tool step refines the
        // activity, so the Live Activity updates smoothly instead of snapping.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: title)
    }
}

private struct TabButton: View {
    let tab: NotchViewModel.Tab
    let isSelected: Bool
    let shortcut: KeyEquivalent
    let namespace: Namespace.ID
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                .frame(width: 30, height: 26)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.12))
                            // One shared namespace, so the pill glides between
                            // the two header clusters as the selection moves.
                            .matchedGeometryEffect(id: "tabPill", in: namespace)
                    } else if isHovering {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.07))
                    }
                }
                // "Options" scale on interaction, matching the notch's scale language.
                .scaleEffect(reduceMotion ? 1.0 : (isSelected ? 1.14 : (isHovering ? 1.1 : 1.0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(tab.label)
    }
}
