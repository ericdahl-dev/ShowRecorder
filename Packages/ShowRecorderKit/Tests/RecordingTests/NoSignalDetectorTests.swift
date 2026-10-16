import Recording
import Testing

@Suite("No signal on a Take (#778)")
struct NoSignalDetectorTests {
    private let rate = 48_000.0
    private let window = 1_600  // a thirtieth of a second at 48 kHz

    private func silent(_ channels: Int = 4) -> [ChannelLevel] {
        Array(repeating: ChannelLevel(peak: 0, meanRectified: 0, frames: window), count: channels)
    }

    private func quiet(_ peak: Float, channels: Int = 4) -> [ChannelLevel] {
        Array(repeating: ChannelLevel(peak: peak, meanRectified: peak / 2, frames: window), count: channels)
    }

    private func feed(_ detector: inout NoSignalDetector, _ levels: [ChannelLevel], seconds: Double) {
        var remaining = seconds
        let step = Double(window) / rate
        while remaining > 0.0001 {
            detector.feed(levels, sampleRate: rate)
            remaining -= step
        }
    }

    @Test("Silence for 10 seconds after the first 3 raises the warning, and not before")
    func warnsAfterTheGraceAndTheWait() {
        var detector = NoSignalDetector()
        feed(&detector, silent(), seconds: 12)
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 2)
        #expect(detector.isSilent)
    }

    @Test("The warning comes at 13 seconds: 3 of grace and 10 of silence, not a window sooner")
    func exactBoundary() {
        var detector = NoSignalDetector()
        feed(&detector, silent(), seconds: 12.9)
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 0.2)
        #expect(detector.isSilent)
    }

    @Test("A window that straddles the end of the grace counts only the part after it")
    func graceStraddle() {
        var detector = NoSignalDetector()
        detector.feed([ChannelLevel(peak: 0, meanRectified: 0, frames: Int(4 * rate))], sampleRate: rate)
        #expect(!detector.isSilent)
        // 9 s more makes 1 + 9 = 10 s past the grace only if the first window counted just its last second.
        detector.feed([ChannelLevel(peak: 0, meanRectified: 0, frames: Int(8.9 * rate))], sampleRate: rate)
        #expect(!detector.isSilent)
        detector.feed([ChannelLevel(peak: 0, meanRectified: 0, frames: Int(0.2 * rate))], sampleRate: rate)
        #expect(detector.isSilent)
    }

    @Test("A sample rate that isn't positive is ignored")
    func badSampleRate() {
        var detector = NoSignalDetector()
        for badRate in [0.0, -48_000.0, Double.nan] {
            for _ in 0..<2_000 { detector.feed(silent(), sampleRate: badRate) }
        }
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 12)
        #expect(!detector.isSilent)
    }

    @Test("Quiet but real signal never warns")
    func quietSignalIsNotSilence() {
        var detector = NoSignalDetector()
        feed(&detector, quiet(0.001), seconds: 60)
        #expect(!detector.isSilent)
    }

    @Test("One live channel among silent ones is signal")
    func oneLiveChannel() {
        var detector = NoSignalDetector()
        var levels = silent()
        levels[2] = ChannelLevel(peak: 0.05, meanRectified: 0.02, frames: window)
        feed(&detector, levels, seconds: 60)
        #expect(!detector.isSilent)
    }

    @Test("Signal clears the warning at once and the wait starts over")
    func signalClearsAndRestarts() {
        var detector = NoSignalDetector()
        feed(&detector, silent(), seconds: 20)
        #expect(detector.isSilent)
        feed(&detector, quiet(0.01), seconds: 0.4)
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 8)
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 3)
        #expect(detector.isSilent)
    }

    @Test("Windows with no frames (input stopped) neither count nor reset")
    func emptyWindowsAreIgnored() {
        var detector = NoSignalDetector()
        feed(&detector, silent(), seconds: 9)
        for _ in 0..<1_000 { detector.feed(Array(repeating: ChannelLevel(peak: 0, meanRectified: 0, frames: 0), count: 4), sampleRate: rate) }
        for _ in 0..<1_000 { detector.feed([], sampleRate: rate) }
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 4)
        #expect(detector.isSilent)
    }

    @Test("A new Take starts over: no warning, and the grace again")
    func resetStartsOver() {
        var detector = NoSignalDetector()
        feed(&detector, silent(), seconds: 20)
        #expect(detector.isSilent)
        detector.reset()
        #expect(!detector.isSilent)
        feed(&detector, silent(), seconds: 12)
        #expect(!detector.isSilent)
    }

    @Test("The floor is -90 dBFS: just above it is signal, just below it is silence")
    func floorEdge() {
        var above = NoSignalDetector()
        feed(&above, quiet(3.3e-5), seconds: 30)
        #expect(!above.isSilent)
        var below = NoSignalDetector()
        feed(&below, quiet(3.1e-5), seconds: 30)
        #expect(below.isSilent)
        var exactly = NoSignalDetector()
        feed(&exactly, quiet(3.2e-5), seconds: 30)
        #expect(exactly.isSilent)
    }

    @Test("The warning is offered in Debug and TestFlight builds only")
    func availability() {
        #expect(NoSignalWarningAvailability.isAvailable(isDebugBuild: true, environment: nil))
        #expect(NoSignalWarningAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
        #expect(!NoSignalWarningAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!NoSignalWarningAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!NoSignalWarningAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}
