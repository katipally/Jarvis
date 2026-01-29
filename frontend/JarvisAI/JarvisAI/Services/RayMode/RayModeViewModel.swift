import Foundation
import SwiftUI
import Combine
import NaturalLanguage

// MARK: - Intent Classification
enum RayIntent: Equatable {
    case app(name: String)
    case search(query: String)
    case calculate(expression: String)
    case emoji(keyword: String)
    case question(text: String)
    case command(action: String, target: String?)
    case compound(parts: [String])
    case unknown
    
    var category: RayCategory {
        switch self {
        case .app: return .apps
        case .search: return .actions
        case .calculate: return .calculator
        case .emoji: return .emoji
        case .question: return .ai
        case .command: return .actions
        case .compound: return .actions
        case .unknown: return .all
        }
    }
}

// MARK: - Ray Category
enum RayCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case ai = "AI"
    case actions = "Actions"
    case apps = "Apps"
    case calculator = "Calculator"
    case emoji = "Emoji"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .ai: return "sparkles"
        case .actions: return "bolt.fill"
        case .apps: return "app.fill"
        case .calculator: return "equal.circle.fill"
        case .emoji: return "face.smiling"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return Color(red: 0.6, green: 0.6, blue: 0.65)
        case .ai: return Color(red: 0.7, green: 0.4, blue: 1.0) // Bright purple
        case .actions: return Color(red: 1.0, green: 0.6, blue: 0.2) // Bright orange
        case .apps: return Color(red: 0.4, green: 0.7, blue: 1.0) // Bright blue
        case .calculator: return Color(red: 0.3, green: 0.85, blue: 0.6) // Bright green
        case .emoji: return Color(red: 1.0, green: 0.85, blue: 0.3) // Bright yellow
        }
    }
}

// MARK: - Search Result
struct RayResult: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String
    let icon: String?
    var appIcon: NSImage?
    let category: RayCategory
    let action: () -> Void
    var actionSteps: [String]?
    var isAIResult: Bool = false
    var isStreaming: Bool = false
}

// MARK: - Calendar Event (for RayModeView compatibility)
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: Color
    
    var timeString: String {
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: startDate)
    }
}

// MARK: - Clipboard Item (for RayModeView compatibility)
struct ClipboardItem: Identifiable {
    let id = UUID()
    let content: String
    let timestamp: Date
    
    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 50 ? String(trimmed.prefix(50)) + "..." : trimmed
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Ray Mode ViewModel
@MainActor
class RayModeViewModel: ObservableObject {
    // MARK: - Published State
    @Published var searchText = "" {
        didSet { handleSearchTextChange() }
    }
    @Published var results: [RayResult] = []
    @Published var selectedIndex = 0
    @Published var isLoading = false
    @Published var activeCategory: RayCategory = .all
    
    // AI State
    @Published var aiResponse = ""
    @Published var isAIThinking = false
    @Published var aiError: String?
    
    // For RayModeView compatibility
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var clipboardHistory: [ClipboardItem] = []
    
    // MARK: - Private
    private let appManager = AppSearchManager.shared
    private let streamingService = StreamingService()
    private var searchTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var aiTimeoutTask: Task<Void, Never>?
    
    // Debounce
    private var debounceWorkItem: DispatchWorkItem?
    
    // Emoji data
    private let emojis: [(String, String, [String])] = [
        ("😀", "grinning", ["happy", "smile"]),
        ("😂", "joy", ["laugh", "lol", "funny"]),
        ("😍", "heart eyes", ["love"]),
        ("🔥", "fire", ["hot", "lit"]),
        ("👍", "thumbs up", ["yes", "ok", "good"]),
        ("👎", "thumbs down", ["no", "bad"]),
        ("❤️", "heart", ["love"]),
        ("✅", "check", ["done", "yes"]),
        ("❌", "cross", ["no", "wrong"]),
        ("⭐", "star", ["favorite"]),
        ("🚀", "rocket", ["launch", "fast"]),
        ("💡", "bulb", ["idea"]),
        ("🎉", "party", ["celebrate"]),
        ("😎", "cool", ["sunglasses"]),
        ("🤔", "thinking", ["hmm"]),
        ("👏", "clap", ["applause"]),
        ("💪", "muscle", ["strong"]),
        ("🙌", "raised hands", ["hooray"]),
        ("😊", "blush", ["happy"]),
        ("🥳", "party face", ["celebrate"]),
    ]
    
