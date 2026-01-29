import Foundation
import AppKit
import Combine

@MainActor
class AppSearchManager: ObservableObject {
    static let shared = AppSearchManager()
    
    @Published var installedApps: [SearchableApp] = []
    @Published var isLoading = false
    
    private var appCache: [String: SearchableApp] = [:]
    private let workspace = NSWorkspace.shared
    
    private init() {
        Task {
            await loadInstalledApps()
        }
    }
    
    // MARK: - Load All Installed Apps
    func loadInstalledApps() async {
        isLoading = true
        defer { isLoading = false }
        
        var apps: [SearchableApp] = []
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        for path in searchPaths {
            let foundApps = await scanDirectory(path)
            apps.append(contentsOf: foundApps)
        }
        
        // Remove duplicates by bundle identifier
        var seen = Set<String>()
        apps = apps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return true }
            if seen.contains(bundleId) { return false }
            seen.insert(bundleId)
            return true
        }
        
        // Sort by name
        apps.sort { $0.name.lowercased() < $1.name.lowercased() }
        
        // Cache apps
        for app in apps {
            if let bundleId = app.bundleIdentifier {
                appCache[bundleId] = app
            }
        }
        
        installedApps = apps
        print("[AppSearchManager] Loaded \(apps.count) applications")
    }
    
    private func scanDirectory(_ path: String) async -> [SearchableApp] {
        var apps: [SearchableApp] = []
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return apps
        }
        
        for item in contents {
            if item.hasSuffix(".app") {
                let appPath = (path as NSString).appendingPathComponent(item)
                if let app = createSearchableApp(from: appPath) {
                    apps.append(app)
                }
            }
        }
        
        return apps
    }
    
    private func createSearchableApp(from path: String) -> SearchableApp? {
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url) else { return nil }
        
        let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let bundleId = bundle.bundleIdentifier
        let icon = workspace.icon(forFile: path)
        
        return SearchableApp(
            name: name,
            path: path,
            bundleIdentifier: bundleId,
            icon: icon
        )
    }
    
    // MARK: - Spotlight-style Search
    func search(query: String) -> [SearchableApp] {
        guard !query.isEmpty else { return [] }
        
        let lowercasedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Score and filter apps using multiple matching strategies
        var scoredApps: [(app: SearchableApp, score: Double)] = []
        
        for app in installedApps {
            let score = calculateSpotlightScore(query: lowercasedQuery, app: app)
            if score > 0 {
                scoredApps.append((app, score))
            }
        }
        
        // Sort by score (higher is better), then by name
        scoredApps.sort { 
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.app.name < $1.app.name
        }
        
        // Return more results like Spotlight does
        return scoredApps.prefix(20).map { $0.app }
    }
    
    private func calculateSpotlightScore(query: String, app: SearchableApp) -> Double {
        let name = app.name.lowercased()
        let bundleId = app.bundleIdentifier?.lowercased() ?? ""
        
        var score: Double = 0
        
        // 1. Exact match - highest priority (like Spotlight)
        if name == query {
            return 10000
        }
        
        // 2. Starts with query - very high priority
        if name.hasPrefix(query) {
            score = 9000 + Double(100 - min(name.count, 100))
            // Boost running apps
            if app.isRunning { score += 500 }
            return score
        }
        
        // 3. Word boundary match (e.g., "code" matches "Visual Studio Code")
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        for (index, word) in words.enumerated() {
            if word.hasPrefix(query) {
                // Earlier word matches score higher
                score = max(score, 8000 - Double(index * 100) + Double(100 - min(word.count, 100)))
            }
            if word == query {
                score = max(score, 8500 - Double(index * 50))
            }
        }
        if score > 0 {
            if app.isRunning { score += 500 }
            return score
        }
        
        // 4. Contains query as substring
        if name.contains(query) {
            if let range = name.range(of: query) {
                let position = name.distance(from: name.startIndex, to: range.lowerBound)
                score = 7000 - Double(position * 10) + Double(100 - min(name.count, 100))
            }
            if app.isRunning { score += 500 }
            return score
        }
        
        // 5. Acronym match (e.g., "vsc" matches "Visual Studio Code")
        let acronym = words.compactMap { $0.first }.map { String($0) }.joined()
        if acronym.hasPrefix(query) || acronym.contains(query) {
            score = 6000 + Double(100 - min(acronym.count, 100))
            if app.isRunning { score += 500 }
            return score
        }
        
        // 6. Bundle ID match (e.g., "chrome" matches "com.google.Chrome")
        if bundleId.contains(query) {
            score = 5000
            if app.isRunning { score += 500 }
            return score
        }
        
        // 7. Advanced fuzzy match with gap penalty
        let fuzzyScore = calculateAdvancedFuzzyScore(query: query, target: name)
        if fuzzyScore > 0 {
            score = 1000 + fuzzyScore
            if app.isRunning { score += 500 }
            return score
        }
        
        // 8. Levenshtein distance for typo tolerance (only for short queries)
        if query.count >= 3 && query.count <= 8 {
            let distance = levenshteinDistance(query, name.prefix(query.count + 2).lowercased())
            if distance <= 2 {
                score = 500 - Double(distance * 100)
                if app.isRunning { score += 500 }
                return score
            }
        }
        
        return 0
    }
    
    private func calculateAdvancedFuzzyScore(query: String, target: String) -> Double {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var score: Double = 0
        var consecutiveMatches = 0
        var lastMatchWasConsecutive = false
        
        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                // Base score for match
                score += 10
                
                // Bonus for consecutive matches
                if lastMatchWasConsecutive {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches * 5)
                } else {
                    consecutiveMatches = 1
                }
                lastMatchWasConsecutive = true
                
                // Bonus for matching at word boundary
                if targetIndex == target.startIndex {
                    score += 15
                } else {
                    let prevIndex = target.index(before: targetIndex)
                    let prevChar = target[prevIndex]
                    if !prevChar.isLetter && !prevChar.isNumber {
                        score += 10
                    } else if prevChar.isLowercase && target[targetIndex].isUppercase {
                        score += 10 // camelCase boundary
                    }
                }
                
                queryIndex = query.index(after: queryIndex)
            } else {
                lastMatchWasConsecutive = false
                // Small penalty for gaps
                score -= 1
            }
            targetIndex = target.index(after: targetIndex)
        }
        
        // All query characters must be found
        guard queryIndex == query.endIndex else { return 0 }
        
        // Bonus for shorter targets (more relevant)
        score += Double(max(0, 50 - target.count))
        
        return max(0, score)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    // MARK: - Launch App
    func launchApp(_ app: SearchableApp) async -> Bool {
        let url = URL(fileURLWithPath: app.path)
        
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await workspace.openApplication(at: url, configuration: config)
            return true
        } catch {
            print("[AppSearchManager] Failed to launch \(app.name): \(error)")
            return false
        }
    }
    
    // MARK: - Get Running Apps
    func getRunningApps() -> [SearchableApp] {
        return workspace.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { runningApp -> SearchableApp? in
                guard let bundleId = runningApp.bundleIdentifier,
                      let bundleURL = runningApp.bundleURL else { return nil }
                
                // Use cached app if available
                if let cached = appCache[bundleId] {
                    return SearchableApp(
                        name: cached.name,
                        path: cached.path,
                        bundleIdentifier: bundleId,
                        icon: cached.icon,
                        isRunning: true
                    )
                }
                
                let name = runningApp.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
                let icon = workspace.icon(forFile: bundleURL.path)
                
                return SearchableApp(
                    name: name,
                    path: bundleURL.path,
                    bundleIdentifier: bundleId,
                    icon: icon,
                    isRunning: true
                )
            }
    }
    
    // MARK: - Get All Apps
    func getAllApps() -> [SearchableApp] {
        return installedApps
    }
    
    // MARK: - Refresh
    func refresh() async {
        await loadInstalledApps()
    }
}

// MARK: - Searchable App Model
struct SearchableApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let bundleIdentifier: String?
    let icon: NSImage
    var isRunning: Bool = false
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SearchableApp, rhs: SearchableApp) -> Bool {
        lhs.id == rhs.id
    }
}
