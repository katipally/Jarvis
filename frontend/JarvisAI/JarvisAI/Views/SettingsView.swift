import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("apiBaseURL") private var apiBaseURL: String = "http://localhost:8000/api"
    @AppStorage("includeReasoning") private var includeReasoning: Bool = true
    @AppStorage("autoScroll") private var autoScroll: Bool = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    TextField("API Base URL", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Current endpoint: \(apiBaseURL)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Chat Settings") {
                    Toggle("Include Reasoning", isOn: $includeReasoning)
                    Toggle("Auto-scroll to Latest", isOn: $autoScroll)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("GPT-5-nano")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(width: 500, height: 400)
        }
    }
}

#Preview {
    SettingsView()
}

