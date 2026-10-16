import AudioIO
import Recording
import CoreAudioIO
import Destinations
import MixerLink
import SwiftUI
import TakeActivity
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
    /// How wide the transport is, so the gap between Stop and Marker can shrink on a very narrow screen.
    @State private var transportWidth: CGFloat = 402
    @State private var showingNewShow = false
    @State private var namingChannel: Int?
    @State private var channelName = ""
    @State private var showingChannelNames = false
    @State private var showingAutoGain = false
    @State private var showingShowList = launchFlag("-showList")
    @State private var settingsSection: SettingsSection?
    @State private var showingTrialOffer = false
    /// The Trial sheet the days chip opens (#743).
    @State private var showingTrialStatus = false
    @AppStorage(License.trialOfferedKey) private var trialOffered = false
    /// The paywall on screen. `model.paywall` is one that came due; it waits here until no other sheet is up (#357).
    @State private var shownPaywall: PaywallRequest?
    #if DEBUG && os(iOS)
    /// The headphone monitor experiment's switches (#233), in a sheet so the meters keep their height.
    @State private var showingMonitor = false
    #endif

    /// Whether a sheet is up, so the record screen doesn't present another over it.
    private var anotherSheetOpen: Bool {
        #if DEBUG && os(iOS)
        if showingMonitor { return true }
        #endif
        return showingSettings || showingMarkers || showingNewShow || showingShowList || showingChannelNames || showingAutoGain
            || showingTrialOffer || showingTrialStatus || model.showingSoundcheck || model.showingMoves || shownPaywall != nil
    }

    /// Shows a paywall that came due, else the first-launch Trial offer, once no other sheet is up.
    private func presentWaitingSheet() {
        guard !anotherSheetOpen else { return }
        if let request = model.paywall {
            model.paywall = nil
            shownPaywall = request
            return
        }
        guard model.pro.license().offersTrial(
            alreadyOffered: trialOffered, recording: model.recorder.isRecording,
            proPrice: model.pro.proProduct?.displayPrice, anotherSheetOpen: anotherSheetOpen) else { return }
        trialOffered = true
        showingTrialOffer = true
    }

    /// Landscape iPhone is short, not narrow: a Pro Max in landscape is wide but still short.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        // One root for both layouts. The task, idle timer, sheet and dialog below hang on it, so rotating
        // swaps the arrangement but never goes away (which would disarm the recorder).
        ZStack {
            if isLandscape { landscape } else { portrait }
        }
        // Text grows with Dynamic Type up to a point: past it the meters and the transport would no longer fit (#249).
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // The loop is the model's, started once; the screen only says when it appears and goes away.
        .task { model.start() }
        .onAppear {
            model.screenAppeared()
            // Screenshot and test flags open these the way a tap would.
            if launchFlag("-showSettings") { showSettings(nil) }
            if launchFlag("-channelNames") { open(.channelNames) }
            if launchFlag("-showMarkers") { open(.markers) }
            if launchFlag("-soundcheck") { model.showingSoundcheck = true }
            if launchFlag("-autoGainDemo") { showingAutoGain = true }
        }
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
            .modifier(AppearanceRoot(mode: model.appearance))
        }
        .alert(
            "Name channel \(namingChannel ?? 0)",
            isPresented: Binding(get: { namingChannel != nil }, set: { if !$0 { namingChannel = nil } })
        ) {
            TextField("Name", text: $channelName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let namingChannel { model.recorder.updateChannelName(channelName, forChannel: namingChannel) } }
        } message: {
            Text("The files take the name when the Take ends. Leave it empty to take the name off.")
        }
        // Each sheet applies the Appearance itself: iOS presents a sheet on its own, and one that only inherits the
        // window's look keeps the old one until it is shown again.
        #if DEBUG && os(iOS)
        .sheet(isPresented: $showingMonitor) { MonitorExperimentSheet().modifier(AppearanceRoot(mode: model.appearance)) }
        #endif
        .sheet(isPresented: $showingNewShow) { NewShowSheet(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $model.showingSoundcheck) { SoundcheckView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $model.showingMoves) { MoveReportSheet(recorder: model.recorder).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $showingShowList) { ShowListView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $showingChannelNames) { ChannelNamesView(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $showingAutoGain) { AutoGainSheet(model: model).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $showingTrialOffer) { TrialSheet(store: model.pro).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $showingTrialStatus) { TrialStatusSheet(store: model.pro).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(item: $shownPaywall) { request in PaywallSheet(store: model.pro, moment: request.moment).modifier(AppearanceRoot(mode: model.appearance)) }
        // The first-launch Trial offer: once, when the Pro price has loaded, never during a Take and never over another
        // sheet. A paywall that came due waits for other sheets too: presenting over Settings closed both (#357).
        .onChange(of: model.pro.proProduct?.displayPrice, initial: true) { _, _ in presentWaitingSheet() }
        .onChange(of: anotherSheetOpen) { _, _ in presentWaitingSheet() }
        .onChange(of: model.paywall) { _, _ in presentWaitingSheet() }
        #if os(macOS)
        .background(WindowCloseGuard(model: model))
        #endif
        // A Mixer Link that comes up during a Take names its Stems when the Take ends.
        .onChange(of: model.linkedSources) { _, sources in model.recorder.offerSources(sources) }
        // Drive only Takes left on the Device move when the Drive connects (#630); never during a Take.
        .onChange(of: model.drive.status) { _, status in
            if case .available = status { model.recorder.driveMayHaveConnected() }
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
            .modifier(AppearanceRoot(mode: model.appearance))
        }
        #endif
        .confirmationDialog("Stop \(model.takeTitle)?", isPresented: $model.confirmingStop, titleVisibility: .visible) {
            Button("Stop Take", role: .destructive) { model.stop() }
            Button("Keep Going", role: .cancel) {}
        }
        // A Take the recorder ended by itself (out of space, no Destination) takes the question with it, so it
        // never offers "Keep Going" with nothing recording (#322).
        .onChange(of: model.recorder.isRecording) { _, recording in
            if !recording { model.confirmingStop = false; model.clearStopHint() }
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

    /// Like the paywall, the Trial sheet never opens during a Take.
    private func trialChipTapped() {
        if !model.recorder.isRecording { showingTrialStatus = true }
    }

    private func showSettings(_ section: SettingsSection?) {
        #if os(macOS)
        openSettings()
        #else
        // Always a full sheet: squeezed into the meters' place it showed only a few rows (Eric, v0.1.20).
        // It is locked during a Take anyway, so it doesn't need Stop and Marker beside it.
        settingsSection = section
        showingSettings = true
        #endif
    }

    /// Opens the Marker list or Channel names as a full sheet. Never in the meters' place: Eric didn't want
    /// anything over the meters (TestFlight feedback on v0.1.20).
    private func open(_ kind: LivePanel) {
        switch kind {
        case .markers: showingMarkers = true
        case .channelNames: showingChannelNames = true
        }
    }

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            StatusStrip(chips: model.chips, extras: model.extraChips, tap: chipTapped, tapTrial: trialChipTapped)
            // `-screenshotWindow` (Debug only): no empty alert band above the meters in a screenshot; the meters take it.
            if !(launchFlag("-screenshotWindow") && model.alerts.top == nil) {
                AlertSlot(queue: model.alerts, perform: model.perform, swipe: model.swipe)
            }
            MeterGrid(model: model.meterModel, clipped: model.recorder.clippedChannels, clearClip: { model.recorder.clearClip(channel: $0) }, sources: model.linkedSources, typedNames: model.recorder.channelNames, nameChannel: nameChannel)
                .overlay { if let block = model.recordBlock { DisarmedNotice(block: block, perform: model.perform) } }
            transport
        }
        .padding()
    }

    /// Header and status strip share one 44 pt row, the meters take the full height below it, and the
    /// transport is a column at the trailing edge (or the leading edge, for left-handed use). An urgent alert takes
    /// the status strip's place in the top row, never the meters' (#644).
    private var landscape: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                headerSummary(compact: true)
                    .frame(maxWidth: 190, alignment: .leading)
                LandscapeAlertRow(alerts: model.alerts, chips: model.chips, extras: model.extraChips, perform: model.perform, swipe: model.swipe, tap: chipTapped, tapTrial: trialChipTapped)
                markersButton
                gearButton
            }
            HStack(alignment: .top, spacing: 12) {
                if model.transportLeading { transportColumn }
                MeterGrid(model: model.meterModel, clipped: model.recorder.clippedChannels, clearClip: { model.recorder.clearClip(channel: $0) }, sources: model.linkedSources, typedNames: model.recorder.channelNames, nameChannel: nameChannel, compact: true)
                    .overlay { if let block = model.recordBlock { DisarmedNotice(block: block, perform: model.perform) } }
                if !model.transportLeading { transportColumn }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Hold to stop is for the iPhone only (#753): the iPad and the Mac keep tap and confirm.
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    @ViewBuilder private func recordButton(size: CGFloat) -> some View {
        if model.recorder.isRecording, TakeStopStyle.current(isPhone: isPhone) == .hold {
            // Hold to stop (#753): no dialog. A tap only shows the hint.
            HoldToStopRecordButton(size: size, label: "Stop \(model.takeTitle)", stop: { model.stop() }, hint: { model.showStopHint() })
        } else {
            Button {
                if model.recorder.isRecording {
                    model.confirmingStop = true
                } else {
                    model.record()
                }
            } label: {
                RecordButtonLabel(isRecording: model.recorder.isRecording, size: size)
            }
            .buttonStyle(.plain)
            .disabled(!model.recorder.isArmed)
            .accessibilityLabel(model.recorder.isRecording ? "Stop \(model.takeTitle)" : "Record")
        }
    }

    /// Always in place, dimmed when no Take is running, so Record never shifts under the thumb.
    private func markerButton(size: CGFloat) -> some View {
        Button {
            model.sequencer.addMarker()
        } label: {
            MarkerButtonLabel(count: model.recorder.takeMarkers.count, size: size)
        }
        .buttonStyle(.plain)
        .disabled(!model.recorder.isRecording)
        // Dimmed but readable while Armed: it is there, just not usable until a Take runs.
        .opacity(model.recorder.isRecording ? 1 : 0.55)
        .accessibilityLabel("Add Marker")
        .accessibilityValue(model.recorder.takeMarkers.count == 1 ? "1 Marker" : "\(model.recorder.takeMarkers.count) Markers")
        .accessibilityHint(model.recorder.isRecording ? "" : "Available during a Take")
        .sensoryFeedback(.success, trigger: model.recorder.takeMarkers.count) { old, new in new > old }
    }

    private func nameChannel(_ number: Int) {
        channelName = model.recorder.naming.editText(number, sources: model.linkedSources)
        namingChannel = number
    }

    private var transport: some View {
        VStack(spacing: 12) {
            // The Show's total beside the Take's time, on the same row: no height taken from the meters (#328).
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                elapsed(font: .system(size: 44, weight: .semibold))
                showTotal(font: .subheadline)
            }
            // One 44 pt row for the Show and its two lists (#240): big enough to hit, and no taller than the
            // two short lines it replaced, so the meters don't lose height.
            HStack(spacing: 4) {
                Button { showingNewShow = true } label: {
                    HStack(spacing: 4) {
                        Text(model.showSummary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                    .secondaryText()
                    .tapTarget()
                }
                .buttonStyle(.plain)
                .disabled(model.recorder.isRecording)
                .accessibilityHint("Opens the Show sheet")
                Spacer(minLength: 4)
                // 44 pt wide each, plus a clear gap, so "Shows" and "Names" read as two buttons.
                Button { showingShowList = true } label: { Text("Shows").tapTarget() }
                    .padding(.trailing, 12)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(model.recorder.isRecording)
                Button { open(.channelNames) } label: { Text("Names").tapTarget() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                if model.mixerGain.offersAutoGain {
                    Button { showingAutoGain = true } label: { Text("Gain").tapTarget() }
                        .padding(.leading, 12)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
                #if DEBUG && os(iOS)
                monitorButton.padding(.leading, 12)
                #endif
            }
            .font(.subheadline)
            // Top-aligned: Marker is taller (its count sits below), so centring would drop Record.
            HStack(alignment: .top, spacing: CGFloat(TransportLayout.gap(availableWidth: Double(transportWidth), buttonSize: 88))) {
                recordButton(size: 88)
                markerButton(size: 88)
            }
            // The line is always there, so a placed Marker doesn't push anything.
            Text(markerPlacedText)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .secondaryText()
                .id(model.recorder.takeMarkers.count)
        }
        .frame(maxWidth: .infinity)
        .background { GeometryReader { geometry in Color.clear.preference(key: TransportWidthKey.self, value: geometry.size.width) } }
        .onPreferenceChange(TransportWidthKey.self) { transportWidth = $0 }
        .animation(.easeInOut(duration: 0.15), value: model.recorder.takeMarkers.count)
    }

    #if DEBUG && os(iOS)
    /// Opens the headphone monitor experiment's sheet (#233), only while the experiment is Armed. In the Show row,
    /// so it takes no height from the meters. Debug builds only, never TestFlight (Eric, 2026-10-14): the `#if DEBUG`
    /// keeps it out of every Release build, unlike auto-gain's availability rule.
    @ViewBuilder private var monitorButton: some View {
        if MonitorExperiment.shared.isArmed {
            Button { showingMonitor = true } label: { Text("Mon").tapTarget() }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Monitor experiment")
        }
    }
    #endif

    private var markerPlacedText: String {
        // On Free a Take keeps 3 Markers (#705); a press past them places nothing, and this line says why.
        guard model.recorder.isRecording else { return " " }
        if model.stopHintShown { return "Hold to stop" }
        guard let last = model.recorder.takeMarkers.last else { return " " }
        if model.recorder.markerLimitReached { return "\(last.name) placed · \(Entitlement.freeMarkerLimit) per Take on Free" }
        return "\(last.name) placed"
    }

    /// Landscape transport: the Show and Take (with how long the Take has run) over Marker, then Record.
    /// Marker and Stop are kept well apart, since Marker is pressed often and Stop ends the Take.
    private var transportColumn: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Button { showingNewShow = true } label: {
                    HStack(spacing: 3) {
                        Text(model.recorder.currentShow?.name ?? "No Show yet")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                    .font(.caption)
                    .secondaryText()
                    .tapTarget()
                }
                .buttonStyle(.plain)
                .disabled(model.recorder.isRecording)
                .accessibilityHint("Opens the Show sheet")
                HStack(spacing: 4) {
                    Button { showingShowList = true } label: { Text("Shows").tapTarget() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .disabled(model.recorder.isRecording)
                    Button { open(.channelNames) } label: { Text("Names").tapTarget() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    if model.mixerGain.offersAutoGain {
                        Button { showingAutoGain = true } label: { Text("Gain").tapTarget() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }
                    #if DEBUG && os(iOS)
                    monitorButton
                    #endif
                }
                .font(.caption)
                // One line for the Take and how long it has run, so the 44 pt rows above still fit a short screen.
                HStack(spacing: 6) {
                    Text(model.takeTitle)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    elapsed(font: .title3)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let note = nonUrgentAlert {
                    Button {
                        if let action = note.action { model.perform(action) }
                    } label: {
                        Text(note.action == .dismissHint ? note.text + " Tap to dismiss." : note.text)
                            .font(.caption2)
                            .secondaryText()
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    .buttonStyle(.plain)
                    // On a short screen the note truncates, so the column never outgrows it (#645).
                    .layoutPriority(-1)
                    // The green Copy summary swipes away here too (#698); it comes back when its text changes.
                    .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { drag in
                        if abs(drag.translation.width) > 60, SwipedAlerts.isSwipeable(note) { model.swipe(note) }
                    })
                    .accessibilityActions { if SwipedAlerts.isSwipeable(note) { Button("Dismiss") { model.swipe(note) } } }
                }
            }
            // This spacer takes the slack and the note truncates first, so Marker and Record stay put when the note comes and goes.
            Spacer(minLength: 8)
            markerButton(size: 64)
            // The same 24 pt gap: the hint takes its place, so nothing moves and the meters keep their height.
            Text(model.stopHintShown ? "Hold to stop" : " ")
                .font(.caption).lineLimit(1).minimumScaleFactor(0.7).secondaryText().frame(height: 24)
                .accessibilityHidden(!model.stopHintShown)
            recordButton(size: 64)
        }
        .frame(width: 128)
    }

    /// How long the running Take has gone, counting up each second. Blank (but the same height) when no
    /// Take is running, so nothing moves when it appears.
    /// "Show 1:02:33": everything recorded in the open Show, counting the running Take each second. Nothing before
    /// the Show has any audio.
    @ViewBuilder private func showTotal(font: Font) -> some View {
        if let recorded = model.showRecordedSeconds {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let running = model.recorder.isRecording ? model.takeStartedAt.map { context.date.timeIntervalSince($0) } : nil
                let text = ElapsedTime.format(seconds: Int(recorded + (running ?? 0)))
                Text("Show \(text)")
                    .font(font.monospacedDigit())
                    .secondaryText()
                    .accessibilityLabel("Show total")
                    .accessibilityValue(text)
            }
        }
    }

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

    /// Opens the Marker list as a sheet, which never takes the record screen (and a running Take) away.
    private var markersButton: some View {
        Button { open(.markers) } label: {
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
                if compact {
                    // Landscape has no room beside the Take's time, so the Show's total joins the input line (#328).
                    HStack(spacing: 4) {
                        Text(model.compactInputSummary)
                        if model.showRecordedSeconds != nil { Text("·"); showTotal(font: .caption) }
                    }
                    .font(.caption)
                    .secondaryText()
                    .monospacedDigit()
                    .lineLimit(1)
                } else {
                    Text(model.inputSummary)
                        .font(.subheadline)
                        .secondaryText()
                        .monospacedDigit()
                        .lineLimit(1)
                }
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

/// The Audio interfaces this device offers: Core Audio on the Mac, the audio session on iOS, and the Demo signal.
struct AppInputDevices: InputDeviceSource {
    func devices() -> [DeviceChoice] { RecordScreenModel.availableDevices() }

    #if os(iOS)
    func currentRouteDevice(sampleRate: Int?) throws -> any AudioIODevice {
        #if DEBUG
        // The monitor experiment (#233) opens it with the plan chosen at Arm, so no category change mid-Take.
        try MonitorExperiment.shared.openForRouteMove(sampleRate: sampleRate)
        #else
        try SessionAudioDevice.current(sampleRate: sampleRate)
        #endif
    }
    #endif
}

@MainActor
@Observable
final class RecordScreenModel {
    /// Each Take goes to the Device and, when the Drive folder is connected at record time, the Drive.
    let recorder: Recorder
    /// Arms the chosen Audio interface and starts and stops Takes on the recorder.
    let sequencer: TakeSequencer
    /// The Drive folder and Device free space, kept current here so the status strip, Settings and the
    /// recorder share one state whether or not Settings is open.
    let drive: DriveFolderModel
    /// The Mixer Link as the app uses it (#556).
    let mixer: MixerSession
    /// The Mixer's address, remembered between launches by the Mixer session (#556).
    var mixerAddress: String {
        get { mixer.address }
        set { mixer.address = newValue }
    }
    /// Whether the system denied microphone access (shows a button that opens the system settings).
    private(set) var micDenied = false
    /// When the running Take started, for the elapsed time.
    var takeStartedAt: Date? { sequencer.takeStartedAt }
    #if os(iOS)
    /// The running Take in the Dynamic Island and on the Lock Screen.
    @ObservationIgnored private let liveActivity = TakeLiveActivity()
    /// The Apple Watch remote (#100).
    @ObservationIgnored private var watchLink: WatchLink?
    #endif
    /// Landscape: the transport column on the leading edge instead of the trailing one (left-handed).
    var transportLeading: Bool = UserDefaults.standard.bool(forKey: RecordScreenModel.transportLeadingKey)
    private static let transportLeadingKey = "transportLeading"
    /// The Pre-roll length in seconds (0 is Off), read when record is pressed. See `PreRollSetting`.
    var preRollSeconds: Double = PreRollSetting.load()
    /// Dark, Sunlight or System (the device's).
    var appearance: AppearanceMode = AppearanceMode.load()
    /// Battery and heat, shown as chips on the status strip.
    let power = PowerMonitor()
    /// Pro, the Trial and the Free channel choice (ADR 0004).
    let pro: ProStore
    /// When the app offers Pro (#62); what was offered is kept on the device.
    @ObservationIgnored private var proOffers = ProOffers()
    /// The paywall to show, when one is due. Never during a Take.
    var paywall: PaywallRequest?
    /// The Templates on this device (#33).
    var templates = TemplateStore()
    private(set) var setupHintDismissed = UserDefaults.standard.bool(forKey: RecordScreenModel.hintKey)
    private static let hintKey = "setupHintDismissed"
    var devices: [DeviceChoice] {
        get { sequencer.devices }
        set { sequencer.devices = newValue }
    }
    var selectedDeviceID: String? {
        get { sequencer.selectedDeviceID }
        set { sequencer.selectedDeviceID = newValue }
    }
    /// Whether the "Stop Take N?" question is showing. In the model so the Take menu can ask it too.
    var confirmingStop = false
    /// The "Hold to stop" hint after a tap on the hold button (#753).
    private(set) var stopHintShown = false
    private var stopHintTask: Task<Void, Never>?
    /// The level meters, in their own model: they change 30 times a second, and only the meter grid reads them.
    let meterModel = MeterModel()
    private(set) var armError: String? {
        get { sequencer.armError }
        set { sequencer.armError = newValue }
    }
    var recordError: String? { sequencer.recordError }
    /// The device as it was when last Armed, to tell a format change from a new device.
    private var armedDevice: InputDeviceInfo? {
        get { sequencer.armedDevice }
        set { sequencer.armedDevice = newValue }
    }
    /// The Armed interface's mixer family: X Air or X32, or nil for anything else (#365).
    var armedFamily: MixerFamily? { armedDevice.flatMap { MixerFamily(audioInterfaceName: $0.name) } }

    /// Mixer Link is offered only while an X Air or X32 is the Armed input (#365). Any other input (a built-in mic,
    /// the Demo signal, an EVO 4, a DJM) has no Mixer Link: Settings hides it, the strip has no Mixer chip and the
    /// Soundcheck skips it. A remembered Mixer stays saved and links again when an X Air or X32 is Armed.
    var offersMixerLink: Bool { mixer.isOffered }

    /// The Mixer's Sources while Mixer Link is offered; none otherwise, so another input's Stems never get the
    /// Mixer's names.
    var linkedSources: [Source] { mixer.sources }

    /// Gain on the Mixer (#554): auto-gain's state (#155), kept here, not in the sheet, so Undo survives closing it,
    /// locked during a Take; and clip protection (#448), only during a Take, only when switched on.
    let mixerGain = MixerGain()
    /// What auto-gain measures from (#554): every meter tick's windows, so it measures in audio time.
    let levelFeed = LevelFeed()
    /// Clip protection's switch in Settings (Debug and TestFlight builds), read when each Take starts. Off by default.
    var clipProtectionOn: Bool = ClipProtectionSetting.isOn() {
        didSet {
            ClipProtectionSetting.save(clipProtectionOn)
            if !clipProtectionOn { mixerGain.switchedOff() }
        }
    }

    /// Clip protection on the linked Mixer, at the rate the input runs at, logging each move in the Take with a
    /// Marker (#450), through `queue`, the one Mixer gain gives auto-gain too. Nil when the Mixer can't set gain.
    private func makeClipProtection(queue: MixerQueue) -> ClipProtection? {
        guard mixer.gainControl != nil, let rate = recorder.sampleRate else { return nil }
        // The gain control at each move, only while Mixer Link is offered and on the Mixer the Take started on
        // (#554, as #508): a new input mid-Take means nothing is written to the old Mixer (#589).
        return ClipProtection(currentControl: { [weak self] in self?.mixer.gainControl }, mixer: { [weak self] in self?.linkedMixer },
                              sampleRate: Double(rate), queue: queue, log: { [weak self] change in self?.recorder.logGainChange(change) })
    }

    /// The one listener to the sequencer's events (an AsyncStream takes one, and ending it ends the stream), for the
    /// model's whole life. Whatever follows Takes is told from here.
    private func followTakes() {
        let events = sequencer.events
        Task { [weak self] in
            for await event in events {
                self?.mixerGain.handle(event)
                #if DEBUG && os(iOS)
                if case .disarmed = event { MonitorExperiment.shared.disarmed() }
                // An interruption's restart reuses the input without `didArm`; the output unit iOS stopped needs a restart.
                if case .inputRestarted = event { MonitorExperiment.shared.inputRestarted() }
                #endif
                // A disarm hides the Mixer Link at once, whatever the screen does (#556); a re-Arm that got there first wins.
                if case .disarmed = event {
                    Task { guard let self, !self.recorder.isArmed else { return }; await self.mixer.armed(interfaceName: nil, usbChannelCount: 0) }
                }
                // Whoever started or ended the Take: Stop, the watch, or the recorder itself (#551).
                guard let self else { return }
                let followUp = TakeFollowUp(event)
                if followUp.contains(.liveActivity) { followLiveActivity() }
                if followUp.contains(.proOffer) { offerProAfterTake() }
            }
        }
    }

    /// A new auto-gain session on the linked Mixer, measuring with the record screen's own meters. Every gain change it
    /// makes or undoes is logged in the Show (#450).
    /// The linked Mixer as auto-gain tells Mixers apart, "FOH · XR18": its network name and model, so two desks both
    /// named FOH aren't one. Nil while the Mixer Link is down or isn't offered.
    var linkedMixer: String? {
        mixer.identity.map { "\($0.networkName) · \($0.model)" }
    }

    func makeAutoGainSession(queue: MixerQueue) -> AutoGainSession? {
        guard mixer.gainControl != nil else { return nil }
        // The Mixer Link's gain control at each step, so a reconnect's new driver is used, Undo included (#508).
        return AutoGainSession(currentControl: { [weak self] in self?.mixer.gainControl },
                               mixer: { [weak self] in self?.linkedMixer }, measure: { [weak self] usb in await self?.levelFeed.measure(usbChannel: usb) },
                               queue: queue, log: { [weak self] change in self?.recorder.logGainChange(change) })
    }

    /// "Kick", or "USB 03" when the channel has no name.
    func channelLabel(_ usbChannel: Int) -> String {
        recorder.naming.displayName(usbChannel, sources: linkedSources)
    }
    /// The Take's Copies (#550), refreshed about once a second.
    private var takeCopies = TakeCopies.none
    /// The Copies as last refreshed; when a Take has started or stopped since, the Recorder's own straight away.
    var copies: TakeCopies { takeCopies.current(isRecording: recorder.isRecording, recorder.copies) }
    /// The Drive stopped and Check Drive found nothing, until it comes back.
    private var driveCheckedAndNotFound = false
    private var driveRejoin = DriveRejoinNotice()

    /// How each Copy of the last Take stands, shown once recording has stopped.
    var copySummary: (text: String, isProblem: Bool)? {
        if recorder.isRecording { return nil }
        if recorder.isRepairing { return ("Repairing Gaps from the other Copy…", false) }
        guard let summary = CopySummary.ofLastTake(recorder.copies, dropoutCount: recorder.dropoutCount) else { return nil }
        return (summary.text, summary.isProblem)
    }

    /// What the record screen showed at the last check, for VoiceOver announcements.
    @ObservationIgnored private var announced: ScreenAnnouncements.State?

    /// Tells VoiceOver about a new alert, clip or Dropout, once, when it happens (#249). Checked about once a second.
    private func announceChanges() {
        let now = ScreenAnnouncements.State(clipped: recorder.clippedChannels, alerts: alerts.ordered, dropoutCount: recorder.dropoutCount)
        for text in ScreenAnnouncements.changes(from: announced, to: now) {
            AccessibilityNotification.Announcement(text).post()
        }
        announced = now
    }

    /// Refreshes the Copy statuses, and says why a Take the recorder ended on its own stopped.
    /// The Recorder checks its Destinations itself while recording.
    /// Everything recorded in the open Show before the running Take, from its files; nil when there is no Show or it
    /// has no audio yet. Read only when the Show or its Take count changes, not every second (#328).
    private(set) var showRecordedSeconds: Double?
    @ObservationIgnored private var showRecordedKey: String?

    private func refreshShowTotal() {
        let show = recorder.currentShow
        // The Drive's coming and going is in the key: a relaunch before the SSD mounts re-reads the total once it does (#625).
        let driveAvailable = if case .available = drive.status { true } else { false }
        let key = show.map { "\($0.folder.path)|\($0.takeCount)|\(recorder.isRecording)|\(driveAvailable)" }
        guard key != showRecordedKey else { return }
        showRecordedKey = key
        // A running Take's own files are already on disk; leave it out, the screen adds its live time.
        guard let show, let seconds = recorder.showRecordedSeconds(leavingOut: recorder.isRecording ? show.takeCount : nil) else {
            showRecordedSeconds = nil
            return
        }
        showRecordedSeconds = seconds > 0 || recorder.isRecording ? seconds : nil
    }

    private func refreshDestinations() {
        refreshShowTotal()
        takeCopies = recorder.copies
        if takeCopies[.drive] != .interrupted { driveCheckedAndNotFound = false }
        driveRejoin.update(copies: takeCopies)
        followLiveActivity()
    }

    /// Starts, updates or ends the Live Activity to match the running Take. The sequencer's events call it at each start,
    /// Marker and end (#551); the per-second refresh keeps its problems current.
    func followLiveActivity() {
        #if os(iOS)
        let take = recorder.isRecording ? takeStartedAt.flatMap { started in
            recorder.currentShow.map {
                TakeActivityContent(showName: $0.name, takeTitle: takeTitle, startedAt: started,
                                    markerCount: recorder.takeMarkers.count, problems: liveActivityProblems,
                                    showsMarkerButton: MarkerButtonAvailability.isAvailableInThisBuild,
                                    markerLimitReached: recorder.markerLimitReached,
                                    markerLimit: Entitlement.freeMarkerLimit)
            }
        } : nil
        liveActivity.follow(take)
        #endif
    }

    /// Just the Armed device's name, for the one-line landscape header.
    var compactInputSummary: String {
        recorder.isArmed ? (armedDevice?.name ?? "Audio interface") : "No audio interface"
    }

    /// The Armed device's name and channel count, for the header.
    var inputSummary: String {
        guard recorder.isArmed else { return recordBlock?.text ?? "Choose the Mixer's audio interface in Settings" }
        let name = armedDevice?.name ?? "Audio interface"
        return "\(name) · \(usbChannelSummary)"
    }

    /// Why Record is dimmed, when it is, and what to offer.
    var recordBlock: RecordAvailability.Block? {
        RecordAvailability.block(
            isArmed: recorder.isArmed, isRecording: recorder.isRecording, micDenied: micDenied,
            armFailed: armError != nil && !micDenied, disarmedForIdle: disarmedForIdle, hasInputs: !devices.isEmpty)
    }

    /// The status strip: Device and Drive time left, and the Mixer Link.
    var chips: [StatusChip] {
        StatusChip.make(
            usbChannelCount: recorder.usbChannelCount,
            deviceAvailableBytes: drive.deviceAvailableBytes,
            drive: drive.status,
            mixer: mixer.state,
            copies: copies,
            sampleRate: recorder.sampleRate ?? 48_000,
            driveAllowed: pro.license().allowsDrive)
    }

    /// Everything the record screen has to say, most urgent first, but the warnings and green summaries swiped away (#644, #698); it shows one
    /// and counts the rest.
    var alerts: AlertQueue { AlertQueue(swipedAlerts.showing(raisedAlerts)) }

    /// Warnings and green summaries the operator swiped away, until their message changes or their problem clears.
    private var swipedAlerts = SwipedAlerts()

    func swipe(_ alert: ScreenAlert) { swipedAlerts.swipe(alert) }

    /// Checked about once a second: a swiped warning whose problem has cleared shows again if it comes back.
    private func forgetClearedSwipes() {
        var swiped = swipedAlerts
        swiped.forget(absentFrom: raisedAlerts)
        if swiped != swipedAlerts { swipedAlerts = swiped }
    }

    private var raisedAlerts: [ScreenAlert] {
        var list: [ScreenAlert] = []
        if let error = armError {
            list.append(ScreenAlert(id: "arm", priority: .cannotRecord, tone: .critical, text: error, action: micDenied ? .openSystemSettings : .arm))
        } else if disarmedForIdle, let block = recordBlock {
            list.append(ScreenAlert(id: "idle", priority: .cannotRecord, tone: .warning, text: block.text, action: block.action))
        }
        if let error = recordError {
            list.append(ScreenAlert(id: "record", priority: .cannotRecord, tone: .critical, text: error))
        }
        if let alert = DestinationAlert.make(copies: copies, checkedAndNotFound: driveCheckedAndNotFound) {
            list.append(alert)
        }
        if let rejoined = driveRejoin.alert { list.append(rejoined) }
        if let shortfall = usbChannelShortfall {
            list.append(ScreenAlert(id: "shortfall", priority: .input, tone: .warning, text: shortfall.message))
        }
        if let notice = interruptions.notice {
            list.append(ScreenAlert(id: "interruption", priority: .input, tone: .warning, text: notice))
        }
        // A re-patch on the Mixer during the Take (#21), until the Take ends or the operator has seen it.
        let routing = recorder.routingChanges
        if recorder.isRecording, routingChangeSeen?.take != takeNumber || routingChangeSeen?.changes != routing,
           let text = recorder.routingNotice {
            list.append(ScreenAlert(id: "routing", priority: .input, tone: .warning, text: text, action: .dismissRoutingChange))
        }
        list += power.status.alerts
        if let summary = copySummary, !recorder.isRecording {
            list.append(ScreenAlert(id: "copies", priority: .copyResult, tone: summary.isProblem ? .warning : .ok, text: summary.text))
        }
        // Drive only Takes moving to the Drive (#630), where Drive only is offered; tap for each Take and why one stays.
        if let alert = recorder.moveReport.alert(isOffered: recorder.movesDriveOnlyTakes, isRecording: recorder.isRecording) {
            list.append(alert)
        }
        if showSetupHint {
            list.append(ScreenAlert(id: "hint", priority: .hint, tone: .info, text: offersMixerLink ? "Choose the audio interface, Drive and Mixer in Settings (the gear)." : "Choose the audio interface and Drive in Settings (the gear).", action: .dismissHint))
        }
        // Offered once, as a banner rather than a sheet, so it never stacks on another first-launch sheet (#63).
        if Soundcheck.shouldOffer(alreadyOffered: soundcheckOffered, isRecording: recorder.isRecording, setupHintShowing: showSetupHint) {
            list.append(ScreenAlert(id: "soundcheck", priority: .hint, tone: .info, text: "Check your rig with a 30 s Soundcheck.", action: .soundcheck))
        }
        return list
    }

    /// Whether the Soundcheck has been offered (opened once from the banner or Settings).
    var soundcheckOffered = UserDefaults.standard.bool(forKey: RecordScreenModel.soundcheckOfferedKey) {
        didSet { UserDefaults.standard.set(soundcheckOffered, forKey: Self.soundcheckOfferedKey) }
    }
    private static let soundcheckOfferedKey = "soundcheckOffered"
    /// The Soundcheck sheet over the record screen.
    var showingSoundcheck = false
    /// What the latest move to the Drive did, Take by Take (#630).
    var showingMoves = false

    /// Runs the Soundcheck with what the Mixer Link and the Drive know right now.
    func runSoundcheck(progress: (Soundcheck.Step.Kind) -> Void, result: (Soundcheck.Step) -> Void) async -> [Soundcheck.Step] {
        await Soundcheck.run(
            sequencer: sequencer, mixer: mixer.state, sources: linkedSources,
            expectedUSBChannels: mixer.capabilities?.usbChannelCount, driveChosen: drive.status != .notChosen,
            allowance: currentAllowance(), progress: progress, result: result)
    }

    /// A first-run nudge, once: neither a Drive nor a Mixer is set up yet.
    private var showSetupHint: Bool {
        !setupHintDismissed && !recorder.isRecording && drive.status == .notChosen && mixerAddress.isEmpty
    }

    /// The routing changes the operator dismissed the warning at, in which Take: a later re-patch, or the next
    /// Take's, warns again.
    private var routingChangeSeen: (take: Int, changes: [TakeMetadata.RoutingChange])?

    func perform(_ action: ScreenAlert.Action) {
        switch action {
        case .openSystemSettings: openSystemSettings()
        case .dismissHint:
            setupHintDismissed = true
            UserDefaults.standard.set(true, forKey: Self.hintKey)
        case .arm:
            // Arm only: never starts a Take.
            sequencer.armAgain()
        case .soundcheck:
            showingSoundcheck = true
        case .dismissRoutingChange:
            routingChangeSeen = (takeNumber, recorder.routingChanges)
        case .showMoves:
            showingMoves = true
        case .checkDrive:
            // Look again now, and say so if it's still not there.
            drive.refresh()
            recorder.checkDestinations()
            refreshDestinations()
            driveCheckedAndNotFound = takeCopies[.drive] == .interrupted
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
            Task { await mixer.retry() }
        }
    }

    func connectMixer() {
        Task { await mixer.connect() }
    }

    /// What to do about audio interruptions, and the banner they leave. The `TakeSequencer` keeps it.
    var interruptions: InterruptionPolicy { sequencer.interruptions }

    init() {
        let drive = DriveFolderModel()
        let store = drive.store
        self.drive = drive
        let recorder = Recorder(driveFolder: {
            store.beginAccess()
        }, preRollSeconds: PreRollSetting.load())
        self.recorder = recorder
        let pro = ProStore()
        self.pro = pro
        // The screenshot build Arms only demo inputs, never a microphone or USB interface (#374).
        let inputs: any InputDeviceSource = DemoOnlyInputSource.isScreenshotBuild() ? DemoOnlyInputSource(AppInputDevices()) : AppInputDevices()
        sequencer = TakeSequencer(recorder: recorder, devices: inputs, capsAt48k: { pro.license().capsAt48k })
        mixer = MixerSession()
        sequencer.sampleRateChoice = {
            #if os(macOS)
            SampleRateSetting.load(platformDefault: nil)
            #else
            SampleRateSetting.load(platformDefault: 48_000)
            #endif
        }()
        sequencer.log = { line in Self.sessionLog.notice("\(line, privacy: .public)") }
        mixerGain.makeSession = { [weak self] queue in self?.makeAutoGainSession(queue: queue) }
        mixerGain.isRecording = { [weak self] in self?.recorder.isRecording ?? false }
        mixerGain.mixer = mixer
        mixerGain.mixerName = { [weak self] in self?.linkedMixer }
        mixerGain.makeProtection = { [weak self] queue in self?.makeClipProtection(queue: queue) }
        mixerGain.takeAllowance = { [weak self] in self?.recorder.takeAllowance }
        mixerGain.allowsAutoGain = { [weak self] in self?.pro.license().allowsAutoGain ?? true }
        followTakes()
        sequencer.didArm = { [unowned self] device in
            #if DEBUG && os(iOS)
            MonitorExperiment.shared.armed(device)
            #endif
            if let device {
                noteOfferedChannels(of: device)
                #if os(iOS)
                // The route's name and channels are only known once the session is active.
                devices = Self.availableDevices()
                if !devices.contains(where: { $0.id == selectedDeviceID }) { selectCurrentRouteInput() }
                #endif
            }
            meterModel.reset(channelCount: recorder.usbChannelCount)
            // The Mixer session hears of each Armed input from the model, at launch and after, even with the screen
            // locked (#556): it re-reads the Sources for a new USB Channel count and links a remembered Mixer when an
            // X Air or X32 is Armed (#365).
            let name = device == nil ? nil : armedDevice?.name, count = device == nil ? 0 : recorder.usbChannelCount
            Task { await mixer.armed(interfaceName: name, usbChannelCount: count) }
        }
        #if os(iOS)
        watchLink = WatchLink(status: { [unowned self] in watchStatus }, actions: watchActions)
        watchLink?.start()
        // The Live Activity's Marker button (#684): the same path as the watch's Marker. Past the Free limit it places
        // nothing, and the button says why.
        MarkerDesk.shared.place = { [weak self] in
            guard let self, recorder.isRecording, !recorder.markerLimitReached else { return false }
            let before = recorder.takeMarkers.count
            sequencer.addMarker()
            return recorder.takeMarkers.count > before
        }
        #endif
        // `-demoSignal` starts on the 18-channel demo signal, for screenshots and layout checks.
        if launchFlag("-demoSignal"), devices.contains(where: { $0.id == "demo" }) { selectedDeviceID = "demo" }
        if launchFlag("-demoStems"), devices.contains(where: { $0.id == "demo-stems" }) { selectedDeviceID = "demo-stems" }
    }

    /// "2026-10-06 Show · Take 02", or a hint before the first Take.
    var showSummary: String {
        guard let show = recorder.currentShow else { return "Press record to start a Show" }
        return "\(show.name) · \(takeTitle)"
    }

    /// The running (or last) Take's number in the Show.
    private var takeNumber: Int { recorder.currentShow?.takeCount ?? 0 }

    var takeTitle: String {
        TakeMetadata.name(take: recorder.currentShow?.takeCount ?? 0)
    }

    func record() {
        // Freeze whatever the Mixer Link knows right now, and what the tier allows, into the Take (Show-Safe
        // Promise: judged only here, never during the Take).
        guard sequencer.record(sources: linkedSources, allowance: currentAllowance()) else { return }
        followLiveActivity()
    }

    func appearanceChanged() { appearance.save() }

    func saveTransportSide() {
        UserDefaults.standard.set(transportLeading, forKey: Self.transportLeadingKey)
    }

    func stop() {
        clearStopHint()
        sequencer.stop()
    }

    func clearStopHint() {
        stopHintTask?.cancel()
        stopHintShown = false
    }

    /// "Hold to stop" for two seconds after a tap on the hold button (#753).
    func showStopHint() {
        stopHintShown = true
        stopHintTask?.cancel()
        stopHintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.stopHintShown = false }
        }
    }

    /// After a Take: a Free Take that went to the Device only with a Drive connected, a Free Take whose Stems got
    /// generic names while the Mixer had names (#705), or the Trial's last days (#62).
    private func offerProAfterTake() {
        let show = recorder.currentShow?.name
        let license = pro.license()
        let driveConnected = if case .available = drive.status { true } else { false }
        let onDevice = show.flatMap {
            proOffers.afterTakeOnDevice(show: $0, license: license, isRecording: recorder.isRecording, driveConnected: driveConnected)
        }
        let mixerNamed = linkedSources.contains { $0.hasMixerName }
        let moment = onDevice
            ?? show.flatMap { proOffers.afterTakeStopped(show: $0, license: license, isRecording: recorder.isRecording, mixerNamed: mixerNamed) }
            ?? proOffers.betweenTakes(show: show, license: license, isRecording: recorder.isRecording)
        if let moment { offerPro(moment) }
    }

    /// Opens the paywall for `moment` (nil: from Settings), once whatever sheet is closing has gone.
    func offerPro(_ moment: ProOfferMoment?) {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !recorder.isRecording else { return }
            paywall = PaywallRequest(moment: moment)
        }
    }

    // MARK: - Auto-disarm

    /// Whether the recorder was disarmed for sitting idle, so coming back should Arm it again.
    var disarmedForIdle: Bool { sequencer.disarmedForIdle }

    /// The screen locked or the app left the front: start counting idle time.
    func screenBecameIdle() {
        sequencer.appMovedToBackground()
    }

    /// The app is in front again: stop counting, and Arm again if it was disarmed for being idle.
    func screenBecameActive() {
        sequencer.appBecameActive()
    }

    /// Chips after the Destination and Mixer ones: a Dropout count when the Take has lost audio, then battery and heat.
    var extraChips: [PowerStatus.Chip] {
        let dropouts = recorder.dropoutCount
        let chip = dropouts > 0
            ? [PowerStatus.Chip(text: dropouts == 1 ? "1 Dropout" : "\(dropouts) Dropouts", shortText: "\(dropouts)", symbol: "waveform.badge.exclamationmark", state: .attention)]
            : []
        let trial = pro.license().chip.map { [$0] } ?? []
        return chip + power.status.chips + trial
    }

    /// Ends the open Show. Returns what to tell the operator, or nil when it ended.
    func endShow() -> String? {
        let ending = recorder.currentShow
        do {
            try sequencer.endShow()
            if let ending, let moment = proOffers.afterShowEnded(
                show: ending.name, takeCount: ending.takeCount, license: pro.license()) {
                offerPro(moment)
            }
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
            try sequencer.startNewShow(name: name, venue: venue)
            return nil
        } catch RecorderError.takeRunning {
            return "A Show can't be started during a Take."
        } catch {
            return "The Show couldn't be created: \(error.localizedDescription)"
        }
    }

    /// Whether Templates can be used now: between Takes, and on Pro or the Trial once Pro is offered.
    var templateAccess: TemplateAccess {
        pro.license().templateAccess(isRecording: recorder.isRecording)
    }

    /// Saves this setup as a Template named `name`: the typed channel names, the open Show's venue, the Pre-roll and
    /// the Mixer (its network name, when linked, and its address).
    func saveTemplate(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        templates.save(Template(
            name: name, venue: recorder.currentShow?.venue, channelNames: recorder.channelNames,
            mixerNetworkName: mixer.networkNameForTemplates, mixerAddress: mixerAddress,
            preRollSeconds: preRollSeconds))
    }

    /// Starts a Show from `template`: its name, venue and channel names, its Pre-roll, and its Mixer. The Show starts
    /// at once; the Mixer is connected after, and looked for by its network name when the saved address doesn't
    /// answer or another mixer is there. Returns what to tell the operator, or nil when the Show started.
    func startShow(from template: Template) -> String? {
        guard templateAccess == .usable else { return templateAccess.note }
        do {
            try sequencer.startNewShow(from: template)
        } catch RecorderError.takeRunning {
            return "A Show can't be started during a Take."
        } catch {
            return "The Show couldn't be created: \(error.localizedDescription)"
        }
        if preRollSeconds != template.preRollSeconds {
            preRollSeconds = template.preRollSeconds
            preRollChanged()
        }
        if !template.mixerAddress.isEmpty || template.mixerNetworkName != nil {
            Task { await connectMixer(for: template) }
        }
        return nil
    }

    /// The known tier changed (the App Store answered, a purchase, a refund): re-Arm between Takes if the rate the
    /// input may run at changed (#316). A Take that's running keeps its rate; the change applies at the next Arm.
    private func tierChanged() {
        sequencer.tierChanged()
    }

    /// At launch with no Show open: the default Template readies the next Show (its channel names now, its name when
    /// record starts it), and sets its Pre-roll and Mixer (#34).
    func applyDefaultTemplate() {
        guard templateAccess == .usable, let template = templates.defaultTemplate,
              sequencer.prepareNextShow(from: template) else { return }
        if preRollSeconds != template.preRollSeconds {
            preRollSeconds = template.preRollSeconds
            preRollChanged()
        }
        if !template.mixerAddress.isEmpty || template.mixerNetworkName != nil {
            Task { await connectMixer(for: template) }
        }
    }

    /// Saves a past Show's setup as a Template named `name`: its channel names and venue, with today's Pre-roll and
    /// Mixer (#34). Returns what to tell the operator, or nil when it was saved.
    func saveTemplate(fromShow folder: URL, named name: String) -> String? {
        guard var template = Template.fromShow(
            folder: folder, mixerNetworkName: mixer.networkNameForTemplates,
            mixerAddress: mixerAddress, preRollSeconds: preRollSeconds) else { return "This Show's setup couldn't be read." }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { template.name = name }
        templates.save(template)
        return nil
    }

    /// The name a Template from this past Show starts with: the Show's, without the date.
    func templateName(forShow folder: URL) -> String {
        Template.fromShow(folder: folder, mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0)?.name ?? ""
    }

    private func connectMixer(for template: Template) async {
        // A Template's Mixer stays in it; it links only when the input is an X Air or X32 (#365).
        await mixer.follow(mixerAt: template.mixerAddress, named: template.mixerNetworkName)
    }

    /// Renames a Marker in the list, during the Take or after it. Returns what to tell the operator, or nil when
    /// every Copy has the new name.
    func renameMarker(_ entry: MarkerEntry, to name: String) async -> String? {
        guard let index = entry.operatorIndex else { return "Only your own Markers can be renamed." }
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
            let problems = outcome.failed.map { "\($0.copy == .drive ? "The Drive" : "The Device") Copy still has the old name: \($0.reason)" }
            if outcome.result == .noCopyUpdated { return "Couldn't rename it. " + problems.joined(separator: " ") }
            return problems.isEmpty ? nil : problems.joined(separator: " ")
        }
    }

    /// The Pre-roll length changed in Settings: keep it, give it to the recorder, and, if Armed, Arm again so
    /// the buffer is sized for it. That only happens between Takes (Settings is locked during one).
    func preRollChanged() {
        PreRollSetting.save(preRollSeconds)
        recorder.preRollSeconds = preRollSeconds
        sequencer.settingsChanged()
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

    /// What a Take pressed right now may do: the tier, the Free channel choice and the Armed USB Channels; nil
    /// (nothing limited) while Pro isn't offered. Read from cached state only, never waiting on the App Store, so it
    /// can be frozen at the record press.
    func currentAllowance() -> TakeAllowance? {
        pro.license().allowance(channelCount: recorder.usbChannelCount)
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
            mixer: mixer.identity, capabilities: mixer.capabilities)
    }

    /// Notes what the system offered for `device`, after it was Armed or took over input.
    func noteOfferedChannels(of device: any AudioIODevice) {
        #if os(iOS)
        offeredChannelCount = (device as? SessionAudioDevice)?.maximumInputChannelCount
        #if DEBUG
        // The monitor experiment (#233) wraps the input in a `MonitorTap`.
        if device is MonitorTap { offeredChannelCount = MonitorExperiment.shared.sessionDevice?.maximumInputChannelCount }
        #endif
        #else
        offeredChannelCount = nil
        #endif
    }

    // MARK: - The loop that outlives the screen

    @ObservationIgnored private var loop: Task<Void, Never>?

    /// Starts the loop that protects and shows a Take: it Arms the input, polls the meters, looks for a Drive
    /// joining or space running low, keeps the Mixer Link and follows route changes. It belongs to the model,
    /// not the screen, so it keeps running (and keeps a Take safe) when the screen is torn down or rebuilt.
    /// Calling it again does nothing.
    func start() {
        guard loop == nil else { return }
        loop = Task { await run() }
        pro.onTierChange = { [weak self] in self?.tierChanged() }
        applyDefaultTemplate()
        Task { await offerDemoSignalIfAvailable() }
        Task { await offerDriveOnlyMovesIfAvailable() }
        // `-demoDrive` (screenshots) uses a folder in the app's own container as the Drive, so the shots show a second
        // Copy instead of a "No Drive" warning.
        // Both touch the container's data (the Drive bookmark, saved names), so they act only in the screenshot build,
        // whose bundle ID ends in ".screens": never in the real app's container.
        let isScreenshotBuild = DemoOnlyInputSource.isScreenshotBuild()
        if launchFlag("-demoDrive"), isScreenshotBuild {
            let folder = URL.documentsDirectory.appending(path: "Show SSD", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            drive.choose(folder)
        }
        // `-demoNames` names the Demo signal's channels like a band's, for screenshots (typed names, in that Show only).
        if launchFlag("-demoNames"), isScreenshotBuild {
            Task {
                try? await Task.sleep(for: .seconds(1))
                var names = Self.demoChannelNames
                #if DEBUG
                if let folder = DemoStemsDevice.folder, let layout = DemoStemsDevice.layout(of: folder) { names = layout.channelNames }
                #endif
                for (index, name) in names.enumerated() { recorder.setChannelName(name, forChannel: index + 1) }
            }
        }
        // `-demoRecord` starts a Take once Armed, for screenshots (the iOS ones in the Simulator too). With `-demoSignal`
        // or `-demoStems`, only once a demo input is Armed, never a microphone a slow launch may Arm first.
        if launchFlag("-demoRecord") {
            Task {
                for _ in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard recorder.isArmed, !recorder.isRecording else { continue }
                    if launchFlag("-demoSignal") || launchFlag("-demoStems"), armedDevice?.id.hasPrefix("demo") != true { continue }
                    record()
                    return
                }
            }
        }
    }

    /// The names `-demoNames` types: a band's input list, no people's names.
    static let demoChannelNames = ["Kick", "Snr", "Hat", "Tom 1", "Tom 2", "OH L", "OH R", "Bs", "Gtr 1", "Gtr 2",
                                   "Key 1", "Key 2", "Vox", "BV 1", "BV 2", "BV 3", "PB", "Clk"]

    /// The Demo signal needs StoreKit's answer (TestFlight or not), which arrives later; the input list
    /// starts without it and gets it here. Only adds an input: the selection and an armed device stay.
    private func offerDemoSignalIfAvailable() async {
        // A Debug build offers it without StoreKit's answer, which can come late on a busy Mac.
        if !DemoSignalAvailability.isAvailableInThisBuild { await DemoSignalAvailability.resolveEnvironment() }
        guard DemoSignalAvailability.isAvailableInThisBuild, !devices.contains(where: { $0.id == "demo" }) else { return }
        devices = Self.availableDevices()
        // `-demoSignal` (Debug, screenshots): when StoreKit answered after the first Arm, switch to the Demo signal now,
        // so a slow launch doesn't leave the built-in microphone Armed.
        if launchFlag("-demoSignal"), selectedDeviceID != "demo", !recorder.isRecording {
            selectedDeviceID = "demo"
            selectionDidChange()
        }
    }

    /// The screen appeared again: Arm if nothing is, never over a running Take.
    func screenAppeared() {
        sequencer.screenAppeared()
    }

    /// The screen went away: disarm an unused recorder, never a running Take.
    func screenDisappeared() {
        sequencer.screenDisappeared()
    }

    /// Drive only Takes move to the Drive (#630) where Drive only is offered, which needs StoreKit's answer in a Release
    /// build. Turning it on moves any the Drive can take now; the Recorder then does after each Take, and
    /// `driveBecameAvailable` when the Drive connects.
    private func offerDriveOnlyMovesIfAvailable() async {
        if !DriveOnlyAvailability.isAvailableInThisBuild { await DemoSignalAvailability.resolveEnvironment() }
        recorder.movesDriveOnlyTakes = DriveOnlyAvailability.isAvailableInThisBuild
    }

    private func run() async {
        defer { loop = nil }
        guard await hasMicrophonePermission() else {
            micDenied = true
            armError = "ShowRecorder needs microphone access to record your mixer. Allow it in the system's Privacy settings, under Microphone."
            return
        }
        drive.refresh()
        sequencer.start()
        #if os(iOS)
        let routeWatcher = Task { await watchRouteChanges() }
        defer { routeWatcher.cancel() }
        let sessionWatcher = Task { await watchAudioSession() }
        defer { sessionWatcher.cancel() }
        #if DEBUG
        let monitorRouteLog = Task { await MonitorExperiment.shared.watchRoutes() }
        defer { monitorRouteLog.cancel() }
        #endif
        #endif
        #if os(macOS)
        let deviceWatcher = Task { await watchDeviceChanges() }
        defer { deviceWatcher.cancel() }
        #endif
        var tick = 0
        var lastPoll = ContinuousClock.now
        while !Task.isCancelled {
            tick += 1
            if tick % 30 == 0 { sequencer.tick(); refreshDestinations(); announceChanges(); forgetClearedSwipes() }
            // Re-check the Drive every few seconds so an unplugged one shows before record is pressed.
            if tick % 90 == 0 { drive.refresh() }
            let now = ContinuousClock.now
            let seconds = min(max((now - lastPoll).inSeconds, 0.001), 0.25)
            lastPoll = now
            let fresh = recorder.takeChannelLevels()
            meterModel.update(from: fresh, seconds: seconds)
            // Clip protection reads the same windows at once; a move runs on its own, so it never holds up the meters.
            mixerGain.meters(fresh)
            levelFeed.meters(fresh, sampleRate: recorder.sampleRate)
            try? await Task.sleep(for: .milliseconds(33))
        }
        // No more ticks: a measurement under way ends rather than waiting for audio that won't come.
        levelFeed.meters([], sampleRate: nil)
    }

    /// The picker changed. Skips the device the model has just Armed itself after a device change.
    func selectionDidChange() {
        sequencer.select(selectedDeviceID)
    }

    func armSelectedDevice() {
        sequencer.arm()
    }

    private func hasMicrophonePermission() async -> Bool {
        if launchFlag("-autoGainDemo") { return false }  // screenshots of sample results: no prompt over the sheet
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return true  // macOS asks on first input; the sandbox entitlement allows it.
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
            sequencer.routeChanged()
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

    /// Re-reads the device list; the `TakeSequencer` keeps, switches, re-Arms or disarms as `InputDeviceChange` decides.
    private func applyDeviceListChange() {
        sequencer.deviceListChanged()
    }
    #endif

    /// iOS can't list a route's rates before it runs, so the picker offers these and iOS picks the nearest it can;
    /// a mixer's input keeps the mixer's rate.
    private static let sessionSampleRates = [44_100, 48_000, 96_000]

    /// The rate to ask iOS for: the choice, at most 48 kHz when capped; nil asks for nothing.
    private static func sessionRate(_ chosen: Int?, capAt48k: Bool) -> Int? {
        guard let chosen else { return nil }
        return capAt48k ? min(chosen, 48_000) : chosen
    }

    /// The sample rate choice (#195): nil is the interface's own rate, the Mac's default; iPhone and iPad default to
    /// 48 kHz, which the app has always asked iOS for.
    var sampleRateChoice: Int? {
        get { sequencer.sampleRateChoice }
        set { sequencer.sampleRateChoice = newValue }
    }

    /// The rate choice changed in Settings: keep it and, if Armed, Arm again at it. Settings is locked during a Take.
    func sampleRateChanged() {
        SampleRateSetting.save(sampleRateChoice)
        sequencer.settingsChanged()
    }

    /// What the rate picker offers for the selected input: "Interface" and each rate it offers, or just "Interface"
    /// when it offers one (a mixer).
    var sampleRateChoices: [Int?] {
        SampleRateSetting.choices(available: devices.first { $0.id == selectedDeviceID }?.availableSampleRates ?? [])
    }

    static func availableDevices() -> [DeviceChoice] {
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
                availableSampleRates: device.availableSampleRates,
                make: { chosen, capAt48k in
                    guard let rate = SampleRateSetting.rateToSet(
                        chosen: chosen, available: device.availableSampleRates,
                        current: Int(device.sampleRate.rounded()), capAt48k: capAt48k) else { return device }
                    return try CoreAudioDevice.settingSampleRate(rate, of: device)
                }))
        }
        for info in InputDeviceInfo.preferredOrder(macChoices.map(\.info), defaultID: defaultChoiceID) {
            if let choice = macChoices.first(where: { $0.id == info.id }) { choices.append(choice) }
        }
        #endif
        #if os(iOS)
        // Every input iOS can see, USB interfaces first, so one that isn't the current route can be chosen.
        let session = AVAudioSession.sharedInstance()
        // Inputs are only listed for a recording category; this doesn't activate the session. Play-and-record (the
        // Debug headphone monitor experiment, #233) records too, and resetting it would cut the monitor off.
        if ![.record, .playAndRecord].contains(session.category) { try? session.setCategory(.record, mode: .measurement, options: []) }
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
                availableSampleRates: Self.sessionSampleRates,
                make: { chosen, capAt48k in
                    #if DEBUG
                    try MonitorExperiment.shared.openForArm(preferredInputUID: uid, sampleRate: Self.sessionRate(chosen, capAt48k: capAt48k))
                    #else
                    try SessionAudioDevice.current(preferredInputUID: uid, sampleRate: Self.sessionRate(chosen, capAt48k: capAt48k))
                    #endif
                }))
        }
        if ports.isEmpty {
            // Nothing listed yet (the session isn't active): offer whatever iOS picks.
            choices.append(DeviceChoice(
                info: InputDeviceInfo(id: Self.routeInputPrefix + "default", name: "Audio interface", inputChannelCount: 0, sampleRate: session.sampleRate),
                name: "Audio interface",
                availableSampleRates: Self.sessionSampleRates,
                make: { chosen, capAt48k in
                    #if DEBUG
                    try MonitorExperiment.shared.openForArm(preferredInputUID: nil, sampleRate: Self.sessionRate(chosen, capAt48k: capAt48k))
                    #else
                    try SessionAudioDevice.current(sampleRate: Self.sessionRate(chosen, capAt48k: capAt48k))
                    #endif
                }))
        }
        #endif
        if DemoSignalAvailability.isAvailableInThisBuild {
            choices.append(DeviceChoice(
                info: InputDeviceInfo(id: "demo", name: "Demo signal", inputChannelCount: DemoAudioDevice.channelCount, sampleRate: 48_000),
                name: "Demo signal (\(DemoAudioDevice.channelCount) channels)",
                make: { _, _ in DemoAudioDevice() }))
        }
        #if DEBUG
        // `-demoStems <folder>` (Debug): a folder of stems as USB Channels, for screenshots (#374).
        if let folder = DemoStemsDevice.folder, let layout = DemoStemsDevice.layout(of: folder) {
            choices.append(DeviceChoice(
                info: InputDeviceInfo(id: "demo-stems", name: "Demo stems", inputChannelCount: layout.channelCount, sampleRate: 48_000),
                name: "Demo stems (\(layout.channelCount) channels)",
                make: { _, _ in DemoStemsDevice(folder: folder, layout: layout) }))
        }
        #endif
        // The screenshot build offers only demo inputs (#374).
        return DemoOnlyInputSource.isScreenshotBuild() ? DemoOnlyInputSource.onlyDemo(choices) : choices
    }
}

/// A large Marker button with the Take's Marker count; dimmed when no Take is running.
struct MarkerButtonLabel: View {
    let count: Int
    var size: CGFloat = 88
    @Environment(\.appearanceMode) private var mode

    /// Yellow, or a darker amber in Sunlight where yellow on a light screen can't be seen.
    private var flagColor: Color { mode == .system ? .yellow : Color(Palette.markerFlag(mode)) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(flagColor.opacity(mode == .sunlight ? 0.25 : 0.2))
                    .frame(width: size, height: size)
                Image(systemName: "flag.fill")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(flagColor)
            }
            Text(count == 1 ? "1 Marker" : "\(count) Markers")
                .font(.caption)
                .monospacedDigit()
                .secondaryText()
        }
        .contentShape(Rectangle())
    }
}

private struct TransportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 402
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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

/// What opens as a sheet from the record screen: the Marker list and Channel names.
enum LivePanel: Equatable {
    case markers, channelNames
}

extension View {
    /// At least 44 by 44 pt to hit, the whole area, as Apple's guidelines ask (#240).
    func tapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
