import Destinations
import Foundation
import TakeFile

/// Which audio a Copy dropped is really lost (#318). Each Copy has its own ring, so one can drop a stretch the other
/// has: that's a Gap in the Copy that dropped it, which Repair fills from the other. Only a stretch every Copy lacks
/// (dropped too, or wasn't recording yet) is a Dropout.
struct DropoutSplit: Equatable {
    var dropouts: [TakeMetadata.Dropout] = []
    var gaps: [TakeMetadata.Gap] = []

    /// - Parameters:
    ///   - dropped: what each Copy's writer dropped, in Take frames.
    ///   - notRecording: where a Copy wasn't recording (a Drive that joined late), which doesn't count as having it.
    init(dropped: [DestinationKind: [Range<Int>]], notRecording: [DestinationKind: [Range<Int>]]) {
        let copies = Set(dropped.keys).union(notRecording.keys)
        for (copy, ranges) in dropped {
            let others = copies.subtracting([copy])
            // Where every other Copy lacks the audio too. With no other Copy, everything it dropped is lost.
            let lostElsewhere: [Range<Int>]? = others.reduce(nil) { lost, other in
                let lacking = Self.merged((dropped[other] ?? []) + (notRecording[other] ?? []))
                return lost.map { Self.intersection($0, lacking) } ?? lacking
            }
            for range in ranges where !range.isEmpty {
                let lost = lostElsewhere.map { Self.intersection([range], $0) } ?? [range]
                dropouts += lost.map { TakeMetadata.Dropout(copy: copy, start: $0.lowerBound, end: $0.upperBound) }
                gaps += Self.subtracting(lost, from: range).map { TakeMetadata.Gap(copy: copy, start: $0.lowerBound, end: $0.upperBound) }
            }
        }
        dropouts.sort { ($0.start, $0.end, $0.copy.index) < ($1.start, $1.end, $1.copy.index) }
        gaps.sort { ($0.start, $0.end, $0.copy.index) < ($1.start, $1.end, $1.copy.index) }
    }

    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for range in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, range.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }

    static func intersection(_ a: [Range<Int>], _ b: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for x in merged(a) {
            for y in merged(b) where x.overlaps(y) {
                out.append(max(x.lowerBound, y.lowerBound)..<min(x.upperBound, y.upperBound))
            }
        }
        return merged(out)
    }

    static func subtracting(_ holes: [Range<Int>], from range: Range<Int>) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = range.lowerBound
        for hole in merged(holes) where hole.overlaps(range) {
            if hole.lowerBound > start { out.append(start..<hole.lowerBound) }
            start = max(start, hole.upperBound)
        }
        if start < range.upperBound { out.append(start..<range.upperBound) }
        return out
    }
}
