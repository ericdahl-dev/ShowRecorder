import AudioIO
import Recording
import CoreAudioIO
import MixerLink
import SwiftUI
#if os(iOS)
import AVFAudio
#endif

/// The record screen. While it is showing, the recorder is Armed on the chosen device.
struct RecordScreen: View {
    @State private var model = RecordScreenModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error = model.armError {
                Banner(text: error, systemImage: "exclamationmark.octagon.fill", tint: .red)
            }
            if let error = model.recordError {
                Banner(text: error, systemImage: "exclamationmark.octagon.fill", tint: .red)
            }
            if model.recorder.hasTooFewUSBChannels {
                Banner(
                    text: "This device sends \(model.usbChannelSummary). The XR18 and MR18 send 18, so some of the Mixer won't be recorded.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange)
            }
            MixerLinkPanel(link: model.mixerLink, usbChannelCount: model.recorder.usbChannelCount)
            MeterGrid(levels: model.levels, sources: model.mixerLink.sources)
            Spacer(minLength: 0)
            transport
        }
        .padding()
        .task { await model.runWhileVisible() }
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
        }
        .frame(maxWidth: .infinity)
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
    let recorder = Recorder()
    let mixerLink = MixerLinkController()
    private(set) var devices: [DeviceChoice] = []
    var selectedDeviceID: String?
    private(set) var levels: [Float] = []
    private(set) var armError: String?
    private(set) var recordError: String?
    /// The device as it was when last Armed, to tell a format change from a new device.
    @ObservationIgnored private var armedDevice: InputDeviceInfo?

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
        } catch {
            recordError = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func stop() {
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
        #endif
        #if os(macOS)
        let deviceWatcher = Task { await watchDeviceChanges() }
        defer { deviceWatcher.cancel() }
        #endif
        while !Task.isCancelled {
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
            try recorder.arm(choice.make())
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
            if selectedDeviceID == Self.routeDeviceID { armSelectedDevice() }
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
        // A device that can carry a whole XR18 comes first, then the system default input.
        let defaultID = CoreAudioDevice.defaultInputDeviceID()
        let devices = CoreAudioDevice.inputDevices().sorted { a, b in
            let aFull = a.inputChannelCount >= Recorder.expectedUSBChannelCount
            let bFull = b.inputChannelCount >= Recorder.expectedUSBChannelCount
            if aFull != bFull { return aFull }
            return a.id == defaultID && b.id != defaultID
        }
        for device in devices {
            choices.append(DeviceChoice(
                info: InputDeviceInfo(
                    id: "coreaudio-\(device.uid)", name: device.name,
                    inputChannelCount: device.inputChannelCount, sampleRate: device.sampleRate),
                name: "\(device.name) (\(device.inputChannelCount) in)",
                make: { device }))
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
            info: InputDeviceInfo(id: "demo", name: "Demo signal", inputChannelCount: 18, sampleRate: 48_000),
            name: "Demo signal (18 channels)",
            make: { DemoAudioDevice() }))
        #endif
        return choices
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
