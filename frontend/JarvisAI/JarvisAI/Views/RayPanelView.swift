import SwiftUI
import AppKit

// MARK: - Ray Panel View
struct RayPanelView: View {
    @StateObject private var viewModel = RayModeViewModel()
    @State private var panelHeight: CGFloat = 72
    @State private var runningApps: [SearchableApp] = []
    
    let onDismiss: () -> Void
    
    private let searchBarHeight: CGFloat = 72
    private let maxHeight: CGFloat = 520
    private let width: CGFloat = 680
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Divider
            if hasContent {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
            
            // Content
            if viewModel.searchText.isEmpty {
                idleContent
            } else if !viewModel.results.isEmpty {
                resultsContent
            } else if viewModel.isLoading {
                loadingContent
            }
        }
        .frame(width: width, height: panelHeight)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .onAppear {
            runningApps = AppSearchManager.shared.getRunningApps()
            updateHeight()
        }
        .onChange(of: viewModel.searchText) { _ in updateHeight() }
        .onChange(of: viewModel.results.count) { _ in updateHeight() }
        .onChange(of: viewModel.selectedIndex) { _ in updateHeight() }
        .onChange(of: viewModel.aiResponse) { _ in updateHeight() }
        .onChange(of: viewModel.isAIThinking) { _ in updateHeight() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RayPanelOpened"))) { _ in
            viewModel.reset()
            runningApps = AppSearchManager.shared.getRunningApps()
            updateHeight()
        }
    }
    
    // MARK: - Background
    private var backgroundView: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(0.03),
                    Color.clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 14) {
            // Icon with animation
            SearchIcon(isThinking: viewModel.isAIThinking)
                .frame(width: 24)
            
            // Text field
            RaySearchField(
                text: $viewModel.searchText,
                viewModel: viewModel,
                onDismiss: onDismiss
            )
            
            // Clear button
            if !viewModel.searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        viewModel.searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Shortcut hint
            Text("⌥Space")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .padding(.horizontal, 18)
        .frame(height: searchBarHeight)
    }
    
    // MARK: - Helpers
    private var hasContent: Bool {
        !viewModel.searchText.isEmpty || !runningApps.isEmpty
    }
    
    private func updateHeight() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            panelHeight = calculateHeight()
        }
    }
    
    private func calculateHeight() -> CGFloat {
        if viewModel.searchText.isEmpty {
            return runningApps.isEmpty ? searchBarHeight : searchBarHeight + 110
        } else if viewModel.results.isEmpty {
            return viewModel.isLoading ? searchBarHeight + 56 : searchBarHeight
        } else {
            var h = searchBarHeight + 16 // Base + top padding
            
            for (i, result) in viewModel.results.prefix(7).enumerated() {
                h += 58 // Row height
                
                // Extra for expanded content when selected
                if i == viewModel.selectedIndex {
                    // Action steps
                    if let steps = result.actionSteps {
                        h += CGFloat(steps.count * 26 + 12)
                    }
                    
                    // AI response
                    if result.isAIResult {
                        if viewModel.isAIThinking {
                            h += 50 // Loading state
                        } else if !viewModel.aiResponse.isEmpty {
                            // Calculate text height
                            let lineCount = max(1, min(6, viewModel.aiResponse.components(separatedBy: "\n").count))
                            h += CGFloat(lineCount * 18 + 80) // Text + buttons
                        }
                    }
                }
            }
            
            h += 8 // Bottom padding
            return min(maxHeight, h)
        }
    }
    
    // MARK: - Idle Content
    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !runningApps.isEmpty {
                Text("RUNNING")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(runningApps.prefix(8).enumerated()), id: \.element.id) { idx, app in
                            RunningAppButton(app: app, index: idx) {
                                Task {
                                    _ = await AppSearchManager.shared.launchApp(app)
                                    onDismiss()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
            }
        }
    }
    
    // MARK: - Results Content
    private var resultsContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.results.prefix(7).enumerated()), id: \.element.id) { idx, result in
                        SearchResultRow(
                            result: result,
                            index: idx,
                            isSelected: idx == viewModel.selectedIndex,
                            viewModel: viewModel,
                            onSelect: {
                                viewModel.selectedIndex = idx
                                viewModel.executeSelected()
                                if !result.isAIResult {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        onDismiss()
                                    }
                                }
                            },
                            onOpenChat: {
                                viewModel.openInChat()
                                onDismiss()
                            }
                        )
                        .id(idx)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
            .onChange(of: viewModel.selectedIndex) { idx in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Loading Content
    private var loadingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white.opacity(0.6))
            Text("Searching...")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 56)
    }
}

// MARK: - Search Field (NSViewRepresentable)
struct RaySearchField: NSViewRepresentable {
    @Binding var text: String
    let viewModel: RayModeViewModel
    let onDismiss: () -> Void
    
