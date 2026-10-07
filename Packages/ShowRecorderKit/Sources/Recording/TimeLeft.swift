/// How long a Destination can keep recording: free space ÷ the data rate of every USB Channel
/// (mono 24-bit Stems).
public struct TimeLeft: Equatable, Sendable, CustomStringConvertible {
    /// Whole seconds, or nil when there's nothing to record.
    public let seconds: Int64?

    public init(availableBytes: Int64, usbChannelCount: Int, sampleRate: Int) {
        let bytesPerSecond = Int64(usbChannelCount) * Int64(sampleRate) * 3
        seconds = bytesPerSecond > 0 ? max(availableBytes, 0) / bytesPerSecond : nil
    }

    public var description: String {
        guard let seconds else { return "–" }
        let minutes = seconds / 60
        if minutes < 1 { return "under 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }
}
