# Recording to the Drive only

Every Take is written to two Destinations at once, the Device and the Drive, and neither is the primary (CONTEXT.md). Some operators don't want audio on this iPhone, iPad or Mac at all: no room on it, a shared or borrowed phone, or they simply trust the SSD. **Drive only** is a setting, off by default, that writes a Take to the Drive alone. This records how it keeps the Show-Safe Promise (ADR 0004) and the Gap and Repair model with one Copy.

**The Device stands in, it doesn't hold a Copy.** With Drive only on, the Device is written only while the Drive can't take the audio: when no Drive is connected at record, or for the stretch a Drive is lost mid-Take. That stretch is a Gap in the Drive Copy, and the Device holds exactly those frames. When the Take ends and the Drive is back, Repair fills the Drive Copy's Gaps from the Device, as it fills any Copy from the other, and then removes the Device's files for that Take. A Take that never lost its Drive leaves nothing on the Device: no Stems and no `Take.json`.

**Why fall back instead of losing the stretch.** The Show-Safe Promise says a Take never stops and audio is never withheld because of a setting. Writing nothing while the Drive is gone would lose audio that can't be recorded again, to honor a preference about where files live. The preference is honored once Repair has moved the audio, which is the operator's wish in every case where the Drive comes back.

**No Drive at record.** Record never refuses: the Take is written to the Device, and the record screen says so ("No Drive: recording to this iPhone; it moves to the Drive when one is connected"), like today's "No Drive" warning. If a Drive is connected later, that Take is moved after it ends; until then it is an ordinary Device Copy.

**Device too full.** The fallback writes as much as fits, under the same rules as today's Device Copy; a stretch neither Destination could take is a Dropout-like loss and is said plainly.

**Pre-roll** is kept in memory, so it never needs the Device.

**Where the setting lives.** Settings › Storage, the Drive choice of "Record to" (This iPhone, Drive, Both; Both by default, #805), with a one-line note when chosen ("Takes are written only to the Drive. If the Drive is lost, this iPhone records until it's back."). Templates carry the Record to choice, like the Pre-roll length (#840).

## Consequences

- While the Drive is missing, audio sits on the Device until Repair moves it: the "nothing on the Device" promise holds only once the Drive is back and Repair has run. The record screen and the Show report say where each Take's audio is.
- A stand-in from a Take cut off by a crash is never removed at the next launch, even if Repair fills the Drive from it: a Gap not yet written to `Take.json` when the app died could make an automatic removal lose audio (#626). It stays on the Device until the move to the Drive (#630) has checked the Drive Copy.
- With one Copy there is no second Copy to Repair from if the Drive itself is damaged after the Take. Operators who want that net leave Drive only off.
- Time left is the Drive's while it is connected, and the Device's during a fallback.
- Hardware check (Eric, with the rig): pull the Drive mid-Take, plug it back, and check the Take ends complete on the Drive and empty on the Device.
- Offered in Debug and TestFlight builds only (`DriveOnlyAvailability`), never the App Store build until that check passes. The first build that carries it is internal-only and promoted after Eric's Take on a real device.
- Decided with Eric, 2026-10-13 (#196).
