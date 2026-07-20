import GRDB
import JAgent
import JKnowledge
import JScreen
import JStore
import SwiftUI

/// Debug transparency for the knowledge core: pipeline counters + a manual
/// drain trigger.
private struct KnowledgeSection: View {
    let knowledge: KnowledgeService

    @State private var stats: KnowledgeStore.Stats?
    @State private var draining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            JarvisSectionHeader(title: "Knowledge")
            if let current = stats {
                HStack(spacing: 14) {
                    counter("Queue", current.episodesPending)
                    counter("Episodes", current.episodesDone)
                    counter("Facts", current.facts)
                    counter("Entities", current.entities)
                    counter("Edges", current.edges)
                    Spacer()
                    Button(draining ? "Extracting…" : "Extract now") {
                        draining = true
                        Task {
                            await knowledge.drainPendingEpisodes(maxPerBoot: 50)
                            stats = await knowledge.store.stats()
                            draining = false
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisAccent)
                    .disabled(draining || current.episodesPending == 0)
                }
                if !current.semanticAvailable {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.jarvisCaption).foregroundStyle(Color.jarvisWarning)
                        Text("Semantic recall is off — the on-device embedding model isn't ready, so memory search is keyword-only for now.")
                            .font(.jarvisCaption).foregroundStyle(Color.jarvisTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Retry") {
                            Task {
                                await knowledge.store.reembedMissing()
                                stats = await knowledge.store.stats()
                            }
                        }
                        .buttonStyle(.plain).font(.jarvisCaption).foregroundStyle(Color.jarvisAccent)
                    }
                }
            } else {
                JarvisLoadingState()
            }
        }
        .padding(.horizontal, 16)
        .task { stats = await knowledge.store.stats() }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisGraphDidChange)) { _ in
            Task { stats = await knowledge.store.stats() }
        }
    }

    private func counter(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.jarvisBody.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Color.jarvisTextPrimary)
            Text(label).font(.jarvisFootnote).foregroundStyle(Color.jarvisTextTertiary)
        }
    }
}

struct SettingsView: View {
    @Bindable var core: JarvisCore
    let screenBuffer: ScreenBuffer
    var knowledge: KnowledgeService?
    var worlds: WorldSyncEngine?

    @State private var modelsByAccount: [String: [ProviderModel]] = [:]
    @State private var loadingModels: Set<String> = []
    @State private var showAddProvider = false
    @State private var pendingDelete: ProviderAccount?

