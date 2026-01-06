import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ChatViewModel
    @AppStorage("apiBaseURL") private var apiBaseURL = "http://localhost:8000/api"
    @AppStorage("includeReasoning") private var includeReasoning = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("showTokenCount") private var showTokenCount = true
    
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
                } header: {
                    Text("General")
                }
                
                Section {
                    Toggle(isOn: $includeReasoning) {
                        Label("Show AI Reasoning", systemImage: "brain")
                    }
                    Toggle(isOn: $showTokenCount) {
                        Label("Show Token Usage", systemImage: "cpu")
                    }
                } header: {
                    Text("Intelligence")
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
            .frame(width: 480, height: 550)
            .background(MacOS26Materials.sidebar)
        }
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

