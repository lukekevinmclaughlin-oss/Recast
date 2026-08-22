import SwiftUI

struct JobRowView: View {
    @ObservedObject var job: ConversionJob
    @EnvironmentObject private var coordinator: ConversionCoordinator

    private var tint: Color { Theme.color(for: job.sourceFormat.category) }

    var body: some View {
        HStack(spacing: 11) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(job.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)

                HStack(spacing: 6) {
                    FormatBadge(format: job.sourceFormat)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                    TargetMenu(job: job, onPick: { coordinator.retarget(job, to: $0) }) {
                        HStack(spacing: 3) {
                            Text(job.target.name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Theme.color(for: job.target.category).opacity(0.4), lineWidth: 0.8))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Change target format, currently \(job.target.name)")
                }

                if let summary = job.sizeSummary {
                    Text(summary).font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 6)
            statusTrailing
        }
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(statusColor.opacity(0.35), lineWidth: 1))
        #if os(macOS)
        // Drag a finished file straight out to Finder or another app.
        .onDrag {
            if case .done = job.status, let url = job.outputURL {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.fileName), \(job.sourceFormat.name) to \(job.target.name), \(statusDescription)")
    }

    private var iconBadge: some View {
        ZStack {
            Circle().fill(statusColor.opacity(0.16)).frame(width: 32, height: 32)
            Image(systemName: job.sourceFormat.category.symbol)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(statusColor)
        }
        .accessibilityHidden(true)
    }

    private var statusColor: Color {
        switch job.status {
        case .ready: return tint
        case .queued: return Theme.accentDeep
        case .running: return Theme.accent
        case .done: return Theme.success
        case .failed: return Theme.amber
        case .cancelled: return .gray
        }
    }

    private var statusDescription: String {
        switch job.status {
        case .ready: return "ready to convert"
        case .queued: return "queued"
        case .running: return "converting, \(Int(job.progress * 100)) percent"
        case .done: return "done"
        case .failed(let m): return "failed: \(m)"
        case .cancelled: return "cancelled"
        }
    }

    @ViewBuilder private var statusTrailing: some View {
        switch job.status {
        case .ready:
            HStack(spacing: 8) {
                Button { coordinator.startReady(job) } label: {
                    Text("Convert").font(.caption.weight(.bold))
                }
                .tint(Theme.accent).glassButton().controlSize(.small)
                .accessibilityLabel("Convert \(job.fileName)")
                removeButton
            }
        case .queued:
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.white.opacity(0.4)).font(.caption)
                removeButton
            }
        case .running:
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    GlowBar(progress: job.progress).frame(width: 60, height: 5)
                    Text("\(Int(job.progress * 100))%")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                }
                iconButton("xmark.circle.fill", "Cancel conversion") { coordinator.cancel(job) }
            }
        case .done:
            HStack(spacing: 10) {
                #if os(macOS)
                iconButton("magnifyingglass", "Reveal in Finder") { if let u = job.outputURL { FileActions.reveal(u) } }
                #else
                if let u = job.outputURL { ShareLink(item: u) { Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent) } }
                #endif
                Image(systemName: "checkmark.seal.fill").foregroundStyle(statusColor)
                    .symbolEffect(.bounce, value: job.outputURL)
                    .accessibilityHidden(true)
                removeButton
            }
        case .failed(let msg):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber).help(msg)
                removeButton
            }
        case .cancelled:
            removeButton
        }
    }

    private var removeButton: some View {
        iconButton("xmark", "Remove from list") { coordinator.remove(job) }
    }

    private func iconButton(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).foregroundStyle(name == "xmark" ? .white.opacity(0.35) : Theme.accent)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A slim progress bar with a moving cyan glow highlight.
struct GlowBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accentDeep, Theme.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, geo.size.width * progress))
                    .shadow(color: Theme.accent.opacity(0.7), radius: 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}
