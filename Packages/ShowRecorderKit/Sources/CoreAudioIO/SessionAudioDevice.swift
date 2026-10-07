#if os(iOS)
import AudioIO
import AudioToolbox
import AVFAudio

/// The current iOS audio input route (for example a mixer on a USB-C hub), used as the recorder's
/// audio I/O.
///
/// `current()` configures the shared `AVAudioSession` for multitrack recording and asks for every
/// input channel the route offers. Input then runs through a RemoteIO unit with the same real-time
/// callback as on the Mac (ADR 0002).
public final class SessionAudioDevice: AudioIODevice, @unchecked Sendable {
    public let name: String
    public let inputChannelCount: Int
    /// Most channels the route offers, before asking. Shown if iOS grants fewer.
    public let maximumInputChannelCount: Int
    public let outputChannelCount = 0
    public let sampleRate: Double

    private var session: InputSession?

    private init(name: String, inputChannelCount: Int, maximumInputChannelCount: Int, sampleRate: Double) {
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.maximumInputChannelCount = maximumInputChannelCount
        self.sampleRate = sampleRate
    }

    deinit { stop() }

    /// Configures and activates the audio session and describes the current input route.
    ///
    /// Record category in measurement mode, so iOS applies no gain control or voice processing.
    /// Asks for 48 kHz and the most input channels the route offers.
    ///
    /// With `preferredInputUID`, first asks iOS to use that input (a USB interface rather than the
    /// built-in microphone). iOS decides, so the route afterwards may still differ.
    public static func current(preferredInputUID: String? = nil) throws -> SessionAudioDevice {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        if let preferredInputUID, let port = audioSession.availableInputs?.first(where: { $0.uid == preferredInputUID }) {
            try audioSession.setPreferredInput(port)
        }
        // The Marker button's haptic: iOS mutes haptics and system sounds while recording unless allowed.
        try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try audioSession.setPreferredSampleRate(48_000)
        try audioSession.setActive(true)

        let maximum = audioSession.maximumInputNumberOfChannels
        if maximum > 0 {
            try audioSession.setPreferredInputNumberOfChannels(maximum)
        }
        let name = audioSession.currentRoute.inputs.first?.portName ?? "Audio input"
        return SessionAudioDevice(
            name: name,
            inputChannelCount: audioSession.inputNumberOfChannels,
            maximumInputChannelCount: maximum,
            sampleRate: audioSession.sampleRate)
    }

    /// Starts input. Also reactivates the audio session, which an interruption deactivates, so this
    /// is how input restarts afterwards; it throws if another app still holds the session.
    public func start(input: @escaping AudioInputHandler) throws {
        stop()
        try AVAudioSession.sharedInstance().setActive(true)
        session = try InputSession(
            subtype: kAudioUnitSubType_RemoteIO,
            channelCount: inputChannelCount,
            sampleRate: sampleRate,
            handler: input)
    }

    public func stop() {
        session?.stop()
        session = nil
    }
}
#endif
