import SwiftUI

struct NotchView: View {
    @Bindable var vm: NotchViewModel
    var core: JarvisCore?
    var chat: ChatStore?
    var voice: VoiceController?
    @State private var isHovering = false

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

    private let openAnimation = Animation.spring(response: 0.40, dampingFraction: 0.78)
    private let closeAnimation = Animation.spring(response: 0.34, dampingFraction: 0.9)
    private let tabAnimation = Animation.spring(response: 0.36, dampingFraction: 0.82)

    private var sizeAnimation: Animation {
        vm.state == .open ? openAnimation : closeAnimation
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
                .transition(.opacity)
            }
            clippedBody
        }
        .animation(sizeAnimation, value: vm.state)
        .animation(tabAnimation, value: vm.selectedTab)
        .animation(sizeAnimation, value: showsListening)
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
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            } else if showsListening, let voice {
                ListeningView(voice: voice, cameraWidth: vm.closedNotchSize.width, cameraHeight: vm.closedNotchSize.height)
                    .transition(.opacity)
            } else {
                Color.black
            }
        }
    }

    /// Tabs split left/right of the camera housing.
    @ViewBuilder
    private var headerRow: some View {
        if vm.state == .open {
            HStack(spacing: 0) {
                HStack(spacing: 22) {
                    tabButton(.home)
                    tabButton(.history)
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: vm.closedNotchSize.width)

                HStack(spacing: 22) {
                    tabButton(.activity)
                    tabButton(.settings)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
            .transition(.opacity)
        } else {
            Color.black
        }
    }

    private func tabButton(_ tab: NotchViewModel.Tab) -> some View {
        TabButton(tab: tab, isSelected: vm.selectedTab == tab) {
            withAnimation(tabAnimation) { vm.selectedTab = tab }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let core, let chat {
            switch vm.selectedTab {
            case .home:
                HomeView(chat: chat, voice: voice)
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
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(systemName: tab.symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
            .frame(width: 30, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.12 : (isHovering ? 0.07 : 0)))
            )
            // "Options" scale on interaction, matching the notch's scale language.
            .scaleEffect(isSelected ? 1.14 : (isHovering ? 1.1 : 1.0))
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovering = hovering }
            }
            .onTapGesture(perform: action)
            .accessibilityLabel(tab.label)
    }
}
