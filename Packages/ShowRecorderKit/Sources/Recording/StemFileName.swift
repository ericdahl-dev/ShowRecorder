import Foundation

enum StemFileName {
    static let maxNameLength = 64

    /// "NN <name>.wav", with the Source name made safe for every file system the Drive might use.
    ///
    /// Path separators, characters Windows and exFAT reject, and control characters become "-";
    /// leading and trailing spaces and dots are dropped; long names are cut. A name that ends up empty
    /// falls back to the USB Channel name. The bext description keeps the original name.
    static func make(usbChannel: Int, sourceName: String) -> String {
        let number = String(format: "%02d", usbChannel)
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let replaced = String(sourceName.unicodeScalars.map { unsafe.contains($0) ? "-" : Character($0) })
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: " .").union(.whitespacesAndNewlines))
        let name = trimmed.isEmpty ? "USB \(number)" : String(trimmed.prefix(maxNameLength))
        return "\(number) \(name).wav"
    }
}
