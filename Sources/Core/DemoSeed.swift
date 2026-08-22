#if DEBUG
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// DEBUG helper: when launched with RECAST_DEMO=1, stages a few real sample files
/// and drops them into the queue so the job UI can be exercised / screenshotted
/// without manual interaction. Never compiled into release builds.
extension ConversionCoordinator {
    func seedDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["RECAST_DEMO"] == "1" else { return }
        guard jobs.isEmpty else { return }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RecastDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // a small gradient PNG (image → cyan)
        let png = dir.appendingPathComponent("sunset-photo.png")
        writeGradientPNG(to: png, size: 96)

        // a JSON file (data → green)
        let json = dir.appendingPathComponent("config.json")
        try? Data("""
        [{"city":"Munich","temp":21},{"city":"Belgrade","temp":28}]
        """.utf8).write(to: json)

        // a text document (document → blue)
        let txt = dir.appendingPathComponent("notes.txt")
        try? Data("Recast\n\nUniversal on-device file conversion.\n".utf8).write(to: txt)

        add(urls: [png, json, txt])
    }

    private func writeGradientPNG(to url: URL, size: Int) {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        let colors = [CGColor(red: 0.31, green: 0.91, blue: 0.96, alpha: 1),
                      CGColor(red: 0.54, green: 0.30, blue: 0.95, alpha: 1)] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size, y: size), options: [])
        }
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
