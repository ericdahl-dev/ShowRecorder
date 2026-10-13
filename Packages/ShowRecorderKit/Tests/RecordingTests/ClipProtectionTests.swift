import Foundation
import TakeFile
@testable import Recording
import Testing

/// Meter windows as `PeakMeters.takeLevels()` gives them: 1,600 frames is about 33 ms at 48 kHz.
enum Windows {
    static let frames = 1_600

    static func at(_ dbfs: Double, frames: Int = frames) -> ChannelLevel {
        ChannelLevel(peak: Float(pow(10, dbfs / 20)), meanRectified: 0.01, frames: frames)
    }

    static let clip = ChannelLevel(peak: 1, meanRectified: 0.1, frames: frames)

    static func repeating(_ level: ChannelLevel, _ count: Int) -> [ChannelLevel] {
        Array(repeating: level, count: count)
    }
}

@Suite("Clip trigger")
struct ClipTriggerTests {
    static func run(_ windows: [ChannelLevel]) -> Double? {
        var trigger = ClipTrigger(sampleRate: 48_000)
        var fired: Double?
        for window in windows where fired == nil { fired = trigger.observe(window) }
        return fired
    }

    @Test("A peak above -3 dBFS held for 300 ms fires, with the highest peak it saw")
    func sustained() throws {
        // 10 windows of 33 ms = 333 ms.
        let windows = [Windows.at(-2), Windows.at(-1.5)] + Windows.repeating(Windows.at(-2), 8)
        let fired = try #require(Self.run(windows))
        #expect(abs(fired - -1.5) < 0.01)
    }

    @Test("A lone hot transient, a kick at -1 dBFS between quiet windows, doesn't fire")
    func transient() {
        let hit = [Windows.at(-1)] + Windows.repeating(Windows.at(-20), 14)
        #expect(Self.run(Array(Array(repeating: hit, count: 10).joined())) == nil)
    }

    @Test("One window dipping to -4 in a held note (vibrato, bass decay) doesn't restart the 300 ms; two in a row do")
    func dip() {
        let held = Windows.repeating(Windows.at(-2), 5)
        #expect(Self.run(held + [Windows.at(-4)] + held) != nil)
        #expect(Self.run(held + Windows.repeating(Windows.at(-4), 2) + held) == nil)
    }

    @Test("A late read, one 500 ms window holding a single transient, counts as one window, not 500 ms")
    func lateRead() {
        #expect(Self.run([Windows.at(-1, frames: 24_000)]) == nil)
    }

    @Test("Three clips within 2 s fire at full scale; a single clip doesn't")
    func clips() {
        let gap = Windows.repeating(Windows.at(-12), 15)   // 500 ms
        #expect(Self.run([Windows.clip] + gap + [Windows.clip] + gap + [Windows.clip]) == 0)
        #expect(Self.run([Windows.clip] + gap) == nil)
    }

    @Test("Three clipping windows in a row are one clip, however often the meters are read")
    func clipRun() {
        #expect(Self.run(Windows.repeating(Windows.clip, 3) + Windows.repeating(Windows.at(-12), 30)) == nil)
    }
}

@Suite("Clip protection step")
struct ClipProtectionStepTests {
    @Test("The step brings the peak to -6 dBFS, at most 6 dB down; a clip reads full scale, so it takes the full 6 dB")
    func step() {
        #expect(ClipProtection.stepDb(peakDbfs: -2) == -4)
        #expect(ClipProtection.stepDb(peakDbfs: -3) == -3)
        #expect(ClipProtection.stepDb(peakDbfs: 0) == -6)
    }

    @Test("The step is in whole half-dB, the preamp's resolution, rounded to turn down more, never less")
    func halfDb() {
        #expect(ClipProtection.stepDb(peakDbfs: -2.7) == -3.5)
        #expect(ClipProtection.stepDb(peakDbfs: -1.999_99) == -4)
    }

    @Test("A Peak already below -6 never turns a preamp up")
    func neverUp() {
        #expect(ClipProtection.stepDb(peakDbfs: -10) == 0)
    }
}

@MainActor
@Suite("Clip protection")
struct ClipProtectionTests {
    let control = FakeGainControl(gainDb: [1: 30, 2: 30], channelOfUSB: [1: 1, 2: 2, 3: 1])

    /// Feeds each window to every USB Channel listed, the others quiet, 3 channels in all.
    static func feed(_ protection: ClipProtection, _ windows: [ChannelLevel], on usbChannels: Set<Int> = [1]) async {
        for window in windows {
            let quiet = Windows.at(-30, frames: window.frames)
            await protection.observe((1...3).map { usbChannels.contains($0) ? window : quiet })
        }
    }

    static let hot = Windows.repeating(Windows.at(-2), 10)

    @Test("A held hot Peak turns that channel's preamp down to put the Peak at -6, and logs it as clip protection")
    func turnsDown() async {
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        await Self.feed(protection, Self.hot)

        #expect(control.gainDb == [1: 26, 2: 30])
        #expect(logged.map(\.reason) == [.clipProtection])
        #expect(logged.first?.usbChannel == 1)
        #expect(logged.first?.toGainDb == 26)
    }

