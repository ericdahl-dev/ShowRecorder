import AudioIO
import Foundation
import Recording
import Testing

/// The screenshot build (bundle ID ending ".screens") may Get ready only demo inputs: never a microphone or a USB
/// interface, so a screenshot run can't record a room (#374, after four runs recorded this Mac's microphone).
@MainActor
@Suite("Demo-only inputs")
struct DemoOnlyInputSourceTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DemoOnlyInputSourceTests-\(UUID().uuidString)")

    @Test("Only demo inputs are offered; the built-in microphone and a USB interface are not")
    func onlyDemo() {
        let real = FakeInputDevices([("coreaudio-BuiltInMicrophoneDevice", 1), ("coreaudio-XR18", 18), ("demo", 18), ("demo-stems", 12)])

        let ids = DemoOnlyInputSource(real).devices().map(\.id)

        #expect(ids == ["demo", "demo-stems"])
    }

    @Test("No route input: an iPhone or iPad's current route is never opened")
    func noRoute() {
        let real = FakeInputDevices()
        #expect(throws: (any Error).self) { try DemoOnlyInputSource(real).currentRouteDevice(sampleRate: nil) }
        #expect(real.routeOpened.isEmpty)
    }

    @Test("A sequencer on it can't get the microphone ready even when it is the one selected, and gets the Demo signal ready")
    func sequencerGetsReadyOnlyDemo() {
        let real = FakeInputDevices([("coreaudio-BuiltInMicrophoneDevice", 1), ("demo", 18)])
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        let sequencer = TakeSequencer(recorder: recorder, devices: DemoOnlyInputSource(real), capsAt48k: { false })

        sequencer.select("coreaudio-BuiltInMicrophoneDevice")
        sequencer.getReady()
        #expect(!recorder.isReady)
        #expect(real.opened.isEmpty, "the microphone was never opened")

        sequencer.select("demo")
        sequencer.getReady()
        #expect(recorder.isReady)
        #expect(sequencer.readyDevice?.id == "demo")
    }
}
