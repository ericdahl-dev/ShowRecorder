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
        SettingsLock.isLocked(item, isRecording: model.takeBusy)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if model.takeBusy {
                    Section {
                        Label(RecordToAvailability.isAvailableInThisBuild
                              ? "The audio interface, Pre-roll, Drive, Record to and Mixer Link can't be changed during a Take."
                              : "The audio interface, Pre-roll, Drive and Mixer Link can't be changed during a Take.", systemImage: "lock.fill")
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
                    #if DEBUG && os(iOS)
                    // Debug only, never in TestFlight: play the input to Bluetooth headphones while recording (#233).
                    Toggle("Monitor experiment (#233)", isOn: Binding(
                        get: { MonitorExperiment.shared.isEnabled },
                        set: { MonitorExperiment.shared.isEnabled = $0; model.monitorExperimentChanged() }
                    ))
                    .disabled(locked(.input))
                    #endif
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
                    // Record to first; with This iPhone in effect the Drive rows step back (Eric, #805).
                    if RecordToAvailability.isAvailableInThisBuild {
                        // Free shows This iPhone, the choice in effect; Drive and Both offer Pro, and the saved choice
                        // stays for Pro or the Trial (Eric, #805).
                        let driveAllowed = model.pro.license().allowsDrive
                        Picker("Record to", selection: Binding(
                            get: { model.recordTo.shown(driveAllowed: driveAllowed) },
                            set: { choice in
                                if choice.offersPro(driveAllowed: driveAllowed) {
                                    showingPaywall = true
                                } else {
                                    model.recordTo = choice
                                    model.recordToChanged()
                                }
                            }
                        )) {
                            ForEach(RecordTo.allCases, id: \.self) { choice in
                                let label = choice.label(deviceWord: ThisHardware.word)
                                Text(choice.offersPro(driveAllowed: driveAllowed) ? "\(label) (Pro)" : label).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(locked(.recordTo))
                        // Free has its own note below: its Takes record to this iPhone, whatever is chosen.
                        if model.pro.license().allowsDrive {
                            switch model.recordTo {
                            case .device:
                                Text("Takes record to this \(ThisHardware.word) only, even with a Drive connected.")
                                    .font(.footnote).secondaryText()
                            case .drive:
                                Text("Takes are written only to the Drive. If the Drive is lost, this \(ThisHardware.word) records until it's back.")
                                    .font(.footnote).secondaryText()
                            case .both: EmptyView()
                            }
                        }
                    }
                    driveStatus
                    // Free records to the Device only (#705): say so where the Drive is chosen, calmly, with no prompt.
                    if !model.pro.license().allowsDrive, case .available = model.drive.status {
                        Text("On Free, Takes record to this \(ThisHardware.word) only. A second Copy on a Drive, with Repair, is part of Pro.")
                            .font(.footnote).secondaryText()
                    }
                    Button(model.drive.status == .notChosen ? "Choose Drive Folder…" : "Change Drive Folder…") { choosing = true }
                        .disabled(locked(.drive))
                        .opacity(showsDrive ? 1 : 0.5)
                    timeLeft
                    // Shown while it runs or has a result even if the Drive drops out, so Cancel and the result stay reachable.
                    if DriveSpeedTestAvailability.isAvailableInThisBuild,
                       model.drive.status.isAvailable || model.speedTest.isRunning || model.speedTest.result != nil {
                        DriveSpeedTestRow(model: model.speedTest, canStart: model.drive.status.isAvailable && model.speedTestMayStart) {
                            guard model.speedTestMayStart else { return }
                            model.speedTest.start(store: model.drive.store)
                        }
                    }
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
                        .disabled(locked(.mixerLink))
                    Button(isConnecting ? "Connecting…" : "Connect") { model.connectMixer() }
                        .disabled(isConnecting || model.mixerAddress.isEmpty || locked(.mixerLink))
                    mixerStatus
                    FindMixersRow(model: model, disabled: locked(.mixerLink))
                    if model.mixerGain.offersClipProtection {
                        Toggle("Clip protection", isOn: $model.clipProtectionOn)
                        Text("During a Take, turns a clipping channel's preamp down on the Mixer, with Mix Hold so the mix stays the same. Each move adds a Marker. Switched on, it starts with the next Take; switched off, it stops at once.")
                            .font(.footnote).secondaryText()
                    }
                } header: {
                    Text("Mixer Link").id(SettingsSection.mixer)
                } }

                Section {
                    Button("Run Soundcheck") { showingSoundcheck = true }
                        .disabled(model.takeBusy)
                } footer: {
                    Text("A 30 s test of the Mixer Link, the USB Channels, every Copy and the files. Not during a Take.")
                }

                if ProStore.isOffered, !locked(.pro) { ProSection(model: model, showingTrial: $showingTrial, showingPaywall: $showingPaywall) }

                SupportSection(model: model)

                // Which build is installed (#697): small and last, and not on the record screen.
                Section {
                    Text(AppVersion.current)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $showingChannelNames) { ChannelNamesView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
            .sheet(isPresented: $showingSoundcheck) { SoundcheckView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
            .sheet(isPresented: $showingTrial) { TrialSheet(store: model.pro).modifier(AppearanceRoot(mode: model.appearance)) }
            .sheet(isPresented: $showingPaywall) { PaywallSheet(store: model.pro, moment: nil, mixerModel: model.mixer.identity?.model).modifier(AppearanceRoot(mode: model.appearance)) }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.drive.choose(url) }
            }
            .onAppear {
                if let scrollTo { proxy.scrollTo(scrollTo, anchor: .top) }
            }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = model.mixer.status { true } else { false }
    }

    @ViewBuilder private var driveStatus: some View {
        switch model.drive.status {
        case .notChosen:
            Label("No Drive folder. Takes go to the Device only.", systemImage: "externaldrive.badge.questionmark")
                .secondaryText()
        case .available(let drive):
            Label("Drive: \(drive.name) · \(drive.availableBytes.formatted(.byteCount(style: .file))) free", systemImage: "externaldrive.fill.badge.checkmark")
        case .unavailable(let problem):
            if showsDrive {
                Label(problem.message, systemImage: "externaldrive.badge.exclamationmark")
                    .warningText()
            }
        }
    }

    /// Whether the Drive's warning and time left show: not with This iPhone in effect (#805).
    private var showsDrive: Bool {
        model.recordTo.settingsShowsDrive(isOffered: RecordToAvailability.isAvailableInThisBuild, driveAllowed: model.pro.license().allowsDrive)
    }

    /// Time left on each Destination for the USB Channels a Take would record.
    @ViewBuilder private var timeLeft: some View {
        let count = model.recordedChannelCount
        if count > 0 {
            let rate = model.recorder.sampleRate ?? 48_000
            let device = TimeLeft(availableBytes: model.drive.deviceAvailableBytes, usbChannelCount: count, sampleRate: rate)
            let drive: TimeLeft? = if showsDrive, case .available(let d) = model.drive.status {
                TimeLeft(availableBytes: d.availableBytes, usbChannelCount: count, sampleRate: rate)
            } else { nil }
            Text("Time left · Device: \(device.description)" + (drive.map { " · Drive: \($0.description)" } ?? ""))
                .monospacedDigit()
                .secondaryText()
        }
    }

    @ViewBuilder private var mixerStatus: some View {
        switch model.mixer.status ?? .idle {
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
