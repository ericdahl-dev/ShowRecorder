/// Where "Record to the Drive only" (#196, ADR 0006) is offered: Debug builds only, until it has passed Eric's rig test
/// (pull the Drive mid-Take). Hidden in TestFlight and the App Store; opening it up is this one rule.
public enum DriveOnlyAvailability {
    public static func isAvailable(isDebugBuild: Bool = LaunchFlags.isDebugBuild) -> Bool {
        isDebugBuild
    }
}
