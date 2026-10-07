import AudioIO
import BroadcastWave
import Foundation
@testable import Recording
import Testing

/// A Stem that fails every append after `healthyFrames`, standing in for a Destination that went away.
final class FailingStem: StemSink, @unchecked Sendable {
    struct Failure: Error {}
    private let real: StemWriter
    private let healthyFrames: Int
    private var frames = 0

    init(_ real: StemWriter, healthyFrames: Int) {
        self.real = real
        self.healthyFrames = healthyFrames
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        if frames + samples.count > healthyFrames { throw Failure() }
        frames += samples.count
        try real.append(samples)
    }
    func commitHeader() throws { try real.commitHeader() }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }
}

@MainActor
@Suite("Gaps")
struct GapTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "GapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("A Drive that fails mid-Take is marked interrupted and the Device Copy carries on")
    func driveFailsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DestinationAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info in
                let real = try StemWriter(url: url, info: info)
                return url.path.hasPrefix(drive.resolvingSymlinksInPath().path) || url.path.hasPrefix(drive.path)
                    ? FailingStem(real, healthyFrames: 480) : real
            })
        try recorder.arm(audio)

        try recorder.startTake()
        for block in 0..<10 {
            audio.deliver([(0..<480).map { RecordingTakeTests.sample(Int32(block * 480 + $0)) }])
            try await waitUntil { recorder.bufferedFrameCount == 0 }
        }
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }

        #expect(recorder.copyStatus(.device) == .recording)
        #expect(recorder.copyStatus(.drive) == .interrupted)
        try recorder.stopTake()

        let deviceStem = try StemFile(contentsOf: device.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(deviceStem.samples.count == 4800)
    }
}
