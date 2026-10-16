/// Decides whether a Take is recording silence (#778): every channel's peak stayed under -90 dBFS for `waitSeconds`
/// of audio, counted after the first `graceSeconds` of the Take. Any channel above the floor counts as signal, clears
/// the warning at once and starts the wait over.
///
/// It reads the meter windows (`ChannelLevel`) from the non-real-time App loop and never touches the audio path. It
/// counts audio frames, not wall time, so a stalled loop doesn't move it, and a window with no frames (the input
/// stopped) neither counts toward the wait nor resets it.
public struct NoSignalDetector: Sendable, Equatable {
    /// How long a Take must record nothing but silence before the warning shows.
    public static let defaultWaitSeconds = 10.0

    /// The warning: the Take has recorded nothing but silence for the wait.
    public private(set) var isSilent = false

    private let floor: Float
    private let graceSeconds: Double
    private let waitSeconds: Double
    private var elapsed = 0.0
    private var silentSeconds = 0.0

    /// `floor` is a linear peak, 3.2e-5 being -90 dBFS.
    public init(floor: Float = 3.2e-5, graceSeconds: Double = 3, waitSeconds: Double = defaultWaitSeconds) {
        self.floor = floor
        self.graceSeconds = graceSeconds
        self.waitSeconds = waitSeconds
    }

    /// Takes one read of the meters, `sampleRate` being the rate of the frames in it.
    public mutating func feed(_ levels: [ChannelLevel], sampleRate: Double) {
        let frames = levels.map(\.frames).max() ?? 0
        guard frames > 0, sampleRate > 0 else { return }
        let seconds = Double(frames) / sampleRate
        if levels.contains(where: { $0.peak > floor }) {
            silentSeconds = 0
            isSilent = false
        } else {
            silentSeconds += max(0, min(seconds, elapsed + seconds - graceSeconds))
            // The tolerance absorbs rounding from adding many small windows.
            isSilent = silentSeconds >= waitSeconds - 1e-6
        }
        elapsed += seconds
    }

    /// Starts over for a new Take: no warning, and the grace again.
    public mutating func reset() {
        elapsed = 0
        silentSeconds = 0
        isSilent = false
    }
}
