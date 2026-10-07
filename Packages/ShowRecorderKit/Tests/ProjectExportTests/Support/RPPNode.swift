import Foundation

/// A minimal Reaper project reader for tests: `<TAG …` opens a node, `>` closes it, and every
/// other line is a property line. Values are split the way Reaper quotes them.
struct RPPNode {
    var tag: String
    var values: [String]
    var lines: [[String]] = []
    var children: [RPPNode] = []

    static func parse(_ text: String) throws -> RPPNode {
        var stack: [RPPNode] = []
        var root: RPPNode?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("<") {
                let tokens = tokenize(String(line.dropFirst()))
                stack.append(RPPNode(tag: tokens.first ?? "", values: Array(tokens.dropFirst())))
            } else if line == ">" {
                guard let node = stack.popLast() else { throw RPPError.unbalanced }
                if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
            } else {
                guard !stack.isEmpty else { throw RPPError.unbalanced }
                stack[stack.count - 1].lines.append(tokenize(line))
            }
        }
        guard stack.isEmpty, let root else { throw RPPError.unbalanced }
        return root
    }

    /// Splits on spaces; a token starting with `"`, `'` or `` ` `` runs to the same closing quote.
    static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var i = line.startIndex
        while i < line.endIndex {
            if line[i] == " " { i = line.index(after: i); continue }
            let quote = line[i]
            if quote == "\"" || quote == "'" || quote == "`" {
                let start = line.index(after: i)
                let end = line[start...].firstIndex(of: quote) ?? line.endIndex
                tokens.append(String(line[start..<end]))
                i = end < line.endIndex ? line.index(after: end) : end
            } else {
                let end = line[i...].firstIndex(of: " ") ?? line.endIndex
                tokens.append(String(line[i..<end]))
                i = end
            }
        }
        return tokens
    }

    func children(_ tag: String) -> [RPPNode] { children.filter { $0.tag == tag } }
    func child(_ tag: String) -> RPPNode? { children.first { $0.tag == tag } }
    /// Every property line starting with `key`, without the key.
    func all(_ key: String) -> [[String]] { lines.filter { $0.first == key }.map { Array($0.dropFirst()) } }
    func value(_ key: String) -> String? { all(key).first?.first }
    func double(_ key: String) -> Double? { value(key).flatMap(Double.init) }
}

enum RPPError: Error { case unbalanced }
