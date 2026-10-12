import { PAGES } from "@/lib/metadata";
import { APP_STORE_URL, REPO_URL, SITE_NAME, SITE_URL } from "@/lib/site";

// schema.org data for the home page, as JSON-LD. Search engines read it to show ShowRecorder as an
// app (name, platform, price) rather than a plain web page. The price is the download price; Pro is
// an in-app purchase and is not listed here.
export function softwareApplicationJsonLd() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    url: SITE_URL,
    description: PAGES.home.description,
    applicationCategory: "MultimediaApplication",
    operatingSystem: "iOS 26, iPadOS 26",
    image: `${SITE_URL}/og-image.png`,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    publisher: { "@type": "Person", name: "Eric Dahl", url: "https://ericdahl.dev" },
    sameAs: [REPO_URL],
    featureList: [
      "One 24-bit WAV file per USB Channel",
      "Channel names and colors from a Behringer XR18 or MR18",
      "A second copy on a USB drive as you record",
      "Crash-safe Takes, saved every 2 seconds",
      "Pre-roll and Markers",
      "A Show report and a Reaper project",
    ],
    ...(APP_STORE_URL ? { installUrl: APP_STORE_URL } : {}),
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
