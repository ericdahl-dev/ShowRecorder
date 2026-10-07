import Recording
import Testing

@Suite("Power and heat status")
struct PowerStatusTests {
    func status(_ level: Double?, _ charging: PowerStatus.Charging = .unplugged, thermal: PowerStatus.Thermal = .nominal) -> PowerStatus {
        PowerStatus(batteryLevel: level, charging: charging, thermal: thermal)
    }

    // MARK: Battery

    @Test("The battery chip shows the percentage, and says when it is charging without relying on color")
    func batteryChipText() {
        #expect(status(0.84).battery?.text == "84%")
        #expect(status(0.84, .charging).battery?.text == "84% charging")
        #expect(status(1, .full).battery?.text == "100% charged")
        #expect(status(0.84, .charging).battery?.symbol.contains("bolt") == true)
        #expect(status(0.84).battery?.symbol.contains("bolt") == false)
    }

    @Test("Above 20% on battery is quiet: no warning, and the chip stays ok")
    func above20IsQuiet() {
        for level in [1.0, 0.5, 0.21, 0.205] {
            let s = status(level)
            #expect(s.warnings.isEmpty, "\(level)")
            #expect(s.battery?.state == .ok, "\(level)")
        }
    }

    @Test("At 20% or less and not charging it warns; at 10% or less it is urgent")
    func thresholds() {
        for level in [0.20, 0.15, 0.11] {
            let s = status(level)
            #expect(s.warnings.map(\.tone) == [.warning], "\(level)")
            #expect(s.battery?.state == .attention, "\(level)")
            #expect(s.warnings.first?.text.contains("\(Int((level * 100).rounded()))%") == true)
        }
        for level in [0.10, 0.05, 0.0] {
            let s = status(level)
            #expect(s.warnings.map(\.tone) == [.critical], "\(level)")
            #expect(s.battery?.state == .failed, "\(level)")
        }
    }

    @Test("The percentage shown is the percentage judged: 20.4% shows as 20% and warns, 20.6% shows as 21% and doesn't")
    func roundingMatchesDisplay() {
        #expect(status(0.204).battery?.text == "20%")
        #expect(status(0.204).warnings.count == 1)
        #expect(status(0.206).battery?.text == "21%")
        #expect(status(0.206).warnings.isEmpty)
    }

    @Test("Charging or full never warns, however low")
    func chargingNeverWarns() {
        for charging in [PowerStatus.Charging.charging, .full] {
            for level in [0.0, 0.05, 0.10, 0.20] {
                let s = status(level, charging)
                #expect(s.warnings.isEmpty, "\(charging) \(level)")
                #expect(s.battery?.state == .ok, "\(charging) \(level)")
            }
        }
    }

    @Test("When it can't tell whether it is charging, a low level doesn't raise a false alarm")
    func unknownChargingDoesNotWarn() {
        let s = status(0.05, .unknown)
        #expect(s.warnings.isEmpty)
        #expect(s.battery?.text == "5%")
    }

    @Test("A device with no battery has no battery status and no battery warning")
    func noBattery() {
        let s = status(nil, .unknown)
        #expect(s.battery == nil)
        #expect(s.warnings.isEmpty)
        let hot = status(nil, .unknown, thermal: .serious)
        #expect(hot.battery == nil)
        #expect(hot.warnings.count == 1)
    }

    @Test("A level outside 0...1 is held to the ends")
    func levelClamped() {
        #expect(status(1.7).battery?.text == "100%")
        #expect(status(-0.2).battery?.text == "0%")
        #expect(status(-0.2).warnings.map(\.tone) == [.critical])
    }

    // MARK: Heat

    @Test("Nominal heat shows nothing; fair is shown without a warning")
    func nominalAndFair() {
        #expect(status(0.8).thermal == nil)
        let fair = status(0.8, thermal: .fair)
        #expect(fair.thermal != nil)
        #expect(fair.thermal?.state == .neutral)
        #expect(fair.warnings.isEmpty)
    }

    @Test("Serious heat warns and critical is urgent, each with the chip to match")
    func seriousAndCritical() {
        let serious = status(0.8, thermal: .serious)
        #expect(serious.thermal?.state == .attention)
        #expect(serious.warnings.map(\.tone) == [.warning])
        let critical = status(0.8, thermal: .critical)
        #expect(critical.thermal?.state == .failed)
        #expect(critical.warnings.map(\.tone) == [.critical])
        #expect(serious.thermal?.text != critical.thermal?.text)
    }

    @Test("Every warning says what to do")
    func warningsSayWhatToDo() {
        for s in [status(0.15), status(0.05), status(0.8, thermal: .serious), status(0.8, thermal: .critical)] {
            let text = s.warnings.first?.text ?? ""
            #expect(text.count > 20 && text.hasSuffix("."), "\(text)")
        }
    }

    // MARK: Together

    @Test("Low battery and heat together give both warnings, the most urgent first, each with its own id")
    func together() {
        let s = status(0.05, thermal: .serious)
        #expect(s.warnings.map(\.tone) == [.critical, .warning])
        #expect(Set(s.warnings.map(\.id)).count == 2)
        let both = status(0.05, thermal: .critical)
        #expect(both.warnings.map(\.tone) == [.critical, .critical])
        #expect(both.warnings.map(\.id) == ["thermal", "battery"], "ties: heat first, it can stop the recording sooner")
    }

    // MARK: Strip

    @Test("The strip gets the battery chip, then the heat chip, and only those that exist")
    func chipsInOrder() {
        #expect(status(0.5).chips.map(\.text) == ["50%"])
        #expect(status(0.5, thermal: .serious).chips.map(\.text) == ["50%", "Hot"])
        #expect(status(nil, .unknown, thermal: .fair).chips.map(\.text) == ["Warm"])
        #expect(status(nil, .unknown).chips.isEmpty)
    }

    @Test("Warnings become record-screen alerts: power priority, same tone and text, most urgent first, nothing when fine")
    func alertsForTheBanner() {
        #expect(status(0.8).alerts.isEmpty)
        let alerts = status(0.05, thermal: .serious).alerts
        #expect(alerts.map(\.priority) == [.power, .power])
        #expect(alerts.map(\.tone) == [.critical, .warning])
        #expect(alerts.map(\.id) == ["battery", "thermal"])
        #expect(alerts.map(\.text) == status(0.05, thermal: .serious).warnings.map(\.text))
        #expect(alerts.allSatisfy { $0.action == nil }, "can't be dismissed while the condition holds")
        // Through the queue, the most urgent is on top.
        #expect(AlertQueue(alerts).top?.id == "battery")
    }

    @Test("Every chip has a short form for a crowded strip: battery drops the words the symbol already says")
    func shortForms() {
        #expect(status(0.84, .charging).battery?.shortText == "84%")
        #expect(status(1, .full).battery?.shortText == "100%")
        #expect(status(0.5).battery?.shortText == "50%")
        #expect(status(0.5, thermal: .serious).thermal?.shortText == "Hot")
    }
}
