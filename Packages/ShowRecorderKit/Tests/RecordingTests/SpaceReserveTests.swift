@testable import Recording
import Testing

@Suite("Space reserve")
struct SpaceReserveTests {
    @Test("The reserve is 60 s of 24-bit audio for every channel")
    func sixtySeconds() {
        let reserve = SpaceReserve(channelCount: 1, sampleRate: 48_000)
        #expect(reserve.bytes == 60 * 48_000 * 3)
    }

    @Test("It scales with channel count and sample rate")
    func scales() {
        let base = SpaceReserve(channelCount: 2, sampleRate: 48_000).bytes
        #expect(SpaceReserve(channelCount: 18, sampleRate: 48_000).bytes == base * 9)
        #expect(SpaceReserve(channelCount: 2, sampleRate: 96_000).bytes == base * 2)
    }

    @Test("A Destination is low when its free space is under the reserve")
    func isLow() {
        let reserve = SpaceReserve(channelCount: 1, sampleRate: 48_000)
        #expect(reserve.isLow(free: reserve.bytes - 1))
        #expect(!reserve.isLow(free: reserve.bytes))
    }

    @Test("Adding bytes breaches the reserve only when it would leave less than the reserve free")
    func wouldBreach() {
        let reserve = SpaceReserve(channelCount: 1, sampleRate: 48_000)
        #expect(!reserve.wouldBreach(free: reserve.bytes + 100, adding: 100))
        #expect(reserve.wouldBreach(free: reserve.bytes + 100, adding: 101))
        #expect(!reserve.wouldBreach(free: 0, adding: 0))
    }
}
