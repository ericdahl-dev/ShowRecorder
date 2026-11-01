import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// A Take that starts while the Drive is being prepared still begins at press minus Pre-roll, as its time stamp says
/// (#915): the audio that came in during the wait is in the Stems.
@MainActor
@Suite("Take start and the time stamp")
struct TakeStartTimelineTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeStartTimelineTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    /// The Drive's answer waits on a gate, so audio can arrive while the Take is starting.
    final class Gate: @unchecked Sendable {
        let gate = TestGate()
        private let lock = NSLock()
        private var asks = 0
        var asked: Bool { lock.withLock { asks > 0 } }
        func ask() { lock.withLock { asks += 1 } }
    }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(_ gate: Gate, preRoll: Double) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device, driveFolder: {
                gate.ask()
                gate.gate.wait()
                return DriveAccess(folder: drive)
            }, now: { RecordingTakeTests.showDay }, preRollSeconds: preRoll, destinationCheckInterval: nil,
            driveStartDeadline: .seconds(60))
    }

    func waitForTheDrive(_ gate: Gate) async {
        let deadline = ContinuousClock.now + .seconds(60)
        while !gate.asked, ContinuousClock.now < deadline { await Task.yield() }
    }

    /// The press, as the recorder stamps it: frames since midnight.
    var pressReference: UInt64 {
        let day = RecordingTakeTests.showDay
        return UInt64(day.timeIntervalSince(Calendar.current.startOfDay(for: day)) * 48_000)
    }

    func take01(_ copy: URL, _ name: String) throws -> ParsedStem {
        try ParsedStem(contentsOf: copy.appending(path: "2026-10-06 Show/Take 01/\(name)"))
    }

    @Test("Audio that arrives while the Drive is being prepared is in the Take, and frame 0 is press minus Pre-roll")
    func audioDuringTheWait() async throws {
        let gate = Gate()
        let recorder = recorder(gate, preRoll: 1)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try await deliver(144_000, from: 0, to: audio, recorder, sample: counting())  // 3 s Ready; the press is at frame 144 000

        let starting = Task { @MainActor in try await recorder.startTakeOffMain() }
        await waitForTheDrive(gate)
        deliver(12_000, from: 144_000, to: audio, block: 480, sample: counting())  // the wait
        gate.gate.open()
        try await starting.value
        try await deliver(1_000, from: 156_000, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        for copy in [device, drive] {
            let stem = try take01(copy, "01 USB 01.wav")
            #expect(stem.samples == (96_000..<157_000).map { Int32($0) }, "\(copy.lastPathComponent)")
            #expect(stem.timeReference == pressReference - 48_000, "the stamp is still the press minus Pre-roll")
        }
    }

    @Test("With Pre-roll off the Take begins at the press, not at the first live block")
    func preRollOff() async throws {
        let gate = Gate()
        let recorder = recorder(gate, preRoll: 0)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try await deliver(144_000, from: 0, to: audio, recorder, sample: counting())

        let starting = Task { @MainActor in try await recorder.startTakeOffMain() }
        await waitForTheDrive(gate)
        deliver(12_000, from: 144_000, to: audio, block: 480, sample: counting())
        gate.gate.open()
        try await starting.value
        try await deliver(1_000, from: 156_000, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        for copy in [device, drive] {
            let stem = try take01(copy, "01 USB 01.wav")
            #expect(stem.samples == (144_000..<157_000).map { Int32($0) }, "\(copy.lastPathComponent)")
            #expect(stem.timeReference == pressReference)
        }
    }
}
