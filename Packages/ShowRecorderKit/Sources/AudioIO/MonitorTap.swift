/// Feeds the headphone monitor (#233) from an input device: every block goes to the recorder's handler first, as it
/// came, then the block's first channel is copied into the monitor's ring. The copy never waits: a full ring drops it.
public final class MonitorTap: AudioIODevice {
    private let device: any AudioIODevice
    public let ring: MonitorRing

    public init(_ device: any AudioIODevice, ring: MonitorRing) {
        self.device = device
        self.ring = ring
    }

    public var name: String { device.name }
    public var inputChannelCount: Int { device.inputChannelCount }
    public var outputChannelCount: Int { device.outputChannelCount }
    public var sampleRate: Double { device.sampleRate }

    public func start(input: @escaping AudioInputHandler) throws {
        let ring = ring
        try device.start { block in
            input(block)
            if block.channelCount > 0 { ring.write(block.channels[0], count: block.frameCount) }
        }
    }

    public func stop() { device.stop() }
}

/// How the audio session is set up for a recording: record only (every normal Take), or record and play to
/// headphones for the monitor experiment (#233). Bluetooth may carry the output, never the input: a headset's mic must
/// not take over from the input being recorded.
public struct AudioSessionPlan: Equatable, Sendable {
    public var playsOutput: Bool
    /// Bluetooth headphones for output only (A2DP).
    public var allowsBluetoothOutput: Bool
    /// A Bluetooth headset as input too (HFP). Never, in either plan.
    public var allowsBluetoothInput: Bool
    /// Play through the phone's speaker when nothing is plugged in.
    public var defaultToSpeaker: Bool

    public init(playsOutput: Bool, allowsBluetoothOutput: Bool, allowsBluetoothInput: Bool, defaultToSpeaker: Bool) {
        self.playsOutput = playsOutput
        self.allowsBluetoothOutput = allowsBluetoothOutput
        self.allowsBluetoothInput = allowsBluetoothInput
        self.defaultToSpeaker = defaultToSpeaker
    }

    public static let recording = AudioSessionPlan(playsOutput: false, allowsBluetoothOutput: false, allowsBluetoothInput: false, defaultToSpeaker: false)
    public static let monitorExperiment = AudioSessionPlan(playsOutput: true, allowsBluetoothOutput: true, allowsBluetoothInput: false, defaultToSpeaker: false)
}
