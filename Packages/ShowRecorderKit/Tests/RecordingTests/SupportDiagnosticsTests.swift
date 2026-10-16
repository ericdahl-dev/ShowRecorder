import Recording
import Testing

@Suite("Support email diagnostics (#722)")
struct SupportDiagnosticsTests {
    private let full = SupportDiagnostics(
        version: "1.1.6", build: "34.1", distribution: .testFlight, device: "iPhone16,1", system: "iOS 26.0.1",
        inputRoute: "USB Audio \"X32\"", channelCount: 32, sampleRate: 48_000, driveFolderSet: true,
        lastInterruption: .routeDisconnected, mixerLink: "X32 · X32, firmware 4.06")

    @Test("The subject carries the version and build")
    func subject() {
        #expect(full.subject == "ShowRecorder support (v1.1.6.34.1)")
    }

    @Test("A missing version or build reads as a question mark, never a blank")
    func subjectWithoutVersion() {
        var details = full
        details.version = nil
        details.build = nil
        #expect(details.subject == "ShowRecorder support (v?.?)")
    }

    @Test("The body leaves room to write, then a titled block with one line per fact")
    func bodyWithEverything() {
        #expect(full.body == """


            ----------------------------------------
            Diagnostics (you can delete these)
            ----------------------------------------
            App: 1.1.6 (build 34.1)
            Distribution: TestFlight
            Device: iPhone16,1
            System: iOS 26.0.1
            Audio input: USB Audio "X32"
            Channels: 32 at 48000 Hz
            Drive folder set: yes
            Last interruption: input disconnected
            Mixer Link: X32 · X32, firmware 4.06
            """)
    }

    @Test("With nothing Armed, no Drive folder, no interruption and no Mixer Link, each line says so")
    func bodyWithNothing() {
        var details = full
        details.inputRoute = nil
        details.channelCount = nil
        details.sampleRate = nil
        details.driveFolderSet = false
        details.lastInterruption = nil
        details.mixerLink = nil
        let body = details.body
        #expect(body.contains("\nAudio input: None\n"))
        #expect(body.contains("\nChannels: Not armed\n"))
        #expect(body.contains("\nDrive folder set: no\n"))
        #expect(body.contains("\nLast interruption: None\n"))
        #expect(body.hasSuffix("\nMixer Link: Not linked"))
    }

    @Test("Every interruption reason has a plain line")
    func interruptionLines() {
        func body(for reason: InterruptionPolicy.Reason) -> String {
            var details = full
            details.lastInterruption = reason
            return details.body
        }
        #expect(body(for: .other).contains("\nLast interruption: a call, Siri or another app\n"))
        #expect(body(for: .builtInMicMuted).contains("\nLast interruption: built-in microphone muted\n"))
        #expect(body(for: .routeDisconnected).contains("\nLast interruption: input disconnected\n"))
    }

    @Test("The distribution comes from the build kind and the StoreKit environment")
    func distribution() {
        typealias D = SupportDiagnostics.Distribution
        #expect(D(isDebugBuild: true, environment: .production) == .debug)
        #expect(D(isDebugBuild: false, environment: .sandbox) == .testFlight)
        #expect(D(isDebugBuild: false, environment: .production) == .appStore)
        #expect(D(isDebugBuild: false, environment: .unknown) == .unknown)
        #expect(D(isDebugBuild: false, environment: nil) == .unknown)
    }

    @Test("The route label names the port type in words; a USB interface's product name follows in quotes")
    func routeLabel() {
        #expect(SupportDiagnostics.routeLabel(portType: "USBAudio", name: "X32") == "USB Audio \"X32\"")
        #expect(SupportDiagnostics.routeLabel(portType: "MicrophoneBuiltIn", name: "iPhone Microphone") == "Built-in microphone")
        #expect(SupportDiagnostics.routeLabel(portType: "MicrophoneWired", name: "x") == "Headset microphone")
        #expect(SupportDiagnostics.routeLabel(portType: "HeadsetMic", name: "x") == "Headset microphone")
        #expect(SupportDiagnostics.routeLabel(portType: "LineIn", name: "x") == "Line in")
        #expect(SupportDiagnostics.routeLabel(portType: "SomethingNew", name: "Box") == "SomethingNew")
        #expect(SupportDiagnostics.routeLabel(portType: nil, name: "X32") == "Audio interface \"X32\"")
        #expect(SupportDiagnostics.routeLabel(portType: nil, name: nil) == "Audio interface")
    }

    @Test("A device named after its owner never reaches the email")
    func personalNameStaysOut() {
        for type in ["BluetoothHFP", "BluetoothA2DP", "BluetoothLE", "MicrophoneBuiltIn", "HeadsetMic"] {
            let label = SupportDiagnostics.routeLabel(portType: type, name: "Eric's AirPods")
            #expect(!label.contains("Eric"), "\(type)")
            var details = full
            details.inputRoute = label
            #expect(!details.body.contains("Eric"), "\(type)")
        }
        #expect(SupportDiagnostics.routeLabel(portType: "BluetoothHFP", name: "Eric's AirPods") == "Bluetooth")
    }

    @Test("Armed with an unknown rate or a zero channel count, the Channels line does not say Not armed")
    func partialChannels() {
        var details = full
        details.sampleRate = nil
        #expect(details.body.contains("\nChannels: 32 at unknown rate\n"))
        details.sampleRate = 44_100
        details.channelCount = 0
        #expect(details.body.contains("\nChannels: unknown at 44100 Hz\n"))
    }

    @Test("The body is the title and exactly these lines, whatever the fields hold")
    func bodyShape() {
        let lines = full.body.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("-") }
        let keys = lines.compactMap { $0.split(separator: ":", maxSplits: 1).first.map(String.init) }
        #expect(keys == ["Diagnostics (you can delete these)", "App", "Distribution", "Device", "System", "Audio input",
                         "Channels", "Drive folder set", "Last interruption", "Mixer Link"])
    }
}
