import type { Metadata } from "next";
import { OG_IMAGE } from "@/lib/metadata";
import { SITE_NAME } from "@/lib/site";

const TITLE = `Page not found - ${SITE_NAME}`;
const DESCRIPTION = "There is no page at this address.";

// Its own Open Graph and Twitter card, replacing the layout's (which describe the home page), with
// no canonical and no og:url: this page is served at whatever address was asked for, unindexed.
export const metadata: Metadata = {
  title: { absolute: TITLE },
  description: DESCRIPTION,
  // Next adds <meta name="robots" content="noindex"> to the not-found page itself; setting
  // robots here as well printed it twice.
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    siteName: SITE_NAME,
    type: "website",
    locale: "en_US",
    images: [OG_IMAGE],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
    images: [{ url: OG_IMAGE.url, alt: OG_IMAGE.alt }],
  },
};

export default function NotFound() {
  return (
    <section className="wrap not-found">
      <h1>Page not found</h1>
      <p>There is no page at this address.</p>
      <p>
        <a href="/">Go to the home page</a>
      </p>
    </section>
  );
}
