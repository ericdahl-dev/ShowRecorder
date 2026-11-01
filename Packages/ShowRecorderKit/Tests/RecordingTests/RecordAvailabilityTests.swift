@testable import Recording
import Testing

/// Why the Record button is dimmed, and what to offer.
@Suite("Record availability")
struct RecordAvailabilityTests {
    func block(ready: Bool = false, recording: Bool = false, micDenied: Bool = false, getReadyFailed: Bool = false, idle: Bool = false, devices: Bool = true) -> RecordAvailability.Block? {
        RecordAvailability.block(isReady: ready, isRecording: recording, micDenied: micDenied, getReadyFailed: getReadyFailed, stoodDownForIdle: idle, hasInputs: devices)
    }

    @Test("Ready or recording: nothing blocks Record")
    func nothingWhenReady() {
        #expect(block(ready: true) == nil)
        #expect(block(ready: true, recording: true) == nil)
    }

    @Test("Microphone access off: say so and offer the system Settings")
    func microphoneDenied() throws {
        let reason = try #require(block(micDenied: true))
        #expect(reason.text == "Microphone access is off. Allow it in Settings.")
        #expect(reason.action == .openSystemSettings)
    }

    @Test("An input that failed to start offers Get ready again")
    func getReadyFailed() throws {
        let reason = try #require(block(getReadyFailed: true))
        #expect(reason.text == "The input didn't start.")
        #expect(reason.action == .getReady)
    }

    @Test("Stood down for sitting idle: say how long and offer Get ready")
    func idle() throws {
        let reason = try #require(block(idle: true))
        #expect(reason.text == "Stood down after 30 minutes idle.")
        #expect(reason.action == .getReady)
    }

    @Test("No input to choose, or none chosen yet: say which, with no button")
    func noInput() throws {
        #expect(try #require(block(devices: false)).text == "No audio interface. Plug in the Mixer's USB cable.")
        #expect(try #require(block(devices: false)).action == nil)
        #expect(try #require(block()).text == "Choose the audio interface in Settings.")
        #expect(try #require(block()).action == nil)
    }

    @Test("The most useful reason wins: microphone denied before a failed get-ready before idle")
    func order() throws {
        #expect(try #require(block(micDenied: true, getReadyFailed: true, idle: true)).action == .openSystemSettings)
        #expect(try #require(block(getReadyFailed: true, idle: true)).text == "The input didn't start.")
    }
}
