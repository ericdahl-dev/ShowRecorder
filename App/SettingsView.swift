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
    @State private var showingSoundcheck = false
    @State private var showingTrial = false
    @State private var showingPaywall = false

    /// Whether a setting can't be changed right now: some can't while a Take runs (`SettingsLock`).
    private func locked(_ item: SettingsItem) -> Bool {
        SettingsLock.isLocked(item, isRecording: model.recorder.isRecording)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if model.recorder.isRecording {
                    Section {
                        Label("The audio interface, Pre-roll, Drive and Mixer Link can't be changed during a Take.", systemImage: "lock.fill")
                            .secondaryText()
                    }
                }
                Section {
                    Picker("Audio interface", selection: $model.selectedDeviceID) {
                        if model.selectedDeviceID == nil {
                            Text(model.devices.isEmpty ? "No audio interface" : "Choose an audio interface").tag(String?.none)
                        }
                        ForEach(model.devices, id: \.id) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    .onChange(of: model.selectedDeviceID) { model.selectionDidChange() }
                    .disabled(locked(.input))
                    Picker("Sample rate", selection: $model.sampleRateChoice) {
                        ForEach(model.sampleRateChoices, id: \.self) { rate in
                            Text(SampleRateSetting.label(rate, current: model.recorder.sampleRate)).tag(rate)
                        }
                        if let chosen = model.sampleRateChoice, !model.sampleRateChoices.contains(chosen) {
                            Text(SampleRateSetting.label(chosen, current: nil)).tag(Optional(chosen))
                        }
                    }
                    .onChange(of: model.sampleRateChoice) { model.sampleRateChanged() }
                    .disabled(locked(.input))
                    Text(model.usbChannelSummary).secondaryText().monospacedDigit()
                    Button("Channel names…") { showingChannelNames = true }
                        .disabled(model.meterModel.channelCount == 0)
                    Picker("Pre-roll", selection: $model.preRollSeconds) {
                        ForEach(PreRollSetting.choices, id: \.self) { seconds in
                            Text(seconds == 0 ? "Off" : "\(Int(seconds)) s").tag(seconds)
                        }
                    }
                    .onChange(of: model.preRollSeconds) { model.preRollChanged() }
                    .disabled(locked(.preRoll))
                    Text(model.preRollNote).font(.footnote).secondaryText()
                    // A dropdown menu. The choice is stored the moment it is picked (in the binding's setter), so it does
                    // not depend on the screen redrawing when the appearance changes under the open menu.
                    Picker("Appearance", selection: Binding(
                        get: { model.appearance },
                        set: { model.appearance = $0; model.appearanceChanged() }
                    )) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(model.appearance.footnote).font(.footnote).secondaryText()
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

                // Only for an X Air or X32 as the input (#365).
                if model.offersMixerLink { Section {
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
                    FindMixersRow(model: model, disabled: locked(.mixerLink))
                    if ClipProtectionSetting.isOffered() {
                        Toggle("Clip protection", isOn: $model.clipProtectionOn)
                        Text("During a Take, turns a clipping channel's preamp down on the Mixer, with Mix Hold so the mix stays the same. Each move adds a Marker. Switched on, it starts with the next Take; switched off, it stops at once.")
                            .font(.footnote).secondaryText()
                    }
                } header: {
                    Text("Mixer Link").id(SettingsSection.mixer)
                } }

                Section {
                    Button("Run Soundcheck") { showingSoundcheck = true }
                        .disabled(model.recorder.isRecording)
                } footer: {
                    Text("A 30 s test of the Mixer Link, the USB Channels, every Copy and the files. Not during a Take.")
                }

                if ProStore.isOffered, !locked(.pro) { ProSection(model: model, showingTrial: $showingTrial, showingPaywall: $showingPaywall) }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $showingChannelNames) { ChannelNamesView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
            .sheet(isPresented: $showingSoundcheck) { SoundcheckView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
            .sheet(isPresented: $showingTrial) { TrialSheet(store: model.pro).modifier(AppearanceRoot(mode: model.appearance)) }
            .sheet(isPresented: $showingPaywall) { PaywallSheet(store: model.pro, moment: nil).modifier(AppearanceRoot(mode: model.appearance)) }
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
            Label("No Drive folder. Takes go to the Device only.", systemImage: "externaldrive.badge.questionmark")
                .secondaryText()
        case .available(let drive):
            Label("Drive: \(drive.name) · \(drive.availableBytes.formatted(.byteCount(style: .file))) free", systemImage: "externaldrive.fill.badge.checkmark")
        case .unavailable(let problem):
            Label(problem.message, systemImage: "externaldrive.badge.exclamationmark")
                .warningText()
        }
    }

    /// Time left on each Destination for the Armed USB Channels.
    @ViewBuilder private var timeLeft: some View {
        let count = model.recorder.usbChannelCount
        if count > 0 {
            let rate = model.recorder.sampleRate ?? 48_000
            let device = TimeLeft(availableBytes: model.drive.deviceAvailableBytes, usbChannelCount: count, sampleRate: rate)
            let drive: TimeLeft? = if case .available(let d) = model.drive.status {
                TimeLeft(availableBytes: d.availableBytes, usbChannelCount: count, sampleRate: rate)
            } else { nil }
            Text("Time left · Device: \(device.description)" + (drive.map { " · Drive: \($0.description)" } ?? ""))
                .monospacedDigit()
                .secondaryText()
        }
    }

    @ViewBuilder private var mixerStatus: some View {
        switch model.mixerLink.status {
        case .idle:
            Label("Not connected to a Mixer. Stems use USB Channel names.", systemImage: "link")
                .secondaryText()
        case .connecting(let host):
            Label("Connecting to \(host)…", systemImage: "antenna.radiowaves.left.and.right")
                .secondaryText()
        case .up(let identity, let path):
            Label("Mixer Link up · \(identity.networkName) (\(identity.model)) · \(path.name)", systemImage: "checkmark.circle.fill")
        case .down(let problem):
            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                .warningText()
        }
    }
}
