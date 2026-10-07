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
            while !Task.isCancelled {
                phase += 0.05
                let channels = (0..<count).map { channel -> [Float] in
                    // The last channel stays silent, so the meters show an unused USB Channel.
                    let level = Float(0.02 + 0.3 * (1 + sin(phase + Double(channel) * 0.6))) * (channel == count - 1 ? 0 : 1)
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
