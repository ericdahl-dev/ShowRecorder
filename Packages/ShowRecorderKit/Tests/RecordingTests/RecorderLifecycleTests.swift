import AudioIO
import Foundation
import Recording
import Testing

/// What the recorder does when the screen showing it goes away and comes back.
@Suite("Recorder lifecycle")
struct RecorderLifecycleTests {
    @Test("When the screen goes away during a Take, nothing ends the Take")
    func disappearDuringATake() {
        #expect(RecorderLifecycle.screenDisappeared(isRecording: true) == .none)
    }

    @Test("When the screen goes away with no Take, the recorder disarms so the input isn't held for nothing")
    func disappearWhileOnlyArmed() {
        #expect(RecorderLifecycle.screenDisappeared(isRecording: false) == .disarm)
    }

    @Test("A screen that appears leaves an Armed recorder alone, because Arming again would stop a Take, and Arms one that isn't")
    func appear() {
        #expect(RecorderLifecycle.screenAppeared(isArmed: true) == .none)
        #expect(RecorderLifecycle.screenAppeared(isArmed: false) == .arm)
    }

    @MainActor
    @Test("Tearing down the screen and building it again during a Take leaves the Take, its Markers and its Stem untouched")
    func screenRebuiltDuringATake() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RecorderLifecycleTests-\(UUID().uuidString)")
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root)
        func sample(_ value: Int32) -> Float { Float(value) / 8_388_608 }
        try recorder.arm(device)
        try recorder.startTake()
        device.deliver([[sample(1), sample(2)]])
        recorder.addMarker(named: "Verse")

        // The screen goes away and a new one appears, as when iOS discards and rebuilds a scene.
        if RecorderLifecycle.screenDisappeared(isRecording: recorder.isRecording) == .disarm { recorder.disarm() }
        if RecorderLifecycle.screenAppeared(isArmed: recorder.isArmed) == .arm { try recorder.arm(device) }

        #expect(recorder.isRecording)
        #expect(recorder.takeMarkers.map(\.name) == ["Verse"])
        device.deliver([[sample(3), sample(4)]])
        try recorder.stopTake()

        let stem = try StemFile(contentsOf: try #require(recorder.currentShow).folder.appending(path: "Take 01/01 USB 01.wav"))
        #expect(stem.samples == [1, 2, 3, 4])
    }
}
