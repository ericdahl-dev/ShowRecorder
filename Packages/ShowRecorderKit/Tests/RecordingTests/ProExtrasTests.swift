import AudioIO
import Foundation
@testable import Recording
import Testing

/// On Free the Show report, the Reaper project and typed channel names are Pro extras (ADR 0004).
@MainActor
@Suite("Pro extras")
struct ProExtrasTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ProExtrasTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"
    let free = TakeAllowance(recordedChannels: [1, 2], showReport: false, reaperExport: false, namingByHand: false)
    let pro = TakeAllowance(recordedChannels: [1, 2], showReport: true, reaperExport: true, namingByHand: true)

    func take(_ recorder: Recorder, _ audio: FakeAudioDevice, _ allowance: TakeAllowance) async throws {
        try recorder.startTake(allowance: allowance)
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        await recorder.waitForRepair()
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: path).path) }

    @Test("A Free Take writes no Show report and no Reaper project; a Pro Take writes both")
    func reportAndProject() async throws {
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.arm(audio)

        try await take(recorder, audio, free)
        #expect(!exists("\(show)/Report.html") && !exists("\(show)/\(show).RPP"))
        #expect(exists("\(show)/Take 01/01 USB 01.wav"), "the audio is recorded as always")

        try await take(recorder, audio, pro)
        #expect(exists("\(show)/Report.html") && exists("\(show)/\(show).RPP"))
    }

    @Test("Typed channel names are kept on Free but not put on the files; the next Pro Take uses them")
    func typedNamesArePro() async throws {
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.arm(audio)
        recorder.setChannelName("Kick", forChannel: 1)

        try await take(recorder, audio, free)
        #expect(exists("\(show)/Take 01/01 USB 01.wav") && !exists("\(show)/Take 01/01 Kick.wav"))
        #expect(recorder.channelNames == [1: "Kick"], "the name is kept")

        // Named during a Free Take: still not applied when it ends.
        try recorder.startTake(allowance: free)
        audio.deliver([[0.1], [0.1]])
        recorder.setChannelName("Snare", forChannel: 2)
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(exists("\(show)/Take 02/02 USB 02.wav") && !exists("\(show)/Take 02/02 Snare.wav"))

        try await take(recorder, audio, pro)
        #expect(exists("\(show)/Take 03/01 Kick.wav") && exists("\(show)/Take 03/02 Snare.wav"))
    }
}
