/// What VoiceOver announces on the record screen (#249): a new alert, a new clip and a Dropout, each once, when it
/// happens. Nothing on the first look or while nothing changes, so a busy screen never chatters.
public enum ScreenAnnouncements {
    /// What the record screen showed at one moment.
    public struct State: Equatable, Sendable {
        /// Clipped meters, by index from 0.
        public var clipped: Set<Int>
        public var alerts: [ScreenAlert]
        public var dropoutCount: Int

        public init(clipped: Set<Int> = [], alerts: [ScreenAlert] = [], dropoutCount: Int = 0) {
            self.clipped = clipped
            self.alerts = alerts
            self.dropoutCount = dropoutCount
        }
    }

    /// What to announce, in order, going from `old` to `new`. Nil `old` is the first look: nothing to announce.
    public static func changes(from old: State?, to new: State) -> [String] {
        guard let old else { return [] }
        var out: [String] = []
        let known = Set(old.alerts.map(\.id))
        out += new.alerts.filter { !known.contains($0.id) }.map(\.text)
        let clips = new.clipped.subtracting(old.clipped).sorted().map { $0 + 1 }
        if clips.count == 1 { out.append("Clip on USB Channel \(clips[0])") }
        if clips.count > 1 {
            out.append("Clip on USB Channels \(clips.dropLast().map(String.init).joined(separator: ", ")) and \(clips.last!)")
        }
        let dropouts = new.dropoutCount - old.dropoutCount
        if dropouts == 1 { out.append("Dropout") }
        if dropouts > 1 { out.append("\(dropouts) Dropouts") }
        return out
    }
}
