import MixerLink
import SwiftUI

/// One vertical meter per USB Channel, numbered from 1, labeled with its Source when the Mixer Link is up.
struct MeterGrid: View {
    let levels: [Float]
    var sources: [Source] = []

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    MeterBar(fraction: Self.fraction(forLinearPeak: levels[index]))
                    SourceLabel(number: index + 1, source: sources.indices.contains(index) ? sources[index] : nil)
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

/// The USB Channel number, and the Source's name on its Mixer color when known.
struct SourceLabel: View {
    let number: Int
    let source: Source?

    var body: some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let source {
                Text(source.hasMixerName ? source.name : "–")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: 44, minHeight: 28)
                    .foregroundStyle(source.color.inverted ? Color.black : source.color.swiftUIColor)
                    .background(source.color.inverted ? source.color.swiftUIColor : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(source.color.swiftUIColor.opacity(0.6)))
                    .accessibilityLabel("USB Channel \(number), \(source.name)")
            }
        }
    }
}

extension MixerColor {
    var swiftUIColor: Color {
        switch hue {
        case .off: .secondary
        case .red: .red
        case .green: .green
        case .yellow: .yellow
        case .blue: .blue
        case .magenta: .pink
        case .cyan: .cyan
        case .white: .primary
        }
    }
}
