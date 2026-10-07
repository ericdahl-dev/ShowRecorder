import Recording
import Testing

@Suite("Time left")
struct TimeLeftTests {
    @Test("Free space divided by the data rate of every USB Channel")
    func freeSpaceOverDataRate() {
        // 18 channels × 48 kHz × 3 bytes = 2,592,000 bytes/s → 9.33 GB/hour.
        let oneHour: Int64 = 2_592_000 * 3600
        #expect(TimeLeft(availableBytes: oneHour, usbChannelCount: 18, sampleRate: 48_000).seconds == 3600)
        #expect(TimeLeft(availableBytes: oneHour, usbChannelCount: 9, sampleRate: 48_000).seconds == 7200)
    }

    @Test("Shown in hours and minutes", arguments: [
        (Int64(2_592_000) * 3600 * 5 + 2_592_000 * 60 * 7, "5 h 07 min"),
        (Int64(2_592_000) * 60 * 42, "42 min"),
        (Int64(2_592_000) * 30, "under 1 min"),
    ])
    func formatted(bytes: Int64, text: String) {
        #expect(TimeLeft(availableBytes: bytes, usbChannelCount: 18, sampleRate: 48_000).description == text)
    }

    @Test("Nothing to record means no estimate")
    func noChannelsNoEstimate() {
        #expect(TimeLeft(availableBytes: 1_000_000, usbChannelCount: 0, sampleRate: 48_000).seconds == nil)
    }
}
