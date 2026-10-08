import MixerLink
import Recording
import SwiftUI

/// One vertical meter per USB Channel, numbered from 1, labeled with its Source when the Mixer Link is up.
///
/// Each meter is the old peak bar (wide, behind), the VU average as a narrower bar in front, shown against
/// the target band (-18 to -15 dBFS), and a line for the held peak. What the colors mean is decided in
/// `ChannelMeter`.
struct MeterGrid: View {
    let meters: [ChannelMeter]
    /// The channels (from 0) that have clipped and not been cleared. Tapping a channel's lane clears its mark.
    var clipped: Set<Int> = []
    var clearClip: (Int) -> Void = { _ in }
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
            ForEach(meters.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    VStack(spacing: 2) {
                        // Shape as well as color: a triangle with an exclamation mark. The row is always there so
                        // a clip doesn't move the meters.
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .opacity(clipped.contains(index) ? 1 : 0)
                        MeterBar(meter: meters[index])
                            .frame(maxHeight: .infinity)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if clipped.contains(index) { clearClip(index) } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Level, USB Channel \(index + 1)")
                    .accessibilityValue(Self.spokenLevel(meters[index], clipped: clipped.contains(index)))
                    .accessibilityAddTraits(clipped.contains(index) ? .isButton : [])
                    .accessibilityHint(clipped.contains(index) ? "Double tap to clear the clip mark" : "")
                    SourceLabel(
                        number: index + 1,
                        source: sources.indices.contains(index) ? sources[index] : nil,
                        compact: compact, showsName: !compact || meters.count <= 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Maps dBFS to 0...1 on a -60...0 scale.
    static func fraction(forDbfs dbfs: Double) -> Double {
        min(max((dbfs + 60) / 60, 0), 1)
    }

    static func spokenLevel(_ meter: ChannelMeter, clipped: Bool = false) -> String {
        let place = switch meter.zone {
        case .low: "below the target"
        case .onTarget: "on target"
        case .hot: "above the target"
        }
        let average = meter.averageDbfs <= VUMeter.floorDbfs ? "silent" : "average \(Int(meter.averageDbfs.rounded())) dB, \(place)"
        let described = meter.peakIsHot ? "\(average), peak near clipping" : average
        return clipped ? "Clipped. \(described)" : described
    }
}

struct MeterBar: View {
    let meter: ChannelMeter

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                // The target band, faint, behind the bar.
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: height * (MeterGrid.fraction(forDbfs: MeterZone.bandHighDbfs) - MeterGrid.fraction(forDbfs: MeterZone.bandLowDbfs)))
                    .offset(y: -height * MeterGrid.fraction(forDbfs: MeterZone.bandLowDbfs))
                // The peak bar, as the old meter drew it.
                RoundedRectangle(cornerRadius: 3)
                    .fill(peakBarColor)
                    .frame(height: height * MeterGrid.fraction(forDbfs: Self.dbfs(ofLinear: meter.peakBar)))
                // The average, narrower and in front.
                RoundedRectangle(cornerRadius: 2)
                    .fill(averageColor)
                    .frame(width: geometry.size.width * 0.5, height: height * MeterGrid.fraction(forDbfs: meter.averageDbfs))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.black.opacity(0.35), lineWidth: 1))
                // The held peak: thicker as well as red when it's near clipping, so color isn't the only cue.
                Rectangle()
                    .fill(meter.peakIsHot ? Color.red : Color.primary.opacity(0.85))
                    .frame(height: meter.peakIsHot ? 4 : 2)
                    .offset(y: -max(height * MeterGrid.fraction(forDbfs: meter.peakDbfs) - 1, 0))
                    .opacity(meter.peakDbfs <= VUMeter.floorDbfs ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(minWidth: 8, maxWidth: MeterGrid.maxBarWidth)
    }

    private static func dbfs(ofLinear level: Float) -> Double {
        level > 0 ? 20 * log10(Double(level)) : VUMeter.floorDbfs
    }

    private var peakBarColor: Color {
        switch meter.peakBarZone {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }

    private var averageColor: Color {
        switch meter.zone {
        case .low: Color(red: 0.45, green: 0.58, blue: 0.72)
        case .onTarget: .green
        case .hot: .orange
        }
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
