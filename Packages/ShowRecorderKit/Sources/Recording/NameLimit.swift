/// Cuts operator-typed names to a safe length. A Show name becomes part of a folder name (a 255-byte limit on
/// the file systems the Device and a Drive use), so the limit counts bytes, and never cuts through a character.
public enum NameLimit {
    /// The longest a Show name or a Marker name can be, in UTF-8 bytes. A Show folder adds "YYYY-MM-DD " in front.
    public static let maxBytes = 100

    public static func cut(_ name: String, maxBytes: Int = Self.maxBytes) -> String {
        var result = ""
        var used = 0
        for character in name {
            let size = String(character).utf8.count
            if used + size > maxBytes { break }
            result.append(character)
            used += size
        }
        return result
    }
}
