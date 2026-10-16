import Recording
import Testing

@Suite("Async Stop availability")
struct AsyncStopAvailabilityTests {
    @Test("A Debug build uses the asynchronous Stop")
    func debugBuild() {
        #expect(AsyncStopAvailability.isAvailable(isDebugBuild: true))
    }

    @Test("Release builds, TestFlight and the App Store alike, do not")
    func releaseBuild() {
        #expect(!AsyncStopAvailability.isAvailable(isDebugBuild: false))
    }

    @Test("This build follows its configuration")
    func thisBuild() {
        #if DEBUG
        #expect(AsyncStopAvailability.isAvailableInThisBuild)
        #else
        #expect(!AsyncStopAvailability.isAvailableInThisBuild)
        #endif
    }
}
