import SwiftUI

/// A menu of formats grouped by category, with a checkmark on the current pick.
/// Shared by the per-file target picker and the batch "Convert all to…" control.
struct GroupedFormatMenu<LabelContent: View>: View {
    let formats: [Format]
    let selectedID: String?
    let onPick: (Format) -> Void
    @ViewBuilder var label: () -> LabelContent

    var body: some View {
        Menu {
            ForEach(FormatCategory.allCases) { category in
                section(for: category)
            }
        } label: {
            label()
        }
    }

    @ViewBuilder
    private func section(for category: FormatCategory) -> some View {
        let items = grouped[category] ?? []
        if !items.isEmpty {
            Section(category.title) {
                ForEach(items) { format in
                    Button { onPick(format) } label: {
                        if format.id == selectedID {
                            Label(format.name, systemImage: "checkmark")
                        } else {
                            Text(format.name)
                        }
                    }
                }
            }
        }
    }

    private var grouped: [FormatCategory: [Format]] {
        Dictionary(grouping: formats.sorted { $0.name < $1.name }, by: { $0.category })
    }
}

/// Per-file "Convert to…" menu listing every format the file can reach.
struct TargetMenu<LabelContent: View>: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    let job: ConversionJob
    let onPick: (Format) -> Void
    @ViewBuilder var label: () -> LabelContent

    var body: some View {
        GroupedFormatMenu(formats: coordinator.reachableTargets(for: job),
                          selectedID: job.target.id, onPick: onPick, label: label)
    }
}

/// Small pill showing a format's short code, tinted by its category.
struct FormatBadge: View {
    let format: Format
    var body: some View {
        let tint = Theme.color(for: format.category)
        Text(format.ext.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.8))
            .accessibilityLabel("\(format.name) format")
    }
}
