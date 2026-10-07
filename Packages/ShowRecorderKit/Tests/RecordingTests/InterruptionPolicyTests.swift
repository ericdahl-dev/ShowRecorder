import Recording
import Testing

@Suite("Audio interruption policy")
struct InterruptionPolicyTests {
    @Test("Going to the background or locking the screen never touches input or the Take")
    func backgroundDoesNothing() {
        var policy = InterruptionPolicy()
        let response = policy.handle(.movedToBackground, isRecording: true)
        #expect(response.action == .none)
        #expect(!policy.isInputStopped)
        #expect(policy.notice == nil)
    }

    @Test("An interruption marks input stopped and tells the operator the Take is still open")
    func interruptionBeganWhileRecording() {
        var policy = InterruptionPolicy()
        let response = policy.handle(.interruptionBegan, isRecording: true)
        #expect(response.action == .none)
        #expect(policy.isInputStopped)
        #expect(policy.notice?.contains("Take is still open") == true)
        #expect(response.log != nil)
    }

    @Test("When the interruption ends with shouldResume, input restarts")
    func endedWithResume() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: true)
        #expect(policy.handle(.interruptionEnded(shouldResume: true), isRecording: true).action == .restartInput)
    }

    @Test("During a Take, input restarts even without shouldResume, so the rest of the Show isn't lost")
    func endedWithoutResumeWhileRecording() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: true)
        #expect(policy.handle(.interruptionEnded(shouldResume: false), isRecording: true).action == .restartInput)
    }

    @Test("Armed without a Take, input waits for the app to come forward when the system says not to resume")
    func endedWithoutResumeWhileArmed() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: false)
        #expect(policy.handle(.interruptionEnded(shouldResume: false), isRecording: false).action == .none)
        #expect(policy.isInputStopped)
        #expect(policy.handle(.becameActive, isRecording: false).action == .restartInput)
    }

    @Test("Becoming active with input running does nothing")
    func activeWithInputRunning() {
        var policy = InterruptionPolicy()
        #expect(policy.handle(.becameActive, isRecording: true).action == .none)
    }

    @Test("A failed restart keeps input stopped, says so, and retries when the app becomes active")
    func failedRestartRetriesOnActive() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: true)
        _ = policy.handle(.interruptionEnded(shouldResume: true), isRecording: true)
        let failed = policy.handle(.restartFailed("session busy"), isRecording: true)
        #expect(failed.action == .none)
        #expect(failed.log?.contains("session busy") == true)
        #expect(policy.isInputStopped)
        #expect(policy.notice?.contains("session busy") == true)
        #expect(policy.handle(.becameActive, isRecording: true).action == .restartInput)
    }

    @Test("After a restart during a Take, the notice stays to say audio from the interruption is missing")
    func restartedWhileRecordingKeepsNotice() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: true)
        _ = policy.handle(.interruptionEnded(shouldResume: true), isRecording: true)
        let response = policy.handle(.restarted, isRecording: true)
        #expect(response.action == .none)
        #expect(!policy.isInputStopped)
        #expect(policy.notice?.contains("missing") == true)
    }

    @Test("After a restart while only Armed, the notice clears")
    func restartedWhileArmedClearsNotice() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: false)
        _ = policy.handle(.interruptionEnded(shouldResume: true), isRecording: false)
        _ = policy.handle(.restarted, isRecording: false)
        #expect(policy.notice == nil)
    }

    @Test("Starting the next Take clears the leftover notice once input is running")
    func takeStartedClearsNotice() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: true)
        _ = policy.handle(.restarted, isRecording: true)
        _ = policy.handle(.takeStarted, isRecording: true)
        #expect(policy.notice == nil)
    }

    @Test("Starting a Take while input is stopped keeps the notice")
    func takeStartedWhileStoppedKeepsNotice() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.interruptionBegan, isRecording: false)
        _ = policy.handle(.takeStarted, isRecording: true)
        #expect(policy.notice != nil)
    }

    @Test("A media services reset replaces the device and marks input stopped until it is back")
    func mediaServicesReset() {
        var policy = InterruptionPolicy()
        let response = policy.handle(.mediaServicesReset, isRecording: true)
        #expect(response.action == .replaceDevice)
        #expect(policy.isInputStopped)
        #expect(response.log != nil)
    }

    @Test("If replacing the device after a reset fails, becoming active tries a replacement again")
    func failedReplacementRetriesReplacement() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.mediaServicesReset, isRecording: true)
        _ = policy.handle(.restartFailed("no input"), isRecording: true)
        #expect(policy.handle(.becameActive, isRecording: true).action == .replaceDevice)
    }

    @Test("A media services reset that couldn't keep the Take says the Take ended")
    func mediaResetEndedTake() {
        var policy = InterruptionPolicy()
        _ = policy.handle(.mediaServicesReset, isRecording: true)
        _ = policy.handle(.takeEndedByReset, isRecording: false)
        #expect(!policy.isInputStopped)
        #expect(policy.notice?.contains("ended") == true)
    }
}
