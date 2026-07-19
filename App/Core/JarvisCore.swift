import Foundation
import GRDB
import JAgent
import JStore

/// App-wide composition root and provider resolver. Owns the DB-backed config
/// (accounts, role assignments) and hands out configured adapters.
@MainActor
@Observable
final class JarvisCore {
    let database: JarvisDatabase
    let settings: SettingsStore
    let catalog: ModelCatalog

    private(set) var accounts: [ProviderAccount] = []
    private(set) var assignments: [AgentRole: RoleAssignment] = [:]
    private(set) var onboardingComplete = false
    private(set) var loaded = false

    private static let assignmentsKey = "role_assignments"
    private static let onboardingKey = "onboarding_complete"

    init(database: JarvisDatabase, cacheDirectory: URL) {
        self.database = database
        self.settings = SettingsStore(db: database)
        self.catalog = ModelCatalog(cacheDirectory: cacheDirectory)
    }

    func load() async {
        accounts = (try? await database.reader.read { db in
            try ProviderAccount.order(Column("created_at")).fetchAll(db)
        }) ?? []

        if let stored = try? await settings.get(Self.assignmentsKey, as: [String: RoleAssignment].self) {
            var result: [AgentRole: RoleAssignment] = [:]
            for (key, value) in stored {
                if let role = AgentRole(rawValue: key) { result[role] = value }
            }
            assignments = result
        }
        onboardingComplete = (try? await settings.get(Self.onboardingKey, as: Bool.self)) ?? false
        loaded = true
        await catalog.refresh()
    }

    var isConfigured: Bool { assignments[.brain] != nil }

    // MARK: - Accounts

    @discardableResult
    func addAccount(provider: ProviderAccount.Provider, baseURL: String?, label: String?, apiKey: String) async throws -> ProviderAccount {
        let account = ProviderAccount(provider: provider, baseUrl: baseURL, label: label)
        try Keychain.set(apiKey, account: account.id)
        try await database.writer.write { db in try account.insert(db) }
        accounts.append(account)
        return account
    }

    func deleteAccount(_ account: ProviderAccount) async {
        try? Keychain.delete(account: account.id)
        _ = try? await database.writer.write { db in
            try ProviderAccount.deleteOne(db, key: account.id)
        }
        accounts.removeAll { $0.id == account.id }
        for (role, assignment) in assignments where assignment.providerAccountId == account.id {
            assignments[role] = nil
        }
        await persistAssignments()
    }

    func account(id: String) -> ProviderAccount? {
        accounts.first { $0.id == id }
    }

    // MARK: - Assignments

    func setAssignment(_ role: AgentRole, _ assignment: RoleAssignment?) async {
        assignments[role] = assignment
        await persistAssignments()
    }

    func completeOnboarding() async {
        onboardingComplete = true
        try? await settings.set(Self.onboardingKey, to: true)
    }

    private func persistAssignments() async {
        let stored = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value) })
        try? await settings.set(Self.assignmentsKey, to: stored)
    }

    // MARK: - Provider resolution

    func spec(forAccount accountID: String) -> ProviderSpec? {
        guard let account = account(id: accountID),
              let key = try? Keychain.get(account: accountID) else { return nil }
        let providerString = account.provider
        let api = ProviderPreset.defaultAPI(for: providerString)
        let base = account.baseUrl.flatMap(URL.init(string:)) ?? ProviderPreset.defaultBaseURL(for: providerString)
        return ProviderSpec(api: api, apiKey: key, baseURL: base)
    }

    struct ResolvedRole {
        let adapter: any ProviderAdapter
        let model: String
        let effort: ReasoningEffort?
        let account: ProviderAccount
    }

    func resolve(_ role: AgentRole) -> ResolvedRole? {
        guard let assignment = assignments[role],
              let account = account(id: assignment.providerAccountId),
              let spec = spec(forAccount: assignment.providerAccountId) else { return nil }
        return ResolvedRole(
            adapter: ProviderFactory.make(spec),
            model: assignment.modelId,
            effort: assignment.reasoningEffort,
            account: account
        )
    }

    func listModels(forAccount accountID: String) async -> [ProviderModel] {
        guard let spec = spec(forAccount: accountID) else { return [] }
        let adapter = ProviderFactory.make(spec)
        return (try? await adapter.listModels()) ?? []
    }

    func capability(forAccount accountID: String, model: String) async -> ModelInfo? {
        guard let account = account(id: accountID) else { return nil }
        return await catalog.info(provider: ProviderPreset.catalogProviderID(for: account.provider), model: model)
    }
}
