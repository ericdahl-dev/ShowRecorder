import MixerLink
import Observation
import Recording
import SwiftUI

/// The levels of every channel, kept apart from the screen's other state so a new reading redraws the meters and
/// nothing else.
@MainActor
@Observable
final class MeterModel {
    private(set) var levels: [ChannelMeter] = []
    /// How many channels there are. Changes only when the input does, so views that just need the count aren't
    /// redrawn with every reading.
    private(set) var channelCount = 0

    func reset(channelCount count: Int) {
        levels = Array(repeating: ChannelMeter(), count: count)
        if channelCount != count { channelCount = count }
    }

    func update(from fresh: [ChannelLevel], seconds: Double) {
        guard fresh.count == levels.count else { return }
        for index in fresh.indices { levels[index].update(fresh[index], seconds: seconds) }
    }
}

/// One vertical meter per USB Channel, numbered from 1, labeled with its Source when the Mixer Link is up.
///
/// Each meter is the old peak bar (wide, behind), the VU average as a narrower bar in front, shown against
/// the target band (-18 to -15 dBFS), and a line for the held peak. What the colors mean is decided in
/// `ChannelMeter`.
struct MeterGrid: View {
    let model: MeterModel
    /// The channels (from 0) that have clipped and not been cleared. Tapping a channel's lane clears its mark.
    var clipped: Set<Int> = []
    var clearClip: (Int) -> Void = { _ in }
    /// The USB Channels (from 1) drawn as not armed: dimmed and marked, the meter still moving (#991).
    var notArmed: Set<Int> = []
    /// Arms (true) or stops arming (false) a USB Channel (from 1), from the lane's menu; nil where that isn't offered.
    var armChannel: ((Int, Bool) -> Void)?
    var sources: [Source] = []
    /// Names the operator typed, by USB Channel number (from 1). They win over the Mixer's names.
    var typedNames: [Int: String] = [:]
    /// Called with a USB Channel number (from 1) when its label is tapped, to name it.
    var nameChannel: (Int) -> Void = { _ in }
    /// Short screens (landscape iPhone): every channel gets its number and a Mixer-color swatch, and the
    /// Source's name only when there are few enough channels to have room for it.
    var compact = false
    @Environment(\.appearanceMode) private var mode

    /// The widest a meter (and its label) gets. Wide enough that 18 channels fill an iPad, narrow enough
    /// that one or two channels aren't a screen-wide slab. The strip is centered when it's narrower
    /// than the screen.
    static let maxBarWidth: CGFloat = 64

