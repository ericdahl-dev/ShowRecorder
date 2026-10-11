import MixerLink
import ProjectExport
import Testing

/// The Show's total recorded time, for the record screen (#328): every finished Take's length, plus the one running.
@Suite("Show total time")
struct ShowTotalTests {
    func take(_ number: Int, frames: UInt64, rate: Int) -> ShowTimeline.Take {
        .init(number: number, sampleRate: rate, frameCount: frames, stems: [])
    }

    @Test("A Show's recorded time is the sum of its Takes' lengths, each at its own sample rate")
    func sumOfTakes() {
        let show = ShowTimeline(showName: "S", usbChannels: [], takes: [take(1, frames: 48_000 * 60, rate: 48_000), take(2, frames: 96_000 * 30, rate: 96_000)])
        #expect(show.recordedSeconds == 90)
        #expect(ShowTimeline(showName: "S", usbChannels: [], takes: []).recordedSeconds == 0)
    }

    @Test("While a Take runs, the total counts it too")
    func withRunningTake() {
        let show = ShowTimeline(showName: "S", usbChannels: [], takes: [take(1, frames: 48_000 * 60, rate: 48_000)])
        #expect(show.recordedSeconds(plusRunning: 12.5) == 72.5)
        #expect(show.recordedSeconds(plusRunning: nil) == 60)
    }
}
