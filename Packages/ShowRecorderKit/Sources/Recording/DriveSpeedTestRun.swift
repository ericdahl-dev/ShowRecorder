import Destinations
import Foundation

/// Where the Drive speed test (#807) is offered: Debug builds only, until Eric has tried it and it moves up a level
/// (its own one-line PR).
public enum DriveSpeedTestAvailability {
    public static func isAvailable(isDebugBuild: Bool) -> Bool { isDebugBuild }

    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        isAvailable(isDebugBuild: true)
        #else
        isAvailable(isDebugBuild: false)
        #endif
    }
}

extension DriveSpeedTest {
    /// Which steps the run takes: each rate in order, climbing the channel counts until one fails.
    public struct Plan: Equatable, Sendable {
        public var sampleRates: [Int]
        public var channelSteps: [Int]
        public var stepDuration: Duration
        /// A Take marks a Gap when the Drive makes no progress this long.
        public var stallLimit: Duration

        public static let standard = Plan(
            sampleRates: [48_000, 96_000], channelSteps: [8, 16, 24, 32], stepDuration: .seconds(30), stallLimit: .seconds(2))
    }

    /// What the run found.
    public struct Report: Equatable, Sendable {
        public var plan: Plan
        public var steps: [StepResult] = []
        /// A step that wasn't run, and why, in words for the operator.
        public var skipped: [String] = []
        public var wasCanceled = false
        /// Why the run stopped on its own (the Drive went away, a file couldn't be made); what was found before is kept.
        public var failure: String?

        /// The most channels the Drive kept up with at `rate`; nil when it kept up with none of the steps.
        public func maxChannels(at rate: Int) -> Int? {
            steps.filter { $0.sampleRate == rate && $0.reliable }.map(\.channels).max()
        }

        /// The longest stall in any step.
        public var worstStall: Duration { steps.map(\.worstStall).max() ?? .zero }

        public var summary: String {
            let notes = " This is for this Drive, cable and hub, on this iPhone, iPad or Mac, today. A real Both Take also writes"
                + " the Device at the same time, which this test does not."
            var text: String
            if steps.isEmpty {
                text = "No channel count was tested."
            } else {
                let first = plan.channelSteps.min() ?? 8
                // Cut short (no room, canceled, a failure): what passed is a floor, not the Drive's limit.
                let atLeast = !skipped.isEmpty || wasCanceled || failure != nil
                func kept(_ rate: Int, short: Bool) -> String {
                    let unit = "\(rate / 1000) kHz"
                    guard steps.contains(where: { $0.sampleRate == rate }) else { return short ? "not tested at \(unit)" : "nothing tested at \(unit)" }
                    guard let channels = maxChannels(at: rate) else {
                        return short ? "fewer than \(first) at \(unit)" : "fewer than \(first) channels at \(unit)"
                    }
                    let count = atLeast ? "at least \(channels)" : "\(channels)"
                    return short ? "\(count) at \(unit)" : "\(count) channels at \(unit)"
                }
                let rates = plan.sampleRates
                text = "This Drive kept up with \(kept(rates[0], short: false))"
                if rates.count > 1 { text += " (\(kept(rates[1], short: true)))" }
                text += ". Worst stall \(String(format: "%.1f", worstStall.seconds)) s."
            }
            for message in skipped { text += " " + message }
            if let failure { text += " " + failure }
            if wasCanceled { text += " The test was canceled before it finished." }
            return text + notes
        }
    }

    /// Bytes a step writes, with a margin for the filesystem and headers.
    static func bytesNeeded(channels: Int, sampleRate: Int, duration: Duration) -> Int64 {
        Int64(Double(channels * sampleRate * 3) * duration.seconds * 1.1) + 20_000_000
    }

    /// Removes scratch folders an earlier run left on the Drive (the app quit or crashed mid-run). Only folders this test
    /// made, by name.
    public static func removeLeftovers(in drive: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: drive.path)) ?? []
        for name in names where name.hasPrefix(scratchPrefix) {
            let url = drive.appending(path: name)
            // Only a real folder: never a file or a link that happens to carry the name.
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The whole test on `drive`: the standard plan on real Stems. Blocks (the caller keeps it off the main actor, with
    /// access to the Drive folder started); `progress` is told what is running. Each step removes its scratch files, and
    /// a run starts by removing an earlier run's leftovers.
    public static func run(
        on drive: URL, isCancelled: @escaping @Sendable () -> Bool = { false }, progress: (@Sendable (String) -> Void)? = nil
    ) throws -> Report {
        let plan = Plan.standard
        return try run(
            on: drive, plan: plan, freeSpace: { DriveFolderStore.availableBytes(at: $0) }, isCancelled: isCancelled,
            progress: progress,
            step: { channels, rate in
                try runStep(
                    in: drive, channels: channels, sampleRate: rate, duration: plan.stepDuration, stallLimit: plan.stallLimit,
                    isCancelled: isCancelled)
            })
    }

    /// `run(on:)` on its own thread, for the App: the Drive's file work can block, so never on the main actor or a pool
    /// thread (#681). Gives the report, or the error that stopped it before it began.
    public static func runOffThread(
        on drive: URL, isCancelled: @escaping @Sendable () -> Bool, progress: (@Sendable (String) -> Void)?
    ) async -> Result<Report, any Error> {
        await runOffPool { Result { try run(on: drive, isCancelled: isCancelled, progress: progress) } }
    }

    /// `removeLeftovers(in:)` on its own thread.
    public static func removeLeftoversOffThread(in drive: URL) async {
        await runOffPool { removeLeftovers(in: drive) }
    }

    /// The run with its steps and free-space reading given, so a test can drive it without a Drive.
    static func run(
        on drive: URL, plan: Plan, freeSpace: (URL) -> Int64, isCancelled: () -> Bool, progress: ((String) -> Void)? = nil,
        step: (_ channels: Int, _ sampleRate: Int) throws -> StepResult
    ) throws -> Report {
        removeLeftovers(in: drive)
        var report = Report(plan: plan)
        for rate in plan.sampleRates {
            let unit = "\(rate / 1000) kHz"
            for channels in plan.channelSteps {
                if isCancelled() { report.wasCanceled = true; return report }
                let needed = bytesNeeded(channels: channels, sampleRate: rate, duration: plan.stepDuration)
                let free = freeSpace(drive)
                // A reading of 0 may be a failed read (a Drive folder whose access the caller hasn't started), not a full
                // Drive: go on, and a full Drive shows as a failed write.
                if free > 0, free < needed {
                    report.skipped.append(
                        "\(channels) channels at \(unit) not tested: not enough free space on the Drive "
                            + "(needs about \(needed / 1_000_000) MB, \(free / 1_000_000) MB free).")
                    break
                }
                progress?("Testing \(channels) channels at \(unit)…")
                let result: StepResult
                do {
                    result = try step(channels, rate)
                } catch {
                    report.failure = "The test stopped at \(channels) channels at \(unit): \(error.localizedDescription)"
                    return report
                }
                if result.wasCanceled { report.wasCanceled = true; return report }
                report.steps.append(result)
                if !result.reliable { break }
            }
        }
        return report
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
