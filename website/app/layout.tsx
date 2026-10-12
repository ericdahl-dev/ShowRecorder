import type { Metadata, Viewport } from "next";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { OG_IMAGE, PAGES } from "@/lib/metadata";
import { SITE_NAME, SITE_URL } from "@/lib/site";
import { THEME_SCRIPT } from "@/lib/theme";
import "./globals.css";

// Defaults for every page. Each page also sets its own title, description, canonical, Open Graph
// and Twitter card with pageMetadata() (lib/metadata.ts), which repeats the OG image, because a
// page's openGraph replaces the layout's rather than merging with it.
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: PAGES.home.title,
    template: `%s - ${SITE_NAME}`,
  },
  description: PAGES.home.description,
  applicationName: SITE_NAME,
  openGraph: {
    siteName: SITE_NAME,
    type: "website",
    url: "/",
    title: PAGES.home.title,
    description: PAGES.home.description,
    images: [OG_IMAGE],
  },
  twitter: {
    card: "summary_large_image",
    title: PAGES.home.title,
    description: PAGES.home.description,
    images: [{ url: OG_IMAGE.url, alt: OG_IMAGE.alt }],
  },
  // Add the apple-itunes-app meta (itunes: { appId }) when the App Store ID is known.
};

export const viewport: Viewport = {
  // The site is Dark by default; the light theme is a choice in the header.
  themeColor: "#111318",
  colorScheme: "dark light",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    // The inline script sets data-theme and data-js on <html> before React hydrates.
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body className="flex min-h-screen flex-col antialiased">
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <Header />
        <main id="main" tabIndex={-1} className="flex-1">
          {children}
        </main>
        <Footer />
      </body>
    </html>
  );
}
