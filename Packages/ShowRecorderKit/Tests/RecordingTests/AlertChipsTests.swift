@testable import Recording
import Testing

@Suite("Which chips an alert is about")
struct AlertChipsTests {
    func alert(_ id: String) -> ScreenAlert {
        ScreenAlert(id: id, priority: .destination, tone: .critical, text: id)
    }

    @Test("The Drive stopping is about the Drive chip, not the Device chip")
    func driveStopped() {
        #expect(alert("drive-stopped").isAbout(.drive))
        #expect(!alert("drive-stopped").isAbout(.device))
    }

    @Test("Both Copies stopping is about the Device and the Drive chips")
    func bothStopped() {
        #expect(alert("both-stopped").isAbout(.device))
        #expect(alert("both-stopped").isAbout(.drive))
        #expect(!alert("both-stopped").isAbout(.mixer))
    }

    @Test("The Device stopping is about the Device chip; no Drive is about the Drive chip")
    func deviceStoppedAndNoDrive() {
        #expect(alert("device-stopped").isAbout(.device))
        #expect(!alert("device-stopped").isAbout(.drive))
        #expect(alert("no-drive").isAbout(.drive))
    }

    @Test("A battery warning is about the battery chip, not the heat chip")
    func batteryChip() {
        let power = PowerStatus(batteryLevel: 0.15, charging: .unplugged, thermal: .serious)
        let battery = power.alerts.first { $0.id == "battery" }!

        #expect(battery.isAbout(power.battery!))
        #expect(!battery.isAbout(power.thermal!))
    }

    @Test("An alert about something else is about no chip")
    func otherAlert() {
        let getReady = alert("getReady")

        #expect(StatusChip.Kind.allCases.allSatisfy { !getReady.isAbout($0) })
        #expect(!getReady.isAbout(PowerStatus.Chip(text: "1 Dropout", symbol: "waveform.badge.exclamationmark", state: .attention)))
    }
}