    init() {
        setupStreamingObservers()
    }
    
    // MARK: - Streaming Setup
    private func setupStreamingObservers() {
        streamingService.$currentMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                guard let self = self, self.isAIThinking else { return }
                self.aiResponse = content
                self.updateAIResult()
            }
            .store(in: &cancellables)
        
        streamingService.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streaming in
                guard let self = self else { return }
                if !streaming && self.isAIThinking {
                    self.finalizeAIResult()
                }
            }
            .store(in: &cancellables)
        
        streamingService.$error
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleAIError(error)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Search Text Handler
    private func handleSearchTextChange() {
        debounceWorkItem?.cancel()
        
        guard !searchText.isEmpty else {
            results = []
            selectedIndex = 0
            cancelAI()
            return
        }
        
        // Debounce search
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.performSearch()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    // MARK: - Search
    func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        
        isLoading = true
        var newResults: [RayResult] = []
        
        let intent = classifyIntent(query)
        
        switch intent {
        case .calculate(let expr):
            if let result = evaluate(expr) {
                newResults.append(RayResult(
                    title: result,
                    subtitle: "= \(query)",
                    icon: "equal.circle.fill",
                    category: .calculator,
                    action: { [weak self] in self?.copyToClipboard(result) }
                ))
            }
            newResults.append(contentsOf: searchApps(query))
            
        case .app:
            newResults.append(contentsOf: searchApps(query))
            newResults.append(contentsOf: searchEmojis(query))
            
        case .emoji:
            newResults.append(contentsOf: searchEmojis(query))
            newResults.append(contentsOf: searchApps(query))
            
        case .search(let searchQuery):
            newResults.append(createSearchResult(searchQuery))
            newResults.append(contentsOf: searchApps(query).prefix(3))
            
        case .command(let action, let target):
            newResults.append(createCommandResult(action: action, target: target, query: query))
            newResults.append(contentsOf: searchApps(query).prefix(2))
            
        case .compound(let parts):
            newResults.append(createCompoundResult(parts: parts, query: query))
            
        case .question:
            newResults.append(createAIResult(query))
            newResults.append(contentsOf: searchApps(query).prefix(2))
            
        case .unknown:
            newResults.append(contentsOf: searchApps(query))
            newResults.append(contentsOf: searchEmojis(query))
            if query.count > 10 {
                newResults.append(createAIResult(query))
            }
        }
        
        // Apply category filter
        if activeCategory != .all {
            newResults = newResults.filter { $0.category == activeCategory }
        }
        
        results = newResults
        selectedIndex = 0
        isLoading = false
    }
    
    // MARK: - Intent Classification
    private func classifyIntent(_ query: String) -> RayIntent {
        let lower = query.lowercased().trimmingCharacters(in: .whitespaces)
        let words = lower.split(separator: " ").map(String.init)
        
        guard !words.isEmpty else { return .unknown }
        
        // 1. Pure calculation - only if it's purely numeric/operators
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if isLikelyCalculation(trimmed), let _ = evaluate(trimmed) {
            return .calculate(expression: trimmed)
        }
        
        // 2. Direct question patterns - HIGHEST PRIORITY for natural language
        // Check if it looks like a question (interrogative words, ends with ?)
        if isQuestion(lower, words: words) {
            return .question(text: query)
        }
        
        // 3. Short single-word app/emoji search (1-2 words, looks like app name)
        if words.count <= 2 && lower.count < 20 {
            // Check for emoji keyword first
            if words.count == 1 {
                let emojiMatches = emojis.filter { 
                    $0.1.contains(lower) || $0.2.contains(where: { $0.contains(lower) }) 
                }
                if !emojiMatches.isEmpty {
                    return .emoji(keyword: query)
                }
            }
            
            // Check for app match
            let apps = appManager.search(query: query)
            if !apps.isEmpty {
                // Verify it's a good match (app name starts with query or contains it prominently)
                let bestMatch = apps.first!
                let appNameLower = bestMatch.name.lowercased()
                if appNameLower.hasPrefix(lower) || 
                   appNameLower.contains(lower) ||
                   lower.split(separator: " ").allSatisfy({ appNameLower.contains($0) }) {
                    return .app(name: query)
                }
            }
        }
        
        // 4. Command patterns (open, launch, close, etc.)
        let commandVerbs = ["open", "launch", "start", "close", "quit", "run", "execute"]
        if let firstWord = words.first, commandVerbs.contains(firstWord) {
            let target = words.dropFirst().joined(separator: " ")
            return .command(action: firstWord, target: target.isEmpty ? nil : target)
        }
        
        // 5. Web search patterns
        let searchVerbs = ["search", "google", "find", "look up", "lookup", "search for", "web search"]
        for verb in searchVerbs {
            if lower.hasPrefix(verb + " ") || lower.hasPrefix(verb + " for ") {
                var searchTerm = lower
                searchTerm = searchTerm.replacingOccurrences(of: verb + " for ", with: "")
                searchTerm = searchTerm.replacingOccurrences(of: verb + " ", with: "")
                return .search(query: searchTerm)
            }
        }
        
        // 6. Compound action: "X and Y", "X then Y"
        if lower.contains(" and ") || lower.contains(" then ") {
            let parts = lower.components(separatedBy: " and ")
                .flatMap { $0.components(separatedBy: " then ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return .compound(parts: parts)
            }
        }
        
        // 7. Natural language with 3+ words is likely a question/AI query
        if words.count >= 3 {
            return .question(text: query)
        }
        
        // 8. Fall back to app search for 2-word queries
        if words.count == 2 {
            let apps = appManager.search(query: query)
            if !apps.isEmpty {
                return .app(name: query)
            }
        }
        
        return .unknown
    }
    
    /// Check if the query looks like a calculation
    private func isLikelyCalculation(_ query: String) -> Bool {
        let calcPattern = "^[\\d\\s\\+\\-\\*\\/\\(\\)\\.\\^%]+$"
        guard let regex = try? NSRegularExpression(pattern: calcPattern) else { return false }
        return regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) != nil
    }
    
