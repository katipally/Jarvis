import AppKit
import Observation

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
    var selectedTab: Tab = .home
    private(set) var closedNotchSize: CGSize
    private(set) var screenFrame: CGRect
    let displayID: CGDirectDisplayID
    private(set) var hasPhysicalNotch: Bool

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var openedAt: Date?
    @ObservationIgnored private var hoverOpenTask: Task<Void, Never>?
    @ObservationIgnored private var hoverCloseTask: Task<Void, Never>?

    static let shadowPadding: CGFloat = 22

    init(screen: NSScreen) {
        displayID = screen.jarvisDisplayID
        screenFrame = screen.frame
        hasPhysicalNotch = screen.safeAreaInsets.top > 0
        closedNotchSize = Self.computeClosedNotchSize(for: screen)
    }

    // MARK: - Per-tab sizing

    /// Home's body height as reported by the chat view (answer + composer).
    /// Drives the dynamic panel height: the notch grows just enough to fit the
    /// current answer, capped at half the screen.
    var homeBodyHeight: CGFloat?

    /// Home chrome above/below the body (header row + content paddings).
    private var homeChromeHeight: CGFloat { closedNotchSize.height + 8 + 26 }

    /// Low floor: a one-line answer should give a compact panel, not a tall
    /// empty one; the greeting reports its own comfortable height instead.
    var homeMinHeight: CGFloat { clamp(screenFrame.height * 0.16, 150, 200) }
    var homeMaxHeight: CGFloat { screenFrame.height * 0.5 }

    /// Each tab expands the notch to its own proportion of the screen.
    func openContentSize(for tab: Tab) -> CGSize {
        let w = screenFrame.width
        let h = screenFrame.height
        switch tab {
        case .home:
            let height = homeBodyHeight.map { clamp($0 + homeChromeHeight, homeMinHeight, homeMaxHeight) }
                ?? homeMinHeight
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

    /// First-run onboarding size (primary display only).
    var onboardingSize: CGSize {
        CGSize(width: clamp(screenFrame.width * 0.42, 560, 700), height: clamp(screenFrame.height * 0.46, 380, 540))
    }

    /// Compact size shown while listening: waveform flanks the camera on the top
    /// row, the transcript sits on one line BELOW the camera cutout.
    var listeningSize: CGSize {
        CGSize(width: clamp(closedNotchSize.width + 200, 340, 400), height: closedNotchSize.height + 26)
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
            width: maxOpenContentSize.width + Self.shadowPadding * 2,
            height: maxOpenContentSize.height + Self.shadowPadding
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
    }

    func close() {
        cancelHoverTasks()
        guard state != .closed else { return }
        state = .closed
        openedAt = nil
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

    var pointerIsInsideVisibleRegion: Bool {
        visibleRect(open: state == .open).insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation)
    }

    func hoverEntered(delay: TimeInterval = 0.28) {
        hoverCloseTask?.cancel()
        guard state == .closed else { return }

        hoverOpenTask?.cancel()
        hoverOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    func hoverExited(delay: TimeInterval = 0.15) {
        hoverOpenTask?.cancel()
        guard state == .open else { return }

        hoverCloseTask?.cancel()
        hoverCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  self.canAutoClose, !self.pointerIsInsideVisibleRegion else { return }
            self.close()
        }
    }

    func cancelHoverTasks() {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
    }

    deinit {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
    }

    private static func computeClosedNotchSize(for screen: NSScreen) -> CGSize {
        var notchWidth: CGFloat = 185
        var notchHeight: CGFloat = 32

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
