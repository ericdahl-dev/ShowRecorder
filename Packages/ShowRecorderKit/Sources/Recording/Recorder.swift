import AudioIO
import BroadcastWave
import Destinations
import Foundation
import MixerLink
import Observation
import ShowReport
import Synchronization

/// The recorder. While Armed it receives audio from a device and keeps meters for every USB Channel.
/// While recording it writes a Take: one Stem per USB Channel in the open Show.
@MainActor
@Observable
public final class Recorder {
    public private(set) var isArmed = false
    public private(set) var isRecording = false
    /// Stop is writing the last Take's Copies (#652): no Take starts until it is done. True from the start of `stopTake`
    /// to the end of its publishing.
    public private(set) var isFinishing = false
    public private(set) var usbChannelCount = 0
    /// The open Show, if any. Created on the first record press.
    public private(set) var currentShow: Show?
    /// Markers placed in the current (or last) Take.
    public private(set) var takeMarkers: [TakeMetadata.Marker] = []
    /// Every Marker of the current (or last) Take, the recorder's Dropout Markers too, in the order they were
    /// placed, with their time in the Take. For the Marker list.
    public private(set) var markerEntries: [MarkerEntry] = []
    /// How much of the start of the current (or last) Take is Pre-roll, in seconds: the Marker times in the
    /// files count from before the press by this much.
    public private(set) var takePreRollSeconds: Double = 0
    /// How many stretches of audio the running (or last) Take lost because a writer couldn't keep up. Each is
    /// silence of the right length in the Stems, a Marker and an entry in `Take.json`. Updated when the
    /// recorder checks Destinations (about once a second) and when the Take ends.
    public private(set) var dropoutCount = 0
    /// The USB Channels (counted from 0) whose peak has reached full scale since they were last cleared. A
    /// clip stays marked until `clearClip(channel:)` or the next Take, so it isn't missed by looking away.
    public private(set) var clippedChannels: Set<Int> = []
    /// A peak at or above this (linear) counts as a clip: within about 0.01 dB of full scale
    /// (docs/adr/0005-level-meter-scale.md).
    nonisolated public static let clipLevel: Float = 0.999
    /// Which Take ended last and why. Nil until a Take has ended.
    private(set) var lastTakeEnd: TakeEnd?
    /// Told each Take end as it happens, whoever ended it (record stopped, a full or failed Destination, an input
    /// change), once `lastTakeEnd` says so. One listener, the `TakeSequencer`, so it stays inside the module;
    /// others follow Take ends through the sequencer's events.
    @ObservationIgnored var onTakeEnded: (TakeEnd) -> Void = { _ in }
    /// How each Copy of the last Take ended up: complete, has Gaps, Repaired or Repair failed.
    private(set) var lastTakeOutcomes: [DestinationKind: CopyOutcome] = [:]
    /// How many USB Channels the last Take recorded and how many carried signal (#62: Free's limit, felt).
    public private(set) var lastTakeSignal: TakeSignal?
    /// Whether Repair is still filling Gaps from the last Take.
    public private(set) var isRepairing = false

    /// Names the operator typed for USB Channels (counted from 1). They win over the Mixer's names: a Take
    /// started with them is named so from the start, and a name typed during a Take is put on its files
    /// when it ends.
    public var channelNames: [Int: String] { naming.typed }
    /// Who names each USB Channel: typed names, and the Mixer's that arrive late in a Take (#443).
    public private(set) var naming = ChannelNaming()
    /// Names typed before on this device, newest first, offered as chips (`SavedChannelNames`).
    public private(set) var savedChannelNames: [String] = []
    @ObservationIgnored private let savedNames: UserDefaults
    /// What the current or last Take was allowed, frozen at its record press. Nil: everything (no allowance given).
    @ObservationIgnored private var lastAllowance: TakeAllowance?
    @ObservationIgnored private var namingTask: Task<Void, Never>?

    /// The Device Destination: Documents/Shows.
    public static var defaultDeviceFolder: URL {
        URL.documentsDirectory.appending(path: "Shows", directoryHint: .isDirectory)
    }

