import Testing

@testable import Recording

/// A lane's arm menu item, built from steady data only (#1135): the channel and whether it is armed, never the level.
@Suite("Channel arm menu item")
struct ChannelArmMenuItemTests {
    @Test("An armed channel offers \"Don't arm channel N\", and a tap stops arming it")
    func armed() {
        let item = ChannelArmMenuItem(channel: 3, notArmed: [5])
        #expect(item.title == "Don't arm channel 3")
        #expect(item.systemImage == "circle.slash")
        #expect(item.accessibilityName == "Don't arm channel")
        #expect(item.armsOnTap == false)
    }

    @Test("A channel that is not armed offers \"Arm channel N\", and a tap arms it")
    func notArmed() {
        let item = ChannelArmMenuItem(channel: 5, notArmed: [5])
        #expect(item.title == "Arm channel 5")
        #expect(item.systemImage == "circle")
        #expect(item.accessibilityName == "Arm channel")
        #expect(item.armsOnTap == true)
    }

    @Test("A lane's item changes only with its own channel: arming another channel leaves it the same")
    func steady() {
        #expect(ChannelArmMenuItem(channel: 3, notArmed: [5]) == ChannelArmMenuItem(channel: 3, notArmed: []))
        #expect(ChannelArmMenuItem(channel: 3, notArmed: [3]) != ChannelArmMenuItem(channel: 3, notArmed: []))
    }
}
