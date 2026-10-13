#if DEBUG
import AVFoundation
import AudioIO
import Foundation
import Recording

/// A folder of stems played as USB Channels, for screenshots (#374): `-demoStems <folder>`, Debug only. Each stereo
/// file is two channels, in a band's order (`StemDemoLayout`), resampled to 48 kHz and looped, so the meters move like
/// a real mixer's. The files are read from the folder given; none are part of the app.
final class DemoStemsDevice: AudioIODevice, @unchecked Sendable {
    /// The folder `-demoStems` names, if any.
    static var folder: URL? {
        let arguments = CommandLine.arguments
        guard launchFlag("-demoStems"), let index = arguments.firstIndex(of: "-demoStems"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    /// The stems in the folder, in channel order; nil when there's no folder or no WAV in it.
    static func layout(of folder: URL) -> StemDemoLayout? {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".wav") }
            .compactMap { name -> (String, Int)? in
                guard let file = try? AVAudioFile(forReading: folder.appending(path: name)) else { return nil }
                return (name, Int(file.processingFormat.channelCount))
            }
        return files.isEmpty ? nil : StemDemoLayout(files: files)
    }

    /// Mastered stems peak near full scale; a mixer's USB sends sit lower, so the meters show mostly green and yellow.
    static let trim: Float = 0.5
    /// Where in the song the loop starts (the intro leaves some stems silent), and how long it plays before it loops.
    static let startSeconds = 25.0
    static let seconds = 15.0

    let name = "Demo stems"
    let sampleRate = 48_000.0
    let inputChannelCount: Int
    var outputChannelCount: Int { inputChannelCount }

    private let channels: [[Float]]
    private let fake: FakeAudioDevice
    private var task: Task<Void, Never>?

    init(folder: URL, layout: StemDemoLayout) {
        var channels: [[Float]] = []
        for stem in layout.order {
            channels += Self.read(folder.appending(path: stem.file), channels: stem.channels)
        }
        self.channels = channels
        inputChannelCount = channels.count
        fake = FakeAudioDevice(inputChannelCount: channels.count)
    }

    /// The file's channels at 48 kHz, trimmed, up to `seconds` long; silence when it can't be read.
    private static func read(_ url: URL, channels count: Int) -> [[Float]] {
        let frames = Int(48_000 * seconds)
        let silence = Array(repeating: [Float](repeating: 0, count: 4_800), count: count)
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: AVAudioChannelCount(count)),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(frames))
        else { return silence }
        file.framePosition = min(AVAudioFramePosition(startSeconds * file.processingFormat.sampleRate), max(file.length - 1, 0))
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192)!
        var done = false
        _ = converter.convert(to: output, error: nil) { _, status in
            guard !done, (try? file.read(into: input)) != nil, input.frameLength > 0 else {
                done = true
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return input
        }
        guard let data = output.floatChannelData, output.frameLength > 0 else { return silence }
        return (0..<count).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: Int(output.frameLength))).map { $0 * trim }
        }
    }

    func start(input: @escaping AudioInputHandler) throws {
        stop()
        try fake.start(input: input)
        let fake = fake
        let channels = channels
        task = Task.detached(priority: .userInitiated) {
            let length = channels.first?.count ?? 0
            guard length > 480 else { return }
            var position = 0
            while !Task.isCancelled {
                if position + 480 > length { position = 0 }
                fake.deliver(channels.map { Array($0[position..<(position + 480)]) })
                position += 480
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
