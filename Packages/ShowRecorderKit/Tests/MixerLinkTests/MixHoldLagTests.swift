import AutoGain
@testable import MixerLink
import OSC
import Testing

/// Mix Hold on a desk whose writes land at different times (#688). Measured on Eric's XR18: the preamp lands at once and
/// the fader eases in over about 70 ms, so a boost that raised the gain too soon after turning the fader down came out
/// louder. Also a desk that takes a gain write late. Preamp plus fader must never rise above where it started, in any
/// state the desk applies, and never fall more than one ramp step (`rampStepDb`) below it.
@Suite("Mix Hold on a desk whose writes land at different times")
struct MixHoldLagTests {
    static let fader = "/ch/01/mix/fader"

    /// Channel 1 at preamp `gainDb`, fader `faderDb`, gate and compressor off; the desk applies a gain write only after
    /// two more queries.
    static func desk(_ state: FakeXAirMixer.State = FakeXAirMixer.State(), headamp: Int, gainDb: Double, faderDb: Double) -> FakeXAirMixer.State {
        var state = state
        state.echoesSets = true
        state.gainLag = 2
        state.headampGains[headamp] = X32Values.headampGain.oscFloat(gainDb)
        state.channels[0].fader = X32Values.fader.oscFloat(faderDb)
        state.channels[0].gateOn = 0
        state.channels[0].compressorOn = 0
        return state
    }

    /// Preamp dB + fader dB in every state the desk went through, against `start`'s.
    static func drift(_ mixer: FakeXAirMixer, gain: String, start: (gain: Double, fader: Double)) -> [Double] {
        mixer.history.map { applied in
            func db(_ address: String, _ scale: X32Values, _ otherwise: Double) -> Double {
                guard case .float(let f)? = applied[address] else { return otherwise }
                return scale.db(ofOSC: f)
            }
            return db(gain, .headampGain, start.gain) + db(fader, .fader, start.fader) - (start.gain + start.fader)
        }
    }

    static func expectSteady(_ drift: [Double], _ comment: Comment) {
        #expect(!drift.isEmpty)
        // One step, plus the preamp's 0.25 dB grid and the fader's: in-between values round down.
        #expect(drift.min()! >= -XAirDriver.rampStepDb - 0.5, "never more than one ramp step down: \(comment)")
        #expect(drift.max()! <= 0.1, "never louder: \(comment)")
    }

    @Test("X-Air ch 1, +14 → +37 dB with the fader 0 → -23: every state the desk applies keeps preamp + fader within one ramp step")
    func xAirBoost() async throws {
        let mixer = try await FakeXAirMixer(Self.desk(headamp: 1, gainDb: 14, faderDb: 0))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 23)

