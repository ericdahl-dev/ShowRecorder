import { DOCS, docHref } from "@/lib/docs";

// Site-wide constants. Pages and components read these instead of hard-coding URLs.

export const SITE_NAME = "ShowRecorder";
export const SITE_URL = "https://showrecorder.app";
export const SITE_DESCRIPTION =
  "Record every channel of your mixer on your iPhone or iPad. One WAV file per channel, named from the mixer, with a second copy on a USB drive.";
export const CONTACT_EMAIL = "showrecorder@ericdahl.dev";
// The app's source code (FSL-1.1-MIT: public to read, MIT two years after each release).
export const REPO_URL = "https://github.com/ericdahl-dev/ShowRecorder";
export const ISSUES_URL = `${REPO_URL}/issues`;

// Fill in with the App Store link when the app is live. While it is null, the badge slots
// (AppStoreBadge) show a "Coming soon to the App Store" placeholder that is not a link.
export const APP_STORE_URL = null as string | null;

// The public TestFlight beta, open while 1.0 is in App Review. With no APP_STORE_URL, the badge
// slots link here instead of showing the placeholder. Set it to null to go back to "Coming soon".
export const TESTFLIGHT_URL = "https://testflight.apple.com/join/sSessST8" as string | null;

// The routes the site exports. sitemap.ts reads this list.
export const ROUTES: readonly string[] = [
  "/",
  "/features",
  "/docs",
  ...DOCS.map((d) => docHref(d.slug)),
  "/mixers/xr18",
  "/mixers/x32",
  "/compare",
  "/changelog",
  "/support",
  "/privacy",
];

// Header navigation. Anchors carry the leading slash so they work from every page.
export const NAV: readonly { label: string; href: string }[] = [
  { label: "Features", href: "/features" },
  { label: "Setup", href: "/#need" },
  { label: "Pricing", href: "/#pricing" },
  { label: "Docs", href: "/docs" },
  { label: "FAQ", href: "/#faq" },
];

export const TRADEMARK_LINE =
  "ShowRecorder is not affiliated with or endorsed by Behringer, Midas, Music Tribe or any other mixer maker. Behringer, Midas, X Air, XR18, MR18, X32, M32 and the other mixer names on this site are trademarks of their owners and are named only to describe compatibility.";
