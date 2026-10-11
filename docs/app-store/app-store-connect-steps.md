# App Store Connect: Eric's steps for launch

Everything in App Store Connect that only Eric (the Account Holder) can do, in order, with the values to type. Menu names are as of 2026 and may differ slightly. Tracked in #338; if something looks different, comment there and an agent will update this file.

Already done (2026-10-10): the app record (bundle `dev.ericdahl.ShowRecorder`) and the pages https://ericdahl.dev/showrecorder, https://ericdahl.dev/showrecorder/privacy and https://ericdahl.dev/showrecorder/support.

Text to paste comes from two files beside this one:

- [`listing.md`](listing.md): subtitle, promotional text, keywords, description and in-app purchase text (in review, PR #356).
- [`review-notes.md`](review-notes.md): the App Review notes.

## 1. Agreements, tax and banking (blocks in-app purchases)

At https://appstoreconnect.apple.com, open **Business** (older name: Agreements, Tax, and Banking).

- [ ] **Paid Apps** agreement: View and Agree. It needs the Account Holder role.
- [ ] **Bank account:** add the account Apple pays into.
- [ ] **Tax forms:** fill in the U.S. form (W-9) as the person or business that sells the app.
- [ ] Wait until the Paid Apps agreement shows **Active**. It can take a day.

## 2. App Privacy (required before submitting)

**Apps → ShowRecorder → App Privacy**

- [ ] **Privacy Policy URL:** `https://ericdahl.dev/showrecorder/privacy`
- [ ] **Data collection:** Get Started → "**No, we do not collect data from this app**" → Save → **Publish**. ShowRecorder sends nothing anywhere; the Mixer Link and Find Mixers stay on the local network.

## 3. In-app purchases (after step 1 is Active)

An agent can create these two through the API once step 1 is Active: say "create the products" in a session. Or by hand: **Apps → ShowRecorder → Monetization → In-App Purchases → +**

**Pro**

- [ ] Type **Non-Consumable**. Reference Name `Pro`. Product ID `dev.ericdahl.ShowRecorder.pro` (exactly; the app looks for this).
- [x] **Price:** $19.99 (ADR 0004). No planned change: the move to $29.99 is on hold (Eric, 2026-10-11).
- [ ] **Family Sharing: On.** This can't be turned off later (ADR 0004 wants it on).
- [ ] **Localization (English U.S.):** Display Name `ShowRecorder Pro` (30 characters max). Description `Every USB Channel, report, Reaper, 96 kHz, Templates` (55 characters max).
- [ ] **Review screenshot:** the paywall (taken for #324).

**14-day Trial**

- [ ] Type **Non-Consumable**. Reference Name `Trial`. Product ID `dev.ericdahl.ShowRecorder.trial`.
- [ ] **Price: Free** ($0.00). Family Sharing **Off**.
- [ ] **Localization:** Display Name `14-day Trial`. Description `Everything Pro does, for 14 days.`
- [ ] **Review screenshot:** the Trial screen (taken for #324).

## 4. Version 1.0 page

**Apps → ShowRecorder → iOS App → 1.0**

- [ ] **Text:** paste the subtitle, promotional text, keywords and description from [`listing.md`](listing.md). Marketing URL `https://showrecorder.app`, Support URL `https://ericdahl.dev/showrecorder/support`.
- [ ] **In-App Purchases:** add both Pro and the Trial, so they're reviewed with the first version.
- [ ] **Screenshots:** iPhone 6.9" (1320 × 2868) and iPad 13" (2064 × 2752); the app runs on iPad, so both sizes are required. An agent makes them from the Simulator once the UI is final (#64); you upload or approve them.
- [ ] **App Review Information:** your name, phone and email. Sign-in: not required. Notes: paste [`review-notes.md`](review-notes.md).
- [ ] **Build:** pick the release build (the TestFlight build that becomes 1.0).
- [ ] **Submit for Review.** Not before #357 (the paywall closing itself) is fixed.

## 5. Decisions only you can make

- [ ] **The Mac app at v1, or iPhone and iPad only?** If the Mac ships, it needs its own build in CI, Mac screenshots and a Mac category. If not, the "Universal Purchase" promise waits for a later version.
- [ ] **Release:** manual, or automatic once approved. Manual is safer for timing the launch price.
