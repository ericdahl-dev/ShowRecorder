import Foundation

/// Where the Demo signal input is offered: Debug builds, and TestFlight builds, so a tester
/// without a mixer can still record a Take. The App Store build never offers it.
public enum DemoSignalAvailability {
    /// TestFlight builds carry a receipt named `sandboxReceipt`; App Store builds carry `receipt`.
    public static func isAvailable(isDebugBuild: Bool, receiptFileName: String?) -> Bool {
        isDebugBuild || receiptFileName == "sandboxReceipt"
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isAvailable(isDebugBuild: isDebugBuild, receiptFileName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }
}
