import Foundation
import JAgent
import JControl
import JKnowledge
import JProactive
import JScreen
import JStore

/// Bundles the M2 agent infrastructure: approval gate + presenter, tool
/// registry, and the artifact/run stores. Built once at launch.
@MainActor
final class AgentServices {
    let approvalStore: ApprovalStore
    let artifactStore: ArtifactStore
    let runStore: RunStore
    let presenter: ApprovalPresenter
    let gate: ApprovalGate
    let tools: ToolRegistry
    /// The system prompt, assembled at launch from `agent.md` with the live tool
    /// catalog spliced in — edit the markdown, not a Swift string.
    let systemPrompt: String
    /// Per-turn skill hints, parsed from `skills.md`.
    let skills: SkillRegistry
    let control: ComputerUseRuntime
    let screenBuffer: ScreenBuffer
    let screenRecall: ScreenRecall
    let cronStore: CronStore

    init(database: JarvisDatabase, supportDirectory: URL, knowledgeStore: KnowledgeStore,
         knowledge: KnowledgeService? = nil) {
        let artifactsDir = supportDirectory.appendingPathComponent("artifacts", isDirectory: true)
        let scratchDir = supportDirectory.appendingPathComponent("scratch", isDirectory: true)
        let framesDir = supportDirectory.appendingPathComponent("frames", isDirectory: true)

        let approvalStore = ApprovalStore(database: database)
        let artifactStore = ArtifactStore(database: database, directory: artifactsDir)
        let presenter = ApprovalPresenter()
        let control = ComputerUseRuntime()
        let screenBuffer = ScreenBuffer(database: database, framesDirectory: framesDir)
        let screenRecall = ScreenRecall(database: database)

        self.approvalStore = approvalStore
        self.artifactStore = artifactStore
        self.runStore = RunStore(database: database)
        self.presenter = presenter
        self.control = control
        self.screenBuffer = screenBuffer
        self.screenRecall = screenRecall
        let cronStore = CronStore(database: database)
        self.cronStore = cronStore
        self.gate = ApprovalGate(store: approvalStore) { request in
            Task { @MainActor in presenter.enqueue(request) }
        } dismiss: { id in
            Task { @MainActor in presenter.dismiss(id) }
        }
        let tools = ToolRegistry(
            StarterTools.specs(artifacts: artifactStore, scratch: scratchDir)
                + ControlTools.registry(runtime: control)
                + BridgeTools.registry()
                + ScreenTools.registry(recall: screenRecall, buffer: screenBuffer)
                + ProactiveTools.registry(cronStore: cronStore)
                + MemoryTools.registry(store: knowledgeStore, knowledge: knowledge)
        )
        self.tools = tools

        // Prompt + skills live in bundled markdown so they change without a code
        // edit. The tool list is spliced in from the live registry, so adding a
        // tool updates the prompt for free (no drift-prone hardcoded list).
        let agentDoc = Self.loadPrompt("agent") ?? Self.fallbackAgentPrompt
        self.systemPrompt = agentDoc.replacingOccurrences(of: "{{TOOLS}}", with: tools.promptCatalog)
        self.skills = SkillRegistry(markdown: Self.loadPrompt("skills") ?? "")

        presenter.gate = gate
    }

    private static func loadPrompt(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }

    /// Used only if `agent.md` is missing from the bundle, so the app still
    /// answers. Kept terse — the real prompt is the markdown file.
    private static let fallbackAgentPrompt = """
    You are Jarvis, the assistant that lives in the notch at the top of this \
    Mac's screen — a fast, capable alternative to Siri. You answer questions, \
    control the Mac, manage calendars, reminders, mail, and notes, and remember \
    things across conversations.

    Prefer acting over describing: when the user asks for something a tool can \
    do, do it. Tools that change anything ask for approval first — never claim \
    an action succeeded before its result comes back. Be brief: lead with the \
    answer, one short paragraph is the norm. A `<context>` block carries the \
    current date, time, frontmost app, and relevant memories — treat it as \
    ground truth and never echo it.

    Available tools:
    {{TOOLS}}
    """
}
