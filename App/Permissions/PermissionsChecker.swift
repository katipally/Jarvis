import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import EventKit
import Speech

/// Live status + grant/open actions for every TCC permission Jarvis uses.
enum Permission: String, CaseIterable, Identifiable {
    case microphone, speech, accessibility, screenRecording, calendar, reminders, automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .speech: "Speech Recognition"
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .automation: "Automation"
        }
    }

    var detail: String {
        switch self {
        case .microphone: "Hold-Option voice input"
        case .speech: "On-device transcription"
        case .accessibility: "Controlling apps (clicking, typing)"
        case .screenRecording: "Screen awareness & screenshots"
        case .calendar: "Reading & adding events"
        case .reminders: "Reading & adding reminders"
        case .automation: "Driving Mail & Notes"
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .speech: "waveform"
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .automation: "app.connected.to.app.below.fill"
        }
    }

    /// Deep link to the relevant System Settings pane.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .speech: anchor = "Privacy_SpeechRecognition"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .calendar: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .automation: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum PermissionState { case granted, denied, notDetermined }

@MainActor
enum PermissionsChecker {
    static func state(_ permission: Permission) -> PermissionState {
        switch permission {
        case .microphone:
            return map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .speech:
            return map(SFSpeechRecognizer.authorizationStatus())
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        case .calendar:
            return map(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return map(EKEventStore.authorizationStatus(for: .reminder))
        case .automation:
            return .notDetermined // no queryable status; granted per-target on first use
        }
    }

    /// Trigger the system prompt where possible, else open System Settings.
    /// TCC completion handlers arrive on private XPC queues — they must be
    /// `@Sendable` (non-MainActor) or the isolation assert traps at runtime.
    static func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable _ in }
        case .speech:
            SFSpeechRecognizer.requestAuthorization { @Sendable _ in }
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        case .calendar:
            EKEventStore().requestFullAccessToEvents { @Sendable _, _ in }
        case .reminders:
            EKEventStore().requestFullAccessToReminders { @Sendable _, _ in }
        case .automation:
            openSettings(permission)
        }
    }

    static func openSettings(_ permission: Permission) {
        if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .authorized: .granted
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }
}
