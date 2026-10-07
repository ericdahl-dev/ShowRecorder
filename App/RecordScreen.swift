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
struct RecordScreen: View {
    @State private var model = RecordScreenModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error = model.armError {
                Banner(text: error, systemImage: "exclamationmark.octagon.fill", tint: .red)
            }
            if let error = model.recordError {
                Banner(text: error, systemImage: "exclamationmark.octagon.fill", tint: .red)
            }
            if let warning = model.destinationWarning {
                Banner(text: warning, systemImage: "externaldrive.badge.exclamationmark", tint: .orange)
            }
            if let summary = model.copySummary, !model.recorder.isRecording {
                Banner(text: summary.text, systemImage: summary.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", tint: summary.isProblem ? .orange : .green)
            }
            if let notice = model.interruptions.notice {
                Banner(text: notice, systemImage: "phone.badge.waveform.fill", tint: .orange)
            }
            if let shortfall = model.usbChannelShortfall {
                Banner(text: shortfall.message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
            DrivePanel(usbChannelCount: model.recorder.usbChannelCount)
            MixerLinkPanel(link: model.mixerLink, usbChannelCount: model.recorder.usbChannelCount)
            MeterGrid(levels: model.levels, sources: model.mixerLink.sources)
            Spacer(minLength: 0)
            transport
        }
        .padding()
        .task { await model.runWhileVisible() }
        // Locking the screen or leaving the app never ends a Take; becoming active retries input
        // that an interruption left stopped.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.handle(.becameActive)
            case .background: model.handle(.movedToBackground)
            default: break
            }
        }
        #if os(iOS)
        // Keep the screen awake while the record screen is showing.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
        .confirmationDialog("Stop recording?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Recording", role: .destructive) { model.stop() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("This ends \(model.takeTitle).")
        }
    }

    @State private var confirmingStop = false

    private var transport: some View {
        VStack(spacing: 12) {
            Text(model.showSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 28) {
                Button {
                    if model.recorder.isRecording {
                        confirmingStop = true
                    } else {
                        model.record()
                    }
                } label: {
                    RecordButtonLabel(isRecording: model.recorder.isRecording)
                }
                .buttonStyle(.plain)
                .disabled(!model.recorder.isArmed)
                .accessibilityLabel(model.recorder.isRecording ? "Stop recording" : "Record")
                .keyboardShortcut("r", modifiers: .command)

                if model.recorder.isRecording {
                    Button {
                        model.recorder.addMarker()
                    } label: {
                        MarkerButtonLabel(count: model.recorder.takeMarkers.count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Marker")
                    .keyboardShortcut("m", modifiers: .command)
                }
            }
            if let last = model.recorder.takeMarkers.last, model.recorder.isRecording {
                Text("\(last.name) placed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .id(model.recorder.takeMarkers.count)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: model.recorder.takeMarkers.count)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Input", selection: $model.selectedDeviceID) {
                if model.selectedDeviceID == nil {
                    Text(model.devices.isEmpty ? "No audio input" : "Choose an input").tag(String?.none)
                }
                ForEach(model.devices, id: \.id) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .onChange(of: model.selectedDeviceID) { model.selectionDidChange() }
            .disabled(model.recorder.isRecording)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.recorder.isArmed ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.recorder.isArmed ? "Armed" : "Not armed")
                Text("·").foregroundStyle(.secondary)
                Text(model.usbChannelSummary)
                    .monospacedDigit()
            }
            .font(.subheadline)
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
    let recorder = Recorder(driveFolder: {
        DriveFolderStore().beginAccess().map { access in DestinationAccess(folder: access.folder, release: { access.end() }) }
    })
    let mixerLink = MixerLinkController()
    private(set) var devices: [DeviceChoice] = []
    var selectedDeviceID: String?
    private(set) var levels: [Float] = []
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
        func word(_ outcome: CopyOutcome) -> String {
            switch outcome {
            case .complete: "complete"
            case .hasGaps: "has Gaps"
            case .repaired: "Repaired"
            case .repairFailed: "Repair failed"
            }
        }
        let parts = [(DestinationKind.device, "Device"), (.drive, "Drive")].compactMap { kind, name in
            outcomes[kind].map { "\(name) copy: \(word($0))" }
        }
        let problem = outcomes.values.contains { $0 == .hasGaps || $0 == .repairFailed }
        return (parts.joined(separator: " · "), problem)
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
        wasRecording = recorder.isRecording
    }

    /// What to do about audio interruptions, and the banner they leave (see AudioSessionEvents.swift).
    var interruptions = InterruptionPolicy()

    init() {
        devices = Self.availableDevices()
        selectedDeviceID = devices.first?.id
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
            recordError = nil
            handle(.takeStarted)
        } catch {
            recordError = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func stop() {
        wasRecording = false  // the operator ended it
        do {
            try recorder.stopTake()
        } catch {
            recordError = "The Take didn't finish cleanly: \(error.localizedDescription)"
        }
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

    /// Arms the selected device, polls meters at about 30 Hz, and disarms when the screen goes away.
    func runWhileVisible() async {
        guard await hasMicrophonePermission() else {
            armError = "ShowRecorder needs microphone access to record your mixer. Turn it on in Settings › Privacy & Security › Microphone."
            return
        }
        armSelectedDevice()
        defer { recorder.disarm() }
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
        while !Task.isCancelled {
            tick += 1
            if tick % 30 == 0 { refreshDestinations() }
            let fresh = recorder.takeMeterLevels()
            levels = fresh.enumerated().map { index, level in
                // Fall back gently so short peaks stay visible.
                max(level, (levels.indices.contains(index) ? levels[index] : 0) * 0.85)
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
            #endif
        } catch {
            armError = "Couldn't start \(choice.name): \(error)"
        }
        levels = Array(repeating: 0, count: recorder.usbChannelCount)
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
            guard selectedDeviceID == Self.routeDeviceID else { continue }
            switch interruptions.routeChanged(isRecording: recorder.isRecording) {
            case .none: break
            case .rearm: armSelectedDevice()
            case .moveInput: moveTakeToCurrentRoute()
            }
        }
    }

    /// Moves a running Take onto the new route, keeping it if the format still matches (#10).
    private func moveTakeToCurrentRoute() {
        do {
            let device = try SessionAudioDevice.current()
            let continued = try recorder.restartInput(on: device)
            noteOfferedChannels(of: device)
            armedDevice = devices.first { $0.id == Self.routeDeviceID }?.info
            levels = Array(repeating: 0, count: recorder.usbChannelCount)
            Self.sessionLog.notice("Input route changed during a Take; \(continued ? "the Take continues" : "the format changed, so the Take was stopped and saved", privacy: .public)")
            if !continued {
                recordError = "The audio input changed format during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take."
            }
        } catch {
            Self.sessionLog.error("Moving the Take to the new route failed: \(String(describing: error), privacy: .public)")
            recordError = "Couldn't move the Take to the new audio input: \(error)"
        }
    }

    private static let routeDeviceID = "ios-route"

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
            levels = []
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
        let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
        let channels = input?.channels?.count
        choices.append(DeviceChoice(
            info: InputDeviceInfo(
                id: routeDeviceID, name: input?.portName ?? "Audio input",
                inputChannelCount: channels ?? 0, sampleRate: AVAudioSession.sharedInstance().sampleRate),
            name: "\(input?.portName ?? "Audio input")" + (channels.map { " (\($0) in)" } ?? ""),
            make: { try SessionAudioDevice.current() }))
        #endif
        #if DEBUG
        choices.append(DeviceChoice(
            info: InputDeviceInfo(id: "demo", name: "Demo signal", inputChannelCount: DemoAudioDevice.channelCount, sampleRate: 48_000),
            name: "Demo signal (\(DemoAudioDevice.channelCount) channels)",
            make: { DemoAudioDevice() }))
        #endif
        return choices
    }
}

/// A large Marker button shown while recording, with the Take's Marker count.
struct MarkerButtonLabel: View {
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.yellow.opacity(0.2))
                    .frame(width: 72, height: 72)
                Image(systemName: "flag.fill")
                    .font(.system(size: 28, weight: .semibold))
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

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary, lineWidth: 4)
                .frame(width: 88, height: 88)
            RoundedRectangle(cornerRadius: isRecording ? 8 : 34)
                .fill(.red)
                .frame(width: isRecording ? 36 : 68, height: isRecording ? 36 : 68)
        }
        .contentShape(Circle())
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }
}

struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(tint)
    }
}

#Preview {
    RecordScreen()
}
