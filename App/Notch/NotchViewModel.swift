import AppKit
import Observation

/// The single, authoritative description of what the notch is showing right now.
/// Both the panel size and the rendered content derive from this one value, so
/// they can never disagree (the old code reconstructed state from ~7 booleans in
/// two parallel `if`-chains that could drift apart). `NotchViewModel.state`
/// (closed/open) remains the authoritative toggle; this is *derived* from it plus
/// the live service state, via a priority ladder in `NotchView`.
enum NotchPresentation: Equatable {
    case idle                              // closed, nothing active
    case onboarding                        // first run (primary display)
    case open(NotchViewModel.Tab)          // expanded panel
    case listening(VoiceController.Phase)  // voice chrome (listening/processing/review)
    case peek(String)                      // proactive nudge, first line
    case meeting                           // live-meeting status bar
    case working                           // background-run pulse bar
}

@MainActor
@Observable
final class NotchViewModel {
    enum State: Equatable {
        case closed
        case open
    }

    enum Tab: String, CaseIterable, Identifiable, Equatable {
        case home, history, activity, settings

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .home: "message"
            case .history: "clock.arrow.circlepath"
            case .activity: "waveform.path.ecg"
            case .settings: "gearshape"
            }
        }

        var label: String {
            switch self {
            case .home: "Home"
            case .history: "History"
            case .activity: "Activity"
            case .settings: "Settings"
            }
        }
    }

    private(set) var state: State = .closed
    var selectedTab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "jarvis.selectedTab") ?? "") ?? .home {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: "jarvis.selectedTab") }
    }
    private(set) var closedNotchSize: CGSize
    private(set) var screenFrame: CGRect
    let displayID: CGDirectDisplayID
    private(set) var hasPhysicalNotch: Bool

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var openedAt: Date?
    @ObservationIgnored private var hoverOpenTask: Task<Void, Never>?
    /// Fired after every open/close so the screen manager can install the pointer
    /// monitors only while a panel is open (→ zero mouse tracking while idle).
    @ObservationIgnored var onStateChange: (() -> Void)?

    private static let homeBodyHeightKey = "jarvis.homeBodyHeight"

    init(screen: NSScreen) {
        displayID = screen.jarvisDisplayID
        screenFrame = screen.frame
        hasPhysicalNotch = screen.safeAreaInsets.top > 0
        closedNotchSize = Self.computeClosedNotchSize(for: screen)
        // Seed the last-known Home height so the first open after launch morphs
        // straight to the right size instead of jumping min → measured. The
        // HomeView measure loop corrects it on mount if the answer differs.
        if let saved = UserDefaults.standard.object(forKey: Self.homeBodyHeightKey) as? Double {
            homeBodyHeight = CGFloat(saved)
        }
    }

    // MARK: - Per-tab sizing

    /// Home's body height as reported by the chat view (answer + composer).
    /// Drives the dynamic panel height: the notch grows just enough to fit the
    /// current answer, capped at half the screen.
    var homeBodyHeight: CGFloat?

    /// Home chrome above/below the body (header row + content paddings).
    private var homeChromeHeight: CGFloat { closedNotchSize.height + 8 + 16 }

    /// Low floor: focus pins ONLY the latest answer and the notch fits it
    /// tightly, so a one-line answer gives a compact panel rather than a tall
    /// empty one. The greeting reports its own comfortable height instead.
    var homeMinHeight: CGFloat { clamp(screenFrame.height * 0.12, 120, 150) }
    var homeMaxHeight: CGFloat { screenFrame.height * 0.5 }
    /// While the user reads history the panel opens up to at least 30% of the
    /// screen — short answers shouldn't force reading through a slot.
    var homeBrowsingHeight: CGFloat { screenFrame.height * 0.30 }

    /// True while the user has scrolled up into history (not pinned to the
    /// latest answer). Set by the chat view.
    var homeBrowsingHistory = false

    /// Each tab expands the notch to its own proportion of the screen.
    func openContentSize(for tab: Tab) -> CGSize {
        let w = screenFrame.width
        let h = screenFrame.height
        switch tab {
        case .home:
            var height = homeBodyHeight.map { clamp($0 + homeChromeHeight, homeMinHeight, homeMaxHeight) }
                ?? homeMinHeight
            if homeBrowsingHistory {
                height = max(height, min(homeBrowsingHeight, homeMaxHeight))
            }
            return CGSize(width: clamp(w * 0.32, 440, 540), height: height)
        case .history:
            return CGSize(width: clamp(w * 0.40, 520, 680), height: clamp(h * 0.34, 240, 400))
        case .settings:
            return CGSize(width: clamp(w * 0.40, 540, 700), height: clamp(h * 0.42, 320, 480))
        case .activity:
            return CGSize(width: clamp(w * 0.56, 620, 960), height: clamp(h * 0.46, 340, 580))
        }
    }

    var currentOpenContentSize: CGSize { openContentSize(for: selectedTab) }

    /// The panel size for a presentation — the single sizing authority. Content
    /// (in NotchView) switches on the same value, so size and content stay locked.
    func size(for presentation: NotchPresentation) -> CGSize {
        switch presentation {
        case .onboarding: onboardingSize
        case .open(let tab): openContentSize(for: tab)
        case .listening(let phase): phase == .review ? listeningReviewSize : listeningSize
        case .peek: listeningSize
        case .meeting: closedStatusSize
        case .working: workingSize     // two lines: holds the verbose status text
        case .idle: closedNotchSize
        }
    }

    /// First-run onboarding size (primary display only).
    var onboardingSize: CGSize {
        CGSize(width: clamp(screenFrame.width * 0.42, 560, 700), height: clamp(screenFrame.height * 0.46, 380, 540))
    }

    /// Compact size shown while listening: waveform flanks the camera on the top
    /// row, the transcript sits on one line BELOW the camera cutout.
    var listeningSize: CGSize {
        CGSize(width: clamp(closedNotchSize.width + NotchMetrics.listeningExtraWidth, 280, 360),
               height: closedNotchSize.height + NotchMetrics.listeningExtraHeight)
    }

    /// Listening size grown for the dictation-review state: the full transcript
    /// plus the send/cancel pair.
    var listeningReviewSize: CGSize {
        CGSize(width: listeningSize.width, height: closedNotchSize.height + NotchMetrics.reviewExtraHeight)
    }

    /// The compact glowing "working" bar: slightly wider than closed and two
    /// lines tall (verbose status below the camera). Shown while the agent is
    /// working, then it expands to the answer.
    var workingSize: CGSize {
        CGSize(width: clamp(closedNotchSize.width + NotchMetrics.workingExtraWidth, 320, 400),
               height: closedNotchSize.height + NotchMetrics.workingExtraHeight)
    }

    /// Slim closed-notch status bar (meeting timer, background-run pulse):
    /// camera-row height only, widened so the flanks can hold an icon + timer.
    var closedStatusSize: CGSize {
        CGSize(width: clamp(closedNotchSize.width + NotchMetrics.statusExtraWidth, 300, 360), height: closedNotchSize.height)
    }

    /// The window is fixed at the largest a tab can ever need; only the inner
    /// content scales, so expansion always originates from the notch. Home can
    /// grow to half the screen, so the window must always allow for it.
    private var maxOpenContentSize: CGSize {
        Tab.allCases.reduce(CGSize(width: 0, height: homeMaxHeight)) { acc, tab in
            let size = openContentSize(for: tab)
            return CGSize(width: max(acc.width, size.width), height: max(acc.height, size.height))
        }
    }

    var windowSize: CGSize {
        CGSize(
            width: maxOpenContentSize.width + NotchMetrics.shadowPadding * 2,
            // Reserve room BELOW the body for the floating glass tray so a
            // max-height answer plus the tray still fits in the fixed window.
            height: maxOpenContentSize.height + NotchMetrics.trayReserve + NotchMetrics.shadowPadding
        )
    }

    /// The visible black region in screen coordinates for the current state —
    /// used for authoritative hover hit-testing (the window itself is larger).
    func visibleRect(open: Bool) -> CGRect {
        let size = open ? currentOpenContentSize : closedNotchSize
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The floating glass tray's region in screen coordinates: directly below
    /// the body, separated by `trayGap`. Union'd with `visibleRect` for the
    /// auto-close hit region so moving onto the composer/Stop never reads as
    /// "left the panel".
    func trayRect(open: Bool) -> CGRect {
        let body = visibleRect(open: open)
        let height = NotchMetrics.trayHeight
        return CGRect(
            x: body.midX - body.width / 2,
            y: body.minY - NotchMetrics.trayGap - height,
            width: body.width,
            height: height
        )
    }

    // MARK: - Window coordination

    func attach(window: NSWindow) {
        self.window = window
        positionWindow()
    }

    func refresh(for screen: NSScreen) {
        screenFrame = screen.frame
        hasPhysicalNotch = screen.safeAreaInsets.top > 0
        closedNotchSize = Self.computeClosedNotchSize(for: screen)
        positionWindow()
    }

    /// Fixed geometry: centered horizontally, pinned to the top. Never animated.
    private func positionWindow() {
        guard let window else { return }
        let size = windowSize
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Open / close

    func open() {
        cancelHoverTasks()
        guard state != .open else { return }
        state = .open
        openedAt = .now
        onStateChange?()
    }

    func close() {
        cancelHoverTasks()
        guard state != .closed else { return }
        state = .closed
        openedAt = nil
        // Persist the settled Home height to seed the next launch's first open.
        if let homeBodyHeight {
            UserDefaults.standard.set(Double(homeBodyHeight), forKey: Self.homeBodyHeightKey)
        }
        onStateChange?()
    }

    /// True while something must stay on screen regardless of the pointer
    /// (a pending approval prompt). Set by the view layer.
    var holdOpen = false

    /// Grace period so the panel can't slam shut right after opening.
    var canAutoClose: Bool {
        guard state == .open, !holdOpen else { return false }
        guard let openedAt else { return true }
        return Date.now.timeIntervalSince(openedAt) > 0.6
    }

    func hoverEntered(delay: TimeInterval = 0.28) {
        guard state == .closed else { return }

        hoverOpenTask?.cancel()
        hoverOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    /// Hover only ever OPENS. Auto-close is owned solely by
    /// NotchScreenManager.pointerMoved (pointer-outside-for-0.75s), so leaving
    /// the hover region here just cancels a still-pending open — it never closes.
    func hoverExited() {
        hoverOpenTask?.cancel()
    }

    func cancelHoverTasks() {
        hoverOpenTask?.cancel()
    }

    deinit {
        hoverOpenTask?.cancel()
    }

    private static func computeClosedNotchSize(for screen: NSScreen) -> CGSize {
        var notchWidth = NotchMetrics.fallbackClosedSize.width
        var notchHeight = NotchMetrics.fallbackClosedSize.height

        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - left - right + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = screen.safeAreaInsets.top
        } else {
            notchHeight = max(30, screen.frame.maxY - screen.visibleFrame.maxY - 1)
        }

        return CGSize(width: notchWidth, height: notchHeight)
    }
}

private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    min(max(value, low), high)
}

extension NSScreen {
    var jarvisDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