    /// Determine if the query is a question
    private func isQuestion(_ lower: String, words: [String]) -> Bool {
        // Direct question mark
        if lower.hasSuffix("?") {
            return true
        }
        
        // Question words (interrogatives)
        let questionWords = [
            "what", "how", "why", "when", "where", "who", "which", "whose", "whom"
        ]
        
        // Auxiliary verbs that start questions
        let auxiliaryVerbs = [
            "is", "are", "was", "were", "do", "does", "did",
            "can", "could", "will", "would", "should", "shall", "may", "might",
            "have", "has", "had"
        ]
        
        // Common question phrases
        let questionPhrases = [
            "tell me", "explain", "describe", "help me", "show me",
            "i want to know", "i need to know", "can you", "could you",
            "would you", "please tell", "please explain"
        ]
        
        guard let firstWord = words.first else { return false }
        
        // Check question words
        if questionWords.contains(firstWord) {
            return true
        }
        
        // Check auxiliary verbs followed by subject (is X, can you, etc.)
        if auxiliaryVerbs.contains(firstWord) && words.count > 1 {
            return true
        }
        
        // Check question phrases
        for phrase in questionPhrases {
            if lower.hasPrefix(phrase) {
                return true
            }
        }
        
        // Natural language heuristic: 4+ words often indicates a question/request
        if words.count >= 4 {
            // Check if it contains common question indicators
            let questionIndicators = ["about", "meaning", "definition", "difference", "between", "work", "works"]
            if questionIndicators.contains(where: { lower.contains($0) }) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Search Helpers
    private func searchApps(_ query: String) -> [RayResult] {
        appManager.search(query: query).prefix(8).map { app in
            let appCopy = app
            return RayResult(
                title: app.name,
                subtitle: app.isRunning ? "Running" : "Application",
                icon: nil,
                appIcon: app.icon,
                category: .apps,
                action: {
                    Task { @MainActor in
                        _ = await AppSearchManager.shared.launchApp(appCopy)
                    }
                }
            )
        }
    }
    
    private func searchEmojis(_ query: String) -> [RayResult] {
        let lower = query.lowercased()
        return emojis.filter { emoji in
            emoji.1.contains(lower) || emoji.2.contains(where: { $0.contains(lower) })
        }.prefix(6).map { emoji in
            let char = emoji.0
            return RayResult(
                title: emoji.0,
                subtitle: emoji.1.capitalized,
                icon: nil,
                category: .emoji,
                action: { [weak self] in self?.copyToClipboard(char) }
            )
        }
    }
    
    private func createSearchResult(_ query: String) -> RayResult {
        return RayResult(
            title: "Search: \(query)",
            subtitle: "Search the web",
            icon: "magnifyingglass",
            category: .actions,
            action: { [weak self] in self?.webSearch(query) },
            actionSteps: ["🌐 Open browser", "🔍 Search \"\(query)\""]
        )
    }
    
    private func createCommandResult(action: String, target: String?, query: String) -> RayResult {
        let title: String
        let steps: [String]
        
        switch action {
        case "open", "launch", "start":
            title = "Open \(target?.capitalized ?? "App")"
            steps = ["🚀 Launch \(target?.capitalized ?? "application")"]
        case "close", "quit":
            title = "Close \(target?.capitalized ?? "App")"
            steps = ["❌ Quit \(target?.capitalized ?? "application")"]
        default:
            title = "\(action.capitalized) \(target ?? "")"
            steps = ["⚡ Execute action"]
        }
        
        return RayResult(
            title: title,
            subtitle: "Command",
            icon: "bolt.fill",
            category: .actions,
            action: { [weak self] in
                guard let target = target else { return }
                Task { @MainActor in
                    await self?.executeCommand(action: action, target: target)
                }
            },
            actionSteps: steps
        )
    }
    
    private func createCompoundResult(parts: [String], query: String) -> RayResult {
        var steps: [String] = []
        for (i, part) in parts.enumerated() {
            steps.append("\(i + 1). \(part.capitalized)")
        }
        
        return RayResult(
            title: "Multi-Step Action",
            subtitle: "\(parts.count) steps",
            icon: "bolt.fill",
            category: .actions,
            action: { [weak self] in
                Task { @MainActor in
                    await self?.executeCompound(parts: parts)
                }
            },
            actionSteps: steps
        )
    }
    
    private func createAIResult(_ query: String) -> RayResult {
        return RayResult(
            title: "Ask Jarvis",
            subtitle: "Press Enter for AI answer",
            icon: "sparkles",
            category: .ai,
            action: { [weak self] in
                Task { @MainActor in
                    await self?.triggerAI(query: query)
                }
            },
            isAIResult: true,
            isStreaming: false
        )
    }
    
    // MARK: - Execute Actions
    private func executeCommand(action: String, target: String) async {
        switch action {
        case "open", "launch", "start":
            let apps = appManager.search(query: target)
            if let app = apps.first {
                _ = await appManager.launchApp(app)
            }
        case "close", "quit":
            let script = "tell application \"\(target)\" to quit"
            runAppleScript(script)
        default:
            break
        }
    }
    
    private func executeCompound(parts: [String]) async {
        for part in parts {
            let intent = classifyIntent(part)
            switch intent {
            case .command(let action, let target):
                if let t = target {
                    await executeCommand(action: action, target: t)
                }
            case .search(let query):
                webSearch(query)
            case .app(let name):
                let apps = appManager.search(query: name)
                if let app = apps.first {
                    _ = await appManager.launchApp(app)
                }
            default:
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    private func webSearch(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func runAppleScript(_ script: String) {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }
    
    // MARK: - AI
    func triggerAI(query: String) async {
        // Cancel any existing AI task
        cancelAI()
        
        // Don't trigger if query is too short
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        
        isAIThinking = true
        aiResponse = ""
        aiError = nil
        
        // Create AI result if not present
        if results.firstIndex(where: { $0.isAIResult }) == nil {
            results.insert(createAIResult(query), at: 0)
            selectedIndex = 0
        }
        
        // Mark AI result as streaming
        if let idx = results.firstIndex(where: { $0.isAIResult }) {
            results[idx].isStreaming = true
            results[idx].subtitle = "Thinking..."
        }
        
        // Get conversation context (last 3 messages for context)
        let history = SharedChatViewModel.shared.viewModel.messages.suffix(3).map {
            ["role": $0.role.rawValue, "content": $0.content]
        }
        
        // Create a timeout task
        aiTask = Task {
            // Start a timeout timer
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                if !Task.isCancelled && isAIThinking && aiResponse.isEmpty {
                    handleAIError("Request timed out. Press Tab to try in full chat.")
                }
            }
            
            await streamingService.sendMessage(query, fileIds: [], conversationHistory: history)
            
            timeoutTask.cancel()
        }
        
        await aiTask?.value
    }
    
    private func updateAIResult() {
        guard let idx = results.firstIndex(where: { $0.isAIResult }) else { return }
        
        let preview = aiResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            results[idx].subtitle = preview.count > 80 ? String(preview.prefix(80)) + "..." : preview
        } else {
            results[idx].subtitle = "Generating..."
        }
        results[idx].isStreaming = true
    }
    
    private func finalizeAIResult() {
        isAIThinking = false
        
        guard let idx = results.firstIndex(where: { $0.isAIResult }) else { return }
        
        let preview = aiResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty {
            results[idx].subtitle = "No response received. Press Tab for full chat."
        } else {
            results[idx].subtitle = preview.count > 80 ? String(preview.prefix(80)) + "..." : preview
        }
        results[idx].isStreaming = false
    }
    
    private func handleAIError(_ error: String) {
        aiError = error
        isAIThinking = false
        
        if let idx = results.firstIndex(where: { $0.isAIResult }) {
            results[idx].subtitle = "⚠️ \(error)"
            results[idx].isStreaming = false
        }
    }
    
    func cancelAI() {
        aiTask?.cancel()
        aiTask = nil
        streamingService.cancelStreaming()
        isAIThinking = false
    }
    
    // MARK: - Calculator
    private func evaluate(_ expr: String) -> String? {
        let pattern = "^[\\d\\s\\+\\-\\*\\/\\(\\)\\.\\^%]+$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)) != nil else {
            return nil
        }
        
        let sanitized = expr.replacingOccurrences(of: "^", with: "**")
            .replacingOccurrences(of: "%", with: "/100*")
        
        // NSExpression(format:) doesn't throw, it returns nil for invalid expressions
        guard let nsExpr = NSExpression(format: sanitized) as NSExpression?,
              let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }
        
        let val = result.doubleValue
        if val == floor(val) && abs(val) < Double(Int.max) {
            return String(Int(val))
        }
        return String(format: "%.6g", val)
    }
    
    // MARK: - Navigation
    func selectNext() {
        if selectedIndex < results.count - 1 {
            selectedIndex += 1
        }
    }
    
    func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
    
    func executeSelected() {
        guard selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        
        // For AI result, trigger AI first if no response yet
        if result.isAIResult && aiResponse.isEmpty && !isAIThinking {
            Task { await triggerAI(query: searchText) }
        } else if result.isAIResult && !aiResponse.isEmpty {
            copyToClipboard(aiResponse)
        } else {
            result.action()
        }
    }
    
    func selectByIndex(_ index: Int) {
        guard index >= 0 && index < results.count else { return }
        selectedIndex = index
        executeSelected()
    }
    
    func copySelectedToClipboard() {
        guard selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        
        if result.isAIResult && !aiResponse.isEmpty {
            copyToClipboard(aiResponse)
        } else if result.category == .calculator {
            copyToClipboard(result.title)
        } else if result.category == .emoji {
            copyToClipboard(result.title)
        }
    }
    
    func openInChat() {
        guard !searchText.isEmpty else { return }
        SharedChatViewModel.shared.viewModel.inputText = searchText
        NotificationCenter.default.post(name: NSNotification.Name("OpenFocusMode"), object: nil)
        AppDelegate.shared?.closeRayPanel()
        
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await SharedChatViewModel.shared.viewModel.sendMessage()
        }
    }
    
    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    // MARK: - Reset
    func reset() {
        searchText = ""
        results = []
        selectedIndex = 0
        cancelAI()
        aiResponse = ""
        aiError = nil
    }
    
    // MARK: - Window Management (for RayModeView)
    func snapWindowLeft() { executeWindowSnap(.left) }
    func snapWindowRight() { executeWindowSnap(.right) }
    func snapWindowTop() { executeWindowSnap(.top) }
    func maximizeWindow() { executeWindowSnap(.maximize) }
    
    private func executeWindowSnap(_ position: WindowSnapPosition) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        var targetFrame: CGRect
        
        switch position {
        case .left:
            targetFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .right:
            targetFrame = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .top:
            targetFrame = CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: frame.height / 2)
        case .maximize:
            targetFrame = frame
        }
        
        runAppleScript("""
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            set frontWindow to first window of frontApp
            set position of frontWindow to {\(Int(targetFrame.minX)), \(Int(screen.frame.maxY - targetFrame.maxY))}
            set size of frontWindow to {\(Int(targetFrame.width)), \(Int(targetFrame.height))}
        end tell
        """)
    }
    
    // MARK: - Clipboard (for RayModeView)
    func pasteFromHistory(_ item: ClipboardItem) {
        copyToClipboard(item.content)
    }
}

enum WindowSnapPosition {
    case left, right, top, maximize
}
