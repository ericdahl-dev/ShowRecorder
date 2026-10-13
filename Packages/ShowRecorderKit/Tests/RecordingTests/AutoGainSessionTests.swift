import AutoGain
import MixerLink
import TakeFile
@testable import Recording
import Testing

/// A mixer in memory: each mixer channel's preamp gain, and what each USB Channel carries. A USB Channel's level is
/// its source's level plus its channel's gain, as a preamp moves it dB for dB.
@MainActor
final class FakeGainControl: GainControl {
    var gainDb: [Int: Double]
    var channelOfUSB: [Int: Int]
    /// Where the gain really goes, when the mapping is wrong: USB Channel's channel -> the channel actually moved.
    var movesInstead: [Int: Int] = [:]
    /// When set, every gain move fails with it (the Mixer stopped answering).
    var problem: MixerLinkProblem?
    let gainRange: ClosedRange<Double> = -12...60

    init(gainDb: [Int: Double], channelOfUSB: [Int: Int]) {
        self.gainDb = gainDb
        self.channelOfUSB = channelOfUSB
    }

    nonisolated func channel(forUSBChannel usbChannel: Int) -> Int? {
        MainActor.assumeIsolated { channelOfUSB[usbChannel] }
    }

    nonisolated func applyReGain(channel: Int, gainChangeDb: Double, scopes: ReGain.Scopes) async throws(MixerLinkProblem) -> GainStep {
        if let problem = await MainActor.run(body: { problem }) { throw problem }
        return await MainActor.run {
            let target = movesInstead[channel] ?? channel
            let from = gainDb[target] ?? 0
            let to = min(gainRange.upperBound, max(gainRange.lowerBound, from + gainChangeDb))
            gainDb[target] = to
            return GainStep(channel: channel, headamp: target, fromGainDb: from, toGainDb: to, held: [:], limitedBy: nil, restore: ["gain/\(target)": Float(from)])
        }
    }

    nonisolated func undo(_ step: GainStep) async throws(MixerLinkProblem) {
        await MainActor.run { gainDb[step.headamp] = step.fromGainDb }
    }
}

@MainActor
@Suite("Auto-gain session")
struct AutoGainSessionTests {
    /// Source levels at 0 dB gain, by USB Channel.
    static func meters(_ control: FakeGainControl, source: [Int: Double]) -> (Int) async -> Double {
        { usb in
            guard let level = source[usb] else { return -120 }
            let channel = control.channelOfUSB[usb] ?? usb
            return level + (control.gainDb[channel] ?? 0)
        }
    }

    @Test("One channel at -40 dBFS is brought to -18 with its preamp")
    func oneChannel() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18)])
        #expect(control.gainDb[1] == 22)
    }

    @Test("All channels: silent ones, ones with no Mixer channel, and a second USB Channel on a channel already moved are skipped")
    func skips() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0, 3: 0], channelOfUSB: [1: 1, 2: 2, 3: 3, 4: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 4: -40]))

        let results = await session.run(usbChannels: [1, 2, 4, 5])

        #expect(results == [
            .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18),
            .skipped(usbChannel: 2, reason: .noSignal),
            .skipped(usbChannel: 4, reason: .sameChannel(asUSBChannel: 1)),
            .skipped(usbChannel: 5, reason: .noChannel),
        ])
        #expect(control.gainDb == [1: 22, 2: 0, 3: 0])
    }

    @Test("If the level doesn't follow the gain (the wrong preamp moved), it stops and puts that gain back")
    func levelDidNotFollow() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1])
        control.movesInstead = [1: 2]          // the mapping is wrong: channel 2's preamp moves instead
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.stopped(usbChannel: 1, channel: 1)])
        #expect(control.gainDb == [1: 0, 2: 0], "the wrong preamp is put back")
        #expect(session.steps[1] == nil || session.steps[1] == [], "nothing left to undo")
    }

    @Test("A channel the rule can't bring to target says why, and keeps its gain for Undo")
    func ruleFailure() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: 10]))   // far too hot

        let results = await session.run(usbChannels: [1])

        guard case .failed(usbChannel: 1, channel: 1, failure: let failure)? = results.first else {
            Issue.record("expected a failure, got \(results)"); return
        }
        #expect([.rangeReached(levelDbfs: -2), .stillClipping(levelDbfs: -2)].contains(failure), "the preamp is at its -12 dB end")
        #expect(control.gainDb[1] == -12)
        #expect(session.steps[1]?.isEmpty == false)
    }

    @Test("A Mixer that stops answering is reported for that channel, not skipped quietly")
    func mixerError() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.problem = .noReply(host: "10.0.0.20")
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        #expect(await session.run(usbChannels: [1]) == [.error(usbChannel: 1, channel: 1, problem: .noReply(host: "10.0.0.20"))])
    }

    @Test("Undo puts one channel's gain back, or every channel's")
    func undo() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 5], channelOfUSB: [1: 1, 2: 2])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 2: -30]))
        _ = await session.run(usbChannels: [1, 2])
        #expect(control.gainDb == [1: 22, 2: 12])

        try await session.undo(usbChannel: 2)
        #expect(control.gainDb == [1: 22, 2: 5])

        try await session.undoAll()
        #expect(control.gainDb == [1: 0, 2: 5])
        #expect(session.steps.values.allSatisfy { $0.isEmpty })
    }

    @Test("Every gain step and every Undo is logged, with what Re-Gain moved (#450)")
    func logsGainChanges() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        var logged: [TakeMetadata.GainChange] = []
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]), log: { logged.append($0) })

        _ = await session.run(usbChannels: [1])
        try await session.undo(usbChannel: 1)

        #expect(logged.map(\.reason) == [.autoGain, .undo])
        #expect(logged.map(\.fromGainDb) == [0, 22])
        #expect(logged.map(\.toGainDb) == [22, 0])
        #expect(logged.allSatisfy { $0.usbChannel == 1 && $0.channel == 1 && $0.headamp == 1 })
    }

    @Test("A safety stop's Undo is logged too")
    func logsSafetyUndo() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1])
        control.movesInstead = [1: 2]
        var logged: [TakeMetadata.GainChange] = []
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]), log: { logged.append($0) })

        _ = await session.run(usbChannels: [1])

        #expect(logged.map(\.reason) == [.autoGain, .undo])
    }
}
