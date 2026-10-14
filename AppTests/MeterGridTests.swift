import Testing
@testable import ShowRecorder

@MainActor
struct MeterGridTests {
    @Test func meterFractionClampsToTheMinus60To0Scale() {
        #expect(MeterGrid.fraction(forDbfs: -90) == 0)
        #expect(MeterGrid.fraction(forDbfs: -60) == 0)
        #expect(MeterGrid.fraction(forDbfs: -30) == 0.5)
        #expect(MeterGrid.fraction(forDbfs: 0) == 1)
        #expect(MeterGrid.fraction(forDbfs: 6) == 1)
    }
}
