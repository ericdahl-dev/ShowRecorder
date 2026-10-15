import Destinations
import AudioIO
import Foundation
import MixerLink
import ShowReport
@testable import Recording
import Testing

/// The Soundcheck (#63): each step passes or says, in plain words, what's wrong.
@Suite("Soundcheck")
struct SoundcheckTests {
    static let xr18 = MixerIdentity(networkName: "FOH", model: "XR18", firmware: "1.26")

    @Test("Mixer: linked with Source names passes and says which Mixer")
    func mixerUp() {
        let step = Soundcheck.judgeMixer(state: .linked(Self.xr18, path: .wifi), sources: [Source(name: "Kick", color: .off), .fallback(usbChannel: 2)])
        #expect(step.passed)
        #expect(step.message == "FOH (XR18) is linked, with 1 channel named.")
    }

    @Test("Mixer: linked with no network name says the model alone (#647)")
    func mixerUpUnnamed() {
        let unnamed = MixerIdentity(networkName: "", model: "XR18", firmware: "1.26")
        let step = Soundcheck.judgeMixer(state: .linked(unnamed, path: .wifi), sources: [Source(name: "Kick", color: .off)])
        #expect(step.message == "XR18 is linked, with 1 channel named.")
    }

    @Test("Mixer: not set, down, or linked with no names each fails with what to do")
    func mixerProblems() {
        #expect(Soundcheck.judgeMixer(state: .notLinked, sources: []) == .init(kind: .mixer, passed: false, message: "No Mixer linked. Add its address in Settings › Mixer Link."))
        let down = Soundcheck.judgeMixer(state: .down(.noReply(host: "10.0.0.9")), sources: [])
        #expect(!down.passed)
        #expect(down.message == MixerLinkProblem.noReply(host: "10.0.0.9").message)
        let unnamed = Soundcheck.judgeMixer(state: .linked(Self.xr18, path: .wifi), sources: [.fallback(usbChannel: 1)])
        #expect(!unnamed.passed)
        #expect(unnamed.message == "FOH (XR18) is linked, but none of its channels has a name. Name them on the Mixer to have them on the Stems.")
    }

    @Test("Mixer: a Link on another Mixer than the Armed one fails and says which, and where to connect (#647)")
    func mixerOtherLinked() {
        let other = Soundcheck.judgeMixer(state: .otherMixer(Self.xr18), sources: [])
        #expect(other == .init(kind: .mixer, passed: false, message: "The Mixer Link is on FOH (XR18), not the Armed Mixer. Connect to the Armed Mixer in Settings › Mixer Link."))
        let unnamed = MixerIdentity(networkName: "", model: "XR18", firmware: "1.26")
        let step = Soundcheck.judgeMixer(state: .otherMixer(unnamed), sources: [])
        #expect(step.message == "The Mixer Link is on XR18, not the Armed Mixer. Connect to the Armed Mixer in Settings › Mixer Link.")
    }

    @Test("Channels: as many as the Mixer sends, with signal, passes and counts them")
    func channelsPass() {
        let step = Soundcheck.judgeChannels(usbChannelCount: 18, expected: 18, signal: TakeSignal(recorded: 18, withSignal: 12))
        #expect(step == .init(kind: .channels, passed: true, message: "18 USB Channels, 12 with signal."))
        #expect(Soundcheck.judgeChannels(usbChannelCount: 4, expected: nil, signal: TakeSignal(recorded: 4, withSignal: 1)).passed)
    }

    @Test("While the test Take records, USB Channels shows as being checked too: it is judged from that Take's audio")
    func checkingDuringTake() {
        #expect(Soundcheck.isChecking(.take, current: .take))
        #expect(Soundcheck.isChecking(.channels, current: .take))
        #expect(Soundcheck.isChecking(.channels, current: .channels))
        #expect(Soundcheck.isChecking(.files, current: .take) == false)
        #expect(Soundcheck.isChecking(.channels, current: .mixer) == false)
        #expect(Soundcheck.isChecking(.channels, current: nil) == false)
    }

