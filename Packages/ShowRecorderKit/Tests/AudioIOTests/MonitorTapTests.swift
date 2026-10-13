@testable import AudioIO
import Testing

/// The tap that feeds the headphone monitor (#233): every input block goes to the recorder first, untouched, then its
/// first channel is copied into the monitor's ring.
@Suite("Monitor tap")
struct MonitorTapTests {
    @Test("The recorder gets every block as it came; the ring gets the first channel")
    func passesThroughAndCopies() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let ring = MonitorRing(capacity: 64)
        let tap = MonitorTap(device, ring: ring)
        #expect(tap.inputChannelCount == 2 && tap.sampleRate == device.sampleRate && tap.name == device.name)

        let seen = Seen()
        try tap.start { block in seen.add(block) }
        device.deliver([[1, 2, 3], [10, 20, 30]])
        tap.stop()

        #expect(seen.blocks == [[[1, 2, 3], [10, 20, 30]]])
        var out = [Float](repeating: 0, count: 3)
        out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 3, latencyLimit: .max) }
        #expect(out == [1, 2, 3])
    }

    @Test("A normal Take asks iOS for the chosen input; the monitor experiment doesn't, so the built-in mic doesn't pull the output to the receiver (#233)")
    func preferredInput() {
        #expect(AudioSessionPlan.recording.pinsPreferredInput)
        #expect(!AudioSessionPlan.monitorExperiment.pinsPreferredInput)
    }

    @Test("The plan for a normal Take records only; the monitor experiment plays to Bluetooth headphones but never takes their mic")
    func sessionPlans() {
        #expect(AudioSessionPlan.recording.playsOutput == false && !AudioSessionPlan.recording.allowsBluetoothOutput)
        #expect(!AudioSessionPlan.recording.allowsBluetoothInput && !AudioSessionPlan.recording.defaultToSpeaker)
        #expect(AudioSessionPlan.monitorExperiment.playsOutput && AudioSessionPlan.monitorExperiment.allowsBluetoothOutput)
        #expect(!AudioSessionPlan.monitorExperiment.allowsBluetoothInput && !AudioSessionPlan.monitorExperiment.defaultToSpeaker)
    }
}

/// Copies of the blocks a handler saw, by channel.
final class Seen: @unchecked Sendable {
    private(set) var blocks: [[[Float]]] = []
    func add(_ block: AudioBlock) {
        blocks.append((0..<block.channelCount).map { Array(UnsafeBufferPointer(start: block.channels[$0], count: block.frameCount)) })
    }
}
