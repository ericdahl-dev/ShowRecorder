import Foundation

/// A folder of stems played as USB Channels, for screenshots (#374): the files in a band's channel order, each stereo
/// file on two channels, named from the file without the prefix the files share ("…_drums.wav" is "Drums L" and
/// "Drums R"). The audio itself is the app's (Debug and the screenshot build only).
public struct StemDemoLayout: Equatable, Sendable {
    public struct Stem: Equatable, Sendable {
        public var file: String
        public var channels: Int
        /// "Drums", "Gtr", "Vox": the name its channels carry.
        public var name: String
    }

    /// The stems in channel order.
    public let order: [Stem]

    /// The usual order of a band's input list; anything else follows, in name order.
    static let bandOrder = ["drums", "kick", "snare", "bass", "guitar", "piano", "keys", "vocals", "vox"]
    /// Short names as a mixer's scribble strip has them.
    static let shortNames = ["guitar": "Gtr", "vocals": "Vox"]

    /// - Parameter files: each file's name and channel count.
    public init(files: [(name: String, channels: Int)]) {
        let bases = files.map { ($0.name as NSString).deletingPathExtension }
        let prefix = Self.sharedPrefix(bases)
        let stems = zip(files, bases).map { file, base -> Stem in
            let instrument = String(base.dropFirst(prefix.count)).lowercased()
            let name = Self.shortNames[instrument] ?? instrument.prefix(1).uppercased() + instrument.dropFirst()
            return Stem(file: file.name, channels: file.channels, name: name)
        }
        func rank(_ stem: Stem) -> Int {
            let key = String((stem.file as NSString).deletingPathExtension.dropFirst(prefix.count)).lowercased()
            return Self.bandOrder.firstIndex(of: key) ?? Self.bandOrder.count
        }
        order = stems.sorted { (rank($0), $0.name) < (rank($1), $1.name) }
    }

    /// One name per USB Channel.
    public var channelNames: [String] {
        order.flatMap { $0.channels == 2 ? ["\($0.name) L", "\($0.name) R"] : Array(repeating: $0.name, count: $0.channels) }
    }

    public var channelCount: Int { order.reduce(0) { $0 + $1.channels } }

    /// The prefix all the names share, cut back to the last "_", "-" or " ", so "…_drums" and "…_bass" share "…_".
    static func sharedPrefix(_ names: [String]) -> String {
        guard names.count > 1, var prefix = names.first else { return "" }
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) { prefix.removeLast() }
        }
        guard let cut = prefix.lastIndex(where: { "_- ".contains($0) }) else { return "" }
        return String(prefix[...cut])
    }
}
