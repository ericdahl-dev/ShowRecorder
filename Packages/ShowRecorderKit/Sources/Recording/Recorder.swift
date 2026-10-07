import AudioIO
import Observation

/// The recorder. While Armed it receives audio from a device and keeps meters for every USB Channel.
@MainActor
@Observable
public final class Recorder {
    public private(set) var isArmed = false
    public private(set) var usbChannelCount = 0

    /// The XR18 and MR18 send 18 USB Channels. Fewer means some of the Mixer won't be recorded.
    public static let expectedUSBChannelCount = 18

    /// True while Armed on a device with fewer than 18 USB Channels.
    public var hasTooFewUSBChannels: Bool {
        isArmed && usbChannelCount < Self.expectedUSBChannelCount
    }

    @ObservationIgnored private var device: (any AudioIODevice)?
    @ObservationIgnored private var meters: PeakMeters?

    public init() {}

    /// Starts receiving audio from `device`. Any previously Armed device is stopped first.
    public func arm(_ device: any AudioIODevice) throws {
        disarm()
        let meters = PeakMeters(channelCount: device.inputChannelCount)
        try device.start(input: { block in meters.record(block) })
        self.device = device
        self.meters = meters
        usbChannelCount = device.inputChannelCount
        isArmed = true
    }

    /// Stops the device and clears the meters.
    public func disarm() {
        device?.stop()
        device = nil
        meters = nil
        usbChannelCount = 0
        isArmed = false
    }

    /// Each USB Channel's linear peak level (0...1) since the last call. Empty when not Armed.
    public func takeMeterLevels() -> [Float] {
        meters?.take() ?? []
    }
}
