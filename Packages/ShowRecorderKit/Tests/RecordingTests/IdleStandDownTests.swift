import Foundation
import Recording
import Testing

@Suite("Auto stand-down")
struct IdleStandDownTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func later(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// Asks whether to stand down `minutes` after the start. (`#expect` can't call a mutating method itself.)
    func standDown(_ idle: inout IdleStandDown, at minutes: Double, recording: Bool = false) -> Bool {
        idle.shouldStandDown(at: later(minutes), isRecording: recording)
    }

    @Test("With the screen in front it never stands down, however long")
    func neverWhileInFront() {
        var idle = IdleStandDown()
        #expect(!standDown(&idle, at: 0))
        #expect(!standDown(&idle, at: 600))
    }

    @Test("It stands down once the screen has been locked for 30 minutes, not before")
    func thirtyMinutes() {
        var idle = IdleStandDown()
        idle.becameIdle(at: start)
        #expect(IdleStandDown.limit == 30 * 60)
        #expect(!standDown(&idle, at: 0))
        #expect(!standDown(&idle, at: 29.99))
        #expect(standDown(&idle, at: 30))
        #expect(standDown(&idle, at: 45))
    }

    @Test("Coming back to the screen cancels the wait; locking again starts a new one")
    func comingBackResets() {
        var idle = IdleStandDown()
        idle.becameIdle(at: start)
        idle.becameActive()
        #expect(!standDown(&idle, at: 60))

        idle.becameIdle(at: later(60))
        #expect(!standDown(&idle, at: 89))
        #expect(standDown(&idle, at: 90))
    }

    @Test("It never stands down during a Take, and the wait starts again when the Take ends")
    func neverDuringATake() {
        var idle = IdleStandDown()
        idle.becameIdle(at: start)
        // A Take is running for two hours of locked screen.
        for minutes in stride(from: 1.0, through: 120.0, by: 1.0) {
            #expect(!standDown(&idle, at: minutes, recording: true))
        }
        // It ended at 2:00; 30 minutes from then, not from the lock.
        #expect(!standDown(&idle, at: 121))
        #expect(!standDown(&idle, at: 149))
        #expect(standDown(&idle, at: 150))
    }

    @Test("Locking twice in a row keeps the first time")
    func lockingTwice() {
        var idle = IdleStandDown()
        idle.becameIdle(at: start)
        idle.becameIdle(at: later(20))
        #expect(standDown(&idle, at: 30))
    }
}
