import Foundation
import SwiftUI

/// Owns the job queue and drives conversions through the engine.
@MainActor
final class ConversionCoordinator: ObservableObject {

    static let shared = ConversionCoordinator()

    @Published private(set) var jobs: [ConversionJob] = []
    @Published private(set) var isProcessing = false
    @Published var showProGate = false
    @Published var outputDestination: OutputDestination
    /// Increments each time a job finishes successfully — used to flash the drop zone.
    @Published private(set) var completedCount = 0
    /// Transient banner text (e.g. "2 unsupported files skipped"); auto-clears.
    @Published var dropNotice: String?

    let engine = ConversionEngine.shared
    private let settings = ConversionSettings.shared
    private let pro = ProManager.shared

    private var runTask: Task<Void, Never>?
    private var currentJob: ConversionJob?
    private var noticeTask: Task<Void, Never>?

    private init() {
        #if os(macOS)
        outputDestination = .nextToOriginal
        #else
        outputDestination = .appExports
        #endif
    }

    // MARK: Intake

    func add(urls: [URL], securityScoped: Bool = false) {
        var files: [URL] = []
        var expandedFromFolder = false
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                expandedFromFolder = true
                files.append(contentsOf: contentsOfFolder(url, securityScoped: securityScoped))
            } else {
                files.append(url)
            }
        }
        let convertible = files.filter { Catalog.format(for: $0) != nil }
        let skipped = files.count - convertible.count
        if skipped > 0 {
            note("\(skipped) unsupported file\(skipped == 1 ? "" : "s") skipped")
        }
        guard !convertible.isEmpty else {
            if files.isEmpty { note("Nothing to convert") }
            return
        }

        if !pro.hasAccess {
            showProGate = true
            return
        }
        enqueue(convertible, securityScoped: securityScoped)
    }

    private func enqueue(_ urls: [URL], securityScoped: Bool) {
        let auto = settings.autoConvertOnDrop
        for url in urls {
            guard let source = Catalog.format(for: url) else { continue }
            let target = defaultTarget(for: source)
            let job = ConversionJob(sourceURL: url, sourceFormat: source,
                                    target: target, securityScoped: securityScoped)
            job.status = auto ? .queued : .ready
            jobs.append(job)
        }
        if auto { startProcessing() }
    }

    private func defaultTarget(for source: Format) -> Format {
        let preferred = settings.lastTarget(for: source.category)
        if preferred.id != source.id, engine.canConvert(from: source.id, to: preferred.id) {
            return preferred
        }
        let reachable = engine.reachableTargets(from: source.id)
        return reachable.first { $0.category == source.category } ?? reachable.first ?? preferred
    }

    private func contentsOfFolder(_ folder: URL, securityScoped: Bool) -> [URL] {
        let accessing = securityScoped && folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard let en = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let item as URL in en where Catalog.format(for: item) != nil { result.append(item) }
        return result
    }

    private func note(_ text: String) {
        dropNotice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.dropNotice = nil }
        }
    }

    // MARK: Processing

    private func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        runTask = Task { await drain() }
    }

    private func drain() async {
        while let job = jobs.first(where: { $0.status == .queued }) {
            await run(job)
        }
        isProcessing = false
        currentJob = nil
    }

    private func run(_ job: ConversionJob) async {
        currentJob = job
        job.status = .running
        job.progress = 0
        let accessing = job.securityScoped && job.sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { job.sourceURL.stopAccessingSecurityScopedResource() } }

        let opts = settings.options
        let from = job.sourceFormat
        let to = job.target
        do {
            try Task.checkCancellation()
            let temp = try await engine.run(source: job.sourceURL, from: from, to: to, options: opts) { p in
                Task { @MainActor in job.progress = p }
            }
            try Task.checkCancellation()
            let final = try place(temp, for: job)
            job.outputURL = final
            job.outputSize = (try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            job.progress = 1
            job.status = .done
            completedCount += 1
        } catch is CancellationError {
            job.status = .cancelled
        } catch ConversionError.cancelled {
            job.status = .cancelled
        } catch {
            job.status = .failed(error.localizedDescription)
        }
    }

    // MARK: Output placement

    private func place(_ tempURL: URL, for job: ConversionJob) throws -> URL {
        let fm = FileManager.default
        let baseName = job.sourceURL.deletingPathExtension().lastPathComponent
        let ext = job.target.ext
        let fileName = "\(baseName)\(settings.namingSuffix).\(ext)"

        let folder: URL
        switch outputDestination {
        case .nextToOriginal: folder = job.sourceURL.deletingLastPathComponent()
        case .folder(let url): folder = url
        case .appExports: folder = exportsFolder()
        }
        let accessing: Bool
        if case .folder(let url) = outputDestination { accessing = url.startAccessingSecurityScopedResource() }
        else { accessing = false }
        defer { if accessing, case .folder(let url) = outputDestination { url.stopAccessingSecurityScopedResource() } }

        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = uniqueURL(in: folder, fileName: fileName)
        do { try fm.moveItem(at: tempURL, to: destination) }
        catch {
            try fm.copyItem(at: tempURL, to: destination)
            try? fm.removeItem(at: tempURL)
        }
        return destination
    }

    private func uniqueURL(in folder: URL, fileName: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 2
        repeat {
            candidate = folder.appendingPathComponent("\(name) \(n).\(ext)")
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    private func exportsFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recast Exports", isDirectory: true)
    }

    // MARK: Queries

    func reachableTargets(for job: ConversionJob) -> [Format] {
        engine.reachableTargets(from: job.sourceFormat.id)
    }

    /// Formats every *unfinished* job can reach (intersection) — for "Convert all to…".
    func commonReachableTargets() -> [Format] {
        let active = jobs.filter { !$0.isFinished }
        guard let first = active.first else { return [] }
        var set = Set(engine.reachableTargets(from: first.sourceFormat.id).map { $0.id })
        for job in active.dropFirst() {
            set.formIntersection(engine.reachableTargets(from: job.sourceFormat.id).map { $0.id })
        }
        return set.compactMap { Catalog.format(id: $0) }
            .sorted { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
    }

    var readyCount: Int { jobs.filter { $0.status == .ready }.count }
    var hasFinishedJobs: Bool { jobs.contains { $0.isFinished } }

    // MARK: Actions

    func reconvert(_ job: ConversionJob, as format: Format) {
        settings.setLastTarget(format, for: job.sourceFormat.category)
        let new = ConversionJob(sourceURL: job.sourceURL, sourceFormat: job.sourceFormat,
                                target: format, securityScoped: job.securityScoped)
        jobs.append(new)
        startProcessing()
    }

    /// Manual mode: user picked a target on a `.ready` job and pressed Convert.
    func startReady(_ job: ConversionJob) {
        guard job.status == .ready else { return }
        job.status = .queued
        startProcessing()
    }

    func startAllReady() {
        for job in jobs where job.status == .ready { job.status = .queued }
        startProcessing()
    }

    /// Retarget a `.ready` job in place (no conversion yet).
    func retarget(_ job: ConversionJob, to format: Format) {
        settings.setLastTarget(format, for: job.sourceFormat.category)
        if job.status == .ready { job.target = format } else { reconvert(job, as: format) }
    }

    func convertAll(to format: Format) {
        for job in jobs where !job.isFinished {
            job.target = format
            if job.status == .ready { job.status = .queued }
        }
        startProcessing()
    }

    func cancel(_ job: ConversionJob) {
        switch job.status {
        case .running:
            runTask?.cancel()
        case .queued, .ready:
            job.status = .cancelled
        default:
            break
        }
    }

    func setDefaultTarget(_ format: Format, for category: FormatCategory) {
        settings.setLastTarget(format, for: category)
    }

    func clearFinished() { jobs.removeAll { $0.isFinished } }
    func clearAll() {
        runTask?.cancel()
        jobs.removeAll()
    }
    func remove(_ job: ConversionJob) {
        if job.status == .running { runTask?.cancel() }
        jobs.removeAll { $0.id == job.id }
    }
}
