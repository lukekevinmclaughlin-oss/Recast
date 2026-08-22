import SwiftUI

/// Surfaces the engine's real coverage: how many formats/conversions are wired
/// up right now and which power tools were detected.
struct CapabilitiesBar: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    var compact = false

    var body: some View {
        let cap = coordinator.engine.capabilities
        HStack(spacing: 8) {
            stat("\(cap.formatCount)", "formats")
            divider
            stat("\(cap.edgeCount)", "conversions")
            if !compact {
                divider
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(Theme.accent)
                    Text(cap.detectedTools.joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.035)))
        .liquidGlass(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.accent)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14)
    }
}