    private static let sessionGapChoices = [2, 5, 10, 15, 30, 60]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                providersSection
                rolesSection
                sessionsSection
                privacySection
                if let knowledge, let worlds {
                    JarvisSectionHeader(title: "Sources").padding(.horizontal, 16)
                    SourcesPane(knowledge: knowledge, engine: worlds)
                }
                ProactivitySettings(settings: core.settings)
                ScreenRewindSection(settings: core.settings, screenBuffer: screenBuffer)
                if let knowledge {
                    KnowledgeSection(knowledge: knowledge)
                }
                PermissionsDashboard()
            }
            .padding(.vertical, 16)
        }
        .task { await refreshAllModels() }
        .confirmationDialog(
            "Remove \(pendingDelete.map { $0.label ?? $0.provider.capitalized } ?? "provider")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let account = pendingDelete {
                    Task { await core.deleteAccount(account); modelsByAccount[account.id] = nil }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Sessions")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a new session after")
                        .font(.jarvisBody)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Any message resets the timer; a reply after this much quiet starts a fresh conversation.")
                        .font(.jarvisFootnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { core.sessionGapMinutes },
                    set: { minutes in Task { await core.setSessionGap(minutes: minutes) } }
                )) {
                    ForEach(Self.sessionGapChoices, id: \.self) { minutes in
                        Text(minutes == 60 ? "1 hour" : "\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .tint(.white)
                .fixedSize()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.jarvisSurface))
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Privacy")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private mode")
                        .font(.jarvisBody).foregroundStyle(.white.opacity(0.85))
                    Text("Jarvis can read your context to answer, but can't act on the world — no sending mail, writing files, or controlling apps.")
                        .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { core.privateMode },
                    set: { on in Task { await core.setPrivateMode(on) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.jarvisAccent)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.jarvisSurface))
        }
    }

    // MARK: - Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Providers", actionTitle: showAddProvider ? "Cancel" : "Add provider") {
                withAnimation(.snappy) { showAddProvider.toggle() }
            }

            if core.accounts.isEmpty && !showAddProvider {
                emptyCard("Add Anthropic, OpenAI, or MiniMax to get started — you bring your own API key.")
            }

            ForEach(core.accounts) { account in
                providerCard(account)
            }

            if showAddProvider {
                AddProviderForm(core: core) { account in
                    withAnimation(.snappy) { showAddProvider = false }
                    Task { await onProviderAdded(account) }
                }
                .transition(.opacity)
            }
        }
    }

    private func providerCard(_ account: ProviderAccount) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill").font(.jarvisCaption).foregroundStyle(.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label ?? account.provider.capitalized)
                    .font(.jarvisRow.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                statusBadge(account)
            }
            Spacer()
            Button {
                pendingDelete = account
            } label: {
                Image(systemName: "trash").font(.jarvisCaption).foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(account.label ?? account.provider.capitalized)")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
    }

    @ViewBuilder
    private func statusBadge(_ account: ProviderAccount) -> some View {
        if loadingModels.contains(account.id) {
            Label("Checking key…", systemImage: "arrow.triangle.2.circlepath")
                .symbolEffect(.rotate)
                .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.45))
        } else if let models = modelsByAccount[account.id] {
            if models.isEmpty {
                Text("No models — check the key or base URL")
                    .font(.jarvisFootnote).foregroundStyle(Color.jarvisError)
            } else {
                Text("\(models.count) models available")
                    .font(.jarvisFootnote).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: models.count)
                    .foregroundStyle(Color.jarvisSuccess)
            }
        } else {
            Text(account.baseUrl ?? ProviderPreset.defaultBaseURL(for: account.provider).absoluteString)
                .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }

    // MARK: - Roles

    private var rolesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Models")
            Text("Route each kind of task to any provider and model.")
                .font(.jarvisCaption).foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 2)

            if core.accounts.isEmpty {
                emptyCard("Add a provider above, then pick a model for each role.")
            } else {
                ForEach(AgentRole.allCases) { role in
                    roleCard(role)
                }
            }
        }
    }

    private func roleCard(_ role: AgentRole) -> some View {
        let assignment = core.assignments[role]
        let accountID = assignment?.providerAccountId
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.label).font(.jarvisRow.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(role.detail).font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if role == .brain && assignment == nil {
                    Text("required").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.jarvisWarning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.jarvisWarning.opacity(0.15)))
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(core.accounts) { account in
                        Button(account.label ?? account.provider.capitalized) {
                            Task { await assign(role, accountID: account.id, model: firstModel(account.id)) }
                        }
                    }
                } label: {
                    pickerLabel(core.account(id: accountID ?? "")?.label
                        ?? core.account(id: accountID ?? "")?.provider.capitalized ?? "Provider", placeholder: accountID == nil)
                }
                .buttonStyle(.plain).fixedSize()

                Menu {
                    if let accountID, let models = modelsByAccount[accountID], !models.isEmpty {
                        ForEach(models) { model in
                            Button(model.displayName ?? model.id) {
                                Task { await assign(role, accountID: accountID, model: model.id) }
                            }
                        }
                    } else {
                        Text(loadingModels.contains(accountID ?? "") ? "Loading…" : "No models")
                    }
                } label: {
                    pickerLabel(assignment?.modelId ?? "Model", placeholder: assignment?.modelId == nil)
                }
                .buttonStyle(.plain)

                if loadingModels.contains(accountID ?? "") {
                    ProgressView().controlSize(.small)
                }
            }

            if let assignment {
                EffortPicker(core: core, role: role, assignment: assignment)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
    }

    // MARK: - Reusable

    private func pickerLabel(_ text: String, placeholder: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.jarvisCaption.weight(placeholder ? .regular : .medium))
                .foregroundStyle(placeholder ? .white.opacity(0.45) : .white.opacity(0.9)).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.jarvisCaption).foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.03)))
    }

    // MARK: - Actions

    private func firstModel(_ accountID: String) -> String { modelsByAccount[accountID]?.first?.id ?? "" }

    private func assign(_ role: AgentRole, accountID: String, model: String) async {
        await core.setAssignment(role, RoleAssignment(providerAccountId: accountID, modelId: model))
        if modelsByAccount[accountID] == nil { await loadModels(accountID) }
    }

    /// After adding a provider, verify the key by loading its models and, if the
    /// Brain role is still unset, auto-assign it to the first available model.
    private func onProviderAdded(_ account: ProviderAccount) async {
        await loadModels(account.id)
        if core.assignments[.brain] == nil, let first = modelsByAccount[account.id]?.first {
            await core.setAssignment(.brain, RoleAssignment(providerAccountId: account.id, modelId: first.id))
        }
    }

    private func refreshAllModels() async {
        await withTaskGroup(of: Void.self) { group in
            for account in core.accounts {
                group.addTask { await loadModels(account.id) }
            }
        }
    }

    private func loadModels(_ accountID: String) async {
        loadingModels.insert(accountID)
        defer { loadingModels.remove(accountID) }
        modelsByAccount[accountID] = await core.listModels(forAccount: accountID)
    }
}

