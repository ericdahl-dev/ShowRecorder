import Testing
@testable import ShowRecorder

struct AppVersionTests {
    @Test("A release build says its version and build: ShowRecorder 1.1.6 (34.1) (#697)")
    func releaseLine() {
        let line = AppVersion.line(version: "1.1.6", build: "34.1", isDebug: false, commit: nil)
        #expect(line == "ShowRecorder 1.1.6 (34.1)")
    }

    @Test("A release build leaves out the commit even when one was stamped (#697)")
    func releaseIgnoresCommit() {
        let line = AppVersion.line(version: "1.1.6", build: "34.1", isDebug: false, commit: "abc1234")
        #expect(line == "ShowRecorder 1.1.6 (34.1)")
    }

    @Test("A Debug build says so and names its commit, since every Debug build reads 0.1.0 (1) (#697)")
    func debugLine() {
        let line = AppVersion.line(version: "0.1.0", build: "1", isDebug: true, commit: "abc1234")
        #expect(line == "ShowRecorder 0.1.0 (1) · Debug · abc1234")
    }

    @Test("A Debug build with no stamped commit still says Debug (#697)")
    func debugWithoutCommit() {
        #expect(AppVersion.line(version: "0.1.0", build: "1", isDebug: true, commit: nil) == "ShowRecorder 0.1.0 (1) · Debug")
        #expect(AppVersion.line(version: "0.1.0", build: "1", isDebug: true, commit: "") == "ShowRecorder 0.1.0 (1) · Debug")
    }

    @Test("A missing version or build reads as a question mark, not a blank (#697)")
    func missingValues() {
        #expect(AppVersion.line(version: nil, build: nil, isDebug: false, commit: nil) == "ShowRecorder ? (?)")
    }
}
