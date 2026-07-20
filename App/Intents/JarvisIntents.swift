import AppIntents

/// Bridge so AppIntents (Siri / Spotlight / Shortcuts) can reach the running
/// assistant. AppDelegate installs `answer` once the app is set up; the intent
/// calls it for a one-shot, memory-grounded reply — no tools, no notch UI.
@MainActor
final class JarvisIntentBridge {
    static let shared = JarvisIntentBridge()
    var answer: ((String) async -> String)?
    private init() {}
}

/// "Ask Jarvis <question>" — the always-available way in, so Jarvis isn't gated
/// behind the notch. Runs in-process when the app is already resident.
struct AskJarvisIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Jarvis"
    static let description = IntentDescription(
        "Ask Jarvis a question and get an answer grounded in your memory."
    )
    // Keep it a background answer — don't yank focus into the notch.
    static let openAppWhenRun = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask Jarvis?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let answer = JarvisIntentBridge.shared.answer else {
            return .result(dialog: "Jarvis is still starting up — try again in a moment.")
        }
        let reply = await answer(question)
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

/// Registers the Siri phrase and the Spotlight/Shortcuts tile.
struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskJarvisIntent(),
            phrases: ["Ask \(.applicationName)"],
            shortTitle: "Ask Jarvis",
            systemImageName: "sparkles"
        )
    }
}
