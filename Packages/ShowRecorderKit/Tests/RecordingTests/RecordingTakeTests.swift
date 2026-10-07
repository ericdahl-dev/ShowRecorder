import AudioIO
import Foundation
import Recording
import Testing

@MainActor
@Suite("Recording a Take")
struct RecordingTakeTests {
    /// 2026-10-06 21:30:00 local time.
    static let showDay: Date = {
        var components = DateComponents(year: 2026, month: 10, day: 6, hour: 21, minute: 30)
        components.timeZone = .current
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RecordingTakeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A value exactly representable in 24 bits, as the recorder will write it.
    static func sample(_ value: Int32) -> Float { Float(value) / 8_388_608 }

    @Test("Pressing record with no open Show creates a Show and Take 01 with a Stem per USB Channel")
    func recordCreatesShowTakeAndStems() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)

        try recorder.startTake()
        device.deliver([
            [100, -200, 300].map(Self.sample),
            [-1, 2, -3].map(Self.sample),
        ])
        try recorder.stopTake()

        let take = root.appending(path: "2026-10-06 Show/Take 01")
        let first = try StemFile(contentsOf: take.appending(path: "01 USB 01.wav"))
        let second = try StemFile(contentsOf: take.appending(path: "02 USB 02.wav"))
        #expect(first.channelCount == 1)
        #expect(first.sampleRate == 48_000)
        #expect(first.bitsPerSample == 24)
        #expect(first.samples == [100, -200, 300])
        #expect(second.samples == [-1, 2, -3])
    }

    @Test("Every Stem's bext carries its name, the originator and the same time reference")
    func bextDescribesStemAndSharesTimeReference() throws {
        let device = FakeAudioDevice(inputChannelCount: 3)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)

        try recorder.startTake()
        device.deliver([[0], [0], [0]])
        try recorder.stopTake()

        let take = root.appending(path: "2026-10-06 Show/Take 01")
        let stems = try ["01 USB 01", "02 USB 02", "03 USB 03"].map {
            try StemFile(contentsOf: take.appending(path: "\($0).wav"))
        }
        #expect(stems.map(\.description) == ["USB 01", "USB 02", "USB 03"])
        #expect(stems.allSatisfy { $0.originator == "ShowRecorder" })
        // 21:30:00 is 77,400 s after midnight; at 48 kHz that's 3,715,200,000 samples.
        #expect(stems.allSatisfy { $0.timeReference == 3_715_200_000 })
    }

    @Test("A second record press starts Take 02 in the same Show")
    func secondRecordStartsTake02InSameShow() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)

        try recorder.startTake()
        device.deliver([[Self.sample(1)]])
        try recorder.stopTake()
        try recorder.startTake()
        device.deliver([[Self.sample(2)]])
        try recorder.stopTake()

        let show = root.appending(path: "2026-10-06 Show")
        #expect(recorder.currentShow?.name == "2026-10-06 Show")
        #expect(recorder.currentShow?.takeCount == 2)
        #expect(try StemFile(contentsOf: show.appending(path: "Take 01/01 USB 01.wav")).samples == [1])
        #expect(try StemFile(contentsOf: show.appending(path: "Take 02/01 USB 01.wav")).samples == [2])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["2026-10-06 Show"])
    }

    @Test("Audio outside a Take isn't written")
    func audioOutsideTakeIsNotWritten() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)

        device.deliver([[Self.sample(9)]])
        try recorder.startTake()
        device.deliver([[Self.sample(1)]])
        try recorder.stopTake()
        device.deliver([[Self.sample(9)]])

        let stem = try StemFile(contentsOf: root.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(stem.samples == [1])
    }

    @Test("Recording needs the recorder to be Armed")
    func recordingNeedsArmed() {
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })

        #expect(throws: RecorderError.notArmed) { try recorder.startTake() }
        #expect(recorder.currentShow == nil)
    }

    @Test("A Show folder that already exists isn't reused")
    func existingShowFolderIsNotReused() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "2026-10-06 Show"), withIntermediateDirectories: false)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))

        try recorder.startTake()
        try recorder.stopTake()

        #expect(recorder.currentShow?.name == "2026-10-06 Show 2")
    }
}
