import MixerLink
import OSC
import Testing

/// Naming a WING's USB Channels (#417): each USB output's routing (`/io/out/USB/n/grp` and `/in`) says which Source it
/// carries, and that Source's name and color (`/io/in/<grp>/<in>/name` and `/col`) name the USB Channel. Paths and
/// reply formats from the WING Remote Protocols document (Maillot, V3.0.5-1); checked against no real WING, and
/// wingemul answers no OSC.
@Suite("WING Sources")
struct WingSourcesTests {
    /// A WING with USB outputs patched as `routing` (USB n -> group, input) and Sources named and colored as `sources`.
    static func wing(routing: [Int: (String, Int)], sources: [String: (String, Int)] = [:]) -> FakeWing.State {
        var state = FakeWing.State()
        for (usb, (group, input)) in routing {
            state.replies["/io/out/USB/\(usb)/grp"] = [.string(group)]
            state.replies["/io/out/USB/\(usb)/in"] = FakeWing.intReply(input)
        }
        for usb in 1...48 where routing[usb] == nil {
            state.replies["/io/out/USB/\(usb)/grp"] = [.string("OFF")]
            state.replies["/io/out/USB/\(usb)/in"] = FakeWing.intReply(1)
        }
        for (path, (name, color)) in sources {
            state.replies["/io/in/\(path)/name"] = [.string(name)]
            state.replies["/io/in/\(path)/col"] = FakeWing.intReply(color)
        }
        return state
    }

    static func driver(_ wing: FakeWing, timeout: Duration = Loopback.replyTimeout) -> WingDriver {
        WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.port), oscPort: wing.oscPort, timeout: timeout)
    }

    @Test("Each USB Channel is named and colored after the Source patched to it")
    func namesFromRouting() async throws {
        let wing = try await FakeWing(Self.wing(
            routing: [1: ("LCL", 1), 2: ("A", 5), 48: ("USB", 3)],
            sources: ["LCL/1": ("Kick", 9), "A/5": ("Lead Vox", 7), "USB/3": ("Click", 4)]))

        let sources = try await Self.driver(wing).sources(usbChannelCount: 48)

        #expect(sources.count == 48)
        #expect(sources[safe: 0]?.name == "Kick")
        #expect(sources[safe: 0]?.color == MixerColor(hue: .red, inverted: false))
        #expect(sources[safe: 0]?.routedFrom == "LCL:1")
        #expect(sources[safe: 1]?.name == "Lead Vox")
        #expect(sources[safe: 1]?.color == MixerColor(hue: .yellow, inverted: false))
        #expect(sources[safe: 47]?.name == "Click")
        #expect(sources[safe: 47]?.color == MixerColor(hue: .cyan, inverted: false))
    }

    @Test("A USB output patched to nothing, or to a bus, main or matrix, keeps its USB Channel name")
    func unpatchedOrMix() async throws {
        let wing = try await FakeWing(Self.wing(routing: [1: ("OFF", 1), 2: ("BUS", 3), 3: ("MAIN", 1)]))

        let sources = try await Self.driver(wing).sources(usbChannelCount: 3)

        #expect(sources.map(\.name) == ["USB 01", "USB 02", "USB 03"])
        #expect(sources.allSatisfy { !$0.hasMixerName && $0.routedFrom == nil })
    }

    @Test("A Source with no name keeps the USB Channel name but shows the Source's color")
    func unnamedSource() async throws {
        let wing = try await FakeWing(Self.wing(routing: [1: ("LCL", 2)], sources: ["LCL/2": ("", 5)]))

        let sources = try await Self.driver(wing).sources(usbChannelCount: 1)

        #expect(sources.first?.name == "USB 01")
        #expect(sources.first?.hasMixerName == false)
        #expect(sources.first?.color == MixerColor(hue: .green, inverted: false))
        #expect(sources.first?.routedFrom == "LCL:2")
    }

    @Test("A WING that answers no OSC (wingemul) names nothing, and costs one timeout, not one per USB Channel")
    func noOSC() async throws {
        let wing = try await FakeWing(.init(answersOSC: false))
        let clock = ContinuousClock()
        let start = clock.now

        let sources = try await Self.driver(wing, timeout: .milliseconds(300)).sources(usbChannelCount: 48)

        #expect(sources.map(\.name) == (1...48).map { Source.fallback(usbChannel: $0).name })
        #expect(clock.now - start < .seconds(5))
        #expect(wing.queries.count == 1, "it stops at the first unanswered query")
    }

    @Test("Now that it reads routing, a WING's 48 USB Channels are all nameable")
    func capabilities() async throws {
        let wing = try await FakeWing()
        let identity = MixerIdentity(networkName: "", model: "ngc-full", firmware: "")
        #expect(Self.driver(wing).capabilities(for: identity) == MixerCapabilities(usbChannelCount: 48, nameableUSBChannelCount: 48))
    }

    @Test("WING colors 1 to 12 map to the nearest of the eight hues (palette names not confirmed from a WING)",
          arguments: [(1, MixerColor.Hue.blue), (2, .blue), (3, .blue), (4, .cyan), (5, .green), (6, .green), (7, .yellow),
                      (8, .yellow), (9, .red), (10, .red), (11, .magenta), (12, .magenta), (0, .off), (13, .off)])
    func colors(index: Int, hue: MixerColor.Hue) {
        #expect(MixerColor(wingIndex: index) == MixerColor(hue: hue, inverted: false))
    }
}
