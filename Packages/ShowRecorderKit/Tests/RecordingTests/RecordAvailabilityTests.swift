@testable import Recording
import Testing

/// Why the Record button is dimmed, and what to offer.
@Suite("Record availability")
struct RecordAvailabilityTests {
    func block(armed: Bool = false, recording: Bool = false, micDenied: Bool = false, armFailed: Bool = false, idle: Bool = false, devices: Bool = true) -> RecordAvailability.Block? {
        RecordAvailability.block(isArmed: armed, isRecording: recording, micDenied: micDenied, armFailed: armFailed, disarmedForIdle: idle, hasInputs: devices)
    }

    @Test("Armed or recording: nothing blocks Record")
    func nothingWhenArmed() {
        #expect(block(armed: true) == nil)
        #expect(block(armed: true, recording: true) == nil)
    }

    @Test("Microphone access off: say so and offer the system Settings")
    func microphoneDenied() throws {
        let block = try #require(block(micDenied: true))
        #expect(block.text == "Microphone access is off. Allow it in Settings.")
        #expect(block.action == .openSystemSettings)
    }

    @Test("An input that failed to start offers Arm again")
    func armFailed() throws {
        let block = try #require(block(armFailed: true))
        #expect(block.text == "The input didn't start.")
        #expect(block.action == .arm)
    }

    @Test("Disarmed for sitting idle: say how long and offer Arm")
    func idle() throws {
        let block = try #require(block(idle: true))
        #expect(block.text == "Disarmed after 30 minutes idle.")
        #expect(block.action == .arm)
    }

    @Test("No input to choose, or none chosen yet: say which, with no button")
    func noInput() throws {
        #expect(try #require(block(devices: false)).text == "No audio input. Plug in your interface.")
        #expect(try #require(block(devices: false)).action == nil)
        #expect(try #require(block()).text == "Choose an input in Settings.")
        #expect(try #require(block()).action == nil)
    }

    @Test("The most useful reason wins: microphone denied before a failed arm before idle")
    func order() throws {
        #expect(try #require(block(micDenied: true, armFailed: true, idle: true)).action == .openSystemSettings)
        #expect(try #require(block(armFailed: true, idle: true)).text == "The input didn't start.")
    }
}
