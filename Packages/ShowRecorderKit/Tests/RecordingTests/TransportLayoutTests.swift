@testable import Recording
import Testing

/// The space between Record or Stop and Marker. Marker is pressed often and Stop ends the Take, so they are kept apart.
@Suite("Transport layout")
struct TransportLayoutTests {
    @Test("On any normal phone width the two buttons are at least 72 pt apart")
    func apartOnPhones() {
        for width in [375.0, 390, 402, 430, 768, 1024] {
            #expect(TransportLayout.gap(availableWidth: width, buttonSize: 88) >= 72, "\(width)")
        }
    }

    @Test("On a very narrow space the gap shrinks so both buttons still fit, but never below 40 pt")
    func shrinksWhenNarrow() {
        let gap = TransportLayout.gap(availableWidth: 250, buttonSize: 88)
        #expect(gap >= 40)
        #expect(88 * 2 + gap <= 250 + 0.001 || gap == 40)
    }

    @Test("The gap does not grow without limit on a wide screen")
    func cappedOnWideScreens() {
        #expect(TransportLayout.gap(availableWidth: 2000, buttonSize: 88) <= 120)
    }
}