    @Test("After a move the channel is left alone for 5 s, then may move again")
    func rateLimit() async {
        let protection = ClipProtection(control: control, sampleRate: 48_000)

        await Self.feed(protection, Self.hot + Self.hot)
        #expect(control.gainDb[1] == 26)

        await Self.feed(protection, Windows.repeating(Windows.at(-20), 150) + Self.hot)
        #expect(control.gainDb[1] == 22)
    }

    @Test("A channel turns down at most 12 dB in a Take; a new Take starts the count again")
    func budget() async {
        let protection = ClipProtection(control: control, sampleRate: 48_000)
        let clipping = Windows.repeating(Windows.clip, 10) + Windows.repeating(Windows.at(-20), 150)

        await Self.feed(protection, clipping + clipping + clipping)
        #expect(control.gainDb[1] == 18)

        protection.takeStarted()
        await Self.feed(protection, clipping)
        #expect(control.gainDb[1] == 12)
    }

    @Test("Two USB Channels carrying one Mixer channel, both hot, move its preamp once")
    func sameChannel() async {
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        await Self.feed(protection, Self.hot, on: [1, 3])

        #expect(control.gainDb == [1: 26, 2: 30])
        #expect(logged.map(\.usbChannel) == [1])
    }

    /// Channels 1 and 2 on one preamp (a shared X32 headamp, or a stereo-linked pair): a move on either lands on 1.
    func sharePreamp() {
        control.preampOf = [2: 1]
        control.movesInstead = [2: 1]
    }

    @Test("Two Mixer channels on one preamp, both hot in one read, turn it down once (#458)")
    func samePreampOnce() async {
        sharePreamp()
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        await Self.feed(protection, Self.hot, on: [1, 2])

        #expect(control.gainDb == [1: 26, 2: 30])
        #expect(logged.count == 1)
    }

    @Test("The 12 dB a Take allows counts the preamp once, whichever of its channels runs hot (#458)")
    func samePreampBudget() async {
        sharePreamp()
        let protection = ClipProtection(control: control, sampleRate: 48_000)
        let clipping = Windows.repeating(Windows.clip, 10) + Windows.repeating(Windows.at(-20), 150)

        await Self.feed(protection, clipping + clipping, on: [1])
        await Self.feed(protection, clipping + clipping, on: [2])

        #expect(control.gainDb[1] == 18)
    }

    @Test("A turn-down the mixer stops answering partway is still logged and counted in the Take's 12 dB (#450)")
    func interruptedTurnDown() async {
        control.interruptsHalfway = true
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        await Self.feed(protection, Self.hot)

        #expect(control.gainDb[1] == 28)
        #expect(logged.map(\.toGainDb) == [28])
    }

    @Test("When the Mixer doesn't answer, nothing is logged and the meters keep going; it tries again after the rest")
    func mixerProblem() async {
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })
        control.problem = .other("no answer")

        await Self.feed(protection, Self.hot)
        #expect(logged.isEmpty)

        control.problem = nil
        await Self.feed(protection, Windows.repeating(Windows.at(-20), 150) + Self.hot)
        #expect(control.gainDb[1] == 26)
        #expect(logged.count == 1)
    }

    @Test("A preamp already at its lowest gain doesn't move, and nothing is logged or Marked")
    func atFloor() async {
        var logged: [TakeMetadata.GainChange] = []
        control.gainDb[1] = -12
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        await Self.feed(protection, Self.hot)

        #expect(control.gainDb[1] == -12)
        #expect(logged.isEmpty)
    }

    @Test("A meter read while a slow Mixer is still answering, a disarm leaving no channels, doesn't crash or move twice")
    func readDuringMove() async {
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.answer = {
            enter.yield()
            for await _ in released { return }
        }
        let protection = ClipProtection(control: control, sampleRate: 48_000)

        let moving = Task { await Self.feed(protection, Self.hot + Self.hot) }
        for await _ in entered { break }
        await protection.observe([])
        release.yield()
        await moving.value

        #expect(control.gainDb[1] == 26)
    }

    @Test("Three separate clips in 2 s take a full 6 dB; the last move of a Take takes only what's left of the 12 dB")
    func clipsAndWhatsLeft() async {
        let protection = ClipProtection(control: control, sampleRate: 48_000)
        let rest = Windows.repeating(Windows.at(-20), 150)
        let gap = Windows.repeating(Windows.at(-12), 15)
        let clips = [Windows.clip] + gap + [Windows.clip] + gap + [Windows.clip] + rest

        await Self.feed(protection, Self.hot + rest)
        #expect(control.gainDb[1] == 26)
        await Self.feed(protection, clips)
        #expect(control.gainDb[1] == 20)
        await Self.feed(protection, clips)
        #expect(control.gainDb[1] == 18)
    }
}

@Suite("Clip protection setting")
struct ClipProtectionSettingTests {
    static func defaults() -> UserDefaults {
        let name = "ClipProtectionSettingTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("Off until the operator switches it on in Settings, then remembered")
    func offByDefault() {
        let defaults = Self.defaults()
        #expect(!ClipProtectionSetting.isOn(in: defaults))
        ClipProtectionSetting.save(true, to: defaults)
        #expect(ClipProtectionSetting.isOn(in: defaults))
    }

    @Test("Debug builds only, even with auto-gain open to every build: it needs its own live test")
    func offered() {
        #expect(ClipProtectionSetting.isOffered(isDebugBuild: true))
        #expect(!ClipProtectionSetting.isOffered(isDebugBuild: false))
    }
}
