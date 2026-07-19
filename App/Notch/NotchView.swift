import SwiftUI

struct NotchView: View {
    @Bindable var vm: NotchViewModel
    var core: JarvisCore?
    var chat: ChatStore?
    var voice: VoiceController?
    @State private var isHovering = false
    @Namespace private var tabPillNamespace
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

    private var isPrimary: Bool { vm.displayID == CGMainDisplayID() }

    private var showsOnboarding: Bool {
        isPrimary && core?.loaded == true && core?.onboardingComplete == false
    }

    private var agentWorking: Bool { chat?.phase == .responding }

    /// Glow appears only while the agent is working or the mic is listening, and
    /// only on the notch the user is looking at (active screen or the open one).
    private var showsGlow: Bool {
        guard isVoiceHost || vm.state == .open else { return false }
        if agentWorking { return true }
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

    private var sizeAnimation: Animation {
        vm.state == .open ? openAnimation : closeAnimation
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
    }

    private var topCornerRadius: CGFloat { vm.state == .open ? 20 : 6 }
    private var bottomCornerRadius: CGFloat { vm.state == .open ? 26 : 14 }

    private var displayedSize: CGSize {
        if showsOnboarding { return vm.onboardingSize }
        if vm.state == .open { return vm.currentOpenContentSize }
        if showsListening { return vm.listeningSize }
        return vm.closedNotchSize
    }

    var body: some View {
        // Fixed window: the black notch body scales within it from the top-center.
        notchBody
            .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var notchBody: some View {
        ZStack(alignment: .top) {
            // Glow is an unclipped sibling behind the body, so it leaks past the edges.
            if showsGlow {
                NotchGlow(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    intensity: voice?.phase == .ready ? 1.0 : 0.85
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
        .animation(sizeAnimation, value: vm.state)
        .animation(tabAnimation, value: vm.selectedTab)
        .animation(sizeAnimation, value: showsListening)
        .animation(tabAnimation, value: vm.homeBodyHeight) // answer-fitted growth
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

    @ViewBuilder
    private var bodyContent: some View {
        Group {
            if showsOnboarding, let core {
                OnboardingView(core: core)
                    .padding(.horizontal, 30).padding(.top, 6).padding(.bottom, 16)
            } else {
                tabbedContent
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
    }

    @ViewBuilder
    private var tabbedContent: some View {
        VStack(spacing: 0) {
            if vm.state == .open {
                headerRow.frame(height: vm.closedNotchSize.height, alignment: .top)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Clear the shape's rounded edges (sides inset by ~topCornerRadius)
                    // and add breathing room so content never crowds the border.
                    .padding(.horizontal, 34)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
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
            } else if showsListening, let voice {
                ListeningView(voice: voice, cameraWidth: vm.closedNotchSize.width, cameraHeight: vm.closedNotchSize.height)
                    .transition(.opacity)
            } else {
                Color.black
            }
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
                Color.clear.frame(width: vm.closedNotchSize.width + 28)
                HStack(spacing: 22) {
                    tabButton(.activity)
                    tabButton(.settings)
                }
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
                HomeView(chat: chat, voice: voice) { bodyHeight in
                    // Grow the notch to fit the answer (NotchViewModel caps at
                    // half the screen); ignore sub-8pt jitter during streaming.
                    if abs((vm.homeBodyHeight ?? 0) - bodyHeight) > 8 {
                        vm.homeBodyHeight = bodyHeight
                    }
                }
            case .history:
                HistoryView(sessions: chat.sessions)
            case .activity:
                ActivityView(agent: chat.agent, graphReader: chat.graphReader)
            case .settings:
                SettingsView(core: core)
            }
        } else {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleHover(_ hovering: Bool) {
        withAnimation(.smooth) { isHovering = hovering }
        if hovering {
            vm.hoverEntered()
        } else {
            vm.hoverExited()
        }
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
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
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
