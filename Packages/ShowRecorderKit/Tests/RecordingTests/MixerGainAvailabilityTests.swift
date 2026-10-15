import Foundation
import MixerLink
@testable import Recording
import Testing

/// Who sees auto-gain (#155) and clip protection (#448), and why auto-gain can't run (#554, PR 10). One table of
/// literal answers, for each build kind and each Mixer session state. Auto-gain: Debug and TestFlight builds (Eric,
/// 2026-10-14, after his live XR18 test); never the App Store. Clip protection: Debug builds only, until its own live test.
@MainActor
@Suite("Mixer gain: availability and the offer")
struct MixerGainAvailabilityTests {
    enum Build: String, CaseIterable {
        /// `releaseBeforeStoreKit`: a TestFlight or App Store build whose StoreKit answer hasn't arrived yet.
        case debug, testFlight, appStore, releaseBeforeStoreKit
        var isDebugBuild: Bool { self == .debug }
        /// What StoreKit says the build came through: TestFlight is the sandbox, the App Store production; a Debug build
        /// run from Xcode has no App Store environment.
        var environment: DistributionEnvironment? {
            switch self {
            case .debug: .unknown
            case .testFlight: .sandbox
            case .appStore: .production
            case .releaseBeforeStoreKit: nil
            }
        }
        var seesAutoGain: Bool { self == .debug || self == .testFlight }
        var seesClipProtection: Bool { self == .debug }
    }

    /// The Mixer session and recorder states the record screen meets.
    enum Scenario: String, CaseIterable {
        case nothingArmed, evo4Armed, xr18ArmedNoLink, xr18Connecting, xr18Linked, xr18LinkedRecording, xr18LinkedNoGain,
             x32ArmedXR18Linked

        var isRecording: Bool { self == .xr18LinkedRecording }

        /// Whether the Gain button shows in a Debug build: while an X Air or X32 is Armed.
        var offeredInDebug: Bool {
            switch self {
            case .nothingArmed, .evo4Armed: false
            default: true
            }
        }

        /// Why auto-gain can't run; nil when it can.
        var whyNot: AutoGainAvailability.Unavailable? {
            switch self {
            case .nothingArmed, .evo4Armed, .xr18ArmedNoLink: .noMixerLink
            case .xr18Connecting: .connecting
            case .xr18Linked: nil
            case .xr18LinkedRecording: .takeRunning
            case .xr18LinkedNoGain: .cantSetGain
            case .x32ArmedXR18Linked: .otherMixerLinked("FOH (XR18)")
            }
        }

        /// A session in this state. `release` lets a held Mixer answer; call it when done.
        @MainActor func session() async throws -> (MixerSession, release: () -> Void) {
            let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
            let driver = LinkedMixerDriver(gainControl: self == .xr18LinkedNoGain ? nil : control,
                                           holdsIdentify: self == .xr18Connecting)
            let link = MixerLinkController(makeDriver: { _, _ in driver })
            let store = UserDefaults(suiteName: "MixerGainAvailabilityTests-\(UUID().uuidString)")!
            let session = MixerSession(link: link, store: store)
            switch self {
            case .nothingArmed:
                break
            case .evo4Armed:
                await session.armed(interfaceName: "EVO 4", usbChannelCount: 2)
            case .xr18ArmedNoLink:
                await session.armed(interfaceName: "XR18", usbChannelCount: 18)
            case .xr18Connecting:
                await session.armed(interfaceName: "XR18", usbChannelCount: 18)
                Task { await link.connect(to: "10.0.0.20", usbChannelCount: 18) }
                do {
                    try await waitUntil { if case .connecting = link.status { true } else { false } }
                } catch {
                    driver.release()
                    throw error
                }
            case .xr18Linked, .xr18LinkedRecording, .xr18LinkedNoGain:
                await session.armed(interfaceName: "XR18", usbChannelCount: 18)
                await link.connect(to: "10.0.0.20", usbChannelCount: 18)
            case .x32ArmedXR18Linked:
                await session.armed(interfaceName: "XR18", usbChannelCount: 18)
                await link.connect(to: "10.0.0.20", usbChannelCount: 18)
                await session.armed(interfaceName: "X-USB", usbChannelCount: 32)
            }
            return (session, driver.release)
        }
    }

    nonisolated static let table: [(Build, Scenario)] = Build.allCases.flatMap { build in Scenario.allCases.map { (build, $0) } }

    @Test("Who sees what: auto-gain in Debug and TestFlight, clip protection in Debug only, neither in the App Store",
          arguments: Build.allCases)
    func whoSeesWhat(build: Build) {
        let expected: [Build: (autoGain: Bool, clipProtection: Bool)] =
            [.debug: (true, true), .testFlight: (true, false), .appStore: (false, false), .releaseBeforeStoreKit: (false, false)]
        let mixerGain = MixerGain()
        mixerGain.isDebugBuild = build.isDebugBuild
        mixerGain.environment = { build.environment }

        #expect(AutoGainAvailability.isAvailable(isDebugBuild: build.isDebugBuild, environment: build.environment)
                == expected[build]!.autoGain)
        #expect(mixerGain.offersClipProtection == expected[build]!.clipProtection)
    }

    // MARK: Mixer gain answers the same table from its inputs.

    @Test("Mixer gain: the Gain button shows in Debug and TestFlight builds, while an X Air or X32 is Armed, and says why it can't run",
          arguments: table)
    func mixerGainAutoGain(build: Build, scenario: Scenario) async throws {
        let (mixer, release) = try await scenario.session()
        defer { release() }
        let mixerGain = MixerGain()
        mixerGain.mixer = mixer
        mixerGain.isDebugBuild = build.isDebugBuild
        mixerGain.environment = { build.environment }
        mixerGain.isRecording = { scenario.isRecording }

        #expect(mixerGain.offersAutoGain == (build.seesAutoGain && scenario.offeredInDebug))
        #expect(mixerGain.autoGainUnavailable == scenario.whyNot)
    }

    @Test("Mixer gain: no Mixer session, so no Gain button and no Mixer Link", arguments: Build.allCases)
    func mixerGainWithoutASession(build: Build) {
        let mixerGain = MixerGain()
        mixerGain.isDebugBuild = build.isDebugBuild
        mixerGain.environment = { build.environment }

        #expect(!mixerGain.offersAutoGain)
        #expect(mixerGain.autoGainUnavailable == .noMixerLink)
    }

    @Test("Mixer gain: clip protection is offered, and protects a Take when switched on, only in Debug builds",
          arguments: Build.allCases)
    func mixerGainClipProtection(build: Build) {
        let mixerGain = MixerGain()
        mixerGain.isDebugBuild = build.isDebugBuild
        mixerGain.environment = { build.environment }
        let control = FakeGainControl(gainDb: [1: 30], channelOfUSB: [1: 1])
        mixerGain.makeProtection = { queue in ClipProtection(control: control, sampleRate: 48_000, queue: queue) }
        mixerGain.isClipProtectionOn = { true }

        #expect(mixerGain.offersClipProtection == build.seesClipProtection)
        mixerGain.handle(.takeStarted(take: 1))
        #expect((mixerGain.protection != nil) == build.seesClipProtection)
        mixerGain.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }
}
