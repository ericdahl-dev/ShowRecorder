import Foundation
import Testing
@testable import Recording

/// The Demo signal's meters look like a healthy show (Eric, 2026-11-15): averages mostly in the green target band,
/// peaks never red. Draft 1 of the Facebook Page walkthrough clip ran most peak bars into red, which reads as clipping.
/// The signal is uniform noise of peak `level`, so its average (RMS) is `level / √3`.
struct DemoSignalLevelTests {
    private let phases = stride(from: 0.0, to: 2 * Double.pi * 4, by: 0.05).map { $0 }

    private func readings() -> [Float] {
        phases.flatMap { phase in (0..<17).map { DemoSignalLevel.peak(channel: $0, of: 18, phase: phase) } }
    }

    @Test("Peaks never reach the red zone (above -6 dBFS) on any channel")
    func neverRed() {
        for level in readings() { #expect(20 * log10(Double(level)) < -6) }
    }

    @Test("Averages sit in the green target band (-18 to -15 dBFS) at least 60% of the time")
    func mostlyOnTarget() {
        let zones = readings().map { MeterZone(averageDbfs: 20 * log10(Double($0) / 3.0.squareRoot())) }
        let onTarget = zones.filter { $0 == .onTarget }.count
        #expect(Double(onTarget) / Double(zones.count) >= 0.6)
        #expect(!zones.contains(.hot))
    }

    @Test("The last channel stays silent, so the meters show an unused USB Channel")
    func lastChannelSilent() {
        #expect(DemoSignalLevel.peak(channel: 17, of: 18, phase: 1) == 0)
        #expect(DemoSignalLevel.peak(channel: 31, of: 32, phase: 1) == 0)
    }
}
