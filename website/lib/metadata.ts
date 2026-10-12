import type { Metadata } from "next";
import { SITE_NAME } from "@/lib/site";

// Per-page titles and descriptions, kept in one place so tests can check every route has them
// and so the MDX pages share the same Open Graph and Twitter card as the home page.

export const OG_IMAGE = {
  url: "/og-image.png",
  width: 1200,
  height: 630,
  alt: "ShowRecorder: record every channel of your mixer, on iPhone and iPad.",
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
    title: "ShowRecorder: multitrack recorder for mixers",
    description:
      "Record every channel of your mixer on your iPhone or iPad. One WAV file per channel, named from the mixer, with a second copy on a USB drive.",
  },
  features: {
    path: "/features",
    title: `Features - ${SITE_NAME}`,
    description:
      "Every ShowRecorder feature for iPhone and iPad, grouped by what it does, with what Free includes and what Pro adds. One WAV file per channel of your mixer.",
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
