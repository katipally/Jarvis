import SwiftUI

/// Live permission status with grant/open actions. Re-checks when the app
/// re-activates (after the user changes a System Settings toggle).
struct PermissionsDashboard: View {
    @State private var states: [Permission: PermissionState] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
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
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).tracking(0.5)
    }

    private func row(_ permission: Permission) -> some View {
        let state = states[permission] ?? .notDetermined
        return HStack(spacing: 11) {
            Image(systemName: permission.symbol)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                Text(permission.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            statusControl(permission, state)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
    }

    @ViewBuilder
    private func statusControl(_ permission: Permission, _ state: PermissionState) -> some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.5))
                .labelStyle(.iconOnly)
                .overlay(alignment: .trailing) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                        .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.5))
                }
        case .denied:
            Button("Open Settings") { PermissionsChecker.openSettings(permission); scheduleRefresh() }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 1, green: 0.6, blue: 0.4))
        case .notDetermined:
            Button("Grant") { PermissionsChecker.request(permission); scheduleRefresh() }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
        }
    }

    private func refresh() {
        for permission in Permission.allCases { states[permission] = PermissionsChecker.state(permission) }
    }

    private func scheduleRefresh() {
        Task { try? await Task.sleep(for: .seconds(1)); refresh() }
    }
}
