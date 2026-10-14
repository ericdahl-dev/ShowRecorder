import Foundation
import MixerLink
@testable import Recording
import Testing

/// Who sees auto-gain (#155) and clip protection (#448), and why auto-gain can't run (#554, PR 10). One table of
/// literal answers, for each build kind and each Mixer session state. Debug builds only for now (Eric, 2026-10-12):
/// TestFlight and App Store builds are Release builds, so neither feature shows there.
@MainActor
@Suite("Mixer gain: availability and the offer")
struct MixerGainAvailabilityTests {
    enum Build: String, CaseIterable {
        case debug, testFlight, appStore
        var isDebugBuild: Bool { self == .debug }
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

    // MARK: Today's rules, as RecordScreenModel composes them (offersAutoGain, autoGainUnavailable, and MixerGain's
    // isClipProtectionOn default), so the table is checked against today before MixerGain answers it.

    static func todayOffersAutoGain(_ mixer: MixerSession, isDebugBuild: Bool) -> Bool {
        AutoGainAvailability.isOffered(available: AutoGainAvailability.isAvailable(isDebugBuild: isDebugBuild),
                                       mixerLinkOffered: mixer.isOffered)
    }

    static func todayAutoGainUnavailable(_ mixer: MixerSession, isRecording: Bool) -> AutoGainAvailability.Unavailable? {
        let isConnecting = if case .connecting = mixer.status { true } else { false }
        return AutoGainAvailability.whyNot(hasMixerLink: mixer.identity != nil, isConnecting: isConnecting,
                                           canSetGain: mixer.gainControl != nil, isRecording: isRecording,
                                           otherMixer: mixer.otherMixerLinked?.nameAndModel)
    }

    static func todayClipProtectionOn(isDebugBuild: Bool, defaults: UserDefaults) -> Bool {
        ClipProtectionSetting.isOffered(isDebugBuild: isDebugBuild) && ClipProtectionSetting.isOn(in: defaults)
    }

    @Test("Today: the Gain button shows only in Debug builds, while an X Air or X32 is Armed, and says why it can't run",
          arguments: table)
    func todayAutoGain(build: Build, scenario: Scenario) async throws {
        let (mixer, release) = try await scenario.session()
        defer { release() }

        #expect(Self.todayOffersAutoGain(mixer, isDebugBuild: build.isDebugBuild) == (build == .debug && scenario.offeredInDebug))
        #expect(Self.todayAutoGainUnavailable(mixer, isRecording: scenario.isRecording) == scenario.whyNot)
    }

    @Test("Today: clip protection is offered, and on when switched on, only in Debug builds", arguments: Build.allCases)
    func todayClipProtection(build: Build) {
        let defaults = UserDefaults(suiteName: "MixerGainAvailabilityTests-\(UUID().uuidString)")!
        #expect(!Self.todayClipProtectionOn(isDebugBuild: build.isDebugBuild, defaults: defaults), "off by default")
        ClipProtectionSetting.save(true, to: defaults)
        #expect(Self.todayClipProtectionOn(isDebugBuild: build.isDebugBuild, defaults: defaults) == (build == .debug))
    }

    // MARK: Mixer gain answers the same table from its inputs.

    @Test("Mixer gain: the Gain button shows only in Debug builds, while an X Air or X32 is Armed, and says why it can't run",
          arguments: table)
    func mixerGainAutoGain(build: Build, scenario: Scenario) async throws {
        let (mixer, release) = try await scenario.session()
        defer { release() }
        let mixerGain = MixerGain()
        mixerGain.mixer = mixer
        mixerGain.isDebugBuild = build.isDebugBuild
        mixerGain.isRecording = { scenario.isRecording }

        #expect(mixerGain.offersAutoGain == (build == .debug && scenario.offeredInDebug))
        #expect(mixerGain.autoGainUnavailable == scenario.whyNot)
    }

    @Test("Mixer gain: no Mixer session, so no Gain button and no Mixer Link", arguments: Build.allCases)
    func mixerGainWithoutASession(build: Build) {
        let mixerGain = MixerGain()
        mixerGain.isDebugBuild = build.isDebugBuild

        #expect(!mixerGain.offersAutoGain)
        #expect(mixerGain.autoGainUnavailable == .noMixerLink)
    }

    @Test("Mixer gain: clip protection is offered, and protects a Take when switched on, only in Debug builds",
          arguments: Build.allCases)
    func mixerGainClipProtection(build: Build) {
        let mixerGain = MixerGain()
        mixerGain.isDebugBuild = build.isDebugBuild
        let control = FakeGainControl(gainDb: [1: 30], channelOfUSB: [1: 1])
        mixerGain.makeProtection = { queue in ClipProtection(control: control, sampleRate: 48_000, queue: queue) }
        mixerGain.isClipProtectionOn = { true }

        #expect(mixerGain.offersClipProtection == (build == .debug))
        mixerGain.handle(.takeStarted(take: 1))
        #expect((mixerGain.protection != nil) == (build == .debug))
        mixerGain.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }
}
