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
    /// More about it, for VoiceOver: the linked Mixer's model and path when the text is its network name.
    public var detail: String?
    public var id: Kind { kind }

    public init(kind: Kind, text: String, state: State, detail: String? = nil) {
        self.kind = kind
        self.text = text
        self.state = state
        self.detail = detail
    }

    /// A shorter text for tight layouts: a time left drops the "Device" or "Drive" the chip's icon already
    /// says. Problems and "not set" keep their full words.
    public var shortText: String {
        for prefix in ["Device ", "Drive "] where text.hasPrefix(prefix) {
            let rest = String(text.dropFirst(prefix.count))
            if state != .failed, rest.contains(where: \.isNumber) { return rest }
        }
        return text
    }

    /// The chips for the current Destinations and Mixer Link, in the order they're shown.
    ///
    /// - Parameters:
    ///   - copies: the Take's Copies (#550): one that stopped mid-Take says so while the Take runs.
    ///   - sampleRate: the Armed input's rate, for the time left (#298); 48 kHz when nothing is Armed.
    ///   - mixer: nil when the input isn't an X Air or X32: Mixer Link isn't offered, so there's no Mixer chip (#365).
    ///   - driveOnly: the Drive only setting (#196), so it applies between Takes too. Drive only, or a Drive-only Take,
    ///     shows one of the Device and Drive chips (#550).
    public static func make(
        usbChannelCount: Int,
        deviceAvailableBytes: Int64,
        drive: DriveStatus,
        mixer: MixerLinkStatus?,
        copies: TakeCopies,
        sampleRate: Int = 48_000,
        driveOnly: Bool = false,
        otherMixer: MixerIdentity? = nil
    ) -> [StatusChip] {
        func stopped(_ kind: DestinationKind) -> Bool { copies.isRunning && copies[kind] == .interrupted }
        func timeLeft(_ bytes: Int64) -> TimeLeft {
            TimeLeft(availableBytes: bytes, usbChannelCount: usbChannelCount, sampleRate: sampleRate)
        }
        /// Under ten minutes of audio left.
        func isLow(_ left: TimeLeft) -> Bool { (left.seconds ?? .max) < 600 }

        let deviceLeft = timeLeft(deviceAvailableBytes)
        var device = StatusChip(kind: .device, text: "Device \(deviceLeft)", state: isLow(deviceLeft) ? .attention : .ok)
        if stopped(.device) { device = StatusChip(kind: .device, text: "Device stopped", state: .failed) }

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
        if stopped(.drive) { driveChip = StatusChip(kind: .drive, text: "Drive stopped", state: .failed) }

        var chips = [device, driveChip]
        if driveOnly || copies.isDriveOnly {
            var driveAvailable: Bool { if case .available = drive { true } else { false } }
            let deviceWrites = copies.isRunning
                ? copies[.device] == .standingIn || (copies[.device] == .recording && copies[.drive] != .recording)
                : !driveAvailable
            chips = [deviceWrites ? device : driveChip]
        }

        guard let mixer else { return chips }
        // The Link is on another Mixer than the Armed one (#647): not a healthy chip.
        if let otherMixer {
            let name = otherMixer.networkName.trimmingCharacters(in: .whitespaces)
            let detail = name.isEmpty ? otherMixer.model : "\(name) · \(otherMixer.model)"
            return chips + [StatusChip(kind: .mixer, text: "Other Mixer linked", state: .attention, detail: detail)]
        }
        let mixerChip: StatusChip
        switch mixer {
        case .idle:
            mixerChip = StatusChip(kind: .mixer, text: "Mixer not linked", state: .neutral)
        case .connecting:
            mixerChip = StatusChip(kind: .mixer, text: "Mixer connecting", state: .neutral)
        case .up(let identity, let path):
            // The Mixer's network name tells two of the same model apart (#328); without one, its model and path.
            let modelAndPath = "\(identity.model) · \(path.name)"
            let name = identity.networkName.trimmingCharacters(in: .whitespaces)
            mixerChip = name.isEmpty
                ? StatusChip(kind: .mixer, text: modelAndPath, state: .ok)
                : StatusChip(kind: .mixer, text: name, state: .ok, detail: modelAndPath)
        case .down:
            mixerChip = StatusChip(kind: .mixer, text: "Mixer down", state: .attention)
        }
        return chips + [mixerChip]
    }
}
