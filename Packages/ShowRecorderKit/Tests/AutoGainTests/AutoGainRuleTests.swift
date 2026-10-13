import AutoGain
import Testing

/// A preamp in front of a steady source: the Average level moves dB for dB with the gain. It can be limited to a
/// range and to whole steps, like a real one, and it never tells the rule its absolute gain.
final class FakePreamp {
    var gainDb: Double
    let range: ClosedRange<Double>
    let stepDb: Double
    /// The source's level with the gain at 0 dB; nil is no signal at all.
    var sourceDbfs: Double?
    /// The source goes silent after this many moves, as if a cable were pulled mid-way.
    var signalLostAfterMoves: Int?
    /// How far the level moves per dB of gain. A real preamp is 1; less stands in for gear whose response doesn't
    /// match what it reports, which the extra passes are there to absorb.
    var levelPerDb = 1.0
    private(set) var settles = 0
    private(set) var moves: [Double] = []

    init(gainDb: Double = 0, range: ClosedRange<Double> = -12...60, stepDb: Double = 0, sourceDbfs: Double?) {
        self.gainDb = gainDb
        self.range = range
        self.stepDb = stepDb
        self.sourceDbfs = sourceDbfs
    }

    func measure() -> Double {
        guard let sourceDbfs else { return -80 }
        return min(sourceDbfs + gainDb * levelPerDb, 0)
    }

    func adjust(by db: Double) -> Double {
        var wanted = gainDb + db
        if stepDb > 0 { wanted = (wanted / stepDb).rounded() * stepDb }
        let next = min(max(wanted, range.lowerBound), range.upperBound)
        let applied = next - gainDb
        gainDb = next
        moves.append(applied)
        if moves.count == signalLostAfterMoves { sourceDbfs = nil }
        return applied
    }

    func settle() { settles += 1 }

    func run(_ rule: AutoGainRule = AutoGainRule()) async throws -> AutoGainRule.Outcome {
        try await rule.run(measure: { self.measure() }, adjust: { self.adjust(by: $0) }, settle: { self.settle() })
    }
}

@Suite("Auto-gain rule")
struct AutoGainRuleTests {
    @Test("A quiet channel is brought up to the target in one step, since the preamp moves the level dB for dB")
    func convergesFromQuiet() async throws {
        let preamp = FakePreamp(gainDb: 10, sourceDbfs: -40)
        let outcome = try await preamp.run()
        #expect(outcome == .onTarget(levelDbfs: -18, changeDb: 12, passes: 1))
        #expect(preamp.gainDb == 22)
        #expect(preamp.settles == 1)
    }

    @Test("A clipping channel reads 0 dBFS, so the first step falls short and a second pass lands it")
    func convergesFromClipping() async throws {
        // 15 dB over full scale, which the meter can only show as 0.
        let preamp = FakePreamp(gainDb: 35, sourceDbfs: -20)
        let outcome = try await preamp.run()
        #expect(outcome == .onTarget(levelDbfs: -18, changeDb: -33, passes: 2))
        #expect(preamp.moves == [-18, -15])
        #expect(preamp.settles == 2)
    }

    @Test("A preamp that only moves in whole dB lands within the tolerance, not exactly on the target")
    func convergesInWholeSteps() async throws {
        let preamp = FakePreamp(gainDb: 10, stepDb: 1, sourceDbfs: -40.4)
        let outcome = try await preamp.run()
        #expect(outcome == .onTarget(levelDbfs: -18.4, changeDb: 12, passes: 1))
        #expect(preamp.gainDb == 22)
    }

    @Test("A preamp that stops short at the top of its range still lands if the level is within the tolerance")
    func convergesAtTheEndOfTheRange() async throws {
        let preamp = FakePreamp(gainDb: 10, range: -12...30, sourceDbfs: -50)
        let outcome = try await preamp.run()
        #expect(outcome == .onTarget(levelDbfs: -20, changeDb: 20, passes: 1))
    }

    @Test("With no signal it fails at once and never touches the preamp")
    func noSignal() async throws {
        let preamp = FakePreamp(gainDb: 10, sourceDbfs: nil)
        let outcome = try await preamp.run()
        #expect(outcome == .failed(.noSignal, changeDb: 0))
        #expect(preamp.moves.isEmpty)
        #expect(preamp.settles == 0)
    }