    @ObservationIgnored private let deviceFolder: URL
    @ObservationIgnored private let driveFolder: () -> DriveAccess?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let freeSpace: (URL) -> Int64
    /// How often a running Take's Destinations are checked (`checkDestinations()`). Nil leaves it to the caller.
    @ObservationIgnored private let destinationCheckInterval: Duration?
    @ObservationIgnored private var destinationChecks: Task<Void, Never>?
    /// How much audio before the record press a Take starts with, in seconds; 0 starts at the press. Read
    /// when record is pressed. The Armed buffer is sized from it when Arming, so a longer value than that
    /// gets what the buffer holds until the recorder is Armed again.
    @ObservationIgnored public var preRollSeconds: Double
    @ObservationIgnored private let makeStem: (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink
    @ObservationIgnored private var device: (any AudioIODevice)?
    /// The Armed input's sample rate, whole Hz; nil when nothing is Armed (#298).
    public private(set) var sampleRate: Int?
    @ObservationIgnored private var capture: Capture?
    /// The running Take's Copies.
    @ObservationIgnored private(set) var session: TakeSession?
    @ObservationIgnored private var lastTake: LastTake?
    /// Counts the Takes that became the last Take, so a move started before another one doesn't touch it (#630).
    @ObservationIgnored private var lastTakeGeneration = 0
    /// Set while a Take runs: a move of a Drive only Take stops at the next Stem (#630).
    @ObservationIgnored let moveStop = StandInMove.StopSignal()
    /// Whether a move of Drive only Takes is running (#630): another asked for meanwhile adds nothing.
    public private(set) var isMoving = false
    /// Drive only (#630): whether Drive only Takes are moved to the Drive: where `DriveOnlyAvailability` offers Drive only.
    /// Turning it on looks for them at once, as the App does at launch once it knows.
    public var movesDriveOnlyTakes = false {
        didSet { if movesDriveOnlyTakes, !oldValue { driveMayHaveConnected() } }
    }
    /// Drive only (#630): what the screen says about moving Takes to the Drive: the latest move that found something.
    public var moveReport: MoveReport { MoveReport(isMoving: foundTakesToMove, moves: lastMoveRun.moves, skips: lastMoveRun.skips) }
    /// Whether the running move has found Takes to move or a cut-off move to finish: until then it says nothing (#630).
    private var foundTakesToMove = false
    /// What the latest move did, while it has something to say: one with nothing to do clears it, and one where every
    /// Take moved is cleared when the next Take starts (#630).
    private var lastMoveRun: (moves: [StandInMove.Result], skips: [TakeMover.Movable]) = ([], [])
    /// The Takes the last move found but left where they are, with why (`TakeMover.Movable.Kind.skipped`) (#630).
    public private(set) var driveOnlySkips: [TakeMover.Movable] = []
    /// The move a trigger started (#630).
    @ObservationIgnored private var moveTrigger: Task<Void, Never>?
    /// What came of each Drive only Take a move took up, oldest first (#630).
    private(set) var driveOnlyMoves: [StandInMove.Result] = []
    /// Repairs ended Takes; its result is published through `copies` (from `lastTakeOutcomes`) and `isRepairing`.
    @ObservationIgnored private let repair: TakeRepair
    /// How long Stop waits on a Copy's writer before giving that Copy up (#320).
    @ObservationIgnored private let writerStopTimeout: Duration
    @ObservationIgnored private let driveStallLimit: Duration

    /// Drive only (#196, ADR 0006): a Take with a Drive is written to the Drive alone, and the Device stands in only for
    /// what the Drive can't take. Read at each record press. Offered where `DriveOnlyAvailability` allows.
    public var recordsToDriveOnly = false
    /// The host clock's ticks per second, for spotting a stop in the input (#317). Tests set it.
    @ObservationIgnored private let hostTicksPerSecond: Double
    /// Whether `AsyncStopAvailability` allows the asynchronous Stop. Nothing reads it for behavior yet (#652, A3a).
    @ObservationIgnored let asyncStopAvailable: Bool
    /// Whether the last Take was Drive only (#196, ADR 0006), Drive or not: its summary speaks of the Drive alone.
    private(set) var lastTakeWasDriveOnly = false
    /// Whether Repair moved the last Take's stand-in to the Drive and off the Device.
    private(set) var lastTakeStandInMoved = false
    /// Whether the last Take's stand-in is still on the Device after Repair.
    private(set) var lastTakeStandInKept = false

    /// - Parameters:
    ///   - deviceFolder: where the Device Copy of every Show goes.
    ///   - driveFolder: asked at each record press for the Drive folder; nil writes to the Device only.
    public init(
        deviceFolder: URL = Recorder.defaultDeviceFolder,
        driveFolder: @escaping () -> DriveAccess? = { nil },
        now: @escaping () -> Date = Date.init,
        freeSpace: @escaping (URL) -> Int64 = { DriveFolderStore.availableBytes(at: $0) },
        preRollSeconds: Double = 0,
        makeStem: @escaping (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink = { try StemWriter.open(url: $0, info: $1, resumingAt: $2) },
        savedNames: UserDefaults = .standard,
        destinationCheckInterval: Duration? = .seconds(1),
        hostTicksPerSecond: Double? = nil,
        writerStopTimeout: Duration = .seconds(5),
        driveStallLimit: Duration = .seconds(2),
        writeAbandoned: @escaping @Sendable (TakeMetadata, URL) -> Void = { try? $0.write(to: $1) },
        asyncStopAvailable: Bool = AsyncStopAvailability.isAvailableInThisBuild
    ) {
        self.asyncStopAvailable = asyncStopAvailable
        self.destinationCheckInterval = destinationCheckInterval
        self.driveStallLimit = driveStallLimit
        self.hostTicksPerSecond = hostTicksPerSecond ?? Capture.machTicksPerSecond
        self.writerStopTimeout = writerStopTimeout
        self.savedNames = savedNames
        savedChannelNames = SavedChannelNames.load(from: savedNames)
        self.freeSpace = freeSpace
        self.preRollSeconds = preRollSeconds
        repair = TakeRepair(freeSpace: freeSpace, writeAbandoned: writeAbandoned)
        self.makeStem = makeStem
        self.deviceFolder = deviceFolder
        self.driveFolder = driveFolder
        self.now = now
        repair.onChange = { [unowned self] in
            lastTakeOutcomes = repair.outcomes
            lastTakeStandInMoved = repair.moved
            // Repair moved the last Take's stand-in to the Drive and removed its Device folder (#618), or removed it as a
            // spare (#621). The outcomes are always the last Take's.
            if repair.moved || repair.outcomes[.device] == nil { lastTake?.deviceFolder = nil }
            lastTakeStandInKept = repair.standInKept
            isRepairing = repair.isRunning
        }
        repair.jobDone = { [unowned self] in regenerateReports(skipping: $0) }
        // A Show left open by a crash or an earlier launch is the open Show again.
        currentShow = Show.findOpen(in: deviceFolder)
        naming = ChannelNaming(typed: currentShow?.channelNames ?? [:])
        finishCutOffTake()
    }

    /// A Take the app was killed or crashed during is finished now (#319): its Stems cover the audio on disk, a
    /// shorter Copy is queued for Repair, and the report and Reaper project include it.
    private func finishCutOffTake() {
        guard var show = currentShow else { return }
        let access = driveFolder()
        let driveShow = access.map { $0.folder.appending(path: show.name, directoryHint: .isDirectory) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard let found = CutOffTake.finish(deviceShow: show.folder, driveShow: driveShow, lastTakeEndedAt: show.lastTakeEndedAt) else {
            access?.end()
            return
        }
        if let driveShow { try? show.useDrive(driveShow.deletingLastPathComponent()) }
        show.noteTakeEnded(at: found.endedAt)
        // The summary of a Drive only Take speaks of the Drive, at a launch as at Stop (#630).
        lastTakeWasDriveOnly = found.metadata.standIns != nil || found.metadata.driveOnly == true
        lastTakeGeneration += 1
        currentShow = show
        regenerateReports()
        if found.metadata.gaps.isEmpty || found.folders[.drive] == nil {
            access?.end()
        } else {
            repair.enqueue(found.metadata, folders: found.folders, holding: access, keepsStandIns: true)
        }
    }

    /// Starts receiving audio from `device`. Any previously Armed device is stopped first.
    public func arm(_ device: any AudioIODevice) throws {
        disarm()
        let capture = Capture(
            channelCount: device.inputChannelCount, sampleRate: device.sampleRate, preRollSeconds: preRollSeconds,
            hostTicksPerSecond: hostTicksPerSecond)
        try device.start(input: { block in capture.receive(block) })
        self.device = device
        self.capture = capture
        usbChannelCount = device.inputChannelCount
        sampleRate = Int(device.sampleRate.rounded())
        isArmed = true
    }

    /// Restarts input on the Armed device after the system stopped it (an audio session
    /// interruption), without ending a running Take.
    ///
    /// Frames the device never delivered while it was stopped are not in the Take: the Stems carry
    /// on from the next frame that arrives.
    public func restartInput() throws {
        guard let device, let capture else { throw RecorderError.notArmed }
        try device.start(input: { block in capture.receive(block) })
    }

    /// Moves input to `replacement` (for example a freshly configured device after the system
    /// reset its media services).
    ///
    /// When `replacement` has the same USB Channel count and sample rate, the running Take carries
    /// on into the same Stems and this returns `true`. Otherwise the Take is stopped and finalized
    /// (its end's reason is `.inputChanged`), the recorder Arms on `replacement`, and this returns `false`.
    @discardableResult
    public func restartInput(on replacement: any AudioIODevice) async throws -> Bool {
        guard let device, let capture,
              replacement.inputChannelCount == capture.channelCount,
              replacement.sampleRate == device.sampleRate
        else {
            if isRecording { try await stopTake(because: .inputChanged) }
            try arm(replacement)
            return false
        }
        device.stop()
        self.device = replacement
        try replacement.start(input: { block in capture.receive(block) })
        return true
    }

    /// Stops any Take, stops the device and clears the meters.
    ///
    /// Stays synchronous (#652, A3a): an `async` disarm would reach every Arm. A running Take is stopped with
    /// `stopTakeNow`, as before.
    public func disarm() {
        if isRecording { stopTakeNow() }
        device?.stop()
        device = nil
        capture = nil
        usbChannelCount = 0
        sampleRate = nil
        clippedChannels = []
        isArmed = false
    }

    /// Whether the Armed recorder is keeping Pre-roll audio.
    public var isKeepingPreRoll: Bool { capture?.preRoll != nil }

    /// The Pre-roll buffer of the Armed device: the last seconds of audio since Arming. Nil when not
    /// Armed or when Pre-roll is off.
    var armedPreRoll: PreRollBuffer? { capture?.preRoll }

    /// Frames lost since Arming because the writer couldn't keep up. (Dropouts proper come in #15.)
    public var droppedFrameCount: Int {
        capture?.maxOverflowedFrames ?? 0
    }

    /// Frames captured but not yet written to the Stems, for the slowest Destination.
    var bufferedFrameCount: Int {
        capture?.maxBufferedFrames ?? 0
    }

    /// Each USB Channel's linear peak level (0...1) since the last call. Empty when not Armed.
    public func takeMeterLevels() -> [Float] {
        capture?.meters.take() ?? []
    }

    /// Each USB Channel's peak, average level and frame count since the last call. Empty when not Armed.
    public func takeChannelLevels() -> [ChannelLevel] {
        let levels = capture?.meters.takeLevels() ?? []
        for (channel, level) in levels.enumerated() where level.peak >= Self.clipLevel {
            clippedChannels.insert(channel)
        }
        if isRecording { session?.accumulate(levels) }
        return levels
    }

    /// Clears one channel's clip mark, when the operator taps it.
    public func clearClip(channel: Int) {
        clippedChannels.remove(channel)
    }

    /// Starts a Show on purpose, with a name and a venue, ending the open Show if there is one. The folder is
    /// "YYYY-MM-DD Name" ("YYYY-MM-DD Show" for no name). The next Take lands in it.
    func startNewShow(name: String, venue: String) throws {
        guard !isRecording else { throw RecorderError.takeRunning }
        let date = now()
        nextShow = nil
        var show = try Show.create(in: deviceFolder, drive: nil, on: date, name: name, venue: venue)
        // Names belong to a Show: the one being replaced keeps its own; names typed before any Show carry over.
        if currentShow != nil { naming.replace(with: [:]) } else if !channelNames.isEmpty { show.setChannelNames(channelNames) }
        currentShow?.end(at: date)
        currentShow = show
    }

    /// Starts a Show from a Template (#33): named after it, at its venue, with its channel names, ending the open Show.
    /// The names are set as if typed, so they come back as chips. Pre-roll and the Mixer are the app's to apply.
    func startNewShow(from template: Template) throws {
        try startNewShow(name: template.name, venue: template.venue ?? "")
        naming.replace(with: [:])
        for (channel, name) in template.channelNames.sorted(by: { $0.key < $1.key }) {
            setChannelName(name, forChannel: channel)
        }
        currentShow?.setChannelNames(channelNames)
    }

    /// The name and venue the next Show gets when a record press starts one, set by the default Template (#34).
    private var nextShow: (name: String, venue: String?)?

    /// Readies the next Show from the default Template, without creating it: its channel names now, and its name and
    /// venue when a record press starts it. Only when no Show is open (an idle one is ended first) and between Takes;
    /// returns whether it did.
    @discardableResult
    func prepareNextShow(from template: Template) -> Bool {
        guard !isRecording else { return false }
        endIdleShow(at: now())
        guard currentShow == nil else { return false }
        naming.replace(with: [:])
        for (channel, name) in template.channelNames.sorted(by: { $0.key < $1.key }) {
            setChannelName(name, forChannel: channel)
        }
        nextShow = (template.name, template.venue)
        return true
    }

    /// Ends the open Show, so the next record starts a new one. Nothing happens when no Show is open.
    func endShow() throws {
        guard !isRecording else { throw RecorderError.takeRunning }
        if currentShow != nil { naming.replace(with: [:]) }
        currentShow?.end(at: now())
        currentShow = nil
    }

    /// A Show with no Take for 6 hours is over; names typed since then are for the next one.
    private func endIdleShow(at date: Date) {
        guard let open = currentShow, open.isIdle(at: date) else { return }
        currentShow?.end(at: date)
        currentShow = nil
        naming.replace(with: [:])
    }

    /// Names USB Channel `usbChannel` (from 1). Works Armed or during a Take; nothing on disk changes until the
    /// Take ends (ADR 0002), and a name that is empty or only whitespace is refused (returns false).
    @discardableResult
    public func setChannelName(_ name: String, forChannel usbChannel: Int) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if !isRecording { endIdleShow(at: now()) }
        naming.type(name, for: usbChannel)
        currentShow?.setChannelNames(channelNames)
        savedChannelNames = SavedChannelNames.adding(name, to: savedChannelNames)
        SavedChannelNames.save(savedChannelNames, to: savedNames)
        return true
    }

    /// Fills this Show's channel names from the Show before it, replacing any typed so far. Returns how many
    /// names were copied, or nil when there is no Show before this one or it has no names (nothing changes).
    @discardableResult
    public func copyChannelNamesFromLastShow() -> Int? {
        guard let current = currentShow, let previous = Show.lastShow(before: current, in: deviceFolder),
              !previous.channelNames.isEmpty else { return nil }
        naming.replace(with: previous.channelNames)
        currentShow?.setChannelNames(channelNames)
        for name in previous.channelNames.sorted(by: { $0.key > $1.key }).map(\.value) {
            savedChannelNames = SavedChannelNames.adding(name, to: savedChannelNames)
        }
        SavedChannelNames.save(savedChannelNames, to: savedNames)
        return channelNames.count
    }

    /// What the naming box and the Channel names page do with what was typed: text names the channel, an empty or
    /// blank box takes its typed name off.
    public func updateChannelName(_ text: String, forChannel usbChannel: Int) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearChannelName(forChannel: usbChannel)
        } else {
            setChannelName(text, forChannel: usbChannel)
        }
    }

