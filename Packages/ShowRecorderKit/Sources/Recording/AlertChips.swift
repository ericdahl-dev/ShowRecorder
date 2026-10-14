extension ScreenAlert {
    /// Whether this alert is about the same problem as a status chip. Beside the landscape banner, only chips with
    /// another problem stay (#644).
    public func isAbout(_ kind: StatusChip.Kind) -> Bool {
        switch id {
        case "both-stopped": kind == .device || kind == .drive
        case "device-stopped": kind == .device
        case "drive-stopped", "no-drive": kind == .drive
        default: false
        }
    }

    /// Whether this alert is about the same problem as a battery or heat chip.
    public func isAbout(_ chip: PowerStatus.Chip) -> Bool {
        chip.id == id
    }
}
