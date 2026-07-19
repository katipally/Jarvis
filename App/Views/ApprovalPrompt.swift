import JAgent
import SwiftUI

/// The notch permission prompt: Approve / Always / Deny. Fail-closed handled by
/// the gate (timeout/dismiss → deny); this view just surfaces the decision.
struct ApprovalPrompt: View {
    let request: ApprovalRequest
    let presenter: ApprovalPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisWarning)
                Text("Jarvis wants to")
                    .font(.jarvisCaption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(request.summary)
                .font(.jarvisBody.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(3)

            HStack(spacing: 8) {
                ApprovalButton(title: "Deny", tint: .white.opacity(0.12), fg: .white.opacity(0.8), shortcut: .cancelAction) {
                    presenter.resolve(request, .deny(persist: false))
                }
                if request.scopeKey != nil {
                    ApprovalButton(title: "Always", tint: .white.opacity(0.12), fg: .white.opacity(0.8)) {
                        presenter.resolve(request, .allow(persist: true))
                    }
                }
                ApprovalButton(title: "Approve", tint: Color.jarvisAccent, fg: .white, shortcut: .defaultAction) {
                    presenter.resolve(request, .allow(persist: false))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .accessibilityAddTraits(.isModal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ApprovalButton: View {
    let title: String
    let tint: Color
    let fg: Color
    var shortcut: KeyboardShortcut? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.jarvisRow.weight(.semibold))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.white.opacity(isHovering ? 0.08 : 0))
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
