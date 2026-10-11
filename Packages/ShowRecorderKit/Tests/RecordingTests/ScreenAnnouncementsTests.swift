@testable import Recording
import Testing

/// What VoiceOver announces on the record screen: only changes, never the same thing twice (#249).
@Suite("Screen announcements")
struct ScreenAnnouncementsTests {
    func alert(_ id: String, _ text: String) -> ScreenAlert {
        ScreenAlert(id: id, priority: .destination, tone: .critical, text: text)
    }

    @Test("The first look and an unchanged screen announce nothing")
    func nothingWithoutChange() {
        let state = ScreenAnnouncements.State(clipped: [2], alerts: [alert("no-drive", "No Drive.")], dropoutCount: 1)
        #expect(ScreenAnnouncements.changes(from: nil, to: state) == [])
        #expect(ScreenAnnouncements.changes(from: state, to: state) == [])
    }

    @Test("A new alert is announced once, with its text; one that stays or goes away is not")
    func newAlerts() {
        let before = ScreenAnnouncements.State(alerts: [alert("no-drive", "No Drive.")])
        let after = ScreenAnnouncements.State(alerts: [alert("no-drive", "No Drive."), alert("drive-stopped", "The Drive stopped.")])
        #expect(ScreenAnnouncements.changes(from: before, to: after) == ["The Drive stopped."])
        #expect(ScreenAnnouncements.changes(from: after, to: before) == [])
    }

    @Test("A new clip names its USB Channels; a clip that is still held is not repeated")
    func clips() {
        let none = ScreenAnnouncements.State()
        #expect(ScreenAnnouncements.changes(from: none, to: .init(clipped: [3])) == ["Clip on USB Channel 4"])
        #expect(ScreenAnnouncements.changes(from: .init(clipped: [3]), to: .init(clipped: [3, 0])) == ["Clip on USB Channel 1"])
        #expect(ScreenAnnouncements.changes(from: none, to: .init(clipped: [5, 1])) == ["Clip on USB Channels 2 and 6"])
    }

    @Test("A Dropout is announced when the count goes up, and not when a new Take resets it")
    func dropouts() {
        #expect(ScreenAnnouncements.changes(from: .init(dropoutCount: 0), to: .init(dropoutCount: 1)) == ["Dropout"])
        #expect(ScreenAnnouncements.changes(from: .init(dropoutCount: 1), to: .init(dropoutCount: 3)) == ["2 Dropouts"])
        #expect(ScreenAnnouncements.changes(from: .init(dropoutCount: 3), to: .init(dropoutCount: 0)) == [])
    }
}
