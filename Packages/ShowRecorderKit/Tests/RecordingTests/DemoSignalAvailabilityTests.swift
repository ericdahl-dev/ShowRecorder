import Recording
import Testing

@Suite("Demo signal availability")
struct DemoSignalAvailabilityTests {
    @Test("Debug builds offer the Demo signal")
    func debugBuild() {
        #expect(DemoSignalAvailability.isAvailable(isDebugBuild: true, receiptFileName: nil))
        #expect(DemoSignalAvailability.isAvailable(isDebugBuild: true, receiptFileName: "receipt"))
    }

    @Test("TestFlight builds offer it")
    func testFlightBuild() {
        #expect(DemoSignalAvailability.isAvailable(isDebugBuild: false, receiptFileName: "sandboxReceipt"))
    }

    @Test("The App Store build and a build with no receipt do not")
    func appStoreBuild() {
        #expect(!DemoSignalAvailability.isAvailable(isDebugBuild: false, receiptFileName: "receipt"))
        #expect(!DemoSignalAvailability.isAvailable(isDebugBuild: false, receiptFileName: nil))
    }
}
