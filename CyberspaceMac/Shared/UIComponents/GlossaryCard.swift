import SwiftUI

struct GlossaryEntry: Identifiable {
    let id: String
    let term: String
    let definition: String
}

struct GlossaryCard: View {
    let title: String
    let entries: [GlossaryEntry]

    @State private var isExpanded = false

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $isExpanded) {
                    Text(isExpanded ? "Hide glossary" : "Show glossary")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(.switch)

                if isExpanded {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.definition)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
