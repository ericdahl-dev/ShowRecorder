import AutoGain
import MixerLink
import Recording
import SwiftUI

/// Auto-gain (#155): brings each USB Channel to the target level by moving its preamp on the Mixer, with Re-Gain
/// keeping the mix the same. All channels at once or one at a time, a result for each, and Undo. Never during a Take.
struct AutoGainSheet: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    /// Kept by the record screen, so closing the sheet loses nothing and Undo is still offered when it opens again.
    private var autoGain: AutoGainPanel { model.autoGain }
    /// The `-autoGainDemo` screenshot flag shows sample results with no Mixer: there's nothing to Undo for real.
    private let isDemo = launchFlag("-autoGainDemo")

    var body: some View {
        NavigationStack {
            AutoGainList(
                channels: isDemo ? AutoGainList.demoChannels : (1...max(1, model.meterModel.channelCount)).map { ($0, model.channelLabel($0)) },
                results: isDemo ? AutoGainList.demoResults : autoGain.results,
                running: isDemo ? [5] : autoGain.running,
                phases: isDemo ? AutoGainList.demoPhases : autoGain.phases,
                progress: isDemo ? AutoGainPanel.Progress(done: 4, total: 6) : autoGain.progress,
                finishedRuns: isDemo ? 0 : autoGain.finishedRuns,
                lastRunTotal: isDemo ? 0 : autoGain.lastRunTotal,
                locked: isDemo || autoGain.isLocked,
                runAll: { Task { await autoGain.run(Array(1...model.meterModel.channelCount)) } },
                runOne: { usb in Task { await autoGain.run([usb]) } },
                undoOne: { usb in Task { await autoGain.undo(usb) } },
                undoAll: { Task { await autoGain.undoAll() } },
                canUndo: { isDemo ? AutoGainList.demoUndoable.contains($0) : autoGain.canUndo($0) },
                canUndoAll: isDemo || autoGain.canUndoAll,
                compensation: { isDemo ? AutoGainList.demoCompensation[$0] : autoGain.compensationSummary($0) },
                unavailable: isDemo ? nil : model.autoGainUnavailable)
                .navigationTitle("Auto-gain")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        // A List has no size of its own; without this a Mac sheet shows it empty.
        .frame(minWidth: 480, minHeight: 560)
        .interactiveDismissDisabled(isDemo || !autoGain.running.isEmpty)
    }
}

/// The channel list: what each USB Channel's auto-gain did, with its buttons. A plain view, so a preview can show it.
struct AutoGainList: View {
    static let explanation = "Plays what's on each channel for a few seconds and moves its preamp on the Mixer to bring it to -18 dBFS. The gate and compressor thresholds, the fader and pre-fader sends move to match, so the mix doesn't change. Play or speak into every channel while it runs."

    let channels: [(number: Int, name: String)]
    let results: [Int: AutoGainSession.Result]
    let running: Set<Int>
    /// Where each channel of the run under way is.
    let phases: [Int: AutoGainSession.Phase]
    /// How far the run under way has got, or nil.
    let progress: AutoGainPanel.Progress?
    /// Runs finished, and the last one's channel count, for VoiceOver.
    var finishedRuns = 0
    var lastRunTotal = 0
    let locked: Bool
    let runAll: () -> Void
    let runOne: (Int) -> Void
    let undoOne: (Int) -> Void
    let undoAll: () -> Void
    let canUndo: (Int) -> Bool
    let canUndoAll: Bool
    /// What moved to keep the mix on a USB Channel, in plain words, while it can still be undone.
    let compensation: (Int) -> String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Why it can't run right now, said at the top; everything is locked meanwhile.
    var unavailable: AutoGainAvailability.Unavailable? = nil

