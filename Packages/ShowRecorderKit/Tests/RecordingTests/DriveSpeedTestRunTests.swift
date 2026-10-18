import Foundation
@testable import Recording
import Testing

/// The Drive speed test's whole run (#807): which steps it takes, when it stops climbing, and what it tells the operator.
@Suite("Drive speed test: the run")
struct DriveSpeedTestRunTests {
    let drive = FileManager.default.temporaryDirectory.appending(path: "DriveSpeedTestRunTests-\(UUID().uuidString)")

    /// A step result for a Drive that keeps up with up to `limit` channels (at any rate), else stalls for 3 s.
    private func result(_ channels: Int, _ rate: Int, limit: [Int: Int]) -> DriveSpeedTest.StepResult {
        let ok = channels <= (limit[rate] ?? 0)
        return DriveSpeedTest.StepResult(
            channels: channels, sampleRate: rate, reliable: ok, worstStall: ok ? .milliseconds(40) : .seconds(3),
            peakBacklog: .zero, fellBehind: false, framesWritten: 0, droppedFrames: 0, bytesPerSecond: 1, wasCanceled: false)
    }

    private func run(
        limit: [Int: Int], free: Int64 = .max, isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> (report: DriveSpeedTest.Report, calls: [String]) {
        nonisolated(unsafe) var calls: [String] = []
        let report = try DriveSpeedTest.run(
            on: drive, plan: .standard, freeSpace: { _ in free }, isCancelled: isCancelled,
            step: { channels, rate in
                calls.append("\(channels)@\(rate)")
                return result(channels, rate, limit: limit)
            })
        return (report, calls)
    }

    @Test("It climbs 8, 16, 24, 32 at 48 kHz then at 96 kHz, and stops climbing a rate at the first step that fails")
    func climbsAndStops() throws {
        let (report, calls) = try run(limit: [48_000: 16, 96_000: 8])
        #expect(calls == ["8@48000", "16@48000", "24@48000", "8@96000", "16@96000"])
        #expect(report.maxChannels(at: 48_000) == 16)
        #expect(report.maxChannels(at: 96_000) == 8)
        #expect(report.worstStall == .seconds(3))
    }

    @Test("A Drive that keeps up with everything reports 32 at both rates; one that fails the first step reports none")
    func extremes() throws {
        let all = try run(limit: [48_000: 32, 96_000: 32]).report
        #expect(all.maxChannels(at: 48_000) == 32)
        #expect(all.maxChannels(at: 96_000) == 32)
        #expect(all.summary.contains("32 channels at 48 kHz (32 at 96 kHz)"))
        let none = try run(limit: [:]).report
        #expect(none.maxChannels(at: 48_000) == nil)
        #expect(none.summary.contains("fewer than 8 channels at 48 kHz"))
    }

    @Test("A step the Drive has no room for is skipped with a plain message, and nothing larger runs at that rate")
    func skipsWithoutRoom() throws {
        // 8 channels at 48 kHz needs about 58 MB, 16 about 96 MB: give it 60 MB.
        let (report, calls) = try run(limit: [48_000: 32, 96_000: 32], free: 60_000_000)
        #expect(calls == ["8@48000"])
        #expect(report.skipped.count == 2)
        #expect(report.skipped.first?.contains("free space") == true)
        #expect(report.summary.contains("not tested"))
        #expect(report.summary.contains("at least 8 channels at 48 kHz"))
    }

    @Test("A free-space reading of zero is taken as unknown, not as a full Drive")
    func zeroFreeSpaceIsUnknown() throws {
        let (_, calls) = try run(limit: [48_000: 8], free: 0)
        #expect(calls.first == "8@48000")
    }

    @Test("What a step needs: the audio's bytes, 10 percent more, and 20 MB")
    func bytesNeeded() {
        // 32 channels, 96 kHz, 3 bytes, 30 s = 276.48 MB; plus 10 percent and 20 MB.
        #expect(DriveSpeedTest.bytesNeeded(channels: 32, sampleRate: 96_000, duration: .seconds(30)) == 324_128_000)
    }

    @Test("A step that throws ends the run and keeps what was found before it")
    func stepThrows() throws {
        struct Gone: Error, LocalizedError { var errorDescription: String? { "the Drive went away" } }
        let report = try DriveSpeedTest.run(
            on: drive, plan: .standard, freeSpace: { _ in .max }, isCancelled: { false },
            step: { channels, rate in
                if channels == 24 { throw Gone() }
                return result(channels, rate, limit: [48_000: 32])
            })
        #expect(report.maxChannels(at: 48_000) == 16)
        #expect(report.summary.contains("at least 16 channels at 48 kHz"))
        #expect(report.summary.contains("stopped at 24 channels at 48 kHz: the Drive went away"))
    }

    @Test("A step that reports it was canceled ends the run as canceled")
    func stepCanceled() throws {
        let report = try DriveSpeedTest.run(
            on: drive, plan: .standard, freeSpace: { _ in .max }, isCancelled: { false },
            step: { channels, rate in
                var canceled = result(channels, rate, limit: [48_000: 32])
                canceled.wasCanceled = true
                return canceled
            })
        #expect(report.wasCanceled)
        #expect(report.steps.isEmpty)
        #expect(report.summary.hasPrefix("No channel count was tested."))
    }

    @Test("A cancel stops the run and says so")
    func cancel() throws {
        nonisolated(unsafe) var asked = 0
        let (report, calls) = try run(limit: [48_000: 32, 96_000: 32], isCancelled: { asked += 1; return asked > 2 })
        #expect(report.wasCanceled)
        #expect(report.summary.contains("at least 16 channels at 48 kHz"))
        #expect(calls.count == 2)
        #expect(report.summary.contains("canceled"))
    }

    @Test("The result says it is for this Drive today, and that a real Both Take also writes the Device")
    func notes() throws {
        let summary = try run(limit: [48_000: 32, 96_000: 32]).report.summary
        #expect(summary.contains("this Drive, cable and hub"))
        #expect(summary.contains("Both"))
    }

    @Test("Leftover scratch folders are removed, and nothing else on the Drive is")
    func removesLeftovers() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: drive.appending(path: "\(DriveSpeedTest.scratchPrefix)abc"), withIntermediateDirectories: true)
        try fm.createDirectory(at: drive.appending(path: "2026-10-18 Show"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: drive) }
        // A file carrying the name is left alone too.
        try Data().write(to: drive.appending(path: "\(DriveSpeedTest.scratchPrefix)file"))
        DriveSpeedTest.removeLeftovers(in: drive)
        #expect(try fm.contentsOfDirectory(atPath: drive.path).sorted() == ["\(DriveSpeedTest.scratchPrefix)file", "2026-10-18 Show"].sorted())
    }

    @Test("The async form runs off the main thread, returns the report, and a cancel asked at the start ends it at once")
    func asyncFormCancels() async throws {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: drive) }
        let outcome = await DriveSpeedTest.runOffThread(on: drive, isCancelled: { true }, progress: nil)
        let report = try outcome.get()
        #expect(report.wasCanceled)
        #expect(report.steps.isEmpty)
    }

    @Test("The async sweep removes an earlier run's leftovers")
    func asyncSweep() async throws {
        let leftover = drive.appending(path: "\(DriveSpeedTest.scratchPrefix)old")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: drive) }
        await DriveSpeedTest.removeLeftoversOffThread(in: drive)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }

    @Test("Debug builds offer the test and Release builds don't")
    func availability() {
        #expect(DriveSpeedTestAvailability.isAvailable(isDebugBuild: true))
        #expect(!DriveSpeedTestAvailability.isAvailable(isDebugBuild: false))
    }
}