    var body: some View {
        // Reading the levels here makes this view, and only this one, redraw as they move.
        let meters = model.levels
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(meters.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    VStack(spacing: 2) {
                        // Shape as well as color: a triangle with an exclamation mark. The row is always there so
                        // a clip doesn't move the meters.
                        if notArmed.contains(index + 1), !clipped.contains(index) {
                            Image(systemName: "circle.slash").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(mode == .system ? Color.red : Color(Palette.meter(.red, mode: mode)))
                                .opacity(clipped.contains(index) ? 1 : 0)
                        }
                        MeterBar(meter: meters[index])
                            .frame(maxHeight: .infinity)
                            .opacity(dimming(index))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if clipped.contains(index) { clearClip(index) } }
                    .accessibilityElement(children: .ignore)
                    // The Source's name too, so a VoiceOver user hears "Level, USB Channel 1, Kick" (#249).
                    .accessibilityLabel(source(at: index).map { "Level, USB Channel \(index + 1), \($0.name)" } ?? "Level, USB Channel \(index + 1)")
                    // Coarse on purpose: the zone and any clip, not a dB number that changes every frame.
                    .accessibilityValue((notArmed.contains(index + 1) ? "Not armed. " : "") + meters[index].spoken(clipped: clipped.contains(index)))
                    .accessibilityAddTraits(clipped.contains(index) ? .isButton : [])
                    .accessibilityHint(clipped.contains(index) ? "Double tap to clear the clip mark" : "")
                    .accessibilityAction(named: notArmed.contains(index + 1) ? "Arm channel" : "Don't arm channel") {
                        armChannel?(index + 1, notArmed.contains(index + 1))
                    }
                    SourceLabel(
                        number: index + 1,
                        source: source(at: index),
                        compact: compact, showsName: !compact || meters.count <= 8,
                        reservesNameRow: anyNamed(count: meters.count))
                        .opacity(dimming(index))
                        .contentShape(Rectangle())
                        .onTapGesture { nameChannel(index + 1) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double tap to name this channel")
                }
                // A 44 pt touch zone at the foot of the lane (#240): the label is shorter than that, and making it
                // taller would take height from the meters. It clears a clip mark when there is one, else names.
                .overlay(alignment: .bottom) {
                    Color.clear
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture { if clipped.contains(index) { clearClip(index) } else { nameChannel(index + 1) } }
                        .accessibilityHidden(true)
                }
                // The lane's menu (a long press, over the whole lane including that foot): a tap is taken, it clears a clip mark (#991).
                .contextMenu {
                    if let armChannel {
                        let isArmed = !notArmed.contains(index + 1)
                        Button(isArmed ? "Don't arm channel \(index + 1)" : "Arm channel \(index + 1)", systemImage: isArmed ? "circle.slash" : "circle") {
                            armChannel(index + 1, !isArmed)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// A not-armed lane's meter and label are dimmed; the meter still moves (#991).
    private func dimming(_ index: Int) -> Double { notArmed.contains(index + 1) ? 0.45 : 1 }

    /// Whether any channel has a name to show. Then every lane keeps the same space for one, so a name under one
    /// meter never makes that meter shorter than the others.
    private func anyNamed(count: Int) -> Bool {
        (0..<count).contains { source(at: $0) != nil }
    }

    /// The Source to show for a channel: the typed name when there is one (with the Mixer's color, or none),
    /// else the Mixer's.
    private func source(at index: Int) -> Source? {
        let mixer = sources.indices.contains(index) ? sources[index] : nil
        guard let typed = typedNames[index + 1] else { return mixer }
        return Source(name: typed, color: mixer?.color ?? .off, hasMixerName: true)
    }

    /// Maps dBFS to 0...1 on a -60...0 scale.
    static func fraction(forDbfs dbfs: Double) -> Double {
        min(max((dbfs + 60) / 60, 0), 1)
    }
}

struct MeterBar: View {
    let meter: ChannelMeter
    @Environment(\.appearanceMode) private var mode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                // The target band behind the bar, with an edge line at each end so it shows on a light screen too.
                let bandTop = height * MeterGrid.fraction(forDbfs: MeterZone.bandHighDbfs)
                let bandBottom = height * MeterGrid.fraction(forDbfs: MeterZone.bandLowDbfs)
                Rectangle()
                    .fill(ink.opacity(0.14))
                    .frame(height: bandTop - bandBottom)
                    .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.55)).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.55)).frame(height: 1) }
                    .offset(y: -bandBottom)
                // The peak bar, as the old meter drew it. A bar only a pixel or two tall gets no outline, so a quiet
                // channel doesn't look like it has signal.
                let peakHeight = height * MeterGrid.fraction(forDbfs: Self.dbfs(ofLinear: meter.peakBar))
                RoundedRectangle(cornerRadius: 3)
                    .fill(peakBarColor)
                    .overlay { if peakHeight >= 4, let outline { RoundedRectangle(cornerRadius: 3).strokeBorder(outline, lineWidth: 1.5) } }
                    .frame(height: peakHeight)
                // The average, narrower and in front, with an edge so it never melts into the peak bar's color.
                let averageHeight = height * MeterGrid.fraction(forDbfs: meter.averageDbfs)
                RoundedRectangle(cornerRadius: 2)
                    .fill(averageColor)
                    .overlay { if averageHeight >= 4 { RoundedRectangle(cornerRadius: 2).strokeBorder(averageEdge, lineWidth: geometry.size.width < 14 ? 1 : 1.5) } }
                    .frame(width: geometry.size.width * 0.5, height: averageHeight)
                // The held peak: thicker as well as red when it's near clipping, so color isn't the only cue. In an
                // outlined meter it has a light core, so it still shows where it meets the bar's black edge.
                Rectangle()
                    .fill(meter.peakIsHot ? color(.red) : ink)
                    .overlay { if outline != nil, !meter.peakIsHot { Rectangle().fill(.white).frame(height: 1) } }
                    .frame(height: meter.peakIsHot ? 4 : (outline != nil ? 3 : 2))
                    .offset(y: -max(height * MeterGrid.fraction(forDbfs: meter.peakDbfs) - 1, 0))
                    .opacity(meter.peakDbfs <= VUMeter.floorDbfs ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(minWidth: 8, maxWidth: MeterGrid.maxBarWidth)
    }

