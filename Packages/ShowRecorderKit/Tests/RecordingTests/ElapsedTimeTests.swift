@testable import Recording
import Testing

@Suite("Elapsed Take time")
struct ElapsedTimeTests {
    @Test("Under an hour is minutes and seconds")
    func underAnHour() {
        #expect(ElapsedTime.format(seconds: 0) == "0:00")
        #expect(ElapsedTime.format(seconds: 5) == "0:05")
        #expect(ElapsedTime.format(seconds: 65) == "1:05")
        #expect(ElapsedTime.format(seconds: 3_599) == "59:59")
    }

    @Test("An hour or more adds hours")
    func overAnHour() {
        #expect(ElapsedTime.format(seconds: 3_600) == "1:00:00")
        #expect(ElapsedTime.format(seconds: 3_723) == "1:02:03")
    }

    @Test("A negative time (clock set back) shows zero")
    func negative() {
        #expect(ElapsedTime.format(seconds: -4) == "0:00")
    }
}
