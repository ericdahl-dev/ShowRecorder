@testable import Recording
import Testing


/// What the record screen says about the Copies of a running Take.
@Suite("Destination alert")
struct DestinationAlertTests {
    @Test("A Drive that stops mid-Take is critical, with its own id, so it is not mistaken for the quiet 'No Drive' notice")
    func driveStoppedIsCritical() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .interrupted)))

        #expect(alert.id == "drive-stopped")
        #expect(alert.tone == .critical)
        #expect(alert.priority == .destination)
        #expect(alert.text.contains("Drive stopped"))
        #expect(alert.text.contains("Gap"))
    }

    @Test("Drive only: the Device standing by or standing in says what it said as missing or recording (#196)")
    func driveOnlyStatesSayTheSame() throws {
        #expect(DestinationAlert.make(copies: takeCopies(device: .standingBy, drive: .recording)) == nil)
        #expect(DestinationAlert.make(copies: takeCopies(device: .standingIn, drive: .recording)) == nil)
        let stopped = try #require(DestinationAlert.make(copies: takeCopies(device: .standingIn, drive: .interrupted)))
        #expect(stopped.id == "drive-stopped")
        #expect(stopped.tone == .critical)
        #expect(stopped.text == "The Drive stopped. Recording continues on the Device; the Gap is Repaired when the Drive comes back.")
    }

    @Test("No Drive at the start of a Take is the quiet warning, not the critical one")
    func noDriveIsAWarning() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .missing)))

        #expect(alert.id == "no-drive")
        #expect(alert.tone == .warning)
        #expect(alert.text == "No Drive. Recording to the Device only.")
    }

    @Test("Drive only, no Drive at record: the audio goes to this iPhone and moves to the Drive later (#550)")
    func driveOnlyNoDrive() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(driveOnly: true, device: .recording, drive: .missing)))

        #expect(alert.id == "no-drive")
        #expect(alert.tone == .warning)
        #expect(alert.priority == .destination)
        #expect(alert.text == "No Drive: recording to this iPhone; it moves to the Drive when one is connected.")
    }

    @Test("Drive only, the Drive stops and the Device stands in: recording to this iPhone for the rest of the Take, no Check Drive (#550)")
    func driveOnlyDriveStopped() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(driveOnly: true, device: .standingIn, drive: .interrupted)))

        #expect(alert.id == "drive-stopped")
        #expect(alert.tone == .critical)
        #expect(alert.priority == .destination)
        #expect(alert.action == nil)
        #expect(alert.text == "The Drive stopped. Recording to this iPhone for the rest of the Take; the audio moves to the Drive after it.")
    }

    @Test("Drive only, the Device stands in after a stall while the Drive still says recording: the same stand-in alert (#550)")
    func driveOnlyStallStandIn() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(driveOnly: true, device: .standingIn, drive: .recording)))

        #expect(alert.id == "drive-stopped")
        #expect(alert.tone == .critical)
        #expect(alert.action == nil)
        #expect(alert.text == "The Drive stopped. Recording to this iPhone for the rest of the Take; the audio moves to the Drive after it.")
    }

    @Test("Drive only that started with no Drive: a Drive connected later is an ordinary Copy, so its stop says the normal text with Check Drive (#550)")
    func driveOnlyLateDriveStops() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(driveOnly: true, device: .recording, drive: .interrupted)))

        #expect(alert.id == "drive-stopped")
        #expect(alert.action == .checkDrive)
        #expect(alert.text == "The Drive stopped. Recording continues on the Device; the Gap is Repaired when the Drive comes back.")
    }

    @Test("Drive only never rejoins the Drive mid-Take, so the stand-in alert has no 'Still not found.' (#550)")
    func driveOnlyNoStillNotFound() throws {
        let alert = try #require(DestinationAlert.make(
            copies: takeCopies(driveOnly: true, device: .standingIn, drive: .interrupted), checkedAndNotFound: true))

        #expect(alert.action == nil)
        #expect(alert.text == "The Drive stopped. Recording to this iPhone for the rest of the Take; the audio moves to the Drive after it.")
    }

    @Test("Drive only on a Mac: both alerts say 'this Mac' (#550)")
    func driveOnlyDeviceWord() throws {
        let noDrive = try #require(DestinationAlert.make(
            copies: takeCopies(driveOnly: true, device: .recording, drive: .missing), deviceWord: "Mac"))
        #expect(noDrive.text == "No Drive: recording to this Mac; it moves to the Drive when one is connected.")

        let stopped = try #require(DestinationAlert.make(
            copies: takeCopies(driveOnly: true, device: .standingIn, drive: .interrupted), deviceWord: "Mac"))
        #expect(stopped.text == "The Drive stopped. Recording to this Mac for the rest of the Take; the audio moves to the Drive after it.")
    }

    @Test("Losing the Device Copy, or both, is critical too")
    func deviceOrBothLost() throws {
        let device = try #require(DestinationAlert.make(copies: takeCopies(device: .interrupted, drive: .recording)))
        #expect(device.id == "device-stopped" && device.tone == .critical)
        #expect(device.text == "The Device stopped writing. Recording continues on the Drive.")

        let both = try #require(DestinationAlert.make(copies: takeCopies(device: .interrupted, drive: .interrupted)))
        #expect(both.id == "both-stopped" && both.tone == .critical)
        #expect(both.text == "Both Copies stopped writing.")
    }

    @Test("Nothing when both Copies are recording, or when no Take is running")
    func quietWhenFine() {
        #expect(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .recording)) == nil)
        #expect(DestinationAlert.make(copies: takeCopies(running: false, device: .interrupted, drive: .interrupted)) == nil)
        #expect(DestinationAlert.make(copies: takeCopies(running: false, device: .recording, drive: .missing)) == nil)
    }
}

