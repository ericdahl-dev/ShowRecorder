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
    /// Asks for `sampleRate` (48 kHz unless chosen otherwise, #195; nil asks for nothing) and the most input channels
    /// the route offers. A mixer's input keeps the mixer's rate whatever is asked.
    ///
    /// With `preferredInputUID`, first asks iOS to use that input (a USB interface rather than the
    /// built-in microphone). iOS decides, so the route afterwards may still differ.
    ///
    /// `plan` is `.recording` for every normal Take: record only, exactly as before. The headphone monitor experiment
    /// (#233) passes `.monitorExperiment`: play and record, with Bluetooth headphones allowed for output only (A2DP,
    /// never the headset's HFP mic) and never the phone's speaker; it doesn't ask for the chosen input (see
    /// `AudioSessionPlan.pinsPreferredInput`).
    public static func current(
        preferredInputUID: String? = nil, sampleRate: Int? = 48_000, plan: AudioSessionPlan = .recording
    ) throws -> SessionAudioDevice {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(Self.category(for: plan), mode: .measurement, options: Self.options(for: plan))
        if plan.pinsPreferredInput, let preferredInputUID,
           let port = audioSession.availableInputs?.first(where: { $0.uid == preferredInputUID }) {
            try audioSession.setPreferredInput(port)
        }
        // The Marker button's haptic: iOS mutes haptics and system sounds while recording unless allowed.
        try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
        if let sampleRate { try audioSession.setPreferredSampleRate(Double(sampleRate)) }
        try audioSession.setActive(true)

        let maximum = audioSession.maximumInputNumberOfChannels
        if maximum > 0 {
            try audioSession.setPreferredInputNumberOfChannels(maximum)
        }
        let name = audioSession.currentRoute.inputs.first?.portName ?? "Audio interface"
        return SessionAudioDevice(
            name: name,
            inputChannelCount: audioSession.inputNumberOfChannels,
            maximumInputChannelCount: maximum,
            sampleRate: audioSession.sampleRate)
    }

    /// `.record` unless the plan plays output.
    static func category(for plan: AudioSessionPlan) -> AVAudioSession.Category {
        plan.playsOutput ? .playAndRecord : .record
    }

    /// None for `.recording`. Bluetooth only as A2DP output; HFP (`.allowBluetoothHFP`) and `.defaultToSpeaker` are
    /// never set, whatever the plan says, so a headset's mic can't replace the recorded input.
    static func options(for plan: AudioSessionPlan) -> AVAudioSession.CategoryOptions {
        guard plan.playsOutput else { return [] }
        return plan.allowsBluetoothOutput ? [.allowBluetoothA2DP] : []
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