    var body: some View {
        let locked = self.locked || unavailable != nil
        return List {
            if let unavailable {
                Section {
                    Label(unavailable.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section {
                // While a run of several channels goes, its progress takes the place of the button that started it.
                // One channel's own run says where it is on its row.
                if let progress, progress.total > 1 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                        Text("Auto-gain is running")
                    } currentValueLabel: {
                        Text(progress.text)
                    }
                    .progressViewStyle(.linear)
                    .accessibilityValue(progress.text)
                    // VoiceOver reads the count live while the bar has focus.
                    .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Button("Auto-gain all channels", action: runAll).disabled(locked)
                }
                Button("Undo all", role: .destructive, action: undoAll).disabled(locked || !canUndoAll)
                #if os(macOS)
                // A Mac list cuts a footer to one line, so the explanation is a row there.
                Text(Self.explanation).font(.callout).foregroundStyle(.secondary)
                #endif
            } footer: {
                #if os(iOS)
                Text(Self.explanation)
                #endif
            }
            Section("Channels") {
                ForEach(channels, id: \.number) { channel in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(channel.number). \(channel.name)")
                            if let label = phases[channel.number]?.label {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                            } else if running.contains(channel.number), phases[channel.number] == nil {
                                Text("Putting the gain back…").font(.caption).foregroundStyle(.secondary)
                            } else if let result = results[channel.number] {
                                Text(result.summary).font(.caption).foregroundStyle(result.isProblem ? .orange : .secondary)
                                if let moved = compensation(channel.number) {
                                    Text(moved).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        // One VoiceOver stop: the channel, its result and what moved to keep the mix.
                        .accessibilityElement(children: .combine)
                        Spacer()
                        if canUndo(channel.number), !running.contains(channel.number) {
                            Button("Undo") { undoOne(channel.number) }.disabled(locked).buttonStyle(.borderless)
                        }
                        Button("Auto-gain") { runOne(channel.number) }.disabled(locked).buttonStyle(.borderless)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: progress)
        // Channels finish in bursts, too fast to announce each; VoiceOver hears when the whole run is done.
        .onChange(of: finishedRuns) {
            AccessibilityNotification.Announcement(
                "Auto-gain finished on \(lastRunTotal) \(lastRunTotal == 1 ? "channel" : "channels")").post()
        }
    }
}

extension AutoGainSession.Result {
    var isProblem: Bool {
        switch self {
        case .set, .skipped: false
        case .failed, .stopped, .error, .haltedForTake: true
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
        case .skipped(_, .alreadyOnTarget(let level)):
            return "Already at \(dbfs(level)), left alone"
        case .skipped(_, .noChannel):
            return "No Mixer channel on this USB Channel"
        case .skipped(_, .sameChannel(let earlier)):
            return "Same Mixer channel as USB \(earlier)"
        case .skipped(_, .samePreamp(let earlier)):
            return "Same preamp as USB \(earlier) (stereo-linked, or on the same input)"
        case .failed(_, _, .stillClipping(let level), _):
            return "Still too loud at the lowest gain (\(dbfs(level)))"
        case .failed(_, _, .stillTooQuiet(let level), _):
            return "Still too quiet at the highest gain (\(dbfs(level)))"
        case .failed(_, _, .rangeReached(let level), let limit?):
            return "\(limit.explanation), so the gain can't move further without changing the mix (\(dbfs(level)))"
        case .failed(_, _, .rangeReached(let level), nil):
            return "The preamp is at the end of its range (\(dbfs(level)))"
        case .failed(_, _, .offTarget(let level), _):
            return String(format: "Ended at %@, %.1f dB from -18", dbfs(level), abs(level + 18))
        case .failed(_, _, .signalLost, _):
            return "The signal stopped while measuring"
        case .failed(_, _, .noSignal, _):
            return "No signal, left alone"
        case .stopped:
            return "Stopped: the level didn't follow the gain. Check the Mixer's USB routing. The gain was put back."
        case .haltedForTake:
            return "Stopped because a Take started. The gain stays where it got to; Undo puts it back."
        case .error(_, _, let problem):
            return problem.message
        }
    }
}

extension AutoGainList {
    /// Sample results for the preview and the `-autoGainDemo` screenshots: one of each kind of result.
    static let demoChannels: [(number: Int, name: String)] = [(1, "Kick"), (2, "Snare"), (3, "USB 03"), (4, "Bass"), (5, "Keys L"), (6, "Vox")]
    static let demoResults: [Int: AutoGainSession.Result] = [
        1: .set(usbChannel: 1, channel: 1, fromGainDb: -12, toGainDb: 13, levelDbfs: -17.2),
        2: .skipped(usbChannel: 2, reason: .noSignal),
        3: .skipped(usbChannel: 3, reason: .noChannel),
        4: .failed(usbChannel: 4, channel: 4, failure: .stillClipping(levelDbfs: -2)),
        6: .stopped(usbChannel: 6, channel: 6),
    ]
    static let demoUndoable: Set<Int> = [1, 4]
    static let demoCompensation: [Int: String] = [
        1: "To keep the mix: fader, 6 sends and 2 thresholds moved -25.0 dB",
    ]
    static let demoPhases: [Int: AutoGainSession.Phase] = [5: .adjusting]
}

#Preview("Auto-gain results") {
    AutoGainList(
        channels: AutoGainList.demoChannels, results: AutoGainList.demoResults,
        running: [5], phases: AutoGainList.demoPhases, progress: AutoGainPanel.Progress(done: 4, total: 6), locked: true, runAll: {}, runOne: { _ in }, undoOne: { _ in }, undoAll: {},
        canUndo: { AutoGainList.demoUndoable.contains($0) }, canUndoAll: true,
        compensation: { AutoGainList.demoCompensation[$0] })
}

#Preview("Auto-gain during a Take") {
    AutoGainList(
        channels: AutoGainList.demoChannels, results: [:], running: [], phases: [:], progress: nil, locked: false,
        runAll: {}, runOne: { _ in }, undoOne: { _ in }, undoAll: {}, canUndo: { _ in false }, canUndoAll: false,
        compensation: { _ in nil }, unavailable: .takeRunning)
}