    /// Takes the typed name off USB Channel `usbChannel` (from 1), so the Show's later Takes use the Mixer's name
    /// again. A Take that is running keeps the name it started with.
    public func clearChannelName(forChannel usbChannel: Int) {
        guard naming.clear(usbChannel) else { return }
        currentShow?.setChannelNames(channelNames)
    }

    /// Deletes the Show folder `name` from the chosen Copies, for good. Refused during a Take and for the open
    /// Show. The Drive is reached for the delete and let go after; without it the outcome says so.
    public func deleteShow(named name: String, from copies: Set<DestinationKind>) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        guard !isRecording else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "A Take is running.") }) }
        // A move to the Drive works on these files too (#630).
        guard !isMoving else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "Takes are moving to the Drive.") }) }
        let access = copies.contains(.drive) ? driveFolder() : nil
        defer { access?.end() }
        return ShowDeleter.delete(show: name, from: copies, device: deviceFolder, drive: access?.folder, openShow: currentShow?.name)
    }

    /// Everything recorded in the open Show, from its files, with `take` left out (#625): the Drive Copy is read under
    /// Drive access, found by the Show's name, so a Drive only Show counts its Drive Takes even after a relaunch. Nil
    /// when no Show is open or its Device folder can't be read.
    public func showRecordedSeconds(leavingOut take: Int?) -> Double? {
        guard let show = currentShow else { return nil }
        let access = driveFolder()
        defer { access?.end() }
        return try? show.recordedSeconds(leavingOut: take, driveShow: access?.folder.appending(path: show.name, directoryHint: .isDirectory))
    }

    /// Checks that the Drive Copy of Show `show` is whole (see `CopyCheck`). Reads every Stem, off the main thread.
    public func checkDriveCopy(of show: String) async -> CopyCheck.Result {
        guard let access = driveFolder() else { return .failed(["The Drive isn't available."]) }
        defer { access.end() }
        let device = deviceFolder, drive = access.folder
        return await Task.detached { CopyCheck.verify(show: show, device: device, drive: drive) }.value
    }

    /// Deletes the Device copy of Show `show`, keeping the Drive copy, but only after `checkDriveCopy` passes.
    /// Refused during a Take and for the open Show. If the check fails, nothing is deleted and the outcome
    /// says why. Permanent.
    public func deleteDeviceCopy(of show: String) async -> ShowDeleter.Outcome {
        func refuse(_ reasons: [String]) -> ShowDeleter.Outcome { .init(deleted: [], failed: reasons.map { .init(copy: .device, reason: $0) }) }
        if isRecording { return refuse(["A Take is running."]) }
        if show == currentShow?.name { return refuse(["This Show is open. End it first."]) }
        switch await checkDriveCopy(of: show) {
        case .failed(let reasons): return refuse(reasons)
        case .passed:
            // Not recording and not the open Show, as of the check; look again before deleting for good.
            return deleteShow(named: show, from: [.device])
        }
    }

    /// Deletes Take `take` of Show `show` from the chosen Copies, for good, with the same refusals as `deleteShow`.
    public func deleteTake(_ take: Int, ofShow show: String, from copies: Set<DestinationKind>) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        guard !isRecording else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "A Take is running.") }) }
        // A move to the Drive works on these files too (#630).
        guard !isMoving else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "Takes are moving to the Drive.") }) }
        let access = copies.contains(.drive) ? driveFolder() : nil
        defer { access?.end() }
        return TakeDeleter.delete(take: take, ofShow: show, from: copies, device: deviceFolder, drive: access?.folder, openShow: currentShow?.name)
    }

    /// Deletes USB Channel `channel`'s file from Take `take` of Show `show` in the chosen Copies, for good, with
    /// the same refusals as `deleteShow`.
    public func deleteChannel(_ channel: Int, inTake take: Int, ofShow show: String, from copies: Set<DestinationKind>) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        guard !isRecording else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "A Take is running.") }) }
        // A move to the Drive works on these files too (#630).
        guard !isMoving else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "Takes are moving to the Drive.") }) }
        let access = copies.contains(.drive) ? driveFolder() : nil
        defer { access?.end() }
        return StemDeleter.delete(channel: channel, inTake: take, ofShow: show, from: copies, device: deviceFolder, drive: access?.folder, openShow: currentShow?.name)
    }

    /// Starts a Take in the open Show, creating a Show first if none is open.
    ///
    /// `sources` are frozen into the Take: Stem names and bext descriptions use them, and later
    /// changes on the Mixer don't touch this Take's files. USB Channels without a Source get "USB NN".
    /// - Parameter allowance: what this Take may do, frozen at the press (ADR 0004). Nil records every USB Channel.
    func startTake(sources: [Source] = [], allowance: TakeAllowance? = nil) throws {
        guard let device, let capture else { throw RecorderError.notArmed }
        guard !isFinishing else { throw RecorderError.finishing }
        guard !isRecording else { return }
        let date = now()

        // A Show with no Take for 6 hours is over: this record starts a new one.
        endIdleShow(at: date)

        // The Drive is Pro (#705): a Take without the Drive Copy never reaches for it, so it records to the Device.
        let mayUseDrive = allowance?.driveCopy ?? true
        var drive = mayUseDrive ? driveFolder() : nil
        let opened: (show: Show, session: TakeSession, folders: [DestinationKind: URL])
        do {
            opened = try openTake(sources: sources, allowance: allowance, date: date, device: device, capture: capture, drive: drive)
        } catch where drive != nil {
            // A Drive that fails at the press doesn't stop the Take: it records to the Device alone (#315), and the
            // Drive's status says what's wrong. A Device that fails too throws its own error. The failed attempt
            // already let the Drive go.
            drive = nil
            opened = try openTake(sources: sources, allowance: allowance, date: date, device: device, capture: capture, drive: nil)
        }
        let (show, session, takeFolders) = opened
        session.onCopyFailed = { [weak self, weak session] in Task { @MainActor in await self?.copyFailed(in: session) } }
        session.stopTimeout = writerStopTimeout
        session.driveStallLimit = driveStallLimit
        if takeFolders[.drive] == nil { drive?.end() }
        self.session = session
        takeMarkers = []
        markerEntries = []
        dropoutCount = 0
        clippedChannels = []
        currentShow = show
        // The levels of a Take count from the press: drop what the meters gathered before it.
        _ = capture.meters.takeLevels()
        naming.takeStarted(with: sources)
        mixerNames = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.offset + 1, $0.element.name) })
        takeRouting = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.offset + 1, $0.element.routedFrom) })
            .compactMapValues { $0 }
        routingChanges = []
        isRecording = true
        moveStop.takeStarted()
        // An all-moved line has been seen; a warning stays until a move changes it (#630).
        if !moveReport.isProblem { lastMoveRun = ([], []) }
        if let destinationCheckInterval {
            destinationChecks = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: destinationCheckInterval)
                    await self?.checkDestinations()
                }
            }
        }
    }

    /// The Mixer Link came up (or its names changed) during a Take. If the Take started with no Mixer
    /// names, the first real ones are adopted, and put on its files when it finalizes. A Take that
    /// One attempt at opening a Take: the Show (created if none is open), its Take folders and the session. A failure
    /// leaves nothing behind (#315).
    private func openTake(
        sources: [Source], allowance: TakeAllowance?, date: Date,
        device: any AudioIODevice, capture: Capture, drive: DriveAccess?
    ) throws -> (show: Show, session: TakeSession, folders: [DestinationKind: URL]) {
        var show: Show
        do {
            if var open = currentShow {
                try open.useDrive(drive?.folder)
                show = open
            } else {
                show = try Show.create(in: deviceFolder, drive: drive?.folder, on: date, name: nextShow?.name, venue: nextShow?.venue)
                nextShow = nil
            }
        } catch {
            drive?.end()
            throw error
        }
        if show.channelNames != channelNames { show.setChannelNames(channelNames) }
        // A Show this press created stays open even if the rest fails, so the next press doesn't make another.
        if currentShow == nil { currentShow = show }
        // The Take folders this press would create, and which of them are already there: only new ones are ever undone.
        let name = TakeMetadata.name(take: show.takeCount + 1)
        let wanted = ([show.folder] + (show.driveFolder.map { [$0] } ?? [])).map { $0.appending(path: name, directoryHint: .isDirectory) }
        let alreadyThere = Set(wanted.filter { FileManager.default.fileExists(atPath: $0.path) })
        var takeFolders: [DestinationKind: URL] = [:]
        do {
            takeFolders = try show.createNextTakeFolder()
            return (show, try makeSession(), takeFolders)
        } catch {
            // Undo this press (#315): the Take folders it created go and the Take number isn't used, so the next
            // press can record. A partly created press (the Device folder made, the Drive's not) is undone too.
            for folder in wanted where !alreadyThere.contains(folder) {
                try? FileManager.default.removeItem(at: folder)
            }
            drive?.end()
            throw error
        }

        func makeSession() throws -> TakeSession {
            let sampleRate = Int(device.sampleRate.rounded())
            // The Take starts with up to `preRollSeconds` of what the Armed recorder has heard, so its
            // timeline, and every Stem's time reference, begin that long before the press.
            let preRollFrames = max(0, min(
                Int((preRollSeconds * device.sampleRate).rounded()),
                capture.preRoll?.totalWrittenFrames ?? 0,
                // Leave the buffer's second of margin, so the writer can't overwrite what's being read.
                (capture.preRoll?.capacity ?? 0) - Int(device.sampleRate.rounded())))
            let pressReference = UInt64(date.timeIntervalSince(Calendar.current.startOfDay(for: date)) * Double(sampleRate))
            let timeReference = pressReference >= UInt64(preRollFrames) ? pressReference - UInt64(preRollFrames) : 0
            let resolved = naming.sources(for: sources, channelCount: capture.channelCount, allowance: allowance)
            let channels = resolved.enumerated().map { index, source in
                TakeMetadata.USBChannel(usbChannel: index + 1, stemFile: StemFileName.make(usbChannel: index + 1, sourceName: source.name), source: source)
            }
            let recorded = allowance?.recordedChannels ?? Set(channels.map(\.usbChannel))
            lastAllowance = allowance
            var metadata = TakeMetadata(
                show: show.name, take: show.takeCount, startedAt: date, sampleRate: sampleRate,
                timeReference: timeReference, usbChannels: channels.filter { recorded.contains($0.usbChannel) })
            metadata.preRollFrames = preRollFrames > 0 ? preRollFrames : nil

            let specs = zip(channels, resolved).map { StemSpec(file: $0.stemFile, description: $1.name, isRecorded: recorded.contains($0.usbChannel)) }
            let info = StemWriter.Info(sampleRate: sampleRate, description: "", originator: "ShowRecorder", timeReference: timeReference, originationDate: date)
            return try TakeSession(
                show: show, folders: takeFolders, drive: takeFolders[.drive] != nil ? drive : nil, metadata: metadata, stems: specs,
                info: info, capture: capture, preRollFrames: preRollFrames, makeStem: makeStem, freeSpace: freeSpace,
                driveOnly: recordsToDriveOnly && (allowance?.driveCopy ?? true))
        }
    }

    /// Logs a gain change ShowRecorder made on the Mixer (#450): during a Take in its `Take.json`, with a Marker such
    /// as "Kick: gain +3.0 dB (auto-gain)"; between Takes in the Show's `Show.json`.
    public func logGainChange(_ change: TakeMetadata.GainChange) {
        var change = change
        change.at = now()
        if let session {
            let name = session.channelName(change.usbChannel) ?? String(format: "USB %02d", change.usbChannel)
            session.logGainChange(change, markerName: GainLog.markerName(for: change, channelName: name))
            refreshMarkers(from: session.metadata)
        } else {
            currentShow?.logGainChange(change)
        }
    }

    /// started with real names stays frozen. Touches no audio and no files while recording.
    public func offerSources(_ sources: [Source]) {
        guard isRecording else { return }
        logRoutingChanges(in: sources)
        logRenames(in: sources)
        naming.mixerOffered(sources)
    }

    /// The name the Mixer last gave each USB Channel during this Take (or, from the start, the Source the
    /// Take began with), to tell a rename from a repeat.
    private var mixerNames: [Int: String] = [:]

    /// The USB routing changes of the running Take, for the record screen's warning (#21). Cleared when a Take starts.
    public private(set) var routingChanges: [TakeMetadata.RoutingChange] = []
    /// What the Mixer routed to each USB Channel: from the Take's start, or from when the routing was first known
    /// (a Mixer Link that arrived after the press), and after each re-patch.
    private var takeRouting: [Int: String] = [:]

    /// What the record screen says about the running Take's routing changes (#21), naming each Stem as it was
    /// named at the start. Nil when there are none.
    public var routingNotice: String? {
        guard let session else { return nil }
        var stems: [Int: String] = [:]
        for change in routingChanges { stems[change.usbChannel] = session.channelName(change.usbChannel) }
        return RoutingChangeNotice.message(for: routingChanges, stemNames: stems)
    }

    /// A USB Channel whose routing changed (#21) is logged as a routing change with a Marker, not as a rename: from
    /// here on its Stem holds another Source. The first routing known for a USB Channel is only noted. A re-patch to
    /// something the Mixer Link can't name (no `routedFrom`) isn't told apart from not knowing: it stays a rename.
    private func logRoutingChanges(in sources: [Source]) {
        guard let session else { return }
        var logged = false
        for (index, source) in sources.enumerated() {
            let number = index + 1
            guard let now = source.routedFrom else { continue }
            guard let known = takeRouting[number] else { takeRouting[number] = now; continue }
            guard now != known else { continue }
            let from = mixerNames[number] ?? Source.fallback(usbChannel: number).name
            session.logRoutingChange(usbChannel: number, from: from, to: source.name)
            routingChanges = session.metadata.routingChanges ?? []
            takeRouting[number] = now
            mixerNames[number] = source.name
            logged = true
        }
        if logged { refreshMarkers(from: session.metadata) }
    }

    private func logRenames(in sources: [Source]) {
        guard let session else { return }
        for (index, source) in sources.enumerated() {
            let number = index + 1
            let known = mixerNames[number] ?? Source.fallback(usbChannel: number).name
            guard source.name != known else { continue }
            session.logRename(usbChannel: number, from: known, to: source.name)
            mixerNames[number] = source.name
        }
    }

    /// What the running Take was allowed at its press (#705), for what follows the Take, such as clip protection.
    /// Nil between Takes, and for a Take with no allowance (everything allowed).
    public var takeAllowance: TakeAllowance? { isRecording ? lastAllowance : nil }

    /// Whether the running Take has as many Markers as its allowance lets it (3 on Free, #705). False with no Take.
    public var markerLimitReached: Bool {
        guard isRecording, let limit = lastAllowance?.markerLimit else { return false }
        return takeMarkers.count >= limit
    }

    /// Places a Marker at the Take's current sample position (frames written so far), in every Stem
    /// of every Copy and in `Take.json`. Does nothing when no Take is running, or when the Take already has as many
    /// as its allowance lets it (3 on Free, #705). Returns whether one was placed.
    @discardableResult
    func addMarker(named name: String? = nil) -> Bool {
        guard isRecording, let session, !markerLimitReached else { return false }
        session.addMarker(named: name)
        refreshMarkers(from: session.metadata)
        return true
    }

    /// Renames one of the running Take's Markers: the one at `index` among the operator's Markers (the order
    /// of `takeMarkers`), in `Take.json` and in every Stem's cue labels, in every Copy.
    @discardableResult
    public func renameMarker(at index: Int, to name: String) -> MarkerRename {
        guard isRecording, let session else { return .notRecording }
        let result = session.renameMarker(at: index, to: name)
        refreshMarkers(from: session.metadata)
        return result
    }

    /// Where the last Take's Copies are, kept for renaming a Marker after it ended.
    private struct LastTake {
        var showName: String
        var takeNumber: Int
        /// Nil when the Take left no Device Copy (Drive only, the Device never stood in).
        var deviceFolder: URL?
        var hadDrive: Bool
    }

    /// Renames one of the last Take's operator Markers (the one at `index` among them, the order of
    /// `takeMarkers`) from the files, in every Copy it can reach: `Take.json` and every Stem's cue label.
    /// The Drive is reached again for the rename and let go after. The outcome names any Copy that wasn't
    /// updated. Waits for Repair first, which would otherwise write the old name back.
    public func renameLastTakeMarker(at index: Int, to name: String) async -> MarkerRenamer.Outcome {
        await repair.wait()
        // A move works on these files too (#630); the rename runs once none is.
        await waitWhileMoving()
        guard !isRecording, let take = lastTake else { return MarkerRenamer.Outcome(result: .notRecording, renamed: [], failed: []) }
        var copies: [DestinationKind: URL] = [:]
        copies[.device] = take.deviceFolder
        var access: DriveAccess?
        if take.hadDrive {
            access = driveFolder()
            if let access { copies[.drive] = access.folder.appending(path: take.showName).appending(path: TakeMetadata.name(take: take.takeNumber)) }
        }
        defer { access?.end() }
        var outcome = MarkerRenamer.rename(markerAt: index, to: name, in: copies, allowsProExtras: lastAllowance?.showReport ?? true)
        if take.hadDrive, access == nil {
            outcome.failed.append(.init(copy: .drive, reason: "The Drive isn't available, so its Copy still has the old name."))
        }
        if !outcome.renamed.isEmpty, let metadata = (copies[.device] ?? copies[.drive]).flatMap(Self.readTake) { refreshMarkers(from: metadata) }
        return outcome
    }

    private static func readTake(at folder: URL) -> TakeMetadata? {
        try? TakeMetadata.read(fromTakeFolder: folder)
    }

    /// Updates `takeMarkers` and `markerEntries` from the Take's metadata.
    private func refreshMarkers(from metadata: TakeMetadata) {
        takeMarkers = metadata.operatorMarkers
        let preRoll = metadata.sampleRate > 0 ? Double(metadata.preRollFrames ?? 0) / Double(metadata.sampleRate) : 0
        takePreRollSeconds = preRoll
        markerEntries = metadata.markers.enumerated().map { place, marker in
            MarkerEntry(
                id: place,
                operatorIndex: metadata.operatorIndex(ofMarkerAt: place),
                seconds: metadata.sampleRate > 0 ? Double(marker.position) / Double(metadata.sampleRate) : 0,
                secondsSincePress: metadata.sampleRate > 0
                    ? Double(max(marker.position - (metadata.preRollFrames ?? 0), 0)) / Double(metadata.sampleRate) : 0,
                name: marker.name, kind: marker.origin)
        }
    }

    /// Looks for a Destination that has become available since the Take started. A Drive that appears
    /// joins the running Take: its Stems start with silence up to the join point, which is recorded as
    /// a Gap in `Take.json` on both Copies. Also ends the Take when the last healthy Destination is about to
    /// fill. The Recorder does this on its own every `destinationCheckInterval` while recording; call it to
    /// look straight away, as Check Drive does.
    public func checkDestinations() async {
        guard isRecording, let session else { return }
        switch session.checkDestinations(drive: driveFolder) {
        case .carryOn:
            currentShow = session.show
            currentShow?.keepChannelNames(channelNames)
            dropoutCount = session.dropoutCount
            refreshMarkers(from: session.metadata)
        case .outOfSpace:
            try? await stopTake(because: .outOfSpace)
        }
    }

    /// A Copy's writer failed. Once every Copy has, there's nowhere left to record: end the Take.
    private func copyFailed(in failed: TakeSession?) async {
        guard isRecording, let session, session === failed, session.allFailed else { return }
        try? await stopTake(because: .noDestination)
    }

    /// Stops the Take and waits until every Stem is written and finalized.
    /// A Copy that failed during the Take doesn't make this throw; see `copies`.
    func stopTake() async throws {
        try await stopTake(because: .stopped)
    }

    /// Three steps (#652, A3a): `beginStop` and `publishStop` run on the main actor, the finish between them is
    /// still inline here. `isFinishing` is true from the start of the first to the end of the last.
    func stopTake(because reason: TakeEnd.Reason) async throws {
        guard let stopping = beginStop(because: reason) else { return }
        let finished = TakeSession.finish(stopping.input)
        publishStop(stopping, finished)
    }

    /// The same three steps with no suspension point, for what can't be `async`: `disarm`, and so Arming over a running Take.
    private func stopTakeNow(because reason: TakeEnd.Reason = .stopped) {
        guard let stopping = beginStop(because: reason) else { return }
        let finished = TakeSession.finish(stopping.input)
        publishStop(stopping, finished)
    }

    private struct Stopping {
        let session: TakeSession
        let input: TakeSession.FinishInput
        let reason: TakeEnd.Reason
    }

    /// Everything up to the snapshot, in this order: the last window is accumulated after the session is dropped and
    /// the destination checks are canceled, and the snapshot is taken after that (a late `attachDrive` would be missing).
    private func beginStop(because reason: TakeEnd.Reason) -> Stopping? {
        guard isRecording, let session else { return nil }
        isFinishing = true
        // Not recording from here on, so a Copy that fails while draining doesn't stop the Take again.
        isRecording = false
        self.session = nil
        destinationChecks?.cancel()
        destinationChecks = nil
        // The last window, which the screen hasn't read yet, is still part of the Take.
        session.accumulate(capture?.meters.takeLevels() ?? [])
        return Stopping(session: session, input: session.finishInput(), reason: reason)
    }

    private func publishStop(_ stopping: Stopping, _ finished: TakeSession.Finished) {
        defer { isFinishing = false }
        let session = stopping.session, reason = stopping.reason
        session.adopt(finished)
        lastTakeWasDriveOnly = session.driveOnly
        lastTakeSignal = finished.signal
        dropoutCount = finished.metadata.dropoutCount
        refreshMarkers(from: finished.metadata)
        lastTakeEnd = TakeEnd(take: finished.metadata.take, reason: reason)
        lastTake = LastTake(
            showName: session.show.name, takeNumber: finished.metadata.take, deviceFolder: finished.folders[.device],
            hadDrive: finished.folders[.drive] != nil)
        lastTakeGeneration += 1
        currentShow = session.show
        // A Copy Stop gave up on may hang on any file operation, so the main thread leaves it alone (#652).
        currentShow?.setChannelNames(channelNames, skipping: finished.abandoned)
        currentShow?.noteTakeEnded(at: now(), skipping: finished.abandoned)
        // The Takes are safe either way; the report and project are regenerated next time.
        regenerateReports(skipping: finished.abandoned)
        repair.enqueue(finished.metadata, folders: finished.folders, holding: finished.access, abandoned: finished.abandoned)
        nameChannels(of: finished.metadata)
        onTakeEnded(TakeEnd(take: finished.metadata.take, reason: reason))
        // A Drive connected during the Take, or a Take left on the Device by it, moves once it is repaired and named.
        driveMayHaveConnected()
    }

    /// Puts the names typed during the Take on its files. Waits for Repair first, which works on the Stems
    /// by their file names.
    private func nameChannels(of metadata: TakeMetadata) {
        let onFiles = Dictionary(metadata.usbChannels.map { ($0.usbChannel, $0.name) }) { first, _ in first }
        let (names, late) = naming.takeEnded(allowance: lastAllowance, onFiles: onFiles)
        guard !names.isEmpty, let take = lastTake else { return }
        let allowsProExtras = lastAllowance?.showReport ?? true
        let previous = namingTask
        namingTask = Task { @MainActor in
            await previous?.value
            await repair.wait()
            await waitWhileMoving()
            // Repair may have moved this Take off the Device meanwhile (#618). If a later Take has ended since,
            // `lastTake` describes it, so this Take's own folders are used.
            var current = take
            if let last = lastTake, last.showName == take.showName, last.takeNumber == take.takeNumber { current = last }
            var copies: [DestinationKind: URL] = [:]
            copies[.device] = current.deviceFolder
            var access: DriveAccess?
            if take.hadDrive {
                access = driveFolder()
                if let access { copies[.drive] = access.folder.appending(path: take.showName).appending(path: TakeMetadata.name(take: take.takeNumber)) }
            }
            defer { access?.end() }
            _ = ChannelRenamer.rename(names: names, lateChannels: late, in: copies, allowsProExtras: allowsProExtras)
        }
    }

    /// Rewrites the Show report and Reaper project, when the last Take's allowance includes them (Pro or Trial). Never
    /// during a Take: a Repair that finishes mid-Take leaves them for its end (#320). A Copy Stop gave up on is skipped.
    private func regenerateReports(skipping skipped: Set<DestinationKind> = []) {
        guard !isRecording else { return }
        let allowance = lastAllowance
        let copies = currentShow?.copies ?? [:]
        for kind in DestinationKind.allCases where !skipped.contains(kind) {
            guard let copy = copies[kind] else { continue }
            if allowance?.showReport ?? true { try? ShowReport.write(showFolder: copy.folder) }
            if allowance?.reaperExport ?? true { try? copy.writeProjects() }
        }
    }

    /// Drive only (#630): moves every stand-in the Device keeps, and every Drive only Take it holds whole, in any Show,
    /// to its Take on the Drive, and removes the Device's Take once the Drive is checked to hold it. Does nothing during a Take or with no Drive; a Take
    /// started meanwhile stops it at the next Stem, and one asked for while another runs does nothing. A move a crash cut
    /// off is finished or undone first (`MoveRecovery`); with no Drive, its set-aside Take stays hidden until the next
    /// move with one. Returns what came of each Take it took up.
    /// - Parameter shouldStop: replaces `moveStop` in tests.
    @discardableResult
    func moveDriveOnlyTakes(shouldStop: (@Sendable () -> Bool)? = nil) async -> [StandInMove.Result] {
        guard !isRecording, !isMoving, let access = driveFolder() else { return [] }
        isMoving = true
        defer {
            isMoving = false
            foundTakesToMove = false
            let waiting = moveWaiters
            moveWaiters = []
            for waiter in waiting { waiter.resume() }
        }
        // A Show detail rename already running finishes first; one asked for from now on waits for this move.
        while editsInProgress > 0 {
            await withCheckedContinuation { editWaiters.append($0) }
        }
        guard !isRecording else {
            access.end()
            return []
        }
        let device = deviceFolder, drive = access.folder
        let first = driveOnlyMoves.count
        let generation = lastTakeGeneration
        // A Take started from now on stops the move, even if it ends before the move asks.
        let shouldStop = shouldStop ?? moveStop.latch()
        // A move a crash cut off after setting the Device's Take aside is finished or undone first.
        let recovered = await repair.recover(deviceFolder: device, driveFolder: drive, shouldStop: shouldStop)
        if !recovered.isEmpty { foundTakesToMove = true }
        for result in recovered {
            let deviceTake = device.appending(path: result.show).appending(path: TakeMetadata.name(take: result.take))
            let driveTake = drive.appending(path: result.show).appending(path: TakeMetadata.name(take: result.take))
            driveOnlyTakeMoved(
                .init(show: result.show, take: result.take, deviceFolder: deviceTake, kind: .redundant), result.outcome,
                driveTake: driveTake, generation: generation)
        }
        driveOnlyScans += 1
        let all = await Task.detached { TakeMover.find(deviceFolder: device, driveFolder: drive) }.value
        driveOnlySkips = all.filter { if case .skipped = $0.kind { true } else { false } }
        let found = all.filter { $0.kind == .standIn || $0.kind == .deviceOnly || $0.kind == .redundant }
        guard !found.isEmpty, !isRecording else {
            access.end()
            return finishMoveRun(from: first)
        }
        foundTakesToMove = true
        repair.move(found, holding: access, shouldStop: shouldStop) { [weak self] movable, outcome in
            let driveTake = drive.appending(path: movable.show).appending(path: movable.deviceFolder.lastPathComponent)
            self?.driveOnlyTakeMoved(movable, outcome, driveTake: driveTake, generation: generation)
        }
        await repair.wait()
        return finishMoveRun(from: first)
    }

    /// What this move did, from `first` in `driveOnlyMoves`; kept for `moveReport` when it found something to say.
    private func finishMoveRun(from first: Int) -> [StandInMove.Result] {
        let moves = Array(driveOnlyMoves[first...])
        // Nothing to say clears what an earlier move said.
        lastMoveRun = moves.contains(where: { $0.outcome != .gone }) || !driveOnlySkips.isEmpty ? (moves, driveOnlySkips) : ([], [])
        return moves
    }

    /// Notes what came of moving a Drive only Take (a kept stand-in, or a Take the Device held whole), and, when it was
    /// the last Take and nothing has replaced that Take since, shows it moved in `copies`.
    private func driveOnlyTakeMoved(_ movable: TakeMover.Movable, _ outcome: StandInMove.Outcome, driveTake: URL, generation: Int) {
        driveOnlyMoves.append(.init(show: movable.show, take: movable.take, outcome: outcome))
        guard outcome == .moved else { return }
        if movable.show == currentShow?.name { regenerateReports() }
        guard !isRecording, generation == lastTakeGeneration, lastTake?.showName == movable.show, lastTake?.takeNumber == movable.take else {
            return
        }
        lastTakeStandInMoved = true
        lastTakeStandInKept = false
        lastTake?.deviceFolder = nil
        // Moved there, the Take is on the Drive now, though it may have been recorded with none.
        lastTake?.hadDrive = true
        lastTakeOutcomes[.drive] = Self.readTake(at: driveTake)?.outcome(ofCopy: .drive)
    }

    /// Drive only (#630): moves the Drive only Takes of every Show to the Drive, when it is there, outside a Take and once
    /// Repair and the naming of the last Take are done. The App calls it when the Drive folder becomes available; the
    /// Recorder after each Take and when moving is turned on. Calls while one runs wait for it, then find nothing left
    /// to do or what has changed. What came of each Take is in `driveOnlyMoves`.
    public func driveMayHaveConnected() {
        // One waiting trigger takes in any more asked for before it starts.
        guard movesDriveOnlyTakes, !isRecording, !triggerWaiting else { return }
        triggerWaiting = true
        let previous = moveTrigger
        moveTrigger = Task { [weak self] in
            await previous?.value
            await self?.waitForRepair()
            guard let self else { return }
            triggerWaiting = false
            guard !isRecording else { return }
            await moveDriveOnlyTakes()
        }
    }

    /// Whether a trigger is waiting to start its move (#630).
    @ObservationIgnored private var triggerWaiting = false
    /// Edits waiting for a move to end (#630).
    @ObservationIgnored private var moveWaiters: [CheckedContinuation<Void, Never>] = []

    /// Returns once no move is running (#630). On the main actor, what the caller does next runs before any move can
    /// start.
    func waitWhileMoving() async {
        while isMoving {
            await withCheckedContinuation { moveWaiters.append($0) }
        }
    }

    /// Counts the scans for Takes to move (#630).
    @ObservationIgnored private(set) var driveOnlyScans = 0

    /// Renames the operator Marker at `index` in Take `take` of Show `show`, in every Copy it reaches (Show detail).
    /// A move works on these files too (#630): the rename runs once none is.
    public func renameMarker(at index: Int, to name: String, inTake take: Int, ofShow show: String, allowsProExtras: Bool) async -> MarkerRenamer.Outcome {
        await waitWhileMoving()
        // Counted while its file work runs off the main actor, so a move waits for it before it starts.
        editsInProgress += 1
        defer {
            editsInProgress -= 1
            if editsInProgress == 0 {
                let waiting = editWaiters
                editWaiters = []
                for waiter in waiting { waiter.resume() }
            }
        }
        let access = driveFolder()
        let device = deviceFolder, hook = beforeDetachedRename
        return await Task.detached {
            defer { access?.end() }
            hook()
            return ShowDetail.renameMarker(at: index, to: name, inTake: take, ofShow: show, device: device, drive: access?.folder, allowsProExtras: allowsProExtras)
        }.value
    }

    /// Show detail renames whose file work is running (#630).
    @ObservationIgnored private var editsInProgress = 0
    /// Moves waiting for those to end (#630).
    @ObservationIgnored private var editWaiters: [CheckedContinuation<Void, Never>] = []

    /// Run before a Show detail rename's file work, off the main actor; tests hold it there.
    @ObservationIgnored var beforeDetachedRename: @Sendable () -> Void = {}

    /// Waits for the move a trigger started, if any (#630).
    func waitForMoves() async {
        await moveTrigger?.value
    }

    /// Waits for Repair of the last Take to finish.
    public func waitForRepair() async {
        await repair.wait()
        await namingTask?.value
    }
}

public enum RecorderError: Error, Equatable {
    case notArmed
    /// A Show can't be started or ended while a Take is running.
    case takeRunning
    /// The last Take's Copies are still being written (#652).
    case finishing
}

/// One line of the Marker list: a Marker with its time in the Take (counted from the start of the audio,
/// as in the Stems, the report and the project).
public struct MarkerEntry: Equatable, Identifiable, Sendable {
    /// Its place in the Take's list of all Markers.
    public var id: Int
    /// Which operator Marker this is (the index `Recorder.renameMarker` takes), or nil for a Marker the recorder
    /// placed (a Dropout, a gain change, a routing change), which can't be renamed.
    public var operatorIndex: Int?
    /// Counted from the start of the audio, which includes the Pre-roll.
    public var seconds: Double
    /// Counted from when Record was pressed, as the timer on the record screen does.
    public var secondsSincePress: Double
    public var name: String
    /// Who placed it: the operator, or the recorder at a Dropout, a gain change or a routing change (#528).
    public var kind: TakeMetadata.Marker.Origin

    /// A Dropout Marker: audio was lost here.
    public var isDropout: Bool { kind == .dropout }
}
