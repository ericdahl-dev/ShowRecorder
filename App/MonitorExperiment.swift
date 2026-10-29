#if DEBUG && os(iOS)
import AudioIO
import AVFAudio
import CoreAudioIO
import Observation
import OSLog
import SwiftUI

/// The headphone monitor experiment (#233, part 1), Debug builds only: with the setting on, getting the iPhone's input ready
/// also plays it to Bluetooth headphones through a second, output-only audio unit. The Take is recorded exactly as
/// without it; the monitor only reads a copy of the first channel. Every route change is logged to the `monitor233`
/// category so a device run can answer: does input stay the built-in mic, are Stems identical, does a headphone
/// coming or going leave the Take alone, and how late is the monitor.
@MainActor
@Observable
final class MonitorExperiment {
    static let shared = MonitorExperiment()
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShowRecorder", category: "monitor233")
    private static let settingKey = "monitorExperiment233"

    /// The Debug setting. Changed only between Takes (Settings locks during one); the next get-ready uses it.
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: MonitorExperiment.settingKey) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.settingKey) }
    }

    /// The plan the last get-ready used. A mid-Take route move opens its input with the same one, so the session's
    /// category never changes during a Take.
    private(set) var readyPlan: AudioSessionPlan = .recording
    /// Whether the Ready input feeds the monitor.
    private(set) var isReady = false
    /// The last route, short, for the record screen.
    private(set) var routeLine = ""
    /// Why the monitor output didn't start, if it didn't.
    private(set) var outputError: String?

    /// Off at every launch. Only sets the switch the output callback reads.
    var monitorOn = false {
        didSet { switches.monitor = monitorOn; logState("monitor \(monitorOn ? "on" : "off")") }
    }

    var toneOn = false {
        didSet { switches.tone = toneOn; logState("tone \(toneOn ? "on" : "off")") }
    }

    /// Room for the mixer's 4096-frame latency limit plus large Bluetooth output slices, with plenty to spare.
    @ObservationIgnored let ring = MonitorRing(capacity: 32_768)
    @ObservationIgnored let switches = MonitorSwitches()
    @ObservationIgnored private var output: MonitorOutput?
    /// The Ready input's rate, for restarting the output after an interruption.
    @ObservationIgnored private var readySampleRate = 48_000.0
    /// The input inside the `MonitorTap`, for what the route offers.
    @ObservationIgnored private(set) var sessionDevice: SessionAudioDevice?

    private init() {}

    // MARK: - Getting ready

    /// Opens the route's input for a get-ready, with the plan the setting asks for. With the experiment on, the input is
    /// wrapped in a `MonitorTap`; off, it's the same `SessionAudioDevice` as without this file.
    func openForGetReady(preferredInputUID: String?, sampleRate: Int?) throws -> any AudioIODevice {
        stopOutput()
        readyPlan = isEnabled ? .monitorExperiment : .recording
        return try open(preferredInputUID: preferredInputUID, sampleRate: sampleRate)
    }

    /// Opens the current route's input for a mid-Take move, with the plan chosen at get-ready.
    func openForRouteMove(sampleRate: Int?) throws -> any AudioIODevice {
        stopOutput()
        return try open(preferredInputUID: nil, sampleRate: sampleRate)
    }

    private func open(preferredInputUID: String?, sampleRate: Int?) throws -> any AudioIODevice {
        let device = try SessionAudioDevice.current(preferredInputUID: preferredInputUID, sampleRate: sampleRate, plan: readyPlan)
        guard readyPlan.playsOutput else {
            sessionDevice = nil
            return device
        }
        sessionDevice = device
        return MonitorTap(device, ring: ring)
    }

    /// After each get-ready or input move (`TakeSequencer.didGetReady`): starts the monitor output when the input is tapped,
    /// stops it otherwise. A failure is logged once and leaves the monitor silent; it never reaches the Take.
    func ready(_ device: (any AudioIODevice)?) {
        stopOutput()
        guard let tap = device as? MonitorTap else {
            isReady = false
            return
        }
        isReady = true
        readySampleRate = tap.sampleRate
        // Nothing reads the ring while the output is stopped, so this side may drain it: no stale audio on start.
        ring.drain()
        routeChanged(reason: "Armed")
        startOutput()
    }

    /// Input came back after an interruption on the same device (no `didGetReady`): restart the output iOS stopped.
    func inputRestarted() {
        guard isReady else { return }
        stopOutput()
        ring.drain()
        routeChanged(reason: "inputRestarted")
        startOutput()
    }

    /// A failure is logged once and leaves the monitor silent; it never reaches the Take.
    private func startOutput() {
        do {
            output = try MonitorOutput(ring: ring, switches: switches, sampleRate: readySampleRate)
            outputError = nil
            Self.log.notice("monitor output started at \(self.readySampleRate, privacy: .public) Hz")
        } catch {
            outputError = String(describing: error)
            Self.log.error("monitor output failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    /// The recorder was stood down (screen gone, idle, device lost).
    func stoodDown() {
        stopOutput()
        isReady = false
    }

    private func stopOutput() {
        output?.stop()
        output = nil
    }

    // MARK: - Route log

    /// Logs every route change, whatever the setting, and keeps the headphones switch current. Never alerts, never
    /// touches the Take. Separate from the record screen's own route watcher, whose input logic stays as it is.
    func watchRoutes() async {
        let reasons = NotificationCenter.default
            .notifications(named: AVAudioSession.routeChangeNotification)
            .map { Self.reasonName($0.userInfo) }
        for await reason in reasons { routeChanged(reason: reason) }
    }

    private func routeChanged(reason: String) {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let headphoneTypes: [AVAudioSession.Port] = [.bluetoothA2DP, .headphones, .bluetoothLE]
        switches.headphones = route.outputs.contains { headphoneTypes.contains($0.portType) }
        let ports = { (list: [AVAudioSessionPortDescription]) in
            list.map { "\($0.portType.rawValue) '\($0.portName)' \($0.uid)" }.joined(separator: ", ")
        }
        let ms = { (seconds: TimeInterval) in String(format: "%.1f ms", seconds * 1_000) }
        Self.log.notice("""
            route \(reason, privacy: .public): in [\(ports(route.inputs), privacy: .public)] \
            out [\(ports(route.outputs), privacy: .public)] \
            category \(session.category.rawValue, privacy: .public) \
            rate \(session.sampleRate, privacy: .public) \
            buffer \(ms(session.ioBufferDuration), privacy: .public) \
            inLatency \(ms(session.inputLatency), privacy: .public) \
            outLatency \(ms(session.outputLatency), privacy: .public) \
            headphones \(self.switches.headphones, privacy: .public) \
            ring overrun \(self.ring.overrunFrames, privacy: .public) underrun \(self.ring.underrunFrames, privacy: .public) \
            skipped \(self.ring.skippedFrames, privacy: .public)
            """)
        let input = route.inputs.first?.portName ?? "none"
        let outputName = route.outputs.first.map { "\($0.portName) (\($0.portType.rawValue))" } ?? "none"
        routeLine = "\(reason): \(input) → \(outputName), \(Int(session.sampleRate)) Hz, out \(ms(session.outputLatency))"
    }

    private func logState(_ change: String) {
        Self.log.notice("""
            \(change, privacy: .public): headphones \(self.switches.headphones, privacy: .public) \
            ring overrun \(self.ring.overrunFrames, privacy: .public) underrun \(self.ring.underrunFrames, privacy: .public) \
            skipped \(self.ring.skippedFrames, privacy: .public)
            """)
    }

    nonisolated private static func reasonName(_ info: [AnyHashable: Any]?) -> String {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return "unknown" }
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "reason \(raw)"
        }
    }
}

/// The experiment's switches and last route, in a sheet so the meters keep their height.
struct MonitorExperimentSheet: View {
    @Bindable var experiment = MonitorExperiment.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Monitor", isOn: $experiment.monitorOn)
                    Toggle("Tone (1 kHz)", isOn: $experiment.toneOn)
                } footer: {
                    Text("Plays the first USB Channel to headphones only. The Take is recorded the same either way.")
                }
                Section("Last route") {
                    Text(experiment.routeLine.isEmpty ? "None yet" : experiment.routeLine)
                        .font(.footnote)
                    if let error = experiment.outputError {
                        Text("Output didn't start: \(error)").font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Monitor experiment (#233)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

extension RecordScreenModel {
    /// The Debug setting changed in Settings: Get ready again so the session uses it. Only between Takes.
    func monitorExperimentChanged() {
        sequencer.settingsChanged()
    }
}
#endif
