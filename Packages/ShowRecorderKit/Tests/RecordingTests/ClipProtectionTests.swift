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

    /// Waits for `stream`'s next value, or gives up after `seconds`, so a gate the code never reaches fails the test
    /// instead of hanging the run (and the shared build lock with it).
    static func next(_ stream: AsyncStream<Void>, within seconds: Double = 30) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

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

    @Test("Two preamps hot in one read are turned down at the same time, not one after the other (#554)")
    func twoPreampsAtOnce() async {
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.answer = {
            enter.yield()
            for await _ in released { return }
        }
        let protection = ClipProtection(control: control, sampleRate: 48_000)

        let moving = Task { await Self.feed(protection, Self.hot, on: [1, 2]) }
        #expect(await Self.next(entered), "a move reaches the Mixer")
        #expect(await Self.next(entered), "the other reaches the Mixer before either answers")
        #expect(control.moveStarts == 2)
        release.yield()
        release.yield()
        await moving.value
        #expect(control.gainDb == [1: 26, 2: 26])
    }

    @Test("Two hundred meter reads while the Mixer is held return at once and start one turn-down per channel (#554)")
    func metersWhileHeld() async {
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.answer = {
            enter.yield()
            for await _ in released { return }
        }
        let protection = ClipProtection(control: control, sampleRate: 48_000)
        let quiet = Windows.at(-30)

        let hot = [Windows.at(-2), quiet, quiet]
        let first = (0..<10).compactMap { _ in protection.meters(hot) }
        #expect(control.moveStarts == 0, "every read returned before any move reached the Mixer")
        #expect(await Self.next(entered), "a move reaches the Mixer")
        // 6 s more of a hot channel while that move waits: past the 5 s rest, so only the pending turn-down keeps a
        // second one from starting.
        let later = (0..<190).compactMap { _ in protection.meters(hot) }
        #expect(later.isEmpty, "no read starts a second turn-down while the first is pending")
        #expect(control.moveStarts == 1)
        release.yield()
        for task in first { await task.value }
        #expect(control.gainDb == [1: 26, 2: 30])
        #expect(control.moveStarts == 1)
    }

    @Test("A channel whose move is done may move again while another lane from the same read still waits on the Mixer (#554)")
    func laneReleasedWhenDone() async {
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.channelAnswer = { channel in
            guard channel == 2 else { return }
            enter.yield()
            for await _ in released { return }
        }
        let (logged, log) = AsyncStream<Void>.makeStream()
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { _ in log.yield() })
        let quiet = Windows.at(-30)

        let both = (0..<10).compactMap { _ in protection.meters([Windows.at(-2), Windows.at(-2), quiet]) }
        #expect(await Self.next(entered), "channel 2's move reaches the Mixer")
        #expect(await Self.next(logged), "channel 1's lane is done")
        #expect(control.gainDb[1] == 26)
        // 6 s more of channel 1 hot while channel 2 still waits: past the 5 s rest, so channel 1 moves again. Each
        // turn-down is awaited before the next read, so it decides at its own read's time.
        for _ in 0..<180 { if let task = protection.meters([Windows.at(-2), quiet, quiet]) { await task.value } }
        #expect(control.gainDb[1] == 22)
        release.yield()
        for task in both { await task.value }
        #expect(control.gainDb[2] == 26)
    }

    @Test("A read's last lane finishing never frees a channel a later turn-down holds (#554)")
    func laneDoneKeepsLaterTurnDown() async {
        let (entered2, enter2) = AsyncStream<Void>.makeStream()
        let (released2, release2) = AsyncStream<Void>.makeStream()
        let (stepped, step) = AsyncStream<Void>.makeStream()
        let (released1, release1) = AsyncStream<Void>.makeStream()
        var movesOn1 = 0
        control.channelAnswer = { @MainActor channel in
            if channel == 2 {
                enter2.yield()
                for await _ in released2 { return }
            }
            guard channel == 1 else { return }
            movesOn1 += 1
            guard movesOn1 > 1 else { return }
            step.yield()
            for await _ in released1 { return }
        }
        let (logged, log) = AsyncStream<Void>.makeStream()
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { _ in log.yield() })
        let quiet = Windows.at(-30), hot1 = [Windows.at(-2), quiet, quiet]

        // Task A turns down channels 1 and 2; channel 2's move waits on the Mixer, channel 1's is done.
        let a = (0..<10).compactMap { _ in protection.meters([Windows.at(-2), Windows.at(-2), quiet]) }
        #expect(await Self.next(entered2), "channel 2's move reaches the Mixer")
        #expect(await Self.next(logged), "channel 1's lane is done")
        // Channel 1 runs hot until, past the 5 s rest, task B turns it down again and that move waits on the Mixer.
        // Each turn-down started meanwhile either finishes (still within the rest) or is B's, at the Mixer.
        var b: Task<Void, Never>?
        for _ in 0..<300 where movesOn1 < 2 {
            guard let task = protection.meters(hot1) else { continue }
            b = task
            Task { await task.value; step.yield() }
            #expect(await Self.next(stepped), "the turn-down finishes or reaches the Mixer")
        }
        #expect(movesOn1 == 2, "channel 1's second move reaches the Mixer")
        // Task A's last lane finishes while B still holds channel 1.
        release2.yield()
        for task in a { await task.value }
        // 6 s more of channel 1 hot: past the rest after B's move, so only B's pending turn-down keeps a third from starting.
        let c = (0..<180).compactMap { _ in protection.meters(hot1) }
        #expect(c.isEmpty, "no turn-down starts on channel 1 while B's waits on the Mixer")
        release1.yield()
        release1.yield()                                    // so a third move, if it started, can't hang the test
        await b?.value
        for task in c { await task.value }
        #expect(movesOn1 == 2)
    }

    @Test("Two channels of a strip-linked pair, both hot, turn down one after the other (#554)")
    func linkedPairOneAfterTheOther() async {
        control.laneOf = [1: 1, 2: 1]
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.answer = {
            enter.yield()
            for await _ in released { return }
        }
        let protection = ClipProtection(control: control, sampleRate: 48_000)

        let moving = Task { await Self.feed(protection, Self.hot, on: [1, 2]) }
        #expect(await Self.next(entered), "a move reaches the Mixer")
        for _ in 0..<10 { await Task.yield() }
        #expect(control.moveStarts == 1, "the second waits for the first: the Mixer mirrors their faders and sends")
        release.yield()
        #expect(await Self.next(entered), "the second move reaches the Mixer")
        #expect(control.gainDb == [1: 26, 2: 30], "USB Channel 1 moved first")
        release.yield()
        await moving.value
        #expect(control.gainDb == [1: 26, 2: 26])
    }

    @Test("Stopped while a strip-linked pair's first move is on the Mixer, the second doesn't start (#554)")
    func linkedPairStopped() async {
        control.laneOf = [1: 1, 2: 1]
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.answer = {
            enter.yield()
            for await _ in released { return }
        }
        let protection = ClipProtection(control: control, sampleRate: 48_000)

        let moving = Task { await Self.feed(protection, Self.hot, on: [1, 2]) }
        #expect(await Self.next(entered), "a move reaches the Mixer")
        protection.stop()                                   // the Take ended mid-ramp
        release.yield()
        release.yield()                                     // so a second move, if it starts, can't hang the test
        await moving.value
        #expect(control.moveStarts == 1)
        #expect(control.gainDb[2] == 30)
    }

    @Test("Reconnected to the same Mixer mid-Take, turn-downs go through the new link (#554)")
    func followsTheSameMixer() async {
        let old = control, new = FakeGainControl(gainDb: [1: 30, 2: 30], channelOfUSB: [1: 1, 2: 2, 3: 1])
        var current = old
        let protection = ClipProtection(currentControl: { current }, mixer: { "FOH · XR18" }, sampleRate: 48_000)

        current = new                                       // the Mixer Link reconnected: a new driver, same Mixer
        await Self.feed(protection, Self.hot)

        #expect(new.gainDb[1] == 26)
        #expect(old.moveStarts == 0 && old.gainDb[1] == 30)
    }

    @Test("Linked to another Mixer mid-Take, nothing is written or logged; back on the first Mixer, it tries again after the 5 s rest (#554)")
    func refusesAnotherMixer() async {
        var mixer = "FOH · XR18"
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(currentControl: { [control] in control }, mixer: { mixer }, sampleRate: 48_000,
                                        log: { logged.append($0) })

        mixer = "Monitors · X32"                            // the Mixer Link moved to another desk
        await Self.feed(protection, Self.hot)
        #expect(control.moveStarts == 0 && logged.isEmpty, "nothing written to, or logged for, the other Mixer")

        mixer = "FOH · XR18"                                // back on the first Mixer
        await Self.feed(protection, Self.hot)               // 0.3 s later: still within the rest
        #expect(control.moveStarts == 0, "it waits out the rest, as after a Mixer that didn't answer")
        await Self.feed(protection, Windows.repeating(Windows.at(-2), 150))   // 5 s more of a hot channel
        #expect(control.gainDb[1] == 26 && logged.count == 1)
    }

    @Test("With the Mixer Link down mid-Take, nothing is written or logged; it tries again after the rest, once the Link is back (#554)")
    func refusesWhileLinkIsDown() async {
        var linked: FakeGainControl? = control
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(currentControl: { linked }, mixer: { linked == nil ? nil : "FOH · XR18" },
                                        sampleRate: 48_000, log: { logged.append($0) })

        linked = nil                                        // the Mixer Link dropped
        await Self.feed(protection, Self.hot)
        #expect(control.moveStarts == 0 && logged.isEmpty)

        linked = control                                    // back
        await Self.feed(protection, Windows.repeating(Windows.at(-2), 160))
        #expect(control.gainDb[1] == 26 && logged.count == 1)
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

    @Test("Two USB Channels on one Mixer channel, both hot: the lower USB Channel moves it, however the Mixer's answers arrive (#554)")
    func sameChannelInOrder() async {
        let (asked, ask) = AsyncStream<Void>.makeStream()
        let (answered, answer) = AsyncStream<Void>.makeStream()
        let (secondAsked, askSecond) = AsyncStream<Void>.makeStream()
        var first = true
        control.preampAnswer = { @MainActor in
            guard first else {
                askSecond.yield()
                return
            }
            first = false
            ask.yield()
            for await _ in answered { return }
        }
        var logged: [TakeMetadata.GainChange] = []
        let protection = ClipProtection(control: control, sampleRate: 48_000, log: { logged.append($0) })

        // The first preamp read is slow, so the other channel's answer comes back first.
        let moving = Task { await Self.feed(protection, Self.hot, on: [1, 3]) }
        #expect(await Self.next(asked), "a preamp read reaches the Mixer")
        #expect(await Self.next(secondAsked), "the other channel's preamp read reaches the Mixer")
        answer.yield()
        await moving.value

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

    @Test("Offered only where auto-gain is, Debug builds for now: it moves the same preamps through the same driver")
    func offered() {
        #expect(ClipProtectionSetting.isOffered(isDebugBuild: true))
        #expect(!ClipProtectionSetting.isOffered(isDebugBuild: false))
    }
}
