/// How the X32 turns an OSC float (0…1) into dB, and the steps it keeps (#392). From Maillot's X32 OSC protocol 4.06,
/// checked against X32-Edit (2026-10-12): it floors a value between steps to the step below, so the driver snaps to
/// the nearest step itself and writes that step's own value.
struct X32Values: Sendable {
    /// Steps between 0 and 1: the value is one of 0, 1/steps … 1.
    let steps: Int
    let toDb: @Sendable (Double) -> Double
    let toFloat: @Sendable (Double) -> Double

    /// Send levels (and the mono level): the 161-step pseudo-log "level" scale, -oo (-90) … +10 dB.
    static let level = X32Values(steps: 160, toDb: levelDb, toFloat: levelFloat)

    /// Channel faders: the same "level" scale in 1024 steps.
    static let fader = X32Values(steps: 1023, toDb: levelDb, toFloat: levelFloat)

    /// `/headamp/NNN/gain`: -12 … +60 dB in 0.5 dB steps.
    static let headampGain = linear(-12, 60)
    /// `/ch/NN/gate/thr`: -80 … 0 dB in 0.5 dB steps.
    static let gateThreshold = linear(-80, 0)
    /// `/ch/NN/dyn/thr`: -60 … 0 dB in 0.5 dB steps.
    static let compressorThreshold = linear(-60, 0)

    /// A linear scale from `low` to `high` dB in 0.5 dB steps.
    static func linear(_ low: Double, _ high: Double) -> X32Values {
        X32Values(steps: Int((high - low) / 0.5), toDb: { low + $0 * (high - low) },
                  toFloat: { (max(low, min(high, $0)) - low) / (high - low) })
    }

    /// The nearest step to `db`, in dB.
    func snap(_ db: Double) -> Double {
        toDb(Double(step(db)) / Double(steps))
    }

    /// The OSC float to write for `db`: its nearest step, nudged up a hair so float error can't floor it to the step
    /// below. The top step is written as 1.
    func oscFloat(_ db: Double) -> Float {
        let step = step(db)
        return step == steps ? 1 : Float((Double(step) + 0.001) / Double(steps))
    }

    /// The dB of an OSC float read from the X32: its step, so Float32 rounding doesn't show as -36.99999.
    func db(ofOSC value: Float) -> Double {
        toDb(Double(max(0, min(steps, Int((Double(value) * Double(steps)).rounded())))) / Double(steps))
    }

    /// The step nearest to `db` (or the one below, with `.down`), 0…steps.
    func step(_ db: Double, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        max(0, min(steps, Int((toFloat(db) * Double(steps) + (rounding == .down ? 1e-9 : 0)).rounded(rounding))))
    }

    /// The OSC float for the step at or below `db`: a ramp's in-between values use it so a level never rounds up.
    func oscFloatBelow(_ db: Double) -> Float {
        let step = step(db, rounding: .down)
        return step == steps ? 1 : Float((Double(step) + 0.001) / Double(steps))
    }

    static func levelDb(_ f: Double) -> Double {
        if f >= 0.5 { return f * 40 - 30 }
        if f >= 0.25 { return f * 80 - 50 }
        if f >= 0.0625 { return f * 160 - 70 }
        return f * 480 - 90
    }

    static func levelFloat(_ db: Double) -> Double {
        let d = max(-90, min(10, db))
        if d < -60 { return (d + 90) / 480 }
        if d < -30 { return (d + 70) / 160 }
        if d < -10 { return (d + 50) / 80 }
        return (d + 30) / 40
    }
}
