# Mixer packs and the upgrade to Pro: App Store Connect draft (#705)

**Draft for Eric.** Nothing here is in App Store Connect yet: no product is created and no price is set. Packs are offered only in Debug builds (`PackAvailability`, `PackOffer.swift:6`); this file gets them ready to leave Debug. Your choices are in "Open decisions" at the end.

Why a file of its own: [`app-store-connect-steps.md`](app-store-connect-steps.md) is the launch checklist for things that exist or are about to (Pro and the Trial). The packs are still a draft with open questions, so they live here until you decide, and that file's section 3 points here.

Sources checked in code (2026-10-18): product IDs in `Packages/ShowRecorderKit/Sources/Recording/ProPurchases.swift`, offer rules and the price ladder in `PackOffer.swift`, families in `MixerLink/MixerFamily.swift`, the paywall in `App/PaywallSheet.swift`, Settings in `App/ProSection.swift`, the store in `App/ProStore.swift`, and the Xcode test products in `App/ShowRecorder.storekit`. Pricing is [ADR 0004](../adr/0004-one-time-pro-unlock-and-show-safe-limits.md), section "Free records every USB Channel" (2026-10-15/16), which replaces the $9.99 packs and the cheapest-upgrade rule in its older "Mixer packs" section.

## Limits (Apple, checked 2026-10-18)

From Apple's "In-app purchase information" page: Reference Name up to 64 characters, Product ID up to 100, **Display Name 2 to 30, Description up to 45**, review notes up to 4000. The Pro entry in `app-store-connect-steps.md` and the table in `listing.md` said 55 for the description; that was wrong and both now say 45. Pro's description there (`Mixer names, Drive copy, report, Reaper, 96 kHz, more`) is 53 characters, over the limit (see Open decisions). Every text below is counted and within the limits.

## How the products behave (all three)

