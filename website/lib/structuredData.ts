import { APP_STORE_URL, SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "@/lib/site";

// schema.org data for the home page, as JSON-LD. Search engines read it to show ShowRecorder as an
// app (name, platform, price) rather than a plain web page. The price is the download price; Pro is
// an in-app purchase and is not listed here.
export function softwareApplicationJsonLd() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    url: SITE_URL,
    description: SITE_DESCRIPTION,
    applicationCategory: "MultimediaApplication",
    operatingSystem: "iOS 26, iPadOS 26",
    image: `${SITE_URL}/og-image.png`,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    ...(APP_STORE_URL ? { installUrl: APP_STORE_URL } : {}),
  };
}
