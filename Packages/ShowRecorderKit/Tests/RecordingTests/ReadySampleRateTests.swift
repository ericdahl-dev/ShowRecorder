import AudioIO
import Foundation
@testable import Recording
import Testing

@MainActor
@Suite("Ready sample rate")
struct ReadySampleRateTests {
    @Test("The Recorder reports the Ready input's sample rate, and none when stood down (#298)")
    func readyRate() throws {
        let recorder = Recorder(deviceFolder: FileManager.default.temporaryDirectory.appending(path: "ReadySampleRateTests-\(UUID().uuidString)"))
        #expect(recorder.sampleRate == nil)
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 2, sampleRate: 44_100))
        #expect(recorder.sampleRate == 44_100)
        recorder.standDown()
        #expect(recorder.sampleRate == nil)
    }
}
