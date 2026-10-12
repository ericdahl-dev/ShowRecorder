// The docs pages under /docs/<slug>, in reading order. app/docs/layout.tsx lists them.
// Each page is app/docs/<slug>/page.mdx and sets its own metadata with pageMetadata(). The sitemap
// (ROUTES in lib/site.ts) and the docs list in app/docs/layout.tsx both read this list.
export type DocLink = { slug: string; title: string };

export const DOCS: readonly DocLink[] = [
  { slug: "getting-started", title: "Getting started" },
  { slug: "connecting-xr18", title: "Connecting an XR18 or MR18" },
  { slug: "mixer-link", title: "Mixer Link and Find Mixers" },
  { slug: "usb-drive", title: "Recording to a USB drive" },
  { slug: "markers-and-pre-roll", title: "Markers and Pre-roll" },
  { slug: "templates", title: "Templates" },
  { slug: "daw", title: "Opening a Show in Reaper or your DAW" },
  { slug: "pricing", title: "Free, 14-day Trial and Pro" },
  { slug: "troubleshooting", title: "Troubleshooting" },
];

export function docHref(slug: string): string {
  return slug ? `/docs/${slug}` : "/docs";
}
