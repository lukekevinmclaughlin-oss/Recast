import Foundation

/// Minimal XML ↔ Foundation-object bridge for the DataBackend. Elements become
/// nested dictionaries; repeated tags become arrays; leaf text becomes strings.
/// Attributes are not modelled (kept simple and predictable for data interchange).
enum MiniXML {

    // MARK: Parse

    static func parse(_ data: Data) throws -> Any {
        let parser = XMLParser(data: data)
        let delegate = Builder()
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw ConversionError.readFailed
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        private var stack: [(name: String, children: [String: Any], text: String)] = []
        var root: Any?

        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            stack.append((name, [:], ""))
        }
        func parser(_ p: XMLParser, foundCharacters string: String) {
            if !stack.isEmpty { stack[stack.count - 1].text += string }
        }
        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let node = stack.removeLast()
            let value: Any = node.children.isEmpty
                ? node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : node.children
            if stack.isEmpty {
                root = [node.name: value]
            } else {
                add(&stack[stack.count - 1].children, key: node.name, value: value)
            }
        }
        private func add(_ dict: inout [String: Any], key: String, value: Any) {
            if let existing = dict[key] {
                if var arr = existing as? [Any] { arr.append(value); dict[key] = arr }
                else { dict[key] = [existing, value] }
            } else {
                dict[key] = value
            }
        }
    }

    // MARK: Emit

    static func emit(_ object: Any) -> String {
        // Always a single <root> element so the output is valid XML even when the
        // source is a top-level array (each item becomes <item>…</item>).
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n" + children(of: object, indent: 1) + "</root>\n"
    }

    private static func children(of value: Any, indent: Int) -> String {
        if let dict = value as? [String: Any] {
            return dict.keys.sorted().map { emit(name: $0, value: dict[$0]!, indent: indent) }.joined()
        }
        if let array = value as? [Any] {
            return array.map { emit(name: "item", value: $0, indent: indent) }.joined()
        }
        let pad = String(repeating: "  ", count: indent)
        return "\(pad)\(escape(stringify(value)))\n"
    }

    private static func emit(name: String, value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        if let dict = value as? [String: Any] {
            let inner = dict.keys.sorted().map { emit(name: $0, value: dict[$0]!, indent: indent + 1) }.joined()
            return "\(pad)<\(name)>\n\(inner)\(pad)</\(name)>\n"
        }
        if let array = value as? [Any] {
            return array.map { emit(name: name, value: $0, indent: indent) }.joined()
        }
        return "\(pad)<\(name)>\(escape(stringify(value)))</\(name)>\n"
    }

    private static func stringify(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case is NSNull: return ""
        default: return String(describing: v)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
