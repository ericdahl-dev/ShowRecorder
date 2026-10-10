import Destinations
import MixerLink
import Recording
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: Hashable {
    case recording, storage, mixer
}

/// Everything set up before a show: the input, the Drive folder and the Mixer Link. Read-only while a
/// Take is running. A sheet over the record screen on iPhone and iPad (so opening it never takes the
/// record screen away) and the Settings scene on the Mac.
struct SettingsView: View {
    @Bindable var model: RecordScreenModel
    /// The section to scroll to when opened from a status chip.
    var scrollTo: SettingsSection?
    @State private var choosing = false
    @State private var showingChannelNames = false

    /// Whether a setting can't be changed right now: some can't while a Take runs (`SettingsLock`).
    private func locked(_ item: SettingsItem) -> Bool {
        SettingsLock.isLocked(item, isRecording: model.recorder.isRecording)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if model.recorder.isRecording {
                    Section {
                        Label("Input, Pre-roll, Drive and Mixer Link can't be changed during a Take.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Input", selection: $model.selectedDeviceID) {
                        if model.selectedDeviceID == nil {
                            Text(model.devices.isEmpty ? "No audio input" : "Choose an input").tag(String?.none)
                        }
                        ForEach(model.devices, id: \.id) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .onChange(of: model.selectedDeviceID) { model.selectionDidChange() }
                    .disabled(locked(.input))
                    Text(model.usbChannelSummary).foregroundStyle(.secondary).monospacedDigit()
                    Button("Channel names…") { showingChannelNames = true }
                        .disabled(model.meterModel.channelCount == 0)
                    Picker("Pre-roll", selection: $model.preRollSeconds) {
                        ForEach(PreRollSetting.choices, id: \.self) { seconds in
                            Text(seconds == 0 ? "Off" : "\(Int(seconds)) s").tag(seconds)
                        }
                    }
                    .onChange(of: model.preRollSeconds) { model.preRollChanged() }
                    .disabled(locked(.preRoll))
                    Text(model.preRollNote).font(.footnote).foregroundStyle(.secondary)
                    // Plain rows, not a menu: the whole row is the tap target, and a checkmark shows the choice.
                    Text("Appearance").font(.subheadline.weight(.semibold))
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            model.appearance = mode
                            model.appearanceChanged()
                        } label: {
                            HStack {
                                Text(mode.title)
                                Spacer()
                                if model.appearance == mode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.appearance == mode ? [.isButton, .isSelected] : .isButton)
                    }
                    Text(model.appearance.footnote).font(.footnote).foregroundStyle(.secondary)
                    #if os(iOS)
                    Toggle("Record button on the left in landscape", isOn: $model.transportLeading)
                        .onChange(of: model.transportLeading) { model.saveTransportSide() }
                    #endif
                } header: {
                    Text("Recording").id(SettingsSection.recording)
                }

                Section {
                    driveStatus
                    Button(model.drive.status == .notChosen ? "Choose Drive Folder…" : "Change Drive Folder…") { choosing = true }
                        .disabled(locked(.drive))
                    timeLeft
                } header: {
                    Text("Storage").id(SettingsSection.storage)
                }

                Section {
                    TextField("Mixer IP address", text: $model.mixerAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { model.connectMixer() }
                        .onChange(of: model.mixerAddress) { model.saveMixerAddress() }
                        .disabled(locked(.mixerLink))
                    Button(isConnecting ? "Connecting…" : "Connect") { model.connectMixer() }
                        .disabled(isConnecting || model.mixerAddress.isEmpty || locked(.mixerLink))
                    mixerStatus
                } header: {
                    Text("Mixer Link").id(SettingsSection.mixer)
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $showingChannelNames) { ChannelNamesView(model: model) }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.drive.choose(url) }
            }
            .onAppear {
                if let scrollTo { proxy.scrollTo(scrollTo, anchor: .top) }
            }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = model.mixerLink.status { true } else { false }
    }

    @ViewBuilder private var driveStatus: some View {
        switch model.drive.status {
        case .notChosen:
            Label("No Drive folder. Takes go to this device only.", systemImage: "externaldrive.badge.questionmark")
                .foregroundStyle(.secondary)
        case .available(let drive):
            Label("Drive: \(drive.name) · \(drive.availableBytes.formatted(.byteCount(style: .file))) free", systemImage: "externaldrive.fill.badge.checkmark")
        case .unavailable(let problem):
            Label(problem.message, systemImage: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
        }
    }

    /// Time left on each Destination for the Armed USB Channels.
    @ViewBuilder private var timeLeft: some View {
        let count = model.recorder.usbChannelCount
        if count > 0 {
            let device = TimeLeft(availableBytes: model.drive.deviceAvailableBytes, usbChannelCount: count, sampleRate: 48_000)
            let drive: TimeLeft? = if case .available(let d) = model.drive.status {
                TimeLeft(availableBytes: d.availableBytes, usbChannelCount: count, sampleRate: 48_000)
            } else { nil }
            Text("Time left · This device: \(device.description)" + (drive.map { " · Drive: \($0.description)" } ?? ""))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var mixerStatus: some View {
        switch model.mixerLink.status {
        case .idle:
            Label("Not connected to a mixer. Stems use USB Channel names.", systemImage: "link")
                .foregroundStyle(.secondary)
        case .connecting(let host):
            Label("Connecting to \(host)…", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case .up(let identity, let path):
            Label("Mixer Link up · \(identity.networkName) (\(identity.model)) · \(path == .wifi ? "Wi-Fi" : "USB")", systemImage: "checkmark.circle.fill")
        case .down(let problem):
            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
