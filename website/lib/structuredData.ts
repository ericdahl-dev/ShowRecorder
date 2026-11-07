import { newestRelease } from "@/lib/changelog";
import { PAGES, type PageInfo } from "@/lib/metadata";
import { SHOTS } from "@/lib/screenshots";
import { APP_STORE_URL, PRO_PRICE, REPO_URL, SITE_NAME, SITE_URL, appStoreLink } from "@/lib/site";

// schema.org data, as JSON-LD. Search engines read it to show ShowRecorder as an app (name, platform,
// price) rather than a plain web page. Two offers: the download is free, and Pro is a one-time in-app
// purchase. Free records every USB Channel with generic names; the 14-day Trial and Pro add names, the Drive and more (#705).
// The Mac version is in the TestFlight beta, so macOS is listed with "(beta)".
const OFFERS = [
  {
    "@type": "Offer",
    name: "Free",
    price: "0",
    priceCurrency: "USD",
    description: "Free to download. Free records every USB Channel, with generic names on the files.",
  },
  {
    "@type": "Offer",
    name: "Pro",
    price: PRO_PRICE,
    priceCurrency: "USD",
    description: "One-time in-app purchase at a launch price, with a 14-day Trial, no subscription. Adds names from the mixer, a second Copy on a Drive, the Show report and Reaper project.",
  },
];

const appStoreVersion = newestRelease("App Store")?.version;

// The app's screenshots, from the images the home page shows (lib/screenshots.ts), each with the alt text the page
// gives it as its caption. The Dark image, the site's default theme. Only screens every App Store customer has: no
// Debug or TestFlight-only feature (the *Availability rules in the app). Left out: the light iPhone set and the iPad
// Sunlight shot (the same screens again) and the Pro screen (a price list, not a feature of the app).
const SCREENSHOT_KEYS = ["heroIpad", "heroPhone", "mixerLink", "markers", "show", "sunlight"] as const;

const SCREENSHOTS = SCREENSHOT_KEYS.map((key) => {
  const shot = SHOTS[key].dark;
  const url = `${SITE_URL}${shot.src}`;
  return { "@type": "ImageObject", url, contentUrl: url, width: shot.width, height: shot.height, caption: shot.alt };
});

function applicationJsonLd(url: string, description: string) {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    url,
    description,
    applicationCategory: "MultimediaApplication",
    operatingSystem: "iOS 26, iPadOS 26, macOS 26 (beta)",
    // The version the App Store installs, from the changelog.
    ...(appStoreVersion ? { softwareVersion: appStoreVersion } : {}),
    image: `${SITE_URL}/og-image.png`,
    screenshot: SCREENSHOTS,
    offers: OFFERS,
    publisher: { "@type": "Person", name: "Eric Dahl", url: "https://ericdahl.dev" },
    // With 1.0 on the App Store, its listing is where to download the app and one of its own profiles (#704).
    sameAs: APP_STORE_URL ? [APP_STORE_URL, REPO_URL] : [REPO_URL],
    ...(APP_STORE_URL ? { installUrl: appStoreLink("site-schema"), downloadUrl: appStoreLink("site-schema") } : {}),
  };
}

export function softwareApplicationJsonLd() {
  return {
    ...applicationJsonLd(SITE_URL, PAGES.home.description),
    featureList: [
      "One 24-bit WAV file per USB Channel",
      "Channel names and colors from a Behringer XR18 or MR18",
      "32 USB Channels with names and colors from a Behringer X32 or Midas M32",
      "A second copy on a USB drive as you record",
      "Crash-safe Takes, saved every 2 seconds",
      "Pre-roll and Markers",
      "A Show report and a Reaper project",
    ],
  };
}

// A mixer page's SoftwareApplication: the same app, with the page's own URL and description.
export function mixerApplicationJsonLd(page: PageInfo) {
  return applicationJsonLd(`${SITE_URL}${page.path}`, page.description);
}

// A step in a breadcrumb trail, below the home page.
export type Crumb = { name: string; path: string };

// Home > each step of the trail, the last one being the page itself.
export function breadcrumbListJsonLd(trail: readonly Crumb[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [{ name: SITE_NAME, path: "" }, ...trail].map((c, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: c.name,
      item: `${SITE_URL}${c.path}`,
    })),
  };
}

// Home > the page, for a page that sits one level under the home page.
export function breadcrumbJsonLd(name: string, path: string) {
  return breadcrumbListJsonLd([{ name, path }]);
}

// A written guide as schema.org TechArticle: who wrote it, when, and the sources it cites.
export function techArticleJsonLd({
  page,
  headline,
  datePublished,
  dateModified,
  citations,
}: {
  page: PageInfo;
  headline: string;
  datePublished: string;
  dateModified: string;
  citations: readonly string[];
}) {
  return {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline,
    description: page.description,
    url: SITE_URL + page.path,
    datePublished,
    dateModified,
    author: { "@type": "Person", name: "Eric Dahl", url: "https://ericdahl.dev" },
    publisher: { "@type": "Organization", name: SITE_NAME, url: SITE_URL },
    citation: [...citations],
  };
}

// The home page FAQ as schema.org FAQPage. Google shows FAQ rich results only for a few kinds of
// site now, but AI assistants read the question and answer pairs.
export function faqPageJsonLd(faqs: readonly { q: string; a: string }[]) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((f) => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: f.a },
    })),
  };
}

// A guide's steps as schema.org HowTo (the no-laptop guide, lib/guide.ts).
// `name` names a HowTo that is one part of the page (the X32 guide's Method A); the page title is the default.
export function howToJsonLd(page: PageInfo, steps: readonly { name: string; text: string }[], name?: string) {
  return {
    "@context": "https://schema.org",
    "@type": "HowTo",
    name: name ?? page.title.replace(/ - ShowRecorder$/, ""),
    description: page.description,
    url: SITE_URL + page.path,
    step: steps.map((s, i) => ({ "@type": "HowToStep", position: i + 1, name: s.name, text: s.text })),
  };
}

// JSON-LD for a <script type="application/ld+json">, with "<" escaped so it can never close the
// script tag early.
export function jsonLdScript(data: object): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
