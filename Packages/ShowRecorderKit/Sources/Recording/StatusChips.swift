import Destinations
import MixerLink

/// One chip in the record screen's status strip: a Destination's or the Mixer's state in a few words.
public struct StatusChip: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable, Hashable, CaseIterable {
        case device, drive, mixer
    }

    /// Ok states stay quiet; only attention and failed draw the eye.
    public enum State: Sendable {
        case neutral, ok, attention, failed
    }

    public var kind: Kind
    public var text: String
    public var state: State
    public var id: Kind { kind }

    /// The chips for the current Destinations and Mixer Link, in the order they're shown.
    ///
    /// - Parameter copies: how each Copy of the running Take is doing; empty when no Take is running.
    public static func make(
        usbChannelCount: Int,
        deviceAvailableBytes: Int64,
        drive: DriveStatus,
        mixer: MixerLinkStatus,
        copies: [DestinationKind: CopyStatus]
    ) -> [StatusChip] {
        func timeLeft(_ bytes: Int64) -> TimeLeft {
            TimeLeft(availableBytes: bytes, usbChannelCount: usbChannelCount, sampleRate: 48_000)
        }
        /// Under ten minutes of audio left.
        func isLow(_ left: TimeLeft) -> Bool { (left.seconds ?? .max) < 600 }

        let deviceLeft = timeLeft(deviceAvailableBytes)
        var device = StatusChip(kind: .device, text: "Device \(deviceLeft)", state: isLow(deviceLeft) ? .attention : .ok)
        if copies[.device] == .interrupted { device = StatusChip(kind: .device, text: "Device stopped", state: .failed) }

        var driveChip: StatusChip
        switch drive {
        case .notChosen:
            driveChip = StatusChip(kind: .drive, text: "Drive not set", state: .neutral)
        case .available(let available):
            let left = timeLeft(available.availableBytes)
            driveChip = StatusChip(kind: .drive, text: "Drive \(left)", state: isLow(left) ? .attention : .ok)
        case .unavailable:
            driveChip = StatusChip(kind: .drive, text: "Drive missing", state: .attention)
        }
        if copies[.drive] == .interrupted { driveChip = StatusChip(kind: .drive, text: "Drive stopped", state: .failed) }

        let mixerChip: StatusChip
        switch mixer {
        case .idle:
            mixerChip = StatusChip(kind: .mixer, text: "Mixer not linked", state: .neutral)
        case .connecting:
            mixerChip = StatusChip(kind: .mixer, text: "Mixer connecting", state: .neutral)
        case .up(let identity, let path):
            mixerChip = StatusChip(kind: .mixer, text: "\(identity.model) · \(path == .wifi ? "Wi-Fi" : "USB")", state: .ok)
        case .down:
            mixerChip = StatusChip(kind: .mixer, text: "Mixer down", state: .attention)
        }
        return [device, driveChip, mixerChip]
    }
}
