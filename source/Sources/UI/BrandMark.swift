import SwiftUI

/// Miniature animated version of the app logo: a rotating reticle around a
/// glowing data-core glyph. Used in headers.
struct BrandMark: View {
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            mark(spin: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                mark(spin: t.truncatingRemainder(dividingBy: 12) / 12 * 360)
            }
        }
    }

    private func mark(spin: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .rotationEffect(.degrees(spin))
            Image(systemName: "cube.transparent")
                .font(.system(size: size * 0.5, weight: .light))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.8), radius: 4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The wordmark used in headers.
struct BrandTitle: View {
    var body: some View {
        Text("Recast")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(0.35), radius: 6)
    }
}
