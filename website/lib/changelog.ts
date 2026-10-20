// The "What's new" page (/changelog). One entry per released version, newest first, in plain words for
// people using the app. The tester-facing notes ("What to try") stay in docs/release-notes/<tag>.md;
// tests/changelog.test.ts fails when a 1.x tag there has no entry here.

export type Channel = "App Store" | "App Store review" | "TestFlight beta";

export type Release = {
  version: string;
  date: string; // YYYY-MM-DD
  channel: Channel;
  summary?: string;
  changes: string[];
};

export const RELEASES: readonly Release[] = [
  {
    version: "1.1.14",
    date: "2026-10-20",
    channel: "TestFlight beta",
    summary: "Steadier Takes around a call or Siri, and safer Drive Copies.",
    changes: [
      "A Take started while a call or Siri has stopped the input starts its silence at the press, and input comes back on its own.",
      "Recording to the Drive only, a short interruption or an earlier slow Drive no longer makes this iPhone stand in.",
      "Audio only this iPhone holds is never removed until the Drive is checked to hold all of it, and a Drive that fails while saving no longer damages a Stem.",
    ],
  },
  {
    version: "1.1.13",
    date: "2026-10-19",
    channel: "TestFlight beta",
    summary: "Choose where a Take records, and steadier recording to a slow Drive.",
    changes: [
      "Settings › Storage › Record to: this iPhone, the Drive, or both.",
      "A slow USB stick no longer makes the screen stutter, and a Drive Copy left unfinished is completed when the Drive is back.",
      "A Copy that ran out of space says it's full, and Repair never writes silence over real audio.",
    ],
  },
  {
    version: "1.1.12",
    date: "2026-10-17",
    channel: "TestFlight beta",
    summary: "A warning when a Take records only silence.",
    changes: [
      "If every channel stays silent for about 13 seconds during a Take, a banner says so and what to check. The Take keeps recording.",
      "Mixer Link keeps one connection to the mixer, so connecting is steadier.",
      "A slow Drive no longer holds up the rest of the app.",
      "The Contact support email has the version and build in its subject and a Diagnostics block you can delete.",
    ],
  },
  {
    version: "1.1.11",
    date: "2026-10-16",
    channel: "TestFlight beta",
    summary: "Clearer word on what interrupted a Take.",
    changes: [
      "When audio input is interrupted, the banner says why: a muted built-in mic, a disconnected input, or another app or a call.",
      "After a Dropout, the silence that fills the gap sits exactly where the audio was lost.",
      "Pro shows its launch price.",
    ],
  },
  {
    version: "1.1.10",
    date: "2026-10-16",
    channel: "TestFlight beta",
    summary: "Hold to stop on the iPhone, and a watch that reconnects by itself.",
    changes: [
      "Stop a Take on the iPhone or iPad by holding Stop for a second, like on the Apple Watch.",
      "The Apple Watch reconnects by itself when you raise your wrist.",
      "Green banners fade after 10 seconds, and you can tap × or swipe one away.",
    ],
  },
  {
    version: "1.1.9",
    date: "2026-10-15",
    channel: "TestFlight beta",
    summary: "A Marker from the Lock Screen, and a steadier Apple Watch.",
    changes: [
      "Place a Marker from the Lock Screen or the Dynamic Island while a Take is running.",
      "The Apple Watch no longer quits on Record, and shows the last status when the iPhone is locked.",
      "The Trial chip says what it is, and the Drive and warning chips stay readable in portrait.",
    ],
  },
  {
    version: "1.1.8",
    date: "2026-10-15",
    channel: "TestFlight beta",
    summary: "Free records every channel.",
    changes: [
      "Free records every USB Channel of your mixer as separate Stems.",
      "Pro adds channel names and colors from the mixer, the second Copy on a Drive, unlimited Markers, auto-gain and clip protection. The 14-day Trial includes everything.",
      "Settings has a Contact support row.",
    ],
  },
  {
    version: "1.1.7",
    date: "2026-10-15",
    channel: "TestFlight beta",
    summary: "Clip protection (in beta, Pro).",
    changes: [
      "Clip protection turns a clipping channel's preamp down on the mixer during a Take and raises its fader to match, at most 12 dB per Take, with a Marker for each move. Off until you switch it on.",
      "Swipe away the green summary after a Take.",
      "Settings shows the version and build number.",
    ],
  },
  {
    version: "1.1.6",
    date: "2026-10-15",
    channel: "TestFlight beta",
    summary: "Auto-gain (in beta, Pro).",
    changes: [
      "Auto-gain sets each channel's preamp on the mixer to -18 dBFS over Mixer Link, moving the fader, sends and dynamics the other way so the mix stays the same.",
      "Undo puts every channel back, and auto-gain never runs during a Take.",
    ],
  },
  {
    version: "1.1.5",
    date: "2026-10-15",
    channel: "TestFlight beta",
    summary: "A quicker, safer Stop.",
    changes: [
      "Stop waits at most about 5 seconds on a Drive that has stopped answering, instead of freezing the screen.",
      "Repair at Stop keeps all the audio a Copy recorded inside its own Gap.",
      "Swipe a yellow warning away; in landscape, warnings sit in the top row and never cover the meters.",
      "Mixer Link says when it's on a different mixer than the one you Armed, and tries again when the network port is briefly busy.",
    ],
  },
  {
    version: "1.1.4",
    date: "2026-10-14",
    channel: "TestFlight beta",
    summary: "A steadier Drive during a Take.",
    changes: [
      "A Drive pulled during a Take and plugged back in no longer loses the seconds before it was pulled; Repair fills the whole Gap.",
      "Plugging a Drive in during a Take is steadier.",
      "Mixer Link follows the input you Arm and reconnects more reliably.",
    ],
  },
  {
    version: "1.1.3",
    date: "2026-10-13",
    channel: "TestFlight beta",
    summary: "An Apple Watch app, free for everyone.",
    changes: [
      "From your wrist: see whether the iPhone is Armed or recording and for how long, drop Markers, start a Take while the iPhone is Armed, and stop with a press and hold so a stray tap can't end a song.",
      "The Take you're recording also shows in the watch's Smart Stack.",
      "If the mixer's USB routing changes during a Take, the record screen warns you and a Marker marks the moment. The Take carries on.",
      "The Marker list shows gain and routing Markers as themselves, not as Dropouts.",
      "The Drive shows by its name, and Mixer Link problems are in plain words.",
      "On the X32 and M32, the X-LIVE card is recognized as well as the X-USB.",
    ],
  },
  {
    version: "1.1.2",
    date: "2026-10-13",
    channel: "TestFlight beta",
    changes: [
      "Mixer Link connects again on iPhone and iPad. In 1.1.1 it failed with \"error 22 - Invalid argument\" even when Find Mixers found the mixer.",
    ],
  },
  {
    version: "1.1.1",
    date: "2026-10-12",
    channel: "TestFlight beta",
    changes: [
      "Behringer X32 and Midas M32 in the beta: names and colors for all 32 USB Channels over Mixer Link.",
      "Each Stem is named after what's actually patched to its USB channel, on the X32, M32, XR18 and MR18.",
      "On Free, the Channel names page says that files use the mixer's names.",
    ],
  },
  {
    version: "1.1.0",
    date: "2026-10-12",
    channel: "TestFlight beta",
    changes: [
      "The Take you're recording shows in the Dynamic Island and on the Lock Screen: the Take, the Show, the time recorded and the number of Markers, so you can see it's still running without opening the app.",
      "Tapping it opens ShowRecorder on the record screen. It goes away as soon as you stop the Take.",
    ],
  },
  {
    version: "1.0.1",
    date: "2026-10-12",
    channel: "TestFlight beta",
    changes: [
      "The Mac app joins the TestFlight beta, alongside iPhone and iPad.",
      "Channel names under the meters break between words, never in the middle of one.",
    ],
  },
  {
    version: "1.0.0",
    date: "2026-10-11",
    channel: "App Store review",
    summary: "The first release, for iPhone and iPad.",
    changes: [
      "One 24-bit WAV file per USB Channel, at the mixer's 48 kHz or up to 96 kHz on interfaces that offer it.",
      "Channel names and colors from a Behringer X Air XR18 or MR18 over its Wi-Fi, with Find Mixers to locate it.",
      "A second Copy on a USB drive as you record, filled back in after the Take if the drive drops out.",
      "Takes saved every 2 seconds, and finished the next time the app opens if it closes mid-Take.",
      "Pre-roll, Markers, a Show report and a Reaper project for every Show, and Templates for each venue.",
      "Free to download with a 14-day Trial of everything; Pro is a one-time purchase, shared with Family Sharing.",
    ],
  },
];

// Before 1.0: the public beta's builds, summed up in one line on the page.
export const BETA_SUMMARY =
  "ShowRecorder went through 24 TestFlight builds (0.1.0 to 0.1.23), with testers recording real shows.";
