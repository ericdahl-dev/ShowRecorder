# App Store listing (1.2 changes marked "1.2"; 1.1 draft for Eric's review, #411; 1.0 was #64)

Paste into App Store Connect > ShowRecorder > the 1.1 version (and App Information for the name and subtitle). The number after each heading is Apple's character limit; every field here is within it (recounted 2026-10-29, with auto-gain for X Air and no X32 or M32: name 12, subtitle 30, promotional text 165, keywords 100, description 3778, What's New 475; the review notes are 3216 of 4000). The 1.2 description, with the X32 and M32, is 3943 (2026-11-23, after the Privacy paragraph changed for crash reports and usage; 3877 on 2026-11-15).

Brand names (Behringer, Midas, X Air, XR18, MR18, X32, M32) appear only as compatibility text in the description and What's New. They are not in the name, subtitle or keywords (Guideline 2.3.7).

## Decided (Eric, 2026-10-13)

- **X32 and M32 only after a real one.** 1.1 names the X32 and M32 only once a tester has confirmed a real X32 or M32 (the gate on #411). Otherwise drop the X32 lines, and when auto-gain is restored make it X Air only: in its held block, its What's New line and the review notes ("X Air or X32" becomes "X Air"). Keep the review notes' Network line either way: the build still asks port 10023 and Find Mixers still looks for X32 mixers. Applied 2026-10-29: the gate is still closed, so 1.1 names no X32 or M32 outside that Network line. **Dropped (Eric, 2026-11-15):** this rule no longer applies. From 1.2 the description names the X32 and M32 beside the X Air for the Mixer Link, as the site's X32 page has since 1.1.18, and the listing carries no emulator caveat (the site's X32 page keeps its own). Auto-gain stays X Air only.
- **No "reaper" keyword** (Cockos' trademark, 2.3.7): "soundcheck" replaces it.
- **1.1 goes to the Mac App Store too** (#374): the Mac is in the promotional text, the description and the review notes.

## Still to decide before submitting 1.1

- ~~Auto-gain~~: decided (Eric, 2026-10-29), in the 1.1 listing for X Air mixers only. #997 moves `AutoGainAvailability` to everyone (still Pro); the new `X32AutoGainAvailability` keeps an X32's or M32's gain to Debug + TestFlight, so the description, What's New and the review notes say X Air only. The held-back text was restored in all three, and its section removed.
- ~~A video for App Review~~: decided (Eric, 2026-10-13), no video. The review notes point to the Demo signal, and [`review-reply-2.1.md`](review-reply-2.1.md) is ready if App Review rejects under 2.1 for needing hardware.

## Name (30)

ShowRecorder: Mixer Multitrack

1.2 (Eric, 2026-11-07, ASO audit): uses all 30 characters so "mixer" and "multitrack" are indexed in the name. 30 characters. Set in App Information.

## Subtitle (30)

Live recorder, every channel

1.2 (Eric, 2026-11-07): pairs with the new name; "multitrack" and "mixer" moved to the name. 28 characters.

## Promotional text (170)

Record every channel of your mixer to your iPhone, iPad or Mac, free. Pro adds names from the mixer, a second copy on a USB drive and more. Try Pro free for 14 days.

Leads with Free (Eric, 2026-10-16). 165 characters. It says "your mixer", not XR18 or X32: brand names stay out of the promotional text (2.3.7, above).

## Keywords (100)

multi,track,stems,usb,wav,gig,band,church,worship,concert,sound,board,daw,record,rehearsal,foh,pa

1.2 (Eric, 2026-11-07): 97 characters, no word repeated from the name or subtitle, no brand names. Dropped audio, multichannel, soundcheck (now in name/subtitle or low value). The spare 3 characters wait for the Apple Ads test's keyword data.

## Description (4000)

Lines 2 and 3 changed for 1.2 (Eric, 2026-11-07, ASO audit): Free and no subscription above the fold, then compatibility. Lines 1 and 3, Named from the mixer and What you need changed for 1.2 (Eric, 2026-11-15): lead with any class-compliant USB mixer or interface, and name the X32 and M32 beside the X Air wherever the Mixer Link is described, with no emulator caveat (Eric, 2026-11-15). Auto-gain stays X Air only (`X32AutoGainAvailability`). To stay under 4000, a few other lines were shortened with no claim changed (the drive copy, crash, stage, auto-gain, watch and Free, Trial and Pro paragraphs). Line 1 was "a USB digital mixer" (Eric, 2026-11-06, for the words people and AI answers use: AI citation baseline, milestone "Mixer recording guides"); it keeps "USB mixer" and the three devices.

Record every channel of any class-compliant USB mixer or audio interface on your iPhone, iPad or Mac, with no laptop at the gig.

Free records every channel as its own 24-bit WAV file, ready for your DAW. No subscription.

On Behringer X Air and X32 mixers, and the Midas MR18 and M32, the Mixer Link adds each channel's name and color. Pro, a one-time purchase with a 14-day free Trial, puts them on the files.

EVERY CHANNEL, ITS OWN FILE
One Broadcast WAV per USB channel, at the mixer's 48 kHz or up to 96 kHz on interfaces that offer it. From an 18-channel mixer you get 18 Stems in step with each other.

NAMED FROM THE MIXER
With Pro, on the mixer's network, ShowRecorder reads your channel names and colors from an X Air, X32 or M32, so channel 3 arrives as "03 Snare.wav", not "USB 03". If you re-patch the mixer's USB outputs, each file is named after what's really routed there. Find Mixers finds it on the network; no IP address to type.

A SECOND COPY AS YOU RECORD
With Pro, add a USB drive and every Take is written to the device and the drive at once. If the drive drops out, the gap is filled in from the other copy afterwards.

NOTHING LOST TO A CRASH
Files are saved every 2 seconds. If the app is closed mid-Take, it finishes that Take the next time it opens. A phone call or another app taking the input leaves marked silence of the exact length, so every file stays in sync.

PRE-ROLL AND MARKERS
A Take starts with the seconds before you pressed record, so the count-in isn't lost. Tap the flag to mark a song or a moment; Markers go into the files and your DAW project.

READY TO MIX
With Pro, each Show gets a report (Takes, levels, any gaps) and a Reaper project with every track and Marker in place.

TEMPLATES FOR EACH VENUE
With Pro, save a room's setup (channel names, mixer, Show name, Pre-roll) and start a Show from it in one tap.

BUILT FOR THE STAGE
Big level meters with a target band, clip marks you can see across the room, Sunlight and Dark appearances, and VoiceOver.

AUTO-GAIN
With Pro and an X Air mixer, Auto-gain sets each channel's preamp so it records at a healthy level, and keeps the mix where you set it. One tap puts it all back. Never during a Take.

ON YOUR WRIST
With an Apple Watch, see the Take's time, drop Markers, and start or stop a Take from the stage. Stop takes a press and hold, so a stray tap can't end a song.

THE SHOW-SAFE PROMISE
A Take never stops, and your audio is never held back, because of a Trial, a limit or a license. Limits are checked only when you press record. Your past Shows are never locked.

FREE, 14-DAY TRIAL AND PRO
Free records every USB channel, with generic file names ("USB 07") and up to 3 Markers per Take.
Pro is a one-time purchase, shared with your family: mixer names on the files, typed names, a second copy on a USB drive, unlimited Markers, the report and Reaper project, 96 kHz and Templates. No subscription.
The 14-day Trial of everything in Pro is free. When it ends, every channel still records.

WHAT YOU NEED
- Any class-compliant USB mixer or audio interface: every USB channel records.
- For names and colors (the Mixer Link): an XR18 or MR18 (18 channels), or an X32 with an X-USB card or M32 with a DN32-USB card (32 channels, through a router on its Ethernet port).
- A USB-C iPhone, an iPad, or a Mac with macOS 26.
- A powered USB-C hub keeps an iPhone or iPad charging with the mixer and a drive plugged in.
- About 9.3 GB per hour for 18 channels at 48 kHz. The app shows the recording time left.

PRIVACY
Your recordings and names stay on your device and your drive. The app sends the developer crash reports and usage, with no tracking; turn it off in Settings. It talks to your mixer only on your local network.

ShowRecorder is not affiliated with or endorsed by Behringer, Midas or Music Tribe. Behringer, Midas, X Air, XR18, MR18, X32 and M32 are trademarks of their owners and are named only to describe compatibility.

## What's New (1.2) (4000)

Approved by Eric 2026-11-23 and submitted with 1.2.14. Only features available to everyone (TestFlight-only ones such as the WING, the slow-Drive wait and clip protection are left out). 719 characters.

- Choose which channels record (Pro or the Trial): long-press a channel's meter to leave it out. A Template keeps the choice.
- An interface with two inputs, both armed, records one stereo file.
- Delete several Shows at once, or every empty Show, from Shows › Select or Settings › Storage › Free Up Space…
- Auto-gain on an X Air (Pro) moves each preamp in the mixer's own 0.5 dB steps, so the mix stays exactly where it was, and leaves channels fed from USB alone.
- The app now sends the developer crash reports and usage, never your recordings or names. Turn it off in Settings › Share crash reports and usage.
- Settings has Help and ShowRecorder on Facebook.
- Fixed: swiping to delete a Show could crash the app.

## What's New (1.1) (4000)

- Files are named after what's really routed to each USB channel on X Air mixers, even after a re-patch.
- With Pro, auto-gain sets each channel's preamp on an X Air and keeps the mix the same, with one-tap Undo.
- Settings shows your USB drive by its name.
- An Apple Watch app: see the Take and drop Markers from your wrist, start a Take, and stop with a press and hold. Free.
- If the mixer's USB routing changes during a Take, ShowRecorder warns you and marks the moment.

## What's New (1.0)

First release.

## URLs

- Support URL: https://showrecorder.app/support
- Marketing URL: https://showrecorder.app
- Privacy Policy URL: https://showrecorder.app/privacy

## In-app purchase display text

| Product ID | Display name | Description (55) |
|---|---|---|
| `dev.ericdahl.ShowRecorder.pro` | ShowRecorder Pro | Mixer names, Drive copy, report, 96 kHz, more |
| `dev.ericdahl.ShowRecorder.trial` | 14-day Trial | Everything Pro does, for 14 days. |

The Trial's description is App Store Connect's live text (read 2026-10-18).

App Store Connect's live Pro description (read 2026-10-18) is "Every USB Channel, report, Reaper, 96 kHz, Templates" (52 characters). It is out of date since #703, as Free records every USB Channel; Eric to change it. Proposed: "Mixer names, Drive copy, report, 96 kHz, more" (45).

The mixer pack and the upgrade to Pro are drafted in [`mixer-packs.md`](mixer-packs.md).

## Screenshots (to take)

6.9" iPhone (required), 13" iPad, and for the Mac (1.1) 16:10 at 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800. Captions, in order:

1. Every channel, its own file (the record screen during a Take, 18 named meters)
2. Named from your mixer (the Mixer Link and Find Mixers)
3. A second copy on a USB drive (the record screen with the Drive chip)
4. Markers as you record
5. Ready to mix (a Show with its report and Reaper project)
6. Sunlight for bright stages

### iPhone 06-pro for 1.2 (taken 2026-11-13, #1057)

The 1.1 listing's 06-pro still says "Every USB Channel, not just 2" and "Buy Pro, $19.99": Free records every channel
since #703, and the price has changed. Its replacement is in [`docs/images/app-store-iphone/`](../images/app-store-iphone/),
1320 × 2868 (6.9"): `iphone-06-pro-light.png` and `iphone-06-pro-dark.png`, the Pro sheet (Settings › Pro › See what
Pro adds) on a fresh install with nothing plugged in, so it reads "ShowRecorder Pro", not a pack offer. It shows
"Buy Pro, $4.99" and "Launch price" from the App Store sandbox: take it again if Pro's price changes before 1.2 is
submitted (the price check is 2026-11-20).

### Apple Watch set (1.1, #100)

1.1 includes a watch app, so the version page needs Apple Watch screenshots: one size is enough; App Store Connect shows the sizes it takes. Take them from the watchOS Simulator with the `-watchDemo` launch flag, which shows a sample Recording (the 42 and 49 mm shots in [`docs/images/`](../images/) were taken that way). Captions:

1. Markers from your wrist (Recording, the elapsed time, Marker and Stop)
2. Stop takes a press and hold (the ring half full)

Boot one watch Simulator at a time, and shut it down and delete it when done (CLAUDE.md).

### Mac set (taken 2026-10-13, #374)

In [`docs/images/app-store-mac/`](../images/app-store-mac/), 2560 × 1600 each: a band's stems played as 10 USB Channels (Drums, Bass, Gtr, Vox, Other, left and right), named from the files, with a Drive set:

1. `mac-01-recording-light.png`: Every channel, its own file (a Take, 10 named meters)
2. `mac-02-recording-dark.png`: the same in Dark
3. `mac-03-shows-light.png` and `mac-04-shows-dark.png`: the Show list
4. `mac-05-sunlight.png`: Sunlight for bright stages

Every channel has signal: the set's piano stem was left out, as it plays for only one second of the song and an idle pair reads as broken. A Mixer Link shot waits for an X Air or X32 on this Mac's USB.

To take them again:
- Build Debug under its own bundle ID, `xcodebuild … PRODUCT_BUNDLE_IDENTIFIER=dev.ericdahl.ShowRecorder.screens`. Its container is empty, the real app's Shows are untouched, and it gets only demo inputs ready (`DemoOnlyInputSource`), never a microphone or USB interface.
- Copy a folder of stems into its container (it is sandboxed), for example `~/Library/Containers/dev.ericdahl.ShowRecorder.screens/Data/tmp/demo-stems`. Leave out any stem that is silent in the loop. Never commit the audio.
- Launch it with `-demoStems <that folder> -demoNames -demoDrive -demoRecord -screenshotWindow`, plus `-lightScheme` for the light set or `-showList` for the list. Sunlight is the appearance setting in that container's preferences.
- `-demoStems` plays seconds 25 to 40 of each stem at 48 kHz, looped, about 6 dB down. `-screenshotWindow` makes a 1280 × 800 window on a Retina screen (2560 × 1600) and leaves out the empty alert slot. 2880 × 1800 would need its size changed in `ShowRecorderApp.swift` and a screen with at least 900 points of usable height.
- Capture the window alone with `screencapture -o -l<window id>`.

## Decided (Eric, 2026-10-11)

- The promotional text ends with "Try everything for 14 days."
- The trademark line stays at the end of the description.
- The description doesn't mention the price; the store shows it.
