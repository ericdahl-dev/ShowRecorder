@testable import Recording
import Testing

/// How auto-gain measures a USB Channel's level (#554), moved out of the App: half a second for the meter to follow a
/// gain move, then 20 readings 100 ms apart, averaged.
@MainActor
@Suite("Level average")
struct LevelAverageTests {
    @Test("Waits 500 ms, then takes 20 readings 100 ms apart and returns their mean")
    func twentyReadingsAfterHalfASecond() async {
        var waits: [Duration] = []
        var next = -30.0
        let level = await LevelAverage.measure(
            reading: { next += 1; return next },        // -29, -28 … -10
            sleep: { waits.append($0) })
        #expect(waits == [.milliseconds(500)] + Array(repeating: .milliseconds(100), count: 20))
        #expect(level == -19.5)
    }

    @Test("With no readings (the channel isn't metered) it returns -120")
    func noReadings() async {
        #expect(await LevelAverage.measure(reading: { nil }, sleep: { _ in }) == -120)
    }
}
