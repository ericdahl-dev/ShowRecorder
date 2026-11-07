import { DOCS, docHref } from "@/lib/docs";
import { BEST_APP_GUIDE } from "@/lib/bestApp";
import { GUIDES_HUB, MIXER_GUIDES, TAP_POINT_GUIDE } from "@/lib/mixerGuides";

// Site-wide constants. Pages and components read these instead of hard-coding URLs.

export const SITE_NAME = "ShowRecorder";
export const SITE_URL = "https://showrecorder.app";
// The one description of the product. PAGES.home.description, llms.txt and the structured data all use it.
export const SITE_DESCRIPTION =
  "Multitrack recorder for iPhone and iPad: every channel of any class-compliant USB mixer to its own WAV file. Names from XR18, MR18, X32, M32.";
export const CONTACT_EMAIL = "showrecorder@ericdahl.dev";
// The app's source code (FSL-1.1-MIT: public to read, MIT two years after each release).
export const REPO_URL = "https://github.com/ericdahl-dev/ShowRecorder";
export const ISSUES_URL = `${REPO_URL}/issues`;

// Pro's price. It is set in lib/price.ts (lib/docs.ts needs it, and this file imports lib/docs.ts) and read from here.
export { PRO_PRICE, PRO_PRICE_TEXT } from "@/lib/price";

// The App Store listing (App Store Connect app 6820213310). While it is null, the badge slots
// (AppStoreBadge) show a "Coming soon to the App Store" placeholder that is not a link.
export const APP_STORE_ID = "6820213310";
export const APP_STORE_URL = `https://apps.apple.com/app/id${APP_STORE_ID}` as string | null;

// App Store Connect's provider token, the `pt` in a campaign link (App Store Connect > Apps > ShowRecorder > Analytics >
// Acquisition > Campaigns > Generate Campaign Link: the link holds pt=<number>). Not a secret. While it is null, App
// Store links are the plain listing, since Apple ignores ct without pt; setting it tags every link at once.
export const APP_STORE_PROVIDER_TOKEN = "117729664" as string | null;

// The campaign (ct) for each place the site links to the App Store, 40 characters or fewer. App Analytics shows
// downloads by these names. docs/app-store/app-store-connect-steps.md ("Tagged links") lists them.
export const APP_STORE_CAMPAIGNS = [
  "site-home",
  "site-home-email",
  "site-home-footer",
  "site-xr18",
  "site-xr18-footer",
  "site-x32",
  "site-x32-footer",
  "site-compare-footer",
  "site-docs",
  "site-changelog",
  "site-schema",
  "llms",
  "site-guides",
  "site-guide-x32",
  "site-guide-xr18",
  "site-guide-qu",
  "site-guide-zoom-l12",
  "site-guide-mackie-dl32r",
  "site-guide-wing",
  "site-guide-m32",
  "site-guide-mackie-dl32s",
  "site-guide-ui24r",
  "site-guide-ah-cq",
  "site-guide-presonus-studiolive-iii",
  "site-guide-ah-sq",
  "site-guide-signature-mtk",
  "site-guide-xr12-xr16-mr12",
  "site-guide-yamaha-tf",
  "site-guide-yamaha-dm3",
  "site-guide-taps",
  "site-guide-best-app",
] as const;
export type AppStoreCampaign = (typeof APP_STORE_CAMPAIGNS)[number];

// A campaign link: the listing plus pt, ct and mt=8 (8 is apps), or the plain listing with no token.
export function campaignLink(listing: string, campaign: AppStoreCampaign, providerToken: string | null): string {
  if (!providerToken) return listing;
  const query = new URLSearchParams({ pt: providerToken, ct: campaign, mt: "8" });
  return `${listing}?${query}`;
}

// The App Store link for a placement on the site, or null while there is no listing.
export function appStoreLink(campaign: AppStoreCampaign): string | null {
  return APP_STORE_URL ? campaignLink(APP_STORE_URL, campaign, APP_STORE_PROVIDER_TOKEN) : null;
}

// The public TestFlight beta: the next version. With no APP_STORE_URL, the badge
// slots link here instead of showing the placeholder. Set it to null to go back to "Coming soon".
export const TESTFLIGHT_URL = "https://testflight.apple.com/join/sSessST8" as string | null;

// The line under the call to action, for whatever the button is. While it is TestFlight (no App Store link, or `beta`
// keeps a mixer page on the beta) it says what happens after the click (#719); on the App Store it is the old price line.
export function ctaNote(beta: boolean): string {
  if (TESTFLIGHT_URL && (!APP_STORE_URL || beta)) {
    return "The beta is free. Opens Apple's TestFlight app: install TestFlight, tap Accept, then Install.";
  }
  return "Free to download, 14-day Trial of everything.";
}

// The crawlers that feed AI search and assistants, named so the policy is explicit: all of them may read the whole
// site (#704). Training crawlers (Google-Extended, Applebot-Extended, CCBot) are included on purpose.
export const AI_CRAWLERS = [
  "GPTBot",
  "OAI-SearchBot",
  "ChatGPT-User",
  "ClaudeBot",
  "Claude-SearchBot",
  "Claude-User",
  "PerplexityBot",
  "Perplexity-User",
  "Google-Extended",
  "Applebot",
  "Applebot-Extended",
  "CCBot",
];

// The routes the site exports. sitemap.ts reads this list.
export const ROUTES: readonly string[] = [
  "/",
  "/features",
  "/docs",
  ...DOCS.map((d) => docHref(d.slug)),
  "/mixers/xr18",
  "/mixers/x32",
  "/compare",
  "/guides/record-gig-without-laptop",
  GUIDES_HUB,
  TAP_POINT_GUIDE,
  BEST_APP_GUIDE,
  // The mixer recording guides, from MIXER_GUIDES (lib/mixerGuides.ts).
  ...MIXER_GUIDES.map((g) => g.path),
  "/changelog",
  "/support",
  "/privacy",
];

// Header navigation. `href` is a real page, so every page links to Setup, Pricing and FAQ content of its own; `home` is
// the home page's section for the same thing, which the inline script in lib/theme.ts swaps in on the home page.
export const NAV: readonly { label: string; href: string; home?: string; wide?: boolean }[] = [
  { label: "Features", href: "/features" },
  { label: "Setup", href: "/docs/getting-started", home: "/#need" },
  { label: "Pricing", href: "/docs/pricing", home: "/#pricing" },
  { label: "Docs", href: "/docs" },
  { label: "FAQ", href: "/support", home: "/#faq" },
  { label: "Compare", href: "/compare", wide: true },
  { label: "Support", href: "/support", wide: true },
];

export const TRADEMARK_LINE =
  "ShowRecorder is not affiliated with or endorsed by Behringer, Midas, Music Tribe or any other mixer maker. Behringer, Midas, X Air, XR18, MR18, X32, M32 and the other mixer names on this site are trademarks of their owners and are named only to describe compatibility.";
