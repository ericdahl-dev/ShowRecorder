import Foundation
@testable import Recording
import Testing

/// "Record to" (#805): one setting for where a Take goes, the Device, the Drive or Both, read at the record press.
@Suite("Record to")
struct RecordToTests {
    @Test("The default is Both (#805)")
    func defaultIsBoth() {
        #expect(RecordTo.standard == .both)
    }

    /// A defaults store that is thrown away with the test.
    func defaults() -> UserDefaults {
        let name = "RecordToTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test("What was saved is read back, for each choice (#805)")
    func roundTrip() {
        let store = defaults()
        for choice in RecordTo.allCases {
            RecordToSetting.save(choice, to: store)
            #expect(RecordToSetting.load(from: store) == choice)
        }
    }

    @Test("Unset, or a stored value that isn't a choice, reads as the default (#805)")
    func unsetOrUnknown() {
        let store = defaults()
        #expect(RecordToSetting.load(from: store) == .both)
        store.set("cloud", forKey: RecordToSetting.key)
        #expect(RecordToSetting.load(from: store) == .both)
        store.set(3, forKey: RecordToSetting.key)
        #expect(RecordToSetting.load(from: store) == .both)
    }

    @Test("Where it isn't offered, every choice records as today: the Device, and the Drive when there is one and it's Pro (#805)")
    func notOffered() {
        for choice in RecordTo.allCases {
            #expect(choice.atPress(isOffered: false, driveAllowed: true) == .both)
            #expect(choice.atPress(isOffered: false, driveAllowed: false) == .device, "Free never gets the Drive")
        }
    }

    @Test("Where it is offered, Free records every choice to the Device only: the Drive is Pro (#805)")
    func free() {
        for choice in RecordTo.allCases {
            #expect(choice.atPress(isOffered: true, driveAllowed: false) == .device)
        }
    }

    @Test("Where it is offered, Pro records to the Device, the Drive only, or Both, as chosen (#805)")
    func pro() {
        for choice in RecordTo.allCases {
            #expect(choice.atPress(isOffered: true, driveAllowed: true) == choice)
        }
    }

    @Test("Where it is offered the Recorder gets the stored choice; elsewhere Both, whatever is stored (#805)")
    func forRecorder() {
        let store = defaults()
        #expect(RecordToSetting.forRecorder(isOffered: true, from: store) == .both)
        for choice in RecordTo.allCases {
            RecordToSetting.save(choice, to: store)
            #expect(RecordToSetting.forRecorder(isOffered: true, from: store) == choice)
            #expect(RecordToSetting.forRecorder(isOffered: false, from: store) == .both)
        }
    }

    @Test("The picker names the choices This iPhone, Drive and Both, with the hardware's word (#805)")
    func labels() {
        #expect(RecordTo.device.label(deviceWord: "iPhone") == "This iPhone")
        #expect(RecordTo.device.label(deviceWord: "Mac") == "This Mac")
        #expect(RecordTo.drive.label(deviceWord: "iPhone") == "Drive")
        #expect(RecordTo.both.label(deviceWord: "iPad") == "Both")
    }

    @Test("Device writes no Drive Copy, Drive writes the Drive alone, Both writes both (#805)")
    func destinations() {
        #expect(!RecordTo.device.usesDrive && !RecordTo.device.isDriveOnly)
        #expect(RecordTo.drive.usesDrive && RecordTo.drive.isDriveOnly)
        #expect(RecordTo.both.usesDrive && !RecordTo.both.isDriveOnly)
    }

    @Test("On Free the picker shows This iPhone, the choice in effect, and leaves what was saved alone (Eric, #805)")
    func shownOnFree() {
        for saved in RecordTo.allCases {
            #expect(saved.shown(driveAllowed: false) == .device)
            #expect(saved.shown(driveAllowed: true) == saved, "with Pro or the Trial the saved choice applies again")
        }
    }

    @Test("On Free, picking Drive or Both offers Pro instead of choosing it; This iPhone is chosen as usual (Eric, #805)")
    func pickingOnFree() {
        #expect(RecordTo.drive.offersPro(driveAllowed: false))
        #expect(RecordTo.both.offersPro(driveAllowed: false))
        #expect(!RecordTo.device.offersPro(driveAllowed: false))
        for choice in RecordTo.allCases { #expect(!choice.offersPro(driveAllowed: true)) }
    }

    @Test("Debug builds offer it whatever the environment, even before it is known (#805)")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(RecordToAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it (#805)")
    func testFlightBuild() {
        #expect(RecordToAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build, or one whose environment is unknown or not yet answered, does not (#805)")
    func appStoreOrUnknown() {
        #expect(!RecordToAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!RecordToAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!RecordToAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

@Suite("Record to availability in this build")
struct RecordToAvailabilityThisBuildTests {
    @Test("A Debug build offers it before the environment is known; a Release build waits for TestFlight (#805)")
    func thisBuild() {
        #if DEBUG
        #expect(RecordToAvailability.isAvailableInThisBuild)
        #else
        #expect(!RecordToAvailability.isAvailableInThisBuild, "no environment resolved in tests")
        #endif
    }
}
