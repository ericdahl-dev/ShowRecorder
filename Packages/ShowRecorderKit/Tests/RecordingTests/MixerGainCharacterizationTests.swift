import AudioIO
import AutoGain
import Foundation
import MixerLink
import TakeFile
@testable import Recording
import Testing

/// What gain on the Mixer does today, pinned before it becomes one module (#554). Behavior Eric chose to change
/// (a reconnect mid-Take, measuring in audio time, two preamps at once) is tested where it changes, not here.
@MainActor
@Suite("Mixer gain, as it is")
struct MixerGainCharacterizationTests {
    @Test("Windows read while one channel's move waits on a slow Mixer still count: another channel running hot meanwhile is turned down too")
    func windowsCountDuringASlowMove() async {
        let control = FakeGainControl(gainDb: [1: 30, 2: 30], channelOfUSB: [1: 1, 2: 2])
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        var first = true
        control.answer = { @MainActor in
            guard first else { return }
            first = false
            enter.yield()
            for await _ in released { return }
        }
        let protection = ClipProtection(control: control, sampleRate: 48_000)
        let hot = Windows.at(-2), quiet = Windows.at(-30)

        // Channel 1 runs hot until its move starts and waits on the Mixer.
        let moving = (0..<10).compactMap { _ in protection.meters([hot, quiet]) }
        #expect(await ClipProtectionTests.next(entered), "channel 1's move reaches the Mixer")
        // Meanwhile channel 2 runs hot for 300 ms, read by read, as the meters go on.
        let meanwhile = (0..<10).compactMap { _ in protection.meters([quiet, hot]) }
        for task in meanwhile { await task.value }
        release.yield()
        for task in moving { await task.value }

        #expect(control.gainDb == [1: 26, 2: 26])
    }

    @Test("A clip-protection turn-down is logged but never offered for Undo in the Gain sheet")
    func clipMovesAreNotUndoable() async {
        let control = FakeGainControl(gainDb: [1: 30], channelOfUSB: [1: 1])
        let panel = MixerGain(makeSession: { _ in AutoGainSession(control: control, measure: AutoGainSessionTests.meters(control, source: [1: -40])) })
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        for _ in 0..<10 { await protection.observe([Windows.at(-2)]) }

        #expect(logged.map(\.reason) == [.clipProtection])
        #expect(!panel.canUndo(1) && !panel.canUndoAll)
    }

    @Test("The gain log names each setting Mix Hold moves")
    func logNames() {
        let names: [(MixHold.Parameter, String)] = [
            (.gateThreshold, "gate threshold"), (.compressorThreshold, "compressor threshold"), (.mainFader, "fader"),
            (.otherMain(1), "mono"), (.otherMain(2), "main 2"), (.send(3), "send 3"),
        ]
        for (parameter, name) in names { #expect(parameter.logName == name) }
        let limit = MixHold.Limit(setting: MixHold.Setting(channel: 1, parameter: .gateThreshold), endDb: 0)
        #expect(limit.explanation == "Channel 1's gate threshold is at its end stop (0 dB)")
        #expect(MixHold.Limit(setting: MixHold.Setting(channel: 4, parameter: .send(2)), endDb: 10).explanation
            == "Channel 4's send 2 is at its end stop (+10 dB)")
    }

    @Test("The gain Marker says the USB Channel's name, the change and why")
    func markerWording() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MixerGainCharacterization-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.getReady(device)
        try recorder.startTake(sources: [Source(name: "Kick", color: .off), Source(name: "Snare", color: .off)])
        let change = TakeMetadata.GainChange(usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 30, toGainDb: 26,
                                             reason: .clipProtection, compensations: [])
        recorder.logGainChange(change)
        recorder.logGainChange(TakeMetadata.GainChange(usbChannel: 2, channel: 2, headamp: 2, fromGainDb: 10, toGainDb: 13.5,
                                                       reason: .autoGain, compensations: []))
        #expect(recorder.markerEntries.map(\.name) == ["Kick: gain -4.0 dB (clip protection)", "Snare: gain +3.5 dB (auto-gain)"])
        try await recorder.stopTake()
    }
}
