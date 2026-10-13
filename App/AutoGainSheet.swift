import AutoGain
import MixerLink
import Recording
import SwiftUI

/// Auto-gain (#155): brings each USB Channel to the target level by moving its preamp on the Mixer, with Re-Gain
/// keeping the mix the same. All channels at once or one at a time, a result for each, and Undo. Never during a Take.
struct AutoGainSheet: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var session: AutoGainSession?
    @State private var results: [Int: AutoGainSession.Result] = [:]
    @State private var running: Set<Int> = []

    var body: some View {
        NavigationStack {
            AutoGainList(
                channels: (1...max(1, model.meterModel.channelCount)).map { ($0, model.channelLabel($0)) },
                results: results, running: running, locked: model.recorder.isRecording || !running.isEmpty,
                runAll: { Task { await run(Array(1...model.meterModel.channelCount)) } },
                runOne: { usb in Task { await run([usb]) } },
                undoOne: { usb in Task { await undo(usb) } },
                undoAll: { Task { await undoAll() } },
                canUndo: { session?.steps[$0]?.isEmpty == false },
                canUndoAll: session?.steps.values.contains { !$0.isEmpty } == true)
                .navigationTitle("Auto-gain")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        // A List has no size of its own; without this a Mac sheet shows it empty.
        .frame(minWidth: 440, minHeight: 420)
        .interactiveDismissDisabled(!running.isEmpty)
    }

    private func run(_ usbChannels: [Int]) async {
        guard let session = session ?? model.makeAutoGainSession() else { return }
        self.session = session
        running.formUnion(usbChannels)
        for result in await session.run(usbChannels: usbChannels) { results[result.usbChannel] = result }
        running.subtract(usbChannels)
    }

    private func undo(_ usb: Int) async {
        try? await session?.undo(usbChannel: usb)
        results[usb] = nil
    }

    private func undoAll() async {
        try? await session?.undoAll()
        results = [:]
    }
}

/// The channel list: what each USB Channel's auto-gain did, with its buttons. A plain view, so a preview can show it.
struct AutoGainList: View {
    let channels: [(number: Int, name: String)]
    let results: [Int: AutoGainSession.Result]
    let running: Set<Int>
    let locked: Bool
    let runAll: () -> Void
    let runOne: (Int) -> Void
    let undoOne: (Int) -> Void
    let undoAll: () -> Void
    let canUndo: (Int) -> Bool
    let canUndoAll: Bool

    var body: some View {
        List {
            Section {
                Button("Auto-gain all channels", action: runAll).disabled(locked)
                Button("Undo all", role: .destructive, action: undoAll).disabled(locked || !canUndoAll)
            } footer: {
                Text("Plays what's on each channel for a few seconds and moves its preamp on the Mixer to bring it to -18 dBFS. The gate and compressor thresholds, the fader and pre-fader sends move to match, so the mix doesn't change. Play or speak into every channel while it runs.")
            }
            Section("Channels") {
                ForEach(channels, id: \.number) { channel in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(channel.number). \(channel.name)")
                            if running.contains(channel.number) {
                                Text("Measuring…").font(.caption).foregroundStyle(.secondary)
                            } else if let result = results[channel.number] {
                                Text(result.summary).font(.caption).foregroundStyle(result.isProblem ? .orange : .secondary)
                            }
                        }
                        Spacer()
                        if canUndo(channel.number), !running.contains(channel.number) {
                            Button("Undo") { undoOne(channel.number) }.disabled(locked).buttonStyle(.borderless)
                        }
                        Button("Auto-gain") { runOne(channel.number) }.disabled(locked).buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

extension AutoGainSession.Result {
    var usbChannel: Int {
        switch self {
        case .set(let usb, _, _, _, _), .skipped(let usb, _), .failed(let usb, _, _), .stopped(let usb, _), .error(let usb, _, _): usb
        }
    }

    var isProblem: Bool {
        switch self {
        case .set, .skipped: false
        case .failed, .stopped, .error: true
        }
    }

    /// One line in plain words.
    var summary: String {
        func db(_ value: Double) -> String { String(format: "%+.1f dB", value) }
        func dbfs(_ value: Double) -> String { String(format: "%.1f dBFS", value) }
        switch self {
        case .set(_, let channel, let from, let to, let level):
            return "Channel \(channel): gain \(db(from)) to \(db(to)), now \(dbfs(level))"
        case .skipped(_, .noSignal):
            return "No signal, left alone"
        case .skipped(_, .noChannel):
            return "No Mixer channel on this USB Channel"
        case .skipped(_, .sameChannel(let earlier)):
            return "Same Mixer channel as USB \(earlier)"
        case .failed(_, _, .stillClipping(let level)):
            return "Still too loud at the lowest gain (\(dbfs(level)))"
        case .failed(_, _, .stillTooQuiet(let level)):
            return "Still too quiet at the highest gain (\(dbfs(level)))"
        case .failed(_, _, .rangeReached(let level)):
            return "The preamp is at the end of its range (\(dbfs(level)))"
        case .failed(_, _, .offTarget(let level)):
            return String(format: "Ended at %@, %.1f dB from -18", dbfs(level), abs(level + 18))
        case .failed(_, _, .signalLost):
            return "The signal stopped while measuring"
        case .failed(_, _, .noSignal):
            return "No signal, left alone"
        case .stopped:
            return "Stopped: the level didn't follow the gain. Check the Mixer's USB routing. The gain was put back."
        case .error(_, _, let problem):
            return problem.message
        }
    }
}

#Preview("Auto-gain results") {
    AutoGainList(
        channels: [(1, "Kick"), (2, "Snare"), (3, "USB 03"), (4, "Bass"), (5, "Keys L"), (6, "Vox")],
        results: [
            1: .set(usbChannel: 1, channel: 1, fromGainDb: -12, toGainDb: 13, levelDbfs: -17.2),
            2: .skipped(usbChannel: 2, reason: .noSignal),
            3: .skipped(usbChannel: 3, reason: .noChannel),
            4: .failed(usbChannel: 4, channel: 4, failure: .stillClipping(levelDbfs: -2)),
            6: .stopped(usbChannel: 6, channel: 6),
        ],
        running: [5], locked: true, runAll: {}, runOne: { _ in }, undoOne: { _ in }, undoAll: {},
        canUndo: { $0 == 1 || $0 == 4 }, canUndoAll: true)
}
