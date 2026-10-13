@testable import Recording
import Testing

/// When an iOS route change means a new input (#233): only then may a running Take move to it. Moving restarts the
/// input, which costs audio, so a change of output alone must never count.
@Suite("Input route")
struct InputRouteTests {
    static let builtIn = InputRoute.Port(uid: "Built-In Microphone", isBuiltIn: true, channelCount: 1)

    @Test("The built-in mic stays the input while the output moves (receiver to AirPods, AirPods into the case and back, the record press): not a new input, even when its channel count changes")
    func outputOnlyChanges() {
        let receiver = InputRoute(ports: [Self.builtIn])
        var a2dp = Self.builtIn
        a2dp.channelCount = 2
        let airPods = InputRoute(ports: [a2dp])
        #expect(!InputRoute.isNewInput(from: receiver, to: airPods))
        #expect(!InputRoute.isNewInput(from: airPods, to: receiver))
        #expect(!InputRoute.isNewInput(from: receiver, to: receiver))
    }

    static let xr18 = InputRoute.Port(uid: "AppleUSBAudioEngine:Behringer:X18/XR18:1", isBuiltIn: false, channelCount: 18)

    @Test("A USB interface plugged in or out is a new input; so is the interface offering a different number of channels")
    func usbChanges() {
        let builtIn = InputRoute(ports: [Self.builtIn]), xr18 = InputRoute(ports: [Self.xr18])
        #expect(InputRoute.isNewInput(from: builtIn, to: xr18))
        #expect(InputRoute.isNewInput(from: xr18, to: builtIn))
        var twoChannels = Self.xr18
        twoChannels.channelCount = 2
        #expect(InputRoute.isNewInput(from: xr18, to: InputRoute(ports: [twoChannels])))
    }
}