private struct EffortPicker: View {
    let core: JarvisCore
    let role: AgentRole
    let assignment: RoleAssignment
    @State private var supportsReasoning = false

    var body: some View {
        Group {
            if supportsReasoning {
                HStack(spacing: 6) {
                    Text("Reasoning").font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                    Menu {
                        Button("Off") { set(nil) }
                        ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                            Button(effort.rawValue.capitalized) { set(effort) }
                        }
                    } label: {
                        Text(assignment.reasoningEffort?.rawValue.capitalized ?? "Off")
                            .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain).fixedSize()
                }
            }
        }
        .task(id: assignment.modelId) {
            let info = await core.capability(forAccount: assignment.providerAccountId, model: assignment.modelId)
            supportsReasoning = info?.reasoning ?? false
        }
    }

    private func set(_ effort: ReasoningEffort?) {
        Task {
            var updated = assignment
            updated.reasoningEffort = effort
            await core.setAssignment(role, updated)
        }
    }
}

private struct AddProviderForm: View {
    let core: JarvisCore
    let onDone: (ProviderAccount) -> Void

    @State private var provider: ProviderAccount.Provider = .anthropic
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var label = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Provider", selection: $provider) {
                Text("Anthropic").tag(ProviderAccount.Provider.anthropic)
                Text("OpenAI").tag(ProviderAccount.Provider.openai)
                Text("MiniMax").tag(ProviderAccount.Provider.minimax)
                Text("Custom (OpenAI-compatible)").tag(ProviderAccount.Provider.custom)
            }
            .pickerStyle(.menu)
            .onChange(of: provider) { _, newValue in
                baseURL = ProviderPreset.defaultBaseURL(for: newValue.rawValue).absoluteString
            }

            SecureField("API key", text: $apiKey).textFieldStyle(.roundedBorder)
            TextField("Base URL", text: $baseURL).textFieldStyle(.roundedBorder).font(.jarvisCaption)
            TextField("Label (optional)", text: $label).textFieldStyle(.roundedBorder)

            if let error {
                Text(error).font(.jarvisFootnote).foregroundStyle(Color.jarvisError)
            }

            HStack {
                Spacer()
                Button {
                    save()
                } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text("Save & verify") }
                }
                .disabled(apiKey.isEmpty || saving)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
        .onAppear {
            if baseURL.isEmpty { baseURL = ProviderPreset.defaultBaseURL(for: provider.rawValue).absoluteString }
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                let account = try await core.addAccount(
                    provider: provider,
                    baseURL: baseURL.isEmpty ? nil : baseURL,
                    label: label.isEmpty ? nil : label,
                    apiKey: apiKey
                )
                onDone(account)
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Proactivity section (Phase 6)

private struct ProactivitySettings: View {
    let settings: SettingsStore
    @State private var muted = false
    @State private var aggressiveness = "balanced"
    @State private var briefTime = "09:00"
    @State private var recapEnabled = false
    @State private var recapTime = "18:30"
    @State private var tokenBudget = 200_000
    // onChange fires while load() populates the @States — without this guard
    // the initial load would write defaults back over stored values.
    @State private var loaded = false
    @State private var saveError: String?

    private static let times: [String] = (0..<24).flatMap { h in ["00", "30"].map { String(format: "%02d:", h) + $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Proactivity")
            VStack(spacing: 12) {
                Toggle(isOn: $muted) { label("Mute proactivity", "Silence all nudges, briefs, and reminders.") }.tint(.jarvisLink)
                row("Aggressiveness", "How readily Jarvis interrupts — scales cooldown and daily cap.") {
                    Picker("", selection: $aggressiveness) {
                        Text("Relaxed").tag("relaxed"); Text("Balanced").tag("balanced"); Text("Eager").tag("eager")
                    }.pickerStyle(.menu).buttonStyle(.plain).tint(.white).fixedSize()
                }
                row("Morning brief", "A short daily brief at this time.") {
                    Picker("", selection: $briefTime) { ForEach(Self.times, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.menu).buttonStyle(.plain).tint(.white).fixedSize()
                }
                Toggle(isOn: $recapEnabled) { label("Evening recap", "An end-of-day recap (off by default).") }.tint(.jarvisLink)
                if recapEnabled {
                    row("Recap time", nil) {
                        Picker("", selection: $recapTime) { ForEach(Self.times, id: \.self) { Text($0).tag($0) } }
                            .pickerStyle(.menu).buttonStyle(.plain).tint(.white).fixedSize()
                    }
                }
                row("Daily token budget", "Ceiling for all background/proactive model spend.") {
                    TextField("", value: $tokenBudget, format: .number)
                        .frame(width: 90).multilineTextAlignment(.trailing).textFieldStyle(.plain).foregroundStyle(.white)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.jarvisSurface))

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.jarvisFootnote)
                    .foregroundStyle(Color.jarvisError)
            }
        }
        .task { await load() }
        .onChange(of: muted) { _, v in save("proactive_muted", v) }
        .onChange(of: aggressiveness) { _, v in save("proactive_aggressiveness", v) }
        .onChange(of: briefTime) { _, v in save("brief_time", v) }
        .onChange(of: recapEnabled) { _, v in save("recap_enabled", v) }
        .onChange(of: recapTime) { _, v in save("recap_time", v) }
        .onChange(of: tokenBudget) { _, v in save("proactive_token_budget", v) }
    }

    private func save<T: Codable & Sendable>(_ key: String, _ value: T) {
        guard loaded else { return }
        Task {
            do {
                try await settings.set(key, to: value)
                saveError = nil
            } catch {
                saveError = "Couldn't save — \(error.localizedDescription)"
            }
        }
    }

    private func label(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.jarvisBody).foregroundStyle(.white.opacity(0.85))
            if let subtitle { Text(subtitle).font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func row<T: View>(_ title: String, _ subtitle: String?, @ViewBuilder trailing: () -> T) -> some View {
        HStack { label(title, subtitle); Spacer(); trailing() }
    }
    private func load() async {
        muted = ((try? await settings.get("proactive_muted", as: Bool.self)) ?? nil) ?? false
        aggressiveness = ((try? await settings.get("proactive_aggressiveness", as: String.self)) ?? nil) ?? "balanced"
        briefTime = ((try? await settings.get("brief_time", as: String.self)) ?? nil) ?? "09:00"
        recapEnabled = ((try? await settings.get("recap_enabled", as: Bool.self)) ?? nil) ?? false
        recapTime = ((try? await settings.get("recap_time", as: String.self)) ?? nil) ?? "18:30"
        tokenBudget = ((try? await settings.get("proactive_token_budget", as: Int.self)) ?? nil) ?? 200_000
        loaded = true
    }
}

// MARK: - Screen Rewind section (Phase 5)

private struct ScreenRewindSection: View {
    let settings: SettingsStore
    let screenBuffer: ScreenBuffer

    @State private var policy = ScreenCapturePolicy.default
    @State private var excludedText = ""
    @State private var stats: ScreenBuffer.StorageStats?
    @State private var thumbnails: [String] = []
    @State private var confirmPurge = false

    private static let retentionChoices = [2, 5, 12]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Screen Rewind")

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { policy.enabled },
                    set: { on in apply { $0.enabled = on } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture my screen").font(.jarvisBody).foregroundStyle(.white.opacity(0.85))
                        Text("Passively snapshots the front window so Jarvis can recall what you saw — just ask (\"what was that error earlier?\"). Stored only on this Mac.")
                            .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.jarvisAccent)

                if policy.enabled {
                    Divider().overlay(Color.jarvisStroke)

                    HStack {
                        Text("Keep history for").font(.jarvisBody).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { policy.retentionHours },
                            set: { hours in apply { $0.retentionHours = hours } }
                        )) {
                            ForEach(Self.retentionChoices, id: \.self) { hours in
                                Text(label(forHours: hours)).tag(hours)
                            }
                        }
                        .pickerStyle(.menu).buttonStyle(.plain).tint(.white).fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Never capture these apps").font(.jarvisBody).foregroundStyle(.white.opacity(0.85))
                        Text("Comma-separated bundle IDs (password managers are always excluded).")
                            .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("com.apple.Notes, com.tinyspeck.slackmacgap", text: $excludedText)
                            .textFieldStyle(.roundedBorder).font(.jarvisCaption)
                            .onSubmit { commitExcluded() }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))

            transparencyCard
        }
        .task {
            policy = await ScreenCapturePolicy.load(from: settings)
            excludedText = policy.excludedBundleIDs.joined(separator: ", ")
            await refreshStats()
        }
        .confirmationDialog("Delete all captured screen history?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task {
                    await screenBuffer.purgeAll()
                    await refreshStats()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Exactly what Screen Rewind is holding — count, size, age, a peek at the
    /// most recent captures, and a way to wipe it all.
    @ViewBuilder
    private var transparencyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(statsLine)
                    .font(.jarvisFootnote).monospacedDigit()
                    .foregroundStyle(Color.jarvisTextSecondary)
                Spacer()
                if let stats, stats.frameCount > 0 {
                    Button("Delete all", role: .destructive) { confirmPurge = true }
                        .buttonStyle(.plain)
                        .font(.jarvisFootnote.weight(.medium))
                        .foregroundStyle(Color.jarvisError)
                }
            }

            if !thumbnails.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(thumbnails, id: \.self) { path in
                            FrameThumb(path: path)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.03)))
    }

    private var statsLine: String {
        guard let stats, stats.frameCount > 0 else { return "Nothing captured yet" }
        var parts = ["\(stats.frameCount) frames",
                     ByteCountFormatter.string(fromByteCount: Int64(stats.totalBytes), countStyle: .file)]
        if let oldest = stats.oldest {
            parts.append("oldest \(oldest.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func refreshStats() async {
        stats = await screenBuffer.storageStats()
        thumbnails = await screenBuffer.recentFramePaths(limit: 8)
    }

    private func label(forHours hours: Int) -> String {
        switch hours { case 2: "2 hours"; case 12: "12 hours"; default: "5 hours" }
    }

    private func commitExcluded() {
        let ids = excludedText.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        apply { $0.excludedBundleIDs = ids }
    }

    private func apply(_ mutate: (inout ScreenCapturePolicy) -> Void) {
        var updated = policy
        mutate(&updated)
        policy = updated
        screenBuffer.setPolicy(updated)
        Task { await updated.save(to: settings) }
    }
}

/// One small screen-frame thumbnail in the Rewind transparency strip.
private struct FrameThumb: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.jarvisSurface
            }
        }
        .frame(width: 68, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.jarvisStroke, lineWidth: 1))
        .task(id: path) {
            let p = path
            image = await Task.detached(priority: .utility) { NSImage(contentsOfFile: p) }.value
        }
    }
}
