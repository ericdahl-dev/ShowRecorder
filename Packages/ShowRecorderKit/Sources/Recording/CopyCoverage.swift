import Destinations
import Foundation
import TakeFile

/// What each Copy of a Take holds (#441): the one place Gaps and Dropouts come from, for a running Take, one that
/// ended and one cut off by a crash. Each Copy has its own ring, so one can lack a stretch the other has: that's a Gap
/// in the Copy that lacks it, which Repair fills from the other (#318). Only a stretch every Copy lacks is a Dropout.
struct CopyCoverage: Equatable {
    /// What one Copy's writer reports.
    struct Copy: Equatable {
        var kind: DestinationKind
        /// Frames written from the start of the Take.
        var written: Int
        /// Audio the writer had to drop (written as silence of the exact length).
        var dropped: [Range<Int>] = []
        /// Silence written where the Copy wasn't recording yet, such as a Drive that joined late.
        var silence: [Range<Int>] = []
        /// The Copy stopped before the Take did (it failed, retired or never joined): it lacks everything from
        /// `written` on.
        var stoppedEarly = false
    }

    var copies: [Copy]

    init(_ copies: [Copy]) {
        self.copies = copies
    }

    /// A Take cut off by a crash, from each Copy's Stems on disk: a Copy shorter than the longest stopped early.
    init(stemLengths: [DestinationKind: Int]) {
        let longest = stemLengths.values.max() ?? 0
        copies = stemLengths.sorted { $0.key.index < $1.key.index }
            .map { Copy(kind: $0.key, written: $0.value, stoppedEarly: $0.value < longest) }
    }

    /// The furthest any Copy got: a cut-off Take's end.
    var end: Int { copies.map(\.written).max() ?? 0 }

    /// Audio every Copy lacks: one Dropout per Copy that dropped it and stretch.
    var dropouts: [TakeMetadata.Dropout] { split.dropouts }

    /// Stretches written as silence in a Copy that another Copy has, or that Repair would otherwise fill.
    /// - Parameter takeEnd: where the Take ended; nil while it runs, when a Copy that stopped early has no tail yet.
    func gaps(takeEnd: Int?) -> [TakeMetadata.Gap] {
        var gaps = split.gaps
        for copy in copies {
            gaps += copy.silence.map { TakeMetadata.Gap(copy: copy.kind, start: $0.lowerBound, end: $0.upperBound) }
            if let takeEnd, copy.stoppedEarly, copy.written < takeEnd {
                gaps.append(TakeMetadata.Gap(copy: copy.kind, start: copy.written, end: takeEnd))
            }
        }
        return gaps.sorted { ($0.start, $0.end, $0.copy.index) < ($1.start, $1.end, $1.copy.index) }
    }

    /// Where a Copy lacks the Take's audio, whether or not it wrote silence there.
    private func lacking(_ copy: Copy) -> [Range<Int>] {
        Self.merged(copy.dropped + copy.silence + (copy.stoppedEarly ? [copy.written..<Int.max] : []))
    }

    /// What the writers dropped, split into audio every Copy lacks (Dropouts) and audio another Copy has (Gaps).
    private var split: (dropouts: [TakeMetadata.Dropout], gaps: [TakeMetadata.Gap]) {
        var dropouts: [TakeMetadata.Dropout] = []
        var gaps: [TakeMetadata.Gap] = []
        for copy in copies {
            let others = copies.filter { $0.kind != copy.kind }
            // Where every other Copy lacks the audio too. With no other Copy, everything it dropped is lost.
            let lostElsewhere: [Range<Int>]? = others.reduce(nil) { lost, other in
                lost.map { Self.intersection($0, lacking(other)) } ?? lacking(other)
            }
            for range in copy.dropped where !range.isEmpty {
                let lost = lostElsewhere.map { Self.intersection([range], $0) } ?? [range]
                dropouts += lost.map { TakeMetadata.Dropout(copy: copy.kind, start: $0.lowerBound, end: $0.upperBound) }
                gaps += Self.subtracting(lost, from: range).map { TakeMetadata.Gap(copy: copy.kind, start: $0.lowerBound, end: $0.upperBound) }
            }
        }
        dropouts.sort { ($0.start, $0.end, $0.copy.index) < ($1.start, $1.end, $1.copy.index) }
        return (dropouts, gaps)
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
