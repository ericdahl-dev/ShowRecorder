import AudioIO
@testable import Recording
import Testing

/// Delivers `frames` frames to every input channel of `audio`, in blocks of `block` frames (all in one block when
/// nil). `sample` gives each sample from its frame, counted on from `start`, and its channel; silence by default.
func deliver(
    _ frames: Int, from start: Int = 0, to audio: FakeAudioDevice, block: Int? = nil,
    sample: (_ frame: Int, _ channel: Int) -> Float = { _, _ in 0 }
) {
    var frame = start
    while frame < start + frames {
        let n = min(block ?? frames, start + frames - frame)
        audio.deliver((0..<audio.inputChannelCount).map { channel in (0..<n).map { sample(frame + $0, channel) } })
        frame += n
    }
}

/// The same in blocks of `block` frames, and while `recorder` is recording, waits after each block until it has
/// taken it. While it is only Armed nothing is waited for: the Pre-roll keeps what it holds.
@MainActor
func deliver(
    _ frames: Int, from start: Int = 0, to audio: FakeAudioDevice, _ recorder: Recorder, block: Int = 480,
    sourceLocation: SourceLocation = #_sourceLocation, sample: (_ frame: Int, _ channel: Int) -> Float = { _, _ in 0 }
) async throws {
    var frame = start
    while frame < start + frames {
        let n = min(block, start + frames - frame)
        deliver(n, from: frame, to: audio, sample: sample)
        frame += n
        if recorder.isRecording { try await waitUntil(sourceLocation: sourceLocation) { recorder.bufferedFrameCount == 0 } }
    }
}

/// Delivers `count` blocks of 480 frames, as `deliver` does, waiting after each until `recorder` has taken it, so
/// no block is dropped however slowly the writers run.
@MainActor
func deliverBlocks(
    _ count: Int, from start: Int = 0, to audio: FakeAudioDevice, _ recorder: Recorder,
    sourceLocation: SourceLocation = #_sourceLocation, sample: (_ frame: Int, _ channel: Int) -> Float = { _, _ in 0 }
) async throws {
    for block in 0..<count {
        deliver(480, from: start + block * 480, to: audio, sample: sample)
        try await waitUntil(sourceLocation: sourceLocation) { recorder.bufferedFrameCount == 0 }
    }
}

/// A sample that tells where it came from: its frame, plus `channelStep` for each channel after the first, exactly as
/// the recorder will write it in 24 bits (as `RecordingTakeTests.sample` scales it).
func counting(channelStep: Int = 1_000_000) -> @Sendable (_ frame: Int, _ channel: Int) -> Float {
    { frame, channel in Float(frame + channel * channelStep) / 8_388_608 }
}
