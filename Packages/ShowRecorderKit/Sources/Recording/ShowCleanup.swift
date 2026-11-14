import Foundation

/// The Shows list's Select mode (#1217): picking several Shows to delete at once, to free space on the Device.
public enum ShowCleanup {
    /// The bytes the Show's Device copy holds; 0 when it has none.
    public static func deviceBytes(of show: ShowSummary) -> Int64 {
        guard show.deviceCopy != nil,
              let files = FileManager.default.enumerator(at: show.folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    /// The Shows that can be picked: all but the open Show, which is ended and deleted only from its own sheet.
    public static func selectable(_ shows: [ShowSummary], openShow: String?) -> [ShowSummary] {
        shows.filter { $0.name != openShow }
    }

    /// "Select empty": the Shows with no Takes left, such as ones whose files were removed in Files.
    public static func empty(_ shows: [ShowSummary], openShow: String?) -> Set<String> {
        Set(selectable(shows, openShow: openShow).filter { $0.takeCount == 0 }.map(\.name))
    }
}
