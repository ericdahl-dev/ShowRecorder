import Foundation
import Recording
import Testing

@Suite("Auto-disarm")
struct IdleDisarmTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func later(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// Asks whether to disarm `minutes` after the start. (`#expect` can't call a mutating method itself.)
    func disarm(_ idle: inout IdleDisarm, at minutes: Double, recording: Bool = false) -> Bool {
        idle.shouldDisarm(at: later(minutes), isRecording: recording)
    }

    @Test("With the screen in front it never disarms, however long")
    func neverWhileInFront() {
        var idle = IdleDisarm()
        #expect(!disarm(&idle, at: 0))
        #expect(!disarm(&idle, at: 600))
    }

    @Test("It disarms once the screen has been locked for 30 minutes, not before")
    func thirtyMinutes() {
        var idle = IdleDisarm()
        idle.becameIdle(at: start)
        #expect(IdleDisarm.limit == 30 * 60)
        #expect(!disarm(&idle, at: 0))
        #expect(!disarm(&idle, at: 29.99))
        #expect(disarm(&idle, at: 30))
        #expect(disarm(&idle, at: 45))
    }

    @Test("Coming back to the screen cancels the wait; locking again starts a new one")
    func comingBackResets() {
        var idle = IdleDisarm()
        idle.becameIdle(at: start)
        idle.becameActive()
        #expect(!disarm(&idle, at: 60))

        idle.becameIdle(at: later(60))
        #expect(!disarm(&idle, at: 89))
        #expect(disarm(&idle, at: 90))
    }

    @Test("It never disarms during a Take, and the wait starts again when the Take ends")
    func neverDuringATake() {
        var idle = IdleDisarm()
        idle.becameIdle(at: start)
        // A Take is running for two hours of locked screen.
        for minutes in stride(from: 1.0, through: 120.0, by: 1.0) {
            #expect(!disarm(&idle, at: minutes, recording: true))
        }
        // It ended at 2:00; 30 minutes from then, not from the lock.
        #expect(!disarm(&idle, at: 121))
        #expect(!disarm(&idle, at: 149))
        #expect(disarm(&idle, at: 150))
    }

    @Test("Locking twice in a row keeps the first time")
    func lockingTwice() {
        var idle = IdleDisarm()
        idle.becameIdle(at: start)
        idle.becameIdle(at: later(20))
        #expect(disarm(&idle, at: 30))
    }
}
