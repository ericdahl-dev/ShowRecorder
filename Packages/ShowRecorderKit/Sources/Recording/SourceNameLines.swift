/// How a Source's name is laid out under its meter: whole words on at most two lines, so a narrow lane
/// shrinks the text instead of breaking a word ("Sna / re", #378).
public enum SourceNameLines {
    /// One line for one word; otherwise two, broken at the word boundary that keeps the longer line shortest.
    public static func split(_ name: String) -> [String] {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 1 else { return words }
        let breaks = (1..<words.count).map { at in
            [words[..<at].joined(separator: " "), words[at...].joined(separator: " ")]
        }
        return breaks.min { $0.map(\.count).max()! < $1.map(\.count).max()! }!
    }
}
