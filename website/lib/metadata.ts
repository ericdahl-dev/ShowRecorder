import type { Metadata } from "next";
import { SITE_NAME } from "@/lib/site";

// Per-page titles and descriptions, kept in one place so tests can check every route has them
// and so the MDX pages share the same Open Graph and Twitter card as the home page.

export type ShareImage = { url: string; width: number; height: number; alt: string };

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
  // The page's own share image (1200x630, in public/); the site's OG_IMAGE when absent.
  image?: ShareImage;
};

export const PAGES = {
  home: {
    path: "/",
    title: "Live multitrack recorder for iPhone and iPad - ShowRecorder",
    description:
      "Multitrack recorder for iPhone and iPad: every USB Channel of your mixer to its own WAV file, no laptop. XR18 and MR18 now, X32 and M32 in the beta.",
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
  mixersXR18: {
    path: "/mixers/xr18",
    title: "XR18 multitrack recording app for iPhone, iPad - ShowRecorder",
    description:
      "Multitrack all 18 USB Channels of a Behringer XR18 or MR18 to iPhone or iPad, each file named from the mixer over its Wi-Fi. No laptop needed.",
    image: {
      url: "/og-mixers-xr18.png",
      width: 1200,
      height: 630,
      alt: "ShowRecorder for the XR18 and MR18: all 18 USB Channels on iPhone and iPad.",
    },
  },
  mixersX32: {
    path: "/mixers/x32",
    title: "X32 and M32 multitrack recording on iPad (beta) - ShowRecorder",
    description:
      "Multitrack all 32 USB Channels of an X32 or M32 to iPhone or iPad, each file named from the mixer. In the public beta now; the App Store later.",
    image: {
      url: "/og-mixers-x32.png",
      width: 1200,
      height: 630,
      alt: "ShowRecorder for the X32 and M32: all 32 USB Channels on iPhone and iPad, in the public beta.",
    },
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
  const image = page.image ?? OG_IMAGE;
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
      images: [image],
    },
    twitter: {
      card: "summary_large_image",
      title: page.title,
      description: page.description,
      images: [{ url: image.url, alt: image.alt }],
    },
  };
}
