import { BEST_APP_FAQS, BEST_APP_GUIDE } from "@/lib/bestApp";
import { RELEASES, newestRelease } from "@/lib/changelog";
import { DOCS, docHref } from "@/lib/docs";
import { featureGroups, inBetaFeatures } from "@/lib/features";
import { PAGES } from "@/lib/metadata";
import { absoluteLinks, guideMarkdown, guideMdx } from "@/lib/guideMarkdown";
import type { Faq } from "@/lib/mixerFaqs";
import { GLOSSARY, HUB_COPY, HUB_FAQS, MIXER_GUIDES, MIXER_ROWS, TAP_POINT_FAQS, TAP_POINT_GUIDE, guideHeadline, pickMixerLink } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { inBeta, planned, worksNow } from "@/lib/mixers";
import { APP_STORE_URL, PRO_PRICE_TEXT, appStoreLink, REPO_URL, SITE_DESCRIPTION, SITE_NAME, SITE_URL, TESTFLIGHT_URL, TRADEMARK_LINE } from "@/lib/site";

// The text of /llms.txt (a short map) and /llms-full.txt (everything on one page), for AI assistants and AI search
// (#704). Both read the site's own lists, so a new docs page, feature or release shows up without editing this file.
// Keep the facts true to what ships: Free records every USB Channel with generic names, the X32 and M32 are in the App Store
// app (only their auto-gain is beta), the Mac is in the public beta, and the items in inBetaFeatures are TestFlight only. Pioneer DJM mixers are planned, not available.

export const abs = (path: string) => (path === "/" ? SITE_URL : SITE_URL + path);
const link = (title: string, path: string, note?: string) => `- [${title}](${abs(path)})${note ? `: ${note}` : ""}`;

// The mixer pages, with their one-line descriptions.
const MIXER_PAGES = [
  { title: "XR18 and MR18", page: PAGES.mixersXR18 },
  { title: "X32 and M32", page: PAGES.mixersX32 },
];

const getIt = APP_STORE_URL
  ? `App Store: ${appStoreLink("llms")}${TESTFLIGHT_URL ? `. The public beta (the next version) is on TestFlight: ${TESTFLIGHT_URL}` : ""}`
  : `ShowRecorder 1.0 for iPhone and iPad is in App Review. The public beta is open on TestFlight${TESTFLIGHT_URL ? `: ${TESTFLIGHT_URL}` : ""}`;

export function facts(): string[] {
  const appStore = newestRelease("App Store");
  const beta = newestRelease("TestFlight beta");
  return [
    "## Facts",
    "",
    `- Last updated: ${RELEASES[0].date}.`,
    ...(appStore ? [`- App Store version: ${appStore.version}, for iPhone and iPad (${appStore.date}).`] : []),
    ...(beta ? [`- TestFlight beta: ${beta.version}, the next version, and the Mac version (${beta.date}).`] : []),
    "- What it is: a multitrack recorder. It records every USB Channel a mixer sends to its own file, on an iPhone or iPad, with no laptop.",
    `- Get it: ${getIt}.`,
    `- Price: free to download. Free records every USB Channel on the iPhone or iPad, with generic names on the files and up to 3 Markers per Take. Pro is a one-time purchase, at a launch price of ${PRO_PRICE_TEXT}, shared with Family Sharing, with a 14-day Trial. Pro adds names and colors from the mixer on the files, typed names, a second Copy on a USB drive, unlimited Markers, the Show report, the Reaper project, 96 kHz, Templates and auto-gain on an XR18 or MR18. No subscription.`,
    "- Needs: a USB-C iPhone (iPhone 15 or later) on iOS 26, or a USB-C iPad on iPadOS 26, a USB cable to the mixer, and a class-compliant USB mixer or audio interface. Wi-Fi is optional, for channel names and colors. No account.",
    "- Files: one mono 24-bit Broadcast WAV file (a Stem) per USB Channel, at the mixer's sample rate, 48 kHz for the XR18 and MR18. Pro adds a second copy on a USB drive, a Show report and a Reaper project.",
    `- Works now: ${worksNow.map((m) => m.name).join("; ")}. The X32 and M32 have been tested only against an emulator so far.`,
    ...(inBeta.length ? [`- Also in the public beta (TestFlight, not the App Store version): ${inBeta.map((m) => m.name).join("; ")}.`] : []),
    "- In the public beta (TestFlight, not the App Store version): the Mac version, in testing on macOS 26.",
    `- Planned, not available: ${planned.filter((m) => /DJM/.test(m.name)).map((m) => m.name).join("; ")}.`,
    `- Also TestFlight only: ${inBetaFeatures.map((f) => f.title).join(", ")}.`,
    "- Privacy: the App Store version collects no data. The TestFlight beta builds send crash reports and usage (never recordings, Show names or file names), and Settings › Share crash reports and usage turns that off. Recordings stay on your device and your drive.",
    "",
  ];
}

