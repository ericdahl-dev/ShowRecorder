import SwiftUI

/// One vertical meter per USB Channel, numbered from 1.
struct MeterGrid: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    MeterBar(fraction: Self.fraction(forLinearPeak: levels[index]))
                    Text("\(index + 1)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 280, alignment: .leading)
    }

    /// Maps a linear peak to 0...1 on a -60...0 dBFS scale.
    static func fraction(forLinearPeak peak: Float) -> Double {
        let dB = 20 * log10(Double(max(peak, 1e-6)))
        return min(max((dB + 60) / 60, 0), 1)
    }
}

struct MeterBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(height: geometry.size.height * fraction)
            }
        }
        .frame(minWidth: 8, maxWidth: 44)
    }

    private var color: Color {
        // -6 dBFS and -18 dBFS thresholds on the -60...0 scale.
        if fraction > 0.9 { return .red }
        if fraction > 0.7 { return .yellow }
        return .green
    }
}
