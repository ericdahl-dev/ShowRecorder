import Destinations
import Foundation
import MixerLink
import ProjectExport
import ShowReport

/// The Soundcheck (#63): a guided check that proves the rig before a Show. Each step passes, or says in plain words
/// what's wrong and what to do. The judges are pure; `run` drives a real Take through the Recorder.
public enum Soundcheck {
    public struct Step: Equatable, Sendable, Identifiable {
        public enum Kind: Hashable, Sendable, CaseIterable {
            /// The Mixer Link is up, with Source names.
            case mixer
            /// The input sends as many USB Channels as the Mixer does, with signal.
            case channels
            /// A short Take was written completely to every Copy.
            case take
            /// The Show folder has its report and Reaper project.
            case files
        }

        public var kind: Kind
        public var passed: Bool
        public var message: String
        public var id: Kind { kind }

        public init(kind: Kind, passed: Bool, message: String) {
            self.kind = kind
            self.passed = passed
            self.message = message
        }
    }

    /// `.otherMixer` fails and says where to connect (#647).
    public static func judgeMixer(state: MixerLinkState, sources: [Source]) -> Step {
        switch state {
        case .otherMixer(let otherMixer):
            return Step(kind: .mixer, passed: false, message: "The Mixer Link is on \(otherMixer.nameAndModel), not the Mixer you're recording from. Connect to that Mixer in Settings › Mixer Link.")
        case .notLinked:
            return Step(kind: .mixer, passed: false, message: "No Mixer linked. Add its address in Settings › Mixer Link.")
        case .connecting(let host):
            return Step(kind: .mixer, passed: false, message: "Still connecting to \(host). Check the address and the network.")
        case .down(let problem):
            return Step(kind: .mixer, passed: false, message: problem.message)
        case .linked(let identity, _):
            let which = identity.nameAndModel
            let named = sources.filter(\.hasMixerName).count
            guard named > 0 else {
                return Step(kind: .mixer, passed: false, message: "\(which) is linked, but none of its channels has a name. Name them on the Mixer to have them on the Stems.")
            }
            return Step(kind: .mixer, passed: true, message: "\(which) is linked, with \(named) channel\(named == 1 ? "" : "s") named.")
        }
    }

    /// Whether `kind` is being checked while `current` runs. USB Channels is judged from the test Take's audio, so it
    /// shows as checked during the Take too; otherwise it looked skipped (TestFlight, 2026-10-11).
    public static func isChecking(_ kind: Step.Kind, current: Step.Kind?) -> Bool {
        kind == current || (kind == .channels && current == .take)
    }

    /// - Parameters:
    ///   - expected: how many USB Channels the linked Mixer sends, when known.
    ///   - signal: what the test Take carried; nil before it ran.
    public static func judgeChannels(usbChannelCount: Int, expected: Int?, signal: TakeSignal?) -> Step {
        guard usbChannelCount > 0 else {
            return Step(kind: .channels, passed: false, message: "No audio interface is Ready. Choose the Mixer's audio interface in Settings.")
        }
        if let expected, usbChannelCount < expected {
            return Step(kind: .channels, passed: false, message: "The input sends \(usbChannelCount) USB Channels; the Mixer sends \(expected). On the Mixer, set the USB interface to \(expected)/\(expected) (X AIR Edit: Setup, Audio/Midi).")
        }
        if let signal, signal.withSignal == 0, let loudest = signal.loudest, loudest.peakDbfs > VUMeter.floorDbfs {
            return Step(kind: .channels, passed: false, message: "No USB Channel went above \(Int(TakeSignal.thresholdDbfs)) dBFS. The loudest was USB \(loudest.usbChannel), at \(Int(loudest.peakDbfs.rounded())) dBFS. Speak or play into a channel, or raise its gain on the Mixer.")
        }
        guard let signal, signal.withSignal > 0 else {
            return Step(kind: .channels, passed: false, message: "No signal on any USB Channel. Play something through the Mixer and check its USB routing.")
        }
        return Step(kind: .channels, passed: true, message: "\(usbChannelCount) USB Channels, \(signal.withSignal) with signal.")
    }

    /// - Parameters:
    ///   - copies: the test Take's Copies (#550); a Copy with no ended state isn't counted.
    ///   - driveChosen: whether a Drive folder is chosen, so the Take should have a Drive copy.
    public static func judgeTake(copies: TakeCopies, driveChosen: Bool) -> Step {
        let outcomes: [DestinationKind: CopyOutcome] = Dictionary(uniqueKeysWithValues: DestinationKind.allCases.compactMap { kind in
            copies[kind].outcome.map { (kind, $0) }
        })
        // Drive only: a Take the Drive took whole leaves no Device Copy, so it is judged by the Drive.
        let device = outcomes[.device]
        guard device != nil || (copies.isDriveOnly && outcomes[.drive] != nil) else {
            return Step(kind: .take, passed: false, message: "The test Take didn't run.")
        }
        for (kind, outcome) in (device.map { [(DestinationKind.device, $0)] } ?? []) + (outcomes[.drive].map { [(.drive, $0)] } ?? []) {
            switch outcome {
            case .complete, .repaired:
                continue
            case .hasGaps:
                let advice = kind == .drive ? "Check its cable and space." : "Check the Device's free space."
                return Step(kind: .take, passed: false, message: "The \(kind.name) copy has Gaps: the \(kind.name) stopped during the test. \(advice)")
            case .repairFailed:
                let advice = kind == .drive ? "Check its cable and space." : "Check the Device's free space."
                return Step(kind: .take, passed: false, message: "The \(kind.name) copy couldn't be Repaired. \(advice)")
            }
        }
        if driveChosen, outcomes[.drive] == nil {
            return Step(kind: .take, passed: false, message: "Nothing was written to the Drive. Check it in Settings, under Drive.")
        }
        if device == nil { return Step(kind: .take, passed: true, message: "Written to the Drive.") }
        return outcomes[.drive] == nil
            ? Step(kind: .take, passed: true, message: "Written to the Device. No Drive is chosen, so there is one Copy.")
            : Step(kind: .take, passed: true, message: "Written to the Device and the Drive.")
    }

