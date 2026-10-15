@testable import Recording
import Testing

/// A folder of stems played as USB Channels for screenshots (#374): which file goes on which channel, and its name.
@Suite("Stem demo layout")
struct StemDemoLayoutTests {
    @Test("Six stereo stems become twelve channels in a band's order, named from the file without the shared prefix")
    func bandOrder() {
        let files = ["bass", "drums", "guitar", "other", "piano", "vocals"].map { ("High_Speed_Run_Ethereal_Drift_\($0).wav", 2) }

        let layout = StemDemoLayout(files: files)

        #expect(layout.channelNames == ["Drums L", "Drums R", "Bass L", "Bass R", "Gtr L", "Gtr R", "Piano L", "Piano R",
                                        "Vox L", "Vox R", "Other L", "Other R"])
        #expect(layout.order.map(\.file).first == "High_Speed_Run_Ethereal_Drift_drums.wav")
    }

    @Test("A mono stem is one channel with its plain name")
    func mono() {
        #expect(StemDemoLayout(files: [("kick.wav", 1), ("snare.wav", 1)]).channelNames == ["Kick", "Snare"])
    }
}
