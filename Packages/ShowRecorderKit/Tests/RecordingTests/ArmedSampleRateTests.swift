import AudioIO
import Foundation
@testable import Recording
import Testing

@MainActor
@Suite("Armed sample rate")
struct ArmedSampleRateTests {
    @Test("The Recorder reports the Armed input's sample rate, and none when disarmed (#298)")
    func armedRate() throws {
        let recorder = Recorder(deviceFolder: FileManager.default.temporaryDirectory.appending(path: "ArmedSampleRateTests-\(UUID().uuidString)"))
        #expect(recorder.sampleRate == nil)
        try recorder.arm(FakeAudioDevice(inputChannelCount: 2, sampleRate: 44_100))
        #expect(recorder.sampleRate == 44_100)
        recorder.disarm()
        #expect(recorder.sampleRate == nil)
    }
}