        #expect(step.toGainDb == 37)
        Self.expectSteady(Self.drift(mixer, gain: "/headamp/01/gain", start: (14, 0)), "boost")
    }

    /// Measured on Eric's XR18 (#688): the preamp lands at once, the fader eases in over about 70 ms. Recorded at main
    /// L/R, a 1 dB ramp with the fader sent 5 ms ahead of the gain came out up to 2 dB loud; one 6 dB step, 7 dB loud.
    static func easingDesk(gainDb: Double, faderDb: Double) -> FakeXAirMixer.State {
        var state = desk(headamp: 1, gainDb: gainDb, faderDb: faderDb)
        state.gainLag = 0
        state.faderEase = 0.07
        return state
    }

    @Test("X-Air ch 1, +6 dB on a desk that eases the fader in over 70 ms: never louder, at most one ramp step down")
    func xAirBoostEasedFader() async throws {
        let mixer = try await FakeXAirMixer(Self.easingDesk(gainDb: 14, faderDb: 0))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.toGainDb == 20)
        Self.expectSteady(Self.drift(mixer, gain: "/headamp/01/gain", start: (14, 0)), "boost, fader eased")
    }

    @Test("X-Air ch 1, Undo of +6 dB on a desk that eases the fader in: never louder")
    func xAirUndoEasedFader() async throws {
        let mixer = try await FakeXAirMixer(Self.easingDesk(gainDb: 14, faderDb: 0))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        try await Task.sleep(for: .milliseconds(100))   // the boost's last fader has eased in
        let boost = mixer.history.count

        try await driver.undo(step)

        let undo = Array(Self.drift(mixer, gain: "/headamp/01/gain", start: (14, 0)).dropFirst(boost))
        #expect(undo.max()! <= 0.1, "never louder: undo, fader eased")
    }

    @Test("X-Air ch 1, a -6 dB cut and its Undo on a desk that eases the fader in: never louder")
    func xAirCutAndUndoEasedFader() async throws {
        let mixer = try await FakeXAirMixer(Self.easingDesk(gainDb: 20, faderDb: -6))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: -6)
        try await Task.sleep(for: .milliseconds(100))   // the cut's last fader has eased in
        let cut = mixer.history.count
        try await driver.undo(step)
        try await Task.sleep(for: .milliseconds(100))
        _ = try await driver.identify()                  // a packet, so the last eased fader is recorded

        let drift = Self.drift(mixer, gain: "/headamp/01/gain", start: (20, -6))
        #expect(step.toGainDb == 14)
        #expect(drift[..<cut].max()! <= 0.1, "never louder: cut, fader eased")
        Self.expectSteady(Array(drift[cut...]), "Undo of the cut, fader eased")
    }

    @Test("X-Air ch 1, +23 dB in 3 dB steps: eight gain writes, each at most 3 dB (Eric, #688)")
    func xAirBoostInThreeDbSteps() async throws {
        let mixer = try await FakeXAirMixer(Self.easingDesk(gainDb: 14, faderDb: 0))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 23)

        let gains = mixer.writes.filter { $0.address == "/headamp/01/gain" }.compactMap { write -> Double? in
            guard case .float(let f) = write.value else { return nil }
            return X32Values.headampGain.db(ofOSC: f)
        }
        #expect(gains.count == 8)
        #expect(zip([14] + gains, gains).allSatisfy { $1 - $0 <= 3.01 })
        Self.expectSteady(Self.drift(mixer, gain: "/headamp/01/gain", start: (14, 0)), "3 dB steps, fader eased")
    }

    /// Every write in order on a cut, as gain and fader dB: the fader may never have risen more than the gain has dropped.
    static func faderNeverAhead(_ mixer: FakeXAirMixer, gain: String, fader: String, start: (gain: Double, fader: Double)) -> [String] {
        var g = start.gain, f = start.fader, bad: [String] = []
        for write in mixer.writes {
            guard case .float(let v) = write.value else { continue }
            if write.address == gain { g = X32Values.headampGain.db(ofOSC: v) }
            if write.address == fader { f = X32Values.fader.db(ofOSC: v) }
            if (f - start.fader) > (start.gain - g) + 0.5 { bad.append(String(format: "gain %.2f fader %.2f", g, f)) }
        }
        return bad
    }

    @Test("Clip turn-downs (-3 and -6 dB) write the preamp down before each fader step up, in order", arguments: [-3.0, -6.0])
    func clipTurnDownOrder(cut: Double) async throws {
        let mixer = try await FakeXAirMixer(Self.easingDesk(gainDb: 38.5, faderDb: -10))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: cut)

        #expect(step.toGainDb == 38.5 + cut)
        #expect(Self.faderNeverAhead(mixer, gain: "/headamp/01/gain", fader: Self.fader, start: (38.5, -10)).isEmpty)
    }

    @Test("A clip turn-down with the fader near its +10 dB top cuts the preamp only as far as the fader can follow")
    func turnDownAtFaderTop() async throws {
        let mixer = try await FakeXAirMixer(Self.easingDesk(gainDb: 38.5, faderDb: 8))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: -6)

        #expect(step.toGainDb >= 36.5 - 0.01, "only the 2 dB the fader can make up")
        #expect(step.limitedBy != nil)
    }

    @Test("X-Air ch 1, Undo of the +23 dB boost: the preamp comes down before the fader comes up")
    func xAirUndo() async throws {
        let mixer = try await FakeXAirMixer(Self.desk(headamp: 1, gainDb: 14, faderDb: 0))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 23)
        let boost = mixer.history.count

        try await driver.undo(step)

        Self.expectSteady(Array(Self.drift(mixer, gain: "/headamp/01/gain", start: (14, 0)).dropFirst(boost)), "undo")
    }

    @Test("X-Air ch 1, a -23 dB cut (clip protection's turn-down) from +37 with the fader at -23")
    func xAirCut() async throws {
        let mixer = try await FakeXAirMixer(Self.desk(headamp: 1, gainDb: 37, faderDb: -23))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: -23)

        #expect(step.toGainDb == 14)
        Self.expectSteady(Self.drift(mixer, gain: "/headamp/01/gain", start: (37, -23)), "cut")
    }

    @Test("X32 ch 1 on headamp 0, +14 → +37 dB: the same")
    func x32Boost() async throws {
        let mixer = try await FakeXAirMixer(Self.desk(.x32(), headamp: 0, gainDb: 14, faderDb: 0))
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 23)

        #expect(step.toGainDb == 37)
        Self.expectSteady(Self.drift(mixer, gain: "/headamp/000/gain", start: (14, 0)), "X32 boost")
    }
}
