import JAgent
import JStore
import SwiftUI

/// First-run flow, shown in-notch (no login): welcome → provider + model → voice
/// permission → done. On finish, marks onboarding complete.
struct OnboardingView: View {
    @Bindable var core: JarvisCore

    enum Step { case welcome, provider, voice, done }
    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Steps only ever advance, so slide new content in from the
                // trailing edge and retire the old toward the leading edge.
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            stepDots
        }
        .animation(.snappy, value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .provider: ProviderStep(core: core) { advance() }
        case .voice: voice
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 34, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Meet Jarvis").font(Self.titleFont).foregroundStyle(.white)
            Text("Your Mac's own assistant — it lives in the notch, remembers what matters, and can act on your behalf. Everything stays on your Mac.")
                .font(.jarvisBody).foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Spacer()
            primaryButton("Get started") { advance() }
        }
        .padding(.horizontal, 20)
    }

    private var voice: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "mic.fill").font(.system(size: 30, weight: .light)).foregroundStyle(.white.opacity(0.8))
            Text("Talk to Jarvis").font(Self.stepTitleFont).foregroundStyle(.white)
            Text("Hold the Option key anywhere to speak. Transcription is on-device. Grant microphone access to enable it.")
                .font(.jarvisBody).foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Spacer()
            HStack(spacing: 10) {
                secondaryButton("Skip") { advance() }
                primaryButton("Enable voice") {
                    PermissionsChecker.request(.microphone)
                    PermissionsChecker.request(.speech)
                    advance()
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var done: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.jarvisSuccess)
            Text("You're all set").font(Self.stepTitleFont).foregroundStyle(.white)
            Text("Hover the notch and type, or hold Option to talk. Jarvis will ask before doing anything that changes your Mac.")
                .font(.jarvisBody).foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Spacer()
            primaryButton("Start using Jarvis") {
                Task { await core.completeOnboarding() }
            }
        }
        .padding(.horizontal, 20)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach([Step.welcome, .provider, .voice, .done], id: \.self) { s in
                Circle().fill(.white.opacity(s == step ? 0.9 : 0.25)).frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepIndex + 1) of 4")
    }

    private var stepIndex: Int {
        [Step.welcome, .provider, .voice, .done].firstIndex(of: step) ?? 0
    }

    /// Onboarding display sizes — hero type the shared scale doesn't cover,
    /// defined once instead of scattered per step.
    private static let titleFont = Font.system(size: 22, weight: .semibold)
    private static let stepTitleFont = Font.system(size: 19, weight: .semibold)

    private func advance() {
        switch step {
        case .welcome: step = .provider
        case .provider: step = .voice
        case .voice: step = .done
        case .done: break
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.jarvisBody.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Capsule().fill(Color.jarvisAccent))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.jarvisBody.weight(.medium)).foregroundStyle(Color.jarvisTextSecondary)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Provider + Brain-model step: add a key, verify, pick a model.
private struct ProviderStep: View {
    @Bindable var core: JarvisCore
    let onContinue: () -> Void

    @State private var provider: ProviderAccount.Provider = .anthropic
    @State private var apiKey = ""
    @State private var accountID: String?
    @State private var models: [ProviderModel] = []
    @State private var selectedModel: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect a model").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            Text("Bring your own API key — Anthropic, OpenAI, or MiniMax. It's stored in your Keychain.")
                .font(.jarvisCaption).foregroundStyle(Color.jarvisTextTertiary)

            if accountID == nil {
                Picker("Provider", selection: $provider) {
                    Text("Anthropic").tag(ProviderAccount.Provider.anthropic)
                    Text("OpenAI").tag(ProviderAccount.Provider.openai)
                    Text("MiniMax").tag(ProviderAccount.Provider.minimax)
                }
                .pickerStyle(.segmented).labelsHidden()

                SecureField("Paste your API key", text: $apiKey).textFieldStyle(.roundedBorder)

                if let error { Text(error).font(.jarvisCaption).foregroundStyle(Color.jarvisError) }

                HStack {
                    Button("Skip for now") { onContinue() }
                        .buttonStyle(.plain).font(.jarvisRow)
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button { connect() } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Connect").fontWeight(.semibold) }
                    }
                    .disabled(apiKey.isEmpty || busy)
                }
            } else {
                Text("\(models.count) models available")
                    .font(.jarvisCaption).monospacedDigit()
                    .foregroundStyle(Color.jarvisSuccess)
                Menu {
                    ForEach(models) { model in
                        Button(model.displayName ?? model.id) { selectModel(model.id) }
                    }
                } label: {
                    HStack {
                        Text(selectedModel ?? "Choose a model").foregroundStyle(selectedModel == nil ? .white.opacity(0.5) : .white)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                    .font(.jarvisBody).padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                HStack {
                    Spacer()
                    Button("Continue") { onContinue() }
                        .disabled(selectedModel == nil).fontWeight(.semibold)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func connect() {
        busy = true
        error = nil
        Task {
            do {
                let account = try await core.addAccount(provider: provider, baseURL: nil, label: nil, apiKey: apiKey)
                let loaded = await core.listModels(forAccount: account.id)
                if loaded.isEmpty {
                    error = "Couldn't reach the provider — check the key."
                    await core.deleteAccount(account)
                } else {
                    accountID = account.id
                    models = loaded
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func selectModel(_ id: String) {
        selectedModel = id
        guard let accountID else { return }
        Task { await core.setAssignment(.brain, RoleAssignment(providerAccountId: accountID, modelId: id)) }
    }
}
