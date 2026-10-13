import AutoGain
@testable import MixerLink
import OSC
import Testing

/// Setting an X32 channel's preamp gain, with Mix Hold's compensation (#392).
@Suite("X32 gain")
struct X32GainTests {
    @Test("A channel's preamp is the one the X32 reports for it; a channel with none (a digital source) has none")
    func preampOfAChannel() async throws {
        var state = FakeXAirMixer.State.x32()
        state.headampOfChannel[4] = 37        // channel 5 on an AES50 A stage box input
        state.headampOfChannel[9] = -1        // channel 10 on a card input: no preamp
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.headamp(ofChannel: 1) == 0)
        #expect(try await driver.headamp(ofChannel: 5) == 37)
        #expect(try await driver.headamp(ofChannel: 10) == nil)
    }

    @Test("Reads a channel's Mix Hold state in dB: thresholds, fader, mono, and its sends with pre or post")
    func readsMixHoldState() async throws {
        var state = FakeXAirMixer.State.x32()
        var kick = state.channels[0]
        kick.gateThreshold = 0.5375          // -37.0 dB
        kick.compressorThreshold = 0.475     // -31.5 dB
        kick.fader = 0.75                    // 0 dB
        kick.monoLevel = 0                   // -oo (-90)
        kick.sendLevels[0] = 0.375           // -20 dB
        kick.sendLevels[1] = 0.53125         // -8.75 dB
        kick.sendTypes[0] = 3                // sends 1-2: PRE
        state.channels[0] = kick
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let read = try await driver.mixHoldState(ofChannel: 1)

        #expect(read.channel == 1)
        #expect(read.gateThresholdDb == -37.0)
        #expect(read.compressorThresholdDb == -31.5)
        #expect(abs((read.mainFaderDb ?? 99) - 0) < 0.05, "0 dB isn't on one of the fader's 1024 steps; the nearest is -0.01 dB")
        #expect(read.otherMainsDb == [1: -90])
        #expect(read.sends.first { $0.bus == 1 } == MixHold.Send(bus: 1, levelDb: -20, preFader: true))
        #expect(read.sends.first { $0.bus == 2 } == MixHold.Send(bus: 2, levelDb: -8.75, preFader: true))
        #expect(read.sends.first { $0.bus == 3 }?.preFader == false, "sends 3-4 are POST")
        #expect(read.sends.count == 16)
    }

    @Test("Finds gates and compressors keyed from a channel's input; a key of 0 (own signal) never counts")
    func keyedFromAChannel() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[1].compressorKey = 1          // channel 2's compressor keyed from In01 (the kick)
        state.channels[1].compressorThreshold = 0.4333  // -34 dB
        state.channels[2].gateKey = 1                // channel 3's gate keyed from In01
        state.channels[2].gateThreshold = 0.5        // -40 dB
        state.channels[3].gateKey = 2                // channel 4 keyed from In02: not ours
        let mixer = try await FakeXAirMixer(state)  // every other key is 0 (own signal)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let keyed = try await driver.keyedDynamics(from: 1)

        #expect(Set(keyed) == [
            MixHold.KeyedDynamics(channel: 2, dynamics: .compressor, thresholdDb: -34, keyChannel: 1),
            MixHold.KeyedDynamics(channel: 3, dynamics: .gate, thresholdDb: -40, keyChannel: 1),
        ])
    }

    @Test("A channel with no input (source off) keys nothing, even though every other key reads 0")
    func noInputKeysNothing() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[0].inputSource = 0
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.keyedDynamics(from: 1).isEmpty)
    }

    /// Channel 1 as on the emulator check (2026-10-12): gain -12, gate -37, compressor -31.5, fader -4.2, PRE sends
    /// -20 and -8.75, and channel 2's compressor keyed from In01 at -34.
    static func kickDesk() -> FakeXAirMixer.State {
        var state = FakeXAirMixer.State.x32()
        state.headampGains[0] = 0                     // -12 dB
        state.channels[0].gateThreshold = 0.5375      // -37
        state.channels[0].compressorThreshold = 0.475 // -31.5
        state.channels[0].fader = 0.6461              // about -4.2
        state.channels[0].sendLevels[0] = 0.375       // -20
        state.channels[0].sendLevels[1] = 0.53125     // -8.75
        state.channels[0].sendTypes[0] = 3            // PRE
        state.channels[1].compressorKey = 1
        state.channels[1].compressorThreshold = 0.4333 // -34
        return state
    }

    @Test("+6 dB: the gain and every compensation are written on the X32's own steps, and the result says what it holds")
    func applyMixHold() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let result = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(result.headamp == 0)
        #expect(result.fromGainDb == -12 && result.toGainDb == -6)
        #expect(result.held[MixHold.Setting(channel: 1, parameter: .gateThreshold)] == -31)
        #expect(result.held[MixHold.Setting(channel: 1, parameter: .compressorThreshold)] == -25.5)
        #expect(result.held[MixHold.Setting(channel: 1, parameter: .send(1))] == -26)
        #expect(result.held[MixHold.Setting(channel: 2, parameter: .compressorThreshold)] == -28)
        let send2 = try #require(result.held[MixHold.Setting(channel: 1, parameter: .send(2))])
        #expect(abs(send2 - -14.75) <= 0.25, "a step next to -14.75")
        #expect(X32Values.level.snap(send2) == send2, "on a step")
        let after = try await driver.mixHoldState(ofChannel: 1)
        #expect(after.gateThresholdDb == -31, "read back as written")
        #expect(after.sends.first { $0.bus == 2 }?.levelDb == send2)
        #expect(mixer.writes.allSatisfy { $0.address.hasPrefix("/ch/") || $0.address.hasPrefix("/headamp/") })
    }

    @Test("Undo puts back every value exactly as it was, gain included")
    func undoMixHold() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = try await driver.mixHoldState(ofChannel: 1)

        let result = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        try await driver.undo(result)

        #expect(try await driver.mixHoldState(ofChannel: 1) == before)
        #expect(try await driver.keyedDynamics(from: 1).first?.thresholdDb == -34)
        #expect(try await driver.gainDb(ofHeadamp: 0) == -12)
    }

    @Test("A channel with no preamp can't have its gain set, and says why")
    func noPreamp() async throws {
        var state = Self.kickDesk()
        state.headampOfChannel[0] = -1
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        await #expect(throws: MixerLinkProblem.noPreamp(channel: 1)) { try await driver.applyMixHold(channel: 1, gainChangeDb: 6) }
        #expect(mixer.writes.isEmpty)
    }

    @Test("Gain stops at the preamp's +60 dB; the compensation follows the gain actually set")
    func gainClampedAtTop() async throws {
        var state = Self.kickDesk()
        state.headampGains[0] = Float(X32Values.headampGain.toFloat(57))   // +57 dB
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let result = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(result.toGainDb == 60)
        #expect(result.held[MixHold.Setting(channel: 1, parameter: .gateThreshold)] == -34, "-37 + 3, not + 6")
    }

    /// Replays the writes in order and returns the loudest the channel got in the mix along the way, against where it
    /// started: gain + fader, and gain + each pre-fader send, in dB. Mix Hold must never make it louder, even for a
    /// moment, so this is at most a hair above 0.
    static func loudestRise(_ writes: [(address: String, value: OSCArgument)], start: [String: Double]) -> Double {
        var now = start
        func level(_ to: String) -> Double { (now["/headamp/000/gain"] ?? 0) + (now[to] ?? 0) }
        let paths = ["/ch/01/mix/fader", "/ch/01/mix/01/level", "/ch/01/mix/02/level"]
        let base = paths.map { level($0) }
        var worst = -Double.infinity
        for write in writes {
            guard case .float(let f) = write.value else { continue }
            switch write.address {
            case "/headamp/000/gain": now[write.address] = X32Values.headampGain.toDb(Double(f))
            case "/ch/01/mix/fader": now[write.address] = X32Values.fader.toDb(Double(f))
            case let a where a.hasPrefix("/ch/01/mix/") && a.hasSuffix("/level"): now[a] = X32Values.level.toDb(Double(f))
            default: continue
            }
            worst = max(worst, zip(paths, base).map { level($0) - $1 }.max()!)
        }
        return worst
    }

    static let kickStart = ["/headamp/000/gain": -12.0, "/ch/01/mix/fader": X32Values.fader.toDb(0.6461),
                            "/ch/01/mix/01/level": -20.0, "/ch/01/mix/02/level": -8.75]

    /// Waits until the fake has received `count` writes (sends are fire-and-forget).
    static func writes(of mixer: FakeXAirMixer, atLeast count: Int) async throws -> [(address: String, value: OSCArgument)] {
        for _ in 0..<200 where mixer.writes.count < count { try await Task.sleep(for: .milliseconds(10)) }
        return mixer.writes
    }

    @Test("Raising the gain by 25 dB ramps in steps of at most 1 dB, and the channel never gets louder in the mix")
    func raiseRampsWithoutGettingLouder() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 25)

        let writes = mixer.writes
        let gainWrites = writes.filter { $0.address == "/headamp/000/gain" }
        #expect(gainWrites.count >= 25, "about 1 dB a step")
        #expect(Self.loudestRise(writes, start: Self.kickStart) <= 0.3, "never louder than at the start")
        #expect(step.toGainDb == 13)
        #expect(try await driver.gainDb(ofHeadamp: 0) == 13, "ends exactly where planned")
    }

    @Test("Lowering the gain ramps too, and never gets louder")
    func lowerRampsWithoutGettingLouder() async throws {
        var state = Self.kickDesk()
        state.headampGains[0] = Float(X32Values.headampGain.toFloat(10))
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        var start = Self.kickStart
        start["/headamp/000/gain"] = 10

        _ = try await driver.applyMixHold(channel: 1, gainChangeDb: -6)

        #expect(Self.loudestRise(mixer.writes, start: start) <= 0.3)
    }

    @Test("Undo ramps back the same way and ends on the exact values from before")
    func undoRampsBack() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = try await driver.mixHoldState(ofChannel: 1)
        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 25)
        let applied = mixer.writes.count
        var start = Self.kickStart
        start["/headamp/000/gain"] = 13
        start["/ch/01/mix/fader"] = (start["/ch/01/mix/fader"] ?? 0) - 25
        start["/ch/01/mix/01/level"] = -45
        start["/ch/01/mix/02/level"] = -33.75

        try await driver.undo(step)

        #expect(Self.loudestRise(Array(mixer.writes.dropFirst(applied)), start: start) <= 0.6)
        #expect(try await driver.mixHoldState(ofChannel: 1) == before)
        #expect(try await driver.gainDb(ofHeadamp: 0) == -12)
    }

    @Test("Two X32 channels on one headamp are one preamp move, and so is a stereo-linked pair (#458)")
    func sharedAndLinkedPreamp() async throws {
        var state = FakeXAirMixer.State.x32()
        state.headampOfChannel[16] = 0   // channel 17 on local input 1, like channel 1
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.preamp(ofChannel: 17) == driver.preamp(ofChannel: 1))
        #expect(try await driver.preamp(ofChannel: 4) != driver.preamp(ofChannel: 3))
        mixer.update { $0.set["/config/chlink/3-4"] = .int(1) }
        #expect(try await driver.preamp(ofChannel: 4) != driver.preamp(ofChannel: 3), "linked strips, preamps not linked")
        mixer.update { $0.set["/config/linkcfg/hadly"] = .int(1) }
        #expect(try await driver.preamp(ofChannel: 4) == driver.preamp(ofChannel: 3))
    }

    @Test("Two channels on one headamp: Mix Hold compensates both, so the other channel's level in the mix stays put (#473)")
    func sharedHeadampCompensatesBoth() async throws {
        var state = FakeXAirMixer.State.x32()
        state.headampOfChannel[16] = 0   // channel 17 on local input 1, like channel 1
        state.channels[16].inputSource = 1
        state.channels[4].gateKey = 1    // channel 5's gate keyed from In01, which both channels take
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        #expect(step.changes.filter { $0.setting == MixHold.Setting(channel: 5, parameter: .gateThreshold) }.count == 1)

        let fader17 = try #require(step.changes.first { $0.setting == MixHold.Setting(channel: 17, parameter: .mainFader) })
        #expect(abs(fader17.toDb - (fader17.fromDb - 6)) < 0.05)
        #expect(step.changes.contains { $0.setting == MixHold.Setting(channel: 17, parameter: .gateThreshold) })
        #expect(mixer.writes.contains { $0.address == "/ch/17/mix/fader" })
        #expect(!step.changes.contains { $0.setting.channel == 2 }, "channel 2 is on its own headamp")

        try await driver.undo(step)
        #expect(mixer.writes.last { $0.address == "/ch/17/mix/fader" }?.value == .float(0.75), "Undo puts channel 17 back too")
        #expect(mixer.writes.last { $0.address == "/ch/17/gate/thr" }?.value == .float(0.5), "and its gate threshold")
    }

    @Test("A gain move the mixer stops answering partway says what it wrote, and Undo puts that back exactly (#450)")
    func interruptedMoveReportsWhatItWrote() async throws {
        var state = FakeXAirMixer.State.x32()
        state.stopsAnsweringAfterWrites = 9   // a few ramp steps into a +6 dB move
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))   // waits out a Mixer that stops answering: keeps the short default
        let before = try await driver.mixHoldState(ofChannel: 1)
        let gainBefore = try await driver.gainDb(ofHeadamp: 0)

        var interrupted: GainStep?
        do {
            _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        } catch {
            if case .gainMoveInterrupted(let step) = error { interrupted = step }
        }

        let step = try #require(interrupted)
        #expect(step.fromGainDb == gainBefore)
        #expect(step.toGainDb > gainBefore && step.toGainDb < gainBefore + 6, "partway: what was written, not the plan")
        let fader = try #require(step.changes.first { $0.setting == MixHold.Setting(channel: 1, parameter: .mainFader) })
        #expect(step.held[fader.setting] == fader.toDb)
        mixer.update { $0.answers = true; $0.stopsAnsweringAfterWrites = nil }
        try await driver.undo(step)
        #expect(try await driver.mixHoldState(ofChannel: 1) == before)
        #expect(try await driver.gainDb(ofHeadamp: 0) == gainBefore)
    }

    @Test("A raise the mixer stops answering before the gain was written reports no gain move, and Undo puts the compensations back (#481)")
    func interruptedBeforeTheGain() async throws {
        var state = FakeXAirMixer.State.x32()
        state.stopsAnsweringAfterWrites = 1   // only the first compensation of the first ramp step lands
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))   // waits out a Mixer that stops answering: keeps the short default
        let before = try await driver.mixHoldState(ofChannel: 1)
        let gainBefore = try await driver.gainDb(ofHeadamp: 0)

        var interrupted: GainStep?
        do {
            _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        } catch {
            if case .gainMoveInterrupted(let step) = error { interrupted = step }
        }

        let step = try #require(interrupted)
        #expect(step.toGainDb == gainBefore)
        #expect(!step.changes.isEmpty)
        mixer.update { $0.answers = true; $0.stopsAnsweringAfterWrites = nil }
        try await driver.undo(step)
        #expect(try await driver.mixHoldState(ofChannel: 1) == before)
        #expect(try await driver.gainDb(ofHeadamp: 0) == gainBefore)
    }

    @Test("An X32 preamp-linked pair: Mix Hold asked on channel 4 compensates channel 3's strip too (#393)")
    func linkedPartnerCompensated() async throws {
        var state = FakeXAirMixer.State.x32()
        state.set["/config/chlink/3-4"] = .int(1)
        state.set["/config/linkcfg/hadly"] = .int(1)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 4, gainChangeDb: 6)

        #expect(step.changes.contains { $0.setting == MixHold.Setting(channel: 3, parameter: .mainFader) })
        #expect(step.changes.contains { $0.setting == MixHold.Setting(channel: 4, parameter: .mainFader) })
        #expect(!step.changes.contains { $0.setting.channel == 5 })
    }
}
