import JAgent
import JStore
import SwiftUI

struct SettingsView: View {
    @Bindable var core: JarvisCore

    @State private var modelsByAccount: [String: [ProviderModel]] = [:]
    @State private var loadingModels: Set<String> = []
    @State private var showAddProvider = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                providersSection
                rolesSection
                PermissionsDashboard()
            }
            .padding(.vertical, 14)
        }
        .task { await refreshAllModels() }
    }

    // MARK: - Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("Providers", trailing: showAddProvider ? "Cancel" : "Add provider") {
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
            Image(systemName: "key.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label ?? account.provider.capitalized)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                statusBadge(account)
            }
            Spacer()
            Button {
                Task { await core.deleteAccount(account); modelsByAccount[account.id] = nil }
            } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
    }

    @ViewBuilder
    private func statusBadge(_ account: ProviderAccount) -> some View {
        if loadingModels.contains(account.id) {
            Label("Checking key…", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        } else if let models = modelsByAccount[account.id] {
            if models.isEmpty {
                Text("No models — check the key or base URL")
                    .font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
            } else {
                Text("\(models.count) models available")
                    .font(.system(size: 10)).foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.5))
            }
        } else {
            Text(account.baseUrl ?? ProviderPreset.defaultBaseURL(for: account.provider).absoluteString)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
        }
    }

    // MARK: - Roles

    private var rolesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("Models", trailing: nil, action: nil)
            Text("Route each kind of task to any provider and model.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
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
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(role.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(role.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                if role == .brain && assignment == nil {
                    Text("required").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.3))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 1, green: 0.75, blue: 0.3).opacity(0.15)))
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
                .menuStyle(.borderlessButton).fixedSize()

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
                .menuStyle(.borderlessButton)

                if loadingModels.contains(accountID ?? "") {
                    ProgressView().controlSize(.small)
                }
            }

            if let assignment {
                EffortPicker(core: core, role: role, assignment: assignment)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
    }

    // MARK: - Reusable

    private func pickerLabel(_ text: String, placeholder: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 11, weight: placeholder ? .regular : .medium))
                .foregroundStyle(placeholder ? .white.opacity(0.4) : .white.opacity(0.9)).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
    }

    private func sectionHeader(_ title: String, trailing: String?, action: (() -> Void)?) -> some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).tracking(0.5)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
            }
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
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
                    Text("Reasoning").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    Menu {
                        Button("Off") { set(nil) }
                        ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                            Button(effort.rawValue.capitalized) { set(effort) }
                        }
                    } label: {
                        Text(assignment.reasoningEffort?.rawValue.capitalized ?? "Off")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
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
        VStack(alignment: .leading, spacing: 9) {
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
            TextField("Base URL", text: $baseURL).textFieldStyle(.roundedBorder).font(.system(size: 11))
            TextField("Label (optional)", text: $label).textFieldStyle(.roundedBorder)

            if let error {
                Text(error).font(.system(size: 10)).foregroundStyle(.red)
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
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
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
