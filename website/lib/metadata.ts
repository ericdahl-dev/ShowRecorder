import type { Metadata } from "next";
import { SITE_NAME } from "@/lib/site";

// Per-page titles and descriptions, kept in one place so tests can check every route has them
// and so the MDX pages share the same Open Graph and Twitter card as the home page.

export const OG_IMAGE = {
  url: "/og-image.png",
  width: 1200,
  height: 630,
  alt: "ShowRecorder: record every channel of your mixer on iPhone and iPad.",
} as const;

export type PageInfo = {
  path: string;
  // The full <title>. Inner pages use "Name - ShowRecorder" (a spaced hyphen).
  title: string;
  description: string;
};

export const PAGES = {
  home: {
    path: "/",
    title: "ShowRecorder: record every mixer channel on iPhone and iPad",
    description:
      "Record every USB Channel of your mixer to iPhone or iPad, no laptop needed. XR18 and MR18 now; X32 and M32 in the public beta. Free to download.",
  },
  features: {
    path: "/features",
    title: `Features and supported mixers - ${SITE_NAME}`,
    description:
      "Every feature, marked Free or Pro, and which mixers work: XR18 and MR18 now, any class-compliant USB interface, X32 and M32 in the public beta.",
  },
  changelog: {
    path: "/changelog",
    title: `What's new - ${SITE_NAME}`,
    description:
      "Every ShowRecorder version for iPhone and iPad, newest first: what changed, when, and whether it's in the App Store or the TestFlight beta.",
  },
  mixersX32: {
    path: "/mixers/x32",
    title: "Record a Behringer X32 or Midas M32 on iPhone - ShowRecorder",
    description:
      "Multitrack all 32 USB Channels of an X32 or M32 to iPhone or iPad, each file named from the mixer. In the public beta now; the App Store later.",
  },
  privacy: {
    path: "/privacy",
    title: `Privacy policy - ${SITE_NAME}`,
    description:
      "ShowRecorder collects no data. Recordings stay on your device and your Drive, and the app talks only to your mixer on your local network.",
  },
  support: {
    path: "/support",
    title: `Support - ${SITE_NAME}`,
    description:
      "Help with ShowRecorder: getting started, where your recordings are, channel names from the mixer, and how to report a problem.",
  },
} satisfies Record<string, PageInfo>;

export function pageMetadata(page: PageInfo): Metadata {
  return {
    title: { absolute: page.title },
    description: page.description,
    alternates: { canonical: page.path },
    openGraph: {
      title: page.title,
      description: page.description,
      url: page.path,
      siteName: SITE_NAME,
      type: "website",
      locale: "en_US",
      images: [OG_IMAGE],
    },
    twitter: {
      card: "summary_large_image",
      title: page.title,
      description: page.description,
      images: [{ url: OG_IMAGE.url, alt: OG_IMAGE.alt }],
    },
  };
}
