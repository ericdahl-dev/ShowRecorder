import AudioIO
import BroadcastWave
import Destinations
import Foundation
import MixerLink
@testable import Recording
import Testing

/// The running Take's Copies, driven through a real `Capture` with no `AudioIODevice`.
@MainActor
@Suite("Take session")
struct TakeSessionTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let capture = Capture(channelCount: 1, sampleRate: 48_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TakeSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Device"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Opened Stems, in order, with the frame count each was asked to resume at.
    final class Opened: @unchecked Sendable {
        var resumes: [UInt64?] = []
    }

    /// Starts a Take on the Device only. `makeStem` wraps the real Stems; `free` is each folder's free space.
    func session(
        withDrive: Bool = false,
        opened: Opened = Opened(),
        wrap: @escaping (URL, StemWriter) -> any StemSink = { _, real in real },
        free: @escaping (URL) -> Int64 = { _ in .max }
    ) throws -> TakeSession {
        var show = try Show.create(in: device, drive: withDrive ? drive : nil, on: RecordingTakeTests.showDay)
        let folders = try show.createNextTakeFolder()
        let metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        return try TakeSession(
            show: show, folders: folders, drive: nil, metadata: metadata,
            stems: [StemSpec(file: "01 USB 01.wav", description: "USB 01")], info: info, capture: capture,
            makeStem: { url, info, resuming in
                opened.resumes.append(resuming)
                return wrap(url, try StemWriter.open(url: url, info: info, resumingAt: resuming))
            },
            freeSpace: free)
    }

    func deliver(_ frames: Int) async throws {
        var samples = [Float](repeating: 0.25, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                capture.receive(AudioBlock(channels: $0, channelCount: 1, frameCount: frames, hostTime: 0))
            }
        }
        try await waitUntil { capture.rings.allSatisfy { $0.availableFrames == 0 } }
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("A Drive that appears mid-Take joins with silence up to the join point, recorded as a Gap")
    func driveJoins() async throws {
        let session = try session()
        try await deliver(480)
        var asked = 0
        let drive = drive
        let check = session.checkDestinations(drive: { asked += 1; return DestinationAccess(folder: drive) })

        #expect(check == .carryOn)
        #expect(session.copies.map(\.kind) == [.device, .drive])
        #expect(session.status(.drive) == .recording)
        try await waitUntil { session.copies[1].ring.joinFrame.load(ordering: .acquiring) >= 0 }
        try await deliver(480)
        let finished = session.finish()

        #expect(finished.metadata.gaps == [.init(copy: .drive, start: 0, end: 480)])
        #expect(finished.folders.count == 2)
        let stem = try StemFile(contentsOf: finished.folders[1].appending(path: "01 USB 01.wav"))
        #expect(stem.samples.count == 960)
        #expect(session.show.driveFolder != nil)
    }

    @Test("A Drive is asked for only while it could join or rejoin")
    func driveAskedLazily() async throws {
        let session = try session()
        var asked = 0
        let drive = drive
        _ = session.checkDestinations(drive: { asked += 1; return DestinationAccess(folder: drive) })
        #expect(asked == 1)
        // The Drive Copy is healthy: nothing to join or rejoin, so it isn't asked again.
        _ = session.checkDestinations(drive: { asked += 1; return nil })
        #expect(asked == 1)
        _ = session.finish()
    }

    @Test("A Drive too full to take 60 s of audio is released, not joined")
    func fullDriveIsReleased() async throws {
        let drive = drive
        let session = try session(free: { $0.path.hasPrefix(drive.path) ? 0 : .max })
        var released = 0
        let check = session.checkDestinations(drive: { DestinationAccess(folder: drive, release: { released += 1 }) })
        #expect(check == .carryOn)
        #expect(released == 1)
        #expect(session.copies.count == 1)
        _ = session.finish()
    }

    @Test("A Drive Copy that failed rejoins when its Destination comes back, keeping its earlier Gaps and resuming its Stems")
    func driveRejoins() async throws {
        let opened = Opened()
        let session = try session(opened: opened, wrap: { url, real in
            let fresh = url.path.contains("/Drive/") && opened.resumes.last! == nil
            return fresh ? FailingStem(real, healthyFrames: 480) : real
        })
        let drive = drive
        try await deliver(480)
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        try await waitUntil { session.copies[1].ring.joinFrame.load(ordering: .acquiring) >= 0 }
        for _ in 0..<4 { try await deliver(480) }
        try await waitUntil { session.status(.drive) == .interrupted && session.copies[1].writer.isFinished }

        var released = 0
        let before = session.copies[1].writer.stemFrameCounts
        let check = session.checkDestinations(drive: { DestinationAccess(folder: drive, release: { released += 1 }) })

        #expect(check == .carryOn)
        #expect(opened.resumes.last == before[0])
        #expect(session.status(.drive) == .recording)
        // The earlier access is let go, the new one is held to the end.
        #expect(session.copies.count == 2)
        let finished = session.finish()
        #expect(finished.metadata.gaps.contains(.init(copy: .drive, start: 0, end: 480)))
        #expect(released == 0)
    }

    @Test("The last healthy Copy running low ends the Take; a Copy running low while another has room retires")
    func lowSpace() async throws {
        let drive = drive
        var driveLow = false
        var deviceLow = false
        let session = try session(free: { url in
            (url.path.hasPrefix(drive.path) ? driveLow : deviceLow) ? 0 : .max
        })
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        try await deliver(480)

        driveLow = true
        #expect(session.checkDestinations(drive: { nil }) == .carryOn)
        #expect(session.status(.drive) == .interrupted)
        #expect(session.status(.device) == .recording)

        deviceLow = true
        #expect(session.checkDestinations(drive: { nil }) == .outOfSpace)
        _ = session.finish()
    }

    @Test("A Copy that is still interrupted at the end is missing everything from where it stopped")
    func gapsAtTakeEnd() async throws {
        let session = try session(wrap: { _, real in FailingStem(real, healthyFrames: 480) })
        for _ in 0..<4 { try await deliver(480) }
        try await waitUntil { session.status(.device) == .interrupted }

        #expect(session.gaps().isEmpty)
        #expect(session.gaps(takeEnd: 1920) == [.init(copy: .device, start: 480, end: 1920)])
        // With every Copy failed capture stops counting, so the Take ends where the frames stopped.
        let takeEnd = capture.takeFrameCount
        let finished = session.finish()
        #expect(finished.statuses[.device] == .interrupted)
        #expect(finished.statuses[.drive] == .missing)
        #expect(finished.metadata.gaps == [.init(copy: .device, start: 480, end: takeEnd)])
    }

    @Test("A Marker lands in Take.json and in the Copy that joins after it")
    func markerReachesJoiningCopy() async throws {
        let session = try session()
        try await deliver(480)
        let marker = session.addMarker()
        #expect(marker.name == "Marker 1")
        #expect(marker.position == 480)
        let drive = drive
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        try await waitUntil { session.copies[1].ring.joinFrame.load(ordering: .acquiring) >= 0 }
        try await deliver(480)
        let finished = session.finish()

        for folder in finished.folders {
            let json = try Data(contentsOf: folder.appending(path: "Take.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(TakeMetadata.self, from: json).markers == [marker])
        }
    }
}
