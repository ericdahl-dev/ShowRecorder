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
    /// Beside the landscape banner (#644): each chip a 44 pt square with its icon alone.
    var iconOnly = false
    let tap: (StatusChip.Kind) -> Void
    /// The Trial chip's tap (#743); without it the chip is display only, like battery and heat.
    var tapTrial: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.appearanceMode) private var mode

    /// How much the strip gives up to fit, in the order it gives it up (#744): the quiet extras (healthy battery, Warm,
    /// the Trial) lose their words first, then the chips use their short text, then every extra is its icon alone.
    /// The Drive and any problem keep their words throughout.
    private enum Squeeze { case none, quietExtras, shortChips, allExtras }

    var body: some View {
        if iconOnly {
            row(.allExtras)
        } else {
            ViewThatFits(in: .horizontal) {
                row(.none)
                row(.quietExtras)
                row(.shortChips)
                row(.allExtras)
            }
        }
    }

    private func row(_ squeeze: Squeeze) -> some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                Button { tap(chip.kind) } label: {
                    chipContent(chip, squeeze)
                        .padding(.horizontal, iconOnly ? 0 : 10)
                        .frame(minWidth: iconOnly ? 44 : nil, minHeight: 44)
                        .frame(maxWidth: iconOnly ? nil : .infinity)
                        .foregroundStyle(foreground(chip.state))
                        .background(background(chip.state), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip.detail.map { "\(chip.text), \($0)" } ?? chip.text)
            }
            ForEach(extras, id: \.symbol) { chip in
                let icon = squeeze == .allExtras || (squeeze != .none && chip.isQuiet)
                if chip.id == Tier.chipID, let tapTrial {
                    Button(action: tapTrial) { extraLabel(chip, iconOnly: icon) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows what the Trial includes and when it ends")
                } else {
                    extraLabel(chip, iconOnly: icon)
                }
            }
        }
    }

    /// The Drive and a problem never shrink below their words, so a warning is always readable; the other chips
    /// (the Device's time left, the Mixer's name) give way when the room runs out.
    @ViewBuilder
    private func chipContent(_ chip: StatusChip, _ squeeze: Squeeze) -> some View {
        let pinned = chip.kind == .drive || chip.state == .attention || chip.state == .failed
        switch squeeze {
        case .none, .quietExtras:
            // The full text if it fits, else the short one.
            chipLabel(chip, text: compact ? chip.shortText : chip.text).fixedSize(horizontal: true, vertical: false)
        case .shortChips:
            chipLabel(chip, text: chip.shortText).fixedSize(horizontal: true, vertical: false)
        case .allExtras:
            if pinned {
                chipLabel(chip, text: chip.shortText).fixedSize(horizontal: true, vertical: false)
            } else {
                ViewThatFits(in: .horizontal) {
                    chipLabel(chip, text: chip.shortText).fixedSize(horizontal: true, vertical: false)
                    chipLabel(chip, text: chip.shortText).minimumScaleFactor(0.6)
                }
            }
        }
    }

    private func extraLabel(_ chip: PowerStatus.Chip, iconOnly icon: Bool) -> some View {
        let iconOnly = iconOnly || icon
        return Label(chip.shortText, systemImage: chip.symbol)
            .labelStyle(StripLabelStyle(iconOnly: iconOnly || typeSize.isAccessibilitySize))
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, iconOnly ? 0 : 10)
            .frame(minWidth: iconOnly ? 44 : nil, minHeight: 44)
            .foregroundStyle(foreground(chip.state))
            .background(background(chip.state), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chip.text)
    }

    /// At the largest text sizes the chip keeps its icon and drops the words (VoiceOver still has them).
    private func chipLabel(_ chip: StatusChip, text: String) -> some View {
        Label(text, systemImage: icon(for: chip))
            .labelStyle(StripLabelStyle(iconOnly: iconOnly || typeSize.isAccessibilitySize))
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
    /// Portrait keeps `height`; landscape's top row has a shorter slot.
    var slotHeight: CGFloat = AlertSlot.height
    /// The banner's lines of text: 1 in landscape's top row.
    var lines = 2
    /// Swiping a warning away (#644). A critical alert can't be swiped.
    var swipe: ((ScreenAlert) -> Void)?
    /// The finger's sideways drag; back to 0 when the drag ends or is canceled.
    @GestureState(resetTransaction: Transaction(animation: .default)) private var dragX: CGFloat = 0
    /// The slide off once the swipe is far enough.
    @State private var flyOffX: CGFloat = 0

    var body: some View {
        Group {
            if let alert = queue.top {
                let swipeable = swipe != nil && SwipedAlerts.isSwipeable(alert)
                AlertBanner(alert: alert, moreCount: queue.moreCount, lines: lines, perform: perform) { listing = true }
                    .offset(x: dragX + flyOffX)
                    .gesture(swipeAway(alert), including: swipeable ? .all : .subviews)
                    .accessibilityActions {
                        if swipeable { Button("Dismiss") { swipe?(alert) } }
                    }
            } else {
                Color.clear
            }
        }
        .frame(height: slotHeight)
        .onChange(of: queue.top?.id) { flyOffX = 0 }
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

    /// Past 80 pt sideways the banner slides off and the warning is swiped; short of it, it springs back.
    private func swipeAway(_ alert: ScreenAlert) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($dragX) { drag, x, _ in
                if abs(drag.translation.width) > abs(drag.translation.height) { x = drag.translation.width }
            }
            .onEnded { drag in
                let x = drag.translation.width
                guard abs(x) > 80, abs(x) > abs(drag.translation.height) else { return }
                flyOffX = x
                withAnimation(.easeOut(duration: 0.2)) {
                    flyOffX = x > 0 ? 1000 : -1000
                } completion: {
                    swipe?(alert)
                    flyOffX = 0
                }
            }
    }
}

