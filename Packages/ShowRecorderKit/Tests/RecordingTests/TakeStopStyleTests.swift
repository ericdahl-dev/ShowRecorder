import Recording
import Testing

@Suite("How a Take is stopped")
struct TakeStopStyleTests {
    @Test("The iPhone holds to stop where its rule is on")
    func phoneWithRule() {
        #expect(TakeStopStyle.resolve(device: .iPhone, holdOnIPhone: true, holdOnIPad: false) == .hold)
    }

    @Test("The iPhone keeps tap and confirm where its rule is off")
    func phoneWithoutRule() {
        #expect(TakeStopStyle.resolve(device: .iPhone, holdOnIPhone: false, holdOnIPad: true) == .confirm)
    }

    @Test("The iPad keeps tap and confirm where only the iPhone rule is on (#753)")
    func padWithoutPadRule() {
        #expect(TakeStopStyle.resolve(device: .iPad, holdOnIPhone: true, holdOnIPad: false) == .confirm)
    }

    @Test("The iPad holds to stop where its own rule is on")
    func padWithPadRule() {
        #expect(TakeStopStyle.resolve(device: .iPad, holdOnIPhone: false, holdOnIPad: true) == .hold)
    }

    @Test("The Mac keeps click and confirm whatever the rules say")
    func mac() {
        for phone in [true, false] {
            for pad in [true, false] {
                #expect(TakeStopStyle.resolve(device: .mac, holdOnIPhone: phone, holdOnIPad: pad) == .confirm)
            }
        }
    }
}
