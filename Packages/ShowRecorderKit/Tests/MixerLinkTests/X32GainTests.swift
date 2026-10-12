import AutoGain
@testable import MixerLink
import OSC
import Testing

/// Setting an X32 channel's preamp gain, with Re-Gain's compensation (#392).
@Suite("X32 gain")
struct X32GainTests {
    @Test("A channel's preamp is the one the X32 reports for it; a channel with none (a digital source) has none")
    func preampOfAChannel() async throws {
        var state = FakeXAirMixer.State.x32()
        state.headampOfChannel[4] = 37        // channel 5 on an AES50 A stage box input
        state.headampOfChannel[9] = -1        // channel 10 on a card input: no preamp
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        #expect(try await driver.headamp(ofChannel: 1) == 0)
        #expect(try await driver.headamp(ofChannel: 5) == 37)
        #expect(try await driver.headamp(ofChannel: 10) == nil)
    }

    @Test("Reads a channel's Re-Gain state in dB: thresholds, fader, mono, and its sends with pre or post")
    func readsReGainState() async throws {
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
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let read = try await driver.reGainState(ofChannel: 1)

        #expect(read.channel == 1)
        #expect(read.gateThresholdDb == -37.0)
        #expect(read.compressorThresholdDb == -31.5)
        #expect(abs((read.mainFaderDb ?? 99) - 0) < 0.05, "0 dB isn't on one of the fader's 1024 steps; the nearest is -0.01 dB")
        #expect(read.otherMainsDb == [1: -90])
        #expect(read.sends.first { $0.bus == 1 } == ReGain.Send(bus: 1, levelDb: -20, preFader: true))
        #expect(read.sends.first { $0.bus == 2 } == ReGain.Send(bus: 2, levelDb: -8.75, preFader: true))
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
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let keyed = try await driver.keyedDynamics(from: 1)

        #expect(Set(keyed) == [
            ReGain.KeyedDynamics(channel: 2, dynamics: .compressor, thresholdDb: -34, keyChannel: 1),
            ReGain.KeyedDynamics(channel: 3, dynamics: .gate, thresholdDb: -40, keyChannel: 1),
        ])
    }

    @Test("A channel with no input (source off) keys nothing, even though every other key reads 0")
    func noInputKeysNothing() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[0].inputSource = 0
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

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
    func applyReGain() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let result = try await driver.applyReGain(channel: 1, gainChangeDb: 6)

        #expect(result.headamp == 0)
        #expect(result.fromGainDb == -12 && result.toGainDb == -6)
        #expect(result.held[ReGain.Setting(channel: 1, parameter: .gateThreshold)] == -31)
        #expect(result.held[ReGain.Setting(channel: 1, parameter: .compressorThreshold)] == -25.5)
        #expect(result.held[ReGain.Setting(channel: 1, parameter: .send(1))] == -26)
        #expect(result.held[ReGain.Setting(channel: 2, parameter: .compressorThreshold)] == -28)
        let send2 = try #require(result.held[ReGain.Setting(channel: 1, parameter: .send(2))])
        #expect(abs(send2 - -14.75) <= 0.25, "a step next to -14.75")
        #expect(X32Values.level.snap(send2) == send2, "on a step")
        let after = try await driver.reGainState(ofChannel: 1)
        #expect(after.gateThresholdDb == -31, "read back as written")
        #expect(after.sends.first { $0.bus == 2 }?.levelDb == send2)
        #expect(mixer.writes.allSatisfy { $0.address.hasPrefix("/ch/") || $0.address.hasPrefix("/headamp/") })
    }

    @Test("Undo puts back every value exactly as it was, gain included")
    func undoReGain() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        let before = try await driver.reGainState(ofChannel: 1)

        let result = try await driver.applyReGain(channel: 1, gainChangeDb: 6)
        try await driver.undo(result)

        #expect(try await driver.reGainState(ofChannel: 1) == before)
        #expect(try await driver.keyedDynamics(from: 1).first?.thresholdDb == -34)
        #expect(try await driver.gainDb(ofHeadamp: 0) == -12)
    }

    @Test("A channel with no preamp can't have its gain set, and says why")
    func noPreamp() async throws {
        var state = Self.kickDesk()
        state.headampOfChannel[0] = -1
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        await #expect(throws: MixerLinkProblem.noPreamp(channel: 1)) { try await driver.applyReGain(channel: 1, gainChangeDb: 6) }
        #expect(mixer.writes.isEmpty)
    }

    @Test("Gain stops at the preamp's +60 dB; the compensation follows the gain actually set")
    func gainClampedAtTop() async throws {
        var state = Self.kickDesk()
        state.headampGains[0] = Float(X32Values.headampGain.toFloat(57))   // +57 dB
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let result = try await driver.applyReGain(channel: 1, gainChangeDb: 6)

        #expect(result.toGainDb == 60)
        #expect(result.held[ReGain.Setting(channel: 1, parameter: .gateThreshold)] == -34, "-37 + 3, not + 6")
    }
}
