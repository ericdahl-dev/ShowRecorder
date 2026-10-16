/// Where the asynchronous Stop (#652, part A) is used: Debug builds only, until Eric has tried it on a device and it
/// moves up a level (its own one-line PR). In A3a nothing reads the answer for behavior yet; A3b is what finishes a
/// Take off the main actor when it is on.
public enum AsyncStopAvailability {
    public static func isAvailable(isDebugBuild: Bool) -> Bool {
        isDebugBuild
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isAvailable(isDebugBuild: isDebugBuild)
    }
}
