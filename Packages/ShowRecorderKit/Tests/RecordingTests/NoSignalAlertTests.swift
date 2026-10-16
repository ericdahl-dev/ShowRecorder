import Recording
import Testing

@Suite("No-signal banner (#778)")
struct NoSignalAlertTests {
    @Test("A silent Take gets a warning in the input slot, with no button")
    func silentTake() throws {
        let alert = try #require(NoSignalAlert.make(isSilent: true, isRecording: true))
        #expect(alert.id == "noSignal")
        #expect(alert.priority == .input)
        #expect(alert.tone == .warning)
        #expect(alert.action == nil)
        #expect(alert.text == "No signal on any channel for 10 seconds. Check the mixer's USB routing, the cable and any muted microphone. The Take is still recording.")
    }

    @Test("No warning when there is signal")
    func signal() {
        #expect(NoSignalAlert.make(isSilent: false, isRecording: true) == nil)
    }

    @Test("No warning once the Take has ended")
    func notRecording() {
        #expect(NoSignalAlert.make(isSilent: true, isRecording: false) == nil)
    }

    @Test("The words follow the detector's wait")
    func wordsMatchTheWait() {
        let seconds = Int(NoSignalDetector.defaultWaitSeconds)
        #expect(NoSignalAlert.make(isSilent: true, isRecording: true)?.text.contains("\(seconds) seconds") == true)
    }
}
