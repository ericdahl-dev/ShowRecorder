import Testing

@testable import Recording

/// Colors for the Dark and Sunlight appearances, checked with measured WCAG contrast ratios.
@Suite("Appearance")
struct AppearanceTests {
    @Test("The WCAG contrast of black on white is 21, and of a color with itself is 1")
    func contrastMath() {
        #expect(abs(RGB(0, 0, 0).contrast(with: RGB(1, 1, 1)) - 21) < 0.001)
        #expect(abs(RGB(0.4, 0.5, 0.6).contrast(with: RGB(0.4, 0.5, 0.6)) - 1) < 0.001)
        // Order doesn't matter.
        #expect(RGB(1, 1, 1).contrast(with: RGB(0, 0, 0)) == RGB(0, 0, 0).contrast(with: RGB(1, 1, 1)))
    }

    @Test("Every banner tone and chip state has at least 4.5:1 text contrast in every appearance, and 7:1 in Sunlight", arguments: AppearanceMode.allCases)
    func bannersAndChips(mode: AppearanceMode) {
        for element in Palette.Element.allCases {
            let pair = Palette.pair(for: element, mode: mode)
            let ratio = pair.text.contrast(with: pair.fill)
            #expect(ratio >= 4.5, "\(element) in \(mode): \(ratio)")
            if mode == .sunlight { #expect(ratio >= 7, "\(element) in sunlight: \(ratio)") }
        }
    }

    @Test("Text on the background is at least 7:1 in Dark and Sunlight; meter colors are at least 3:1 against the background, or against their outline when they have one", arguments: [AppearanceMode.dark, .sunlight])
    func textAndMeters(mode: AppearanceMode) {
        let background = Palette.background(mode)
        #expect(Palette.primaryText(mode).contrast(with: background) >= 7)
        #expect(Palette.secondaryText(mode).contrast(with: background) >= 7)
        let outline = Palette.meterOutline(mode)
        if let outline { #expect(outline.contrast(with: background) >= 7) }
        for color in Palette.MeterColor.allCases {
            let edge = outline ?? background
            let ratio = Palette.meter(color, mode: mode).contrast(with: edge)
            #expect(ratio >= 3, "\(color) in \(mode): \(ratio)")
        }
        #expect(Palette.markerFlag(mode).contrast(with: background) >= 3)
    }

    @Test("In Sunlight the peak-bar zones differ in lightness, not only hue: green and red each contrast at least 3:1 with yellow")
    func zonesDifferInLightness() {
        let yellow = Palette.meter(.yellow, mode: .sunlight)
        #expect(Palette.meter(.green, mode: .sunlight).contrast(with: yellow) >= 3)
        #expect(Palette.meter(.red, mode: .sunlight).contrast(with: yellow) >= 3)
    }
}
