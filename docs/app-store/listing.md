# App Store listing (1.1 draft for Eric's review, #411; 1.0 was #64)

Paste into App Store Connect > ShowRecorder > the 1.1 version (and App Information for the name and subtitle). The number after each heading is Apple's character limit; every field here is within it (checked 2026-10-13: subtitle 30, promotional text 165, keywords 96, description 3601 with the auto-gain block and 3365 without, What's New 371).

Brand names (Behringer, Midas, X Air, XR18, MR18, X32, M32) appear only as compatibility text in the description and What's New. They are not in the name, subtitle or keywords (Guideline 2.3.7).

## Decide before submitting 1.1

- **A real X32 or M32.** X32 and M32 support has run only against an X32 emulator so far, and no card's USB name has been seen (#503). Submit with the X32 and M32 named only once one has been checked on a real mixer; otherwise take the X32 lines out of the description and What's New, and keep them in the public beta.
- **Auto-gain.** The AUTO-GAIN block, its What's New line and the Auto-gain sentence in review-notes.md are only for a 1.1 that ships it (#494, after the live XR18 test). Delete all three otherwise.
- **Mac.** The 1.1.2 Mac build is in TestFlight. If 1.1 goes to the Mac App Store too, put "Mac" back in the promotional text, the description and "What you need" (1.0 was iPhone and iPad only, Eric 2026-10-11).

## Name (30)

ShowRecorder

## Subtitle (30)

Multitrack recorder for mixers

## Promotional text (170)

Record every channel of your mixer on your iPhone or iPad. One file per channel, named from the mixer, with a second copy on a USB drive. Try everything for 14 days.

## Keywords (100)

live,stems,wav,gig,band,church,worship,concert,rehearsal,multichannel,usb,audio,daw,reaper,sound

## Description (4000)

Record every channel of your mixer, with no recording laptop at the gig.

Plug a compatible mixer into your iPhone or iPad, press record, and get one 24-bit WAV file per channel, named after what's on it and ready for your DAW.

EVERY CHANNEL, ITS OWN FILE
One Broadcast WAV per USB channel, at the mixer's 48 kHz or up to 96 kHz on interfaces that offer it. From an 18-channel mixer you get 18 Stems in step with each other; from an X32 or M32, 32.

NAMED FROM THE MIXER
On the mixer's network, ShowRecorder reads your channel names and colors, so channel 3 arrives as "03 Snare.wav", not "USB 03". If you re-patch the mixer's USB outputs, each file is named after what's really routed there. Find Mixers locates the mixer on the network; there is no IP address to type.

A SECOND COPY AS YOU RECORD
Add a USB drive and every Take is written to the device and the drive at once. If the drive drops out, the missing part is filled back in from the other copy after the Take.

NOTHING LOST TO A CRASH
Files are saved every 2 seconds. If the app is closed mid-Take, it finishes that Take the next time it opens. A phone call or another app taking the input leaves silence of the exact length, marked, so every file stays in sync with your video.

PRE-ROLL AND MARKERS
A Take starts with the seconds before you pressed record, so the count-in isn't lost. Tap the flag to mark a song or a moment; Markers go into the files and your DAW project.

READY TO MIX
Each Show gets a report (Takes, levels, any gaps) and a Reaper project with every track and Marker in place.

TEMPLATES FOR EACH VENUE
Save a room's setup (channel names, mixer, Show name and Pre-roll) and start a Show from it in one tap.

BUILT FOR THE STAGE
Big level meters with a target band, clip marks you can see across the room, a Sunlight appearance for bright stages and a Dark one for dark rooms. Works with VoiceOver.

AUTO-GAIN
With an X Air or X32 mixer, Auto-gain sets each channel's preamp so it records at a healthy level, and moves the faders, sends and thresholds to match so the mix doesn't change. One tap puts it all back. Never during a Take.

THE SHOW-SAFE PROMISE
A Take never stops, and your audio is never held back, because of a Trial, a limit or a license. Limits are checked only when you press record. Your past Shows are never locked.

FREE, 14-DAY TRIAL AND PRO
ShowRecorder is free to download. Start a 14-day Trial of everything at no cost. After the Trial, Free records 2 USB channels of your choice, with names and colors from the mixer.
Pro is a one-time purchase, shared with your family and across your iPhone and iPad: every USB channel, typed channel names, the Show report and Reaper project, 96 kHz and Templates. No subscription.

WHAT YOU NEED
- A Behringer X Air XR18 or MR18 for 18 channels with names and colors.
- A Behringer X32 or Midas M32 with its USB card for 32 channels; names and colors need a router on the mixer's Ethernet port.
- Other class-compliant USB audio interfaces record too, without names.
- A USB-C iPhone or an iPad.
- A powered USB-C hub lets the phone charge while the mixer and a drive are plugged in.
- About 9.3 GB per hour for 18 channels at 48 kHz, 16.6 GB for 32. The app shows the recording time left.

PRIVACY
ShowRecorder collects no data. Your recordings stay on your device and your drive, and the app talks only to your mixer on your local network.

ShowRecorder is not affiliated with or endorsed by Behringer, Midas or Music Tribe. Behringer, Midas, X Air, XR18, MR18, X32 and M32 are trademarks of their owners and are named only to describe compatibility.

## What's New (1.1) (4000)

- Records the Behringer X32 and Midas M32: all 32 USB channels, each file named and colored from the mixer.
- Files are named after what's really routed to each USB channel, on the X32 and the XR18, even after a re-patch.
- Auto-gain sets each channel's preamp on an X Air or X32 and keeps the mix the same, with one-tap Undo.
- Settings shows your USB drive by its name.

## What's New (1.0)

First release.

## URLs

- Support URL: https://showrecorder.app/support
- Marketing URL: https://showrecorder.app
- Privacy Policy URL: https://showrecorder.app/privacy

## In-app purchase display text

| Product ID | Display name | Description (55) |
|---|---|---|
| `dev.ericdahl.ShowRecorder.pro` | ShowRecorder Pro | Every USB Channel, report, Reaper, 96 kHz, Templates |
| `dev.ericdahl.ShowRecorder.trial` | 14-day Trial | Everything in Pro for 14 days, at no cost |

## Screenshots (to take)

6.9" iPhone (required) and 13" iPad. Captions, in order:

1. Every channel, its own file (the record screen during a Take, 18 named meters)
2. Named from your mixer (the Mixer Link and Find Mixers)
3. A second copy on a USB drive (the record screen with the Drive chip)
4. Markers as you record
5. Ready to mix (a Show with its report and Reaper project)
6. Sunlight for bright stages

## Decided (Eric, 2026-10-11)

- The promotional text ends with "Try everything for 14 days."
- The trademark line stays at the end of the description.
- The description doesn't mention the price; the store shows it.
