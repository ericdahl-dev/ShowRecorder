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
    /// While a progress-based Stop (#817) waits on the Drive: how much audio it still has to write. Nil otherwise.
    public private(set) var finishProgress: FinishProgress?
    /// Callers of `waitForRepair` that came while the last Take was still being written: resumed when it is published.
    @ObservationIgnored private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    /// Gain changes made while the last Take was being written: the publish replaces `currentShow`, so they go on it after.
    @ObservationIgnored private var gainChangesWhileFinishing: [TakeMetadata.GainChange] = []
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
    @ObservationIgnored private let driveFolder: @Sendable () -> DriveAccess?
    /// Why the Drive isn't available right now, asked only after a press found none (#814).
    @ObservationIgnored private let driveProblem: @Sendable () -> String?
    /// Why the running (or last) Take started without its Drive Copy, or nil when the press had one (#814). Also in the
    /// Take's `Take.json`.
    public private(set) var driveNotice: String?
    /// Whether the running Take may have a Drive Copy: what the press decided from the tier (and, with Drive only
    /// settings, from where Takes go). The Drive joins mid-Take only when this is true (#814).
    @ObservationIgnored private var takeMayUseDrive = true
    /// Whether the tier allows the running (or last) Take a Drive Copy. Free has none, so the screen has no "No Drive"
    /// warning for it: the Drive chip already says Pro (Eric, #814).
    public private(set) var driveCopyAllowed = true
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let freeSpace: @Sendable (URL) -> Int64
    /// The free-space read under way, shared by a check that comes while it runs, so a stick that hangs on it costs one
    /// thread and not one per check (#814).
    @ObservationIgnored private var freeSpaceRead: Task<[URL: Int64], Never>?
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
    /// The longest a Take waits at the press for the Drive's folders and Stems (#914). A stick that makes them faster is
    /// ready at once; a slower one starts the Take on the Device alone and joins when it is ready. 18 Stems took 0.7 s each on
    /// the stick that stuttered.
    public static let defaultDriveStartDeadline: Duration = .milliseconds(1500)
    @ObservationIgnored private let driveStartDeadline: Duration
    /// A Take is being started by `startTakeOffMain`: waiting on the Drive, not recording yet (#914).
    public private(set) var isStarting = false
    /// The Drive start job, which a Take that gave up on it leaves to finish and clean up after itself.
    @ObservationIgnored private var driveStartJob: Task<Void, Never>?
    /// Whether that job is still running: the Drive does not join the Take until it has finished (#914), as both make the
    /// Take's folder on the Drive.
    @ObservationIgnored private var driveStartJobsRunning = 0
    /// A Stop came while the Take was starting: the start ends without a Take (#914).
    @ObservationIgnored private var startCanceled = false
    /// The meeting point of the Drive start under way, so a cancel need not wait out the deadline.
    @ObservationIgnored private var driveStartHandoff: DriveStartHandoff?

    /// Where a Take is written (#805): the Device, the Drive (Drive only, ADR 0006: the Device stands in only for what
    /// the Drive can't take), or Both. Read at each record press. The App sets it from `RecordToSetting` where
    /// `RecordToAvailability` offers it, else leaves Both, which is today's behavior.
    public var recordTo: RecordTo = .standard
    /// The host clock's ticks per second, for spotting a stop in the input (#317). Tests set it.
    @ObservationIgnored private let hostTicksPerSecond: Double
    /// The host clock now, in the ticks a block's host time counts (#877). Tests set it.
    @ObservationIgnored private let hostClock: @Sendable () -> UInt64
    /// Whether `AsyncStopAvailability` allows the asynchronous Stop: `stopTake` finishes the Take off the main actor (#652).
    @ObservationIgnored private let asyncStopRule: () -> Bool
    /// The rule's answer now, asked at each Stop rather than once at launch: StoreKit may answer after it.
    var asyncStopAvailable: Bool { asyncStopRule() }

    /// How a Take's `Take.json` is staged on disk while it records (#914); tests slow it down.
    var stageTakeJson: @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }
    /// Whether the last Take was Drive only (#196, ADR 0006), Drive or not: its summary speaks of the Drive alone.
    private(set) var lastTakeWasDriveOnly = false
    /// Whether the last Take was recorded to the Device by choice (#805): its summary misses no Drive.
    private(set) var lastTakeWasDeviceOnly = false
    /// Whether Repair moved the last Take's stand-in to the Drive and off the Device.
    private(set) var lastTakeStandInMoved = false
    /// Whether the last Take's stand-in is still on the Device after Repair.
    private(set) var lastTakeStandInKept = false

    /// - Parameters:
    ///   - deviceFolder: where the Device Copy of every Show goes.
    ///   - driveFolder: asked at each record press for the Drive folder; nil writes to the Device only.
    public init(
        deviceFolder: URL = Recorder.defaultDeviceFolder,
        driveFolder: @escaping @Sendable () -> DriveAccess? = { nil },
        driveProblem: @escaping @Sendable () -> String? = { nil },
        now: @escaping () -> Date = Date.init,
        freeSpace: @escaping @Sendable (URL) -> Int64 = { DriveFolderStore.availableBytes(at: $0) },
        preRollSeconds: Double = 0,
        makeStem: @escaping (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink = { try StemWriter.open(url: $0, info: $1, resumingAt: $2) },
        savedNames: UserDefaults = .standard,
        destinationCheckInterval: Duration? = .seconds(1),
        hostTicksPerSecond: Double? = nil,
        hostClock: @escaping @Sendable () -> UInt64 = { mach_absolute_time() },
        writerStopTimeout: Duration = .seconds(5),
        driveStallLimit: Duration = .seconds(2),
        driveStartDeadline: Duration = Recorder.defaultDriveStartDeadline,
        writeAbandoned: @escaping @Sendable (TakeMetadata, URL) -> Void = { try? $0.write(to: $1) },
        asyncStopAvailable: @escaping () -> Bool = { AsyncStopAvailability.isAvailableInThisBuild }
    ) {
        asyncStopRule = asyncStopAvailable
        self.destinationCheckInterval = destinationCheckInterval
        self.driveStallLimit = driveStallLimit
        self.driveStartDeadline = driveStartDeadline
        self.hostTicksPerSecond = hostTicksPerSecond ?? Capture.machTicksPerSecond
        self.hostClock = hostClock
        self.writerStopTimeout = writerStopTimeout
        self.savedNames = savedNames
        savedChannelNames = SavedChannelNames.load(from: savedNames)
        self.freeSpace = freeSpace
        self.preRollSeconds = preRollSeconds
        repair = TakeRepair(freeSpace: freeSpace, writeAbandoned: writeAbandoned)
        self.makeStem = makeStem
        self.deviceFolder = deviceFolder
        self.driveFolder = driveFolder
        self.driveProblem = driveProblem
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
        repair.jobDone = { [unowned self] in regenerateReportsOffMain(skipping: $0) }
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

    @ObservationIgnored private var isRecoveringAbandoned = false
    /// Takes this launch abandoned a Drive Copy of, by Show name: the writer thread may still be alive and writing, so recovery
    /// leaves them to the next launch.
    @ObservationIgnored private var abandonedThisLaunch: [String: Set<Int>] = [:]
    /// The Drive writers Stop gave up on this launch, by Show name and Take: a move leaves their Takes while one still
    /// runs, since it could write over what the move puts on the Drive (#916). Held weakly: a writer's thread keeps it
    /// alive while it runs, and its open Stems close once it is gone.
    @ObservationIgnored private var abandonedDriveWriters: [String: [Int: WeakWriter]] = [:]
    struct WeakWriter { weak var writer: TakeWriter? }
    /// Waits for the writers a move left Takes for, then moves again.
    @ObservationIgnored private var writerWait: Task<Void, Never>?
    /// The Shows and Takes whose abandoned Drive writer still runs.
    private var runningDriveWriters: [String: Set<Int>] {
        abandonedDriveWriters.mapValues { Set($0.filter { $0.value.writer?.isFinished == false }.keys) }.filter { !$0.value.isEmpty }
    }

    /// Finishes the open Show's Drive Copies that Stop gave up on (#817) once the Drive is back: their Stems cover the audio
    /// on the Drive, and Repair fills what they lack from the Device. The app calls it at launch and when it comes to the
    /// front. Does nothing during a Take, a save or a Repair, with no Drive, or when the Drive has no folder for the Show; a
    /// marker stays until its Take's Drive Copy is reachable. The file work runs off the main thread, since a Drive that was
    /// slow enough to be abandoned may be slow now. Every recovered Take with both Copies is queued for Repair, the earlier ones
    /// first; only the Show's latest Take publishes its Copies to the screen.
    public func recoverAbandonedCopies() async {
        guard !isRecording, !isStarting, !isFinishing, !isRecoveringAbandoned, !repair.isRunning, let show = currentShow,
              let access = driveFolder() else { return }
        let driveShow = access.folder.appending(path: show.name, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: driveShow.path) else {
            access.end()
            return
        }
        isRecoveringAbandoned = true
        let deviceShow = show.folder, skipping = abandonedThisLaunch[show.name] ?? [], takeCount = show.takeCount
        let found = await runOffPool {
            let found = AbandonedCopyRecovery.finish(deviceShow: deviceShow, driveShow: driveShow, skipping: skipping, upTo: takeCount)
            // Then the Take folders a canceled or hung Drive join left empty (#814): after the recovery, which needs the folder of
            // a Copy Stop gave up on, and only Takes the Show had when this look began (a Take that starts meanwhile has a higher
            // number).
            DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: takeCount)
            return found
        }
        isRecoveringAbandoned = false
        guard !found.isEmpty else {
            access.end()
            return
        }
        // A Take, a save or a Repair may have begun meanwhile, or the Show changed: the files are right, but the screen's
        // state is left alone.
        guard !isRecording, !isStarting, !isFinishing, !repair.isRunning, currentShow?.name == show.name else {
            access.end()
            return
        }
        regenerateReports()
        // Every Take with a Gap and both Copies is queued, the earlier ones first; only the Show's latest Take (queued last)
        // publishes its Copies to the screen. A Take with no Device Copy has nothing to fill its tail from.
        let repairable = found.filter { !$0.metadata.gaps.isEmpty && $0.folders[.device] != nil && $0.folders[.drive] != nil }
        guard !repairable.isEmpty else {
            access.end()
            return
        }
        for (index, take) in repairable.enumerated() {
            let latest = take.metadata.take == currentShow?.takeCount
            if latest {
                lastTakeWasDriveOnly = take.metadata.standIns != nil || take.metadata.driveOnly == true
                lastTakeGeneration += 1
            }
            // Each job holds its own access to the Drive until it is done; the first holds the one taken above.
            repair.enqueue(take.metadata, folders: take.folders, holding: index == 0 ? access : driveFolder(), keepsStandIns: true, publishing: latest)
        }
    }

    /// Starts receiving audio from `device`. Any previously Armed device is stopped first.
    public func arm(_ device: any AudioIODevice) throws {
        guard !isFinishing else { throw RecorderError.finishing }
        disarm()
        let capture = Capture(
            channelCount: device.inputChannelCount, sampleRate: device.sampleRate, preRollSeconds: preRollSeconds,
            // Room for a Take that starts while the Drive is prepared: the deadline, a second for the rest of the start (#915).
            startHeadroomSeconds: Double(driveStartDeadline.components.seconds) + Double(driveStartDeadline.components.attoseconds) / 1e18 + 1,
            hostTicksPerSecond: hostTicksPerSecond, hostClock: hostClock)
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
            if isRecording || isFinishing { try await stopTake(because: .inputChanged) }
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
    public var isKeepingPreRoll: Bool { (capture?.preRollSeconds ?? 0) > 0 }

    /// The Pre-roll buffer of the Armed device: the last seconds of audio since Arming. Nil when not Armed, or when Pre-roll
    /// is off and the Capture keeps no room for a Take that starts late (#915).
    var armedPreRoll: PreRollBuffer? { capture?.preRoll }

    /// Frames lost in this Take because the writer couldn't keep up: each Copy's count starts again when its ring is emptied,
    /// at Take start, at a rejoin and when its writer fails. (Dropouts proper come in #15.)
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
        guard !isRecording, !isStarting else { throw RecorderError.takeRunning }
        guard !isFinishing else { throw RecorderError.finishing }
        let date = now()
        nextShow = nil
        var show = try Show.create(in: deviceFolder, drive: nil, on: date, name: name, venue: venue)
        // Names belong to a Show: the one being replaced keeps its own; names typed before any Show carry over.
        if currentShow != nil { naming.replace(with: [:]) } else if !channelNames.isEmpty { show.setChannelNames(channelNames) }
        currentShow?.end(at: date, skipping: suspectDrive)
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
        guard !isRecording, !isStarting, !isFinishing else { return false }
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
        guard !isRecording, !isStarting else { throw RecorderError.takeRunning }
        guard !isFinishing else { throw RecorderError.finishing }
        if currentShow != nil { naming.replace(with: [:]) }
        currentShow?.end(at: now(), skipping: suspectDrive)
        currentShow = nil
    }

    /// A Show with no Take for 6 hours is over; names typed since then are for the next one.
    private func endIdleShow(at date: Date) {
        guard let open = currentShow, open.isIdle(at: date) else { return }
        currentShow?.end(at: date, skipping: suspectDrive)
        currentShow = nil
        naming.replace(with: [:])
    }

    /// Names USB Channel `usbChannel` (from 1). Works Armed or during a Take; nothing on disk changes until the
    /// Take ends (ADR 0002), and a name that is empty or only whitespace is refused (returns false).
    @discardableResult
    public func setChannelName(_ name: String, forChannel usbChannel: Int) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if !isRecording, !isFinishing, !isStarting { endIdleShow(at: now()) }
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
        guard !isRecording, !isStarting else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "A Take is running.") }) }
        guard !isFinishing else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: RecorderError.finishing.errorDescription ?? "") }) }
        // A move to the Drive works on these files too (#630).
        guard !isMoving else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "Takes are moving to the Drive.") }) }
        // Names are being put on a Take's files (#652): a delete would pull the folder from under it.
        guard editsInProgress == 0 else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "The Take's files are being renamed.") }) }
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

    /// `showRecordedSeconds`, read off the main thread: it lists the Drive's Show and reads its Take.json files, which can hang
    /// on a Drive that was given up on at Stop (#673).
    public func showRecordedSecondsOffMain(leavingOut take: Int?) async -> Double? {
        guard let show = currentShow else { return nil }
        // The Drive's bookmark is resolved on that thread too (it can block on a wedged Drive), and the access is ended where the
        // read ends, so a read stuck on a hung Drive keeps it only until that Drive lets go.
        let resolve = driveFolder
        return await runOffPool {
            let access = resolve()
            defer { access?.end() }
            let driveShow = access?.folder.appending(path: show.name, directoryHint: .isDirectory)
            return try? show.recordedSeconds(leavingOut: take, driveShow: driveShow)
        }
    }

    /// Checks that the Drive Copy of Show `show` is whole (see `CopyCheck`). Reads every Stem, off the main thread.
    public func checkDriveCopy(of show: String) async -> CopyCheck.Result {
        guard let access = driveFolder() else { return .failed(["The Drive isn't available."]) }
        defer { access.end() }
        let device = deviceFolder, drive = access.folder
        return await runOffPool { CopyCheck.verify(show: show, device: device, drive: drive) }
    }

    /// Deletes the Device copy of Show `show`, keeping the Drive copy, but only after `checkDriveCopy` passes.
    /// Refused during a Take and for the open Show. If the check fails, nothing is deleted and the outcome
    /// says why. Permanent.
    public func deleteDeviceCopy(of show: String) async -> ShowDeleter.Outcome {
        func refuse(_ reasons: [String]) -> ShowDeleter.Outcome { .init(deleted: [], failed: reasons.map { .init(copy: .device, reason: $0) }) }
        if isRecording || isStarting { return refuse(["A Take is running."]) }
        if show == currentShow?.name { return refuse(["This Show is open. End it first."]) }
        switch await checkDriveCopy(of: show) {
        case .failed(let reasons): return refuse(reasons)
        case .passed:
            // Not recording and not the open Show, as of the check; look again before deleting for good.
            return deleteShow(named: show, from: [.device])
        }
    }

    /// Deletes Take `take`'s Device copy, once the Drive is checked to hold everything the Device holds of it (#925): the
    /// check and delete of Delete from iPhone (#656, `releaseFromDevice`). A Take the Drive doesn't have is the only copy and
    /// is deleted as it is, unless it was recorded for the Drive: then the Drive it was recorded to must be connected.
    public func deleteDeviceCopy(of show: String, take: Int) async -> ShowDeleter.Outcome {
        func refuse(_ reasons: [String]) -> ShowDeleter.Outcome { .init(deleted: [], failed: reasons.map { .init(copy: .device, reason: $0) }) }
        switch deviceCopyDelete(of: show, take: take) {
        case .refused(let reason): return refuse([reason])
        case .onlyCopy: return deleteTake(take, ofShow: show, from: [.device])
        case .checked: break
        }
        switch await releaseFromDevice(show: show, take: take) {
        case .released:
            // As `TakeDeleter` does: the Device's report and projects no longer list the Take.
            let folder = deviceFolder.appending(path: show, directoryHint: .isDirectory)
            try? ShowReport.write(showFolder: folder)
            try? Show(name: show, folder: folder, takeCount: 0).writeProjects()
            return .init(deleted: [.device], failed: [])
        case .kept(let reasons): return refuse(reasons)
        case .stopped: return refuse(["A Take started, so nothing was deleted."])
        case .gone: return refuse(["There is no such Take in this Copy."])
        }
    }

    /// What `deleteDeviceCopy(of:take:)` would do, for the Check the Drive copy button: passed where it deletes, failed
    /// with why where it refuses. Deletes nothing.
    public func checkDeviceCopyDelete(of show: String, take: Int) async -> CopyCheck.Result {
        switch deviceCopyDelete(of: show, take: take) {
        case .refused(let reason): return .failed([reason])
        case .onlyCopy: return .passed
        case .checked: break
        }
        switch await checkRelease(show: show, take: take) {
        case .ok: return .passed
        case .no(let reasons): return .failed(reasons)
        case .stopped: return .failed(["A Take started. Check again after it."])
        }
    }

    private enum DeviceCopyDelete { case refused(String), onlyCopy, checked }

    /// Whether Take `take`'s Device copy is refused, is the only copy, or needs the Drive check first (#925).
    private func deviceCopyDelete(of show: String, take: Int) -> DeviceCopyDelete {
        if isRecording || isStarting { return .refused("A Take is running.") }
        if show == currentShow?.name { return .refused("This Show is open. End it first.") }
        let name = TakeMetadata.name(take: take)
        let folder = deviceFolder.appending(path: show).appending(path: name)
        guard FileManager.default.fileExists(atPath: folder.appending(path: TakeMetadata.fileName).path) else { return .onlyCopy }
        guard let deviceTake = Self.readTake(at: folder) else {
            return .refused("This Take's details can't be read on the Device, so it can't be checked against the Drive.")
        }
        let forDrive = deviceTake.driveOnly == true || deviceTake.standIns?.isEmpty == false
        let access = driveFolder()
        defer { access?.end() }
        let onDrive = access.map { FileManager.default.fileExists(atPath: $0.folder.appending(path: show).appending(path: name).path) } ?? false
        if onDrive { return .checked }
        // The Device's is the only copy of a Take recorded to it; a Take recorded for the Drive needs its Drive checked.
        if !forDrive { return .onlyCopy }
        return access == nil ? .refused("This Take was recorded for the Drive. Connect that Drive, so it can be checked first.") : .checked
    }

    /// Deletes Take `take` of Show `show` from the chosen Copies, for good, with the same refusals as `deleteShow`.
    public func deleteTake(_ take: Int, ofShow show: String, from copies: Set<DestinationKind>) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        guard !isRecording, !isStarting else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "A Take is running.") }) }
        guard !isFinishing else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: RecorderError.finishing.errorDescription ?? "") }) }
        // A move to the Drive works on these files too (#630).
        guard !isMoving else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "Takes are moving to the Drive.") }) }
        // Names are being put on a Take's files (#652): a delete would pull the folder from under it.
        guard editsInProgress == 0 else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "The Take's files are being renamed.") }) }
        let access = copies.contains(.drive) ? driveFolder() : nil
        defer { access?.end() }
        return TakeDeleter.delete(take: take, ofShow: show, from: copies, device: deviceFolder, drive: access?.folder, openShow: currentShow?.name)
    }

    /// Deletes USB Channel `channel`'s file from Take `take` of Show `show` in the chosen Copies, for good, with
    /// the same refusals as `deleteShow`.
    public func deleteChannel(_ channel: Int, inTake take: Int, ofShow show: String, from copies: Set<DestinationKind>) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        guard !isRecording, !isStarting else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "A Take is running.") }) }
        guard !isFinishing else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: RecorderError.finishing.errorDescription ?? "") }) }
        // A move to the Drive works on these files too (#630).
        guard !isMoving else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "Takes are moving to the Drive.") }) }
        // Names are being put on a Take's files (#652): a delete would pull the folder from under it.
        guard editsInProgress == 0 else { return .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: "The Take's files are being renamed.") }) }
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
        guard !isRecording, !isStarting else { return }
        let date = now()
        // The press, in the Pre-roll buffer's own count: read with the press time, before any file work (#915).
        let pressPosition = capture.preRoll?.totalWrittenFrames

        // A Show with no Take for 6 hours is over: this record starts a new one.
        endIdleShow(at: date)

        // The Drive is Pro (#705): a Take without the Drive Copy never reaches for it, so it records to the Device.
        // Nor does a Take recorded to the Device alone (#805).
        let mayUseDrive = recordTo.usesDrive && (allowance?.driveCopy ?? true)
        // What the press decided holds for the whole Take: a Take that may not use the Drive never gets one later (#814).
        takeMayUseDrive = mayUseDrive
        driveCopyAllowed = allowance?.driveCopy != false
        driveNotice = nil
        var drive = mayUseDrive ? driveFolder() : nil
        // Why this Take has no Drive Copy from the press (#814): always in its Take.json, so a report that asks why the Drive
        // Copy starts late has the answer; and on screen only when the app has a reason to give (a Drive chosen but not
        // there, a Drive that failed), so "no Drive chosen" doesn't grow new text.
        var driveNote: String?
        var onScreen: String?
        if allowance?.driveCopy == false {
            // The tier, not where Takes are set to go: a Take sent to the Device by choice has nothing to explain.
            driveNote = "The Drive Copy is a Pro feature."
            onScreen = driveNote
        } else if mayUseDrive, drive == nil {
            if let reason = driveProblem() {
                driveNote = "The Drive wasn't available at the press: \(reason)"
                onScreen = driveNote
            } else {
                driveNote = "No Drive was connected at the press."
            }
        }
        let opened: (show: Show, session: TakeSession, folders: [DestinationKind: URL])
        do {
            opened = try openTake(
                sources: sources, allowance: allowance, date: date, pressPosition: pressPosition, device: device, capture: capture,
                drive: drive, driveNote: driveNote)
        } catch where drive != nil {
            // A Drive that fails at the press doesn't stop the Take: it records to the Device alone (#315), and the
            // Drive's status says what's wrong. A Device that fails too throws its own error. The failed attempt
            // already let the Drive go. The error is kept (#814): it says why the Drive Copy starts late.
            drive = nil
            driveNote = "The Drive failed at the press, so this Take started on the Device only: \(Self.describe(error))"
            onScreen = driveNote
            opened = try openTake(
                sources: sources, allowance: allowance, date: date, pressPosition: pressPosition, device: device, capture: capture,
                drive: nil, driveNote: driveNote)
        }
        takeOpened(opened, drive: drive, sources: sources, capture: capture, onScreen: onScreen)
    }

    /// The Take's session exists: the Recorder is recording.
    private func takeOpened(
        _ opened: (show: Show, session: TakeSession, folders: [DestinationKind: URL]), drive: DriveAccess?,
        sources: [Source], capture: Capture, onScreen: String?
    ) {
        driveNotice = onScreen
        let (show, session, takeFolders) = opened
        session.onCopyFailed = { [weak self, weak session] in Task { @MainActor in await self?.copyFailed(in: session) } }
        session.stopTimeout = writerStopTimeout
        session.stageTakeJson = stageTakeJson
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
                    await self?.checkDestinations(awaitingDrive: false)
                }
            }
        }
    }

    /// How a Drive's start went (#914).
    private enum DriveStart {
        case prepared(TakeSession.PreparedDrive)
        case noDrive(problem: String?)
        case failed
        case tooSlow
    }

    /// Starts a Take like `startTake`, without the main actor waiting on the Drive (#914). The Drive's folders and Stems are
    /// made on a thread of its own, and the Take waits for them at most `driveStartDeadline`. A Drive that is slower starts the
    /// Take on the Device alone, as one that was not there at the press, and joins when it is ready (`checkDestinations`).
    /// `isStarting` is true meanwhile: no second start, and nothing that changes the Show.
    func startTakeOffMain(sources: [Source] = [], allowance: TakeAllowance? = nil) async throws {
        guard let device, let capture else { throw RecorderError.notArmed }
        guard !isFinishing else { throw RecorderError.finishing }
        guard !isRecording, !isStarting else { return }
        isStarting = true
        startCanceled = false
        defer {
            isStarting = false
            driveStartHandoff = nil
        }
        let date = now()
        let pressPosition = capture.preRoll?.totalWrittenFrames
        endIdleShow(at: date)

        let mayUseDrive = recordTo.usesDrive && (allowance?.driveCopy ?? true)
        takeMayUseDrive = mayUseDrive
        driveCopyAllowed = allowance?.driveCopy != false
        driveNotice = nil
        var driveNote: String?
        if allowance?.driveCopy == false { driveNote = "The Drive Copy is a Pro feature." }
        var onScreen = driveNote
        // The Device's side first: the Show and the Take folder there, and what the session is made from. Nothing of the
        // Drive's is touched on this thread.
        var plan = try planTake(
            sources: sources, allowance: allowance, date: date, pressPosition: pressPosition, capture: capture, drive: nil, driveNote: driveNote)
        // The Show has this Take from now on: a gain change or a name typed while the Drive is prepared lands on it, and is
        // still there when the session is made.
        currentShow = plan.show
        var prepared: TakeSession.PreparedDrive?
        if mayUseDrive, allowance?.driveCopy != false {
            switch await startDrive(plan) {
            case .prepared(let drive):
                prepared = drive
            case .noDrive(let problem):
                driveNote = problem.map { "The Drive wasn't available at the press: \($0)" } ?? "No Drive was connected at the press."
                if problem != nil { onScreen = driveNote }
            case .failed:
                driveNote = "The Drive failed at the press, so this Take started on the Device only."
                onScreen = driveNote
            case .tooSlow:
                driveNote = "The Drive was too slow to start the Take, so this Take started on the Device only."
                onScreen = driveNote
            }
        }
        plan.metadata.driveNote = driveNote
        // The input may have been disarmed, or another one Armed, while the Drive was working: this Take is not for it.
        // Nor is one that Stop canceled.
        guard self.capture === capture, !startCanceled else {
            if let prepared { await runOffPool { TakeSession.discardDriveStart(prepared) } }
            plan.undo()
            giveBackTake(of: plan)
            throw self.capture === capture ? RecorderError.startCanceled : RecorderError.notArmed
        }
        // What the Show took meanwhile (gain changes, names) comes along; the Drive the job prepared joins it.
        if let current = currentShow, current.folder == plan.show.folder { plan.show = current }
        if let prepared { plan.show.adoptDrive(from: prepared.show) }
        let session: TakeSession
        do {
            session = try makeSession(plan, device: device, capture: capture, drive: nil, preparedDrive: prepared)
        } catch {
            // The session leaves a prepared Drive to us, and its cleanup is file work for a thread of its own.
            if let prepared { await runOffPool { TakeSession.discardDriveStart(prepared) } }
            plan.undo()
            giveBackTake(of: plan)
            throw error
        }
        // The job leaves the Device's Show.json alone; the Show now says a Drive Copy was written.
        if prepared != nil { try? plan.show.file.write(to: plan.show.folder) }
        takeOpened((plan.show, session, plan.takeFolders), drive: nil, sources: sources, capture: capture, onScreen: onScreen)
    }

    /// Makes the Drive's folders and Stems on a thread of its own and waits for them, at most `driveStartDeadline`. Past
    /// it the job is canceled (it cleans up after itself, and a late join waits until it has) and the Take goes without.
    private func startDrive(_ plan: TakePlan) async -> DriveStart {
        let cancel = AttachCancel()
        let handoff = DriveStartHandoff()
        nonisolated(unsafe) let makeStem = makeStem
        nonisolated(unsafe) let problem = driveProblem
        let driveFolder = driveFolder, freeSpace = freeSpace
        let show = plan.show, metadata = plan.metadata, specs = plan.specs, info = plan.info
        driveStartJobsRunning += 1
        let job = Task {
            await runOffPool {
                let missing = DriveStartMissing()
                let prepared = TakeSession.prepareDriveStart(
                    show: show, metadata: metadata, stems: specs, info: info, makeStem: makeStem, freeSpace: freeSpace,
                    drive: {
                        let access = driveFolder()
                        if access == nil { missing.set() }
                        return access
                    }, cancel: cancel)
                let why = prepared == nil && missing.isSet ? problem() : nil
                let finished = DriveStartHandoff.Finished(prepared: prepared, noDrive: missing.isSet, problem: why)
                if let late = handoff.finish(finished) { TakeSession.discardDriveStart(late) }
            }
        }
        driveStartJob = job
        Task { [weak self] in
            await job.value
            self?.driveStartJobsRunning -= 1
        }
        driveStartHandoff = handoff
        let deadline = driveStartDeadline
        let timer = Task {
            do { try await Task.sleep(for: deadline) } catch { return }
            handoff.timeOut()
        }
        let outcome = await handoff.wait()
        timer.cancel()
        switch outcome {
        case .timedOut:
            cancel.cancel()
            return .tooSlow
        case .finished(let finished):
            if let prepared = finished.prepared { return .prepared(prepared) }
            return finished.noDrive ? .noDrive(problem: finished.problem) : .failed
        }
    }

    /// A start that came to nothing: the Show takes back the Take number its plan used.
    private func giveBackTake(of plan: TakePlan) {
        guard currentShow?.folder == plan.show.folder else { return }
        currentShow?.giveBackTake()
    }

    /// Stop came while a Take was starting (`isStarting`): the start ends without a Take, and its Drive work is undone.
    func cancelStart() {
        guard isStarting else { return }
        startCanceled = true
        driveStartHandoff?.timeOut()
    }

    /// Waits for the Drive start job, if one is running (a Take whose Drive was too slow leaves it to finish and clean up).
    func waitForDriveStartJob() async {
        await driveStartJob?.value
    }

    /// A Take about to start: its Show and Take folder on the Device, and what its session is made from.
    struct TakePlan {
        var show: Show
        var takeFolders: [DestinationKind: URL]
        var metadata: TakeMetadata
        var specs: [StemSpec]
        var info: StemWriter.Info
        var preRollFrames: Int
        /// The Pre-roll buffer's frame count at the press: where the Take's timeline starts, plus Pre-roll (#915).
        var pressPosition: Int?
        var allowance: TakeAllowance?
        /// Where this Take goes, decided at the press: Record to can change while the Drive is being prepared (#914).
        var driveOnly: Bool
        var deviceOnly: Bool
        /// The Take folders this press made (and the ones it found), so only new ones are ever undone.
        var wanted: [URL]
        var alreadyThere: Set<URL>

        /// Undoes this press (#315): the Take folders it created go and the Take number isn't used.
        func undo() {
            for folder in wanted where !alreadyThere.contains(folder) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    /// The Mixer Link came up (or its names changed) during a Take. If the Take started with no Mixer
    /// names, the first real ones are adopted, and put on its files when it finalizes. A Take that
    /// One attempt at opening a Take: the Show (created if none is open), its Take folders and the session. A failure
    /// leaves nothing behind (#315).
    private func openTake(
        sources: [Source], allowance: TakeAllowance?, date: Date, pressPosition: Int?,
        device: any AudioIODevice, capture: Capture, drive: DriveAccess?, driveNote: String? = nil
    ) throws -> (show: Show, session: TakeSession, folders: [DestinationKind: URL]) {
        let plan = try planTake(
            sources: sources, allowance: allowance, date: date, pressPosition: pressPosition, capture: capture, drive: drive, driveNote: driveNote)
        do {
            return (plan.show, try makeSession(plan, device: device, capture: capture, drive: drive, preparedDrive: nil), plan.takeFolders)
        } catch {
            plan.undo()
            drive?.end()
            throw error
        }
    }

    /// The Show (created if none is open), its Take folders and what the session is made from. A failure leaves nothing
    /// behind (#315) and lets `drive` go.
    private func planTake(
        sources: [Source], allowance: TakeAllowance?, date: Date, pressPosition: Int?, capture: Capture, drive: DriveAccess?,
        driveNote: String?
    ) throws -> TakePlan {
        guard let device else {
            drive?.end()
            throw RecorderError.notArmed
        }
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
        let takeFolders: [DestinationKind: URL]
        do {
            takeFolders = try show.createNextTakeFolder()
        } catch {
            // Undo this press (#315): the Take folders it created go and the Take number isn't used, so the next
            // press can record. A partly created press (the Device folder made, the Drive's not) is undone too.
            for folder in wanted where !alreadyThere.contains(folder) {
                try? FileManager.default.removeItem(at: folder)
            }
            drive?.end()
            throw error
        }

        let sampleRate = Int(device.sampleRate.rounded())
        // The Take starts with up to `preRollSeconds` of what the Armed recorder has heard, so its
        // timeline, and every Stem's time reference, begin that long before the press.
        let preRollFrames = max(0, min(
            Int((preRollSeconds * device.sampleRate).rounded()),
            pressPosition ?? 0,
            // What the buffer was made to keep. Its second of margin (so the writer can't overwrite what's being read) and
            // its room for a Take that starts late (#915) are not Pre-roll.
            Int((capture.preRollSeconds * device.sampleRate).rounded())))
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
        metadata.driveNote = driveNote
        let driveOnly = recordTo.isDriveOnly && (allowance?.driveCopy ?? true)
        let deviceOnly = !recordTo.usesDrive && (allowance?.driveCopy ?? true)
        // Every Copy's Take.json says the Take is Drive only, the Drive's from the job that made it (#630).
        if driveOnly { metadata.driveOnly = true }

        let specs = zip(channels, resolved).map { StemSpec(file: $0.stemFile, description: $1.name, isRecorded: recorded.contains($0.usbChannel)) }
        let info = StemWriter.Info(sampleRate: sampleRate, description: "", originator: "ShowRecorder", timeReference: timeReference, originationDate: date)
        return TakePlan(
            show: show, takeFolders: takeFolders, metadata: metadata, specs: specs, info: info, preRollFrames: preRollFrames, pressPosition: pressPosition,
            allowance: allowance, driveOnly: driveOnly, deviceOnly: deviceOnly, wanted: wanted, alreadyThere: alreadyThere)
    }

    private func makeSession(
        _ plan: TakePlan, device: any AudioIODevice, capture: Capture, drive: DriveAccess?, preparedDrive: TakeSession.PreparedDrive?
    ) throws -> TakeSession {
        try TakeSession(
            show: plan.show, folders: plan.takeFolders, drive: plan.takeFolders[.drive] != nil ? drive : nil, metadata: plan.metadata,
            stems: plan.specs, info: plan.info, capture: capture, preRollFrames: plan.preRollFrames, makeStem: makeStem, freeSpace: freeSpace,
            driveOnly: plan.driveOnly, deviceOnly: plan.deviceOnly, preparedDrive: preparedDrive,
            pressPosition: plan.pressPosition)
    }

    /// An error as the operator or a bug report can read it: its description, with the system error's domain and code
    /// when it has them ("NSCocoaErrorDomain 513").
    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        let description = error.localizedDescription
        return nsError.domain.isEmpty || nsError.domain == "Foundation._GenericObjCError"
            ? description : "\(description) (\(nsError.domain) \(nsError.code))"
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
        } else if isFinishing {
            gainChangesWhileFinishing.append(change)
        } else {
            // Not to a Copy the last Stop gave up on: it may be hung (#673).
            currentShow?.logGainChange(change, skipping: suspectDrive)
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
        await waitWhileFinishing()
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
        await checkDestinations(awaitingDrive: true)
    }

    /// `awaitingDrive` false is the one-second loop's: a Drive that joins is started and left to finish, so a join that
    /// takes seconds on a slow stick (or hangs on a dead one) doesn't stop the checks that keep a Take safe, such as the
    /// low-space one (#814). A caller that asks for the Drive, like Check Drive, waits for it.
    func checkDestinations(awaitingDrive: Bool) async {
        guard isRecording, let session else { return }
        // A Copy's free space is a read of its volume, and a stick busy with a Take can take hundreds of milliseconds to
        // answer it: read them all on their own thread, once a second, and not on the main actor (#814).
        let reading: Task<[URL: Int64], Never>
        if let running = freeSpaceRead {
            reading = running
        } else {
            let folders = session.spaceFolders, readFree = freeSpace
            reading = Task { await runOffPool { Dictionary(folders.map { ($0, readFree($0)) }, uniquingKeysWith: { first, _ in first }) } }
            freeSpaceRead = reading
        }
        let readings = await reading.value
        if freeSpaceRead == reading { freeSpaceRead = nil }
        // The Take may have ended, or another one begun, while that read was under way.
        guard isRecording, self.session === session else { return }
        // The Drive joins below, off the main actor; the check itself never reaches for it.
        switch session.checkDestinations(drive: { nil }, freeSpace: { readings[$0] ?? .max }) {
        case .carryOn:
            // A Drive that appears or comes back joins with its Stems made on their own thread, not here (#814); a Take
            // the tier or the settings kept off the Drive never asks for it.
            if takeMayUseDrive, session.wantsDrive, driveStartJobsRunning == 0 {
                if awaitingDrive {
                    await joinDrive(in: session)
                    // The Take may have ended while the Stems were being made.
                    guard isRecording, self.session === session else { return }
                } else {
                    Task { [weak self] in await self?.joinDrive(in: session) }
                }
            }
            refreshFromSession(session)
        case .outOfSpace:
            try? await stopTake(because: .outOfSpace)
        }
    }

    /// The Drive joins (or rejoins) the running Take: its file work runs off the main actor (#814).
    private func joinDrive(in session: TakeSession) async {
        guard await session.attachDriveOffMain(drive: driveFolder) else { return }
        // The Take may have ended meanwhile; a Drive that joined after the snapshot never does (see `finishInput`).
        guard isRecording, self.session === session else { return }
        refreshFromSession(session)
    }

    /// What the screen reads of the running Take, brought up to date after a check or a Drive join.
    private func refreshFromSession(_ session: TakeSession) {
        // The Drive joined: "wasn't available at the press" is no longer true, and would be wrong if it dropped later.
        if driveNotice != nil, session.takeCopies[.drive] != .missing { driveNotice = nil }
        currentShow = session.show
        currentShow?.keepChannelNames(channelNames)
        dropoutCount = session.dropoutCount
        refreshMarkers(from: session.metadata)
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

    /// Three steps (#652): `beginStop` and `publishStop` run on the main actor. With the rule on (`asyncStopAvailable`, asked at each Stop) the finish
    /// between them runs on its own thread (it blocks on the writers, so never a pool thread) and the main actor is free
    /// meanwhile; otherwise it is inline. `isFinishing` is true from the start of the first to the end of the last. The
    /// await is not a cancellation point, so canceling the caller skips neither the finish nor the publish.
    func stopTake(because reason: TakeEnd.Reason) async throws {
        // Already stopping: this Stop returns once that one is published, so a quit or an Arm after it is safe.
        guard let stopping = beginStop(because: reason) else { return await waitWhileFinishing() }
        var input = stopping.input
        // Only the off-main finish waits on a slow Drive: the inline one holds the main thread, so it keeps the deadline.
        let offMain = asyncStopAvailable
        input.progressBased = offMain
        if offMain {
            let progress = FinishProgress()
            finishProgress = progress
            input.progress = progress
        }
        let finished = offMain ? await runOffPool { [input] in TakeSession.finish(input) } : TakeSession.finish(input)
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
        /// The names as they were at Stop: names typed afterwards are for the next Take.
        var naming: ChannelNaming
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
        // The Take ends here, not when the finish thread gets to it.
        capture?.stopCapturing()
        // The last window, which the screen hasn't read yet, is still part of the Take.
        session.accumulate(capture?.meters.takeLevels() ?? [])
        let namingAtStop = naming
        _ = naming.takeEnded(allowance: lastAllowance, onFiles: [:])
        var input = session.finishInput()
        // The Show report and Reaper project are rewritten in the finish too, once the Takes' files are final: the Takes are safe
        // either way, and a Repair that finishes later rewrites them again. Not for a Copy Stop gave up on (#673).
        let allowance = lastAllowance, writeReports = reportWriter
        let reports: @Sendable (Show, Set<DestinationKind>) -> Void = { show, skipped in
            let copies = show.copies
            for kind in DestinationKind.allCases where !skipped.contains(kind) {
                if let copy = copies[kind] { writeReports(copy, allowance?.showReport ?? true, allowance?.reaperExport ?? true) }
            }
        }
        input.showEnd = TakeSession.ShowEnd(show: session.show, names: channelNames, date: now(), write: finishShowFiles, reports: reports)
        return Stopping(session: session, input: input, reason: reason, naming: namingAtStop)
    }

    private func publishStop(_ stopping: Stopping, _ finished: TakeSession.Finished) {
        defer {
            isFinishing = false
            finishProgress = nil
            let waiting = finishWaiters
            finishWaiters = []
            for waiter in waiting { waiter.resume() }
        }
        let session = stopping.session, reason = stopping.reason
        session.adopt(finished)
        lastTakeWasDriveOnly = session.driveOnly
        lastTakeWasDeviceOnly = session.deviceOnly
        lastTakeSignal = finished.signal
        dropoutCount = finished.metadata.dropoutCount
        refreshMarkers(from: finished.metadata)
        lastTakeEnd = TakeEnd(take: finished.metadata.take, reason: reason)
        lastTake = LastTake(
            showName: session.show.name, takeNumber: finished.metadata.take, deviceFolder: finished.folders[.device],
            hadDrive: finished.folders[.drive] != nil)
        lastTakeGeneration += 1
        // The finish already wrote the Show's end-of-Take state into Show.json and rewrote its report and project, off the
        // main thread when Stop is async. A name typed while it ran is newer than what it wrote: only then is Show.json written again.
        currentShow = finished.show ?? session.show
        if currentShow?.channelNames != channelNames { currentShow?.setChannelNames(channelNames, skipping: finished.abandoned) }
        if finished.abandoned.contains(.drive) { abandonedThisLaunch[session.show.name, default: []].insert(finished.metadata.take) }
        if let writer = finished.abandonedDriveWriter {
            abandonedDriveWriters[session.show.name, default: [:]][finished.metadata.take] = WeakWriter(writer: writer)
        }
        suspectCopies = finished.abandoned
        for change in gainChangesWhileFinishing { currentShow?.logGainChange(change, skipping: finished.abandoned) }
        gainChangesWhileFinishing = []
        repair.enqueue(finished.metadata, folders: finished.folders, holding: finished.access, abandoned: finished.abandoned)
        nameChannels(of: finished.metadata, naming: stopping.naming)
        onTakeEnded(TakeEnd(take: finished.metadata.take, reason: reason))
        // A Drive connected during the Take, or a Take left on the Device by it, moves once it is repaired and named.
        driveMayHaveConnected()
    }

    /// Puts the names on the Take's files in each Copy's folder: renames the Stems and rewrites Take.json (and the report and
    /// project). It runs off the main thread (#652). Tests replace it.
    @ObservationIgnored var renameChannels: @Sendable (_ names: [Int: String], _ late: Set<Int>, _ copies: [DestinationKind: URL], _ allowsProExtras: Bool) -> Void = {
        _ = ChannelRenamer.rename(names: $0, lateChannels: $1, in: $2, allowsProExtras: $3)
    }

    /// Puts the names typed during the Take on its files. Waits for Repair first, which works on the Stems
    /// by their file names.
    private func nameChannels(of metadata: TakeMetadata, naming atStop: ChannelNaming) {
        var atStop = atStop
        let onFiles = Dictionary(metadata.usbChannels.map { ($0.usbChannel, $0.name) }) { first, _ in first }
        let (names, late) = atStop.takeEnded(allowance: lastAllowance, onFiles: onFiles)
        guard !names.isEmpty, let take = lastTake else { return }
        let allowsProExtras = lastAllowance?.showReport ?? true
        let previous = namingTask
        namingTask = Task { @MainActor in
            await previous?.value
            await repair.wait()
            await waitWhileMoving()
            // Counted while its file work runs off the main actor, so a move waits for it and a delete is refused (#652).
            // Nothing suspends between the last wait and this, so no move starts in the gap.
            editsInProgress += 1
            defer { endEdit() }
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
            // File work on a Drive that may be slow: not on the main thread (#652). The names are the Take's own, so a later
            // Take's names can't reach these files.
            let rename = renameChannels, folders = copies
            await runOffPool { rename(names, late, folders, allowsProExtras) }
        }
    }

    /// Rewrites the Show report and Reaper project, when the last Take's allowance includes them (Pro or Trial). Never
    /// during a Take: a Repair that finishes mid-Take leaves them for its end (#320). A Copy Stop gave up on is skipped.
    func regenerateReports(skipping skipped: Set<DestinationKind> = []) {
        guard let job = reportJob(skipping: skipped, whileFinishing: true) else { return }
        for copy in job.copies { reportWriter(copy, job.report, job.projects) }
    }

    /// The same rewrite for a Repair that has finished, off the main thread and one at a time: a Drive that hangs (one Stop
    /// didn't know about) can't block the UI, and two rewrites never overlap (#588).
    func regenerateReportsOffMain(skipping skipped: Set<DestinationKind>) {
        guard let job = reportJob(skipping: skipped, whileFinishing: false) else { return }
        let previous = reportTask, write = reportWriter, limit = reportWaitLimit
        reportTask = Task {
            // One that hangs on a Drive holds the next only for a while: they all rewrite the same files.
            await waitBounded(previous, for: limit)
            await runOffPool { for copy in job.copies { write(copy, job.report, job.projects) } }
        }
    }

    /// What a rewrite writes and where: not during a Take, and not on a Copy `skipped` or the last Take's abandoned Copy
    /// (`suspectCopies`) names, since its Destination may be hung (#673).
    private func reportJob(skipping skipped: Set<DestinationKind>, whileFinishing: Bool) -> (copies: [Show], report: Bool, projects: Bool)? {
        // A Repair's rewrite is not made while a Take is being saved either: Stop rewrites them when it is published (that
        // call is `whileFinishing`), and the Drive it is waiting on may be the one that hangs.
        guard !isRecording, whileFinishing || !isFinishing else { return nil }
        let allowance = lastAllowance
        let shows = currentShow?.copies ?? [:]
        let skip = skipped.union(suspectCopies)
        let copies = DestinationKind.allCases.filter { !skip.contains($0) }.compactMap { shows[$0] }
        return (copies, allowance?.showReport ?? true, allowance?.reaperExport ?? true)
    }

    /// Writes the Show's end-of-Take state into every Copy's `Show.json` but those skipped, and returns the Show as it is then:
    /// the typed names and when the Take ended. It runs inside the finish, off the main thread when Stop is asynchronous (#652).
    /// Tests replace it.
    @ObservationIgnored var finishShowFiles: @Sendable (Show, _ names: [Int: String], _ at: Date, _ skipping: Set<DestinationKind>) -> Show = Recorder.writeShowEnd
    nonisolated static let writeShowEnd: @Sendable (Show, [Int: String], Date, Set<DestinationKind>) -> Show = { show, names, date, skipped in
        var show = show
        show.setChannelNames(names, skipping: skipped)
        show.noteTakeEnded(at: date, skipping: skipped)
        return show
    }

    /// Writes one Copy's report and Reaper project. Tests replace it.
    @ObservationIgnored var reportWriter: @Sendable (Show, _ report: Bool, _ projects: Bool) -> Void = Recorder.writeReports
    nonisolated static let writeReports: @Sendable (Show, Bool, Bool) -> Void = { copy, report, projects in
        if report { try? ShowReport.write(showFolder: copy.folder) }
        if projects { try? copy.writeProjects() }
    }
    @ObservationIgnored private var reportTask: Task<Void, Never>?
    /// How long a report rewrite, or `waitForRepair`, waits for an earlier rewrite before going on without it.
    @ObservationIgnored var reportWaitLimit: Duration = .seconds(10)
    /// The Copies the last Take's Stop gave up on: their Destination may be hung, so nothing writes them from the main thread.
    @ObservationIgnored var suspectCopies: Set<DestinationKind> = []
    /// The Drive, when the last Stop gave up on it: what the main thread's Show.json writes leave out. Never the Device: its
    /// `Show.json` is the file a relaunch reads to tell whether the Show is open.
    private var suspectDrive: Set<DestinationKind> { suspectCopies.intersection([.drive]) }

    /// Drive only (#630): moves every stand-in the Device keeps, and every Drive only Take it holds whole, in any Show,
    /// to its Take on the Drive, and removes the Device's Take once the Drive is checked to hold it. Does nothing during a Take or with no Drive; a Take
    /// started meanwhile stops it at the next Stem, and one asked for while another runs does nothing. A move a crash cut
    /// off is finished or undone first (`MoveRecovery`); with no Drive, its set-aside Take stays hidden until the next
    /// move with one. Returns what came of each Take it took up.
    /// - Parameter shouldStop: replaces `moveStop` in tests.
    @discardableResult
    func moveDriveOnlyTakes(shouldStop: (@Sendable () -> Bool)? = nil) async -> [StandInMove.Result] {
        guard !isRecording, !isStarting, !isFinishing, !isMoving, let access = driveFolder() else { return [] }
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
        let running = runningDriveWriters
        // Writers that stopped, or are gone, are let go.
        abandonedDriveWriters = abandonedDriveWriters.compactMapValues { takes in
            let left = takes.filter { $0.value.writer?.isFinished == false }
            return left.isEmpty ? nil : left
        }
        let all = await runOffPool { TakeMover.find(deviceFolder: device, driveFolder: drive) }.map { movable in
            guard running[movable.show]?.contains(movable.take) == true else { return movable }
            var waiting = movable
            waiting.kind = .skipped(.driveStillWriting)
            return waiting
        }
        if !running.isEmpty { moveOnceWritersStop() }
        driveOnlySkips = all.filter { if case .skipped = $0.kind { true } else { false } }
        let found = all.filter { $0.kind == .standIn || $0.kind == .deviceOnly || $0.kind == .redundant }
        // With the Device chosen the operator is asked first, once per Drive connection (#805). Device Copies the Drive
        // already holds go without asking, and aren't counted.
        let waiting = found.filter { $0.kind != .redundant }.count
        let offer = moveConsent == .approved ? .move : DriveOnlyMoveOffer.decide(
            // The App sets recordTo from the stored choice only where Record to is offered.
            storedChoice: recordTo, isOffered: true, isRecording: isRecording, waitingTakes: waiting,
            askedThisConnection: moveConsent == .asked)
        switch offer {
        case .ask(let count):
            moveOffer = count
            moveConsent = .asked
        case .move:
            moveOffer = nil
        case .leave:
            // An unanswered question stays while its Takes wait, and counts the ones still waiting.
            if moveOffer != nil { moveOffer = waiting > 0 ? waiting : nil }
        }
        let moving = offer == .move ? found : found.filter { $0.kind == .redundant }
        // While a question waits, a move with nothing to say keeps what the one before it said.
        let keepsReport = moveOffer != nil
        guard !moving.isEmpty, !isRecording else {
            access.end()
            return finishMoveRun(from: first, keepingEarlier: keepsReport)
        }
        foundTakesToMove = true
        repair.move(moving, holding: access, shouldStop: shouldStop) { [weak self] movable, outcome in
            let driveTake = drive.appending(path: movable.show).appending(path: movable.deviceFolder.lastPathComponent)
            self?.driveOnlyTakeMoved(movable, outcome, driveTake: driveTake, generation: generation)
        }
        await repair.wait()
        return finishMoveRun(from: first, keepingEarlier: keepsReport)
    }

    /// Once every Drive writer a move left a Take for has stopped, moves again (#916). One wait at a time; it looks once a
    /// second, since such a writer finishes at most the one write it is stuck in.
    private func moveOnceWritersStop() {
        guard writerWait == nil else { return }
        writerWait = Task { [weak self] in
            // The Recorder isn't held through the sleeps.
            while self?.runningDriveWriters.isEmpty == false {
                try? await Task.sleep(for: .seconds(1))
            }
            self?.writerWait = nil
            self?.driveMayHaveConnected()
        }
    }

    /// What this move did, from `first` in `driveOnlyMoves`; kept for `moveReport` when it found something to say.
    /// - Parameter keepingEarlier: nothing to say leaves what an earlier move said (#805).
    private func finishMoveRun(from first: Int, keepingEarlier: Bool = false) -> [StandInMove.Result] {
        let moves = Array(driveOnlyMoves[first...])
        let hasSomethingToSay = moves.contains(where: { $0.outcome != .gone }) || !driveOnlySkips.isEmpty
        if keepingEarlier, !hasSomethingToSay { return moves }
        // Nothing to say clears what an earlier move said.
        lastMoveRun = hasSomethingToSay ? (moves, driveOnlySkips) : ([], [])
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

    /// Drive only (#656): whether a kept Take may be deleted from the Device by hand: the Drive holds everything the Device holds
    /// of it. The facts for the confirmation are in the answer. Deletes nothing. Not during a Take or a save, and not while a Device
    /// Copy Stop gave up on may still be written.
    public func checkRelease(show: String, take: Int) async -> DeviceTakeRelease.Check {
        if let refusal = releaseRefusal(show: show, take: take) { return .no([refusal]) }
        await waitWhileMoving()
        // A Repair still filling the Drive's Take would change what the check compares.
        await repair.wait()
        if let refusal = releaseRefusal(show: show, take: take) { return .no([refusal]) }
        guard let access = driveFolder() else { return .no(["The Drive isn't connected."]) }
        defer { access.end() }
        let name = TakeMetadata.name(take: take)
        let deviceTake = deviceFolder.appending(path: show).appending(path: name)
        let driveTake = access.folder.appending(path: show).appending(path: name)
        let shouldStop = moveStop.latch()
        return await runOffPool { DeviceTakeRelease.check(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop) }
    }

    /// Drive only (#656): deletes a kept Take from the Device, at the operator's choice, once the Drive holds everything the
    /// Device holds of it (`DeviceTakeRelease`). Never during a Take or a save; a Take started meanwhile stops it.
    @discardableResult
    public func releaseFromDevice(show: String, take: Int) async -> DeviceTakeRelease.Outcome {
        if let refusal = releaseRefusal(show: show, take: take) { return .kept([refusal]) }
        // A Repair still filling the Drive's Take would change what is compared; a move or delete running goes first.
        repeat {
            await waitWhileMoving()
            await repair.wait()
        } while isMoving
        // On the main actor, what is checked here holds until the delete below sets `isMoving`.
        if let refusal = releaseRefusal(show: show, take: take) { return .kept([refusal]) }
        guard let access = driveFolder() else { return .kept(["The Drive isn't connected."]) }
        isMoving = true
        defer {
            isMoving = false
            let waiting = moveWaiters
            moveWaiters = []
            for waiter in waiting { waiter.resume() }
        }
        // A Show detail edit already running finishes first, as for a move.
        while editsInProgress > 0 {
            await withCheckedContinuation { editWaiters.append($0) }
        }
        if let refusal = releaseRefusal(show: show, take: take) {
            access.end()
            return .kept([refusal])
        }
        let name = TakeMetadata.name(take: take)
        let deviceTake = deviceFolder.appending(path: show).appending(path: name)
        let driveTake = access.folder.appending(path: show).appending(path: name)
        let shouldStop = moveStop.latch()
        let outcome = await runOffPool { DeviceTakeRelease.run(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop) }
        access.end()
        guard outcome == .released else { return outcome }
        // It is no longer kept on this device: off the moves list, and the last Take reads as moved if it is that one.
        lastMoveRun.moves.removeAll { $0.show == show && $0.take == take }
        lastMoveRun.skips.removeAll { $0.show == show && $0.take == take }
        if show == currentShow?.name { regenerateReports() }
        if !isRecording, lastTake?.showName == show, lastTake?.takeNumber == take {
            lastTakeStandInMoved = true
            lastTakeStandInKept = false
            lastTake?.deviceFolder = nil
            lastTake?.hadDrive = true
            lastTakeOutcomes[.drive] = Self.readTake(at: driveTake)?.outcome(ofCopy: .drive)
        }
        return outcome
    }

    /// Why a kept Take can't be deleted from the Device now, if so.
    private func releaseRefusal(show: String, take: Int) -> String? {
        // `show` comes from the App and goes into a path: it must be one plain folder of the Device's, never a way out of it.
        let plain = !show.isEmpty && show != "." && show != ".." && !show.hasPrefix(".") && !show.contains("/") && !show.contains("\0")
        guard plain, take > 0, ShowDeleter.isRealFolder(deviceFolder.appending(path: show)) else {
            return "That Take isn't in a Show on the Device."
        }
        if isRecording { return "A Take is running." }
        if isFinishing { return "A Take is being saved." }
        if suspectCopies.contains(.device) { return "The Device may still be writing the last Take; try again after the app is restarted." }
        return nil
    }

    /// Drive only (#630): moves the Drive only Takes of every Show to the Drive, when it is there, outside a Take and once
    /// Repair and the naming of the last Take are done. The App calls it when the Drive folder becomes available; the
    /// Recorder after each Take and when moving is turned on. Calls while one runs wait for it, then find nothing left
    /// to do or what has changed. What came of each Take is in `driveOnlyMoves`.
    public func driveMayHaveConnected() {
        // One waiting trigger takes in any more asked for before it starts.
        // Not while a Device Copy Stop gave up on may still have its writer alive: the mover could move and remove it (#838).
        guard movesDriveOnlyTakes, !isRecording, !triggerWaiting, !suspectCopies.contains(.device) else { return }
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

    /// Record to (#805): how many Drive only Takes wait for the operator's answer to the move question; nil when none
    /// is asked. The App shows it outside a Take only.
    public private(set) var moveOffer: Int?
    /// Record to (#805): what the operator said about moving Takes since the Drive connected.
    enum MoveConsent { case notAsked, asked, approved }
    /// Set for the whole Drive connection: a Move answer moves what a stopped move left, after Stop, without asking (#805).
    @ObservationIgnored private var moveConsent = MoveConsent.notAsked

    /// Record to (#805): the operator's answer to `moveOffer`. Move moves the Takes now and for the rest of the Drive
    /// connection; Not now leaves them until the next Drive connection.
    public func answerMoveOffer(move: Bool) {
        moveOffer = nil
        guard move else { return }
        moveConsent = .approved
        driveMayHaveConnected()
    }

    /// Record to (#805): the App calls it when the Drive folder goes away, so the Drive's next connection asks again.
    public func driveWentAway() {
        moveConsent = .notAsked
        moveOffer = nil
    }

    /// Whether a trigger is waiting to start its move (#630).
    @ObservationIgnored var triggerWaiting = false
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
        await waitWhileFinishing()
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
        return await runOffPool {
            defer { access?.end() }
            hook()
            return ShowDetail.renameMarker(at: index, to: name, inTake: take, ofShow: show, device: device, drive: access?.folder, allowsProExtras: allowsProExtras)
        }
    }

    /// Show detail renames whose file work is running (#630).
    /// An edit's file work is done: a move waiting for it may start.
    private func endEdit() {
        editsInProgress -= 1
        if editsInProgress == 0 {
            let waiting = editWaiters
            editWaiters = []
            for waiter in waiting { waiter.resume() }
        }
    }

    @ObservationIgnored private var editsInProgress = 0
    /// Moves waiting for those to end (#630).
    @ObservationIgnored private var editWaiters: [CheckedContinuation<Void, Never>] = []

    /// Run before a Show detail rename's file work, off the main actor; tests hold it there.
    @ObservationIgnored var beforeDetachedRename: @Sendable () -> Void = {}

    /// Waits for the move a trigger started, if any (#630).
    func waitForMoves() async {
        await moveTrigger?.value
    }

    /// Returns once the Take being written is published (at once when none is).
    func waitWhileFinishing() async {
        if isFinishing { await withCheckedContinuation { finishWaiters.append($0) } }
    }

    /// Waits for Repair of the last Take to finish.
    public func waitForRepair() async {
        // A Take that is still being written has nothing to repair yet.
        await waitWhileFinishing()
        await repair.wait()
        await waitBounded(reportTask, for: reportWaitLimit)
        await namingTask?.value
    }
}

public enum RecorderError: Error, Equatable, LocalizedError {
    case notArmed
    /// A Show can't be started or ended while a Take is running.
    case takeRunning
    /// The last Take's Copies are still being written (#652).
    case finishing
    /// Stop came while the Take was starting (#914).
    case startCanceled

    public var errorDescription: String? {
        switch self {
        case .finishing: "The last Take is still being saved."
        default: nil
        }
    }
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
