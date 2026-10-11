import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A stall on one Copy only (a slow Drive) loses no audio: the other Copy has it, so it's a Gap that Repair fills,
/// not a Dropout (#318).
@MainActor
@Suite("One-Copy Dropout")
struct OneCopyDropoutTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "OneCopyDropoutTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    /// A Stem whose writes wait while `stalled` is set: a Drive that stops taking data for a while.
    final class Gate: @unchecked Sendable {
        private let lock = NSCondition()
        private var stalled = true
        func wait() { lock.lock(); while stalled { lock.wait() }; lock.unlock() }
        func open() { lock.lock(); stalled = false; lock.broadcast(); lock.unlock() }
    }
    final class StalledStem: StemSink, @unchecked Sendable {
        let inner: StemWriter
        let gate: Gate
        init(_ inner: StemWriter, gate: Gate) { self.inner = inner; self.gate = gate }
        var frameCount: UInt64 { inner.frameCount }
        func append(_ samples: UnsafeBufferPointer<Float>) throws { gate.wait(); try inner.append(samples) }
        func commitHeader() throws { try inner.commitHeader() }
        func finalize() throws { try inner.finalize() }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try inner.setMarkers(markers) }
    }

    @Test("Audio only the Drive dropped is a Gap in the Drive that Repair fills; the Take has no Dropout")
    func driveOnlyStall() async throws {
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = Gate()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? StalledStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        // About 5 s at 48 kHz in 0.5 s blocks: more than the Drive's 4 s ring holds while it's stalled; the Device keeps up.
        for _ in 0..<10 {
            audio.deliver([Array(repeating: 0.25, count: 24_000)])
            try await Task.sleep(for: .milliseconds(40))
        }
        gate.open()
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        recorder.checkDestinations()
        try recorder.stopTake()
        await recorder.waitForRepair()

        let metadata = try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/Take 01"))
        #expect(metadata.dropouts.isEmpty, "the Device has every frame, so nothing was lost")
        #expect(metadata.gaps.contains { $0.copy == .drive }, "the Drive's stall is a Gap")
        #expect(!metadata.markers.contains { $0.origin == .dropout })
        let deviceStem = device.appending(path: "\(show)/Take 01/01 USB 01.wav")
        let driveStem = drive.appending(path: "\(show)/Take 01/01 USB 01.wav")
        #expect(try StemLength.frameCount(at: driveStem) == StemLength.frameCount(at: deviceStem))
        #expect(try Data(contentsOf: driveStem) == Data(contentsOf: deviceStem), "Repair filled the Drive from the Device")
    }
}
