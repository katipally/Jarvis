import Foundation
import JAgent
import JControl
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
    let control: ComputerUseRuntime
    let screenBuffer: ScreenBuffer
    let screenRecall: ScreenRecall
    let funnel: NudgeFunnel
    let cronStore: CronStore

    init(database: JarvisDatabase, supportDirectory: URL) {
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
        self.funnel = NudgeFunnel(database: database)
        let cronStore = CronStore(database: database)
        self.cronStore = cronStore
        self.gate = ApprovalGate(store: approvalStore) { request in
            Task { @MainActor in presenter.enqueue(request) }
        }
        self.tools = ToolRegistry(
            StarterTools.specs(artifacts: artifactStore, scratch: scratchDir)
                + ControlTools.registry(runtime: control)
                + BridgeTools.registry()
                + ScreenTools.registry(recall: screenRecall, buffer: screenBuffer)
                + ProactiveTools.registry(cronStore: cronStore)
        )

        presenter.gate = gate
    }
}