    func makeNSView(context: Context) -> RayTextField {
        let textField = RayTextField()
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        return textField
    }
    
    func updateNSView(_ textField: RayTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        context.coordinator.viewModel = viewModel
        context.coordinator.onDismiss = onDismiss
        context.coordinator.textBinding = $text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, viewModel: viewModel, onDismiss: onDismiss)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, NSTextFieldDelegate {
        var textBinding: Binding<String>
        var viewModel: RayModeViewModel
        var onDismiss: () -> Void
        
        init(text: Binding<String>, viewModel: RayModeViewModel, onDismiss: @escaping () -> Void) {
            self.textBinding = text
            self.viewModel = viewModel
            self.onDismiss = onDismiss
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                textBinding.wrappedValue = textField.stringValue
            }
        }
        
        // Number key codes (not consecutive on macOS)
        private static let numberKeyCodes: [UInt16: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
        ]
        
        // Handle special keys
        @MainActor
        func handleKey(_ keyCode: UInt16, command: Bool) -> Bool {
            // Command shortcuts
            if command {
                // ⌘C - Copy
                if keyCode == 8 {
                    viewModel.copySelectedToClipboard()
                    return true
                }
                
                // ⌘1-9 - Quick select
                if let num = Self.numberKeyCodes[keyCode] {
                    if num >= 1 && num <= min(9, viewModel.results.count) {
                        viewModel.selectedIndex = num - 1
                        viewModel.executeSelected()
                        if num - 1 < viewModel.results.count && !viewModel.results[num - 1].isAIResult {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                self.onDismiss()
                            }
                        }
                        return true
                    }
                }
            }
            
