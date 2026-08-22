import Foundation

/// Structured-data conversion, entirely in Swift. Everything decodes to a common
/// Foundation object model (dicts / arrays / scalars) and re-encodes to the
/// target, so any reader pairs with any writer.
struct DataBackend: ConversionBackend {
    let id = "data"
    var isAvailable: Bool { true }

    private let formats = ["json", "plist", "yaml", "xml", "csv", "tsv"]

    func edges() -> [FormatEdge] {
        var e: [FormatEdge] = []
        for a in formats {
            for b in formats where a != b {
                e.append(FormatEdge(from: a, to: b, backendID: id, cost: 1.0))
            }
        }
        return e
    }

    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let data = try Data(contentsOf: source)
        let object = try decode(data, as: from.id)
        let outData = try encode(object, as: to.id)
        let out = tempURL(for: to)
        try outData.write(to: out)
        progress(1)
        return out
    }

    // MARK: Decoders

    private func decode(_ data: Data, as fmt: String) throws -> Any {
        switch fmt {
        case "json":
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        case "plist":
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        case "yaml":
            guard let s = String(data: data, encoding: .utf8) else { throw ConversionError.readFailed }
            return MiniYAML.parse(s)
        case "xml":
            return try MiniXML.parse(data)
        case "csv", "tsv":
            guard let s = String(data: data, encoding: .utf8) else { throw ConversionError.readFailed }
            let rows = DelimitedText.parse(s, delimiter: fmt == "csv" ? "," : "\t")
            return DelimitedText.rowsToObjects(rows)
        default:
            throw ConversionError.unsupportedSource(fmt)
        }
    }

    // MARK: Encoders

    private func encode(_ object: Any, as fmt: String) throws -> Data {
        switch fmt {
        case "json":
            return try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        case "plist":
            return try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        case "yaml":
            return Data(MiniYAML.emit(object).utf8)
        case "xml":
            return Data(MiniXML.emit(object).utf8)
        case "csv", "tsv":
            let rows = try DelimitedText.objectsToRows(object)
            return Data(DelimitedText.serialize(rows, delimiter: fmt == "csv" ? "," : "\t").utf8)
        default:
            throw ConversionError.unsupportedTarget("Unsupported data target.")
        }
    }
}

// MARK: - Delimited text (CSV / TSV)

enum DelimitedText {
    /// RFC4180-ish parser: honours quotes, escaped quotes and embedded newlines.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case delimiter: endField()
                case "\n": endRow()
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func rowsToObjects(_ rows: [[String]]) -> Any {
        guard let header = rows.first, rows.count > 1 else { return rows }
        return rows.dropFirst().map { row -> [String: Any] in
            var obj: [String: Any] = [:]
            for (i, key) in header.enumerated() { obj[key] = i < row.count ? row[i] : "" }
            return obj
        }
    }

    static func objectsToRows(_ object: Any) throws -> [[String]] {
        guard let array = object as? [Any] else {
            throw ConversionError.unsupportedTarget("CSV/TSV needs a top-level list of rows.")
        }
        if let dicts = array as? [[String: Any]] {
            var keys: [String] = []
            for d in dicts { for k in d.keys where !keys.contains(k) { keys.append(k) } }
            keys.sort()
            var rows: [[String]] = [keys]
            for d in dicts { rows.append(keys.map { stringify(d[$0]) }) }
            return rows
        }
        if let arrays = array as? [[Any]] {
            return arrays.map { $0.map { stringify($0) } }
        }
        return [array.map { stringify($0) }]
    }

    static func serialize(_ rows: [[String]], delimiter: Character) -> String {
        let d = String(delimiter)
        return rows.map { row in
            row.map { field -> String in
                if field.contains(delimiter) || field.contains("\"") || field.contains("\n") {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }.joined(separator: d)
        }.joined(separator: "\n")
    }

    static func stringify(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case .none, is NSNull: return ""
        default: return String(describing: v ?? "")
        }
    }
}
