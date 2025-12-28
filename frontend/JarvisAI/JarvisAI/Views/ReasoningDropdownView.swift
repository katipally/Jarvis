import SwiftUI

// MARK: - Reasoning Dropdown View (HIG Compliant)
// Uses native DisclosureGroup for standard macOS behavior

struct ReasoningDropdownView: View {
    let reasoning: [String]
    @Binding var isExpanded: Bool
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reasoning.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        // Step number badge
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor.opacity(0.8), in: Circle())
                        
                        // Step content
                        Text(reasoning[index])
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
                    if index < reasoning.count - 1 {
                        Divider()
                            .padding(.leading, 30)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text("AI Reasoning")
                        .font(.subheadline.weight(.medium))
                    
                    Text("·")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(reasoning.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "brain")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
        }
        .tint(.accentColor)
    }
}

#Preview {
    VStack(spacing: 20) {
        ReasoningDropdownView(
            reasoning: [
                "Analyzing the user's query for key concepts",
                "Searching knowledge base for relevant information",
                "Formulating a comprehensive response"
            ],
            isExpanded: .constant(true)
        )
        
        ReasoningDropdownView(
            reasoning: ["Quick analysis", "Response ready"],
            isExpanded: .constant(false)
        )
    }
    .padding()
    .frame(width: 400)
}
