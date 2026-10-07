import AudioIO
import Synchronization
import Testing

@Suite("Fake audio device")
struct FakeAudioDeviceTests {
    @Test("Delivering many blocks off the main thread doesn't grow the call stack")
    func manyBlocksDoNotGrowTheStack() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let received = Atomic<Int>(0)
        try device.start(input: { _ in received.add(1, ordering: .relaxed) })

        // The demo signal crashed after ~5,500 blocks on a 512 KB stack. Use far more than that,
        // on a detached task, which runs on a small-stack cooperative thread like the demo did.
        let blocks = 30_000
        await Task.detached {
            for _ in 0..<blocks { device.deliver([[0]]) }
        }.value

        #expect(received.load(ordering: .relaxed) == blocks)
    }
}
