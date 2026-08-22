import SwiftUI

struct QueueListView: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    @EnvironmentObject private var pro: ProManager
    var maxHeight: CGFloat = 230

    var body: some View {
        if coordinator.jobs.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 7) {
                header
                queueScroll
                    .animation(.snappy, value: coordinator.jobs.count)
            }
        }
    }

    /// A scroll view with a *definite* height so the enclosing menu-bar window
    /// grows to show the rows (a purely flexible ScrollView collapses to nothing).
    private var queueScroll: some View {
        let rowH: CGFloat = 69
        let content = ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(coordinator.jobs.reversed()) { job in
                    JobRowView(job: job)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity))
                }
            }
        }
        return Group {
            if maxHeight == .infinity {
                content.frame(maxHeight: .infinity)
            } else {
                content.frame(height: min(maxHeight, CGFloat(coordinator.jobs.count) * rowH))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("QUEUE")
                .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("\(coordinator.jobs.count)")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            if coordinator.readyCount > 1 {
                Button { coordinator.startAllReady() } label: {
                    Text("Convert \(coordinator.readyCount)").font(.caption.weight(.bold))
                }
                .tint(Theme.accent).glassButton().controlSize(.mini)
            }

            batchMenu

            if coordinator.hasFinishedJobs {
                Button("Clear done") { withAnimation(.snappy) { coordinator.clearFinished() } }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Button("Clear all") { withAnimation(.snappy) { coordinator.clearAll() } }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder private var batchMenu: some View {
        let unfinished = coordinator.jobs.filter { !$0.isFinished }
        if unfinished.count > 1 {
            let common = coordinator.commonReachableTargets()
            if !common.isEmpty {
                GroupedFormatMenu(formats: common, selectedID: nil,
                                  onPick: { fmt in
                                      if pro.isPro { coordinator.convertAll(to: fmt) }
                                      else { coordinator.showProGate = true }
                                  }) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 9))
                        Text("Convert all").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
    }
}

/// Transient banner: "2 unsupported files skipped" etc.
struct DropNoticeBanner: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    var body: some View {
        if let notice = coordinator.dropNotice {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption2)
                Text(notice).font(.caption)
                Spacer()
            }
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.amber.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.amber.opacity(0.3), lineWidth: 1))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
