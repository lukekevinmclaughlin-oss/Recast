import Foundation

/// A compact YAML emitter + parser for the common subset (nested maps, lists,
/// scalars). Not a full YAML 1.2 implementation — enough for round-tripping
/// config/data files. Falls back to strings for anything ambiguous.
enum MiniYAML {

    // MARK: Emit

    static func emit(_ object: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch object {
        case let dict as [String: Any]:
            if dict.isEmpty { return "\(pad){}\n" }
            var out = ""
            for key in dict.keys.sorted() {
                let value = dict[key]!
                if isScalar(value) {
                    out += "\(pad)\(escapeKey(key)): \(scalar(value))\n"
                } else {
                    out += "\(pad)\(escapeKey(key)):\n" + emit(value, indent: indent + 1)
                }
            }
            return out
        case let array as [Any]:
            if array.isEmpty { return "\(pad)[]\n" }
            var out = ""
            for item in array {
                if isScalar(item) {
                    out += "\(pad)- \(scalar(item))\n"
                } else {
                    let block = emit(item, indent: indent + 1)
                    let trimmed = block.drop(while: { $0 == " " })
                    out += "\(pad)- \(trimmed)"
                }
            }
            return out
        default:
            return "\(pad)\(scalar(object))\n"
        }
    }

    private static func isScalar(_ v: Any) -> Bool {
        !(v is [String: Any]) && !(v is [Any])
    }

    private static func escapeKey(_ k: String) -> String {
        k.contains(":") || k.contains(" ") ? "\"\(k)\"" : k
    }

    private static func scalar(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case let n as NSNumber:
            if n.isBool { return n.boolValue ? "true" : "false" }
            return n.stringValue
        case let s as String:
            if s.isEmpty || s.contains(":") || s.contains("#") || s.first == " " || s.last == " " {
                return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return s
        default:
            return "\"\(String(describing: v))\""
        }
    }

    // MARK: Parse

    static func parse(_ text: String) -> Any {
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        var index = 0
        return parseBlock(lines, &index, indent: 0)
    }

    private static func indentOf(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func parseBlock(_ lines: [String], _ i: inout Int, indent: Int) -> Any {
        // Decide list vs map by the first line at this indent.
        guard i < lines.count else { return [String: Any]() }
        let first = lines[i]
        let firstIndent = indentOf(first)
        if firstIndent < indent { return [String: Any]() }
        let isList = first.trimmingCharacters(in: .whitespaces).hasPrefix("- ")

        if isList {
            var array: [Any] = []
            while i < lines.count {
                let line = lines[i]
                let ind = indentOf(line)
                if ind < indent { break }
                let content = line.trimmingCharacters(in: .whitespaces)
                guard content.hasPrefix("- ") else { break }
                let rest = String(content.dropFirst(2))
                i += 1
                if rest.contains(":") && !looksScalar(rest) {
                    // inline map start: treat rest as first key of a nested map
                    var synthetic = [String(repeating: " ", count: ind + 2) + rest]
                    while i < lines.count && indentOf(lines[i]) > ind { synthetic.append(lines[i]); i += 1 }
                    var j = 0
                    array.append(parseBlock(synthetic, &j, indent: ind + 2))
                } else {
                    array.append(scalarValue(rest))
                }
            }
            return array
        } else {
            var map: [String: Any] = [:]
            while i < lines.count {
                let line = lines[i]
                let ind = indentOf(line)
                if ind < indent { break }
                if ind > indent { i += 1; continue }
                let content = line.trimmingCharacters(in: .whitespaces)
                guard let colon = content.firstIndex(of: ":") else { i += 1; continue }
                let key = String(content[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                let after = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                i += 1
                if after.isEmpty {
                    map[key] = parseBlock(lines, &i, indent: ind + 1)
                } else {
                    map[key] = scalarValue(after)
                }
            }
            return map
        }
    }

    private static func looksScalar(_ s: String) -> Bool {
        // "- 3:30" style values shouldn't be treated as maps if quoted
        s.hasPrefix("\"") || s.hasPrefix("'")
    }

    private static func scalarValue(_ raw: String) -> Any {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        switch s.lowercased() {
        case "null", "~", "": return NSNull()
        case "true", "yes": return true
        case "false", "no": return false
        default: break
        }
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        return s
    }
}

private extension NSNumber {
    /// Distinguish genuine booleans from 0/1 numbers.
    var isBool: Bool { CFGetTypeID(self) == CFBooleanGetTypeID() }
}