    /// Text-colored ink for edges: black on a light screen, white on a dark one.
    private var ink: Color { mode == .system ? .primary : Color(Palette.primaryText(mode)) }

    /// The black edge on a light screen (Sunlight, or System in light mode), where a yellow bar has no edge of its own.
    private var outline: Color? {
        if let outline = Palette.meterOutline(mode) { return Color(outline) }
        return mode == .system && colorScheme == .light ? .black : nil
    }

    /// The average bar's edge: solid in Sunlight and light mode, softer in Dark where white lines on 18 lanes get busy.
    private var averageEdge: Color { mode == .dark ? ink.opacity(0.7) : ink }

    private static func dbfs(ofLinear level: Float) -> Double {
        level > 0 ? 20 * log10(Double(level)) : VUMeter.floorDbfs
    }

    private func color(_ color: Palette.MeterColor) -> Color {
        mode == .system ? systemColor(color) : Color(Palette.meter(color, mode: mode))
    }

    private func systemColor(_ color: Palette.MeterColor) -> Color {
        switch color {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .low: Color(red: 0.45, green: 0.58, blue: 0.72)
        case .orange: .orange
        }
    }

    private var peakBarColor: Color {
        switch meter.peakBarZone {
        case .green: color(.green)
        case .yellow: color(.yellow)
        case .red: color(.red)
        }
    }

    private var averageColor: Color {
        switch meter.zone {
        case .low: color(.low)
        case .onTarget: color(.green)
        case .hot: color(.orange)
        }
    }
}

/// The USB Channel number, and the Source's name on its Mixer color when known.
struct SourceLabel: View {
    let number: Int
    let source: Source?
    var compact = false
    var showsName = true
    /// Keep the name row's space even with no name, so every lane is the same height.
    var reservesNameRow = false

    private var nameHeight: CGFloat { compact ? 16 : 28 }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.caption2)
                .monospacedDigit()
                // One line always: a wrapped "10" would make that lane's meter shorter than the others.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .secondaryText()
            if let source {
                if showsName {
                    name(source.hasMixerName ? source.name : "–")
                        .font(.caption2.weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: MeterGrid.maxBarWidth, minHeight: nameHeight, maxHeight: nameHeight)
                        .foregroundStyle(source.color.inverted ? Color.black : source.color.swiftUIColor)
                        .background(source.color.inverted ? source.color.swiftUIColor : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(source.color.swiftUIColor.opacity(0.6)))
                } else {
                    // No room for the name: the Mixer's color for this channel, as a bar under the number.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(source.color.swiftUIColor)
                        .frame(maxWidth: MeterGrid.maxBarWidth, minHeight: 4, maxHeight: 4)
                }
            } else if showsName, reservesNameRow {
                Color.clear.frame(height: nameHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.map { "USB Channel \(number), \($0.name)" } ?? "USB Channel \(number)")
    }

    /// Whole words only: one line if it fits, else a word per line, else those lines shrunk or cut short.
    /// A two-line Text would break inside a word in a narrow lane ("Sna / re", #378).
    @ViewBuilder
    private func name(_ name: String) -> some View {
        if compact {
            Text(name).lineLimit(1)
        } else {
            ViewThatFits(in: .horizontal) {
                Text(name).lineLimit(1)
                lines(name)
            }
        }
    }

    private func lines(_ name: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(SourceNameLines.split(name).enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1)
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

#Preview("Name chips in narrow lanes") {
    let names = ["Snare", "Bass", "Keys 1", "Overhead 1", "Kick", "Lead Vox Left"]
    VStack(spacing: 24) {
        ForEach([22.0, 30.0, 44.0], id: \.self) { width in
            HStack(spacing: 2) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    SourceLabel(number: index + 1, source: Source(name: name, color: MixerColor(hue: .cyan, inverted: index.isMultiple(of: 2))))
                        .frame(width: width)
                }
            }
        }
    }
    .padding()
}