- **Type:** Non-Consumable, like Pro.
- **Family Sharing: On**, the same setting as Pro (Eric, #705; ADR 0004). It can't be turned off later.
- **A pack is Pro on its own Mixer family only:** the family of the Armed Audio interface, recognized from its name (`MixerFamily(audioInterfaceName:)`). Any other input, including the built-in microphone and the Demo signal, stays Free (or Trial).
- **Who sees what** (`PackOffer.items`): no pack yet, with an X Air or X32 Armed: that family's pack first, Pro beside it. A generic input: Pro only. Someone who bought a pack: only the upgrade, never a second pack. Someone whose only pack is Family Shared: Pro only, no upgrade (`PackOffer.swift:38-40`).
- **The upgrade counts as Pro only while a pack is still owned** (`ProPurchases.init`): an upgrade this person bought needs a pack they bought, so refunding the pack takes Pro back; an upgrade shared with them rests on any pack shared with them.
- **The stage** is set in code (`PriceStage.current`, now `.launch`); "Launch price" shows under the offers at the Launch stage only. Each step moves App Store Connect's prices and that line by hand, on your go.

### Price per stage

| Product | Launch (now) | Step 2 (about 25 buyers) | Full (about 50 buyers) |
|---|---|---|---|
| Pro (exists) | $4.99 | $9.99 | $19.99 |
| X Air pack | $2.99 | $4.99 | $7.99 |
| X32 pack | $2.99 | $4.99 | $7.99 |
| Upgrade to Pro | $1.99 | $4.99 | $11.99 |

The upgrade is the nearest App Store price point below Pro minus a pack: $4.99 − $2.99 = $2.00 → $1.99; $9.99 − $4.99 = $5.00 → $4.99; $19.99 − $7.99 = $12.00 → $11.99. This matches `PackOffer.swift:81-83`. One upgrade product, repriced at each stage (ADR 0004's "reprice all three upgrades" line predates this). If Pro's price ever changes off this ladder, the upgrade moves with it.

## X Air pack

- [ ] Type **Non-Consumable**. Reference Name `X Air pack`. Product ID `dev.ericdahl.ShowRecorder.pack.xair` (exactly; `ProPurchases.packProductIDs[.xAir]`).
- [ ] **Price:** $2.99 (Launch); see the table.
- [ ] **Family Sharing: On.**
- [ ] **Availability:** every country Pro is in. Not before `PackAvailability` moves past Debug.
- [ ] **Localization (English U.S.):** Display Name `X Air pack` (10 of 30). Description `Everything in Pro, with an XR18 or MR18` (39 of 45). Brand-free alternative: Display Name `Pro for one mixer type` (22), Description `Pro features with one mixer family only` (39). See "Brand names" below before choosing.
- [ ] **Covers:** the X Air family, `MixerFamily.xAir`: an Audio interface named XR18, MR18 or X18 (the Mac shows "X18/XR18"). The XR12 and XR16 send no multichannel USB, so they never Arm as an X Air.
- [ ] **Review notes** (paste):
  > The X Air pack unlocks everything Pro does, but only while a Behringer XR18 or MR18 is the Audio interface the app is recording from (Settings > Recording > Audio interface). It is offered in Settings > Pro and in the Pro screen ("See what Pro adds") only while one of those mixers is connected over USB. With the built-in microphone, the Demo signal or any other interface, the app offers Pro alone, so without an XR18 or MR18 this purchase can't be seen. The screenshot shows Settings > Pro on an iPhone with an XR18 connected. ShowRecorder Pro, the upgrade and this pack are non-consumables; Restore Purchases is in Settings > Pro.
- [ ] **Review screenshot:** the Pro screen (paywall) on an iPhone with the XR18 Armed and nothing bought: the headline "Pro for your XR18", the button "Buy X Air pack, $2.99" above "Buy Pro, $4.99", and "Launch price" under them. Taken from Eric's iPhone and XR18 (a Debug build with the StoreKit configuration shows the same screen).

## X32 pack

- [ ] Type **Non-Consumable**. Reference Name `X32 pack`. Product ID `dev.ericdahl.ShowRecorder.pack.x32` (exactly; `ProPurchases.packProductIDs[.x32]`).
- [ ] **Price:** $2.99 (Launch); see the table.
- [ ] **Family Sharing: On.**
- [ ] **Availability:** as the X Air pack, and **not on sale before a real X32 or M32 has been confirmed**: `MixerFamily.swift` says its card names are "not yet seen on a real card (#503)", and `listing.md` gates naming the X32 on the same test (#411).
- [ ] **Localization (English U.S.):** Display Name `X32 pack` (8 of 30). Description `Everything in Pro, with an X32 or M32` (37 of 45). The family includes the Midas M32, which the name "X32 pack" doesn't say; the description does. Brand-free alternative: as the X Air pack's, which would make the two products read the same on the App Store (see "Brand names").
- [ ] **Covers:** `MixerFamily.x32`: an Audio interface whose name contains X-USB, X-LIVE, X32, M32 or DN32 (DN32-USB, DN32-LIVE), so a Behringer X32 or Midas M32 with its USB card.
- [ ] **Review notes** (paste):
  > The X32 pack unlocks everything Pro does, but only while a Behringer X32 or Midas M32 (with its USB card) is the Audio interface the app is recording from. It is offered in Settings > Pro and the Pro screen only while one of those mixers is connected over USB; with any other input the app offers Pro alone, so without an X32 or M32 this purchase can't be seen. The screenshot shows the Pro screen with an X32 connected. Restore Purchases is in Settings > Pro.
- [ ] **Review screenshot:** the Pro screen with an X32 or M32 Armed and nothing bought: "Pro for your X32" (or the linked Mixer's model), "Buy X32 pack, $2.99", "Buy Pro, $4.99", "Launch price". Needs a real X32 or M32 on USB; if none is at hand, a Debug build can't fake one (no demo input carries a family name).

## Upgrade to Pro

- [ ] Type **Non-Consumable**. Reference Name `Upgrade to Pro`. Product ID `dev.ericdahl.ShowRecorder.upgrade.pro` (exactly; `ProPurchases.upgradeProductID`).
- [ ] **Price:** $1.99 (Launch); repriced at each stage with Pro.
- [ ] **Family Sharing: On.**
- [ ] **Availability:** as the packs.
- [ ] **Localization (English U.S.):** Display Name `Upgrade to Pro` (14 of 30). Description `Pro on every mixer, for a pack owner` (36 of 45). No brand name either way.
- [ ] **Review notes** (paste):
  > Upgrade to Pro is offered only to someone who bought a mixer pack (X Air or X32) themselves, not one shared through Family Sharing. It then replaces the Buy Pro button in Settings > Pro and on the Pro screen, at Pro's price minus the pack's. It unlocks Pro on every input, and counts only while that pack is still owned: if the pack is refunded, the upgrade stops unlocking Pro. Reaching it needs a bought pack, so it needs an XR18, MR18, X32 or M32 connected to buy one first. The screenshot shows Settings > Pro after buying the X Air pack.
- [ ] **Review screenshot:** Settings > Pro with the X Air pack bought and no Pro: Plan "X Air pack", "Upgrade to Pro, $1.99", "Launch price", Restore Purchases. Any input can be Armed for this one: the offer depends on what's owned, not on the input. A Debug build with the StoreKit configuration (buy the pack in Xcode) or a sandbox account gets there.

## Brand names (Guideline 2.3.7): your call

What Apple says:

- 2.3.7: "don't try to pack any of your metadata with trademarked terms, popular app names, pricing information, or other irrelevant phrases just to game the system."
- 2.3.2: if in-app purchases are promoted on the App Store, "ensure that the in-app purchase Display Name, Screenshot and Description are appropriate for a public audience".
- 5.2.1: "Don't use protected third-party material such as trademarks … in your app without permission."

The Display Name and Description show on the App Store page's in-app purchase list and on Apple's purchase sheet, so they are metadata. `listing.md` already keeps Behringer, Midas, X Air, XR18, MR18, X32 and M32 out of the name, subtitle, keywords and promotional text, and names them only as compatibility in the description, with a trademark line. The guideline names no rule for in-app purchase names, so whether "X Air pack" is fine is a judgment, not a rule found:

- **Option A, model names** (`X Air pack`, `X32 pack`): clearest to a buyer and matches the app's buttons. Risk: a reviewer reads a Behringer product line in a purchase name as trademark use (5.2.1) and rejects the products, or asks for the names to change. The description's "with an XR18 or MR18" reads as compatibility, the same as the app description.
- **Option B, no brand** (`Pro for one mixer type` and a family-neutral description): no trademark question. Costs: both packs read the same on the App Store, and Apple's purchase sheet shows the App Store name while the app's button says "Buy X Air pack" (the app labels buttons from `MixerFamily.name`, not `product.displayName`; only the failure note "Couldn't buy …" in `ProStore.swift:103` uses the App Store name).
- A middle option: model names in the Description only, a neutral Display Name.

Either way the in-app copy can keep naming the mixer: it describes what the purchase works with, like the description's compatibility list.

## App Review can't reach a pack without a mixer

Plainly: **there is no Demo or review path to the pack offer.** The Demo signal's interface is named "Demo signal" (`RecordScreen.swift:1817`), which no family claims, so `armedFamily` is nil and the offer is Pro alone. No launch flag fakes a family. A reviewer without an XR18, MR18, X32 or M32 sees neither pack, and so never sees the upgrade either.

Guideline 2.1(b): in-app purchases must be "visible to the reviewer and functional. If any configured in-app purchase items cannot be found or reviewed in your app, explain the reason in your review notes." The review notes above explain it, which the guideline allows; whether that is enough is App Review's call. The 1.1 decision was no review video (`listing.md`); packs may change that. When packs ship, add this to [`review-notes.md`](review-notes.md) under "In-app purchases":

> - "X Air pack" and "X32 pack" are non-consumables (Family Sharing on) that unlock everything Pro does, only while that mixer (an XR18 or MR18; an X32 or M32) is the USB audio interface. They are offered only while one is connected, so they can't be seen with the Demo signal. "Upgrade to Pro" is offered only after buying a pack. Each one's review notes say how it is reached.

## Copy check (app vs site and listing, 2026-10-18)

The site and `listing.md` say nothing about packs, which is right while packs are Debug-only; each line below becomes a mismatch the day `PackAvailability` moves. Nothing in the app was changed here.

1. `App/ShowRecorder.storekit` (Pro): description "Record every USB Channel, with your own channel names, the Show report, Reaper export, 96 kHz and venue Templates." Free records every USB Channel since #703; the site and listing say so. Fix: the final App Store text (45 at most), such as "Mixer names, Drive copy, report, 96 kHz" (39).
2. `App/ShowRecorder.storekit` (packs, upgrade): "Everything Pro does, while an X Air mixer is the Armed input." (61, over 45; "Armed input" is our word, not a buyer's) and "Pro on every input, for an owner of a mixer pack." (49). Fix: the descriptions drafted above.
3. `App/PaywallSheet.swift:40` and `App/ProSection.swift:36`: "Buy X Air pack" says nothing about the pack covering one family; the paywall's feature list beneath it is Pro's. Nothing on the site or listing explains packs yet. Fix: a footnote under a pack offer, such as "The X Air pack is Pro while an XR18 or MR18 is the Audio interface. Pro covers every one."
4. `App/ProSection.swift:83` (footer, shown to a pack owner whose plan reads "X Air pack"): "Free records every USB Channel on the Device. Pro is a one-time purchase…". For a pack owner it reads as if they had nothing. Fix: a pack owner's footer, such as "Your X Air pack is Pro while an XR18 or MR18 is the Audio interface. Upgrade to Pro for every one."
5. `App/PaywallSheet.swift:63` with `ProOffer.swift:131`: the upgrade-only paywall is headed "ShowRecorder Pro" and lists Pro's features, which a pack owner already has on their family. Fix: a headline for the upgrade, such as "Pro on every Audio interface".
6. `Packages/ShowRecorderKit/Sources/Recording/PackOffer.swift:61`: "No Pro purchase found for this Apple Account." With packs, a purchase may be a pack. Fix: "No purchase found for this Apple Account."
7. `Packages/ShowRecorderKit/Sources/Recording/ProOffer.swift:109` vs `website/app/page.tsx:130` and `website/app/docs/pricing/page.mdx:33`: paywall "A second Copy on the Drive"; site "A second Copy on a Drive, with Repair" and "…with Repair, and recording to the Drive only". Fix: pick one wording (the site's names Repair and Drive only, which are Pro).
8. `ProOffer.swift:111` "The Show report and Reaper export" vs `website/app/page.tsx:132` "The Show report and Reaper project" and `listing.md:77` "the Show report and Reaper project". Fix: "Reaper project" in the app, or accept the difference.
9. `website/lib/screenshots.ts:56` (alt text): "The Pro screen: every USB Channel, channel names you type, …". Stale since #703. Fix: "The Pro screen: names and colors from the Mixer, channel names you type, a second Copy on the Drive, …".
10. `website/app/page.tsx:206`: "shared with Family Sharing and across your iPhone and iPad." The Mac is in 1.1 and the Pro card at line 135 says "across your devices". Fix: "across your iPhone, iPad and Mac" or "across your devices".
11. `ProOffer.swift:116` "A one-time purchase, shared with your family through Family Sharing." The site and listing say "at a launch price"; the app shows "Launch price" as its own line. Consistent; no fix.
12. `listing.md:77` names "$4.99" while `listing.md:161` records "The description doesn't mention the price" (Eric, 2026-10-11). An older decision against a newer line; pick one. When packs ship, line 77's section gains a pack sentence, and the in-app purchase table gains three rows.

13. The Trial's description: `app-store-connect-steps.md` says `Everything Pro does, for 14 days.`, `listing.md` says `Everything in Pro for 14 days, at no cost`. Fix: use the one entered in App Store Connect in both.

## Xcode pack test (Debug build, `App/ShowRecorder.storekit`)

The StoreKit configuration has all five products with matching IDs, non-consumable, Family Sharing on for Pro, the packs and the upgrade (off for the Trial), at Launch prices: Pro $4.99, packs $2.99, upgrade $1.99. Reset purchases between parts (Debug > StoreKit > Manage Transactions, delete all). This checks StoreKit and the app's rules; it is not a real-device TestFlight Take.

- [ ] **Launch price and plan line:** nothing bought, XR18 Armed: Settings > Pro shows Plan "Free", "Buy X Air pack $2.99", "Buy Pro $4.99", "Launch price". The paywall shows "Pro for your XR18" (the linked Mixer's model; "Pro for your X Air" with Mixer Link down).
- [ ] **Buy the X Air pack with an X Air Armed:** the sheet closes only when the pack came through, not on Cancel. Plan reads "X Air pack". The offers are now "Upgrade to Pro $1.99" only, no X32 pack, no Buy Pro.
- [ ] **Record press on the pack's family:** with the XR18 Armed, a Take gets Mixer names on its Stems, unlimited Markers, the Show report and Reaper project, 96 kHz if chosen, and Templates.
- [ ] **Record press on another family or a generic input:** Arm the built-in microphone, the Demo signal (or an EVO 4 or an X32): the Take is Free (generic names, 3 Markers, Device only), with no limit applied mid-Take. Re-Arm the XR18: Pro again from the next press.
- [ ] **Settings > Storage, Record to on a pack:** with the XR18 Armed, Drive and Both are offered plainly and a Take writes to the Drive. With another input Armed, they read "Drive (Pro)" and "Both (Pro)", choosing one opens the Pro screen, "On Free, Takes record to this iPhone only…" shows, and a Take goes to the Device only (`license().allowsDrive` on its family only).
- [ ] **The other family Armed, nothing bought:** with an X32 (or M32) Armed, the X32 pack is offered first. A generic input: Buy Pro only.
- [ ] **Buy the upgrade:** after the bought X Air pack, buy "Upgrade to Pro": Plan "Pro", no offers, Pro on every input.
- [ ] **Refund the pack under the upgrade:** in Manage Transactions, refund the X Air pack: Pro goes (the upgrade needs a pack bought by this person), Plan back to "Free", offers back. Refund the upgrade alone with the pack kept: Plan "X Air pack", the upgrade offered again.
- [ ] **Family Shared pack:** Pro only, no upgrade offer; the plan still reads "X Air pack". **Unconfirmed whether Xcode's transaction manager can mark a transaction Family Shared**; I found no such option in the configuration file. If it can't, this is covered by `ProPurchasesTests` and `PackOfferTests` and checked once on a sandbox family in TestFlight.
- [ ] **Restore:** with only a pack bought, Restore Purchases says "Restored: X Air pack"; with Pro, nothing; with nothing, "No Pro purchase found for this Apple Account." (see copy item 6).
- [ ] **Ask to Buy / pending:** with Ask to Buy on, buying a pack says "Waiting for approval…" and unlocks nothing until approved.
- [ ] **Cold start with last-known packs:** buy a pack, quit, turn off the network (or break StoreKit with the configuration's fail options), relaunch with the XR18 Armed: the first record press is already Pro on the X Air, from `proPurchases.ownedPacks` / `proPurchases.boughtPacks` in UserDefaults, and the upgrade (not a pack) is offered.
- [ ] **Trial plus a pack:** start the Trial while owning a pack: Plan says the Trial, not the pack, and every input is Pro until it ends; then the pack rule again.
- [ ] **Auto-gain on a pack** (where it's offered): it runs on the pack's family; it is judged when it runs, not at record.

## Open decisions (Eric)

1. **Pro's description is 53 characters; Apple allows 45.** Is the text in App Store Connect today different, or does it need shortening (for example `Mixer names, Drive copy, report, 96 kHz` is 39)?
2. **Brand names in the pack names:** Option A (`X Air pack`, `X32 pack`), Option B (brand-free), or the middle option.
3. **A review path for packs:** rely on the review notes, add a review video, or build a way to reach the pack offer without a mixer (such as a Debug and TestFlight demo input that counts as an X Air). The last is a code change, not part of this file.
4. **The X32 pack's timing:** on sale with the X Air pack, or only after a real X32 or M32 is confirmed (#503, #411).
5. **Copy fixes 1 to 10 above:** which to make, and whether before packs leave Debug.
6. **The level packs move to next:** Debug + TestFlight, after your device test, as a one-line PR (`PackAvailability`).
