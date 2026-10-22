import Foundation
@testable import Recording
import Testing

/// The hidden file Take.json is staged in (#914) is told apart from any other file by its exact name.
@Suite("Staged Take.json name")
struct TakeJsonStagingNameTests {
    @Test("A name the writer makes is a staging file")
    func ownName() {
        #expect(TakeJsonWriter.isStagingFile(TakeJsonWriter.stagingName()))
        #expect(TakeJsonWriter.isStagingFile(".Take.json.\(UUID().uuidString)"))
    }

    @Test("Take.json itself and look-alikes are not")
    func lookAlikes() {
        for name in ["Take.json", ".Take.json", ".Take.json.", ".Take.json.tmp", ".Take.json.\(UUID().uuidString).bak",
                     "Take.json.\(UUID().uuidString)", ".DS_Store", ".take.json.\(UUID().uuidString)", ".Take.json.1234",
                     ".Take.json.\(UUID().uuidString.lowercased())"] {
            #expect(!TakeJsonWriter.isStagingFile(name), "\(name)")
        }
    }
}
