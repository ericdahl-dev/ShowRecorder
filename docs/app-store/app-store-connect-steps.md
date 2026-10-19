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
- [x] **Price:** $4.99, the launch price (ADR 0004; set 2026-10-16). The app says "Launch price" under Buy Pro. Then two steps, each only after Eric says go (Claude watches sales through the App Store Connect API and asks):
  - [ ] At about 25 buyers: **$9.99**.
  - [ ] At about 50 buyers: **$19.99**, full price. The "Launch price" line goes when `PriceStage.current` moves past `.launch`.
- [ ] **Family Sharing: On.** This can't be turned off later (ADR 0004 wants it on).
- [ ] **Localization (English U.S.):** Display Name `ShowRecorder Pro` (30 characters max). Description `Mixer names, Drive copy, report, Reaper, 96 kHz, more` (Free records every USB Channel now). Apple's limit is 45 characters, not 55 as this line said; this text is 53, so it needs shortening ([`mixer-packs.md`](mixer-packs.md), Open decisions).
- [ ] **Review screenshot:** the paywall (taken for #324).

**Mixer packs and the upgrade to Pro** (#705): drafted in [`mixer-packs.md`](mixer-packs.md), not yet created; packs are Debug-only.

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

- [x] **The Mac app:** iPhone and iPad first at 1.0 (Eric, 2026-10-11); **1.1 goes to the Mac App Store too** (Eric, 2026-10-13). See section 6.
- [ ] **Release:** manual, or automatic once approved. Manual is safer for timing the launch price.

## 6. Mac App Store (1.1, #374)

Already done:

- [x] **Add Platform > macOS** on the app record (2026-10-12). One bundle ID, so Pro and the Trial are a Universal Purchase with Family Sharing, as on iPhone and iPad.
- [x] **CI uploads a Mac build** on every tag (a missing installer certificate fails the Mac job, and the run logs the certificate's expiry): the Mac Installer Distribution certificate is in the GitHub secrets `MAC_INSTALLER_CERT_P12_BASE64` and `MAC_INSTALLER_CERT_PASSWORD` (since 2026-10-12). v1.1.2 uploaded Mac build 29.1, and its signed archive passed `scripts/preflight.sh`: App Sandbox, the Music category, the icon, the privacy manifest and the usage strings.

Your steps:

- [ ] **Infisical:** make sure the installer certificate and its password are also in project `showrecorder`, environment `prod`, under the same two names. GitHub has them; Infisical is where they're kept (docs/DEVELOPING.md). Never paste either value into a chat.
- [ ] **Renewal:** note the installer certificate's expiry date (Keychain Access, or the Certificates page in the developer account). Like the Apple Distribution certificate, it lasts a year, and an expired one stops the Mac upload.
- [ ] **TestFlight on a Mac:** once 1.1.2's beta review passes, install it on a Mac and run #327's Mac checks on this release build: the XR18 over USB, Mixer Link and Find Mixers, a Drive folder on an external disk, and a Take recorded and played back.
- [ ] **macOS 1.1 version page:** **Apps → ShowRecorder → macOS App → 1.1.** Paste the promotional text, description and keywords from [`listing.md`](listing.md) (the Mac is in them since #512), and the notes from [`review-notes.md`](review-notes.md). Each platform's version has its own Support URL (`https://ericdahl.dev/showrecorder/support`), copyright and App Review contact (your name, phone and email); App Privacy and the age rating are shared.
- [ ] **Mac screenshots:** upload the set in `docs/images/app-store-mac/` (2560 × 1600, light, dark and Sunlight; see [`listing.md`](listing.md), "Mac set"). Apple takes 1 to 10 at 16:10 (1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800).
- [ ] **Category:** Music. The category is set once for the app; the Mac app's Info.plist already says `public.app-category.music`.
- [ ] **Build:** the Mac build of the 1.1 tag. One App Review submission can carry the iOS and macOS 1.1 versions together, or each can go on its own.
- [ ] **In-app purchases:** nothing new. Pro and the Trial already cover the Mac.

