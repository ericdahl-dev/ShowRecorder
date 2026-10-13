@testable import Recording
import Testing


/// What the record screen says about the Copies of a running Take.
@Suite("Destination alert")
struct DestinationAlertTests {
    @Test("Today's call with two running words says the same as one with the Take's Copies (until the screen moves over)")
    func adapterSaysTheSame() {
        let words: [CopyStatus] = [.recording, .interrupted, .missing]
        for recording in [true, false] {
            for device in words {
                for drive in words {
                    #expect(DestinationAlert.make(isRecording: recording, device: device, drive: drive)
                            == DestinationAlert.make(copies: takeCopies(running: recording, device: CopyState(device), drive: CopyState(drive))))
                }
            }
        }
    }

    @Test("A Drive that stops mid-Take is critical, with its own id, so it is not mistaken for the quiet 'No Drive' notice")
    func driveStoppedIsCritical() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .interrupted)))

        #expect(alert.id == "drive-stopped")
        #expect(alert.tone == .critical)
        #expect(alert.priority == .destination)
        #expect(alert.text.contains("Drive stopped"))
        #expect(alert.text.contains("Gap"))
    }

    @Test("No Drive at the start of a Take is the quiet warning, not the critical one")
    func noDriveIsAWarning() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .missing)))

        #expect(alert.id == "no-drive")
        #expect(alert.tone == .warning)
        #expect(alert.text == "No Drive. Recording to the Device only.")
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

    @Test("The rejoin notice fed the Drive's running word says the same as one fed the Take's Copies (until the screen moves over)")
    func rejoinAdapterSaysTheSame() {
        var old = DriveRejoinNotice(), new = DriveRejoinNotice()
        let steps: [(Bool, CopyStatus)] = [(true, .recording), (true, .interrupted), (true, .missing), (true, .recording),
                                          (true, .recording), (false, .recording), (true, .interrupted), (false, .interrupted)]
        for (recording, drive) in steps {
            old.update(isRecording: recording, drive: drive)
            new.update(copies: takeCopies(running: recording, device: .recording, drive: CopyState(drive)))
            #expect(old.alert == new.alert)
        }
    }
}
