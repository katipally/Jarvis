import SwiftUI

/// Live permission status with grant/open actions. Re-checks when the app
/// re-activates (after the user changes a System Settings toggle).
struct PermissionsDashboard: View {
    @State private var states: [Permission: PermissionState] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            ForEach(Permission.allCases) { permission in
                row(permission)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var sectionHeader: some View {
        Text("PERMISSIONS")
            .font(.jarvisCaption.weight(.semibold)).foregroundStyle(.white.opacity(0.5)).tracking(0.5)
    }

    private func row(_ permission: Permission) -> some View {
        let state = states[permission] ?? .notDetermined
        return HStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.title).font(.jarvisRow).foregroundStyle(.white.opacity(0.9))
                Text(permission.detail).font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            statusControl(permission, state)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
    }

    @ViewBuilder
    private func statusControl(_ permission: Permission, _ state: PermissionState) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15))
                .foregroundStyle(Color.jarvisSuccess)
                .accessibilityLabel("Granted")
        case .denied:
            Button("Open Settings") { PermissionsChecker.openSettings(permission); scheduleRefresh() }
                .buttonStyle(.plain).font(.jarvisCaption.weight(.medium))
                .foregroundStyle(Color.jarvisWarning)
        case .notDetermined:
            Button("Grant") { PermissionsChecker.request(permission); scheduleRefresh() }
                .buttonStyle(.plain).font(.jarvisCaption.weight(.semibold))
                .foregroundStyle(Color.jarvisLink)
        }
    }

    private func refresh() {
        for permission in Permission.allCases { states[permission] = PermissionsChecker.state(permission) }
    }

    private func scheduleRefresh() {
        Task { try? await Task.sleep(for: .seconds(1)); refresh() }
    }
}
