import AutoGain
@testable import MixerLink
import OSC
import Testing

/// Setting an X-Air channel's preamp gain with Re-Gain (#153). Addresses and scales as read on Eric's XR18
/// (firmware 1.26): /headamp/01-16 -12..+60 dB, 17-18 (aux line in) -12..+20 dB; a channel's preamp from its insrc.
@Suite("X-Air gain")
struct XAirGainTests {
    /// Channel 1 like Eric's XR18: preamp 1 at +14.5, gate -18.5, compressor -25, fader -6.2, send 7 (FX 1) at -8.5
    /// PRE, every other send off. Like the real desk, it echoes each set.
    static func kickDesk() -> FakeXAirMixer.State {
        var state = FakeXAirMixer.State()
        state.echoesSets = true
        state.usbRouting = (0..<18).map { [Int32($0), 0] }
        state.headampGains[1] = 0.3681                 // /headamp/01: +14.5
        state.channels[0].gateThreshold = 0.7688       // -18.5
        state.channels[0].compressorThreshold = 0.5833 // -25
        state.channels[0].fader = 0.5943               // -6.2
        state.channels[0].sendLevels[6] = 0.5375       // send 7: -8.5
        state.channels[0].sendTaps[6] = 3              // PRE
        state.channels[1].compressorKey = 1            // channel 2's compressor keyed from channel 1
        state.channels[1].compressorThreshold = 0.5    // -30
        return state
    }

    @Test("A channel's preamp comes from its input source: In01-16 preamps 1-16, the aux line in 17-18, OFF none")
    func preampOfAChannel() async throws {
        var state = Self.kickDesk()
        state.channels[2].inputSource = 16     // L (aux line in)
        state.channels[3].inputSource = 18     // OFF
        state.channels[4].inputSource = 7      // In08
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        #expect(try await driver.headamp(ofChannel: 1) == 1)
        #expect(try await driver.headamp(ofChannel: 3) == 17)
        #expect(try await driver.headamp(ofChannel: 4) == nil)
        #expect(try await driver.headamp(ofChannel: 5) == 8)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 14.5)
    }

    @Test("Reads a channel's Re-Gain state: thresholds, fader, and its 10 sends, each pre or post from its own tap; no mono")
    func readsReGainState() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let state = try await driver.reGainState(ofChannel: 1)

        #expect(state.gateThresholdDb == -18.5)
        #expect(state.compressorThresholdDb == -25)
        #expect(abs((state.mainFaderDb ?? 0) - -6.2) < 0.05)
        #expect(state.otherMainsDb.isEmpty)
        #expect(state.sends.count == 10)
        #expect(state.sends.first { $0.bus == 7 } == ReGain.Send(bus: 7, levelDb: -8.5, preFader: true))
        #expect(state.sends.first { $0.bus == 1 }?.preFader == false, "POST")
    }

    @Test("Finds gates and compressors keyed from a channel: on the X-Air a key is a channel (1-16), 0 is SELF")
    func keyed() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        #expect(try await driver.keyedDynamics(from: 1) == [ReGain.KeyedDynamics(channel: 2, dynamics: .compressor, thresholdDb: -30, keyChannel: 1)])
        #expect(try await driver.keyedDynamics(from: 3).isEmpty)
    }

    @Test("USB Channels map to input channels from the routing; the aux return has no preamp to move")
    func usbToChannel() async throws {
        var state = Self.kickDesk()
        state.usbRouting?[0] = [4, 0]          // USB 1 carries Ch05
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        _ = try await driver.sources(usbChannelCount: 18)

        #expect(driver.channel(forUSBChannel: 1) == 5)
        #expect(driver.channel(forUSBChannel: 2) == 2)
        #expect(driver.channel(forUSBChannel: 17) == nil)
    }

    @Test("+12 dB ramps, never makes the channel louder in the mix, ends on the plan, and undo puts it all back; the desk's echoes don't confuse it")
    func applyAndUndo() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        let before = try await driver.reGainState(ofChannel: 1)

        let step = try await driver.applyReGain(channel: 1, gainChangeDb: 12, scopes: .all)

        #expect(step.headamp == 1 && step.fromGainDb == 14.5 && step.toGainDb == 26.5)
        #expect(step.held[ReGain.Setting(channel: 1, parameter: .gateThreshold)] == -6.5)
        #expect(step.held[ReGain.Setting(channel: 1, parameter: .send(7))] == -20.5)
        #expect(step.held[ReGain.Setting(channel: 2, parameter: .compressorThreshold)] == -18)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 26.5)
        #expect(Self.loudestRise(mixer.writes) <= 0.3)

        try await driver.undo(step)
        #expect(try await driver.reGainState(ofChannel: 1) == before)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 14.5)
    }

    /// The loudest channel 1 got in the mix along the writes (gain + fader, gain + send 7), against the start.
    static func loudestRise(_ writes: [(address: String, value: OSCArgument)]) -> Double {
        var now = ["/headamp/01/gain": 14.5, "/ch/01/mix/fader": X32Values.fader.toDb(0.5943), "/ch/01/mix/07/level": -8.5]
        func level(_ to: String) -> Double { now["/headamp/01/gain"]! + now[to]! }
        let base = ["/ch/01/mix/fader": level("/ch/01/mix/fader"), "/ch/01/mix/07/level": level("/ch/01/mix/07/level")]
        var worst = -Double.infinity
        for write in writes {
            guard case .float(let f) = write.value, now[write.address] != nil else { continue }
            now[write.address] = write.address.hasSuffix("gain") ? X32Values.headampGain.toDb(Double(f))
                : write.address.hasSuffix("fader") ? X32Values.fader.toDb(Double(f)) : X32Values.level.toDb(Double(f))
            worst = max(worst, base.map { level($0.key) - $0.value }.max()!)
        }
        return worst
    }

    @Test("A stereo-linked pair is one preamp move: channel 2 linked with 1 answers channel 1's preamp (#458)")
    func linkedPairPreamp() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0].inputSource = 0
        state.channels[1].inputSource = 1
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        #expect(try await driver.preamp(ofChannel: 2) == 2)
        mixer.update { $0.set["/config/chlink/1-2"] = .int(1) }
        #expect(try await driver.preamp(ofChannel: 2) == 1)
        #expect(try await driver.preamp(ofChannel: 1) == 1)
    }
}
