import Recording
import SwiftUI

/// One line of chips on the record screen: Device and Drive time left, and the Mixer Link. Ok states
/// are quiet; a problem fills its chip. Every chip has an icon and words, so none relies on color.
struct StatusStrip: View {
    let chips: [StatusChip]
    /// Battery, heat and Dropouts, after the Destination and Mixer chips. Display only.
    var extras: [PowerStatus.Chip] = []
    /// Landscape iPhone: shorter text, so three chips fit beside the header.
    var compact = false
    let tap: (StatusChip.Kind) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.appearanceMode) private var mode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                Button { tap(chip.kind) } label: {
                    // The full text if it fits, else the short one, else the short one scaled down.
                    ViewThatFits(in: .horizontal) {
                        if !compact { chipLabel(chip, text: chip.text).fixedSize(horizontal: true, vertical: false) }
                        chipLabel(chip, text: chip.shortText).fixedSize(horizontal: true, vertical: false)
                        chipLabel(chip, text: chip.shortText).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(foreground(chip.state))
                    .background(background(chip.state), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip.detail.map { "\(chip.text), \($0)" } ?? chip.text)
            }
            ForEach(extras, id: \.symbol) { chip in
                Label(chip.shortText, systemImage: chip.symbol)
                    .labelStyle(StripLabelStyle(iconOnly: typeSize.isAccessibilitySize))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .foregroundStyle(foreground(chip.state))
                    .background(background(chip.state), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chip.text)
            }
        }
    }

    /// At the largest text sizes the chip keeps its icon and drops the words (VoiceOver still has them).
    private func chipLabel(_ chip: StatusChip, text: String) -> some View {
        Label(text, systemImage: icon(for: chip))
            .labelStyle(StripLabelStyle(iconOnly: typeSize.isAccessibilitySize))
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
    }

    private func icon(for chip: StatusChip) -> String {
        switch (chip.kind, chip.state) {
        case (_, .failed): "xmark.octagon.fill"
        case (_, .attention): "exclamationmark.triangle.fill"
        case (.device, _): "internaldrive"
        case (.drive, _): "externaldrive"
        case (.mixer, _): "slider.vertical.3"
        }
    }

    private func foreground(_ state: StatusChip.State) -> Color {
        switch state {
        case .failed: Color(Palette.pair(for: .chipFailed, mode: mode).text)
        case .attention: Color(Palette.pair(for: .chipAttention, mode: mode).text)
        case .ok: mode == .system ? .primary : Color(Palette.primaryText(mode))
        case .neutral: mode == .system ? .secondary : Color(Palette.secondaryText(mode))
        }
    }

    private func background(_ state: StatusChip.State) -> Color {
        switch state {
        case .failed: Color(Palette.pair(for: .chipFailed, mode: mode).fill)
        case .attention: Color(Palette.pair(for: .chipAttention, mode: mode).fill)
        case .ok, .neutral: Color.primary.opacity(mode == .sunlight ? 0.12 : 0.08)
        }
    }
}

/// The record screen's one place for alerts: the most urgent at full size, a count of the rest. It has
/// a fixed height, so an alert appearing never moves the meters or the transport.
struct AlertSlot: View {
    let queue: AlertQueue
    let perform: (ScreenAlert.Action) -> Void
    @State private var listing = false

    static let height: CGFloat = 56
    /// Portrait keeps `height`; landscape overlays a shorter slot.
    var slotHeight: CGFloat = AlertSlot.height

    var body: some View {
        Group {
            if let alert = queue.top {
                AlertBanner(alert: alert, moreCount: queue.moreCount, perform: perform) { listing = true }
            } else {
                Color.clear
            }
        }
        .frame(height: slotHeight)
        .popover(isPresented: $listing) {
            VStack(spacing: 8) {
                // Here every alert is shown in full (#292): the slot's 2 lines can cut a long one off.
                ForEach(queue.ordered) { alert in
                    AlertBanner(alert: alert, moreCount: 0, inFull: true, perform: perform) {}
                        .frame(minHeight: Self.height)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.sheet)
        }
    }
}

/// A banner with solid fill and high-contrast text; tinted-on-tint fails in sunlight.
struct AlertBanner: View {
    let alert: ScreenAlert
    let moreCount: Int
    /// In the list of every alert: the whole text, however many lines. In the slot: 2 lines, and a tap shows the list.
    var inFull = false
    let perform: (ScreenAlert.Action) -> Void
    let showMore: () -> Void
    @Environment(\.appearanceMode) private var mode

    var body: some View {
        HStack(spacing: 8) {
            if inFull {
                text
                    .padding(.vertical, 10)
            } else {
                // The whole height of the banner, not just the text's line, so it is easy to hit.
                Button(action: showMore) { text.frame(maxHeight: .infinity, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the whole message")
            }
            if let action = alert.action {
                // The bezel adds about 7 pt above and below: 30 inside makes a 44 pt button, inside the slot.
                Button { perform(action) } label: { Text(action.title).frame(minHeight: 30) }
                    .buttonStyle(.bordered)
                    .tint(foreground)
            }
            if moreCount > 0 {
                Button(action: showMore) { Text("+\(moreCount) more").underline().tapTarget() }
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var text: some View {
        Label(alert.text, systemImage: icon)
            .font(.callout.weight(.medium))
            .lineLimit(inFull ? nil : 2)
            .minimumScaleFactor(inFull ? 1 : 0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }


    private var icon: String {
        switch alert.tone {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var element: Palette.Element {
        switch alert.tone {
        case .critical: .alertCritical
        case .warning: .alertWarning
        case .ok: .alertOk
        case .info: .alertInfo
        }
    }

    private var foreground: Color { Color(Palette.pair(for: element, mode: mode).text) }
    private var background: Color { Color(Palette.pair(for: element, mode: mode).fill) }
}

/// Icon and text side by side, or the icon alone at accessibility text sizes.
private struct StripLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}

extension ScreenAlert.Action {
    /// The button's words, the same in the alert banner and the disarmed record screen.
    var title: String {
        switch self {
        case .openSystemSettings: "Open Settings"
        case .dismissHint: "Got it"
        case .checkDrive: "Check Drive"
        case .arm: "Arm"
        case .soundcheck: "Soundcheck"
        case .dismissRoutingChange: "Got it"
        }
    }
}

/// Fills the empty meter region while nothing is Armed: why, and the one thing to do about it (#253).
struct DisarmedNotice: View {
    let block: RecordAvailability.Block
    let perform: (ScreenAlert.Action) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.largeTitle)
                .secondaryText()
            Text(block.text)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action = block.action {
                Button { perform(action) } label: { Text(action.title).frame(minHeight: 30) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: 320)
        .accessibilityElement(children: .combine)
    }
}
