@testable import Recording
import Testing

/// Every feature that ships hidden names one of three levels (#557, CLAUDE.md): Debug only, Debug + TestFlight, or everyone.
/// Moving a feature up is its one `level` line; this table is the place that shows where each one stands.
@Suite("Availability levels")
struct AvailabilityLevelTests {
    static let environments: [DistributionEnvironment?] = [nil, .unknown, .sandbox, .production]

    @Test("Debug only: Debug builds, whatever the environment; no Release build")
    func debugOnly() {
        for environment in Self.environments {
            #expect(AvailabilityLevel.debugOnly.isOn(isDebugBuild: true, environment: environment))
            #expect(!AvailabilityLevel.debugOnly.isOn(isDebugBuild: false, environment: environment))
        }
    }

    @Test("Debug + TestFlight: Debug builds and a TestFlight (sandbox) answer; not the App Store, not an answer that hasn't come")
    func debugAndTestFlight() {
        let level = AvailabilityLevel.debugAndTestFlight
        for environment in Self.environments { #expect(level.isOn(isDebugBuild: true, environment: environment)) }
        #expect(level.isOn(isDebugBuild: false, environment: .sandbox))
        for environment: DistributionEnvironment? in [nil, .unknown, .production] {
            #expect(!level.isOn(isDebugBuild: false, environment: environment))
        }
    }

    @Test("Everyone: every build")
    func everyone() {
        for isDebugBuild in [true, false] {
            for environment in Self.environments { #expect(AvailabilityLevel.everyone.isOn(isDebugBuild: isDebugBuild, environment: environment)) }
        }
    }

    struct Feature: Sendable {
        var name: String
        /// Where it stands today; moving a feature up changes this row and its `level`.
        var expected: AvailabilityLevel
        var level: AvailabilityLevel
        var isAvailable: @Sendable (Bool, DistributionEnvironment?) -> Bool
    }

    /// Where every hidden feature stands today.
    static let features: [Feature] = [
        .init(name: "Auto-gain", expected: .debugAndTestFlight, level: AutoGainAvailability.level, isAvailable: { AutoGainAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Clip protection", expected: .debugAndTestFlight, level: ClipProtectionSetting.level, isAvailable: { ClipProtectionSetting.isOffered(isDebugBuild: $0, environment: $1) }),
        .init(name: "Demo mixer family", expected: .debugAndTestFlight, level: DemoMixerFamilyAvailability.level, isAvailable: { DemoMixerFamilyAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Demo signal", expected: .debugAndTestFlight, level: DemoSignalAvailability.level, isAvailable: { DemoSignalAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Delete from iPhone", expected: .debugOnly, level: DeviceTakeDeleteAvailability.level, isAvailable: { DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Drive only", expected: .debugAndTestFlight, level: DriveOnlyAvailability.level, isAvailable: { DriveOnlyAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Hold to stop", expected: .debugAndTestFlight, level: HoldToStopAvailability.level, isAvailable: { HoldToStopAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Marker button", expected: .debugAndTestFlight, level: MarkerButtonAvailability.level, isAvailable: { MarkerButtonAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "No-signal warning", expected: .debugAndTestFlight, level: NoSignalWarningAvailability.level, isAvailable: { NoSignalWarningAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Record to", expected: .debugAndTestFlight, level: RecordToAvailability.level, isAvailable: { RecordToAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Asynchronous Stop", expected: .debugOnly, level: AsyncStopAvailability.level, isAvailable: { AsyncStopAvailability.isAvailable(isDebugBuild: $0, environment: $1) }),
        .init(name: "Mixer packs", expected: .debugOnly, level: PackAvailability.level, isAvailable: { isDebug, _ in PackAvailability.isAvailable(isDebugBuild: isDebug) }),
        .init(name: "Drive speed test", expected: .debugOnly, level: DriveSpeedTestAvailability.level, isAvailable: { isDebug, _ in DriveSpeedTestAvailability.isAvailable(isDebugBuild: isDebug) })
    ]

    @Test("Each feature's level today")
    func levels() {
        for feature in Self.features { #expect(feature.level == feature.expected, "\(feature.name)") }
    }

    @Test("Each feature answers as its level does, in every build and environment")
    func featuresFollowTheirLevel() {
        for feature in Self.features {
            for isDebugBuild in [true, false] {
                for environment in Self.environments {
                    #expect(feature.isAvailable(isDebugBuild, environment) == feature.level.isOn(isDebugBuild: isDebugBuild, environment: environment), "\(feature.name)")
                }
            }
        }
    }
}
