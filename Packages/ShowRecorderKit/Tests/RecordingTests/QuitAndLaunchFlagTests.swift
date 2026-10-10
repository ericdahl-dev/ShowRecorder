@testable import Recording
import Testing

@Suite("Quit and launch flags")
struct QuitAndLaunchFlagTests {
    @Test("Quitting the Mac app during a Take asks first, like closing the window; otherwise it just quits")
    func quitAsksDuringATake() {
        #expect(RecorderLifecycle.quitRequested(isRecording: true) == .askToStop)
        #expect(RecorderLifecycle.quitRequested(isRecording: false) == .quit)
    }

    @Test("Screenshot launch flags work in a Debug build only")
    func flagsOnlyInDebug() {
        let arguments = ["ShowRecorder", "-demoRecord", "-demoSignal"]
        #expect(LaunchFlags.isSet("-demoRecord", in: arguments, isDebugBuild: true))
        #expect(!LaunchFlags.isSet("-demoRecord", in: arguments, isDebugBuild: false))
        #expect(!LaunchFlags.isSet("-showList", in: arguments, isDebugBuild: true), "not given")
    }
}
