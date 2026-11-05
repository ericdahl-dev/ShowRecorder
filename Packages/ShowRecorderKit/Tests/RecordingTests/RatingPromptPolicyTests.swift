import Destinations
import Foundation
@testable import Recording
import Testing

/// When the app asks for an App Store rating: after the operator's second clean Take and later ones, once the screen is
/// idle, at most once per app version and never more than three times.
@Suite("Rating prompt policy")
struct RatingPromptPolicyTests {
    /// Both Copies written whole.
    static let bothComplete = TakeCopies(isRunning: false) { _ in .complete }

    static func cleanTake(_ number: Int) -> (TakeEnd, Int, TakeCopies) {
        (TakeEnd(take: number, reason: .stopped), 0, bothComplete)
    }

    static func end(_ policy: inout RatingPromptPolicy, _ take: (TakeEnd, Int, TakeCopies)) {
        policy.takeEnded(take.0, dropouts: take.1, copies: take.2)
    }

    @Test("The second clean Take asks; the first does not")
    func secondCleanTake() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
        Self.end(&policy, Self.cleanTake(2))
        #expect(policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }

    @Test("A Take the recorder ended, not the operator, is not clean", arguments: [
        TakeEnd.Reason.outOfSpace, .noDestination, .inputChanged,
    ])
    func endedByTheRecorder(reason: TakeEnd.Reason) {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, (TakeEnd(take: 2, reason: reason), 0, Self.bothComplete))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }

    @Test("A Take with a Dropout is not clean")
    func dropout() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, (TakeEnd(take: 2, reason: .stopped), 1, Self.bothComplete))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }

    @Test("A Take whose Drive Copy wasn't written whole is not clean", arguments: [
        CopyState.hasGaps, .repaired, .repairFailed,
    ])
    func driveCopyNotWhole(drive: CopyState) {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        let copies = TakeCopies(isRunning: false) { $0 == .drive ? drive : .complete }
        Self.end(&policy, (TakeEnd(take: 2, reason: .stopped), 0, copies))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }

    @Test("A Drive only Take whose Device stood in for a lost Drive is not clean", arguments: [CopyState.moved, .standInKept])
    func standIn(device: CopyState) {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        let copies = TakeCopies(isRunning: false, isDriveOnly: true) { $0 == .device ? device : .complete }
        Self.end(&policy, (TakeEnd(take: 2, reason: .stopped), 0, copies))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }

    @Test("It asks only after a clean Take: not after a Take that went wrong, even with two clean ones before it")
    func onlyAfterACleanTake() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, Self.cleanTake(2))
        Self.end(&policy, (TakeEnd(take: 3, reason: .stopped), 2, Self.bothComplete))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
        Self.end(&policy, Self.cleanTake(4))
        #expect(policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }

    @Test("Never while a Take is running or finishing")
    func neverDuringATake() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, Self.cleanTake(2))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: true))
    }

    @Test("At most once per app version: asked in 1.2.3, not again until 1.2.4")
    func oncePerVersion() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, Self.cleanTake(2))
        policy.asked(appVersion: "1.2.3")
        Self.end(&policy, Self.cleanTake(3))
        #expect(!policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
        #expect(policy.shouldAsk(appVersion: "1.2.4", isRecording: false))
    }

    @Test("A new version asks only after a new clean Take, not on the Take asked about before")
    func newVersionNeedsANewTake() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, Self.cleanTake(2))
        policy.asked(appVersion: "1.2.3")
        #expect(!policy.shouldAsk(appVersion: "1.2.4", isRecording: false))
    }

    @Test("Never again once asked three times, whatever the version")
    func threeAsksAtMost() {
        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        for (index, version) in ["1.2.3", "1.2.4", "1.2.5"].enumerated() {
            Self.end(&policy, Self.cleanTake(index + 2))
            #expect(policy.shouldAsk(appVersion: version, isRecording: false))
            policy.asked(appVersion: version)
        }
        Self.end(&policy, Self.cleanTake(5))
        #expect(!policy.shouldAsk(appVersion: "1.3.0", isRecording: false))
    }

    @Test("The counts survive a relaunch: saved to and loaded from UserDefaults")
    func persists() throws {
        let suite = "RatingPromptPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RatingPromptPolicy.load(from: defaults) == RatingPromptPolicy())

        var policy = RatingPromptPolicy()
        Self.end(&policy, Self.cleanTake(1))
        Self.end(&policy, Self.cleanTake(2))
        policy.asked(appVersion: "1.2.3")
        Self.end(&policy, Self.cleanTake(3))
        policy.save(to: defaults)
        #expect(RatingPromptPolicy.load(from: defaults) == policy)
    }

    @Test("A Take recorded to the Device alone, with no Drive Copy, is clean")
    func deviceOnly() {
        var policy = RatingPromptPolicy()
        let copies = TakeCopies(isRunning: false, isDeviceOnly: true) { $0 == .device ? .complete : .missing }
        Self.end(&policy, (TakeEnd(take: 1, reason: .stopped), 0, copies))
        Self.end(&policy, (TakeEnd(take: 2, reason: .stopped), 0, copies))
        #expect(policy.shouldAsk(appVersion: "1.2.3", isRecording: false))
    }
}
