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
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
                Text("Jarvis wants to")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(request.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)

            HStack(spacing: 8) {
                button("Deny", tint: .white.opacity(0.12), fg: .white.opacity(0.8)) {
                    presenter.resolve(request, .deny(persist: false))
                }
                if request.scopeKey != nil {
                    button("Always", tint: .white.opacity(0.12), fg: .white.opacity(0.8)) {
                        presenter.resolve(request, .allow(persist: true))
                    }
                }
                button("Approve", tint: Color(red: 0.3, green: 0.55, blue: 1.0), fg: .white) {
                    presenter.resolve(request, .allow(persist: false))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func button(_ title: String, tint: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
        }
        .buttonStyle(.plain)
    }
}
