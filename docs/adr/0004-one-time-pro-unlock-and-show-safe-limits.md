# One-time Pro unlock, a channel-limited Free tier, and the Show-Safe Promise

ShowRecorder is free to download with a 14-day full Trial (a $0 non-consumable in-app purchase, App Review Guideline 3.1.1). After the Trial, Free records 2 USB Channels of the operator's choice, with Source names and colors; a one-time Pro unlock (Universal Purchase, Family Sharing on; price below) records every USB Channel and adds naming channels by hand, the Show report, Reaper export, 96 kHz recording and Templates. We chose a channel gate over the obvious 30-minute recording cap because a cap that stops a live set loses audio that can't be recorded again, and locking files after a limit holds the operator's show hostage. We chose a one-time unlock over a subscription because X-Air users already pay that way (Mixing Station) and the app costs almost nothing per user to run.

The **Show-Safe Promise** binds every limit: a Take never stops, and audio is never withheld, because of a Trial, limit or license. Limits are checked only when record is pressed; a Trial that expires during a Take records to the end.

## Decisions confirmed by Eric (2026-10-10)

- **Price:** **$19.99**. A rise to $29.99 three months after release was planned; on 2026-10-11 Eric put it on hold, undecided. Nothing is scheduled in App Store Connect, and the README promises no future price. One-time, Universal Purchase (iPhone, iPad, Mac), Family Sharing on.
- **Free:** 2 USB Channels of the operator's choice after the Trial, with Source names and colors from the Mixer. Never a time cap.
- **Trial:** 14 days, every feature.
- **In Pro, beyond every USB Channel:** the Show report and Reaper export, 96 kHz recording (#195), naming channels by hand (typed names, the Channel names page, shortcut chips and saved names), and Templates (#33, #34).
- Every limit is checked only when record is pressed (the Show-Safe Promise). A Free user's earlier Shows, reports and Stems are never locked.

## Launch scope (Eric, 2026-10-11)

- **Pro promises at launch only what is built:** every USB Channel, naming channels by hand, the Show report and Reaper export, 96 kHz recording and Templates. 96 kHz and Templates are built before Pro is offered.
- **Templates are venue setups:** the typed channel names, the Mixer (by its network name), the Show name pattern and the Pre-roll, so one tap readies a different room. As first written (Mixer address, name pattern, Pre-roll) they saved too little to sell.
- **Mixer Triggers are not promised** until they are built (#28, #29 are on hold; whether the XR18 can do it is unconfirmed, #16). When they ship they join Pro.

## Per-mixer unlocks later (Eric, 2026-10-11)

Considered: pricing like Mixing Station, a one-time unlock per mixer family (X Air $5.99, X32 $6.99, WING $6.99 on the App Store). Decided: **launch with Pro at $19.99 as "every mixer, every feature"**. At launch only the X Air is supported, so a per-mixer unlock would be Pro under another name. When a second family ships (Pioneer DJM first, #364), add **cheaper single-family unlocks** beside Pro. Pro owners keep everything, so nobody who bought early loses out. A generic class-compliant interface still needs a place in that menu; decide it with the first pack. The DJ price question (beating DJM-REC for less, #367) is answered by a DJM pack, not by lowering Pro.

## Mixer packs (Eric, 2026-10-12, #412)

With X32 support coming (#199), the second family is here, so the single-family unlocks above get their prices:

- **X Air pack $9.99, X32/M32 pack $9.99, Pioneer DJM pack $6.99.** Pro stays $19.99 for every mixer.
- A pack unlocks **everything Pro does** while that family's USB interface is the Armed input. Any other input stays Free (2 USB Channels).
- **DJM at $6.99** is under Pioneer's DJM-REC ($9.99 unlock after a 30-day trial), which answers #367's "better than DJM-REC, for less". The X Air and X32 packs are above Mixing Station's $5.99–6.99, because they record rather than only control.
- **Show-Safe:** a pack is judged only when record is pressed, from the Armed input, like Pro.
- **Generic interfaces need full Pro** (an EVO 4, or anything without a family): there is no pack for them, because their channel count can't be assumed.
- **The Trial** stays everything, any input, for 14 days.
- **Upgrading:** pack owners get a separate "Pro upgrade" purchase priced at Pro minus what they paid ($9.99 after an X Air or X32 pack, $12.99 after a DJM pack), offered only to them. Owners of two or more packs get the cheapest upgrade, $2.99. An upgrade counts as Pro only while a qualifying pack is still owned: a refunded or revoked pack takes it back too (Eric, 2026-10-13).
- **Paywall:** the connected mixer's pack first, with Pro beside it; a generic input is offered only Pro.

## Free records every USB Channel (Eric, 2026-10-15, #703, #705)

This replaces "Free = 2 USB Channels" above and in the mixer packs section. A free competitor (Manytrack) records every channel, so a channel gate loses that comparison; the gate moves to the workflow around the recording.

- **Free:** every USB Channel, as mono BWF Stems, on the Device only; generic names ("USB 07"); up to 3 Markers per Take; 44.1 and 48 kHz; crash recovery and routing-change warnings. The Apple Watch remote stays Free.
- **Pro or a pack** adds: names and colors from the Mixer, typed names, the Drive (second Copy, Repair, Drive only), unlimited Markers, auto-gain, clip protection, the Show report, Reaper export, 96 kHz and Templates.
- Pack prices change to X Air $7.99, X32/M32 $7.99; DJM stays $6.99. Pro stays $19.99.
- Still judged only when record is pressed and frozen into the Take (`TakeAllowance`); auto-gain, which runs between Takes, is judged when it runs.
- **Launch price ladder (Eric, 2026-10-15/16):** Launch Pro $4.99, packs $2.99, upgrade to Pro $1.99; Step 2 $9.99 / $4.99 / $4.99; Full $19.99 / $7.99 / $11.99. Moved by Eric at about 25 and 50 buyers. Pro went to $4.99 in App Store Connect on 2026-10-16. The "Launch price" line follows Pro's live StoreKit price against a per-currency table of launch prices, so a price step hides it without an app update (Eric, #908). X Air and X32 packs first (DJM waits for #364); one upgrade product repriced per stage; a second pack is hidden; only a pack the person bought earns the upgrade offer; packs and the upgrade share with family like Pro.

## Consequences

- Family Sharing can't be turned off for an in-app purchase once enabled; a church team on one family plan shares one unlock.
- Apple's volume purchasing doesn't cover in-app purchases. If organizations need purchase orders, that needs a paid-upfront option later (a separate listing risks Guideline 4.3).
- Future paid features (virtual soundcheck, AAF/Logic export) are separate add-ons or an optional subscription, never taken away from Pro.
- **Pro and the upgrade prices are linked:** the Pro upgrades are priced at Pro minus a pack. If Pro's price changes, reprice all three upgrades with it.