/// The Drive coming back during a Take.
@Suite("Drive rejoin notice")
struct DriveRejoinNoticeTests {
    @Test("The Drive stopped alert offers Check Drive, and says so when the check found nothing")
    func checkDriveAction() throws {
        let stopped = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .interrupted)))
        #expect(stopped.action == .checkDrive)
        #expect(stopped.text.hasPrefix("The Drive stopped."))

        let again = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .interrupted), checkedAndNotFound: true))
        #expect(again.text.hasPrefix("Still not found. The Drive stopped."))
        #expect(again.action == .checkDrive)
    }

    @Test("The notice appears when the Drive comes back during a Take, stays until the Take ends, and is not made up for a Drive that was never lost")
    func rejoinNotice() throws {
        var notice = DriveRejoinNotice()
        notice.update(copies: takeCopies(device: .recording, drive: .recording))
        #expect(notice.alert == nil, "never lost")

        notice.update(copies: takeCopies(device: .recording, drive: .interrupted))
        #expect(notice.alert == nil, "still lost")

        notice.update(copies: takeCopies(device: .recording, drive: .recording))
        let alert = try #require(notice.alert)
        #expect(alert.id == "drive-back" && alert.tone == .ok && alert.priority == .destination)
        #expect(alert.text == "The Drive is back. The Gap will be Repaired after the Take.")

        notice.update(copies: takeCopies(device: .recording, drive: .recording))
        #expect(notice.alert != nil, "stays while the Take runs")

        notice.update(copies: takeCopies(running: false, device: .recording, drive: .recording))
        #expect(notice.alert == nil, "gone once the Take ends")
    }

    @Test("A Drive lost in one Take doesn't make the next Take say it's back")
    func rejoinResetsAtTakeEnd() {
        var notice = DriveRejoinNotice()
        notice.update(copies: takeCopies(device: .recording, drive: .interrupted))
        notice.update(copies: takeCopies(running: false, device: .complete, drive: .repaired))
        notice.update(copies: takeCopies(device: .recording, drive: .recording))
        #expect(notice.alert == nil)
    }
}
