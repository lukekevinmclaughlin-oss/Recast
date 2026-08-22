import Foundation

/// The heart of Recast: aggregates every backend's capabilities into one directed
/// graph of formats, finds the cheapest path between any two (chaining hops when
/// needed, e.g. docx → html → pdf), and executes it.
final class ConversionEngine {

    static let shared = ConversionEngine()

    private let backends: [ConversionBackend]
    private let backendByID: [String: ConversionBackend]
    /// best (lowest-cost) edge for each (from,to)
    private let bestEdge: [Pair: FormatEdge]
    /// adjacency: from-id → [to-id]
    private let adjacency: [String: [String]]

    struct Pair: Hashable { let from: String; let to: String }

    init(backends: [ConversionBackend]? = nil) {
        var list: [ConversionBackend] = backends ?? [
            ImageBackend(),
            AudioVideoBackend(),
            PDFBackend(),
            DataBackend(),
        ]
        #if os(macOS)
        if backends == nil {
            list.append(DocumentBackend())
            #if !APP_STORE
            list.append(ExternalToolBackend())
            #endif
        }
        #endif

        let available = list.filter { $0.isAvailable }
        self.backends = available
        self.backendByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })

        var best: [Pair: FormatEdge] = [:]
        for backend in available {
            for edge in backend.edges() {
                let key = Pair(from: edge.from, to: edge.to)
                if let existing = best[key], existing.cost <= edge.cost { continue }
                best[key] = edge
            }
        }
        self.bestEdge = best

        var adj: [String: [String]] = [:]
        for key in best.keys { adj[key.from, default: []].append(key.to) }
        self.adjacency = adj
    }

    // MARK: Capability queries

    /// Every format reachable from `sourceID` (one or more hops), sorted by category.
    func reachableTargets(from sourceID: String) -> [Format] {
        var seen: Set<String> = [sourceID]
        var queue = [sourceID]
        var result: Set<String> = []
        while let node = queue.popLast() {
            for next in adjacency[node] ?? [] where !seen.contains(next) {
                seen.insert(next); result.insert(next); queue.append(next)
            }
        }
        return result.compactMap { Catalog.format(id: $0) }
            .sorted { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
    }

    func canConvert(from: String, to: String) -> Bool { plan(from: from, to: to) != nil }

    struct Capabilities {
        let formatCount: Int
        let edgeCount: Int
        let detectedTools: [String]
    }

    var capabilities: Capabilities {
        var tools = ["Apple frameworks"]
        #if os(macOS) && !APP_STORE
        tools += ExternalToolBackend.detected
        #endif
        let nodes = Set(bestEdge.keys.flatMap { [$0.from, $0.to] })
        return Capabilities(formatCount: nodes.count, edgeCount: bestEdge.count, detectedTools: tools)
    }

    // MARK: Routing (Dijkstra over edge costs)

    func plan(from: String, to: String) -> [FormatEdge]? {
        if from == to { return [] }
        var dist: [String: Double] = [from: 0]
        var prev: [String: FormatEdge] = [:]
        var visited: Set<String> = []
        var frontier: [(String, Double)] = [(from, 0)]

        while !frontier.isEmpty {
            frontier.sort { $0.1 < $1.1 }
            let (node, d) = frontier.removeFirst()
            if node == to { break }
            if visited.contains(node) { continue }
            visited.insert(node)
            for next in adjacency[node] ?? [] {
                guard let edge = bestEdge[Pair(from: node, to: next)] else { continue }
                let nd = d + edge.cost
                if nd < (dist[next] ?? .infinity) {
                    dist[next] = nd; prev[next] = edge
                    frontier.append((next, nd))
                }
            }
        }
        guard dist[to] != nil else { return nil }
        var path: [FormatEdge] = []
        var cur = to
        while cur != from {
            guard let edge = prev[cur] else { return nil }
            path.append(edge); cur = edge.from
        }
        return path.reversed()
    }

    // MARK: Execution

    func run(source: URL, from: Format, to: Format,
             options: ConversionOptions,
             progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let steps = plan(from: from.id, to: to.id), !steps.isEmpty else {
            throw ConversionError.unsupportedTarget("No conversion path from \(from.name) to \(to.name).")
        }
        var current = source
        var intermediates: [URL] = []
        let n = Double(steps.count)

        for (i, edge) in steps.enumerated() {
            guard let backend = backendByID[edge.backendID],
                  let stepFrom = Catalog.format(id: edge.from),
                  let stepTo = Catalog.format(id: edge.to) else {
                throw ConversionError.exportFailed("Broken conversion step.")
            }
            let base = Double(i)
            let output = try await backend.convert(source: current, from: stepFrom, to: stepTo,
                                                   options: options) { p in
                progress((base + p) / n)
            }
            if i > 0 { intermediates.append(current) }
            current = output
        }
        // clean up intermediate temp files (keep the final output)
        for url in intermediates where url != current { try? FileManager.default.removeItem(at: url) }
        progress(1)
        return current
    }
}
