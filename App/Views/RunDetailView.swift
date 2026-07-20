import JStore
import SwiftUI

/// Full timeline for a single run — foreground or background. Given a run id and
/// the RunStore, fetches the run header (kind, tokens, cost, duration) and the
/// interleaved assistant-text + tool rows, plus artifact links. Reachable from
/// the Runs pane; `onBack` returns to the list.
struct RunDetailView: View {
    let runID: String
    let runStore: RunStore
    var onBack: (() -> Void)? = nil

    @State private var detail: RunStore.RunDetail?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let detail {
                    header(detail)

                    ForEach(detail.items) { item in
                        switch item {
                        case .assistant(_, let text):
                            Text(text)
                                .font(.jarvisBody)
                                .foregroundStyle(.white.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .tool(let tool):
                            RunToolRow(tool: tool)
                        }
                    }

                    if !detail.artifacts.isEmpty {
                        Text("Artifacts")
                            .font(.jarvisFootnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 4)
                        ForEach(detail.artifacts) { ArtifactRowView(artifact: $0) }
                    }

                    if let error = detail.error, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.jarvisCaption)
                            .foregroundStyle(Color.jarvisError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }

                    if detail.items.isEmpty && detail.artifacts.isEmpty && (detail.error?.isEmpty ?? true) {
                        Text("No activity recorded for this run.")
                            .font(.jarvisCaption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else if !didLoad {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                        .padding(.top, 30)
                } else {
                    Text("Couldn't load this run.")
                        .font(.jarvisCaption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 30)
                }
            }
            .padding(.bottom, 10)
        }
        .task(id: runID) {
            didLoad = false
            detail = await runStore.fetchRun(id: runID)
            didLoad = true
        }
    }

    private func header(_ d: RunStore.RunDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.jarvisSurfaceHover))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .accessibilityLabel("Back to runs")
                }
                RunKindBadge(kind: d.kind)
                RunStatusDot(status: d.status)
                Text(d.label ?? d.kind.capitalized)
                    .font(.jarvisRow)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                metric("in", RunFormat.tokens(d.inputTokens))
                metric("out", RunFormat.tokens(d.outputTokens))
                if d.cacheReadTokens > 0 { metric("cache", RunFormat.tokens(d.cacheReadTokens)) }
                if let cost = RunFormat.cost(d.costUsd) { metric("cost", cost) }
                if let dur = RunFormat.duration(d.duration) { metric("took", dur) }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.jarvisCaption.weight(.medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            Text(label)
                .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.45))
        }
    }
}

/// One tool row in the detail timeline: name, state, duration, and an expandable
/// output preview.
private struct RunToolRow: View {
    let tool: RunStore.RunToolItem
    @State private var expanded = false

    private var hasOutput: Bool { !tool.output.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasOutput else { return }
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                        .font(.jarvisCaption)
                        .foregroundStyle(tint)
                    Text(tool.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    if let ms = tool.durationMs {
                        Text(RunFormat.durationMs(ms))
                            .font(.jarvisFootnote).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                    if hasOutput {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, hasOutput {
                // Expands in place; the detail view's outer ScrollView handles
                // long outputs instead of trapping them in a nested scroller.
                Text(tool.output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.jarvisSurface)
                .strokeBorder(Color.jarvisStroke, lineWidth: 1)
        )
    }

    private var icon: String {
        if tool.isError { return "exclamationmark.triangle.fill" }
        switch tool.state {
        case "error": return "exclamationmark.triangle.fill"
        case "running": return "gearshape.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        if tool.isError { return Color.jarvisError }
        switch tool.state {
        case "error": return Color.jarvisError
        case "running": return .white.opacity(0.6)
        default: return Color.jarvisSuccess
        }
    }
}

// MARK: - Shared run chrome (used by the Runs pane too)

/// Colored capsule badge for a run's kind (foreground / cron / heartbeat / nudge).
struct RunKindBadge: View {
    let kind: String

    private var color: Color {
        switch kind {
        case "foreground": Color.jarvisAccent
        case "cron": Color.jarvisWarning
        case "heartbeat": Color.jarvisSuccess
        case "nudge": Color.jarvisLink
        default: .white.opacity(0.55)
        }
    }

    var body: some View {
        Text(kind.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

/// Status dot shared between the run list and detail header.
struct RunStatusDot: View {
    let status: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }

    private var color: Color {
        switch status {
        case "done": Color.jarvisSuccess
        case "error": Color.jarvisError
        case "running": Color.jarvisWarning
        default: .white.opacity(0.4)
        }
    }
}

/// Compact numeric formatters shared across the Activity run views.
enum RunFormat {
    static func duration(_ t: TimeInterval?) -> String? {
        guard let t, t >= 0 else { return nil }
        if t < 1 { return "<1s" }
        if t < 60 { return String(format: "%.0fs", t) }
        return "\(Int(t) / 60)m \(Int(t) % 60)s"
    }

    static func durationMs(_ ms: Int) -> String {
        duration(TimeInterval(ms) / 1000) ?? "—"
    }

    static func cost(_ c: Double?) -> String? {
        guard let c else { return nil }
        return c < 0.01 ? "<$0.01" : String(format: "$%.2f", c)
    }

    static func tokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

/// One row in the live Runs list: kind badge, status, label, and a metrics line
/// (tokens, cost, duration, tool count). Tapping opens `RunDetailView`.
struct RunRowCard: View {
    let run: RunStore.RunSummary
    var artifactCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RunStatusDot(status: run.status)
                RunKindBadge(kind: run.kind)
                Text(run.label ?? run.kind.capitalized)
                    .font(.jarvisRow)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(run.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.jarvisFootnote).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 10) {
                metric("↑\(RunFormat.tokens(run.totalInputTokens))")
                metric("↓\(RunFormat.tokens(run.totalOutputTokens))")
                if let cost = RunFormat.cost(run.costUsd) { metric(cost) }
                if let dur = RunFormat.duration(run.duration) { metric(dur) }
                if !run.toolCalls.isEmpty {
                    metric("\(run.toolCalls.count) tool\(run.toolCalls.count == 1 ? "" : "s")")
                }
                if artifactCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "paperclip").font(.system(size: 8))
                        Text("\(artifactCount)").font(.jarvisFootnote).monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
        .contentShape(Rectangle())
    }

    private func metric(_ text: String) -> some View {
        Text(text)
            .font(.jarvisFootnote).monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
    }
}