    @Test("A level only just above silence is a noise floor, not a signal: no move (Eric's XR18 kick, -67 dBFS, 2026-10-12)",
          arguments: [-79.5, -67.2, -60.5])
    func noiseFloorIsNoSignal(level: Double) async throws {
        let preamp = FakePreamp(gainDb: 32, sourceDbfs: level - 32)
        let outcome = try await preamp.run()
        #expect(outcome == .failed(.noSignal, changeDb: 0))
        #expect(preamp.moves.isEmpty)
    }

    @Test("A quiet but real signal, above -60 dBFS, is still brought up")
    func quietSignalMoves() async throws {
        let preamp = FakePreamp(gainDb: 0, sourceDbfs: -55)
        let outcome = try await preamp.run()
        #expect(outcome == .onTarget(levelDbfs: -18, changeDb: 37, passes: 1))
    }

    @Test("A signal that disappears mid-way fails, reporting how far the preamp has already moved")
    func signalLost() async throws {
        let preamp = FakePreamp(gainDb: 35, sourceDbfs: -20)
        preamp.signalLostAfterMoves = 1
        let outcome = try await preamp.run()
        #expect(outcome == .failed(.signalLost, changeDb: -18))
        #expect(preamp.moves.count == 1)
    }

    @Test("A level still above -3 dBFS after the last pass is still clipping")
    func stillClipping() async throws {
        let preamp = FakePreamp(gainDb: 50, range: -100...100, sourceDbfs: 0)
        preamp.levelPerDb = 0.1
        let outcome = try await preamp.run()
        guard case .failed(.stillClipping(let level), _) = outcome else {
            Issue.record("Expected still clipping, got \(outcome)")
            return
        }
        #expect(level > -3)
        #expect(preamp.moves.count == 4)
    }

    @Test("A level still below -30 dBFS after the last pass is still too quiet")
    func stillTooQuiet() async throws {
        let preamp = FakePreamp(gainDb: 0, range: -100...100, sourceDbfs: -40)
        preamp.levelPerDb = 0.1
        let outcome = try await preamp.run()
        guard case .failed(.stillTooQuiet(let level), _) = outcome else {
            Issue.record("Expected still too quiet, got \(outcome)")
            return
        }
        #expect(level < -30)
        #expect(preamp.moves.count == 4)
        #expect(preamp.settles == 4)
    }

    @Test("A preamp at the end of its range with the level still off target fails at once, without spending the passes")
    func rangeReached() async throws {
        let preamp = FakePreamp(gainDb: 0, range: -12...30, sourceDbfs: -58)
        let outcome = try await preamp.run()
        #expect(outcome == .failed(.rangeReached(levelDbfs: -28), changeDb: 30))
        #expect(preamp.moves == [30, 0])
    }

    @Test("A level between -30 and -3 dBFS but outside the tolerance after the last pass is off target, not a success")
    func offTarget() async throws {
        let preamp = FakePreamp(gainDb: 40, range: -100...100, sourceDbfs: -5)
        preamp.levelPerDb = 0.25
        let outcome = try await preamp.run()
        guard case .failed(.offTarget(let level), _) = outcome else {
            Issue.record("Expected off target, got \(outcome)")
            return
        }
        #expect(level > -15 && level < -3)
        #expect(preamp.moves.count == 4)
    }

    @Test("A channel already on target is left alone")
    func alreadyOnTarget() async throws {
        let preamp = FakePreamp(gainDb: 20, sourceDbfs: -36)
        let outcome = try await preamp.run()
        #expect(outcome == .onTarget(levelDbfs: -16, changeDb: 0, passes: 0))
        #expect(preamp.moves.isEmpty)
        #expect(preamp.settles == 0)
    }

    @Test("The target and tolerance are parameters")
    func otherTarget() async throws {
        // -16 is within 3 dB of -18, but not within 1 dB of -20.
        let preamp = FakePreamp(gainDb: 20, sourceDbfs: -36)
        let outcome = try await preamp.run(AutoGainRule(targetDbfs: -20, toleranceDb: 1))
        #expect(outcome == .onTarget(levelDbfs: -20, changeDb: -4, passes: 1))
    }

    @MainActor
    @Test("A caller on the main actor, like the record screen, can pass closures that use its own state")
    func runsInTheCallersIsolation() async throws {
        var level = -30.0
        var moves: [Double] = []
        let outcome = try await AutoGainRule().run(
            measure: { level },
            adjust: { db in moves.append(db); level += db; return db },
            settle: {}
        )
        #expect(outcome == .onTarget(levelDbfs: -18, changeDb: 12, passes: 1))
        #expect(moves == [12])
    }
}
