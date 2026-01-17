import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ChatViewModel
    @AppStorage("apiBaseURL") private var apiBaseURL = "http://localhost:8000/api"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("showTokenCount") private var showTokenCount = true
    
    // AI Provider Settings
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openaiModel") private var openaiModel = "gpt-5-nano"
    @AppStorage("ollamaModel") private var ollamaModel = "qwen3:8b"
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                    Toggle(isOn: $showTokenCount) {
                        Label("Show Token Usage", systemImage: "cpu")
                    }
                } header: {
                    Text("General")
                }
                
                Section {
                    Picker("AI Brain", selection: $aiProvider) {
                        Text("OpenAI (Cloud)").tag("openai")
                        Text("Ollama (Local)").tag("ollama")
                    }
                    .pickerStyle(.segmented)
                    
                    if aiProvider == "openai" {
                        // OpenAI: Free text input as requested
                        TextField("Model Name", text: $openaiModel)
                            .help("Enter the OpenAI model ID (e.g., gpt-4o, o1-mini, o3-mini)")
                        
                        Text("Common: gpt-4o, o1-mini, o3-mini")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                    } else {
                        // Ollama: Dropdown from local models
                        if let models = viewModel.availableModels?.ollama {
                            Picker("Model", selection: $ollamaModel) {
                                ForEach(models, id: \.id) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                        } else {
                            Text("Loading Ollama models...").font(.caption)
                        }
                        
                        Text("Make sure 'ollama serve' is running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Model Configuration")
                }
                
                Section {
                    TextField("URL", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Backend Connection")
                }
                
                Section {
                    let stats = viewModel.getSessionStats()
                    LabeledContent("Tokens This Session", value: "\(stats.tokens)")
                    LabeledContent("Estimated Cost", value: String(format: "$%.6f", stats.cost))
                    
                    Button(role: .destructive) {
                        viewModel.resetSessionStats()
                    } label: {
                        Text("Reset Statistics")
                    }
                } header: {
                    Text("Usage Statistics")
                }
                
                Section {
                    LabeledContent("Version", value: "1.2.0")
                    LabeledContent("Engine", value: "Apple Intelligence (Mock)")
                    LabeledContent("Interface", value: "Liquid Glass 2.0")
                } header: {
                    Text("System Information")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .frame(width: 480, height: 600)
            .background(MacOS26Materials.sidebar)
            .onChange(of: aiProvider) { newValue in syncSettings() }
            .onChange(of: openaiModel) { newValue in syncSettings() }
            .onChange(of: ollamaModel) { newValue in syncSettings() }
            .onAppear {
                viewModel.fetchModels()
                syncSettings()
            }
        }
    }
    
    private func syncSettings() {
        viewModel.updateAISettings(
            provider: aiProvider,
            openaiModel: openaiModel,
            ollamaModel: ollamaModel
        )
    }
}

struct SettingsPreviewContainer: View {
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}

#Preview {
    SettingsPreviewContainer()
}

