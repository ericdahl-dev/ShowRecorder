import MixerLink
import SwiftUI

/// One vertical meter per USB Channel, numbered from 1, labeled with its Source when the Mixer Link is up.
struct MeterGrid: View {
    let levels: [Float]
    var sources: [Source] = []
    /// Short screens (landscape iPhone): every channel gets its number and a Mixer-color swatch, and the
    /// Source's name only when there are few enough channels to have room for it.
    var compact = false

    /// The widest a meter (and its label) gets. Wide enough that 18 channels fill an iPad, narrow enough
    /// that one or two channels aren't a screen-wide slab. The strip is centered when it's narrower
    /// than the screen.
    static let maxBarWidth: CGFloat = 64

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    MeterBar(fraction: Self.fraction(forLinearPeak: levels[index]))
                        .frame(maxHeight: .infinity)
                    SourceLabel(
                        number: index + 1,
                        source: sources.indices.contains(index) ? sources[index] : nil,
                        compact: compact, showsName: !compact || levels.count <= 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(height: geometry.size.height * fraction)
            }
        }
        .frame(minWidth: 8, maxWidth: MeterGrid.maxBarWidth)
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
    var compact = false
    var showsName = true

    var body: some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let source {
                if showsName {
                    Text(source.hasMixerName ? source.name : "–")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: MeterGrid.maxBarWidth, minHeight: compact ? 16 : 28)
                        .foregroundStyle(source.color.inverted ? Color.black : source.color.swiftUIColor)
                        .background(source.color.inverted ? source.color.swiftUIColor : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(source.color.swiftUIColor.opacity(0.6)))
                } else {
                    // No room for the name: the Mixer's color for this channel, as a bar under the number.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(source.color.swiftUIColor)
                        .frame(maxWidth: MeterGrid.maxBarWidth, minHeight: 4, maxHeight: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.map { "USB Channel \(number), \($0.name)" } ?? "USB Channel \(number)")
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
