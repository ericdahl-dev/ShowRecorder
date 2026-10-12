@testable import MixerLink
import Testing

/// Which input channel an X32's USB Channel carries, from the card routing, the input routing and each channel's
/// source (#20). Block numbers are Maillot's X32 OSC protocol 4.06 (firmware 4.0 and above).
@Suite("X32 USB routing")
struct X32RoutingTests {
    /// The X32's defaults: card and inputs both AN1-8 … AN25-32, channel n on In n.
    static let defaults = X32Routing(cardBlocks: [0, 1, 2, 3], inputBlocks: [0, 1, 2, 3], channelSources: Array(1...32))

    @Test("On the default patch, USB Channel n carries channel n")
    func defaultPatch() {
        #expect((1...32).map { Self.defaults.channel(forUSBChannel: $0) } == (1...32).map { Optional($0) })
    }

    @Test("A channel moved to another input follows it: USB Channel 1 (input 1) is the channel whose source is In01")
    func channelOnAnotherInput() {
        var routing = Self.defaults
        routing.channelSources[0] = 0      // channel 1 off
        routing.channelSources[4] = 1      // channel 5 on In01
        #expect(routing.channel(forUSBChannel: 1) == 5)
        #expect(routing.channel(forUSBChannel: 5) == nil, "no channel uses In05 now, so USB Channel 5 gets no channel's name")
    }

    @Test("Card block patched to another bank: USB 1–8 carrying AN9-16 are channels 9–16")
    func cardBlockFromAnotherBank() {
        var routing = Self.defaults
        routing.cardBlocks[0] = 1   // AN9-16
        #expect((1...8).map { routing.channel(forUSBChannel: $0) } == (9...16).map { Optional($0) })
    }

    @Test("A stage box: inputs 1–8 from AES50 A1-8, and the card sends A1-8 on USB 17–24, so those are channels 1–8")
    func stageBox() {
        var routing = Self.defaults
        routing.inputBlocks[0] = 4  // A1-8
        routing.cardBlocks[2] = 4   // A1-8 on USB 17-24
        #expect((17...24).map { routing.channel(forUSBChannel: $0) } == (1...8).map { Optional($0) })
        #expect(routing.channel(forUSBChannel: 1) == nil, "no input carries AN1-8 now")
    }

    @Test("User inputs: UIN1-8 is 32 on the card and 20 on the inputs, and still matches")
    func userInputs() {
        var routing = Self.defaults
        routing.inputBlocks[1] = 20  // UIN1-8 on inputs 9-16
        routing.cardBlocks[3] = 32   // UIN1-8 on USB 25-32
        #expect((25...32).map { routing.channel(forUSBChannel: $0) } == (9...16).map { Optional($0) })
    }

    @Test("Outputs, P16 and aux on the card carry no input channel", arguments: [20, 21, 22, 23, 24, 25, 26, 31])
    func outputsCarryNoChannel(block: Int) {
        var routing = Self.defaults
        routing.cardBlocks[0] = block
        #expect((1...8).allSatisfy { routing.channel(forUSBChannel: $0) == nil })
    }
}
