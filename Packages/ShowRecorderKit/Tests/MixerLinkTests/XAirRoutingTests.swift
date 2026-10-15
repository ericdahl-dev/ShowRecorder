@testable import MixerLink
import Testing

/// What an X-Air's USB Channel carries (#20), from `/routing/usb/NN` = [source, tap], as read on an XR18 (firmware
/// 1.26): source 0-15 Ch01-16, 16-17 AuxL/R, 18-25 FX, 26-31 Bus, 32-35 Send, 36-37 main L/R.
@Suite("X-Air USB routing")
struct XAirRoutingTests {
    @Test("Source 0-15 is input channel 1-16, 16-17 the aux return, anything else no channel")
    func targets() {
        #expect(XAirRouting.target(ofSource: 0) == .channel(1))
        #expect(XAirRouting.target(ofSource: 15) == .channel(16))
        #expect(XAirRouting.target(ofSource: 16) == .auxReturn)
        #expect(XAirRouting.target(ofSource: 17) == .auxReturn)
        for other in [18, 25, 26, 31, 32, 35, 36, 37, -1, 38] {
            #expect(XAirRouting.target(ofSource: other) == nil, "source \(other)")
        }
    }
}
