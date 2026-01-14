import SwiftUI

struct SettingsWindowView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            VoiceSettingsView()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }
            
            AutomationSettingsView()
                .tabItem {
                    Label("Automation", systemImage: "command")
                }
            
            HotkeysSettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
            
            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("apiBaseURL") private var apiBaseURL = "http://127.0.0.1:8000"
    @AppStorage("theme") private var theme = "system"
    
    var body: some View {
        Form {
            Section("API Configuration") {
                TextField("API Base URL", text: $apiBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct VoiceSettingsView: View {
    @AppStorage("voiceEnabled") private var voiceEnabled = true
    @AppStorage("voiceSpeed") private var voiceSpeed = 1.0
    @AppStorage("selectedVoice") private var selectedVoice = "com.apple.voice.compact.en-US.Samantha"
    
    var body: some View {
        Form {
            Section("Voice Output") {
                Toggle("Enable Voice", isOn: $voiceEnabled)
                
                Slider(value: $voiceSpeed, in: 0.5...2.0, step: 0.1) {
                    Text("Speech Rate: \(voiceSpeed, specifier: "%.1f")x")
                }
            }
            
            Section("Speech Recognition") {
                Text("Using on-device Apple Speech Recognition")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AutomationSettingsView: View {
    @AppStorage("confirmDestructive") private var confirmDestructive = true
    @AppStorage("logActions") private var logActions = true
    
    var body: some View {
        Form {
            Section("Safety") {
                Toggle("Confirm Destructive Actions", isOn: $confirmDestructive)
                Toggle("Log All Actions", isOn: $logActions)
            }
            
            Section("Available Capabilities") {
                Label("App Control", systemImage: "app.badge.checkmark")
                Label("UI Automation", systemImage: "cursorarrow.click.2")
                Label("Keyboard/Mouse", systemImage: "keyboard")
                Label("Shortcuts Integration", systemImage: "square.stack.3d.up")
                Label("System Monitoring", systemImage: "chart.bar")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HotkeysSettingsView: View {
    var body: some View {
        Form {
            Section("Global Hotkeys") {
                HStack {
                    Text("Activate Jarvis")
                    Spacer()
                    Text("⌘⇧J")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("Toggle Focus Mode")
                    Spacer()
                    Text("⌘⇧⌥F")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("Voice Command")
                    Spacer()
                    Text("⌘⌥Space")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("Quick Capture")
                    Spacer()
                    Text("⌘⇧⌥C")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Section {
                Text("Hotkeys require Accessibility permission")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PermissionsSettingsView: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    
    var body: some View {
        Form {
            Section("Required Permissions") {
                PermissionRow(
                    name: "Accessibility",
                    description: "UI automation and hotkeys",
                    isGranted: accessibilityGranted
                )
                
                PermissionRow(
                    name: "Automation",
                    description: "AppleScript control",
                    isGranted: true
                )
                
                PermissionRow(
                    name: "Microphone",
                    description: "Voice conversations",
                    isGranted: true
                )
                
                PermissionRow(
                    name: "Screen Recording",
                    description: "Screenshots and screen capture",
                    isGranted: true
                )
            }
            
            Section {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
        }
    }
}

struct PermissionRow: View {
    let name: String
    let description: String
    let isGranted: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isGranted ? .green : .red)
        }
    }
}

#Preview {
    SettingsWindowView()
}
