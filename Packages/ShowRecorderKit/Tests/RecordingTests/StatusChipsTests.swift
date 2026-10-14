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
        // No running words is no Take running, as the record screen passes them today.
        let take = TakeCopies(isRunning: !copies.isEmpty) { copies[$0].map(CopyState.init) ?? .recording }
        return Dictionary(uniqueKeysWithValues: StatusChip.make(
            usbChannelCount: 18, deviceAvailableBytes: deviceBytes, drive: drive, mixer: mixer, copies: take
        ).map { ($0.kind, $0) })
    }

    func drive(bytes: Int64) -> DriveStatus {
        .available(Drive(folder: URL(filePath: "/Volumes/SSD"), name: "SSD", availableBytes: bytes))
    }

    @Test("Time left follows the Armed input's sample rate: the same space lasts longer at 44.1 kHz, half as long at 96 kHz (#298)")
    func timeLeftAtInputRate() {
        func texts(_ rate: Int) -> [String] {
            StatusChip.make(
                usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour), mixer: .idle,
                copies: .none, sampleRate: rate
            ).filter { $0.kind != .mixer }.map(\.text)
        }
        #expect(texts(48_000) == ["Device 1 h 00 min", "Drive 1 h 00 min"])
        #expect(texts(44_100) == ["Device 1 h 05 min", "Drive 1 h 05 min"])
        #expect(texts(96_000) == ["Device 30 min", "Drive 30 min"])
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

    @Test("Drive only: the Device chip shows time left while the Device stands by or stands in (#196)")
    func driveOnlyDeviceChip() {
        for device in [CopyState.standingBy, .standingIn] {
            let chip = StatusChip.make(
                usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour), mixer: nil,
                copies: takeCopies(device: device, drive: .recording)
            ).first { $0.kind == .device }

            #expect(chip?.text == "Device 1 h 00 min")
            #expect(chip?.state == .ok)
        }
    }

    @Test("Mixer chip: not linked, connecting, up and down")
    func mixerStates() {
        #expect(chips(mixer: .idle)[.mixer]?.text == "Mixer not linked")
        #expect(chips(mixer: .idle)[.mixer]?.state == .neutral)
        #expect(chips(mixer: .connecting(host: "10.0.0.9"))[.mixer]?.text == "Mixer connecting")

        // The Mixer's own network name, so two XR18s on one network can be told apart (#328); the model and path
        // go to VoiceOver and stay as the text when the Mixer has no name.
        let up = chips(mixer: .up(MixerIdentity(networkName: "FOH", model: "XR18", firmware: "1.0"), path: .wifi))[.mixer]
        #expect(up?.text == "FOH")
        #expect(up?.detail == "XR18 · Wi-Fi")
        #expect(up?.state == .ok)
        let unnamed = chips(mixer: .up(MixerIdentity(networkName: "  ", model: "XR18", firmware: "1.0"), path: .wifi))[.mixer]
        #expect(unnamed?.text == "XR18 · Wi-Fi")
        #expect(unnamed?.detail == nil)

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

    @Test("After a Take, a Copy that stopped during it no longer shows as stopped: the chips are back to time left")
    func stoppedOnlyWhileRunning() {
        let ended = TakeCopies(isRunning: false) { _ in .interrupted }
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour),
                                    mixer: nil, copies: ended).map(\.text)
        #expect(shown == ["Device 1 h 00 min", "Drive 1 h 00 min"])
    }

    @Test("Drive only between Takes, the Drive there: one chip, the Drive's, beside the Mixer's (#550)")
    func driveOnlyBetweenTakesDrive() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: .idle, copies: .none, driveOnly: true).map(\.text)
        #expect(shown == ["Drive 2 h 00 min", "Mixer not linked"])
    }

    @Test("Drive only between Takes, no Drive: one chip, the Device's, since the Device would stand in (#550)")
    func driveOnlyBetweenTakesNoDrive() {
        for drive in [DriveStatus.notChosen, .unavailable(.notConnected(name: "SSD"))] {
            let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive,
                                        mixer: nil, copies: .none, driveOnly: true).map(\.text)
            #expect(shown == ["Device 1 h 00 min"])
        }
    }

    @Test("A Drive-only Take with the Device standing by: one chip, the Drive's (#550)")
    func driveOnlyTakeStandingBy() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: nil, copies: takeCopies(driveOnly: true, device: .standingBy, drive: .recording))
        #expect(shown.map(\.text) == ["Drive 2 h 00 min"])
    }

    @Test("A Drive-only Take with the Device standing in for the Drive: one chip, the Device's (#550)")
    func driveOnlyTakeStandingIn() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: nil, copies: takeCopies(driveOnly: true, device: .standingIn, drive: .interrupted))
        #expect(shown.map(\.text) == ["Device 1 h 00 min"])
    }

    @Test("A Drive-only Take that started with no Drive: the Device records it, so one chip, the Device's (#550)")
    func driveOnlyTakeWithoutDrive() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour,
                                    drive: .unavailable(.notConnected(name: "SSD")), mixer: nil,
                                    copies: takeCopies(driveOnly: true, device: .recording, drive: .missing))
        #expect(shown.map(\.text) == ["Device 1 h 00 min"])
    }

    @Test("A Drive that joins a Drive-only Take takes the audio: one chip, the Drive's (#550)")
    func driveOnlyTakeDriveJoined() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: nil, copies: takeCopies(driveOnly: true, device: .recording, drive: .recording))
        #expect(shown.map(\.text) == ["Drive 2 h 00 min"])
    }

    @Test("The Device standing in for a stalled Drive that still reads recording: one chip, the Device's (#550)")
    func driveOnlyTakeStandingInStall() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: nil, copies: takeCopies(driveOnly: true, device: .standingIn, drive: .recording))
        #expect(shown.map(\.text) == ["Device 1 h 00 min"])
    }

    @Test("A stand-in that failed, with the Drive stopped too: one chip, the Drive's, saying it stopped (#550)")
    func driveOnlyTakeStandInFailed() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: nil, copies: takeCopies(driveOnly: true, device: .interrupted, drive: .interrupted))
        #expect(shown.map(\.text) == ["Drive stopped"])
        #expect(shown.first?.state == .failed)
    }

    @Test("A Drive-only Take with a Mixer: one of the Device and Drive chips, then the Mixer's (#550)")
    func driveOnlyTakeWithMixer() {
        let shown = StatusChip.make(usbChannelCount: 18, deviceAvailableBytes: Self.anHour, drive: drive(bytes: Self.anHour * 2),
                                    mixer: .idle, copies: takeCopies(driveOnly: true, device: .standingBy, drive: .recording))
        #expect(shown.map(\.text) == ["Drive 2 h 00 min", "Mixer not linked"])
    }
}
