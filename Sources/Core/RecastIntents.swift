import AppIntents
import Foundation
import UniformTypeIdentifiers

/// A target format exposed to Shortcuts as a searchable list of all 58 formats.
struct FormatEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let ext: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Format" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: ".\(ext)")
    }
    static var defaultQuery = FormatQuery()
}

struct FormatQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FormatEntity] {
        identifiers.compactMap { id in
            Catalog.format(id: id).map { FormatEntity(id: $0.id, name: $0.name, ext: $0.ext) }
        }
    }
    func suggestedEntities() async throws -> [FormatEntity] {
        Catalog.all.map { FormatEntity(id: $0.id, name: $0.name, ext: $0.ext) }
    }
}

/// "Convert File" — the Shortcuts / Siri / (user-enablable) Finder Quick Action.
/// Runs the same on-device engine as the app and returns the converted file.
struct ConvertFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert File"
    static var description = IntentDescription(
        "Convert a file to another format, entirely on-device.",
        categoryName: "Conversion")

    @Parameter(title: "File")
    var file: IntentFile

    @Parameter(title: "Convert to")
    var target: FormatEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$file) to \(\.$target)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // Resolve the source to a real file on disk.
        let srcURL: URL
        if let url = file.fileURL {
            srcURL = url
        } else {
            srcURL = workDir.appendingPathComponent(file.filename)
            try file.data.write(to: srcURL)
        }

        guard let from = Catalog.format(for: srcURL) else {
            throw ConversionError.unsupportedSource(srcURL.lastPathComponent)
        }
        guard let to = Catalog.format(id: target.id) else {
            throw ConversionError.unsupportedTarget("Unknown target format.")
        }

        let produced = try await ConversionEngine.shared.run(
            source: srcURL, from: from, to: to, options: ConversionOptions()) { _ in }

        // Give the result the original base name with the new extension.
        let friendly = workDir
            .appendingPathComponent(srcURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(to.ext)
        if produced != friendly {
            try? FileManager.default.removeItem(at: friendly)
            try? FileManager.default.moveItem(at: produced, to: friendly)
        }
        let result = FileManager.default.fileExists(atPath: friendly.path) ? friendly : produced
        return .result(value: IntentFile(fileURL: result, filename: result.lastPathComponent))
    }
}

struct RecastShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConvertFileIntent(),
            phrases: ["Convert a file with \(.applicationName)"],
            shortTitle: "Convert File",
            systemImageName: "arrow.left.arrow.right")
    }
}