/// Landscape's top row (#644): the chips, or while a warning or critical alert is up, its banner in their place, so
/// nothing covers the meters. A chip showing another problem stays beside the banner as its icon. The row swaps with a
/// cross-fade, and an alert once shown stays at least `AlertHold.minimum`, so a flickering problem doesn't flicker it.
struct LandscapeAlertRow: View {
    let alerts: AlertQueue
    let chips: [StatusChip]
    let extras: [PowerStatus.Chip]
    let perform: (ScreenAlert.Action) -> Void
    let swipe: (ScreenAlert) -> Void
    let tap: (StatusChip.Kind) -> Void
    var tapTrial: (() -> Void)?
    @State private var hold = AlertHold()
    @State private var shown: ScreenAlert?

    private var urgent: AlertQueue { AlertQueue(alerts.ordered.filter { $0.tone == .critical || $0.tone == .warning }) }

    var body: some View {
        ZStack {
            if let shown {
                HStack(spacing: 8) {
                    AlertSlot(queue: urgent.top == nil ? AlertQueue([shown]) : urgent, perform: perform, slotHeight: 44, lines: 1) { alert in
                        hold.release()
                        self.shown = nil
                        swipe(alert)
                    }
                    StatusStrip(
                        chips: chips.filter { $0.state.isProblem && !shown.isAbout($0.kind) },
                        extras: extras.filter { $0.state.isProblem && !shown.isAbout($0) },
                        iconOnly: true, tap: tap, tapTrial: tapTrial)
                }
                .transition(.opacity)
            } else {
                StatusStrip(chips: chips, extras: extras, compact: true, tap: tap, tapTrial: tapTrial)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shown?.id)
        .task(id: urgent.top) {
            shown = hold.update(urgent.top, at: .now)
            // Cleared while held: look again once the hold is over. A change cancels the wait.
            guard shown != nil, urgent.top == nil,
                  (try? await Task.sleep(for: .seconds(hold.remaining(at: .now)))) != nil else { return }
            shown = hold.update(urgent.top, at: .now)
        }
    }
}

private extension StatusChip.State {
    var isProblem: Bool { self == .attention || self == .failed }
}

/// A banner with solid fill and high-contrast text; tinted-on-tint fails in sunlight.
struct AlertBanner: View {
    let alert: ScreenAlert
    let moreCount: Int
    /// In the list of every alert: the whole text, however many lines. In the slot: 2 lines, and a tap shows the list.
    var inFull = false
    /// The slot's lines of text; one line never shrinks.
    var lines = 2
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
            .lineLimit(inFull ? nil : lines)
            .minimumScaleFactor(inFull || lines == 1 ? 1 : 0.8)
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
        case .showMoves: "Details"
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

/// Drive only (#630): each Take the latest move to the Drive took up, and why one stays on this iPhone.
struct MoveReportSheet: View {
    let recorder: Recorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(recorder.moveReport.entries) { entry in
                // A kept Take's row is where a way to delete it from this iPhone goes (#656).
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.headline)
                    if entry.status == .kept {
                        Text(entry.statusText).warningText()
                    } else {
                        Text(entry.statusText).secondaryText()
                    }
                    ForEach(entry.reasons, id: \.self) { reason in
                        Text(reason).font(.footnote).secondaryText()
                    }
                }
            }
            .navigationTitle("Moving to the Drive")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
