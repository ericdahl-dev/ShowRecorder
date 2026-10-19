# App Store listing (1.1 draft for Eric's review, #411; 1.0 was #64)

Paste into App Store Connect > ShowRecorder > the 1.1 version (and App Information for the name and subtitle). The number after each heading is Apple's character limit; every field here is within it (checked 2026-10-13, with the Apple Watch: subtitle 30, promotional text 170, keywords 100, description 3996 with the auto-gain block and 3753 without (recounted 2026-10-16 for "with Pro" under each heading), What's New 615).

Brand names (Behringer, Midas, X Air, XR18, MR18, X32, M32) appear only as compatibility text in the description and What's New. They are not in the name, subtitle or keywords (Guideline 2.3.7).

## Decided (Eric, 2026-10-13)

- **X32 and M32 only after a real one.** 1.1 names the X32 and M32 only once a tester has confirmed a real X32 or M32 (the gate on #411). Otherwise drop the X32 lines and make Auto-gain X Air only: in the AUTO-GAIN block, its What's New line and the review notes ("X Air or X32" becomes "X Air"). Keep the review notes' Network line either way: the build still asks port 10023 and Find Mixers still looks for X32 mixers.
- **No "reaper" keyword** (Cockos' trademark, 2.3.7): "soundcheck" replaces it.
- **1.1 goes to the Mac App Store too** (#374): the Mac is in the promotional text, the description and the review notes.

## Still to decide before submitting 1.1

- **Auto-gain.** The AUTO-GAIN block, its What's New line and the Auto-gain sentence in review-notes.md are only for a 1.1 that ships it (#494, after the live XR18 test). Delete all three otherwise.
- ~~A video for App Review~~: decided (Eric, 2026-10-13), no video. The review notes point to the Demo signal, and [`review-reply-2.1.md`](review-reply-2.1.md) is ready if App Review rejects under 2.1 for needing hardware.

## Name (30)

ShowRecorder

## Subtitle (30)

Multitrack recorder for mixers

## Promotional text (170)

Record every channel of your mixer to your iPhone, iPad or Mac, free. Pro adds names from the mixer, a second copy on a USB drive and more. Try Pro free for 14 days.

Leads with Free (Eric, 2026-10-16). 165 characters. It says "your mixer", not XR18 or X32: brand names stay out of the promotional text (2.3.7, above).

## Keywords (100)

live,stems,wav,gig,band,church,worship,concert,rehearsal,multichannel,usb,audio,daw,soundcheck,sound

## Description (4000)

Record every channel of your mixer, with no recording laptop at the gig.

Plug a compatible mixer into your iPhone, iPad or Mac, press record, and get one 24-bit WAV file per channel, named after what's on it and ready for your DAW.

EVERY CHANNEL, ITS OWN FILE
One Broadcast WAV per USB channel, at the mixer's 48 kHz or up to 96 kHz on interfaces that offer it. From an 18-channel mixer you get 18 Stems in step with each other; from an X32 or M32, 32.

NAMED FROM THE MIXER
With Pro, on the mixer's network, ShowRecorder reads your channel names and colors, so channel 3 arrives as "03 Snare.wav", not "USB 03". If you re-patch an X Air or X32's USB outputs, each file is named after what's really routed there. Find Mixers finds it on the network; no IP address to type.

A SECOND COPY AS YOU RECORD
With Pro, add a USB drive and every Take is written to the device and the drive at once. If the drive drops out, the missing part is filled back in from the other copy after the Take.

NOTHING LOST TO A CRASH
Files are saved every 2 seconds. If the app is closed mid-Take, it finishes that Take the next time it opens. A phone call or another app taking the input leaves silence of the exact length, marked, so every file stays in sync with your video.

PRE-ROLL AND MARKERS
A Take starts with the seconds before you pressed record, so the count-in isn't lost. Tap the flag to mark a song or a moment; Markers go into the files and your DAW project.

READY TO MIX
With Pro, each Show gets a report (Takes, levels, any gaps) and a Reaper project with every track and Marker in place.

TEMPLATES FOR EACH VENUE
With Pro, save a room's setup (channel names, mixer, Show name and Pre-roll) and start a Show from it in one tap.

BUILT FOR THE STAGE
Big level meters with a target band, clip marks you can see across the room, a Sunlight appearance for bright stages and a Dark one for dark rooms. Works with VoiceOver.

AUTO-GAIN
With Pro and an X Air or X32 mixer, Auto-gain sets each channel's preamp so it records at a healthy level, and moves the faders, sends and thresholds so the mix stays where you set it. One tap puts it all back. Never during a Take.

ON YOUR WRIST
With an Apple Watch, see that you're recording and for how long, drop Markers, and start or stop a Take from the stage. Stop takes a press and hold, so a stray tap can't end a song. Free for everyone.

THE SHOW-SAFE PROMISE
A Take never stops, and your audio is never held back, because of a Trial, a limit or a license. Limits are checked only when you press record. Your past Shows are never locked.

FREE, 14-DAY TRIAL AND PRO
Free records every USB channel to your iPhone, iPad or Mac, with generic file names ("USB 07") and up to 3 Markers per Take.
Pro is a one-time purchase, shared with your family: names and colors from the mixer on the files, typed names, a second copy on a USB drive, unlimited Markers, the Show report and Reaper project, 96 kHz and Templates. No subscription.
A 14-day Trial of everything in Pro costs nothing. When it ends, every channel still records.

WHAT YOU NEED
- A Behringer X Air XR18 or MR18 for 18 channels with names and colors.
- A Behringer X32 or Midas M32 with its USB card for 32 channels; names and colors need a router on the mixer's Ethernet port.
- Other class-compliant USB audio interfaces record too, without names.
- A USB-C iPhone, an iPad, or a Mac with macOS 26.
- On an iPhone or iPad, a powered USB-C hub lets it charge while the mixer and a drive are plugged in.
- About 9.3 GB per hour for 18 channels at 48 kHz, 16.6 GB for 32. The app shows the recording time left.

PRIVACY
ShowRecorder collects no data. Your recordings stay on your device and your drive, and the app talks only to your mixer on your local network.

ShowRecorder is not affiliated with or endorsed by Behringer, Midas or Music Tribe. Behringer, Midas, X Air, XR18, MR18, X32 and M32 are trademarks of their owners and are named only to describe compatibility.

## What's New (1.1) (4000)

- Records the Behringer X32 and Midas M32: all 32 USB channels, each file named and colored from the mixer over its network.
- Files are named after what's really routed to each USB channel on X Air and X32 mixers, even after a re-patch.
- With Pro, auto-gain sets each channel's preamp on an X Air or X32 and keeps the mix the same, with one-tap Undo.
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

## Screenshots (to take)

6.9" iPhone (required), 13" iPad, and for the Mac (1.1) 16:10 at 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800. Captions, in order:

1. Every channel, its own file (the record screen during a Take, 18 named meters)
2. Named from your mixer (the Mixer Link and Find Mixers)
3. A second copy on a USB drive (the record screen with the Drive chip)
4. Markers as you record
5. Ready to mix (a Show with its report and Reaper project)
6. Sunlight for bright stages

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
- Build Debug under its own bundle ID, `xcodebuild … PRODUCT_BUNDLE_IDENTIFIER=dev.ericdahl.ShowRecorder.screens`. Its container is empty, the real app's Shows are untouched, and it Arms only demo inputs (`DemoOnlyInputSource`), never a microphone or USB interface.
- Copy a folder of stems into its container (it is sandboxed), for example `~/Library/Containers/dev.ericdahl.ShowRecorder.screens/Data/tmp/demo-stems`. Leave out any stem that is silent in the loop. Never commit the audio.
- Launch it with `-demoStems <that folder> -demoNames -demoDrive -demoRecord -screenshotWindow`, plus `-lightScheme` for the light set or `-showList` for the list. Sunlight is the appearance setting in that container's preferences.
- `-demoStems` plays seconds 25 to 40 of each stem at 48 kHz, looped, about 6 dB down. `-screenshotWindow` makes a 1280 × 800 window on a Retina screen (2560 × 1600) and leaves out the empty alert slot. 2880 × 1800 would need its size changed in `ShowRecorderApp.swift` and a screen with at least 900 points of usable height.
- Capture the window alone with `screencapture -o -l<window id>`.

## Decided (Eric, 2026-10-11)

- The promotional text ends with "Try everything for 14 days."
- The trademark line stays at the end of the description.
- The description doesn't mention the price; the store shows it.