            // Regular keys
            switch keyCode {
            case 125: // Down arrow
                viewModel.selectNext()
                return true
            case 126: // Up arrow
                viewModel.selectPrevious()
                return true
            case 53: // Escape
                onDismiss()
                return true
            case 36: // Return/Enter
                if viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
                    // No results - trigger AI
                    Task { @MainActor in
                        await viewModel.triggerAI(query: viewModel.searchText)
                    }
                } else {
                    viewModel.executeSelected()
                    if viewModel.selectedIndex < viewModel.results.count {
                        let result = viewModel.results[viewModel.selectedIndex]
                        if !result.isAIResult {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                self.onDismiss()
                            }
                        }
                    }
                }
                return true
            case 48: // Tab
                viewModel.openInChat()
                onDismiss()
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Custom Text Field
class RayTextField: NSTextField {
    weak var coordinator: RaySearchField.Coordinator?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 20, weight: .light)
        textColor = .white
        placeholderAttributedString = NSAttributedString(
            string: "Ask Jarvis anything...",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 20, weight: .light)
            ]
        )
    }
    
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        if mods.contains(.command) {
            let result = coordinator?.handleKey(event.keyCode, command: true) ?? false
            if result { return true }
        }
        
        return super.performKeyEquivalent(with: event)
    }
    
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = mods.contains(.command)
        
        if coordinator?.handleKey(event.keyCode, command: isCommand) == true {
            return
        }
        
        super.keyDown(with: event)
    }
    
    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            _ = coordinator?.handleKey(36, command: false) // Return
            return
        }
        if selector == #selector(NSResponder.insertTab(_:)) {
            _ = coordinator?.handleKey(48, command: false) // Tab
            return
        }
        if selector == #selector(NSResponder.moveUp(_:)) {
            _ = coordinator?.handleKey(126, command: false) // Up
            return
        }
        if selector == #selector(NSResponder.moveDown(_:)) {
            _ = coordinator?.handleKey(125, command: false) // Down
            return
        }
        super.doCommand(by: selector)
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in
            if let editor = self?.currentEditor() {
                editor.selectedRange = NSRange(location: self?.stringValue.count ?? 0, length: 0)
            }
        }
        return result
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let result: RayResult
    let index: Int
    let isSelected: Bool
    let viewModel: RayModeViewModel
    let onSelect: () -> Void
    let onOpenChat: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // Main row
                mainRow
                
                // Expanded content (when selected)
                if isSelected {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = h
            }
        }
    }
    
    // MARK: - Main Row
    private var mainRow: some View {
        HStack(spacing: 12) {
            // Icon
            resultIcon
            
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.category == .emoji ? result.subtitle : result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.95))
                        .lineLimit(1)
                    
                    // Streaming indicator
                    if result.isAIResult && viewModel.isAIThinking {
                        ThinkingDots()
                    }
                }
                
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        result.isAIResult && viewModel.isAIThinking 
                            ? result.category.color.opacity(0.8)
                            : .white.opacity(0.55)
                    )
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            // Right side info
            HStack(spacing: 6) {
                // Category badge - always visible with good contrast
                Text(result.category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(result.category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(result.category.color.opacity(0.2))
                            .overlay(
                                Capsule()
                                    .strokeBorder(result.category.color.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                
                // Shortcut badge - always visible with clear styling
                if index < 9 {
                    HStack(spacing: 2) {
                        Text("⌘")
                            .font(.system(size: 9, weight: .medium))
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0.1), lineWidth: 0.5)
                            )
                    )
                }
                
                // Enter indicator when selected
                if isSelected {
                    HStack(spacing: 3) {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Enter")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.green.opacity(0.2))
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    // MARK: - Expanded Content
    @ViewBuilder
    private var expandedContent: some View {
        // Action steps
        if let steps = result.actionSteps {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(spacing: 10) {
                        // Step number
                        Text("\(idx + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(result.category.color)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(result.category.color.opacity(0.2))
                            )
                        
                        Text(step)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .padding(.leading, 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(result.category.color.opacity(0.05))
                    .padding(.horizontal, 14)
            )
        }
        
        // AI Response
        if result.isAIResult {
            aiResponseSection
        }
    }
    
    // MARK: - AI Response Section
    @ViewBuilder
    private var aiResponseSection: some View {
        let aiColor = result.category.color
        
        if viewModel.isAIThinking && viewModel.aiResponse.isEmpty {
            // Loading state
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(aiColor)
                Text("Jarvis is thinking...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(aiColor.opacity(0.9))
                
                Spacer()
                
                // Tab hint
                HStack(spacing: 3) {
                    Text("Tab")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    Text("for full chat")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .padding(.leading, 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(aiColor.opacity(0.08))
                    .padding(.horizontal, 14)
            )
        } else if !viewModel.aiResponse.isEmpty {
            // Response content
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(aiColor.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                
                // Response text
                Text(viewModel.aiResponse)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(6)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.leading, 36)
                    .textSelection(.enabled)
                
                // Action buttons
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Copy button
                    Button {
                        viewModel.copyToClipboard(viewModel.aiResponse)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("Copy")
                            Text("⌘C")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Open in Chat button
                    Button(action: onOpenChat) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                            Text("Full Chat")
                            Text("Tab")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(aiColor.opacity(0.8))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(aiColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(aiColor.opacity(0.2))
                                .overlay(Capsule().strokeBorder(aiColor.opacity(0.3), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }
    
    // MARK: - Helpers
    private var subtitleText: String {
        if result.category == .emoji {
            return "Emoji"
        }
        if result.isAIResult && viewModel.isAIThinking {
            return "Thinking..."
        }
        if result.isAIResult && !viewModel.aiResponse.isEmpty && !isSelected {
            let preview = viewModel.aiResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.count > 60 ? String(preview.prefix(60)) + "..." : preview
        }
        return result.subtitle
    }
    
    @ViewBuilder
    private var resultIcon: some View {
        if let appIcon = result.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if result.category == .emoji {
            Text(result.title)
                .font(.system(size: 28))
                .frame(width: 36, height: 36)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                result.category.color.opacity(0.35),
                                result.category.color.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(result.category.color.opacity(0.4), lineWidth: 0.5)
                    )
                
                Image(systemName: result.icon ?? result.category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(result.category.color)
            }
        }
    }
    
    private var rowBackground: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                result.category.color.opacity(0.15),
                                result.category.color.opacity(0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(result.category.color.opacity(0.25), lineWidth: 1)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            }
        }
    }
}

// MARK: - Running App Button
struct RunningAppButton: View {
    let app: SearchableApp
    let index: Int
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                    
                    // Running indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                        .offset(x: 2, y: 2)
                }
                
                Text(app.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovered = h
            }
        }
    }
}

// MARK: - Search Icon (with AI animation)
struct SearchIcon: View {
    let isThinking: Bool
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var glowOpacity: CGFloat = 0.3
    
    private let aiColor = Color(red: 0.7, green: 0.4, blue: 1.0)
    
    var body: some View {
        ZStack {
            if isThinking {
                // Glow effect
                Circle()
                    .fill(aiColor.opacity(glowOpacity))
                    .frame(width: 32, height: 32)
                    .blur(radius: 8)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.4, blue: 1.0),
                                Color(red: 0.5, green: 0.6, blue: 1.0),
                                Color(red: 0.7, green: 0.4, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(scale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            scale = 1.2
                            glowOpacity = 0.6
                        }
                    }
                    .onDisappear {
                        scale = 1.0
                        glowOpacity = 0.3
                    }
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Thinking Dots Animation
struct ThinkingDots: View {
    @State private var animate = false
    let color: Color
    
    init(color: Color = Color(red: 0.7, green: 0.4, blue: 1.0)) {
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.opacity(0.6)
        RayPanelView(onDismiss: {})
    }
    .frame(width: 800, height: 600)
}
