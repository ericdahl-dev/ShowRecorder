import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#630): a stand-in kept on the Device moves to the Drive once the Drive is back.
extension DriveOnlyTakeTests {
    /// Waits until the Drive Stem stops growing: a writer Stop gave up on finishes its hung write once the gate opens.
    func waitForDriveStemToSettle() async throws {
        let stem = drive.appending(path: "\(take)/01 USB 01.wav")
        var last: UInt64 = .max
        try await waitUntil {
            let now = (try? StemFile.inspect(stem))?.framesOnDisk ?? 0
            defer { last = now }
            return now == last
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("A stand-in kept at Stop moves to the Drive once it is back: the Drive is whole and the Device's Take gone (#630)")
    func moveStandInKeptAtStop() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = try await recordStandInKeptTake(gate: gate)
        gate.open()
        try await waitForDriveStemToSettle()

        let results = await recorder.moveKeptStandIns()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(try driveSamples(frames: 14_400) == (0..<14_400).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "the Device's Take is gone")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/.moved Take 01").path))
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).standIns == nil)
        #expect(recorder.copies[.device] == .moved)
        #expect(recorder.copies[.drive] == .repaired)
    }

    @Test("A kept stand-in that doesn't match the Drive stays on the Device, with why, and nothing is deleted (#630)")
    func moveKeepsMismatchingStandIn() async throws {
        let crashed = try await crashAfterStandIn()
        let next = try await launch()
        let start = try standInStart()
        let standIn = device.appending(path: "\(take)/\(TakeMetadata.StandIn(start: start, end: start).folderName)/01 USB 01.wav")
        try silence(standIn, from: 0, frames: 480)

        let results = await next.moveKeptStandIns()

        let outcome = try #require(results.first?.outcome)
        guard case .kept(let reasons) = outcome else { Issue.record("moved: \(outcome)"); return }
        #expect(reasons.contains { $0.contains("different audio on the Drive") }, "\(reasons)")
        try expectStandInKept()
        #expect(try driveSamples(frames: 7_200) == (0..<7_200).map { counting()($0, 0) }, "the Drive's audio is unchanged")
        _ = crashed
    }

    @Test("A Take started during a move stops it at a Stem, with nothing removed, and a later move finishes it (#630)")
    func moveStopsForATakeAndResumes() async throws {
        let crashed = try await crashAfterStandIn()
        let next = try await launch(withDrive: false)
        let moving = recorder()
        let driveStem = drive.appending(path: "\(take)/01 USB 01.wav")
        let before = try StemFile.inspect(driveStem).framesOnDisk

        let stopped = await moving.moveKeptStandIns(shouldStop: { true })

        #expect(stopped.map(\.outcome) == [.stopped])
        try expectStandInKept()
        #expect(try StemFile.inspect(driveStem).framesOnDisk == before, "the Drive is as it was")

        let resumed = await moving.moveKeptStandIns()

        #expect(resumed.map(\.outcome) == [.moved])
        #expect(try driveSamples(frames: 7_200) == (0..<7_200).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path))
        _ = (crashed, next)
    }

    @Test("While a Take runs, a move is told to stop (#630)")
    func moveStopSetDuringATake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        #expect(!recorder.moveStop.isSet)
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(recorder.moveStop.isSet)
        #expect(await recorder.moveKeptStandIns().isEmpty, "no move starts during a Take")
        try await deliverBlocks(2, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(!recorder.moveStop.isSet)
    }

    @Test("Moving an older Take's stand-in leaves the last Take's summary as it was (#630)")
    func moveOlderTakeKeepsLastTakeSummary() async throws {
        let crashed = try await crashAfterStandIn()
        _ = try await launch(withDrive: false)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()
        let summary = CopySummary.ofLastTake(recorder.copies, dropoutCount: 0)?.text
        #expect(summary == "Drive copy: complete")

        let results = await recorder.moveKeptStandIns()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: 0)?.text == summary)
        #expect(recorder.copies[.device] == .missing)
        _ = crashed
    }

    @Test("A move asked for while one runs adds nothing: each Take is taken up once (#630)")
    func overlappingMoves() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = try await recordStandInKeptTake(gate: gate)
        gate.open()
        try await waitForDriveStemToSettle()

        async let first = recorder.moveKeptStandIns()
        async let second = recorder.moveKeptStandIns()
        let all = await first + second

        #expect(all == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
    }
}
