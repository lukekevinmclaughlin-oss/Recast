import SwiftUI

// MARK: - Palette

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    static let accent = Color(hex: 0x4FE9F5)     // holographic cyan (app chrome)
    static let accentDeep = Color(hex: 0x2CB6E8)
    static let amber = Color(hex: 0xFFC24D)      // Stark accent
    static let bgTop = Color(hex: 0x12233B)
    static let bgBottom = Color(hex: 0x05080F)
    static let panelStroke = Color.white.opacity(0.10)
    static let hairline = Color(hex: 0x3FC9E6, alpha: 0.25)
    static let success = Color(hex: 0x54E39B)

    /// Per-category accent, so file types are scannable at a glance.
    static func color(for category: FormatCategory) -> Color {
        switch category {
        case .image:    return Color(hex: 0x4FE9F5) // cyan
        case .audio:    return Color(hex: 0xB98CFF) // violet
        case .video:    return Color(hex: 0xFF8A5B) // orange
        case .document: return Color(hex: 0x5B8CFF) // blue
        case .data:     return Color(hex: 0x54E39B) // green
        case .vector:   return Color(hex: 0xFFC24D) // amber
        case .archive:  return Color(hex: 0x9AA6B2) // slate
        case .ebook:    return Color(hex: 0xFF6FB5) // pink
        }
    }
}

// MARK: - Liquid Glass (with pre-26 fallbacks)

extension View {
    /// Applies Liquid Glass on macOS/iOS 26+, falling back to a material panel.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S,
                                         tint: Color? = nil,
                                         interactive: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(Self.recastGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.panelStroke, lineWidth: 1))
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private static func recastGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Glass button style on 26+, sensible fallback before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

/// Groups overlapping glass shapes so they blend/merge correctly (26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Animated holographic background

/// The signature Jarvis-style backdrop: a dark field with slowly drifting cyan
/// aurora glows, a faint node grid and a soft vertical scan sweep. Pure Canvas so
/// it runs on every supported OS version, not just 26.
struct HoloBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Static single frame — no continuous animation.
                Canvas { ctx, size in draw(&ctx, size: size, t: 0) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { ctx, size in
                        draw(&ctx, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(
                    Gradient(colors: [Theme.bgTop, Theme.bgBottom]),
                    center: CGPoint(x: w * 0.5, y: h * 0.32),
                    startRadius: 0, endRadius: max(w, h) * 0.95))

        let blobs: [(Color, Double, Double, CGFloat)] = [
            (Theme.accentDeep, 0.11, 0.0, 0.55),
            (Color(hex: 0x3B6DFF), 0.07, 2.1, 0.48),
            (Theme.accent, 0.09, 4.2, 0.40),
        ]
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 80))
            for (color, speed, phase, rf) in blobs {
                let cx = w * (0.5 + 0.34 * cos(t * speed + phase))
                let cy = h * (0.42 + 0.30 * sin(t * speed * 1.3 + phase))
                let r = min(w, h) * rf
                layer.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                           with: .color(color.opacity(0.22)))
            }
        }

        let step: CGFloat = 34
        var dots = Path()
        var y: CGFloat = step / 2
        while y < h { var x: CGFloat = step / 2
            while x < w { dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)); x += step }
            y += step
        }
        ctx.fill(dots, with: .color(Theme.accent.opacity(0.05)))

        let scanY = h * (0.5 + 0.5 * sin(t * 0.35))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.fill(Path(CGRect(x: 0, y: scanY - 1.5, width: w, height: 3)),
                       with: .color(Theme.accent.opacity(0.16)))
        }
    }
}
