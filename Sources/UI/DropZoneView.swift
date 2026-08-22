import SwiftUI

/// The animated holographic drop target: a rotating HUD reticle with targeting
/// brackets that lock on and sweep-scan when a file hovers, and a success pulse
/// when a conversion completes.
struct DropZoneView: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var successFlash = false
    var compact = false
    var big = false

    private var panelHeight: CGFloat { big ? 260 : (compact ? 150 : 190) }

    var body: some View {
        Group {
            if reduceMotion {
                content(t: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { timeline in
                    content(t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill((successFlash ? Theme.success : Theme.accent).opacity(isTargeted || successFlash ? 0.10 : 0.03)))
        .liquidGlass(RoundedRectangle(cornerRadius: 22, style: .continuous),
                     tint: isTargeted ? Theme.accent.opacity(0.5) : nil, interactive: true)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isTargeted || successFlash ? 1.7 : 1)
            .shadow(color: borderColor.opacity(isTargeted || successFlash ? 0.7 : 0), radius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: isTargeted)
        .animation(.easeOut(duration: 0.4), value: successFlash)
        .onChange(of: coordinator.completedCount) { _, _ in pulseSuccess() }
        .dropReceiver(isTargeted: $isTargeted) { urls in coordinator.add(urls: urls) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isTargeted ? "Release to convert" : "Drop files to convert")
        .accessibilityHint("Drop images, audio, video, documents or data to convert them")
        .accessibilityAddTraits(.isButton)
    }

    private var borderColor: Color {
        if successFlash { return Theme.success }
        return isTargeted ? Theme.accent : Theme.accent.opacity(0.25)
    }

    private func pulseSuccess() {
        successFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            successFlash = false
        }
    }

    @ViewBuilder
    private func content(t: TimeInterval) -> some View {
        let spin = reduceMotion ? 0 : t.truncatingRemainder(dividingBy: 16) / 16 * 360
        let pulse = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 2.2)

        ZStack {
            if isTargeted && !reduceMotion { ScanSweep(t: t).allowsHitTesting(false) }
            reticle(spin: spin, pulse: pulse)

            VStack(spacing: compact ? 6 : 9) {
                Image(systemName: successFlash ? "checkmark.circle.fill"
                        : (isTargeted ? "arrow.down.circle.fill" : "cube.transparent"))
                    .font(.system(size: big ? 52 : (compact ? 30 : 40), weight: .light))
                    .foregroundStyle(successFlash ? Theme.success : Theme.accent)
                    .shadow(color: (successFlash ? Theme.success : Theme.accent).opacity(0.8),
                            radius: isTargeted || successFlash ? 14 : 8)
                    .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating, value: !isTargeted)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: 2) {
                    Text(successFlash ? "Done" : (isTargeted ? "Scanning — release to convert" : "Drop files to convert"))
                        .font(big ? .title3.weight(.semibold) : (compact ? .subheadline.weight(.semibold) : .headline))
                        .foregroundStyle(.white)
                    if !compact {
                        Text("Any file — images, audio, video, documents, data")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
    }

    private func reticle(spin: Double, pulse: Double) -> some View {
        let ringSize: CGFloat = big ? 190 : (compact ? 120 : 150)
        let color = successFlash ? Theme.success : Theme.accent
        return ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 12]))
                .foregroundStyle(color.opacity(0.55))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(spin))
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1, 7]))
                .foregroundStyle(Theme.accentDeep.opacity(0.5))
                .frame(width: ringSize - 26, height: ringSize - 26)
                .rotationEffect(.degrees(-spin * 1.6))
            CornerBrackets()
                .stroke(color.opacity(isTargeted ? 0.95 : 0.4),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: ringSize + (isTargeted ? 40 : 30) + CGFloat(pulse * 6),
                       height: ringSize + (isTargeted ? 40 : 30) + CGFloat(pulse * 6))
                .shadow(color: color.opacity(isTargeted ? 0.6 : 0), radius: 6)
        }
        .allowsHitTesting(false)
    }
}

/// Four L-shaped HUD targeting brackets.
struct CornerBrackets: Shape {
    var arm: CGFloat = 0.26
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let a = min(rect.width, rect.height) * arm
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (c, dx, dy) in corners {
            p.move(to: CGPoint(x: c.x + dx * a, y: c.y))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y + dy * a))
        }
        return p
    }
}

/// A bright horizontal line that sweeps top-to-bottom while a file is over the zone.
struct ScanSweep: View {
    let t: TimeInterval
    var body: some View {
        GeometryReader { geo in
            let phase = (t * 0.9).truncatingRemainder(dividingBy: 1)
            let y = geo.size.height * phase
            LinearGradient(colors: [.clear, Theme.accent.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 40).blur(radius: 6).offset(y: y - 20)
        }
    }
}
