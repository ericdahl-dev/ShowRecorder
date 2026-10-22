import AutoGain
@testable import MixerLink
import OSC
import Testing

/// Setting an X-Air channel's preamp gain with Mix Hold (#153). Addresses and scales as read on Eric's XR18
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
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.headamp(ofChannel: 1) == 1)
        #expect(try await driver.headamp(ofChannel: 3) == 17)
        #expect(try await driver.headamp(ofChannel: 4) == nil)
        #expect(try await driver.headamp(ofChannel: 5) == 8)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 14.5)
    }

    @Test("Reads a channel's Mix Hold state: thresholds, fader, and its 10 sends, each pre or post from its own tap; no mono")
    func readsMixHoldState() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let state = try await driver.mixHoldState(ofChannel: 1)

        #expect(state.gateThresholdDb == -18.5)
        #expect(state.compressorThresholdDb == -25)
        #expect(abs((state.mainFaderDb ?? 0) - -6.2) < 0.05)
        #expect(state.otherMainsDb.isEmpty)
        #expect(state.sends.count == 10)
        #expect(state.sends.first { $0.bus == 7 } == MixHold.Send(bus: 7, levelDb: -8.5, preFader: true))
        #expect(state.sends.first { $0.bus == 1 }?.preFader == false, "POST")
    }

    @Test("Finds gates and compressors keyed from a channel: on the X-Air a key is a channel (1-16), 0 is SELF")
    func keyed() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.keyedDynamics(from: 1) == [MixHold.KeyedDynamics(channel: 2, dynamics: .compressor, thresholdDb: -30, keyChannel: 1)])
        #expect(try await driver.keyedDynamics(from: 3).isEmpty)
    }

    @Test("USB Channels map to input channels from the routing; the aux return has no preamp to move")
    func usbToChannel() async throws {
        var state = Self.kickDesk()
        state.usbRouting?[0] = [4, 0]          // USB 1 carries Ch05
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        _ = try await driver.sources(usbChannelCount: 18)

        #expect(driver.channel(forUSBChannel: 1) == 5)
        #expect(driver.channel(forUSBChannel: 2) == 2)
        #expect(driver.channel(forUSBChannel: 17) == nil)
    }

    @Test("+12 dB ramps, never makes the channel louder in the mix, ends on the plan, and undo puts it all back; the desk's echoes don't confuse it")
    func applyAndUndo() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = try await driver.mixHoldState(ofChannel: 1)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 12, scopes: .all)

        #expect(step.headamp == 1 && step.fromGainDb == 14.5 && step.toGainDb == 26.5)
        #expect(step.held[MixHold.Setting(channel: 1, parameter: .gateThreshold)] == -6.5)
        #expect(step.held[MixHold.Setting(channel: 1, parameter: .send(7))] == -20.5)
        #expect(step.held[MixHold.Setting(channel: 2, parameter: .compressorThreshold)] == -18)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 26.5)
        #expect(Self.loudestRise(mixer.writes) <= 0.3)

        try await driver.undo(step)
        #expect(try await driver.mixHoldState(ofChannel: 1) == before)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 14.5)
        #expect(try await driver.mixHoldState(ofChannel: 2).compressorThresholdDb == -30, "the keyed compressor goes back too (#393)")
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

    @Test("A stereo-linked pair with its preamps linked is one preamp move: channel 2 answers channel 1's preamp (#458)")
    func linkedPairPreamp() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0].inputSource = 0
        state.channels[1].inputSource = 1
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.preamp(ofChannel: 2) == 2)
        mixer.update { $0.set["/config/chlink/1-2"] = .int(1) }
        #expect(try await driver.preamp(ofChannel: 2) == 2, "linked strips, but each keeps its own preamp")
        mixer.update { $0.set["/config/linkcfg/preamp"] = .int(1) }
        #expect(try await driver.preamp(ofChannel: 2) == 1)
        #expect(try await driver.preamp(ofChannel: 1) == 1)
    }

    @Test("A pair whose strips are linked is one lane for clip protection, its first channel; unlinked, none (#554)")
    func linkedStripsLane() async throws {
        let mixer = try await FakeXAirMixer(FakeXAirMixer.State())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.lane(ofChannel: 2) == nil)
        mixer.update { $0.set["/config/chlink/1-2"] = .int(1) }
        #expect(try await driver.lane(ofChannel: 1) == 1)
        #expect(try await driver.lane(ofChannel: 2) == 1)
        #expect(try await driver.lane(ofChannel: 3) == nil)
    }

    @Test("A preamp-linked pair: Mix Hold on channel 1 compensates channel 2's strip too, and Undo puts both back (#393)")
    func linkedPartnerCompensated() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0].inputSource = 0
        state.channels[1].inputSource = 1
        state.usbRouting = XAirDriverTests.defaultRouting
        state.set["/config/chlink/1-2"] = .int(1)
        state.set["/config/linkcfg/preamp"] = .int(1)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = try await driver.mixHoldState(ofChannel: 2)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        let fader2 = try #require(step.changes.first { $0.setting == MixHold.Setting(channel: 2, parameter: .mainFader) })
        #expect(abs(fader2.toDb - (fader2.fromDb - 6)) < 0.05)
        #expect(step.changes.contains { $0.setting == MixHold.Setting(channel: 2, parameter: .gateThreshold) })
        try await driver.undo(step)
        #expect(try await driver.mixHoldState(ofChannel: 2) == before)
    }

    @Test("Two channels on one input: Mix Hold on channel 1 compensates channel 5 too, and Undo puts it back (#874)")
    func sharedPreampCompensatesBoth() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0].inputSource = 0
        state.channels[4].inputSource = 0   // channel 5 on In01, like channel 1
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = try await driver.mixHoldState(ofChannel: 5)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        let fader5 = try #require(step.changes.first { $0.setting == MixHold.Setting(channel: 5, parameter: .mainFader) })
        #expect(abs(fader5.toDb - (fader5.fromDb - 6)) < 0.05)
        #expect(!step.changes.contains { $0.setting.channel == 2 }, "channel 2 is on its own input")
        try await driver.undo(step)
        #expect(try await driver.mixHoldState(ofChannel: 5) == before)
    }

    @Test("A linked partner that also shares the preamp is compensated once, not twice (#874)")
    func partnerOnSharedPreampCountedOnce() async throws {
        var state = FakeXAirMixer.State()
        state.channels[1].inputSource = 0   // channel 2 on In01 as well as channel 1
        state.usbRouting = XAirDriverTests.defaultRouting
        state.set["/config/chlink/1-2"] = .int(1)
        state.set["/config/linkcfg/preamp"] = .int(1)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.changes.filter { $0.setting == MixHold.Setting(channel: 2, parameter: .mainFader) }.count == 1)
    }

    @Test("A channel whose input is OFF or the aux line in is not moved with an In01 channel (#874)")
    func otherInputsLeftAlone() async throws {
        var state = FakeXAirMixer.State()
        state.channels[2].inputSource = 18   // OFF
        state.channels[3].inputSource = 16   // aux line in L
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.changes.allSatisfy { $0.setting.channel == 1 })
    }

    /// The input source queries a Mix Hold call made, per channel.
    static func inputQueries(_ mixer: FakeXAirMixer, after count: Int) -> [String] {
        mixer.queries.dropFirst(count).filter { $0.hasSuffix("/config/insrc") }
    }

    @Test("The channel-to-preamp routing is read once: a second Mix Hold call asks no other channel's input (#874)")
    func routingReadOnce() async throws {
        var state = FakeXAirMixer.State()
        state.channels[4].inputSource = 0
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)
        let seen = mixer.queries.count

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)

        #expect(Self.inputQueries(mixer, after: seen) == ["/ch/01/config/insrc"], "only the channel asked for is read fresh")
        #expect(step.changes.contains { $0.setting == MixHold.Setting(channel: 5, parameter: .mainFader) }, "channel 5 is still compensated")
    }

    @Test("Live updates that stop being renewed mark the routing stale, so it is read again (#874)")
    func lapsedLiveUpdatesMarkStale() async throws {
        var state = FakeXAirMixer.State()
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Self.lostQueryTimeout)
        await driver.readPreamps()
        #expect(!driver.preampMap.snapshot().isStale)

        mixer.update { $0.answers = false }
        await #expect(throws: MixerLinkProblem.self) { try await driver.renewLiveUpdates() }

        #expect(driver.preampMap.snapshot().isStale)
    }

    @Test("Reading the routing ahead leaves the first Mix Hold call asking only the channel it moves (#874)")
    func readAhead() async throws {
        var state = FakeXAirMixer.State()
        state.channels[4].inputSource = 0
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        await driver.readPreamps()
        let seen = mixer.queries.count

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)

        #expect(Self.inputQueries(mixer, after: seen) == ["/ch/01/config/insrc"])
        #expect(step.changes.contains { $0.setting == MixHold.Setting(channel: 5, parameter: .mainFader) })
    }

    @Test("A pushed input change reads the routing again: channel 5 moved off In01 is no longer compensated (#874)")
    func pushedInputChangeRefreshes() async throws {
        var state = FakeXAirMixer.State()
        state.channels[4].inputSource = 0
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()
        _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)

        mixer.setInput(channel: 5, to: 4)   // back on In05
        mixer.rename(channel: 2, to: "Snare")
        #expect(await changes.next() == SourceChange(usbChannel: 2, name: "Snare"), "the input change came before it, in order")
        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)

        #expect(!step.changes.contains { $0.setting.channel == 5 })
    }

    @Test("Channel 1 now answers another preamp than held: the routing is read again, not trusted (#874)")
    func askedChannelMismatchRefreshes() async throws {
        var state = FakeXAirMixer.State()
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)
        mixer.update { $0.channels[0].inputSource = 4; $0.channels[4].inputSource = 0 }   // ch1 and ch5 swap, nothing pushed

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)

        #expect(step.changes.allSatisfy { $0.setting.channel == 1 }, "ch1 is on preamp 5 alone now; ch5 on preamp 1")
    }

    /// How long a query waits before it counts as lost, for the tests that need one to be. Every query of such a test
    /// shares it, so it has to be long enough for the loopback fake to answer under a loaded full run; the one lost
    /// query waits it out once.
    static let lostQueryTimeout: Duration = .seconds(3)

    @Test("One channel's input query lost: the move still happens, that channel is left out, and the rest are not waited for (#874)")
    func lostQueryDoesNotFailTheMove() async throws {
        var state = FakeXAirMixer.State()
        state.channels[6].inputSource = 0   // channel 7 shares In01 with channel 1 but its answer is lost
        state.silentAddresses = ["/ch/07/config/insrc"]
        state.channels[8].inputSource = 0   // channel 9 shares too and would be asked after channel 7
        state.usbRouting = XAirDriverTests.defaultRouting
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Self.lostQueryTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)

        #expect(step.toGainDb > step.fromGainDb, "the move went ahead")
        #expect(!mixer.queries.contains("/ch/09/config/insrc"), "the read stopped at the lost query")
        #expect(!step.changes.contains { $0.setting.channel == 7 })

        mixer.update { $0.silentAddresses = [] }   // the next call asks again, and only for what is missing
        let seen = mixer.queries.count
        let next = try await driver.applyMixHold(channel: 1, gainChangeDb: 3)
        let asked = Self.inputQueries(mixer, after: seen)
        #expect(asked == (([1] + Array(7...16)).map { String(format: "/ch/%02d/config/insrc", $0) }), "channels 2-6 were read and are not asked again")
        #expect(next.changes.contains { $0.setting == MixHold.Setting(channel: 7, parameter: .mainFader) })
        #expect(next.changes.contains { $0.setting == MixHold.Setting(channel: 9, parameter: .mainFader) })
    }

    @Test("Linked strips without linked preamps: Mix Hold on channel 1 leaves channel 2 alone")
    func linkedStripsOnly() async throws {
        var state = FakeXAirMixer.State()
        state.channels[1].inputSource = 1
        state.set["/config/chlink/1-2"] = .int(1)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(!step.changes.contains { $0.setting.channel == 2 })
    }

    @Test("-6 dB and back: a cut compensates the other way, and Undo restores everything exactly (#393)")
    func cutAndUndo() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = (try await driver.mixHoldState(ofChannel: 1), try await driver.mixHoldState(ofChannel: 2))

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: -6, scopes: .all)
        #expect(step.toGainDb == 8.5)
        #expect(step.held[MixHold.Setting(channel: 1, parameter: .gateThreshold)] == -24.5)
        try await driver.undo(step)

        #expect(try await driver.mixHoldState(ofChannel: 1) == before.0)
        #expect(try await driver.mixHoldState(ofChannel: 2) == before.1)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 14.5)
    }

    @Test("With only the gate in scope, Mix Hold moves the gain and the gate threshold and nothing else (#393)")
    func scopeThroughTheDriver() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 4, scopes: .gate)

        #expect(step.changes.map(\.setting) == [MixHold.Setting(channel: 1, parameter: .gateThreshold)])
        #expect(!mixer.writes.contains { $0.address == "/ch/01/mix/fader" })
    }

    @Test("Each step reads the mixer fresh: a fader moved by hand between two steps is compensated from where it now is (#393)")
    func readsFreshEachStep() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        _ = try await driver.applyMixHold(channel: 1, gainChangeDb: 2, scopes: .all)
        mixer.update { $0.set["/ch/01/mix/fader"] = .float(0.75) }   // someone pushes the fader to 0 dB

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 2, scopes: .all)

        let fader = try #require(step.changes.first { $0.setting == MixHold.Setting(channel: 1, parameter: .mainFader) })
        #expect(abs(fader.fromDb) < 0.05)
        #expect(abs(fader.toDb - -2) < 0.05)
    }
    @Test("Reads what each gate and compressor listens to: its own signal, another channel, or a bus (#497)")
    func readsKeys() async throws {
        var state = Self.kickDesk()       // channel 2's compressor keyed from channel 1
        state.channels[2].gateKey = 17    // channel 3's gate keyed from a bus
        state.channels[3].gateKey = 4     // channel 4's gate keyed from channel 4: its own signal
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.mixHoldState(ofChannel: 1).gateKey == .own)
        #expect(try await driver.mixHoldState(ofChannel: 2).compressorKey == .channel(1))
        #expect(try await driver.mixHoldState(ofChannel: 3).gateKey == .elsewhere)
        #expect(try await driver.mixHoldState(ofChannel: 4).gateKey == .own)
    }

    @Test("Moving channel 2's preamp leaves its compressor keyed from channel 1 where it is: it doesn't hear that preamp (#497)")
    func keyedFromAnotherChannelStays() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 2, gainChangeDb: 6)

        #expect(!step.changes.contains { $0.setting == MixHold.Setting(channel: 2, parameter: .compressorThreshold) })
        #expect(try await driver.mixHoldState(ofChannel: 2).compressorThresholdDb == -30)
    }
    @Test("Channel 2's compressor keyed from channel 1: move 1, move 2, undo 1, and channel 2's own move stays (#497)")
    func undoOneKeepsTheOther() async throws {
        let mixer = try await FakeXAirMixer(Self.kickDesk())
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let before = try await driver.mixHoldState(ofChannel: 2)

        let first = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        _ = try await driver.applyMixHold(channel: 2, gainChangeDb: 4)
        let afterTwo = try await driver.mixHoldState(ofChannel: 2)
        try await driver.undo(first)

        let now = try await driver.mixHoldState(ofChannel: 2)
        #expect(now.compressorThresholdDb == before.compressorThresholdDb, "channel 1's share is gone")
        #expect(now.mainFaderDb == afterTwo.mainFaderDb, "channel 2's own move stays")
        #expect(now.mainFaderDb != before.mainFaderDb)
    }

    @Test("A gate at 0 dB and a compressor at -3 dB, both off: +6 dB moves only the preamp, with no end stop (#685)")
    func dynamicsOffLeftAlone() async throws {
        var state = Self.kickDesk()
        state.channels[0].gateOn = 0
        state.channels[0].compressorOn = 0
        state.channels[0].gateThreshold = 1         // 0 dB
        state.channels[0].compressorThreshold = 0.95   // -3 dB: on, +6 would stop at +3
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.limitedBy == nil)
        #expect(step.toGainDb == 20.5)
        #expect(!step.changes.contains { $0.setting.channel == 1 && !$0.setting.parameter.isLevel })
        #expect(!mixer.writes.contains { $0.address.hasPrefix("/ch/01/") && $0.address.hasSuffix("/thr") })
    }

    @Test("A compressor that's off on channel 2, keyed from channel 1 and at -3 dB: +6 dB on channel 1 leaves it alone (#685)")
    func keyedDynamicsOffLeftAlone() async throws {
        var state = Self.kickDesk()                 // channel 2's compressor keyed from channel 1
        state.channels[1].compressorOn = 0
        state.channels[1].compressorThreshold = 0.95   // -3 dB: on, +6 would stop at +3
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.limitedBy == nil)
        #expect(!step.changes.contains { $0.setting == MixHold.Setting(channel: 2, parameter: .compressorThreshold) })
        #expect(!mixer.writes.contains { $0.address == "/ch/02/dyn/thr" })
    }

    @Test("A gate that's on at 0 dB still stops a boost at its end stop (#685)")
    func dynamicsOnStillStops() async throws {
        var state = Self.kickDesk()
        state.channels[0].gateThreshold = 1         // 0 dB
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.limitedBy == MixHold.Limit(setting: MixHold.Setting(channel: 1, parameter: .gateThreshold), endDb: 0))
    }

    @Test("A compressor that's on at the top of its range (0 dB) never acts: a -6 dB cut doesn't lower it (#685)")
    func compressorAtTopLeftAlone() async throws {
        var state = Self.kickDesk()
        state.channels[0].compressorThreshold = 1   // 0 dB, the top of -60...0
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: -6)

        #expect(step.limitedBy == nil)
        #expect(!step.changes.contains { $0.setting == MixHold.Setting(channel: 1, parameter: .compressorThreshold) })
        #expect(!mixer.writes.contains { $0.address == "/ch/01/dyn/thr" })
    }

    @Test("A gate that's on at the bottom of its range (-80 dB) is always open: a +6 dB boost doesn't raise it (#685)")
    func gateAtBottomLeftAlone() async throws {
        var state = Self.kickDesk()
        state.channels[0].gateThreshold = 0         // -80 dB, the bottom of -80...0
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.limitedBy == nil)
        #expect(!step.changes.contains { $0.setting == MixHold.Setting(channel: 1, parameter: .gateThreshold) })
        #expect(!mixer.writes.contains { $0.address == "/ch/01/gate/thr" })
    }

    @Test("Eric's XR18, channel 1: gate and compressor off, compressor at -6.5, gate at -80, fader -24.7; +10 dB moves only the preamp and the fader (#685)")
    func dynamicsOffOnEricsXR18() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0].gateOn = 0
        state.channels[0].compressorOn = 0
        state.channels[0].compressorThreshold = 0.89167   // -6.5 dB
        state.channels[0].gateThreshold = 0               // -80 dB
        state.channels[0].fader = 0.31625                 // -24.7 dB
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 10)

        #expect(step.limitedBy == nil)
        #expect(step.toGainDb - step.fromGainDb == 10)
        #expect(step.changes.map(\.setting) == [MixHold.Setting(channel: 1, parameter: .mainFader)])
        #expect(!mixer.writes.contains { $0.address.hasSuffix("/thr") })
    }

    @Test("A gate that's off on channel 3, keyed from channel 1 and at -3 dB: +6 dB on channel 1 leaves it alone (#685)")
    func keyedGateOffLeftAlone() async throws {
        var state = Self.kickDesk()
        state.channels[2].gateKey = 1               // channel 3's gate keyed from channel 1 (In01 on the X32)
        state.channels[2].gateOn = 0
        state.channels[2].gateThreshold = 0.9625    // -3 dB: on, +6 would stop at +3
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let step = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)

        #expect(step.limitedBy == nil)
        #expect(!step.changes.contains { $0.setting == MixHold.Setting(channel: 3, parameter: .gateThreshold) })
        #expect(!mixer.writes.contains { $0.address == "/ch/03/gate/thr" })
    }

    @Test("Keyed dynamics that are on but do nothing (a compressor at 0 dB, a gate at -80 dB) are left alone, with no end stop (#685)")
    func keyedDynamicsIdleLeftAlone() async throws {
        var state = Self.kickDesk()                 // channel 2's compressor keyed from channel 1
        state.channels[1].compressorThreshold = 1   // 0 dB, the top of -60...0
        state.channels[2].gateKey = 1               // channel 3's gate keyed from channel 1 (In01 on the X32)
        state.channels[2].gateThreshold = 0         // -80 dB, the bottom of -80...0
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let boost = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        let cut = try await driver.applyMixHold(channel: 1, gainChangeDb: -12)

        #expect(boost.limitedBy == nil && cut.limitedBy == nil)
        #expect(!(boost.changes + cut.changes).contains { $0.setting.channel != 1 })
        #expect(!mixer.writes.contains { $0.address == "/ch/02/dyn/thr" || $0.address == "/ch/03/gate/thr" })
    }

    @Test("A compressor on at -3 dB: +6 dB stops at +3 with its end stop, and the next step, given what auto-gain moved, stays stopped (#685)")
    func movedToEdgeStillStops() async throws {
        var state = Self.kickDesk()
        state.channels[0].compressorThreshold = 0.95   // -3 dB
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let compressor = MixHold.Limit(setting: MixHold.Setting(channel: 1, parameter: .compressorThreshold), endDb: 0)

        let first = try await driver.applyMixHold(channel: 1, gainChangeDb: 6)
        let second = try await driver.applyMixHold(channel: 1, gainChangeDb: 3, live: Set(first.changes.map(\.setting)))

        #expect(first.toGainDb - first.fromGainDb == 3 && first.limitedBy == compressor)
        #expect(second.toGainDb == second.fromGainDb && second.limitedBy == compressor)
    }

    @Test("A gate on at -77 dB: -6 dB stops at -3 with its end stop, and the next cut, given what auto-gain moved, stays stopped (#685)")
    func gateMovedToBottomStillStops() async throws {
        var state = Self.kickDesk()
        state.channels[0].gateThreshold = 0.0375    // -77 dB
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let gate = MixHold.Limit(setting: MixHold.Setting(channel: 1, parameter: .gateThreshold), endDb: -80)

        let first = try await driver.applyMixHold(channel: 1, gainChangeDb: -6)
        let second = try await driver.applyMixHold(channel: 1, gainChangeDb: -3, live: Set(first.changes.map(\.setting)))

        #expect(first.toGainDb - first.fromGainDb == -3 && first.limitedBy == gate)
        #expect(second.toGainDb == second.fromGainDb && second.limitedBy == gate)
    }
}
