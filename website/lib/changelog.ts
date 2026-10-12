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
