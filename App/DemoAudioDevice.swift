import AudioIO
import Foundation

/// A synthetic multichannel signal for the simulator and UI work. Not real-time: blocks are
/// generated on a background task, roughly every 10 ms.
final class DemoAudioDevice: AudioIODevice, @unchecked Sendable {
    /// How many channels the demo sends. Nothing else depends on this number.
    static let channelCount = 18

    let name = "Demo signal (\(DemoAudioDevice.channelCount) channels)"
    let inputChannelCount = DemoAudioDevice.channelCount
    let outputChannelCount = DemoAudioDevice.channelCount
    let sampleRate = 48_000.0

    private let fake = FakeAudioDevice(inputChannelCount: DemoAudioDevice.channelCount)
    private var task: Task<Void, Never>?

    func start(input: @escaping AudioInputHandler) throws {
        stop()
        try fake.start(input: input)
        let fake = fake
        task = Task.detached(priority: .userInitiated) {
            let count = DemoAudioDevice.channelCount
            var phase = 0.0
            // `-demoDropout`: every 15 s deliver one block bigger than a ring, so the recorder has to drop it.
            let overflows = launchFlag("-demoDropout")
            // `-demoClip`: every 3 s, one full-scale sample on channel 3, so the clip mark can be checked.
            let clips = launchFlag("-demoClip")
            // `-demoCalm` (screenshots): levels a mixed band would show, mostly green and yellow (peaks to about
            // -12 dBFS), with one hot channel (channel 2) near -4 dBFS.
            let calm = launchFlag("-demoCalm")
            var blocks = 0
            while !Task.isCancelled {
                phase += 0.05
                blocks += 1
                if overflows, blocks % 1_500 == 0 { fake.deliver(Array(repeating: Array(repeating: 0, count: 250_000), count: count)) }
                let channels = (0..<count).map { channel -> [Float] in
                    // The last channel stays silent, so the meters show an unused USB Channel.
                    let swing = sin(phase + Double(channel) * 0.6)
                    let loud = calm ? (channel == 1 ? 0.6 : 0.03 + 0.11 * (1 + swing)) : 0.02 + 0.3 * (1 + swing)
                    let level = Float(loud) * (channel == count - 1 ? 0 : 1)
                    return (0..<480).map { _ in Float.random(in: -level...level) }
                }
                var delivered = channels
                if clips, blocks % 300 == 0 { delivered[2][0] = 1 }
                fake.deliver(delivered)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        fake.stop()
    }
}
