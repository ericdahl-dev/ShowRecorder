/// Which input channel an X32's USB Channel carries (#20), worked out from the Mixer's routing. Block numbers are
/// those of Maillot's X32 OSC protocol 4.06, firmware 4.0 and above.
struct X32Routing: Equatable, Sendable {
    /// `/config/routing/CARD/1-8` … `25-32`: what each block of 8 USB Channels carries.
    var cardBlocks: [Int]
    /// `/config/routing/IN/1-8` … `25-32`: what each block of 8 inputs (In01 … In32) carries.
    var inputBlocks: [Int]
    /// `/ch/01…32/config/source` in channel order: 0 off, 1–32 In01–In32, then aux, USB, FX and buses.
    var channelSources: [Int]

    /// The input channel (1–32) whose signal USB Channel `usbChannel` (1–32) carries, or nil when it carries something
    /// else, such as an output or a signal no channel uses.
    func channel(forUSBChannel usbChannel: Int) -> Int? {
        let offset = (usbChannel - 1) % 8
        guard let block = cardBlocks[safe: (usbChannel - 1) / 8], let bank = Self.inputBank(ofCardBlock: block),
              let inputBlock = inputBlocks.firstIndex(of: bank) else { return nil }
        let input = inputBlock * 8 + offset + 1
        return channelSources.firstIndex(of: input).map { $0 + 1 }
    }

    /// The input-routing number of the bank a card block carries, when it carries one the inputs can also carry:
    /// local (AN), AES50 A and B, and the card itself are 0–19 in both lists; the user inputs UIN1-8 … UIN25-32 are
    /// 32–35 on the card and 20–23 on the inputs. Outputs, P16, aux and user outputs are nil: no input channel
    /// carries them.
    static func inputBank(ofCardBlock block: Int) -> Int? {
        switch block {
        case 0...19: block
        case 32...35: block - 12
        default: nil
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