    @Test("Channels: nothing Armed, fewer than the Mixer sends, or no signal each fails with what to do")
    func channelsProblems() {
        #expect(Soundcheck.judgeChannels(usbChannelCount: 0, expected: 18, signal: nil).message == "No audio interface is Armed. Choose the Mixer's audio interface in Settings.")
        #expect(Soundcheck.judgeChannels(usbChannelCount: 2, expected: 18, signal: TakeSignal(recorded: 2, withSignal: 2)).message
            == "The input sends 2 USB Channels; the Mixer sends 18. On the Mixer, set the USB interface to 18/18 (X AIR Edit: Setup, Audio/Midi).")
        #expect(Soundcheck.judgeChannels(usbChannelCount: 18, expected: 18, signal: TakeSignal(recorded: 18, withSignal: 0)).message
            == "No signal on any USB Channel. Play something through the Mixer and check its USB routing.")
        #expect(!Soundcheck.judgeChannels(usbChannelCount: 18, expected: 18, signal: TakeSignal(recorded: 18, withSignal: 0)).passed)
        // The loudest channel, so a quiet mic is told apart from no audio at all (TestFlight, 2026-10-11).
        let quiet = TakeSignal(recorded: 18, withSignal: 0, loudest: .init(usbChannel: 1, peakDbfs: -58.4))
        #expect(Soundcheck.judgeChannels(usbChannelCount: 18, expected: 18, signal: quiet).message
            == "No USB Channel went above -50 dBFS. The loudest was USB 1, at -58 dBFS. Speak or play into a channel, or raise its gain on the Mixer.")
    }

    @Test("Take: every Copy complete (or Repaired) passes and names where it went")
    func takePass() {
        #expect(Soundcheck.judgeTake(copies: takeCopies(running: false, device: .complete, drive: .repaired), driveChosen: true)
            == .init(kind: .take, passed: true, message: "Written to the Device and the Drive."))
        #expect(Soundcheck.judgeTake(copies: takeCopies(running: false, device: .complete, drive: .missing), driveChosen: false)
            == .init(kind: .take, passed: true, message: "Written to the Device. No Drive is chosen, so there is one Copy."))
    }

    @Test("Take: not run, a Copy with Gaps, or a chosen Drive that wasn't written each fails")
    func takeProblems() {
        #expect(Soundcheck.judgeTake(copies: takeCopies(running: false, device: .missing, drive: .missing), driveChosen: false).message == "The test Take didn't run.")
        #expect(Soundcheck.judgeTake(copies: takeCopies(running: false, device: .complete, drive: .hasGaps), driveChosen: true).message
            == "The Drive copy has Gaps: the Drive stopped during the test. Check its cable and space.")
        #expect(Soundcheck.judgeTake(copies: takeCopies(running: false, device: .repairFailed, drive: .complete), driveChosen: true).message
            == "The Device copy couldn't be Repaired. Check the Device's free space.")
        #expect(Soundcheck.judgeTake(copies: takeCopies(running: false, device: .complete, drive: .missing), driveChosen: true).message
            == "Nothing was written to the Drive. Check it in Settings, under Drive.")
    }

    @Test("Files: the report and the Reaper project in the Show folder pass; each missing one is named")
    func files() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SoundcheckFiles-\(UUID().uuidString)/Soundcheck")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(Soundcheck.judgeFiles(showFolder: folder).message == "Missing from the Show folder: the Show report and the Reaper project.")
        try Data().write(to: folder.appending(path: "Report.html"))
        #expect(Soundcheck.judgeFiles(showFolder: folder).message == "Missing from the Show folder: the Reaper project.")
        try Data().write(to: folder.appending(path: "Soundcheck.RPP"))
        #expect(Soundcheck.judgeFiles(showFolder: folder) == .init(kind: .files, passed: true, message: "The Show report and the Reaper project are in the Show folder."))
    }

    @Test("A run records a short Take into its own Soundcheck Show, judges every step, then ends that Show")
    @MainActor
    func run() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SoundcheckRun-\(UUID().uuidString)")
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)
        // The fake device delivers only when told: feed it a tone on channel 1 and silence on 2 while the Take runs.
        let feeding = Task { @MainActor in
            while !Task.isCancelled {
                audio.deliver([[Float](repeating: 0.5, count: 480), [Float](repeating: 0, count: 480)])
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { feeding.cancel() }

        var seen: [Soundcheck.Step.Kind] = []
        var resultsWhenTakeStarted: [Soundcheck.Step.Kind] = []
        var results: [Soundcheck.Step.Kind] = []
        let steps = await Soundcheck.run(
            sequencer: TakeSequencer(recorder: recorder, devices: FakeInputDevices(), capsAt48k: { false }), mixer: .notLinked, sources: [], expectedUSBChannels: nil, driveChosen: false,
            takeLength: .milliseconds(300),
            progress: { kind in
                seen.append(kind)
                if kind == .take { resultsWhenTakeStarted = results }
            },
            result: { results.append($0.kind) })

        #expect(steps.map(\.kind) == [.mixer, .channels, .take, .files])
        #expect(steps.map(\.passed) == [false, true, true, true])
        #expect(steps[1].message == "2 USB Channels, 1 with signal.")
        #expect(seen == [.mixer, .take, .channels, .files])
        // Each result is reported as soon as it's known: the Mixer's before the 30 s Take, not after it.
        #expect(resultsWhenTakeStarted == [.mixer])
        #expect(results == [.mixer, .channels, .take, .files])
        #expect(recorder.currentShow == nil)
        #expect(!recorder.isRecording)
        let shows = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(shows.contains { $0.contains("Soundcheck") })
    }

    /// A Soundcheck run on a 4-channel input with tone on every channel, under `allowance`; returns its steps and where it recorded.
    @MainActor
    func runFree(_ allowance: TakeAllowance?) async throws -> (steps: [Soundcheck.Step], take: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "SoundcheckFree-\(UUID().uuidString)")
        let audio = FakeAudioDevice(inputChannelCount: 4)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)
        let feeding = Task { @MainActor in
            while !Task.isCancelled {
                audio.deliver((0..<4).map { _ in [Float](repeating: 0.5, count: 480) })
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { feeding.cancel() }
        let steps = await Soundcheck.run(
            sequencer: TakeSequencer(recorder: recorder, devices: FakeInputDevices(), capsAt48k: { false }), mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false, allowance: allowance,
            takeLength: .milliseconds(300))
        let show = try #require(try FileManager.default.contentsOfDirectory(atPath: root.path).first { $0.contains("Soundcheck") })
        return (steps, root.appending(path: "\(show)/Take 01"))
    }

    @Test("On Free, the test Take records every USB Channel, as a Take would (#558, #705)")
    @MainActor
    func freeRecordsFreeChannels() async throws {
        let free = Entitlement.allowance(for: .free, channelCount: 4)
        let (_, take) = try await runFree(free)
        let stems = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }
        #expect(stems.count == 4)
    }

    @Test("On Free, the test Take writes no Show report or Reaper project, and the files step doesn't fail for it (#558)")
    @MainActor
    func freeWritesNoProExtras() async throws {
        let free = Entitlement.allowance(for: .free, channelCount: 4)
        let (steps, take) = try await runFree(free)
        let show = take.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: show.appending(path: ShowReport.htmlFileName).path))
        let files = try #require(steps.first { $0.kind == .files })
        #expect(files.passed)
        #expect(files.message == "Free writes no Show report or Reaper project; the Takes are in the Show folder.")
    }

    @Test("A run never starts during a Take")
    @MainActor
    func notDuringATake() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SoundcheckBusy-\(UUID().uuidString)")
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)
        try recorder.startTake()
        let steps = await Soundcheck.run(sequencer: TakeSequencer(recorder: recorder, devices: FakeInputDevices(), capsAt48k: { false }), mixer: .notLinked, sources: [], expectedUSBChannels: nil, driveChosen: false)
        #expect(steps == [.init(kind: .take, passed: false, message: "A Take is running. Stop it before the Soundcheck.")])
        #expect(recorder.isRecording)
        try recorder.stopTake()
    }

    @MainActor
    @Test("With an input that isn't an X Air or X32, the Mixer Link step is skipped, not failed (#365)")
    func mixerLinkStepSkipped() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SoundcheckNoMixer-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        var progressed: [Soundcheck.Step.Kind] = []
        let steps = await Soundcheck.run(sequencer: TakeSequencer(recorder: recorder, devices: FakeInputDevices(), capsAt48k: { false }), mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false,
                                         progress: { progressed.append($0) })
        #expect(!steps.contains { $0.kind == .mixer })
        #expect(!progressed.contains(.mixer))
        #expect(steps.map(\.kind) == [.channels])
    }

    @Test("The status strip has no Mixer chip for an input that isn't an X Air or X32 (#365)")
    func noMixerChip() {
        let chips = StatusChip.make(usbChannelCount: 2, deviceAvailableBytes: 1 << 34, drive: .notChosen, mixer: nil, copies: .none)
        #expect(chips.map(\.kind) == [.device, .drive])
    }

    @Test("The Soundcheck is offered once, never during a Take, and not over the first-run setup hint")
    func offer() {
        #expect(Soundcheck.shouldOffer(alreadyOffered: false, isRecording: false, setupHintShowing: false))
        #expect(!Soundcheck.shouldOffer(alreadyOffered: true, isRecording: false, setupHintShowing: false))
        #expect(!Soundcheck.shouldOffer(alreadyOffered: false, isRecording: true, setupHintShowing: false))
        #expect(!Soundcheck.shouldOffer(alreadyOffered: false, isRecording: false, setupHintShowing: true))
    }

    @Test("A Drive only test Take whose stand-in Repair moved to the Drive passes (#550)")
    func driveOnlyMovedTakePasses() {
        let step = Soundcheck.judgeTake(copies: takeCopies(running: false, driveOnly: true, device: .moved, drive: .repaired), driveChosen: true)
        #expect(step.passed)
        #expect(step.message == "Written to the Device and the Drive.")
    }

    @Test("A Drive only test Take the Drive took whole passes, with no Device Copy (#618)")
    func driveOnlyDriveWholeTakePasses() {
        let step = Soundcheck.judgeTake(copies: takeCopies(running: false, driveOnly: true, device: .missing, drive: .complete), driveChosen: true)
        #expect(step.passed)
        #expect(step.message == "Written to the Drive.")
    }
}
