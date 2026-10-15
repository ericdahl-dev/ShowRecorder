import { RELEASES } from "@/lib/changelog";
import { DOCS, docHref } from "@/lib/docs";
import { featureGroups, inBetaFeatures } from "@/lib/features";
import { PAGES } from "@/lib/metadata";
import { inBeta, planned, worksNow } from "@/lib/mixers";
import { APP_STORE_URL, REPO_URL, SITE_DESCRIPTION, SITE_NAME, SITE_URL, TESTFLIGHT_URL, TRADEMARK_LINE } from "@/lib/site";

// The text of /llms.txt (a short map) and /llms-full.txt (everything on one page), for AI assistants and AI search
// (#704). Both read the site's own lists, so a new docs page, feature or release shows up without editing this file.
// Keep the facts true to what ships: Free records 2 USB Channels of your choice, the X32 and M32 and the Mac are in
// the public beta, and the items in inBetaFeatures are TestFlight only. Pioneer DJM mixers are planned, not available.

export const abs = (path: string) => (path === "/" ? SITE_URL : SITE_URL + path);
const link = (title: string, path: string, note?: string) => `- [${title}](${abs(path)})${note ? `: ${note}` : ""}`;

// The mixer pages, with their one-line descriptions.
const MIXER_PAGES = [
  { title: "XR18 and MR18", page: PAGES.mixersXR18 },
  { title: "X32 and M32 (public beta)", page: PAGES.mixersX32 },
];

const getIt = APP_STORE_URL
  ? `App Store: ${APP_STORE_URL}`
  : `ShowRecorder 1.0 for iPhone and iPad is in App Review. The public beta is open on TestFlight${TESTFLIGHT_URL ? `: ${TESTFLIGHT_URL}` : ""}`;

export function facts(): string[] {
  return [
    "## Facts",
    "",
    "- What it is: a multitrack recorder. It records every USB Channel a mixer sends to its own file, on an iPhone or iPad, with no laptop.",
    `- Get it: ${getIt}.`,
    "- Price: free to download, with a 14-day Trial of everything. Free records 2 USB Channels of your choice. Pro is a one-time $19.99 purchase, shared with Family Sharing. No subscription.",
    "- Needs: a USB-C iPhone (iPhone 15 or later) on iOS 26, or a USB-C iPad on iPadOS 26, a USB cable to the mixer, and a class-compliant USB mixer or audio interface. Wi-Fi is optional, for channel names and colors. No account.",
    "- Files: one mono 24-bit Broadcast WAV file (a Stem) per USB Channel, at the mixer's sample rate, 48 kHz for the XR18 and MR18, with a second copy on a USB drive. Pro adds a Show report and a Reaper project.",
    `- Works now: ${worksNow.map((m) => m.name).join("; ")}.`,
    `- In the public beta (TestFlight, not the App Store version): ${inBeta.map((m) => m.name).join("; ")}, tested only against an emulator so far. The Mac version, in testing on macOS 26, is also in the beta.`,
    `- Planned, not available: ${planned.filter((m) => /DJM/.test(m.name)).map((m) => m.name).join("; ")}.`,
    `- Also TestFlight only: ${inBetaFeatures.map((f) => f.title).join(", ")}.`,
    "- Privacy: no data is collected. Recordings stay on your device and your drive.",
    "",
  ];
}

export function llmsTxt(): string {
  return [
    `# ${SITE_NAME}`,
    "",
    `> ${SITE_DESCRIPTION}`,
    "",
    ...facts(),
    "## Pages",
    "",
    link("Home", PAGES.home.path, "What ShowRecorder does, what you need, pricing and the FAQ."),
    link("Features", PAGES.features.path, PAGES.features.description),
    ...MIXER_PAGES.map((m) => link(m.title, m.page.path, m.page.description)),
    link("What's new", PAGES.changelog.path, PAGES.changelog.description),
    link("Support", PAGES.support.path, PAGES.support.description),
    link("Privacy policy", PAGES.privacy.path, PAGES.privacy.description),
    "",
    "## Docs",
    "",
    link("Docs index", "/docs"),
    ...DOCS.map((d) => link(d.title, docHref(d.slug), d.description)),
    "",
    "## Optional",
    "",
    `- [Everything on one page](${abs("/llms-full.txt")})`,
    `- [Source and issues](${REPO_URL})`,
    "",
    TRADEMARK_LINE,
    "",
  ].join("\n");
}

export function llmsFullTxt(): string {
  const list = (items: { title: string; body: string }[]) => items.map((i) => `- ${i.title}: ${i.body}`);
  return [
    `# ${SITE_NAME}`,
    "",
    `> ${SITE_DESCRIPTION}`,
    "",
    ...facts(),
    "## Supported mixers",
    "",
    ...worksNow.map((m) => `- ${m.name}${m.href ? ` (${abs(m.href)})` : ""}: ${m.body}`),
    ...inBeta.map((m) => `- ${m.name}${m.href ? ` (${abs(m.href)})` : ""}, public beta: ${m.body}`),
    "",
    "## Features",
    "",
    "Each feature is marked Free or Pro.",
    "",
    ...featureGroups.flatMap((g) => [
      `### ${g.title}`,
      "",
      ...(g.intro ? [g.intro, ""] : []),
      ...g.features.map((f) => `- ${f.title} (${f.tier === "pro" ? "Pro" : "Free"}): ${f.body}`),
      "",
    ]),
    "### In the public beta (TestFlight only, not in the App Store version)",
    "",
    ...list(inBetaFeatures),
    "",
    "## Docs",
    "",
    ...DOCS.map((d) => `- [${d.title}](${abs(docHref(d.slug))}): ${d.description}`),
    "",
    "## Version history",
    "",
    ...RELEASES.flatMap((r) => [
      `### ${r.version} (${r.date}, ${r.channel})`,
      "",
      ...(r.summary ? [r.summary, ""] : []),
      ...r.changes.map((c) => `- ${c}`),
      "",
    ]),
    "## Optional",
    "",
    `- [Source and issues](${REPO_URL})`,
    "",
    TRADEMARK_LINE,
    "",
  ].join("\n");
}
