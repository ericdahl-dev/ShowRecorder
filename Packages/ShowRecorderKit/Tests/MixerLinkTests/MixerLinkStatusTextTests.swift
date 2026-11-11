import MixerLink
import Testing

/// What Settings › Mixer Link says: before connecting, which Mixers the Link works with; once up, what kind of Mixer
/// it is on.
@Suite("Mixer Link status text")
struct MixerLinkStatusTextTests {
    @Test("Not connected names the Mixers the Link works with, without the WING where it isn't offered")
    func idleWithoutWing() {
        #expect(MixerLinkStatus.idle.settingsText(offering: MixerFamily.offered(wing: false))
            == "Works with X Air (XR12/16/18, MR18) and X32/M32. Not connected. Stems use USB Channel names.")
    }

    @Test("Not connected names the WING where it is offered")
    func idleWithWing() {
        #expect(MixerLinkStatus.idle.settingsText(offering: MixerFamily.offered(wing: true))
            == "Works with X Air (XR12/16/18, MR18), X32/M32 and WING. Not connected. Stems use USB Channel names.")
    }

    @Test("Connected says what kind of Mixer the Link is on, from the model the Mixer gave",
          arguments: [("XR18", "Connected to an X Air · FOH (XR18) · Wi-Fi"),
                      ("X32", "Connected to an X32 · FOH (X32) · Wi-Fi"),
                      ("ngc-full", "Connected to a WING · FOH (WING) · Wi-Fi")])
    func up(model: String, text: String) {
        let identity = MixerIdentity(networkName: "FOH", model: model, firmware: "1.0")
        #expect(MixerLinkStatus.up(identity, path: .wifi).settingsText() == text)
    }

    @Test("Connected without a network name shows the model alone")
    func upWithoutName() {
        let identity = MixerIdentity(networkName: "", model: "XR18", firmware: "1.0")
        #expect(MixerLinkStatus.up(identity, path: .wifi).settingsText() == "Connected to an X Air · XR18 · Wi-Fi")
    }

    @Test("A WING shows its plain model name, not the code it reports; any other WING code reads as WING",
          arguments: [("ngc-full", "WING"), ("wing-rack", "WING Rack"), ("wing-compact", "WING Compact"), ("wing-bk", "WING")])
    func wingModel(code: String, name: String) {
        let identity = MixerIdentity(networkName: "FOH", model: code, firmware: "3.0")
        #expect(MixerLinkStatus.up(identity, path: .wifi).settingsText() == "Connected to a WING · FOH (\(name)) · Wi-Fi")
    }

    @Test("A WING with no network name shows its plain model name alone")
    func wingWithoutName() {
        let identity = MixerIdentity(networkName: "", model: "wing-rack", firmware: "3.0")
        #expect(MixerLinkStatus.up(identity, path: .wifi).settingsText() == "Connected to a WING · WING Rack · Wi-Fi")
    }

    @Test("Connecting and down read as before")
    func connectingAndDown() {
        #expect(MixerLinkStatus.connecting(host: "192.168.1.146").settingsText() == "Connecting to 192.168.1.146…")
        #expect(MixerLinkStatus.down(.networkUnreachable).settingsText() == MixerLinkProblem.networkUnreachable.message)
    }
}
