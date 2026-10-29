import AudioIO
import Foundation
@testable import Recording
import Testing

/// When the system stops input mid-Take (a phone call, Siri, a media services reset), the recorder
/// restarts input without ending the Take.
@MainActor
@Suite("Restarting input during a Take")
struct InputRestartTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "InputRestartTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func sample(_ value: Int32) -> Float { Float(value) / 8_388_608 }

    /// The first Take of whichever Show the recorder opened.
    func take01(_ recorder: Recorder) -> URL { recorder.currentShow!.folder.appending(path: "Take 01") }

    @Test("Restarting input on the Ready device keeps the same Take going")
    func restartKeepsTake() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root)
        try recorder.getReady(device)
        try recorder.startTake()
        device.deliver([[Self.sample(1), Self.sample(2)]])

        device.stop()  // The system stops input.
        device.deliver([[Self.sample(99)]])  // Never arrives.
        try recorder.restartInput()
        device.deliver([[Self.sample(3)]])
        #expect(recorder.isRecording)
        try await recorder.stopTake()

        #expect(recorder.currentShow?.takeCount == 1)
        let stem = try ParsedStem(contentsOf: take01(recorder).appending(path: "01 USB 01.wav"))
        #expect(stem.samples == [1, 2, 3])
    }

    @Test("Restarting input while Ready and not recording keeps the meters running")
    func restartWhileReady() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root)
        try recorder.getReady(device)
        device.stop()

        try recorder.restartInput()

        #expect(device.isRunning)
        #expect(recorder.isReady)
        device.deliver([[0.5], [0.25]])
        #expect(recorder.takeMeterLevels() == [0.5, 0.25])
    }

    @Test("Restarting input when not Ready is an error")
    func restartWhenNotReady() {
        let recorder = Recorder(deviceFolder: root)
        #expect(throws: RecorderError.notReady) { try recorder.restartInput() }
    }

    @Test("A replacement device with the same channels and rate continues the Take")
    func replacementWithSameFormatContinues() async throws {
        let old = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root)
        try recorder.getReady(old)
        try recorder.startTake()
        old.deliver([[Self.sample(1)]])

        let replacement = FakeAudioDevice(inputChannelCount: 1)
        let continued = try await recorder.restartInput(on: replacement)
        replacement.deliver([[Self.sample(2)]])
        try await recorder.stopTake()

        #expect(continued)
        #expect(!old.isRunning)
        #expect(recorder.currentShow?.takeCount == 1)
        let stem = try ParsedStem(contentsOf: take01(recorder).appending(path: "01 USB 01.wav"))
        #expect(stem.samples == [1, 2])
    }

    @Test("A replacement device with a different format ends the Take cleanly and gets ready on it")
    func replacementWithDifferentFormatEndsTake() async throws {
        let old = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root)
        try recorder.getReady(old)
        try recorder.startTake()
        old.deliver([[Self.sample(1)], [Self.sample(2)]])

        let replacement = FakeAudioDevice(inputChannelCount: 1, sampleRate: 44_100)
        let continued = try await recorder.restartInput(on: replacement)

        #expect(!continued)
        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .inputChanged), "the Take ended because the input changed, not by the operator (#301)")
        #expect(TakeEnd.Reason.inputChanged.message != nil)
        #expect(recorder.isReady)
        #expect(recorder.usbChannelCount == 1)
        #expect(replacement.isRunning)
        let stem = try ParsedStem(contentsOf: take01(recorder).appending(path: "01 USB 01.wav"))
        #expect(stem.samples == [1])
    }
}
