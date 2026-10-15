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
    version: "1.1.6",
    date: "2026-10-15",
    channel: "TestFlight beta",
    summary: "Auto-gain, in the beta.",
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
