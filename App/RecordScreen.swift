import AudioIO
import Recording
import CoreAudioIO
import Destinations
import MixerLink
import SwiftUI
#if os(iOS)
import AVFAudio
#endif

/// The record screen. While it is showing, the recorder is Armed on the chosen device.
///
/// It shows the Take, not its setup: meters, transport, Markers, one status strip and one alert.
/// Input, Drive and Mixer Link are set in Settings.
struct RecordScreen: View {
    @Bindable var model: RecordScreenModel
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var showingSettings = false
    @State private var showingMarkers = false
    @State private var showingNewShow = false
    @State private var namingChannel: Int?
    @State private var channelName = ""
    @State private var showingShowList = CommandLine.arguments.contains("-showList")
    @State private var settingsSection: SettingsSection?
    @State private var confirmingStop = false

    /// Landscape iPhone is short, not narrow: a Pro Max in landscape is wide but still short.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        // One root for both layouts. The task, idle timer, sheet and dialog below hang on it, so rotating
        // swaps the arrangement but never goes away (which would disarm the recorder).
        ZStack {
            if isLandscape { landscape } else { portrait }
        }
        // The loop is the model's, started once; the screen only says when it appears and goes away.
        .task { model.start() }
        .onAppear { model.screenAppeared() }
        .onDisappear { model.screenDisappeared() }
        .sheet(isPresented: $showingMarkers) {
            NavigationStack {
                MarkerListView(model: model)
                    .navigationTitle("Markers")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showingMarkers = false } }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
            #endif
        }
        .alert(
            "Name channel \(namingChannel ?? 0)",
            isPresented: Binding(get: { namingChannel != nil }, set: { if !$0 { namingChannel = nil } })
        ) {
            TextField("Name", text: $channelName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let namingChannel { model.recorder.setChannelName(channelName, forChannel: namingChannel) } }
        } message: {
            Text("The files take the name when the Take ends.")
        }
        .sheet(isPresented: $showingNewShow) { NewShowSheet(model: model) }
        .sheet(isPresented: $showingShowList) { ShowListView(model: model) }
        #if os(macOS)
        .background(WindowCloseGuard(model: model))
        #endif
        // Read Sources for the USB Channels the newly Armed device actually sends.
        .task(id: model.recorder.usbChannelCount) {
            await model.mixerLink.refreshSources(usbChannelCount: model.recorder.usbChannelCount)
        }
        // Locking the screen or leaving the app never ends a Take; becoming active retries input
        // that an interruption left stopped.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.screenBecameActive()
                model.handle(.becameActive)
                model.drive.refresh()
            case .background:
                model.screenBecameIdle()
                model.handle(.movedToBackground)
            default: break
            }
        }
        #if os(iOS)
        // Keep the screen awake while the record screen is showing.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // A sheet, so opening Settings never takes the record screen (and the Armed recorder) away.
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(model: model, scrollTo: settingsSection)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } }
                    }
            }
            .presentationDetents([.large])
        }
        #endif
        .confirmationDialog("Stop recording?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Recording", role: .destructive) { model.stop() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("This ends \(model.takeTitle).")
        }
    }

    /// Outside a Take a chip opens its part of Settings; during one it only retries (Drive, Mixer).
    private func chipTapped(_ kind: StatusChip.Kind) {
        if model.recorder.isRecording {
            model.retryDuringTake(kind)
        } else {
            showSettings(kind.settingsSection)
        }
    }

    private func showSettings(_ section: SettingsSection?) {
        #if os(macOS)
        openSettings()
        #else
        settingsSection = section
        showingSettings = true
        #endif
    }

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            StatusStrip(chips: model.chips, extras: model.extraChips, tap: chipTapped)
            AlertSlot(queue: model.alerts, perform: model.perform)
            MeterGrid(meters: model.meters, clipped: model.recorder.clippedChannels, clearClip: { model.recorder.clearClip(channel: $0) }, sources: model.mixerLink.sources, typedNames: model.recorder.channelNames, nameChannel: nameChannel)
            transport
        }
        .padding()
    }

    /// Header and status strip share one 44 pt row, the meters take the full height below it, and the
    /// transport is a column at the trailing edge (or the leading edge, for left-handed use).
    private var landscape: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                headerSummary(compact: true)
                    .frame(maxWidth: 190, alignment: .leading)
                StatusStrip(chips: model.chips, extras: model.extraChips, compact: true, tap: chipTapped)
                markersButton
                gearButton
            }
            HStack(alignment: .top, spacing: 12) {
                if model.transportLeading { transportColumn }
                MeterGrid(meters: model.meters, clipped: model.recorder.clippedChannels, clearClip: { model.recorder.clearClip(channel: $0) }, sources: model.mixerLink.sources, typedNames: model.recorder.channelNames, nameChannel: nameChannel, compact: true)
                    // Urgent alerts sit over the top of the meters, which aren't tappable and don't move,
                    // so the chips and the gear stay reachable (the Drive's Reconnect is one of them).
                    .overlay(alignment: .top) {
                        let urgent = AlertQueue(model.alerts.ordered.filter { $0.tone == .critical || $0.tone == .warning })
                        AlertSlot(queue: urgent, perform: model.perform, slotHeight: 44)
                            .allowsHitTesting(urgent.top != nil)
                    }
                if !model.transportLeading { transportColumn }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func recordButton(size: CGFloat) -> some View {
        Button {
            if model.recorder.isRecording {
                confirmingStop = true
            } else {
                model.record()
            }
        } label: {
            RecordButtonLabel(isRecording: model.recorder.isRecording, size: size)
        }
        .buttonStyle(.plain)
        .disabled(!model.recorder.isArmed)
        .accessibilityLabel(model.recorder.isRecording ? "Stop recording" : "Record")
        .keyboardShortcut("r", modifiers: .command)
    }

    /// Always in place, dimmed when no Take is running, so Record never shifts under the thumb.
    private func markerButton(size: CGFloat) -> some View {
        Button {
            model.recorder.addMarker()
        } label: {
            MarkerButtonLabel(count: model.recorder.takeMarkers.count, size: size)
        }
        .buttonStyle(.plain)
        .disabled(!model.recorder.isRecording)
        .opacity(model.recorder.isRecording ? 1 : 0.3)
        .accessibilityLabel("Add Marker")
        .keyboardShortcut("m", modifiers: .command)
        .sensoryFeedback(.success, trigger: model.recorder.takeMarkers.count) { old, new in new > old }
    }

    private func nameChannel(_ number: Int) {
        channelName = model.recorder.channelNames[number] ?? (model.mixerLink.sources.indices.contains(number - 1) && model.mixerLink.sources[number - 1].hasMixerName ? model.mixerLink.sources[number - 1].name : "")
        namingChannel = number
    }

    private var transport: some View {
        VStack(spacing: 12) {
            elapsed(font: .system(size: 44, weight: .semibold))
            Button { showingNewShow = true } label: {
                Text(model.showSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.recorder.isRecording)
            .accessibilityHint("Starts a new Show")
            Button("Shows") { showingShowList = true }
                .font(.caption)
                .disabled(model.recorder.isRecording)
            // Top-aligned: Marker is taller (its count sits below), so centring would drop Record.
            HStack(alignment: .top, spacing: 28) {
                recordButton(size: 88)
                markerButton(size: 88)
            }
            // The line is always there, so a placed Marker doesn't push anything.
            Text(markerPlacedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .id(model.recorder.takeMarkers.count)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: model.recorder.takeMarkers.count)
    }

    private var markerPlacedText: String {
        if let last = model.recorder.takeMarkers.last, model.recorder.isRecording { return "\(last.name) placed" }
        return " "
    }

    /// Landscape transport: the Show and Take (with how long the Take has run) over Marker, then Record.
    /// Marker and Stop are kept well apart, since Marker is pressed often and Stop ends the Take.
    private var transportColumn: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Button { showingNewShow = true } label: {
                    Text(model.recorder.currentShow?.name ?? "No Show yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.plain)
                .disabled(model.recorder.isRecording)
                .accessibilityHint("Starts a new Show")
                Button("Shows") { showingShowList = true }
                    .font(.caption2)
                    .disabled(model.recorder.isRecording)
                Text(model.takeTitle)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                elapsed(font: .title3)
                if let note = nonUrgentAlert {
                    Button {
                        if let action = note.action { model.perform(action) }
                    } label: {
                        Text(note.action == .dismissHint ? note.text + " Tap to dismiss." : note.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Only this spacer flexes, so Marker and Record stay put when the note above comes and goes.
            Spacer(minLength: 8)
            markerButton(size: 64)
            Color.clear.frame(height: 24)
            recordButton(size: 64)
        }
        .frame(width: 128)
    }

    /// How long the running Take has gone, counting up each second. Blank (but the same height) when no
    /// Take is running, so nothing moves when it appears.
    @ViewBuilder private func elapsed(font: Font) -> some View {
        if let started = model.takeStartedAt, model.recorder.isRecording {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let text = ElapsedTime.format(seconds: Int(context.date.timeIntervalSince(started)))
                Text(text)
                    .font(font.monospacedDigit())
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(text)
                    // VoiceOver reads it when asked; it doesn't announce every second.
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } else {
            Text(" ").font(font)
        }
    }

    /// The most urgent alert that isn't a warning or failure (a Copy result, the first-run hint), for the column.
    private var nonUrgentAlert: ScreenAlert? {
        model.alerts.ordered.first { $0.tone == .ok || $0.tone == .info }
    }

    /// Opens the Marker list. A sheet, so it never takes the record screen (and a running Take) away.
    private var markersButton: some View {
        Button { showingMarkers = true } label: {
            Image(systemName: "list.bullet")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Markers")
        #if os(macOS)
        .help("Markers")
        #endif
    }

    private var gearButton: some View {
        Button { showSettings(nil) } label: {
            Image(systemName: "gearshape")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        #if os(macOS)
        .help("Settings (⌘,)")
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            headerSummary(compact: false)
            Spacer(minLength: 8)
            markersButton
            gearButton
        }
    }

    private func headerSummary(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: compact ? 8 : 12) {
            Circle()
                .fill(model.recorder.isRecording ? Color.red : model.recorder.isArmed ? Color.green : Color.secondary)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                // The word carries the state; the dot's color is only a second cue.
                Text(model.recorder.isRecording ? "Recording" : model.recorder.isArmed ? "Armed" : "Not armed")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                Text(compact ? model.compactInputSummary : model.inputSummary)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

extension StatusChip.Kind {
    var settingsSection: SettingsSection {
        switch self {
        case .device: .recording
        case .drive: .storage
        case .mixer: .mixer
        }
    }
}

/// One choosable audio device.
struct DeviceChoice: Identifiable {
    /// What the hot-plug decision sees. `info.id` is stable across unplug and replug.
    let info: InputDeviceInfo
    /// The label shown in the picker.
    let name: String
    let make: () throws -> any AudioIODevice

    var id: String { info.id }
}

@MainActor
@Observable
final class RecordScreenModel {
    /// Each Take goes to the Device and, when the Drive folder is connected at record time, the Drive.
    let recorder: Recorder
    /// The Drive folder and Device free space, kept current here so the status strip, Settings and the
    /// recorder share one state whether or not Settings is open.
    let drive: DriveFolderModel
    let mixerLink = MixerLinkController()
    /// The Mixer's address, remembered between launches.
    var mixerAddress: String
    /// Whether the system denied microphone access (shows a button that opens the system settings).
    private(set) var micDenied = false
    /// When the running Take started, for the elapsed time.
    private(set) var takeStartedAt: Date?
    /// Landscape: the transport column on the leading edge instead of the trailing one (left-handed).
    var transportLeading: Bool = UserDefaults.standard.bool(forKey: RecordScreenModel.transportLeadingKey)
    private static let transportLeadingKey = "transportLeading"
    /// The Pre-roll length in seconds (0 is Off), read when record is pressed. See `PreRollSetting`.
    var preRollSeconds: Double = PreRollSetting.load()
    /// Battery and heat, shown as chips on the status strip.
    let power = PowerMonitor()
    private(set) var setupHintDismissed = UserDefaults.standard.bool(forKey: RecordScreenModel.hintKey)
    private static let hintKey = "setupHintDismissed"
    private static let mixerAddressKey = "mixerAddress"
    private(set) var devices: [DeviceChoice] = []
    var selectedDeviceID: String?
    private(set) var meters: [ChannelMeter] = []
    private(set) var armError: String?
    private(set) var recordError: String?
    /// The device as it was when last Armed, to tell a format change from a new device.
    @ObservationIgnored private var armedDevice: InputDeviceInfo?
    /// How each Copy of the running Take is doing, refreshed about once a second.
    private(set) var deviceCopy: CopyStatus = .missing
    private(set) var driveCopy: CopyStatus = .missing
    @ObservationIgnored private var wasRecording = false

    /// A persistent warning while a Take is missing a Copy.
    var destinationWarning: String? {
        guard recorder.isRecording else { return nil }
        switch (deviceCopy, driveCopy) {
        case (.interrupted, .interrupted): return "Both Copies stopped writing."
        case (.interrupted, _): return "This device stopped writing. Recording continues on the Drive."
        case (_, .interrupted): return "The Drive stopped. Recording continues on this device, and the Drive rejoins when it comes back."
        case (_, .missing): return "No Drive. Recording to this device only."
        default: return nil
        }
    }

    /// How each Copy of the last Take stands, shown once recording has stopped.
    var copySummary: (text: String, isProblem: Bool)? {
        if recorder.isRecording { return nil }
        if recorder.isRepairing { return ("Repairing Gaps from the other Copy…", false) }
        let outcomes = recorder.lastTakeOutcomes
        guard !outcomes.isEmpty else { return nil }
        let summary = CopySummary(outcomes: outcomes, dropoutCount: recorder.dropoutCount)
        return (summary.text, summary.isProblem)
    }

    /// Looks for a Drive that has appeared or come back, and refreshes the Copy statuses. Also notices a
    /// Take the recorder ended on its own.
    private func refreshDestinations() {
        if recorder.isRecording { recorder.checkDestinations() }
        deviceCopy = recorder.copyStatus(.device)
        driveCopy = recorder.copyStatus(.drive)
        if wasRecording, !recorder.isRecording, recordError == nil {
            recordError = recorder.endedForLackOfSpace
                ? "Recording stopped because the last Destination was about to fill. Everything recorded was saved."
                : "Recording stopped because no Destination could be written. Everything recorded so far was saved."
        }
        if !recorder.isRecording { takeStartedAt = nil }
        wasRecording = recorder.isRecording
    }

    /// Just the Armed device's name, for the one-line landscape header.
    var compactInputSummary: String {
        recorder.isArmed ? (armedDevice?.name ?? "Input") : "No input"
    }

    /// The Armed device's name and channel count, for the header.
    var inputSummary: String {
        guard recorder.isArmed else { return "Choose an input in Settings" }
        let name = armedDevice?.name ?? "Input"
        return "\(name) · \(usbChannelSummary)"
    }

    /// The status strip: Device and Drive time left, and the Mixer Link.
    var chips: [StatusChip] {
        StatusChip.make(
            usbChannelCount: recorder.usbChannelCount,
            deviceAvailableBytes: drive.deviceAvailableBytes,
            drive: drive.status,
            mixer: mixerLink.status,
            copies: recorder.isRecording ? [.device: deviceCopy, .drive: driveCopy] : [:])
    }

    /// Everything the record screen has to say, most urgent first; it shows one and counts the rest.
    var alerts: AlertQueue {
        var list: [ScreenAlert] = []
        if let error = armError {
            list.append(ScreenAlert(id: "arm", priority: .cannotRecord, tone: .critical, text: error, action: micDenied ? .openSystemSettings : nil))
        }
        if let error = recordError {
            list.append(ScreenAlert(id: "record", priority: .cannotRecord, tone: .critical, text: error))
        }
        if let warning = destinationWarning {
            list.append(ScreenAlert(id: "destination", priority: .destination, tone: deviceCopy == .interrupted && driveCopy == .interrupted ? .critical : .warning, text: warning))
        }
        if let shortfall = usbChannelShortfall {
            list.append(ScreenAlert(id: "shortfall", priority: .input, tone: .warning, text: shortfall.message))
        }
        if let notice = interruptions.notice {
            list.append(ScreenAlert(id: "interruption", priority: .input, tone: .warning, text: notice))
        }
        list += power.status.alerts
        if let summary = copySummary, !recorder.isRecording {
            list.append(ScreenAlert(id: "copies", priority: .copyResult, tone: summary.isProblem ? .warning : .ok, text: summary.text))
        }
        if showSetupHint {
            list.append(ScreenAlert(id: "hint", priority: .hint, tone: .info, text: "Set the input, Drive and Mixer in Settings (the gear).", action: .dismissHint))
        }
        return AlertQueue(list)
    }

    /// A first-run nudge, once: neither a Drive nor a Mixer is set up yet.
    private var showSetupHint: Bool {
        !setupHintDismissed && !recorder.isRecording && drive.status == .notChosen && mixerAddress.isEmpty
    }

    func perform(_ action: ScreenAlert.Action) {
        switch action {
        case .openSystemSettings: openSystemSettings()
        case .dismissHint:
            setupHintDismissed = true
            UserDefaults.standard.set(true, forKey: Self.hintKey)
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
        #endif
    }

    /// During a Take the status strip can only retry: look for the Drive again, or reconnect the Mixer.
    func retryDuringTake(_ kind: StatusChip.Kind) {
        switch kind {
        case .device: break
        case .drive:
            drive.refresh()
            recorder.checkDestinations()
        case .mixer:
            if case .down = mixerLink.status { connectMixer() }
        }
    }

    func connectMixer() {
        saveMixerAddress()
        let address = mixerAddress
        let count = recorder.usbChannelCount
        Task { await mixerLink.connect(to: address, usbChannelCount: count) }
    }

    func saveMixerAddress() {
        UserDefaults.standard.set(mixerAddress, forKey: Self.mixerAddressKey)
    }

    /// What to do about audio interruptions, and the banner they leave (see AudioSessionEvents.swift).
    var interruptions = InterruptionPolicy()

    init() {
        let drive = DriveFolderModel()
        let store = drive.store
        self.drive = drive
        recorder = Recorder(driveFolder: {
            store.beginAccess().map { access in DestinationAccess(folder: access.folder, release: { access.end() }) }
        }, preRollSeconds: PreRollSetting.load())
        mixerAddress = UserDefaults.standard.string(forKey: Self.mixerAddressKey) ?? ""
        devices = Self.availableDevices()
        selectedDeviceID = devices.first?.id
        // `-demoSignal` starts on the 18-channel demo signal, for screenshots and layout checks.
        if CommandLine.arguments.contains("-demoSignal"), devices.contains(where: { $0.id == "demo" }) { selectedDeviceID = "demo" }
    }

    /// "2026-10-06 Show · Take 02", or a hint before the first Take.
    var showSummary: String {
        guard let show = recorder.currentShow else { return "Press record to start a Show" }
        return "\(show.name) · \(takeTitle)"
    }

    var takeTitle: String {
        String(format: "Take %02d", recorder.currentShow?.takeCount ?? 0)
    }

    func record() {
        do {
            // Freeze whatever the Mixer Link knows right now into the Take's Stems.
            try recorder.startTake(sources: mixerLink.sources)
            takeStartedAt = Date()
            recordError = nil
            handle(.takeStarted)
        } catch {
            recordError = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func saveTransportSide() {
        UserDefaults.standard.set(transportLeading, forKey: Self.transportLeadingKey)
    }

    func stop() {
        takeStartedAt = nil
        wasRecording = false  // the operator ended it
        do {
            try recorder.stopTake()
        } catch {
            recordError = "The Take didn't finish cleanly: \(error.localizedDescription)"
        }
    }

    // MARK: - Auto-disarm

    @ObservationIgnored private var idle = IdleDisarm()
    /// Whether the recorder was disarmed for sitting idle, so coming back should Arm it again.
    @ObservationIgnored private var disarmedForIdle = false

    /// The screen locked or the app left the front: start counting idle time.
    func screenBecameIdle() {
        idle.becameIdle(at: Date())
    }

    /// The app is in front again: stop counting, and Arm again if it was disarmed for being idle.
    func screenBecameActive() {
        idle.becameActive()
        if disarmedForIdle {
            disarmedForIdle = false
            armSelectedDevice()
        }
    }

    /// Disarms an unused recorder that has been idle for 30 minutes. Never during a Take.
    private func disarmIfIdle() {
        guard recorder.isArmed, idle.shouldDisarm(at: Date(), isRecording: recorder.isRecording) else { return }
        recorder.disarm()
        armedDevice = nil
        disarmedForIdle = true
    }

    /// Chips after the Destination and Mixer ones: a Dropout count when the Take has lost audio, then battery and heat.
    var extraChips: [PowerStatus.Chip] {
        let dropouts = recorder.dropoutCount
        let chip = dropouts > 0
            ? [PowerStatus.Chip(text: dropouts == 1 ? "1 dropout" : "\(dropouts) dropouts", shortText: "\(dropouts)", symbol: "waveform.badge.exclamationmark", state: .attention)]
            : []
        return chip + power.status.chips
    }

    /// Ends the open Show. Returns what to tell the operator, or nil when it ended.
    func endShow() -> String? {
        do {
            try recorder.endShow()
            return nil
        } catch RecorderError.takeRunning {
            return "A Show can't be ended during a Take."
        } catch {
            return "The Show couldn't be ended: \(error.localizedDescription)"
        }
    }

    /// Starts a new Show. Returns what to tell the operator, or nil when it started.
    func startNewShow(name: String, venue: String) -> String? {
        do {
            try recorder.startNewShow(name: name, venue: venue)
            return nil
        } catch RecorderError.takeRunning {
            return "A Show can't be started during a Take."
        } catch {
            return "The Show couldn't be created: \(error.localizedDescription)"
        }
    }

    /// Renames a Marker in the list, during the Take or after it. Returns what to tell the operator, or nil when
    /// every Copy has the new name.
    func renameMarker(_ entry: MarkerEntry, to name: String) async -> String? {
        guard let index = entry.operatorIndex else { return "Dropout Markers can't be renamed." }
        if recorder.isRecording {
            switch recorder.renameMarker(at: index, to: name) {
            case .renamed: return nil
            case .emptyName: return "A Marker needs a name."
            case .noSuchMarker: return "That Marker isn't there any more."
            case .notRecording, .noCopyUpdated: return "The Take ended. Try again."
            }
        }
        let outcome = await recorder.renameLastTakeMarker(at: index, to: name)
        switch outcome.result {
        case .emptyName: return "A Marker needs a name."
        case .noSuchMarker: return "That Marker isn't there any more."
        case .notRecording: return "There is no Take to rename a Marker in."
        case .noCopyUpdated, .renamed:
            let problems = outcome.failed.map { "\($0.copy == .drive ? "The Drive" : "This device") Copy still has the old name: \($0.reason)" }
            if outcome.result == .noCopyUpdated { return "Couldn't rename it. " + problems.joined(separator: " ") }
            return problems.isEmpty ? nil : problems.joined(separator: " ")
        }
    }

    /// The Pre-roll length changed in Settings: keep it, give it to the recorder, and, if Armed, Arm again so
    /// the buffer is sized for it. That only happens between Takes (Settings is locked during one).
    func preRollChanged() {
        PreRollSetting.save(preRollSeconds)
        recorder.preRollSeconds = preRollSeconds
        if recorder.isArmed { armSelectedDevice() }
    }

    /// What the chosen Pre-roll length costs in memory for the Armed input (or an 18-channel one before
    /// anything is Armed), in words for Settings.
    var preRollNote: String {
        guard preRollSeconds > 0 else { return "Off. A Take starts when you press record." }
        let bytes = PreRollSetting.memoryBytes(
            seconds: preRollSeconds,
            channelCount: recorder.isArmed ? recorder.usbChannelCount : 18,
            sampleRate: armedDevice?.sampleRate ?? 48_000)
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
        return "A Take starts with the last \(Int(preRollSeconds)) s before you press record. Uses about \(size) of memory while Armed."
    }

    var usbChannelSummary: String {
        let count = recorder.usbChannelCount
        return count == 1 ? "1 USB Channel" : "\(count) USB Channels"
    }

    /// Most input channels the Armed route offers, where the system reports it (iOS).
    private(set) var offeredChannelCount: Int?

    /// A real reason some USB Channels won't be recorded, or nil to just show the count.
    var usbChannelShortfall: USBChannelShortfall? {
        USBChannelShortfall.check(
            usbChannelCount: recorder.isArmed ? recorder.usbChannelCount : 0,
            offeredChannelCount: offeredChannelCount,
            mixer: mixerLink.identity, capabilities: mixerLink.capabilities)
    }

    /// Notes what the system offered for `device`, after it was Armed or took over input.
    func noteOfferedChannels(of device: any AudioIODevice) {
        #if os(iOS)
        offeredChannelCount = (device as? SessionAudioDevice)?.maximumInputChannelCount
        #else
        offeredChannelCount = nil
        #endif
    }

    // MARK: - The loop that outlives the screen

    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Set once the first Arm has been tried, so a screen appearing before that doesn't Arm early.
    @ObservationIgnored private var didStart = false

    /// Starts the loop that protects and shows a Take: it Arms the input, polls the meters, looks for a Drive
    /// joining or space running low, keeps the Mixer Link and follows route changes. It belongs to the model,
    /// not the screen, so it keeps running (and keeps a Take safe) when the screen is torn down or rebuilt.
    /// Calling it again does nothing.
    func start() {
        guard loop == nil else { return }
        loop = Task { await run() }
        Task { await offerDemoSignalIfAvailable() }
    }

    /// The Demo signal needs StoreKit's answer (TestFlight or not), which arrives later; the input list
    /// starts without it and gets it here. Only adds an input: the selection and an armed device stay.
    private func offerDemoSignalIfAvailable() async {
        await DemoSignalAvailability.resolveEnvironment()
        guard DemoSignalAvailability.isAvailableInThisBuild, !devices.contains(where: { $0.id == "demo" }) else { return }
        devices = Self.availableDevices()
    }

    /// The screen appeared again: Arm if nothing is, never over a running Take (see `RecorderLifecycle`).
    func screenAppeared() {
        guard didStart, RecorderLifecycle.screenAppeared(isArmed: recorder.isArmed) == .arm else { return }
        armSelectedDevice()
    }

    /// The screen went away: disarm an unused recorder, never a running Take.
    func screenDisappeared() {
        if RecorderLifecycle.screenDisappeared(isRecording: recorder.isRecording) == .disarm { recorder.disarm() }
    }

    private func run() async {
        defer { loop = nil }
        guard await hasMicrophonePermission() else {
            micDenied = true
            armError = "ShowRecorder needs microphone access to record your mixer. Allow it in the system's Privacy settings, under Microphone."
            return
        }
        drive.refresh()
        if RecorderLifecycle.screenAppeared(isArmed: recorder.isArmed) == .arm { armSelectedDevice() }
        didStart = true
        // Reconnect to the remembered Mixer. This runs here, not in Settings, so it happens without Settings open.
        if !mixerAddress.isEmpty, mixerLink.status == .idle { connectMixer() }
        #if os(iOS)
        let routeWatcher = Task { await watchRouteChanges() }
        defer { routeWatcher.cancel() }
        let sessionWatcher = Task { await watchAudioSession() }
        defer { sessionWatcher.cancel() }
        #endif
        #if os(macOS)
        let deviceWatcher = Task { await watchDeviceChanges() }
        defer { deviceWatcher.cancel() }
        #endif
        var tick = 0
        var lastPoll = ContinuousClock.now
        while !Task.isCancelled {
            tick += 1
            if tick % 30 == 0 { refreshDestinations() }
            if tick % 30 == 0 { disarmIfIdle() }
            // Re-check the Drive every few seconds so an unplugged one shows before record is pressed.
            if tick % 90 == 0 { drive.refresh() }
            let now = ContinuousClock.now
            let seconds = min(max((now - lastPoll).inSeconds, 0.001), 0.25)
            lastPoll = now
            let fresh = recorder.takeChannelLevels()
            if fresh.count == meters.count {
                for index in fresh.indices { meters[index].update(fresh[index], seconds: seconds) }
            }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// The picker changed. Skips the device the model has just Armed itself after a device change.
    func selectionDidChange() {
        if recorder.isArmed, armedDevice?.id == selectedDeviceID { return }
        armSelectedDevice()
    }

    func armSelectedDevice() {
        guard let choice = devices.first(where: { $0.id == selectedDeviceID }) else {
            recorder.disarm()
            armedDevice = nil
            return
        }
        do {
            armedDevice = nil
            let device = try choice.make()
            try recorder.arm(device)
            noteOfferedChannels(of: device)
            armedDevice = choice.info
            armError = nil
            #if os(iOS)
            // The route's name and channels are only known once the session is active.
            devices = Self.availableDevices()
            if !devices.contains(where: { $0.id == selectedDeviceID }) { selectCurrentRouteInput() }
            #endif
        } catch {
            armError = "Couldn't start \(choice.name): \(error)"
        }
        meters = Array(repeating: ChannelMeter(), count: recorder.usbChannelCount)
    }

    private func hasMicrophonePermission() async -> Bool {
        #if os(iOS)
        await AVAudioApplication.requestRecordPermission()
        #else
        true  // macOS asks on first input; the sandbox entitlement allows it.
        #endif
    }

    #if os(iOS)
    /// Re-arms when the input route really changes (a mixer plugged in or out). Comparing the route
    /// avoids re-arming on the notifications our own session changes cause.
    private func watchRouteChanges() async {
        var armedRoute = Self.currentRouteSignature()
        for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification).map({ _ in () }) {
            let route = Self.currentRouteSignature()
            guard route != armedRoute else { continue }
            armedRoute = route
            devices = Self.availableDevices()
            guard Self.isRouteInput(selectedDeviceID) else { continue }
            // Whatever iOS just routed to is now the selection; re-arming must not pull it back.
            selectCurrentRouteInput()
            switch interruptions.routeChanged(isRecording: recorder.isRecording) {
            case .none: break
            case .rearm: armSelectedDevice()
            case .moveInput: moveTakeToCurrentRoute()
            }
        }
    }

    /// Moves a running Take onto the new route, keeping it if the format still matches (#10).
    private func moveTakeToCurrentRoute() {
        let wasStopped = interruptions.isInputStopped
        do {
            let device = try SessionAudioDevice.current()
            let continued = try recorder.restartInput(on: device)
            noteOfferedChannels(of: device)
            armedDevice = devices.first { $0.id == selectedDeviceID }?.info
            meters = Array(repeating: ChannelMeter(), count: recorder.usbChannelCount)
            Self.sessionLog.notice("Input route changed during a Take; \(continued ? "the Take continues" : "the format changed, so the Take was stopped and saved", privacy: .public)")
            if !continued {
                recordError = "The audio input changed format during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take."
            }
            // A retry that works ends the "input is stopped" state the failed move left behind.
            if wasStopped { handle(.restarted) }
        } catch {
            // The policy says what's missing and tries again on the next route change or foreground.
            handle(.moveFailed(String(describing: error)))
        }
    }

    /// Selects the input iOS is routing to now, if it's in the list.
    private func selectCurrentRouteInput() {
        guard let uid = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid,
              let choice = devices.first(where: { $0.id == Self.routeInputPrefix + uid }) else { return }
        selectedDeviceID = choice.id
        if recorder.isArmed { armedDevice = choice.info }
    }

    private static let routeInputPrefix = "ios-input-"

    /// Whether `id` is an iOS input, which follows the route when it changes.
    private static func isRouteInput(_ id: String?) -> Bool {
        id?.hasPrefix(routeInputPrefix) == true
    }

    private static func currentRouteSignature() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.map { "\($0.uid):\($0.channels?.count ?? 0)" }.joined(separator: "|")
    }
    #endif

    #if os(macOS)
    /// Refreshes the device list whenever Core Audio reports a change, until canceled.
    private func watchDeviceChanges() async {
        for await _ in CoreAudioDevice.changes() {
            // One plug or unplug arrives as a burst of notifications; let it settle first.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            applyDeviceListChange()
        }
    }

    /// Re-reads the device list and keeps, switches, re-arms or disarms as `InputDeviceChange` decides.
    private func applyDeviceListChange() {
        let fresh = Self.availableDevices()
        let change = InputDeviceChange.decide(
            old: devices.map(\.info), new: fresh.map(\.info),
            selectedID: selectedDeviceID,
            armed: recorder.isArmed ? armedDevice : nil,
            isRecording: recorder.isRecording)
        devices = fresh
        if change.stopsTake {
            do {
                try recorder.stopTake()
                recordError = change.message
            } catch {
                recordError = "\(change.message ?? "The input device changed during the Take.") But the Take didn't finish cleanly: \(error.localizedDescription)"
            }
        }
        selectedDeviceID = change.selectedID
        switch change.action {
        case .none:
            break
        case .arm:
            armSelectedDevice()
        case .disarm:
            recorder.disarm()
            armedDevice = nil
            meters = []
            if !change.stopsTake { armError = change.message }
        }
    }
    #endif

    private static func availableDevices() -> [DeviceChoice] {
        var choices: [DeviceChoice] = []
        #if os(macOS)
        // Multichannel devices first (most channels first), then the system default input.
        let defaultID = CoreAudioDevice.defaultInputDeviceID()
        var defaultChoiceID: String?
        var macChoices: [DeviceChoice] = []
        for device in CoreAudioDevice.inputDevices() {
            let id = "coreaudio-\(device.uid)"
            if device.id == defaultID { defaultChoiceID = id }
            macChoices.append(DeviceChoice(
                info: InputDeviceInfo(
                    id: id, name: device.name,
                    inputChannelCount: device.inputChannelCount, sampleRate: device.sampleRate),
                name: "\(device.name) (\(device.inputChannelCount) in)",
                make: { device }))
        }
        for info in InputDeviceInfo.preferredOrder(macChoices.map(\.info), defaultID: defaultChoiceID) {
            if let choice = macChoices.first(where: { $0.id == info.id }) { choices.append(choice) }
        }
        #endif
        #if os(iOS)
        // Every input iOS can see, USB interfaces first, so one that isn't the current route can be chosen.
        let session = AVAudioSession.sharedInstance()
        // Inputs are only listed for a recording category; this doesn't activate the session.
        if session.category != .record { try? session.setCategory(.record, mode: .measurement, options: []) }
        let current = session.currentRoute.inputs.first
        var ports = session.availableInputs ?? []
        if let current, !ports.contains(where: { $0.uid == current.uid }) { ports.append(current) }
        ports.sort { ($0.portType == .usbAudio ? 0 : 1) < ($1.portType == .usbAudio ? 0 : 1) }
        for port in ports {
            let isCurrent = port.uid == current?.uid
            let channels = isCurrent ? port.channels?.count : nil
            let uid = port.uid
            choices.append(DeviceChoice(
                info: InputDeviceInfo(
                    id: Self.routeInputPrefix + uid, name: port.portName,
                    inputChannelCount: channels ?? 0, sampleRate: session.sampleRate),
                name: port.portName + (channels.map { " (\($0) in)" } ?? ""),
                make: { try SessionAudioDevice.current(preferredInputUID: uid) }))
        }
        if ports.isEmpty {
            // Nothing listed yet (the session isn't active): offer whatever iOS picks.
            choices.append(DeviceChoice(
                info: InputDeviceInfo(id: Self.routeInputPrefix + "default", name: "Audio input", inputChannelCount: 0, sampleRate: session.sampleRate),
                name: "Audio input",
                make: { try SessionAudioDevice.current() }))
        }
        #endif
        if DemoSignalAvailability.isAvailableInThisBuild {
            choices.append(DeviceChoice(
                info: InputDeviceInfo(id: "demo", name: "Demo signal", inputChannelCount: DemoAudioDevice.channelCount, sampleRate: 48_000),
                name: "Demo signal (\(DemoAudioDevice.channelCount) channels)",
                make: { DemoAudioDevice() }))
        }
        return choices
    }
}

/// A large Marker button with the Take's Marker count; dimmed when no Take is running.
struct MarkerButtonLabel: View {
    let count: Int
    var size: CGFloat = 88

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.yellow.opacity(0.2))
                    .frame(width: size, height: size)
                Image(systemName: "flag.fill")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            Text(count == 1 ? "1 Marker" : "\(count) Markers")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// A large round record button that turns into a stop square while recording.
struct RecordButtonLabel: View {
    let isRecording: Bool
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary, lineWidth: 4)
                .frame(width: size, height: size)
            RoundedRectangle(cornerRadius: isRecording ? 8 : size * 0.39)
                .fill(.red)
                .frame(width: size * (isRecording ? 0.41 : 0.77), height: size * (isRecording ? 0.41 : 0.77))
        }
        .contentShape(Circle())
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }
}

#Preview {
    RecordScreen(model: RecordScreenModel())
}

private extension Duration {
    var inSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
