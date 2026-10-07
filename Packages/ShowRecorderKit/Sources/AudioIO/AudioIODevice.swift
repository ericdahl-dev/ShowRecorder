/// One block of input audio, delivered on the real-time audio thread.
///
/// Samples are planar 32-bit float: `channels[c][f]` is frame `f` of USB Channel `c`.
/// The pointers are only valid for the duration of the callback.
public struct AudioBlock {
    public let channels: UnsafePointer<UnsafePointer<Float>>
    public let channelCount: Int
    public let frameCount: Int
    public let hostTime: UInt64

    public init(channels: UnsafePointer<UnsafePointer<Float>>, channelCount: Int, frameCount: Int, hostTime: UInt64) {
        self.channels = channels
        self.channelCount = channelCount
        self.frameCount = frameCount
        self.hostTime = hostTime
    }
}

/// Called on the real-time audio thread for every input block.
///
/// Implementations must not allocate, lock, log, or touch the file system, UI or network (ADR 0002).
public typealias AudioInputHandler = @Sendable (AudioBlock) -> Void

/// The audio I/O boundary: a full-duplex device on one clock.
///
/// Input is used now. Output (`outputChannelCount`) is part of the boundary so virtual soundcheck
/// can play Stems back to the Mixer later on the same clock.
public protocol AudioIODevice: AnyObject, Sendable {
    var name: String { get }
    var inputChannelCount: Int { get }
    var outputChannelCount: Int { get }
    var sampleRate: Double { get }

    /// Starts the device. `input` is called on the real-time thread until `stop()` returns.
    func start(input: @escaping AudioInputHandler) throws
    func stop()
}
