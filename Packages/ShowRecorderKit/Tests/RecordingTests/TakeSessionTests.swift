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
        let drive = drive
        let check = session.checkDestinations(drive: { DestinationAccess(folder: drive) })

        #expect(check == .carryOn)
        #expect(session.copies.map(\.kind) == [.device, .drive])
        #expect(session.status(.drive) == .recording)
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
        var firstReleased = 0
        var secondReleased = 0
        try await deliver(480)
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive, release: { firstReleased += 1 }) })
        for _ in 0..<4 { try await deliver(480) }
        try await waitUntil { session.status(.drive) == .interrupted && session.copies[1].writer.isFinished }
        // It joined at 480 and failed on its first audio: it has the silence and nothing more.
        let failedAt = Int(session.copies[1].writer.stemFrameCounts[0])
        #expect(failedAt == 480)

        let check = session.checkDestinations(drive: { DestinationAccess(folder: drive, release: { secondReleased += 1 }) })

        #expect(check == .carryOn)
        #expect(opened.resumes.last == UInt64(failedAt))
        #expect(session.status(.drive) == .recording)
        #expect(session.copies.count == 2)
        // The earlier access is let go; the new one is held to the end.
        #expect(firstReleased == 1)
        #expect(secondReleased == 0)

        let rejoinFrame = capture.takeFrameCount
        try await deliver(480)
        let finished = session.finish()

        #expect(finished.metadata.gaps == [.init(copy: .drive, start: 0, end: 480), .init(copy: .drive, start: failedAt, end: rejoinFrame)])
        #expect(finished.statuses[.drive] == .recording)
        #expect(secondReleased == 0)
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

    @Test("A Drive join requested just before the Take stops leaves the whole Take as a Gap in the Drive Copy")
    func driveJoinStillWaitingAtStop() async throws {
        let session = try session()
        try await deliver(480)
        let drive = drive
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        // No block arrives, so the real-time side never picks the Copy's join frame.
        let takeEnd = capture.takeFrameCount
        let finished = session.finish()

        #expect(takeEnd == 480)
        #expect(finished.metadata.gaps == [.init(copy: .drive, start: 0, end: takeEnd)])
        #expect(finished.metadata.outcome(ofCopy: .drive) == .hasGaps)
    }

    @Test("A Drive rejoin requested just before the Take stops leaves the rest of the Take as a Gap in the Drive Copy")
    func driveRejoinStillWaitingAtStop() async throws {
        let opened = Opened()
        let session = try session(opened: opened, wrap: { url, real in
            let fresh = url.path.contains("/Drive/") && opened.resumes.last! == nil
            return fresh ? FailingStem(real, healthyFrames: 480) : real
        })
        let drive = drive
        try await deliver(480)
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        for _ in 0..<4 { try await deliver(480) }
        try await waitUntil { session.status(.drive) == .interrupted && session.copies[1].writer.isFinished }
        let failedAt = Int(session.copies[1].writer.stemFrameCounts[0])

        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        let takeEnd = capture.takeFrameCount
        let finished = session.finish()

        #expect(finished.metadata.gaps == [.init(copy: .drive, start: 0, end: 480), .init(copy: .drive, start: failedAt, end: takeEnd)])
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
        try await deliver(480)
        let finished = session.finish()

        for folder in finished.folders {
            let json = try Data(contentsOf: folder.appending(path: "Take.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(TakeMetadata.self, from: json).markers == [marker])
        }
    }

    @Test("Audio the ring dropped becomes a Dropout in Take.json and a Dropout Marker where it was lost")
    func dropoutRecorded() async throws {
        let session = try session()
        try await deliver(480)
        try await deliver(200_000)  // more than a ring holds: dropped
        try await deliver(480)
        let finished = session.finish()

        #expect(finished.metadata.dropouts == [.init(copy: .device, start: 480, end: 200_480)])
        #expect(finished.metadata.markers == [.init(position: 480, name: "Dropout", origin: .dropout)])
        // The Stem is as long as the Take: the silence is in it, and the Marker is in its cue points.
        let stemURL = finished.folders[0].appending(path: "01 USB 01.wav")
        #expect(try StemFile(contentsOf: stemURL).samples.count == 200_960)
        #expect(try cuePoints(stemURL) == [CuePoint(position: 480, label: "Dropout")])
    }

    @Test("Dropout Markers don't count in the operator's Marker numbering")
    func operatorMarkerNumberingSkipsDropouts() async throws {
        let session = try session()
        try await deliver(480)
        try await deliver(200_000)
        try await deliver(480)
        // The writer thread notes the drop a moment after the audio is delivered.
        try await waitUntil { !session.copies[0].writer.dropouts.isEmpty }
        _ = session.checkDestinations(drive: { nil })
        #expect(session.metadata.markers.map(\.origin) == [.dropout])

        let marker = session.addMarker()
        #expect(marker.name == "Marker 1")
        _ = session.finish()
    }

    @Test("Both Copies losing the same stretch is two Dropouts in Take.json but one Marker")
    func bothCopiesOneMarker() async throws {
        let session = try session()
        try await deliver(480)
        let drive = drive
        _ = session.checkDestinations(drive: { DestinationAccess(folder: drive) })
        try await deliver(480)  // the Drive joins
        try await deliver(200_000)  // both rings drop it
        try await deliver(480)
        let finished = session.finish()

        #expect(finished.metadata.dropouts.map(\.copy) == [.device, .drive])
        #expect(Set(finished.metadata.dropouts.map(\.start)).count == 1)
        #expect(finished.metadata.markers.filter { $0.origin == .dropout }.count == 1)
    }
}
