import AudioIO
import Foundation

/// A synthetic multichannel signal for the simulator and UI work. Not real-time: blocks are
/// generated on a background task, roughly every 10 ms.
final class DemoAudioDevice: AudioIODevice, @unchecked Sendable {
    /// The Demo signal inputs, by id and channel count: 18 channels (counts as an X Air for packs and the license) and
    /// 32 (counts as an X32; Eric, 2026-11-09). Each id starts with "demo", so the screenshot build keeps offering them
    /// (`DemoOnlyInputSource`). `-demoSignal` selects "demo".
    static let signals: [(id: String, channelCount: Int)] = [("demo", 18), ("demo-32", 32)]

    /// The channel count of the Demo signal with this input id, or nil for any other input (Demo stems included).
    static func channelCount(forID id: String) -> Int? {
        signals.first { $0.id == id }?.channelCount
    }

    let name: String
    let inputChannelCount: Int
    let outputChannelCount: Int
    let sampleRate = 48_000.0

    private let fake: FakeAudioDevice
    private var task: Task<Void, Never>?

    init(channelCount: Int) {
        name = "Demo signal (\(channelCount) channels)"
        inputChannelCount = channelCount
        outputChannelCount = channelCount
        fake = FakeAudioDevice(inputChannelCount: channelCount)
    }

    func start(input: @escaping AudioInputHandler) throws {
        stop()
        try fake.start(input: input)
        let fake = fake
        let count = inputChannelCount
        task = Task.detached(priority: .userInitiated) {
            var phase = 0.0
            // `-demoDropout`: every 15 s deliver one block bigger than a ring, so the recorder has to drop it.
            let overflows = launchFlag("-demoDropout")
            // `-demoClip`: every 3 s, one full-scale sample on channel 3, so the clip mark can be checked.
            let clips = launchFlag("-demoClip")
            var blocks = 0
            while !Task.isCancelled {
                phase += 0.05
                blocks += 1
                if overflows, blocks % 1_500 == 0 { fake.deliver(Array(repeating: Array(repeating: 0, count: 250_000), count: count)) }
                let channels = (0..<count).map { channel -> [Float] in
                    // The last channel stays silent, so the meters show an unused USB Channel.
                    let level = Float(0.02 + 0.3 * (1 + sin(phase + Double(channel) * 0.6))) * (channel == count - 1 ? 0 : 1)
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
