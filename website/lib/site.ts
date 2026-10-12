import { DOCS, docHref } from "@/lib/docs";

// Site-wide constants. Pages and components read these instead of hard-coding URLs.

export const SITE_NAME = "ShowRecorder";
export const SITE_URL = "https://showrecorder.app";
export const SITE_DESCRIPTION =
  "Record every channel of your mixer on your iPhone or iPad. One WAV file per channel, named from the mixer, with a second copy on a USB drive.";
export const CONTACT_EMAIL = "showrecorder@ericdahl.dev";
export const ISSUES_URL = "https://github.com/ericdahl-dev/ShowRecorder/issues";

// The App Store listing (App Store Connect app 6820213310). While it is null, the badge slots
// (AppStoreBadge) show a "Coming soon to the App Store" placeholder that is not a link.
export const APP_STORE_ID = "6820213310";
export const APP_STORE_URL = `https://apps.apple.com/app/id${APP_STORE_ID}` as string | null;

// The routes the site exports. sitemap.ts reads this list.
export const ROUTES: readonly string[] = [
  "/",
  "/features",
  "/docs",
  ...DOCS.map((d) => docHref(d.slug)),
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
  "ShowRecorder is not affiliated with or endorsed by Behringer or Music Tribe. Behringer, X Air, XR18 and MR18 are trademarks of their owners and are named only to describe compatibility.";
