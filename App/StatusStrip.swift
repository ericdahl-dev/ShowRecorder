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
                .accessibilityLabel(chip.text)
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
        case .failed: .white
        case .attention: .black
        case .ok: .primary
        case .neutral: .secondary
        }
    }

    private func background(_ state: StatusChip.State) -> Color {
        switch state {
        case .failed: Color(red: 0.70, green: 0.15, blue: 0.12)
        case .attention: Color(red: 1.0, green: 0.69, blue: 0.13)
        case .ok, .neutral: Color.primary.opacity(0.08)
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
                ForEach(queue.ordered) { alert in
                    AlertBanner(alert: alert, moreCount: 0, perform: perform) {}
                        .frame(height: Self.height)
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
    let perform: (ScreenAlert.Action) -> Void
    let showMore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(alert.text, systemImage: icon)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action = alert.action {
                Button(label(for: action)) { perform(action) }
                    .buttonStyle(.bordered)
                    .tint(foreground)
            }
            if moreCount > 0 {
                Button("+\(moreCount) more", action: showMore)
                    .font(.callout.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .underline()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
    }

    private func label(for action: ScreenAlert.Action) -> String {
        switch action {
        case .openSystemSettings: "Open Settings"
        case .dismissHint: "Got it"
        }
    }

    private var icon: String {
        switch alert.tone {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var foreground: Color {
        alert.tone == .warning ? .black : .white
    }

    private var background: Color {
        switch alert.tone {
        case .critical: Color(red: 0.70, green: 0.15, blue: 0.12)
        case .warning: Color(red: 1.0, green: 0.69, blue: 0.13)
        case .ok: Color(red: 0.12, green: 0.42, blue: 0.23)
        case .info: Color(red: 0.20, green: 0.30, blue: 0.55)
        }
    }
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
