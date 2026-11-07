import Foundation

/// A stereo pair of USB Channels recorded as one interleaved stereo Stem (#1088). The Take writer feeds a Stem per USB
/// Channel; a pair gives it two lanes, left and right, that it feeds like two mono Stems, and they write the one file. Built
/// around a pair, not a 2-input interface, so a mixer whose USB sends are all pairs (Pioneer DJM, #364) can reuse it.
///
/// Not real-time safe: used on the writer thread, like the Stem it writes into. Each lane holds what it was given until the
/// other lane has the same frames, so a lane fed a block ahead holds about a block.
public enum StereoPair {
    /// Left and right lanes writing into `file`, a 2-channel Stem that takes interleaved samples. On a Stem that already has
    /// frames (a resumed one), both lanes carry on after them.
    public static func lanes(writingTo file: any StemSink) -> (left: any StemSink, right: any StemSink) {
        let pair = Pair(file: file)
        return (Lane(pair: pair, side: 0), Lane(pair: pair, side: 1))
    }

    /// What the two lanes share: the file and what each lane was given that the file doesn't have yet.
    private final class Pair {
        let file: any StemSink
        var pending: [[Float]] = [[], []]
        private var interleaved: [Float] = []
        private var finalized = false

        init(file: any StemSink) {
            self.file = file
        }

        func append(_ samples: UnsafeBufferPointer<Float>, side: Int) throws {
            pending[side].append(contentsOf: samples)
            try writeWholeFrames()
        }

        /// Writes the frames both lanes have.
        private func writeWholeFrames() throws {
            let frames = min(pending[0].count, pending[1].count)
            guard frames > 0 else { return }
            interleaved.removeAll(keepingCapacity: true)
            interleaved.reserveCapacity(frames * 2)
            for index in 0..<frames {
                interleaved.append(pending[0][index])
                interleaved.append(pending[1][index])
            }
            pending[0].removeFirst(frames)
            pending[1].removeFirst(frames)
            try interleaved.withUnsafeBufferPointer { try file.append($0) }
        }

        /// Closes the file once, whichever lane asks first. A lane that is ahead (a Copy that failed mid-block) keeps its
        /// audio: the other channel is silence there.
        func finalize() throws {
            guard !finalized else { return }
            finalized = true
            let longest = max(pending[0].count, pending[1].count)
            for side in 0..<2 { pending[side] += [Float](repeating: 0, count: longest - pending[side].count) }
            try writeWholeFrames()
            try file.finalize()
        }
    }

    /// One channel of the pair, as the Take writer sees it: a Stem it appends that channel's samples to.
    private final class Lane: StemSink {
        private let pair: Pair
        private let side: Int

        init(pair: Pair, side: Int) {
            self.pair = pair
            self.side = side
        }

        /// The frames in the file plus those this lane holds for the other one.
        var frameCount: UInt64 { pair.file.frameCount + UInt64(pair.pending[side].count) }

        func append(_ samples: UnsafeBufferPointer<Float>) throws { try pair.append(samples, side: side) }
        func commitHeader() throws { try pair.file.commitHeader() }
        func finalize() throws { try pair.finalize() }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try pair.file.setMarkers(markers) }
    }
}
