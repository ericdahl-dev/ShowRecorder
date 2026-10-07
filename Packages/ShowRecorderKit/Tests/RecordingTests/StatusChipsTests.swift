import Destinations
import Foundation
import MixerLink
@testable import Recording
import Testing

@Suite("Status chips")
struct StatusChipsTests {
    /// One hour of 18 channels at 48 kHz, 24-bit.
    static let anHour: Int64 = 18 * 48_000 * 3 * 3_600

    func chips(
        deviceBytes: Int64 = StatusChipsTests.anHour,
        drive: DriveStatus = .notChosen,
        mixer: MixerLinkStatus = .idle,
        copies: [DestinationKind: CopyStatus] = [:]
    ) -> [StatusChip.Kind: StatusChip] {
        Dictionary(uniqueKeysWithValues: StatusChip.make(
            usbChannelCount: 18, deviceAvailableBytes: deviceBytes, drive: drive, mixer: mixer, copies: copies
        ).map { ($0.kind, $0) })
    }

    func drive(bytes: Int64) -> DriveStatus {
        .available(Drive(folder: URL(filePath: "/Volumes/SSD"), name: "SSD", availableBytes: bytes))
    }

    @Test("The Device chip shows time left")
    func deviceTimeLeft() {
        let device = chips()[.device]

        #expect(device?.text == "Device 1 h 00 min")
        #expect(device?.state == .ok)
    }

    @Test("Under ten minutes left needs attention")
    func lowTimeLeftNeedsAttention() {
        let device = chips(deviceBytes: StatusChipsTests.anHour / 12)[.device]

        #expect(device?.text == "Device 5 min")
        #expect(device?.state == .attention)
    }

    @Test("Drive chip: not chosen, available and missing")
    func driveStates() {
        #expect(chips(drive: .notChosen)[.drive]?.text == "Drive not set")
        #expect(chips(drive: .notChosen)[.drive]?.state == .neutral)

        let available = chips(drive: drive(bytes: StatusChipsTests.anHour * 2))[.drive]
        #expect(available?.text == "Drive 2 h 00 min")
        #expect(available?.state == .ok)

        let missing = chips(drive: .unavailable(.notConnected(name: "SSD")))[.drive]
        #expect(missing?.text == "Drive missing")
        #expect(missing?.state == .attention)
    }

    @Test("A Copy that stopped during the Take is a failure on its chip")
    func interruptedCopyFails() {
        let result = chips(drive: drive(bytes: StatusChipsTests.anHour), copies: [.device: .recording, .drive: .interrupted])

        #expect(result[.drive]?.text == "Drive stopped")
        #expect(result[.drive]?.state == .failed)
        #expect(result[.device]?.state == .ok)
    }

    @Test("Mixer chip: not linked, connecting, up and down")
    func mixerStates() {
        #expect(chips(mixer: .idle)[.mixer]?.text == "Mixer not linked")
        #expect(chips(mixer: .idle)[.mixer]?.state == .neutral)
        #expect(chips(mixer: .connecting(host: "10.0.0.9"))[.mixer]?.text == "Mixer connecting")

        let up = chips(mixer: .up(MixerIdentity(networkName: "FOH", model: "XR18", firmware: "1.0"), path: .wifi))[.mixer]
        #expect(up?.text == "XR18 · Wi-Fi")
        #expect(up?.state == .ok)

        let down = chips(mixer: .down(.noReply(host: "10.0.0.9")))[.mixer]
        #expect(down?.text == "Mixer down")
        #expect(down?.state == .attention)
    }

    @Test("Short text drops the word the icon already says, but keeps problems in full")
    func shortText() {
        let ok = chips(drive: drive(bytes: StatusChipsTests.anHour * 2))
        #expect(ok[.device]?.shortText == "1 h 00 min")
        #expect(ok[.drive]?.shortText == "2 h 00 min")
        #expect(ok[.mixer]?.shortText == "Mixer not linked")

        #expect(chips(drive: .notChosen)[.drive]?.shortText == "Drive not set")
        #expect(chips(drive: .unavailable(.notConnected(name: "SSD")))[.drive]?.shortText == "Drive missing")
        let stopped = chips(drive: drive(bytes: StatusChipsTests.anHour), copies: [.drive: .interrupted])
        #expect(stopped[.drive]?.shortText == "Drive stopped")
    }
}
