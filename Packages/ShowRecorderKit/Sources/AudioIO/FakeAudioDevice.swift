import Synchronization

/// A device for tests and previews. Audio is pushed in by calling `deliver(...)`.
public final class FakeAudioDevice: AudioIODevice {
    public let name: String
    public let inputChannelCount: Int
    public let outputChannelCount: Int
    public let sampleRate: Double

    /// Boxed so the mutex holds a class reference, not a function value. Passing a function `inout`
    /// through `Mutex.withLock` re-wraps it in a thunk on every access, which grew a new layer per
    /// delivered block until the stack overflowed.
    private final class HandlerBox: Sendable {
        let call: AudioInputHandler
        init(_ call: @escaping AudioInputHandler) { self.call = call }
    }

    private let handler = Mutex<HandlerBox?>(nil)

    public init(name: String = "Fake Device", inputChannelCount: Int, outputChannelCount: Int = 0, sampleRate: Double = 48_000) {
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.sampleRate = sampleRate
    }

    public var isRunning: Bool { handler.withLock { $0 != nil } }

    public func start(input: @escaping AudioInputHandler) throws {
        handler.withLock { $0 = HandlerBox(input) }
    }

    public func stop() {
        handler.withLock { $0 = nil }
    }

    /// Delivers one block of audio to the running handler, on the calling thread.
    /// `channels[c]` holds the samples of USB Channel `c`; all channels must be the same length.
    public func deliver(_ channels: [[Float]], hostTime: UInt64 = 0) {
        guard let input = handler.withLock({ $0?.call }) else { return }
        let frameCount = channels.first?.count ?? 0
        precondition(channels.allSatisfy { $0.count == frameCount }, "all channels must have the same frame count")

        let buffers = channels.map { samples -> UnsafeMutablePointer<Float> in
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: max(frameCount, 1))
            buffer.initialize(from: samples, count: frameCount)
            return buffer
        }
        defer { buffers.forEach { $0.deallocate() } }

        buffers.map { UnsafePointer($0) }.withUnsafeBufferPointer { pointers in
            input(AudioBlock(channels: pointers.baseAddress!, channelCount: channels.count, frameCount: frameCount, hostTime: hostTime))
        }
    }
}
