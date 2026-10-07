#if DEBUG
import AudioIO
import Foundation

/// A synthetic 18-channel signal for the simulator and UI work. Not real-time: blocks are
/// generated on a background task, roughly every 10 ms.
final class DemoAudioDevice: AudioIODevice, @unchecked Sendable {
    let name = "Demo signal (18 channels)"
    let inputChannelCount = 18
    let outputChannelCount = 18
    let sampleRate = 48_000.0

    private let fake = FakeAudioDevice(inputChannelCount: 18)
    private var task: Task<Void, Never>?

    func start(input: @escaping AudioInputHandler) throws {
        stop()
        try fake.start(input: input)
        let fake = fake
        task = Task.detached(priority: .userInitiated) {
            var phase = 0.0
            while !Task.isCancelled {
                phase += 0.05
                let channels = (0..<18).map { channel -> [Float] in
                    let level = Float(0.02 + 0.3 * (1 + sin(phase + Double(channel) * 0.6))) * (channel == 17 ? 0 : 1)
                    return (0..<480).map { _ in Float.random(in: -level...level) }
                }
                fake.deliver(channels)
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
#endif
