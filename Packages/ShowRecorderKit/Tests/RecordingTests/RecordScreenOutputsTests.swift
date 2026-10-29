import Destinations
import Foundation
import MixerLink
@testable import Recording
import TakeFile
import Testing
import WatchRemote

/// What the record screen shows besides its alerts, from the same snapshot (#552): the chips, the record block, the
/// header text, the Copy summary, the watch status and VoiceOver announcements.
@Suite("Record screen outputs")
struct RecordScreenOutputsTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let anHour: Int64 = 18 * 48_000 * 3 * 3_600
    private let missingDrive = DriveStatus.unavailable(.notConnected(name: "SSD"))

    /// A Take that is running on the Ready 18-channel Mixer, with room on the Device, the Drive gone and the Mixer Link lost.
    private var takeWithNoDriveAndLostLink: RecordScreenSnapshot {
        var s = RecordScreenSnapshot()
        s.isReady = true
        s.isRecording = true
        s.takeBusy = true
        s.hasInputs = true
        s.usbChannelCount = 18
        s.deviceAvailableBytes = anHour
        s.driveStatus = missingDrive
        s.mixerState = .down(.noReply(host: "10.0.0.9"))
        s.mixerDown = true
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        s.takeStartedAt = t0
        s.takeNumber = 3
        s.showName = "2026-10-06 Show"
        return s
    }

    @Test("The chips are the Device and Drive time left and the Mixer Link, from the snapshot")
    func chips() throws {
        var s = RecordScreenSnapshot()
        s.usbChannelCount = 18
        s.deviceAvailableBytes = anHour
        s.driveStatus = missingDrive
        s.mixerState = .notLinked
        let chips = Dictionary(uniqueKeysWithValues: RecordScreenState().chips(s).map { ($0.kind, $0) })
        #expect(chips[.device]?.text.hasPrefix("Device") == true)
        #expect(chips[.drive]?.shortText == "Drive missing")
        #expect(chips[.mixer] != nil)
    }

    @Test("A Take with no Drive and a Mixer Link loss: the Drive and Mixer chips, the alert and the watch problems all say so")
    func noDriveAndLostLink() throws {
        let s = takeWithNoDriveAndLostLink
        let state = RecordScreenState()

        let chips = Dictionary(uniqueKeysWithValues: state.chips(s).map { ($0.kind, $0) })
        #expect(chips[.drive]?.state == .failed)
        #expect(chips[.mixer]?.text == "Mixer down")
        #expect(chips[.mixer]?.state == .attention)

        #expect(state.alerts(s).ordered.map(\.id) == ["drive-stopped"])

        let watch = state.watchStatus(s, now: t0)
        #expect(watch.problems == [.copyStopped, .mixerLinkLost])
        #expect(watch.state == .recording(startedAt: t0, takeTitle: "Take 03", markerCount: 0))
    }

    @Test("The watch reports low space between Takes, and during a Take a stopped or full Copy (whose chip is already failed) and Dropouts")
    func watchProblems() {
        var s = RecordScreenSnapshot()
        s.isReady = true
        s.usbChannelCount = 18
        s.deviceAvailableBytes = 60_000
        s.driveStatus = .available(Drive(folder: URL(filePath: "/Volumes/SSD"), name: "SSD", availableBytes: 60_000))
        s.dropoutCount = 4
        let idle = RecordScreenState().watchStatus(s, now: t0)
        #expect(idle.state == .ready)
        #expect(idle.problems == [.deviceLowSpace, .driveLowSpace])

        s.isRecording = true
        s.takeStartedAt = t0
        s.copies = takeCopies(device: .full, drive: .interrupted)
        let recording = RecordScreenState().watchStatus(s, now: t0)
        #expect(recording.problems == [.copyStopped, .copyFull, .gapOrDropout])
    }

    @Test("Not ready and not recording, the watch says so")
    func watchNotReady() {
        #expect(RecordScreenState().watchStatus(RecordScreenSnapshot(), now: t0).state == .notReady)
    }

    @Test("Why Record is dimmed: the microphone, an input that didn't start, being idle, no interface, or none chosen")
    func recordBlock() {
        var s = RecordScreenSnapshot()
        s.hasInputs = true
        #expect(RecordScreenState().recordBlock(s)?.text == "Choose the audio interface in Settings.")
        s.hasInputs = false
        #expect(RecordScreenState().recordBlock(s)?.text == "No audio interface. Plug in the Mixer's USB cable.")
        s.stoodDownForIdle = true
        #expect(RecordScreenState().recordBlock(s)?.action == .getReady)
        s.getReadyError = "The input didn't start."
        #expect(RecordScreenState().recordBlock(s)?.text == "The input didn't start.")
        s.micDenied = true
        #expect(RecordScreenState().recordBlock(s)?.action == .openSystemSettings)
        s.isReady = true
        #expect(RecordScreenState().recordBlock(s) == nil)
    }

    @Test("The header names the Ready interface and its channels, or says what to do; the compact one is just the name")
    func inputSummary() {
        var s = RecordScreenSnapshot()
        #expect(RecordScreenState().inputSummary(s) == "No audio interface. Plug in the Mixer's USB cable.")
        #expect(RecordScreenState().compactInputSummary(s) == "No audio interface")

        s.isReady = true
        s.usbChannelCount = 18
        #expect(RecordScreenState().inputSummary(s) == "Audio interface · 18 USB Channels")
        s.readyDeviceName = "XR18"
        #expect(RecordScreenState().inputSummary(s) == "XR18 · 18 USB Channels")
        #expect(RecordScreenState().compactInputSummary(s) == "XR18")
        s.usbChannelCount = 1
        #expect(RecordScreenState().inputSummary(s) == "XR18 · 1 USB Channel")
    }

    @Test("The Take's title and the Show summary: a hint before the first Show, then the Show and its Take")
    func showSummary() {
        var s = RecordScreenSnapshot()
        #expect(RecordScreenState().takeTitle(s) == "Take 00")
        #expect(RecordScreenState().showSummary(s) == "Press record to start a Show")
        s.showName = "2026-10-06 Show"
        s.takeNumber = 2
        #expect(RecordScreenState().showSummary(s) == "2026-10-06 Show · Take 02")
    }

    @Test("VoiceOver hears of a new alert, clip and Dropout once, and nothing on the first look")
    func announcements() {
        var state = RecordScreenState()
        var s = RecordScreenSnapshot()
        s.isReady = true
        #expect(state.announcements(s).isEmpty)

        s.interruptionNotice = "A call interrupted the input."
        s.clippedChannels = [2]
        s.dropoutCount = 1
        #expect(state.announcements(s) == ["A call interrupted the input.", "Clip on USB Channel 3", "Dropout"])
        #expect(state.announcements(s).isEmpty)

        s.interruptionNotice = nil
        #expect(state.announcements(s).isEmpty)
        s.interruptionNotice = "A call interrupted the input."
        #expect(state.announcements(s) == ["A call interrupted the input."])
    }

    @Test("A swiped alert is not announced again, and a fade does not announce")
    func announcementsSkipSwiped() throws {
        var state = RecordScreenState()
        var s = RecordScreenSnapshot()
        s.isReady = true
        _ = state.announcements(s)
        s.interruptionNotice = "A call interrupted the input."
        _ = state.announcements(s)
        state.swipe(try #require(state.alerts(s).top))
        #expect(state.announcements(s).isEmpty)
    }
}