    /// The Show folder (named after its Show) has the report and the Reaper project a finished Take writes.
    public static func judgeFiles(showFolder: URL) -> Step {
        let fm = FileManager.default
        let report = fm.fileExists(atPath: showFolder.appending(path: ShowReport.htmlFileName).path)
        let project = fm.fileExists(atPath: showFolder.appending(path: "\(showFolder.lastPathComponent).\(ReaperExporter().fileExtension)").path)
        let missing = (report ? [] : ["the Show report"]) + (project ? [] : ["the Reaper project"])
        guard missing.isEmpty else {
            return Step(kind: .files, passed: false, message: "Missing from the Show folder: \(missing.joined(separator: " and ")).")
        }
        return Step(kind: .files, passed: true, message: "The Show report and the Reaper project are in the Show folder.")
    }

    /// How long the test Take runs (Eric, #63: 30 s is enough to write, finalize and check every Copy).
    public static let takeLength: Duration = .seconds(30)

    /// Runs the Soundcheck: judges the Mixer Link, records a test Take into its own "Soundcheck" Show, judges the
    /// USB Channels, the Copies and the files, and ends that Show so the next record press starts a new one.
    /// Never during a Take. `progress` is told which step is being worked on, in the order they run; `result` gets
    /// each step's result as soon as it is judged, so the Mixer's shows before the 30 s Take, not after it.
    ///
    /// Starting the Soundcheck Show ends any open Show first, as a new Show always does. `mixer` is nil when the input
    /// isn't an X Air or X32: Mixer Link isn't offered, so its step is skipped rather than failed (#365).
    @MainActor
    public static func run(
        sequencer: TakeSequencer, mixer: MixerLinkState?, sources: [Source], expectedUSBChannels: Int?, driveChosen: Bool,
        allowance: TakeAllowance? = nil, takeLength: Duration = Soundcheck.takeLength, progress: (Step.Kind) -> Void = { _ in },
        result: (Step) -> Void = { _ in }
    ) async -> [Step] {
        let recorder = sequencer.recorder
        guard !recorder.isRecording else {
            return [Step(kind: .take, passed: false, message: "A Take is running. Stop it before the Soundcheck.")]
        }
        var mixerSteps: [Step] = []
        if let mixer {
            progress(.mixer)
            let mixerStep = judgeMixer(state: mixer, sources: sources)
            result(mixerStep)
            mixerSteps = [mixerStep]
        }
        guard recorder.isReady else {
            let channels = judgeChannels(usbChannelCount: 0, expected: expectedUSBChannels, signal: nil)
            result(channels)
            return mixerSteps + [channels]
        }

        progress(.take)
        var takeError: String?
        // The Soundcheck leaves the record screen's error as it found it (#551).
        let before = sequencer.recordError
        do {
            try sequencer.startNewShow(name: "Soundcheck", venue: "")
            // The test Take records what a Take would under the License: Free's USB Channels, no Pro extras (#558).
            // It runs through the sequencer, so it has a start time like any Take (#551).
            if await sequencer.recordOffMain(sources: sources, allowance: allowance, soundcheck: true) {
                try? await Task.sleep(for: takeLength)
                await sequencer.stop()
                await recorder.waitForRepair()
            } else if let failed = sequencer.recordError {
                takeError = "The test Take couldn't be recorded: \(failed)"
            }
        } catch {
            takeError = "The test Take couldn't be recorded: \(error.localizedDescription)"
        }
        sequencer.recordError = before
        let showFolder = recorder.currentShow?.folder

        progress(.channels)
        let channelsStep = judgeChannels(usbChannelCount: recorder.usbChannelCount, expected: expectedUSBChannels, signal: takeError == nil ? recorder.lastTakeSignal : nil)
        let takeStep = takeError.map { Step(kind: .take, passed: false, message: $0) }
            ?? judgeTake(copies: recorder.copies, driveChosen: driveChosen)
        result(channelsStep)
        result(takeStep)

        progress(.files)
        var filesStep = Step(kind: .files, passed: false, message: "There is no Show folder to check.")
        if let showFolder, let allowance, !allowance.showReport, !allowance.reaperExport {
            // Free writes neither (#558): nothing is missing.
            filesStep = Step(kind: .files, passed: true, message: "Free writes no Show report or Reaper project; the Takes are in the Show folder.")
        } else if let showFolder {
            // The report and project are written after the Take finalizes; give them a few seconds.
            for _ in 0..<50 {
                filesStep = judgeFiles(showFolder: showFolder)
                if filesStep.passed { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        result(filesStep)
        try? sequencer.endShow()
        return mixerSteps + [channelsStep, takeStep, filesStep]
    }

    /// Whether the record screen offers the Soundcheck (a banner, once): not during a Take, and not while the
    /// first-run hint to set things up is still showing, since the Soundcheck needs them set.
    public static func shouldOffer(alreadyOffered: Bool, isRecording: Bool, setupHintShowing: Bool) -> Bool {
        !alreadyOffered && !isRecording && !setupHintShowing
    }
}
