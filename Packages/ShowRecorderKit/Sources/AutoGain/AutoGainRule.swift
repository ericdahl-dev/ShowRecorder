/// The closed-loop auto-gain rule (#152): steps a channel's preamp until its Average level lands on the target.
/// Ported from friture's `EVOGainWorker`. It measures, moves the gain by the remaining error (a preamp moves the
/// level dB for dB), lets it settle and measures again, for at most a few passes.
///
/// It never reads the absolute gain back: it only asks for relative moves, and the actuator answers with how far it
/// actually moved. An actuator at the end of its range (or of the range Mix Hold can compensate) moves less, or not
/// at all, and the rule stops there instead of spending its passes. The wait between passes is passed in, so tests
/// don't sleep.
public struct AutoGainRule: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The level landed within the tolerance of the target. `changeDb` is how far the gain moved in all.
        case onTarget(levelDbfs: Double, changeDb: Double, passes: Int)
        /// It stopped without landing. `changeDb` is how far the gain had moved by then, so it can be undone.
        case failed(Failure, changeDb: Double)
    }

    public enum Failure: Equatable, Sendable {
        /// Silence or only a noise floor before the first step (at or below `signalFloorDbfs`), so there was nothing to
        /// measure. The gain is untouched.
        case noSignal
        /// The signal went silent after a step.
        case signalLost
        /// Still above `clippingDbfs` after the last pass.
        case stillClipping(levelDbfs: Double)
        /// Still below `tooQuietDbfs` after the last pass.
        case stillTooQuiet(levelDbfs: Double)
        /// The actuator could move no further toward the target.
        case rangeReached(levelDbfs: Double)
        /// Between the two limits after the last pass, but outside the tolerance. friture counted this as a success;
        /// here it isn't one, so the result never claims a level it didn't reach.
        case offTarget(levelDbfs: Double)
    }

    /// The Average level to aim for.
    public var targetDbfs: Double
    /// How close to the target counts as landed, either side.
    public var toleranceDb: Double
    /// How many steps it takes at most.
    public var maxPasses: Int
    /// A level at or below this is no signal (the meters read -80 for silence).
    public var silenceDbfs: Double
    /// Before the first step, a level at or below this is a noise floor rather than a source, so nothing moves. On
    /// Eric's XR18 (2026-10-12) a quiet kick channel read -67 dBFS between hits; boosting that pushed the preamp and
    /// pinned the gate threshold for nothing. A real source to set gain on plays well above it.
    public var signalFloorDbfs: Double
    /// Above this after the last pass, the channel is still clipping.
    public var clippingDbfs: Double
    /// Below this after the last pass, the channel is still too quiet.
    public var tooQuietDbfs: Double

    public init(
        targetDbfs: Double = -18,
        toleranceDb: Double = 3,
        maxPasses: Int = 4,
        silenceDbfs: Double = -80,
        signalFloorDbfs: Double = -60,
        clippingDbfs: Double = -3,
        tooQuietDbfs: Double = -30
    ) {
        self.targetDbfs = targetDbfs
        self.toleranceDb = toleranceDb
        self.maxPasses = maxPasses
        self.silenceDbfs = silenceDbfs
        self.signalFloorDbfs = signalFloorDbfs
        self.clippingDbfs = clippingDbfs
        self.tooQuietDbfs = tooQuietDbfs
    }

    /// - Parameters:
    ///   - measure: the channel's Average level now, in dBFS.
    ///   - adjust: moves the gain by about the given dB and returns how far it actually moved, which can be less
    ///     at the end of its range, or rounded to the steps it takes.
    ///   - settle: waits for the level to follow a move before measuring again (friture waited 150 ms).
    ///   - isolation: where the closures run: the caller's actor, so a screen on the main actor can use its own state.
    public func run(
        isolation: isolated (any Actor)? = #isolation,
        measure: () async throws -> Double,
        adjust: (Double) async throws -> Double,
        settle: () async throws -> Void
    ) async throws -> Outcome {
        var level = try await measure()
        guard level > max(silenceDbfs, signalFloorDbfs) else { return .failed(.noSignal, changeDb: 0) }
        var change = 0.0
        var passes = 0
        while passes < maxPasses, !isOnTarget(level) {
            let applied = try await adjust(targetDbfs - level)
            guard applied != 0 else { return .failed(.rangeReached(levelDbfs: level), changeDb: change) }
            change += applied
            try await settle()
            level = try await measure()
            guard level > silenceDbfs else { return .failed(.signalLost, changeDb: change) }
            passes += 1
        }
        if isOnTarget(level) { return .onTarget(levelDbfs: level, changeDb: change, passes: passes) }
        if level > clippingDbfs { return .failed(.stillClipping(levelDbfs: level), changeDb: change) }
        if level < tooQuietDbfs { return .failed(.stillTooQuiet(levelDbfs: level), changeDb: change) }
        return .failed(.offTarget(levelDbfs: level), changeDb: change)
    }

    private func isOnTarget(_ level: Double) -> Bool {
        abs(targetDbfs - level) <= toleranceDb
    }
}