// The guides: the hub, each mixer guide (from MIXER_GUIDES, so a new guide is listed without editing this file) and
// the no-laptop guide.
function guidesSection(): string[] {
  return [
    "## Guides",
    "",
    link("How to multitrack record a digital mixer (every mixer, one table)", PAGES.guidesHub.path, PAGES.guidesHub.description),
    link("Pre or post fader: which tap point to record", PAGES.guideTapPoints.path, PAGES.guideTapPoints.description),
    link("Best app to multitrack record a digital mixer on iPhone and iPad", PAGES.guideBestApp.path, PAGES.guideBestApp.description),
    ...MIXER_GUIDES.map((g) => link(guideHeadline(g.mixer), g.path, g.description)),
    link("Record a gig without a laptop", PAGES.guideNoLaptop.path, PAGES.guideNoLaptop.description),
    "",
  ];
}

// The recording guides in full, for llms-full.txt: the hub (its words from HUB_COPY, its table, glossary and
// questions), then the tap-point guide and each mixer guide, each read from the page's own content.mdx.
function mixerGuidesFull(): string[] {
  const cell = (s: string) => s.replace(/\|/g, "/");
  const hub = PAGES.guidesHub.path;
  const md = (text: string) => absoluteLinks(text, hub);
  const guideName = (path: string) => MIXER_GUIDES.find((g) => g.path === path)?.short ?? "";
  return [
    "## Recording guides, mixer by mixer",
    "",
    `### ${HUB_COPY.title}`,
    "",
    `URL: ${abs(hub)}`,
    "",
    ...(PAGE_DATES[hub] ? [`Last checked: ${PAGE_DATES[hub]}`, ""] : []),
    md(HUB_COPY.lede),
    "",
    md(HUB_COPY.method),
    "",
    `#### ${HUB_COPY.pickTitle}`,
    "",
    ...MIXER_GUIDES.map((g) => `- [${g.mixer}](${abs(g.path)}): ${g.pick}${g.productPage ? ` ${md(pickMixerLink(g.productPage))}` : ""}`),
    `- ${HUB_COPY.pickOthers}: see the table below.`,
    "",
    `#### ${HUB_COPY.tableTitle}`,
    "",
    md(HUB_COPY.tableIntro),
    "",
    "| Model | Over USB | With no computer | Mac | iPad | iPhone |",
    "| --- | --- | --- | --- | --- | --- |",
    ...MIXER_ROWS.map((r) => `| ${r.name} | ${[r.usb, r.onboard, r.mac, r.ipad, r.iphone].map(cell).join(" | ")} |`),
    "",
    "Notes on the table:",
    "",
    ...MIXER_ROWS.filter((r) => r.note || r.guide).map(
      (r) => `- ${r.name}:${r.note ? ` ${r.note}` : ""}${r.guide ? ` [Read the ${guideName(r.guide)} guide](${abs(r.guide)}).` : ""}`,
    ),
    "",
    `#### ${HUB_COPY.waysTitle}`,
    "",
    ...HUB_COPY.ways.map((w) => `- ${md(w)}`),
    "",
    ...HUB_COPY.waysAfter.flatMap((p) => [md(p), ""]),
    `#### ${HUB_COPY.fitsTitle}`,
    "",
    md(HUB_COPY.fits),
    "",
    `#### ${HUB_COPY.glossaryTitle}`,
    "",
    ...GLOSSARY.map((g) => `- **${g.term}:** ${g.def}`),
    "",
    ...faqSection(HUB_FAQS),
    ...fullGuide(TAP_POINT_GUIDE, TAP_POINT_FAQS),
    ...MIXER_GUIDES.flatMap((g) => fullGuide(g.path, g.faqs)),
    ...fullGuide(BEST_APP_GUIDE, BEST_APP_FAQS),
  ];
}

// A page's questions, as the page shows them at the end.
const faqSection = (faqs: readonly Faq[]) => ["#### Frequently asked questions", "", ...faqs.flatMap((f) => [`##### ${f.q}`, "", f.a, ""])];

// One guide in full: its title, URL and the whole page (content.mdx as Markdown), then its questions, as on the page.
function fullGuide(path: string, faqs: readonly Faq[]): string[] {
  const { title, body } = guideMarkdown(guideMdx(path), path);
  return [`### ${title}`, "", `URL: ${abs(path)}`, "", body, "", ...faqSection(faqs)];
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
    ...guidesSection(),
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
    ...inBetaFeatures.map((f) => `- ${f.title}${f.tier === "pro" ? " (In beta, Pro)" : ""}: ${f.body}`),
    "",
    "## Docs",
    "",
    ...DOCS.map((d) => `- [${d.title}](${abs(docHref(d.slug))}): ${d.description}`),
    "",
    ...mixerGuidesFull(),
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
