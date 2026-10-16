import { PAGES, type PageInfo } from "@/lib/metadata";
import { APP_STORE_URL, REPO_URL, SITE_NAME, SITE_URL } from "@/lib/site";

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
    price: "4.99",
    priceCurrency: "USD",
    description: "One-time in-app purchase at a launch price, with a 14-day Trial, no subscription. Adds names from the mixer, a second Copy on a Drive, the Show report and Reaper project.",
  },
];

function applicationJsonLd(url: string, description: string) {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    url,
    description,
    applicationCategory: "MultimediaApplication",
    operatingSystem: "iOS 26, iPadOS 26, macOS 26 (beta)",
    image: `${SITE_URL}/og-image.png`,
    offers: OFFERS,
    publisher: { "@type": "Person", name: "Eric Dahl", url: "https://ericdahl.dev" },
    sameAs: [REPO_URL],
    ...(APP_STORE_URL ? { installUrl: APP_STORE_URL } : {}),
  };
}

export function softwareApplicationJsonLd() {
  return {
    ...applicationJsonLd(SITE_URL, PAGES.home.description),
    featureList: [
      "One 24-bit WAV file per USB Channel",
      "Channel names and colors from a Behringer XR18 or MR18",
      "32 USB Channels with names and colors from a Behringer X32 or Midas M32 in the public beta",
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

// Home > the page, for a page that sits one level under the home page.
export function breadcrumbJsonLd(name: string, path: string) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: SITE_NAME, item: SITE_URL },
      { "@type": "ListItem", position: 2, name, item: `${SITE_URL}${path}` },
    ],
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

// JSON-LD for a <script type="application/ld+json">, with "<" escaped so it can never close the
// script tag early.
export function jsonLdScript(data: object): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
