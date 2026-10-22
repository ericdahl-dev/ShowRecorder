import AudioIO
import Destinations
import Foundation
import Synchronization
@testable import Recording
import TakeFile
import Testing

/// Take.json is rewritten during a Take (a Marker, a Gap, a stand-in) on a thread of its own, one latest-wins writer per
/// Take folder, so a slow stick can't freeze the screen (#914). Stop writes the final one itself, and nothing a stuck
/// write finishes later can replace it.
@MainActor
@Suite("Take.json off the main thread")
struct TakeJsonOffMainTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    var deviceTake: URL { device.appending(path: "2026-10-06 Show/Take 01") }
    var driveTake: URL { drive.appending(path: "2026-10-06 Show/Take 01") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TakeJsonOffMainTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(_ audio: FakeAudioDevice) throws -> Recorder {
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
                                writerStopTimeout: .seconds(2))
        try recorder.arm(audio)
        return recorder
    }

    func markers(in take: URL) throws -> [String] {
        try TakeMetadata.read(fromTakeFolder: take).markers.map(\.name)
    }

    @Test("A Marker's Take.json write happens off the main thread, and still lands in both Copies")
    func markerWriteOffMain() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = try recorder(audio)
        let onMain = Mutex<[Bool]>([])
        recorder.stageTakeJson = { data, url in
            onMain.withLock { $0.append(Thread.isMainThread) }
            try data.write(to: url)
        }
        try recorder.startTake()
        deliver(4_800, to: audio)

        recorder.addMarker(named: "A")

        try await waitUntil { onMain.withLock { $0.count } >= 2 }   // the Device's and the Drive's
        #expect(onMain.withLock { $0 }.allSatisfy { !$0 }, "no Take.json write ran on the main thread")
        try await recorder.stopTake()
        #expect(try markers(in: deviceTake) == ["A"])
        #expect(try markers(in: driveTake) == ["A"])
    }

    @Test("A Dropout found mid-Take is written off the main thread too, not synchronously beside the queued writes")
    func dropoutWriteOffMain() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
                                destinationCheckInterval: nil)
        try recorder.arm(audio)
        let staged = Mutex<[(onMain: Bool, dropouts: Int)]>([])
        recorder.stageTakeJson = { data, url in
            staged.withLock { $0.append((Thread.isMainThread, (try? TakeMetadataProbe.dropoutCount(data)) ?? 0)) }
            try data.write(to: url)
        }
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 480)])
        audio.deliver([Array(repeating: 0, count: 2_000_000)])   // more than a ring holds: a Dropout
        audio.deliver([Array(repeating: 0, count: 480)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }

        await recorder.checkDestinations()

        try await waitUntil(timeout: .seconds(10)) { staged.withLock { $0.contains { $0.dropouts > 0 } } }
        #expect(staged.withLock { $0.allSatisfy { !$0.onMain } })
        try await recorder.stopTake()
    }

    @Test("Writes queued behind a slow one collapse to the newest, and never an older state after a newer one")
    func latestWins() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = try recorder(audio)
        let gate = DispatchSemaphore(value: 0)
        let seen = Mutex<[Int]>([])   // markers in each Drive write, in order
        let drive = drive
        recorder.stageTakeJson = { data, url in
            if url.path.hasPrefix(drive.path) {
                seen.withLock { $0.append((try? TakeMetadataProbe.markerCount(data)) ?? -1) }
                if seen.withLock({ $0.count }) == 1 { _ = gate.wait(timeout: .now() + 60) }
            }
            try data.write(to: url)
        }
        try recorder.startTake()
        deliver(4_800, to: audio)

        recorder.addMarker(named: "A")
        try await waitUntil { seen.withLock { $0.count } == 1 }   // the first write is under way and held
        recorder.addMarker(named: "B")
        recorder.addMarker(named: "C")
        gate.signal()
        try await waitUntil { seen.withLock { $0.last } == 3 }   // before Stop writes the last one itself
        let counts = seen.withLock { $0 }
        #expect(counts.last == 3 && counts.count == 2, "B was folded into C: \(counts)")
        #expect(counts == counts.sorted(), "never an older state after a newer one: \(counts)")
        try await recorder.stopTake()
        #expect(try markers(in: driveTake) == ["A", "B", "C"])
    }

    @Test("A Drive write that hangs: Stop still finishes, the Device's final Take.json is written, and the late write can't replace what came after")
    func hungDriveWrite() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = try recorder(audio)
        let gate = DispatchSemaphore(value: 0)
        let staged = Mutex<[URL]>([])
        let drive = drive
        recorder.stageTakeJson = { data, url in
            try data.write(to: url)   // the temp file is there; a stuck stick would hang right after
            if url.path.hasPrefix(drive.path) {
                staged.withLock { $0.append(url) }
                _ = gate.wait(timeout: .now() + 60)
            }
        }
        try recorder.startTake()
        deliver(4_800, to: audio)

        recorder.addMarker(named: "A")
        try await waitUntil { staged.withLock { $0.count } == 1 }   // the Drive's write is hung
        recorder.addMarker(named: "B")
        try await recorder.stopTake()

        #expect(try markers(in: deviceTake) == ["A", "B"], "the Device was never held up by the Drive")
        #expect(try markers(in: driveTake) == ["A", "B"], "Stop wrote the Drive's final Take.json itself")
        // Something later (a Repair, a move) rewrites the Drive's Take.json; then the stuck write wakes up.
        var later = try TakeMetadata.read(fromTakeFolder: driveTake)
        later.markers = []
        try later.write(to: driveTake)
        let temp = try #require(staged.withLock { $0.first })
        gate.signal()
        try await waitUntil { !FileManager.default.fileExists(atPath: temp.path) }   // it gave up and cleaned up

        #expect(try markers(in: driveTake) == [], "the late write did not replace the later Take.json")
    }
}

/// Counts the Markers in a Take.json as written.
enum TakeMetadataProbe {
    static func dropoutCount(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: data).dropoutCount
    }

    static func markerCount(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: data).markers.count
    }
}

@Suite("Take.json writer")
struct TakeJsonWriterTests {
    @Test("A move into place stuck on the stick holds up neither submit nor close")
    func hungMoveBlocksNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TakeJsonWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let entered = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        let gateTimedOut = Mutex(false)
        let writer = TakeJsonWriter(folder: folder, stage: { try $0.write(to: $1) }, move: { staged, target in
            entered.signal()
            if gate.wait(timeout: .now() + 30) == .timedOut { gateTimedOut.withLock { $0 = true } }
            return rename(staged.path, target.path) == 0
        })
        var metadata = TakeMetadata(show: "S", take: 1, startedAt: Date(), sampleRate: 48_000, timeReference: 0, usbChannels: [])

        writer.submit(metadata)
        #expect(entered.wait(timeout: .now() + 30) == .success, "the first write reached its move")
        metadata.markers = [.init(position: 1, name: "B", origin: .operator)]
        writer.submit(metadata)             // must not wait on the stuck move
        writer.close(moveWait: 0.05)        // nor must close
        let heldUpByTheMove = gateTimedOut.withLock { $0 }
        gate.signal()

        #expect(!heldUpByTheMove, "submit and close returned while the move was still stuck")
    }
}
