// The docs pages under /docs/<slug>, in reading order. app/docs/layout.tsx lists them.
// Each page is app/docs/<slug>/page.mdx and sets its own metadata with pageMetadata(). The sitemap
// (ROUTES in lib/site.ts) and the docs list in app/docs/layout.tsx both read this list.
// `description` repeats the page's own meta description (tests/seo.test.ts checks they match); llms.txt shows it.
export type DocLink = { slug: string; title: string; description: string };

export const DOCS: readonly DocLink[] = [
  { slug: "getting-started", title: "Getting started", description: "What you need to record a show with ShowRecorder, how to plug in your mixer, and how to record, mark and stop your first Take." },
  { slug: "usb-cable-and-setup", title: "USB cable and setup", description: "The USB cable, a powered hub and the Audio interface setting for an XR18 or MR18 on iPhone or iPad, and how to check that all 18 USB Channels come in." },
  { slug: "mixer-link", title: "Mixer Link and Find Mixers", description: "Link ShowRecorder to your mixer over Wi-Fi to name every Stem after its channel, with its color. No internet needed, and recording never depends on it." },
  { slug: "usb-drive", title: "Recording to a USB drive", description: "Write every Take to your iPhone or iPad and a USB drive at once. Choose the Drive folder, see what happens if the drive is unplugged, and how Repair works." },
  { slug: "markers-and-pre-roll", title: "Markers and Pre-roll", description: "Keep the count-in with Pre-roll, and tap the flag to mark songs and moments. Markers go into every Stem, the Show report and the Reaper project." },
  { slug: "templates", title: "Templates", description: "Save a venue's setup as a Template (channel names, mixer, Show name and Pre-roll) and start a Show from it in one tap. A Pro feature." },
  { slug: "daw", title: "Opening a Show in Reaper or your DAW", description: "How a ShowRecorder Show folder is laid out, how Stems are named, what the Reaper project holds, and how to get the files onto your computer." },
  { slug: "pricing", title: "Pricing", description: "ShowRecorder is free to download and records every USB Channel. Pro is a one-time $4.99 purchase with Family Sharing and a 14-day Trial. No subscription." },
  { slug: "troubleshooting", title: "Troubleshooting", description: "Step-by-step fixes: a mixer the iPhone can't see, missing channels, Mixer Link, a Drive that fails or is slow, TestFlight and finding your files." },
];

export function docHref(slug: string): string {
  return slug ? `/docs/${slug}` : "/docs";
}
