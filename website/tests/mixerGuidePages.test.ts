import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { GuideJsonLd } from "@/components/GuideJsonLd";
import { tapPointsAnchor } from "@/components/TapPicks";
import { llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { MIXER_GUIDES, MIXER_ROWS, TAP_POINT_GUIDE, X32_METHOD_A, guideHeadline, guideTitle } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { ROUTES } from "@/lib/site";

// The per-mixer recording guides (#1063, #1064). Every guide has the same shape (the template), checked here for
// each one; the mixer-specific facts are checked below. Facts come only from docs/research/mixer-recording/.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const headings = (mdx: string) => [...mdx.matchAll(/^## (.+)$/gm)].map((m) => m[1]);
const body = (slug: string) => read("app", "guides", "record", slug, "content.mdx");
const shell = (slug: string) => read("app", "guides", "record", slug, "page.tsx");

// "an X32", "an XR18", but "a Qu": the article before a guide's short name, by how the name is said.
const A_SHORT: Record<string, string> = { Qu: "a", DL32R: "a", WING: "a", DL32S: "a", Ui24R: "a", CQ: "a", StudioLive: "a", "Signature MTK": "a" };
const waysHeading = (short: string) => `Ways to record ${A_SHORT[short] ?? "an"} ${short}`;

// The sections every mixer guide has, in this order. They name the mixer (review batch 1), so a heading quoted out of
// context still says which mixer it is about.
const TEMPLATE = (short: string) => [
  waysHeading(short),
  `${short} recording settings`,
  `${short} USB routing`,
  `${short} playback for virtual soundcheck`,
  `${short} tap points`,
  `${short} on Mac, iPad and iPhone`,
  "Sources",
];

// The id a heading gets on the page: lowercase, punctuation dropped, spaces to hyphens.
const slugify = (h: string) => h.toLowerCase().replace(/[^a-z0-9 -]/g, "").replace(/ /g, "-");
const section = (mdx: string, start: string, end: string) => mdx.slice(mdx.indexOf(`## ${start}`), mdx.indexOf(`## ${end}`));

// Mackie's page for the current Master Fader Reference Guide (V5.1, Feb 2026). Its "Click here" opens Mackie's
// Brandfolder; the PDF itself sits behind a signed URL, so the guides link this page (#1111).
const MACKIE_MF_DOWNLOADS = "https://help.mackie.com/hc/en-us/articles/14288356150159-Master-Fader-Downloads";
// Midas's own M32 documents, linked from midasconsoles.com (Midas's current site) (#1111).
const MIDAS_M32_MANUAL = "https://cdn-media.empowertribe.com/5a30d52258104865a4392b99550ee1f9/M32_M_EN.pdf";
const MIDAS_M32_LIVE_QSG = "https://cdn-media.empowertribe.com/019427b1584f42aab500bf0dc082ace5/QSG_MI_0603-AEO_M32%20LIVE.pdf";

describe.each(MIXER_GUIDES)("the $slug recording guide (template)", (guide) => {
  const mdx = body(guide.slug);
  const page = (PAGES as Record<string, { path: string; title: string; description: string }>)[guide.pageKey];

  it("lives under the hub, in the sitemap, with metadata, a date and an llms.txt line", () => {
    expect(guide.path).toBe(`/guides/record/${guide.slug}`);
    expect(page.path).toBe(guide.path);
    expect(page.title).toBe(guideTitle(guide.short));
    expect(ROUTES).toContain(guide.path);
    expect(PAGE_DATES[guide.path]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(llmsTxt()).toContain(`https://showrecorder.app${guide.path})`);
  });

  it("has the template's sections in order", () => {
    expect(headings(mdx)).toEqual(TEMPLATE(guide.short));
  });

  it("uses its article headline as the H1 and in llms.txt", () => {
    expect(mdx).toMatch(new RegExp(`^# ${guideHeadline(guide.mixer)}$`, "m"));
    expect(llmsTxt()).toContain(`[${guideHeadline(guide.mixer)}](`);
  });

  it("opens with a short answer and a numbered quick start whose links reach its sections, before the caveats", () => {
    const top = mdx.slice(0, mdx.indexOf("\n## "));
    expect(top).toMatch(/\*\*Short answer\.\*\*/);
    const quick = top.slice(top.indexOf("**Quick start**"));
    expect(top.indexOf("**Quick start**")).toBeGreaterThan(top.indexOf("**Short answer.**"));
    expect(quick).toMatch(/^1\. /m);
    const ids = new Set([...mdx.matchAll(/^#{2,3} (.+)$/gm)].map((m) => slugify(m[1])));
    const anchors = [...quick.matchAll(/\]\(#([^)]+)\)/g)].map((m) => m[1]);
    expect(anchors.length).toBeGreaterThanOrEqual(3);
    for (const a of anchors) expect(ids.has(a), a).toBe(true);
    expect(quick).toMatch(/30 s|short test/i);
  });

  it("has a 'seeing too few channels?' heading under its recording settings", () => {
    const settings = section(mdx, `${guide.short} recording settings`, `${guide.short} USB routing`);
    expect(settings).toMatch(/^### Only [^\n]+\?/m);
  });

  it("has breadcrumbs and a last-checked day around its H1, and the shared JSON-LD in its shell", () => {
    expect(mdx).toContain(`<Breadcrumbs trail={guideTrail("${guide.short}", "${guide.path}")} />`);
    expect(mdx).toContain(`<LastChecked path="${guide.path}" />`);
    expect(mdx.indexOf("<Breadcrumbs")).toBeLessThan(mdx.indexOf("\n# "));
    expect(shell(guide.slug)).toContain(`<GuideJsonLd slug="${guide.slug}" />`);
    const ld = renderToStaticMarkup(createElement(GuideJsonLd, { slug: guide.slug }));
    for (const type of ["BreadcrumbList", "FAQPage", "TechArticle", "SoftwareApplication"]) expect(ld).toContain(`"@type":"${type}"`);
    expect(ld).toContain('"position":3');
    for (const f of guide.faqs) expect(ld).toContain(JSON.stringify(f.q).slice(1, -1).replace(/</g, "\\u003c"));
  });

  it("cites in its TechArticle data exactly the links in its Sources section", () => {
    const links = [...mdx.slice(mdx.indexOf("## Sources")).matchAll(/\]\((https?:\/\/[^)]+)\)/g)].map((m) => m[1]);
    expect([...guide.sources].sort()).toEqual([...new Set(links)].sort());
  });

  it("offers the app with its own campaign, the ask-us line, the glossary and a quotable ShowRecorder line", () => {
    expect(mdx).toContain(`<GetTheApp campaign="${guide.campaign}" />`);
    expect(mdx).toContain("<AskUs />");
    expect(mdx).toContain("](/guides/record#glossary)");
    expect(mdx).toContain("ShowRecorder (the app this site makes)");
  });

  it("has commented-out screenshot slots, with alt text, for Eric's images", () => {
    expect(mdx.match(/\{\/\* Screenshot: [^*]+alt="[^"]+"/g)?.length).toBeGreaterThanOrEqual(2);
  });

  it("is linked from the tap-point guide's per-mixer list, at its tap points section", () => {
    expect(TEMPLATE(guide.short).map(slugify)).toContain(tapPointsAnchor(guide.short));
    expect(guide.tapPick.trim()).not.toBe("");
  });

  it("covers every way to record: a computer, the mixer itself, and an iPhone, iPad or Mac", () => {
    const ways = section(mdx, waysHeading(guide.short), `${guide.short} recording settings`);
    expect(ways).toMatch(/computer/i);
    expect(ways).toMatch(/no computer|without a computer/i);
    expect(ways).toMatch(/iPhone/);
  });

  // A mixer with no ShowRecorder product page (no Mixer Link, such as the Qu) links only the hub and the tap guide.
  it("links the shared tap-point guide, the hub, and the ShowRecorder page for this mixer (if any), which links back", () => {
    expect(mdx).toContain(`](${TAP_POINT_GUIDE})`);
    expect(mdx).toContain("](/guides/record)");
    // Only the Qu, the Zoom, the DL32R, the WING, the Mackie DL32S, the Ui24R, the CQ, the StudioLive, the SQ and the Signature MTK have none; a Mixer Link guide that lost its product page must fail here, not skip.
    expect(guide.productPage === undefined).toBe(["qu", "zoom-l12", "mackie-dl32r", "wing", "mackie-dl32s", "ui24r", "ah-cq", "presonus-studiolive-iii", "ah-sq", "signature-mtk"].includes(guide.slug));
    if (guide.productPage === undefined) return;
    expect(mdx).toContain(`](${guide.productPage})`);
    expect(read("app", "mixers", guide.productPage.split("/").pop()!, "content.mdx")).toContain(`](${guide.path})`);
  });

  // One hub row per model family; the Qu guide covers two rows (the new Qu and Qu Classic).
  it("is the guide link in the hub table", () => {
    expect(MIXER_ROWS.filter((r) => r.guide === guide.path)).toHaveLength(guide.hubRows ?? 1);
  });

  it("cites its sources: the maker's documents, with forum posts marked as such", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toMatch(
      /\]\(https:\/\/(cdn-media\.empowertribe\.com|www\.behringer\.com|support\.allen-heath\.com|www\.allen-heath\.com|zoomcorp\.com|mackie\.com|help\.mackie\.com|www\.soundcraft\.com|harman\.helpjuice\.com|www\.fmicassets\.com|support\.presonus\.com)\//,
    );
  });

  it("says Mixer Link works only on the XR18/MR18 and X32/M32, and that ShowRecorder records every USB Channel", () => {
    expect(mdx).toMatch(/every USB Channel/);
    expect(mdx).toMatch(/Mixer Link/);
  });

  it("shows the same questions it puts in its FAQPage data", () => {
    expect(shell(guide.slug)).toMatch(new RegExp(`<MixerFaq faqs=\\{${guide.faqsName}\\}`));
    expect(guide.faqs.length).toBeGreaterThanOrEqual(4);
  });

  it("has no em dashes or exclamation points in its prose", () => {
    const text = mdx + guide.faqs.map((f) => f.q + f.a).join(" ");
    expect(text).not.toMatch(/—/);
    expect(text.replace(/^(import|export)[^\n]*$/gm, "").replace(/<[^>]+>/g, "")).not.toMatch(/!(?!=)/);
  });
});

describe("the X32 guide's facts", () => {
  const mdx = body("x32");

  it("covers both routing methods: card out blocks of 8, and user routing from firmware 4.0", () => {
    expect(mdx).toMatch(/blocks of 8/);
    expect(mdx).toMatch(/\*\*card out\*\*/);
    expect(mdx).toMatch(/User In/);
    expect(mdx).toMatch(/User Out/);
    expect(mdx).toMatch(/firmware 4\.0/);
  });

  it("stages buses, the main mix and tapped channels through Out 1-16 and P16", () => {
    expect(mdx).toMatch(/Out 1-16/);
    expect(mdx).toMatch(/P16/);
    expect(mdx).toMatch(/Main/);
  });

  it("says user routing comes from user reports, before the first User In or User Out, and files it under Advanced", () => {
    expect(mdx).toMatch(/forum/i);
    expect(mdx.indexOf("per user reports")).toBeGreaterThan(-1);
    expect(mdx.indexOf("per user reports")).toBeLessThan(mdx.indexOf("User In"));
    expect(mdx).toMatch(/^### Advanced: user routing \(firmware 4\.0 and later, per user reports\)$/m);
    const faq = MIXER_GUIDES.find((g) => g.slug === "x32")!.faqs.find((f) => /User Out/.test(f.a))!;
    expect(faq.a).toMatch(/per user reports; no Behringer manual describes it/);
  });

  it("explains Local, AES50, card out and P16 before Method A", () => {
    const before = mdx.slice(mdx.indexOf("## X32 USB routing"), mdx.indexOf("### Method A"));
    for (const w of ["Local", "AES50", "card out", "P16"]) expect(before).toContain(w);
  });

  it("gives Method A as one list that the HowTo data repeats", () => {
    expect(mdx).toContain("X32_METHOD_A.map(");
    expect(X32_METHOD_A.length).toBe(3);
    expect(shell("x32")).toMatch(/howToJsonLd\(PAGES\.guideX32, X32_METHOD_A/);
  });

  it("gives both tap lists from Behringer's manual: the numbered steps and the screenshot", () => {
    expect(mdx).toMatch(/Input, Pre-EQ, Pre-Fader and Post-Fader/);
    expect(mdx).toMatch(/Pre EQ, Post EQ, Pre Fader and Post Fader/);
  });

  it("doesn't promise an iPhone in its description, and doesn't claim the X32 can't charge a phone", () => {
    expect(PAGES.guideX32.description).not.toMatch(/or an iPhone/);
    expect(mdx).not.toMatch(/doesn't charge a phone/);
    expect(mdx).toMatch(/we don't know of a way to charge a phone from it/);
  });

  it("says plainly that iPhone and iPad audio from the card is not documented, and no real Take has been recorded", () => {
    const apple = mdx.slice(mdx.indexOf("## X32 on Mac, iPad and iPhone"), mdx.indexOf("## Sources"));
    expect(apple).toMatch(/not documented/i);
    expect(apple).toMatch(/emulator/);
    expect(apple).toMatch(/X-USB or X-LIVE card into an iPhone/);
  });

  it("gives the card settings and the X-LIVE SD recorder limits", () => {
    expect(mdx).toMatch(/\*\*Setup > Card\*\*/);
    expect(mdx).toMatch(/32\/32, 16\/16, 32\/8, 8\/32, 8\/8 (and|or) 2\/2/);
    expect(mdx).toMatch(/\*\*Setup > Config\*\*/);
    expect(mdx).toMatch(/32 GB/);
    expect(mdx).toMatch(/200 min/);
  });
});

describe("the XR18 and MR18 guide's facts", () => {
  const mdx = body("xr18");

  it("says the XR18 can't record by itself, and the XR12 and XR16 send no USB audio", () => {
    expect(mdx).toMatch(/can't record by itself/i);
    expect(mdx).toMatch(/XR12/);
  });

  it("gives the per-slot Routing grid path and the sample rate setting", () => {
    expect(mdx).toMatch(/Inputs\/USB/);
    expect(mdx).toMatch(/orange dots/);
    expect(mdx).toMatch(/Audio\/MIDI/);
    expect(mdx).toMatch(/[Mm]ute the main LR/);
  });

  // The audited research: the manual shows only pre-low-cut and post-fader channel feeds; the "Input ... Post Fader"
  // list is the aux and main bus taps. A tap choice per USB send is user-reported only.
  // Eric's XR18 (Routing > USB Sends, 2026-11-06): each USB Send has its own Signal Source and Signal Tap.
  it("gives each USB send's own tap, with the list seen on a real XR18, and what the manual shows", () => {
    expect(mdx).toMatch(/Analog, Analog \+M, Input, Input \+M, Pre EQ, Pre EQ \+M, Post EQ, Post EQ \+M, Pre Fader, Pre Fader \+M, Post Fader/);
    expect(mdx).toMatch(/\*\*Signal Tap\*\*/);
    expect(mdx).toMatch(/goes silent when the channel is muted/);
    expect(mdx).toMatch(/\*\*pre low cut\*\*/);
    expect(mdx).not.toMatch(/input channel taps/i);
  });

  // Review batch 1: plain picks first, hedged readings, and no claim the manual doesn't back.
  it("leads its tap points with a plain pick, defines +M at first use, and hedges what it reads", () => {
    const taps = mdx.slice(mdx.indexOf("## XR18 tap points"), mdx.indexOf("## XR18 on Mac"));
    expect(taps.split("\n").find((l) => l.startsWith("- "))).toMatch(/For a service or gig recording you'll remix: \*\*Input\*\*\. Avoid \+M and Post Fader\./);
    expect(mdx.indexOf("goes silent when the channel is muted")).toBeLessThan(mdx.indexOf("Analog +M"));
    expect(mdx).toMatch(/in the order the app shows them/);
    expect(mdx).not.toMatch(/earliest first/);
    expect(mdx).toMatch(/probably came with later firmware/);
    expect(mdx).toMatch(/clock is internal \(our reading\)/);
    expect(mdx).not.toMatch(/how you put a bus or the main mix on a USB channel/);
  });

  it("says the XR18 routing rarely needs changing but must be checked, and explains P16", () => {
    const routing = mdx.slice(mdx.indexOf("## XR18 USB routing"), mdx.indexOf("## XR18 playback"));
    expect(routing).toMatch(/Recording every channel\?/);
    expect(routing).toMatch(/P16 \(Behringer's personal monitor system\)/);
  });

  it("cites Midas's own MR18 manual, which lists the same systems as the XR18", () => {
    expect(mdx).toMatch(/confirms 18 x 18 USB, type B, and 44\.1 or 48 kHz/);
    expect(mdx).toContain("(https://cdn-media.empowertribe.com/f4e89140f9994eed93e4f2a4e086c578/M_MI_0605-AAF_MR18-MR12_EN.pdf)");
    expect(mdx).not.toMatch(/manualslib/);
    expect(mdx).not.toMatch(/retailer/i);
  });

  it("warns that a 2 x 2 setting sends only 2 channels, and that 48 kHz is the default", () => {
    expect(mdx).toMatch(/2 x 2 sends only 2 channels/);
    expect(mdx).toMatch(/48 kHz by default/);
  });

  it("says iPad is maker-confirmed for both, the iPhone isn't named, and ShowRecorder has recorded all 18 on one", () => {
    const apple = mdx.slice(mdx.indexOf("## XR18 on Mac, iPad and iPhone"), mdx.indexOf("## Sources"));
    expect(apple).toMatch(/iOS 7 or higher \(iPad\)/);
    expect(apple).toMatch(/doesn't name the iPhone/);
    // Owner fact O-2: an iPhone Take of all 18 XR18 channels; only a full show through a powered hub (#327) is untested.
    expect(apple).toMatch(/ShowRecorder \(the app this site makes\) has recorded all 18 XR18 channels on an iPhone/);
    expect(apple).toMatch(/full-length show on an iPhone through a powered hub is not tested yet/);
    expect(apple).toMatch(/Midas lists the same/);
  });
});

describe("the Allen & Heath Qu guide's facts", () => {
  const mdx = body("qu");
  const guide = MIXER_GUIDES.find((g) => g.slug === "qu")!;
  const short = mdx.slice(mdx.indexOf("**Short answer.**"), mdx.indexOf("**Quick start**"));

  // AI citation baseline (2026-11-06): no engine answered "Can I multitrack record a Qu-16 to an iPad?".
  // The "yes" is Allen & Heath staff's, not ours: the first sentence carries the attribution (it is what FAQPage
  // JSON-LD and a quoting AI answer pick up), and the untested status follows.
  it("answers 'Can I multitrack record a Qu-16 to an iPad?' in its short answer: whose yes, how many channels, which models", () => {
    const attributed = /^Allen & Heath staff say yes: iOS sees a Qu as a class-compliant multichannel device/;
    expect(short).toMatch(/^\*\*Short answer\.\*\* /);
    expect(short.replace("**Short answer.** ", "")).toMatch(attributed);
    expect(short).not.toMatch(/Yes, a Qu-16 can/);
    expect(short).toMatch(/Qu-16 sends 24 channels at 48 kHz/);
    for (const m of ["Qu-24", "Qu-32", "Qu-SB", "Qu-Pac", "Qu-5", "Qu-6", "Qu-7", "Qu-3"]) expect(short).toContain(m);
    expect(short).toMatch(/send 32/);
    expect(short).toMatch(/haven't tested/);
    expect(guide.faqs[0].q).toBe("Can I multitrack record a Qu-16 to an iPad?");
    expect(guide.faqs[0].a).toMatch(attributed);
    expect(guide.faqs[0].a).toMatch(/haven't tested/);
  });

  // Research: the default patch for new Qu USB sockets 3-32 is unknown, so the answer says to patch the direct outs.
  it("tells new Qu owners to patch the direct outs to USB rather than implying a default", () => {
    const tap = guide.faqs.find((f) => /pre or post fader/.test(f.q))!.a;
    expect(tap).toMatch(/On a new Qu, patch the input direct outs to USB; they include all processing before the Direct Out Source point you pick/);
    expect(tap).not.toMatch(/USB records the input direct outs/);
  });

  it("labels the cable tip as our advice and doesn't say a Qu Classic has nothing to set", () => {
    expect(mdx).toMatch(/We'd use a USB-C to USB-B cable/);
    expect(mdx).not.toMatch(/with nothing to set/);
    expect(mdx).toMatch(/there is no stream mode to set/);
  });

  it("keeps the two generations apart: new Qu on USB-C and SD, Qu Classic on USB-B and Qu-Drive", () => {
    expect(mdx).toMatch(/32 in and 32 out over USB-C, at 48 or 96 kHz/);
    expect(mdx).toMatch(/16 channels at 96 kHz, or 32 at 48 kHz/);
    expect(mdx).toMatch(/18 tracks, 48 kHz 24-bit WAV/);
    expect(mdx).toMatch(/USB-B, high speed USB 2\.0/);
  });

  it("gives the stream mode switch, the patch screens, and the 'Only 2 channels?' fix", () => {
    expect(mdx).toMatch(/\*\*SETUP > Audio > Sync & USB\*\*/);
    expect(mdx).toMatch(/\*\*I\/O > Outputs > USB\*\*/);
    expect(mdx).toMatch(/\*\*Setup > I\/O Patch > USB Audio\*\*/);
    expect(mdx).toMatch(/^### Only 2 channels\? Set USB Stream Mode to Multitrack$/m);
  });

  // The research's Gaps section (docs/research/mixer-recording/ah-qu.md): each is "not confirmed" or left out.
  it("respects the research gaps: no direct-out point names, no default for USB 3-32, no Qu-16 return count", () => {
    expect(mdx).toMatch(/doesn't list the point names/);
    expect(mdx).toMatch(/What sockets 3-32 carry out of the box is not confirmed/);
    expect(mdx + guide.faqs.map((f) => f.a).join(" ")).not.toMatch(/\b22\b/);
    expect(mdx).toMatch(/Which one your app gets is not confirmed/);
    expect(mdx).toMatch(/Clock source options are not confirmed/);
    expect(mdx).toMatch(/not confirmed for either generation/);
  });

  it("says ShowRecorder records a Qu, is untested on one, and has no Mixer Link for Allen & Heath", () => {
    const apple = mdx.slice(mdx.indexOf("## Qu on Mac, iPad and iPhone"), mdx.indexOf("## Sources"));
    expect(apple).toMatch(/ShowRecorder \(the app this site makes\) records every USB Channel/);
    expect(apple).toMatch(/nobody has tested it on a Qu yet/);
    expect(apple).toMatch(/so it should record a Qu over USB/);
    expect(apple).toMatch(/no Mixer Link for Allen & Heath/);
    expect(apple).toMatch(/we'd like to hear how it goes/);
    expect(apple).toMatch(/not possible for all devices to be tested and officially supported/);
    expect(guide.productPage).toBeUndefined();
  });

  it("marks the forum post as Allen & Heath staff", () => {
    expect(mdx.slice(mdx.indexOf("## Sources"))).toMatch(/Allen & Heath staff on its forum/);
  });
});

// Facts: docs/research/mixer-recording/m32.md (#1065), and x32.md where m32.md says the X32 facts apply. The M32
// shares the X32 page's routing; the guide calls out the differences: the DN32 cards and the M32 LIVE's SD recorder.
describe("the Midas M32 guide's facts", () => {
  const mdx = body("m32");
  const guide = MIXER_GUIDES.find((g) => g.slug === "m32")!;
  const all = () => mdx + guide.faqs.map((f) => f.q + " " + f.a).join(" ");

  it("is in MIXER_GUIDES with its own campaign, links the X32 and M32 product page, and the hub's M32 row links it", () => {
    expect(guide.campaign).toBe("site-guide-m32");
    expect(guide.productPage).toBe("/mixers/x32");
    expect(MIXER_ROWS.find((r) => /Midas M32/.test(r.name))!.guide).toBe(guide.path);
  });

  it("names the three cards and which consoles carry which, and that no card means no USB multitrack", () => {
    expect(mdx).toMatch(/\*\*DN32-USB:\*\*/);
    expect(mdx).toMatch(/\*\*DN32-LIVE:\*\*/);
    expect(mdx).toMatch(/\*\*XUF:\*\*/);
    expect(mdx).toMatch(/M32 LIVE and M32R LIVE/);
    expect(mdx).toMatch(/M32C/);
    expect(mdx).toMatch(/rear USB port is for remote control only/);
  });

  it("gives the DN32-USB and DN32-LIVE USB specs, and says what Midas doesn't state", () => {
    expect(mdx).toMatch(/32 in and 32 out, 24-bit at 48 kHz/);
    expect(mdx).toMatch(/32, 16, 8 or 2 channels/);
    expect(mdx).toMatch(/44\.1 kHz is not stated for the DN32-USB/);
    expect(mdx).toMatch(/bit depth on USB is not stated/);
  });

  it("gives the DN32-LIVE SD recorder limits and the stereo USB stick recorder", () => {
    expect(mdx).toMatch(/8, 16 or 32 channels/);
    expect(mdx).toMatch(/32-bit PCM/);
    expect(mdx).toMatch(/FAT32/);
    expect(mdx).toMatch(/32 GB/);
    expect(mdx).toMatch(/200 min/);
    expect(mdx).toMatch(/16-bit/);
    expect(mdx).toMatch(/2 GB/);
    expect(mdx).toMatch(/DN32-USB[^.]*can't record by itself/);
  });

  it("routes with card out blocks of 8 from the M32 manual, and stages buses in Out 1-16 or P16", () => {
    expect(mdx).toMatch(/\*\*ROUTING > card out\*\*/);
    expect(mdx).toMatch(/blocks of 8/);
    expect(mdx).toMatch(/\(M32 manual\)/);
    expect(mdx).toMatch(/Out 1-16/);
    expect(mdx).toMatch(/P16/);
  });

  // The research gaps: what is documented for the X32 only is labeled, never stated as a Midas fact.
  it("labels what is known only from the X32: user routing, the Setup > Card mode names, presets, card trim", () => {
    expect(mdx).toMatch(/^### Advanced: user routing \(firmware 4\.x, per user reports\)$/m);
    expect(mdx).toMatch(/No Midas document describes User In or User Out/);
    expect(mdx).toMatch(/32\/32, 16\/16, 32\/8, 8\/32, 8\/8 and 2\/2[^.]*X32[^.]*\(our reading\)/);
    expect(mdx).toMatch(/Record and Play[^.]*\(our reading\)/);
    expect(mdx).toMatch(/digital trim[^.]*\(our reading\)/);
    expect(mdx).toMatch(/reboot[^.]*X32/);
  });

  it("gives the tap points from the M32 manual and the shared stage box caveat", () => {
    const taps = section(mdx, "M32 tap points", "M32 on Mac, iPad and iPhone");
    // #1124 fact check: Midas's current manual lists nine taps for Out 1-16 (p. 26) and P16 (p. 27).
    expect(taps).toMatch(/IN\/LC, IN\/LC \+M, PreEQ, PreEQ \+M, PostEQ, PostEQ \+M, PreFdr, PreFdr \+M and Post Fader \(Midas M32 manual, pp\. 26-27\)/);
    expect(taps).not.toMatch(/forum users report newer names/);
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toMatch(/\(pp\. 26-27\)/);
    const notes = read("..", "docs", "research", "mixer-recording", "m32.md");
    expect(notes).not.toMatch(/X32 forum sources only/);
    expect(notes).toMatch(/IN\/LC[^\n]*PostEQ[^\n]*M-5 p\.26-27/);
    expect(taps).toMatch(/DL16 or DL32/);
    expect(taps).toMatch(/no gain compensation/i);
  });

  it("says iPhone, iPad and Mixer Link are not tested yet, and names no macOS version", () => {
    const apple = section(mdx, "M32 on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/iPhone and iPad:\*\* not documented, and not tested yet/);
    expect(apple).toMatch(/Mixer Link with an M32 is not tested yet/);
    expect(apple).toMatch(/emulator/);
    expect(all()).not.toMatch(/10\.12|Sonoma|Sequoia|Ventura/);
    expect(all()).not.toMatch(/unsupported/i);
  });

  // Fact check, loop 1 on #1108: X-LIVE and X32 facts are labeled; only what Midas states is stated.
  it("states only what Midas states, and labels what comes from the X32 or X-LIVE", () => {
    expect(mdx).not.toMatch(/Each session is one multichannel WAV/);
    expect(mdx).toMatch(/Files are uncompressed multichannel WAV \(8, 16 or 32 channels\) at the console's 44\.1 or 48 kHz, 32-bit PCM \(M32 LIVE guide\)/);
    expect(guide.faqs[0].a).toMatch(/as uncompressed multichannel 32-bit WAV/);
    expect(mdx).not.toMatch(/\*\*Bit depth:\*\* fixed/);
    expect(mdx).toMatch(/on the X32 it is fixed \(X32 manual\), and we expect the same on the M32 \(our reading\)/);
    expect(mdx).not.toMatch(/Confirm if asked/);
    expect(mdx).toMatch(/config: This screen offers adjustments for sample rates and synchronisation/); // spelling: ok (Midas's own word, quoted)
    expect(mdx).not.toMatch(/Input\/LC and \+M variants \(our reading for the M32\)/);
    expect(mdx).toMatch(/through a card in its expansion slot \(DN32-USB, DN32-LIVE or XUF\)/);
    expect(mdx).not.toMatch(/DN32-USB is always 32 x 32/);
    expect(mdx).toMatch(/On a DN32-LIVE, set \*\*Setup > Card\*\* to 32 each way \(the DN32-USB is 32 x 32\)/);
    expect(mdx).toMatch(/it is built to also read channel names and colors over Mixer Link/);
    expect(guide.faqs.find((f) => /main mix/.test(f.q))!.a).toMatch(/per user reports \(our reading\)/);
  });

  it("marks the Midas documents read on third-party hosts, and the forum posts as not Midas", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toMatch(/hosted by/);
    expect(sources).toMatch(/not Midas/);
  });

  // #1111: Midas's own manual and M32 LIVE guide, linked from midasconsoles.com, are now in hand.
  it("cites Midas's own M32 manual and M32 LIVE guide from midasconsoles.com, and never midasgroup.com", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    for (const url of [MIDAS_M32_MANUAL, MIDAS_M32_LIVE_QSG]) {
      expect(sources).toContain(`](${url})`);
      expect(guide.sources).toContain(url);
    }
    expect(sources).toMatch(/Midas moved to midasconsoles\.com/);
    const notes = read("..", "docs", "research", "mixer-recording", "m32.md");
    expect(notes).toContain(MIDAS_M32_MANUAL);
    expect(notes).toContain(MIDAS_M32_LIVE_QSG);
    for (const text of [mdx, notes, guide.sources.join(" ")]) expect(text).not.toMatch(/midasgroup/);
  });

  // #1111: the card-out step quotes and the name "XUF" are only in the ManualsLib copy, not Midas's current manual.
  it("says the card-out quotes and the XUF name come from an earlier edition of the M32 manual, on ManualsLib", () => {
    expect(mdx).toMatch(/"Tap the first control to assign the selected output path, completing the process" \(an earlier edition of the M32 manual, on ManualsLib\)/);
    expect(mdx).not.toMatch(/"(Adjust the first rotary control|Tap the first control)[^"]*" \(M32 manual\)/);
    expect(mdx).toMatch(/\*\*XUF:\*\*[^\n]*an earlier edition of the M32 manual, on ManualsLib/);
  });

  it("gives the SD card sizes the M32 LIVE guide gives: SD or SDHC, 1 to 32 GB per slot", () => {
    expect(mdx).not.toMatch(/SDXC/);
    expect(mdx).toMatch(/SD or SDHC cards \(FAT32, 1 to 32 GB per slot\)/);
    expect(read("..", "docs", "research", "mixer-recording", "m32.md")).not.toMatch(/SDXC above 32 GB is not supported/);
  });
});

// Plain-language pass (#1111, Eric 2026-11-07): the guides are for laypeople, such as a church volunteer with the mixer
// and an iPhone. Each term is explained where it first appears (or links the glossary), and prose sentences stay short.
const PLAIN_TERMS: readonly { term: RegExp; explained: RegExp }[] = [
  { term: /tap points?/i, explained: /where (in the channel )?the (recording|feed)[^.]*(is taken|comes from)|#glossary/ },
  { term: /pre-fader/i, explained: /before the (channel |main )?fader|fader doesn't change|#glossary/ },
  { term: /class compliant/i, explained: /no driver|without a driver|#glossary/ },
  { term: /virtual soundcheck|virtual sound check/i, explained: /play(s|ing)? (a|the) recording back|no band|#glossary/ },
  { term: /USB returns?/i, explained: /back (in|into|from)|comes back|#glossary/ },
];

// The prose of a guide, one sentence per entry: no headings, code, comments, Sources, link targets or emphasis marks.
const proseSentences = (mdx: string) =>
  mdx
    .slice(0, mdx.indexOf("## Sources"))
    .split("\n")
    .filter((l) => l.trim() && !/^(#|import|export|<|\{\/\*)/.test(l.trim()))
    .map((l) => l.replace(/\]\([^)]*\)/g, "]").replace(/[*[\]`]/g, "").replace(/^\s*(-|\d+\.)\s*/, ""))
    .flatMap((l) => l.split(/(?<=[.:;?])\s+(?=[A-Z"(])/))
    .filter((s) => s.trim());

describe.each(["mackie-dl32r", "mackie-dl32s", "m32"])("the %s guide, for beginners", (slug) => {
  const mdx = body(slug);
  const lines = mdx
    .slice(0, mdx.indexOf("## Sources"))
    .split("\n")
    .filter((l) => l.trim() && !/^(#|import|export|<|\{\/\*)/.test(l.trim()));

  it.each(PLAIN_TERMS.map((t) => [t.term.source, t] as const))("explains %s where it first appears", (_, { term, explained }) => {
    const first = lines.find((l) => term.test(l.replace(/\]\([^)]*\)/g, "]")));
    if (first === undefined) return;
    expect(first).toMatch(explained);
  });

  it("keeps every prose sentence to 30 words or fewer", () => {
    const long = proseSentences(mdx).filter((s) => s.split(/\s+/).filter(Boolean).length > 30);
    expect(long).toEqual([]);
  });
});

describe("guide headlines", () => {
  it("say 'an' before a vowel", () => {
    expect(guideHeadline("Allen & Heath Qu")).toBe("How to multitrack record an Allen & Heath Qu");
    expect(guideHeadline("Behringer X32")).toBe("How to multitrack record a Behringer X32");
  });
});

// Facts: docs/research/mixer-recording/zoom-livetrak-l12-l20.md (#1080). Zoom is the one maker that names the iPhone.
describe("the Zoom LiveTrak L-12 and L-20 guide's facts", () => {
  const mdx = body("zoom-l12");
  const guide = MIXER_GUIDES.find((g) => g.slug === "zoom-l12")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's Zoom row links it", () => {
    expect(guide.campaign).toBe("site-guide-zoom-l12");
    expect(MIXER_ROWS.find((r) => /Zoom/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives the USB channel counts, the 44.1/48 kHz limit, and that USB stops at 96 kHz", () => {
    expect(mdx).toMatch(/14 channels/);
    expect(mdx).toMatch(/22 channels/);
    expect(mdx).toMatch(/44\.1 or 48 kHz/);
    expect(mdx).toMatch(/audio interface is off/);
  });

  it("names the rear switches, read at power-on, and the Class Compliant Mode switch for iPhone and iPad", () => {
    expect(mdx).toMatch(/\*\*CLASS COMPLIANT MODE\*\*/);
    expect(mdx).toMatch(/\*\*MODE\*\*/);
    expect(mdx).toMatch(/\*\*SAMPLE RATE\*\*/);
    expect(mdx).toMatch(/cannot be changed after starting up/);
    expect(mdx).toMatch(/before you turn it on/);
  });

  it("says the USB order is fixed, with no per-slot routing, and the driver can move the master to 1/2", () => {
    const routing = section(mdx, "L-12 and L-20 USB routing", "L-12 and L-20 playback for virtual soundcheck");
    expect(routing).toMatch(/fixed/i);
    expect(routing).toMatch(/master/i);
    expect(routing).toMatch(/Mac and Windows driver only/);
  });

  it("gives the tap points: post-compressor, pre-EQ, the L-20 REC SOURCE for SD only, from the block diagram", () => {
    const taps = section(mdx, "L-12 and L-20 tap points", "L-12 and L-20 on Mac, iPad and iPhone");
    expect(taps).toMatch(/after the compressor/i);
    expect(taps).toMatch(/before the EQ/i);
    expect(taps).toMatch(/\*\*REC SOURCE\*\*/);
    expect(taps).toMatch(/PRE COMP/);
    expect(taps).toMatch(/per Zoom's block diagram/);
  });

  it("says Zoom names the iPhone and iPad, with a Lightning camera adapter, USB-C not tested, and no Mixer Link", () => {
    const apple = section(mdx, "L-12 and L-20 on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/Zoom names the iPhone/);
    expect(apple).toMatch(/Lightning-to-USB Camera Adapter required/);
    expect(apple).toMatch(/USB-C[^.]*not tested yet/);
    expect(apple).toMatch(/install Zoom's driver/i);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/ShowRecorder has recorded[^.]*(L-12|L-20|Zoom)/);
  });

  // Fact check, loop 1 on #1101: only what Zoom states is stated; our readings and advice say so.
  it("labels our readings and advice, and states only what Zoom's text says", () => {
    const faq = guide.faqs.find((f) => /see no audio/.test(f.q))!;
    expect(faq.a).toMatch(/MODE and SAMPLE RATE are read at power-on \(Zoom\); set CLASS COMPLIANT MODE before power-on too \(our advice\)/);
    expect(mdx).not.toMatch(/records silence there/);
    expect(mdx).not.toMatch(/before the EQ, LOW CUT, fader and pan/);
    expect(mdx).toMatch(/the same channels to their own SD card/);
    expect(mdx).not.toMatch(/same tracks to their own SD card/);
    expect(mdx).toMatch(/then press \*\*REC\*\* \(L-12 manual\)/);
    expect(mdx).toMatch(/REC FORMAT\*\* \(L-12 manual\)/);
    expect(mdx).not.toMatch(/the app that records sets it\./);
    expect(mdx).not.toMatch(/Turning it during the show changes the recorded level\./);
    const l20usb = mdx.split("\n").find((l) => l.startsWith("- **L-20, USB:**"))!;
    expect(l20usb).toMatch(/^- \*\*L-20, USB:\*\* after the compressor, whatever/);
    expect(l20usb).toMatch(/before the EQ[^.]*per Zoom's block diagram \(our reading\)/);
  });

  it("records to an SD card with no computer: 14 or 22 tracks, WAV, a new file every 2 GB", () => {
    expect(mdx).toMatch(/SD card/);
    expect(mdx).toMatch(/2 GB/);
    expect(mdx).toMatch(/TRACK01/);
  });
});

// Facts: docs/research/mixer-recording/mackie-dl32r.md (#1079). The manual's spec table says 24 drive tracks, its text
// and the newer Master Fader 5 guide say 32: the page says so plainly.
describe("the Mackie DL32R guide's facts", () => {
  const mdx = body("mackie-dl32r");
  const guide = MIXER_GUIDES.find((g) => g.slug === "mackie-dl32r")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's DL32R row links it", () => {
    expect(guide.campaign).toBe("site-guide-mackie-dl32r");
    expect(MIXER_ROWS.find((r) => r.name === "Mackie DL32R")!.guide).toBe(guide.path);
  });

  it("gives USB: 32 in and 32 out, 48 kHz only, 16 or 24-bit, class compliant, a driver on Windows", () => {
    expect(mdx).toMatch(/32 in and 32 out/);
    expect(mdx).toMatch(/48 kHz only/);
    expect(mdx).toMatch(/16 or 24-bit/);
    expect(mdx).toMatch(/class compliant/i);
    expect(mdx).toMatch(/Windows[^.]*driver/);
  });

  it("says the drive and a computer can't record at the same time", () => {
    expect(mdx).toMatch(/can't be used at the same time/);
    expect(mdx).toMatch(/USB A and USB B connectors may NOT be used simultaneously/);
  });

  it("names the drive track-count contradiction plainly: 24 in the 2015 spec table, 32 in the text and the 2018 guide", () => {
    expect(mdx).toMatch(/1-24 channel/);
    expect(mdx).toMatch(/1-32/);
    expect(mdx).toMatch(/contradict/i);
    expect(mdx).toMatch(/\(our reading\)/);
  });

  it("gives the drive rules: one multichannel WAV per take, split under 2 GB, a spinning hard drive, no thumb drive, no hub", () => {
    expect(mdx).toMatch(/multichannel/);
    expect(mdx).toMatch(/2 GB/);
    expect(mdx).toMatch(/spinning hard/);
    expect(mdx).toMatch(/Do not use a thumb drive/);
    expect(mdx).toMatch(/hub/);
    expect(mdx).toMatch(/100 MB/);
  });

  it("gives the per-slot routing path, the default and the main mix example", () => {
    const routing = section(mdx, "DL32R USB routing", "DL32R playback for virtual soundcheck");
    expect(routing).toMatch(/\*\*I\/O Patch\*\*/);
    expect(routing).toMatch(/\*\*USB\*\* tab/);
    expect(routing).toMatch(/Mic Pre 1-32 to USB 1-32/);
    expect(routing).toMatch(/Main L\/R/);
  });

  it("gives virtual soundcheck through Input B", () => {
    const pb = section(mdx, "DL32R playback for virtual soundcheck", "DL32R tap points");
    expect(pb).toMatch(/Input B/);
    expect(pb).toMatch(/A Tracks \/ B Tracks/);
  });

  it("gives both taps from the block diagram, and labels the second-iPad gain point as our reading", () => {
    const taps = section(mdx, "DL32R tap points", "DL32R on Mac, iPad and iPhone");
    expect(taps).toMatch(/\*\*Mic Pre\*\*/);
    expect(taps).toMatch(/Post-DSP/);
    expect(taps).toMatch(/Access Limiting/);
    expect(taps).toMatch(/\(our reading\)/);
  });

  it("says the manual names the iPad with a camera adapter, the iPhone is not tested yet, and there is no Mixer Link", () => {
    const apple = section(mdx, "DL32R on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/camera connection kit/);
    expect(apple).toMatch(/iPhone[^.]*not tested yet/);
    expect(apple).toMatch(/10\.11/);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/unsupported/i);
  });

  // Fact check, loop 1 on #1106: no claim past the sources; our readings say so.
  it("makes no unsourced power or clock claim, and labels its readings", () => {
    expect(mdx).not.toMatch(/powers nothing/);
    expect(mdx).toMatch(/Mackie doesn't say whether USB B charges an iPad\./);
    expect(mdx).not.toMatch(/\*\*Clock:\*\* internal/);
    expect(mdx).toMatch(/\*\*Clock:\*\* Mackie documents no word clock\. An optional Dante card is offered \(spec sheet\)\./);
    expect(read("..", "docs", "research", "mixer-recording", "mackie-dl32r.md")).not.toMatch(/Clock: internal/);
    expect(mdx).not.toMatch(/always offers 32 x 32/);
    expect(mdx).toMatch(/so we expect 32 x 32 every time \(our reading\)/);
    // #1124 fact check: say what Mackie documents, not what the mixer has; the default is one input per channel.
    expect(mdx).toMatch(/Mackie documents no mode or channel-count option/);
    expect(mdx).toMatch(/32 channels at 48 kHz, by default one per input/);
    expect(section(mdx, "Ways to record a DL32R", "DL32R recording settings")).toMatch(/\*\*Set the drive up:\*\*[^\n]*FAT32/);
    expect(read("..", "docs", "research", "mixer-recording", "mackie-dl32r.md")).not.toMatch(/p\.209/);
    expect(read("..", "docs", "research", "mixer-recording", "xr18-mr18.md")).not.toMatch(/midasgroup/);
    expect(mdx).toMatch(/after the Mic Pre tap \(block diagram\)/);
    expect(mdx).not.toMatch(/sound like front of house/);
    expect(mdx).toMatch(/Use it for processed tracks \(our advice\)\./);
    expect(guide.faqs.find((f) => /pre or post fader/.test(f.q))!.a).toMatch(/^For the channels, pre-fader either way\./);
    expect(MIXER_ROWS.find((r) => r.name === "Mackie DL32R")!.onboard).toMatch(/\(older units may show 24 until updated; our reading\)/);
  });

  // #1111: Mackie hosts the current guide (V5.1, Feb 2026) itself; the Ambertech V5.0 copy is secondary at most.
  it("cites Mackie's own Master Fader V5.1 guide first, from help.mackie.com", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toContain(`](${MACKIE_MF_DOWNLOADS})`);
    expect(sources).toMatch(/V5\.1[^\n]*2026/);
    expect(guide.sources).toContain(MACKIE_MF_DOWNLOADS);
    const ambertech = sources.indexOf("ambertech.com.au");
    if (ambertech >= 0) expect(sources.indexOf(MACKIE_MF_DOWNLOADS)).toBeLessThan(ambertech);
    expect(read("..", "docs", "research", "mixer-recording", "mackie-dl32r.md")).toContain(MACKIE_MF_DOWNLOADS);
  });

  // #1111: the FAQ page shows an error in a real browser; the meter fact now rests on the V5.1 guide (p. 38).
  it("doesn't link Mackie's DL32R FAQ page, and sources the meter point from the V5.1 guide", () => {
    expect(mdx).not.toMatch(/mackie\.com\/en\/support\/faq/);
    expect(guide.sources).not.toContain("https://mackie.com/en/support/faq/dl32r.html");
    expect(mdx).not.toMatch(/Input meters are fixed Pre DSP/);
    expect(mdx).toMatch(/before all channel processing/);
    expect(read("..", "docs", "research", "mixer-recording", "mackie-dl32r.md")).not.toMatch(/\[FAQ\] excerpt/);
  });

  it("says the 2026 V5.1 guide also gives 32 drive channels at 48 kHz, 24-bit (p. 210)", () => {
    const tracks = section(mdx, "DL32R recording settings", "DL32R USB routing");
    expect(tracks).toMatch(/2026 V5\.1 guide also says[^.]*32 channels \(48 kHz, 24-bit\)[^.]*p\. 210/);
  });

  it("cites V5.1 page numbers in the research notes (block diagram pp. 290-291, not V5.0's p. 284)", () => {
    const notes = read("..", "docs", "research", "mixer-recording", "mackie-dl32r.md");
    expect(notes).not.toMatch(/p\.284/);
    expect(notes).toMatch(/RG p\.290-291/);
    expect(notes).toMatch(/RG p\.210\]/);
  });
});

// Facts: docs/research/mixer-recording/wing.md (#1066). iPad reports conflict and the Mac driverless report is a forum
// post: the guide says both plainly, and says not tested yet for the iPhone.
describe("the Behringer WING guide's facts", () => {
  const mdx = body("wing");
  const guide = MIXER_GUIDES.find((g) => g.slug === "wing")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's WING row links it", () => {
    expect(guide.campaign).toBe("site-guide-wing");
    expect(MIXER_ROWS.find((r) => /WING/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives the USB channel counts, 24-bit, the USB AUDIO setting and the unconfirmed 44.1 kHz", () => {
    expect(mdx).toMatch(/48 x 48/);
    expect(mdx).toMatch(/24-bit/);
    expect(mdx).toMatch(/\*\*SETUP > AUDIO > USB AUDIO\*\*/);
    expect(mdx).toMatch(/2 x 2, 8 x 8, 16 x 16, 32 x 32 or 48 x 48/);
    expect(mdx).toMatch(/44\.1 kHz[^.]*not confirmed/);
  });

  it("records with no computer: WING-LIVE to two SD cards, and a 4-track USB stick that needs HS", () => {
    expect(mdx).toMatch(/64 channels/);
    expect(mdx).toMatch(/32-bit/);
    expect(mdx).toMatch(/LiveSessions/);
    expect(mdx).toMatch(/FAT32/);
    expect(mdx).toMatch(/32 kB/);
    expect(mdx).toMatch(/\*\*USB HOST SPEED\*\*/);
    expect(mdx).toMatch(/2 tracks at 16-bit/);
  });

  it("routes per slot on ROUTING > OUTPUTS, with User Signals for processed channels, and gives no default routing", () => {
    const routing = section(mdx, "WING USB routing", "WING playback for virtual soundcheck");
    expect(routing).toMatch(/\*\*ROUTING > OUTPUTS\*\*/);
    expect(routing).toMatch(/no blocks of 8/);
    expect(routing).toMatch(/WLIVE REC/);
    expect(routing).toMatch(/RECORDER/);
    expect(routing).toMatch(/User Signal/);
    expect(routing).toMatch(/patch every slot/i);
    expect(routing).not.toMatch(/\+1 AUTO/);
    expect(routing).not.toMatch(/\b48 User Signals\b/);
  });

  it("plays back through each channel's ALT input, switched by INPUT SELECT", () => {
    const play = section(mdx, "WING playback for virtual soundcheck", "WING tap points");
    expect(play).toMatch(/WLIVE PLAY/);
    expect(play).toMatch(/USB PLAYER/);
    expect(play).toMatch(/\*\*ALT\*\*/);
    expect(play).toMatch(/INPUT SELECT/);
  });

  it("lists the eight channel TAP points in Behringer's words, and labels the trim reading as ours", () => {
    const taps = section(mdx, "WING tap points", "WING on Mac, iPad and iPhone");
    expect(taps).toMatch(/INPUT, FILTER, TAP 3, TAP 4, TAP 5, PRE FDR, POST FDR and POST PROC/);
    expect(taps).toMatch(/immediately after the preamp, before any processing/);
    expect(taps).toMatch(/before the digital TRIM[^.]*\(our reading\)/);
    expect(taps).toMatch(/fixed post insert point and pre-fader/);
    expect(taps).toMatch(/changes the recording/);
  });

  it("says the iPad reports conflict, the iPhone is not tested yet, a Mac driverless only per a forum user, and no Mixer Link", () => {
    const apple = section(mdx, "WING on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/[Rr]eports differ/);
    expect(apple).toMatch(/iPhone[^.]*not tested yet/);
    expect(apple).toMatch(/Behringer doesn't say/);
    expect(apple).toMatch(/forum/);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/unsupported/i);
    expect(mdx).not.toMatch(/ShowRecorder has recorded[^.]*WING/);
  });

  it("warns that the rear USB port can turn into a USB disk, and how to get audio back", () => {
    expect(mdx).toMatch(/WING OS/);
    expect(mdx).toMatch(/WING DATA/);
    expect(mdx).toMatch(/[Ee]ject/);
  });
});

// Facts: docs/research/mixer-recording/mackie-dl32s.md (#1078). Mackie names no iPhone or iPad for the DL32S.
describe("the Mackie DL32S guide's facts", () => {
  const mdx = body("mackie-dl32s");
  const guide = MIXER_GUIDES.find((g) => g.slug === "mackie-dl32s")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's DL32S row links it", () => {
    expect(guide.campaign).toBe("site-guide-mackie-dl32s");
    expect(MIXER_ROWS.find((r) => /DL32S/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives 32 x 32 (16 x 16 on the DL16S), 48 kHz only, 16/24-bit, and no onboard recorder", () => {
    expect(mdx).toMatch(/32 channels/);
    expect(mdx).toMatch(/DL16S[^.]*16 channels/);
    expect(mdx).toMatch(/48 kHz only/);
    expect(mdx).toMatch(/16 or 24-bit/);
    expect(mdx).toMatch(/can't record by itself/);
  });

  it("routes per slot in Master Fader's I/O Patch > USB tab, Mic Pre N to USB N by default", () => {
    const routing = section(mdx, "DL32S USB routing", "DL32S playback for virtual soundcheck");
    expect(routing).toMatch(/\*\*I\/O Patch\*\*/);
    expect(routing).toMatch(/\*\*USB\*\* tab/);
    expect(routing).toMatch(/Mic Pre 1-32 to USB 1-32/);
    expect(routing).toMatch(/Any combination of channels or outputs/);
    expect(routing).toMatch(/Main L\/R/);
    expect(routing).toMatch(/Reset to Default/);
  });

  it("plays back through Input B, the USB returns, for virtual soundcheck", () => {
    const vsc = section(mdx, "DL32S playback for virtual soundcheck", "DL32S tap points");
    expect(vsc).toMatch(/Input A/);
    expect(vsc).toMatch(/Input B/);
    expect(vsc).toMatch(/virtual sound check/);
  });

  it("gives both taps from the block diagram: Mic Pre before trim and HPF, Channel Post-DSP after EQ, before mute and fader", () => {
    const taps = section(mdx, "DL32S tap points", "DL32S on Mac, iPad and iPhone");
    expect(taps).toMatch(/\*\*Mic Pre\*\*[^\n]*before[^\n]*Digital Trim/);
    expect(taps).toMatch(/\*\*Channel Post-DSP\*\*[^\n]*before the mute and fader/);
    expect(taps).toMatch(/6 dB/);
    expect(taps).toMatch(/Access Limiting/);
    expect(taps).toMatch(/\(our reading\)/);
  });

  it("says a Mac needs no driver, Windows needs Mackie's, and the iPhone and iPad are not tested yet, with no Mixer Link", () => {
    const apple = section(mdx, "DL32S on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/no additional drivers/);
    expect(apple).toMatch(/Windows[^.]*driver/);
    expect(apple).toMatch(/iPhone[^.]*not tested yet/);
    expect(apple).toMatch(/macOS 10\.13 and 10\.14/);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/ShowRecorder has recorded[^.]*DL32S/);
    expect(guide.faqs.find((f) => /iPhone|iPad/.test(f.q))!.a).toMatch(/not tested yet/i);
  });

  // #1111: Mackie hosts the current guide (V5.1, Feb 2026) itself; the Ambertech V5.0 copy is secondary at most.
  it("cites Mackie's own Master Fader V5.1 guide first, from help.mackie.com, and not the DL32R FAQ page", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toContain(`](${MACKIE_MF_DOWNLOADS})`);
    expect(sources).toMatch(/V5\.1[^\n]*2026/);
    expect(guide.sources).toContain(MACKIE_MF_DOWNLOADS);
    const ambertech = sources.indexOf("ambertech.com.au");
    if (ambertech >= 0) expect(sources.indexOf(MACKIE_MF_DOWNLOADS)).toBeLessThan(ambertech);
    const notes = read("..", "docs", "research", "mixer-recording", "mackie-dl32s.md");
    expect(notes).toContain(MACKIE_MF_DOWNLOADS);
    expect(notes).not.toMatch(/mackie\.com\/en\/support\/faq/);
  });

  it("keeps the SE models apart: their patch menu is not in the Master Fader guide", () => {
    expect(mdx).toMatch(/DL32SE/);
    expect(mdx).toMatch(/SE models[^.]*not in/);
  });
});

// Facts: docs/research/mixer-recording/soundcraft-ui24r.md (#1072). Soundcraft states no file format for the onboard
// multitrack and names no iPhone or iPad.
describe("the Soundcraft Ui24R guide's facts", () => {
  const mdx = body("ui24r");
  const guide = MIXER_GUIDES.find((g) => g.slug === "ui24r")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's Ui24R row links it", () => {
    expect(guide.campaign).toBe("site-guide-ui24r");
    expect(MIXER_ROWS.find((r) => /Ui24R/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives 32 x 32 USB at 48 kHz, the Mac with no driver and Windows with Soundcraft's driver", () => {
    expect(mdx).toMatch(/32 x 32 USB Audio Interface/);
    expect(mdx).toMatch(/48 kHz/);
    expect(mdx).toMatch(/Core Audio compliant/);
    expect(mdx).toMatch(/V3\.20 or later/);
    expect(mdx).toMatch(/bit depth[^.]*not stated/i);
  });

  it("gives the fixed USB map: 1-2 master, 3-10 AUX 1-8, 11-32 inputs 1-22, not patchable", () => {
    const routing = section(mdx, "Ui24R USB routing", "Ui24R playback for virtual soundcheck");
    expect(routing).toMatch(/USB 1-2[^\n]*Master L\/R/);
    expect(routing).toMatch(/USB 3-10[^\n]*AUX 1-8/);
    expect(routing).toMatch(/USB 11-32[^\n]*inputs 1-22/);
    expect(routing).toMatch(/No USB send patching is required/);
    expect(routing).toMatch(/POST PROC/);
    // Fact check on #1110: the forum claim that the main mix is post-processing has no fetchable source.
    expect(routing).toMatch(/doesn't state where the main mix on USB 1-2 is taken/);
    expect(routing).not.toMatch(/after the processing/);
  });

  it("records up to 22 tracks to a FAT32 USB drive of 32 GB or less, and says Soundcraft doesn't state the file format", () => {
    expect(mdx).toMatch(/22 tracks/);
    expect(mdx).toMatch(/MEDIA - REC/);
    expect(mdx).toMatch(/FAT32/);
    expect(mdx).toMatch(/32 GB or less/);
    expect(mdx).toMatch(/file format[^.]*not stated by Soundcraft/i);
    expect(mdx).toMatch(/WAV or FLAC[^.]*2017 Sound On Sound review/);
    expect(mdx).toMatch(/\*\*SETTINGS > 2 TRK RECORD MODE\*\*/);
  });

  it("plays back from the USB returns and from the drive's Soundcheck patch", () => {
    const play = section(mdx, "Ui24R playback for virtual soundcheck", "Ui24R tap points");
    expect(play).toMatch(/SETTINGS > PATCHING > CHANNELS/);
    expect(play).toMatch(/Patch 1:1/);
    expect(play).toMatch(/Soundcheck/);
    expect(play).toMatch(/SETTINGS > PATCHING > OVERVIEW/);
  });

  // Fact check on #1110: the forum post (proforums.harman.com) doesn't resolve, so no claim rests on it.
  it("gives the tap as straight after the preamp, pre-fader and pre-processing, with our readings labeled and no forum claim", () => {
    const taps = section(mdx, "Ui24R tap points", "Ui24R on Mac, iPad and iPhone");
    expect(taps).toMatch(/directly from the mic preamps/);
    expect(taps).toMatch(/pre-fader, pre-processing/);
    expect(taps).toMatch(/\(our reading\)/);
    expect(mdx).not.toMatch(/forum|proforums\.harman\.com/i);
    expect(taps).not.toMatch(/pre-HPF|before the HPF/);
  });

  it("says Soundcraft doesn't name the iPhone or iPad, not tested yet, and no Mixer Link", () => {
    const apple = section(mdx, "Ui24R on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/neither is tested yet/);
    expect(apple).toMatch(/Soundcraft doesn't say/);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/unsupported/i);
    expect(mdx).not.toMatch(/ShowRecorder has recorded[^.]*Ui24R/);
  });

  // #1111: both Soundcraft PDFs were read in full in a real browser, from Harman's file host, and matched the guide.
  it("notes in its research that the v1.0 manual and v2.0 addendum were read in full on 2026-11-07 and matched", () => {
    const notes = read("..", "docs", "research", "mixer-recording", "soundcraft-ui24r.md");
    expect(notes).toMatch(/v1\.0[^\n]*v2\.0 (User Guide )?[Aa]ddendum[^\n]*read in full on 2026-11-07[^\n]*adn\.harmanpro\.com[^\n]*match/);
  });
});

// Facts: docs/research/mixer-recording/ah-cq.md (#1070). Maker facts come from Allen & Heath's help center and its
// staff on the forum; everything else on the forum is one user's report and is labeled as such.
describe("the Allen & Heath CQ guide's facts", () => {
  const mdx = body("ah-cq");
  const guide = MIXER_GUIDES.find((g) => g.slug === "ah-cq")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's CQ row links it", () => {
    expect(guide.campaign).toBe("site-guide-ah-cq");
    expect(MIXER_ROWS.find((r) => /CQ-12T/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives each model's USB channel count at 48 or 96 kHz over a class-compliant USB 2.0 port, with no Mac driver", () => {
    const ways = section(mdx, "Ways to record a CQ", "CQ recording settings");
    expect(ways).toMatch(/CQ-12T:\*\* 16 channels to the computer, 16 back/);
    expect(ways).toMatch(/CQ-18T:\*\* 24 channels to the computer, 22 back/);
    expect(ways).toMatch(/CQ-20B:\*\* 24 channels to the computer, 24 back/);
    expect(ways).toMatch(/48 or 96 kHz/);
    expect(ways).toMatch(/USB 2\.0/);
    expect(ways).toMatch(/Core Audio compliant/);
    expect(ways).toMatch(/Windows driver \(called ASIO\)/);
    expect(ways).toMatch(/Bit depth over USB:\*\* not stated by Allen & Heath/);
  });

  it("puts Stream Mode = Multitrack first, with its menu path, as the fix for seeing only 2 channels", () => {
    const quick = mdx.slice(mdx.indexOf("**Quick start**"), mdx.indexOf("\n## "));
    expect(quick).toMatch(/^1\. \*\*Set Stream Mode to Multitrack\.\*\*/m);
    const settings = section(mdx, "CQ recording settings", "CQ USB routing");
    expect(settings).toMatch(/^### Only 2 channels\? Set Stream Mode to Multitrack$/m);
    expect(settings).toMatch(/\*\*CONFIG\*\*, then \*\*Digital Audio\*\*, then \*\*USB\/SD\*\*/);
    expect(settings).toMatch(/One setting covers USB-B, the USB stick and the SD card|This one setting covers USB-B, the USB stick and the SD card/);
  });

  it("gives the fixed 1:1 input map, the stereo pairs you choose per model, and Main LR on the last pair", () => {
    const routing = section(mdx, "CQ USB routing", "CQ playback for virtual soundcheck");
    expect(routing).toMatch(/CQ input 7 is being sent to USB channel 7/);
    expect(routing).toMatch(/CQ-12T:\*\* USB 1-10 are inputs 1-10\. USB 11-16 are 3 stereo pairs/);
    expect(routing).toMatch(/CQ-18T and CQ-20B:\*\* USB 1-16 are inputs 1-16\. USB 17-24 are 4 stereo pairs/);
    expect(routing).toMatch(/Channel Assignment/);
    expect(routing).toMatch(/The last stereo pair is set to Main LR by default/);
    expect(routing).toMatch(/Other pairs' defaults:\*\* not stated/);
  });

  it("records every channel to an SD card, 16 at 96 kHz on the 18T and 20B, and only stereo to a USB stick", () => {
    const ways = section(mdx, "Ways to record a CQ", "CQ recording settings");
    expect(ways).toMatch(/CQ-18T and CQ-20B:\*\* 24 tracks at 48 kHz, or 16 tracks at 96 kHz/);
    expect(ways).toMatch(/mono 24-bit WAV/);
    expect(ways).toMatch(/SDHC card of 32 GB or less, marked UHS-I and Class 10/);
    expect(ways).toMatch(/\*\*HOME\*\*, then \*\*RECORD\*\*, then \*\*Multitrack\*\*/);
    expect(ways).toMatch(/USB stick records only stereo/);
    expect(ways).toMatch(/can't run at the same time/);
  });

  it("plays back through Input Source = USB/SD, and sets the digital Trim, not the preamp Gain, for USB channels", () => {
    const play = section(mdx, "CQ playback for virtual soundcheck", "CQ tap points");
    expect(play).toMatch(/\*\*CONFIG\*\*, then \*\*INPUTS\*\*/);
    expect(play).toMatch(/\*\*Input Source\*\* to \*\*USB\/SD\*\*/);
    expect(play).toMatch(/Multi Select/);
    expect(play).toMatch(/\*\*Trim\*\*/);
  });

  it("gives one global Source Point, labels the forum's option names and post-fader claim as users' reports, and explains pre-fader", () => {
    const taps = section(mdx, "CQ tap points", "CQ on Mac, iPad and iPhone");
    expect(taps).toMatch(/\*\*Source Point\*\*, on \*\*CONFIG\*\*/);
    expect(taps).toMatch(/no input channel processing, some processing, or all processing/);
    // The option names come from one user's list, never as Allen & Heath's.
    const names = taps.split("\n").filter((l) => /Post AMM|Post Preamp/.test(l));
    expect(names.length).toBeGreaterThan(0);
    for (const l of names) expect(l).toMatch(/user/);
    expect(taps).toMatch(/users say there's no post-fader option, and we couldn't confirm one/i);
    expect(taps).toMatch(/factory setting:\*\* not stated by Allen & Heath/);
    expect(taps).toMatch(/Auto Gain/);
    expect(taps).toMatch(/before the fader[^\n]*pre-fader/i);
    const faq = guide.faqs.find((f) => /pre or post fader/.test(f.q))!;
    expect(faq.a).toMatch(/Users say there's no post-fader option, and we couldn't confirm one/);
  });

  it("says the iPad works per Allen & Heath staff, the iPhone is not tested yet, and the CQ records without Mixer Link", () => {
    const apple = section(mdx, "CQ on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/iPad:\*\* Allen & Heath staff on its forum say it works/);
    expect(apple).toMatch(/iPhone:\*\* Allen & Heath doesn't name it, and we haven't tested one yet/);
    expect(apple).toMatch(/designed only to power a USB drive/);
    // Fact check on #1114: no untested result ("so it records a CQ").
    expect(mdx).toMatch(
      /records every USB Channel from any class-compliant mixer\. We haven't tested it with a CQ yet\. There is no Mixer Link for the CQ/,
    );
    expect(mdx).not.toMatch(/so it records a CQ/);
    expect(mdx).not.toMatch(/unsupported/i);
  });

  // Fact check on #1114: a direct cable takes the iPad's only port, so a long show needs the camera adapter.
  it("gives a cable for a short show and a powered adapter for a long one, without contradicting itself", () => {
    const apple = section(mdx, "CQ on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/Short show:\*\*[^\n]*USB-C to USB-B cable \(our advice\)/);
    expect(apple).toMatch(/Long show:\*\*[^\n]*camera adapter with a power input[^\n]*USB-A to USB-B cable/);
  });

  // Fact check on #1114: the Source Point covers channel processing, never FX units such as reverb.
  it("says the Source Point covers the channel's processing, not effects, and leads its tap section with what to do", () => {
    const quick = mdx.slice(mdx.indexOf("**Quick start**"), mdx.indexOf("\n## "));
    expect(quick).toMatch(/how much of the channel's processing \(gate, EQ, compressor\) ends up in the recording/);
    expect(quick).not.toMatch(/effects/);
    const taps = section(mdx, "CQ tap points", "CQ on Mac, iPad and iPhone");
    expect(taps.split("\n").find((l) => l.trim() && !l.startsWith("##"))).toMatch(/^\*\*Check Source Point before you record\.\*\*/);
    expect(taps).toMatch(/\*\*Faders don't change the recording\.\*\* Every Source Point is before the fader, users report\./);
  });

  it("explains its terms for beginners the first time they come up", () => {
    expect(mdx).toMatch(/Class compliant means it works without a driver/);
    expect(mdx).toMatch(/A virtual soundcheck plays a recorded show back/);
    expect(mdx).toMatch(/The tap point is the place in each channel where the recording is taken/);
    expect(mdx).toMatch(/\(USB returns\)/);
    expect(mdx).toMatch(/AMM is the automatic mic mixer/);
  });

  it("files every forum link under Allen & Heath staff or under one user's report", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    const staff = sources.slice(sources.indexOf("Allen & Heath staff on its forum:"), sources.indexOf("Users on Allen & Heath's forum"));
    const users = sources.slice(sources.indexOf("Users on Allen & Heath's forum (one user's report each"));
    const forum = [...sources.matchAll(/\]\((https:\/\/forums\.allen-heath\.com[^)]+)\)/g)].map((m) => m[1]);
    expect(forum.length).toBeGreaterThan(1);
    for (const url of forum) expect(staff.includes(url) || users.includes(url), url).toBe(true);
    expect(staff).toContain("usb-interface/16038");
  });
});

// Facts: docs/research/mixer-recording/presonus-studiolive-iii.md (#1077): PreSonus's current console manual (July
// 2026, on fmicassets.com) and its support articles. PreSonus names iPhones only in a general statement for all its
// USB devices, and the tap point of the "Inputs" on USB and SD is not documented.
describe("the PreSonus StudioLive Series III guide's facts", () => {
  const mdx = body("presonus-studiolive-iii");
  const guide = MIXER_GUIDES.find((g) => g.slug === "presonus-studiolive-iii")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's StudioLive row links it", () => {
    expect(guide.campaign).toBe("site-guide-presonus-studiolive-iii");
    expect(MIXER_ROWS.find((r) => /StudioLive/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives 64 x 64 USB as slots (32 mixing channels, 64 on the 64S), the 16R's 18 or 24, 44.1 or 48 kHz and USB 2.0 Type-B", () => {
    const ways = section(mdx, "Ways to record a StudioLive", "StudioLive recording settings");
    expect(ways).toMatch(/up to 64 to the computer and 64 back/);
    expect(ways).toMatch(/only the 64S mixes 64/);
    expect(ways).toMatch(/16R[^\n]*18[^\n]*24/);
    expect(ways).toMatch(/48 kHz or 44\.1 kHz/);
    expect(ways).toMatch(/"USB 2\.0, Type-B"/);
    expect(ways).toMatch(/doesn't state the USB bit depth/);
  });

  it("records 34 tracks to an SDHC card of up to 32 GB on the consoles, stereo only on the racks, with the arming steps", () => {
    expect(mdx).toMatch(/channels 1-32 plus a stereo pair/);
    expect(mdx).toMatch(/up to 32 GB, formatted FAT32/);
    expect(mdx).toMatch(/SDXC cards \(64 GB and up\) are not supported/);
    expect(mdx).toMatch(/racks[^\n]*stereo only/);
    for (const step of ["**Edit**", "**Speed Test**", "**New Session**", "**Arm All Tracks**", "**Save and Close**"]) expect(mdx).toContain(step);
    expect(mdx).toMatch(/doesn't name the audio file format/);
  });

  it("explains Native (64 x 64) and Compatibility (34 x 34) mode, the iPad crash, and the main mix on USB 33-34", () => {
    const settings = section(mdx, "StudioLive recording settings", "StudioLive USB routing");
    expect(settings).toMatch(/\*\*Home > System > Sample Rate\*\*|\*\*Home\*\*, touch \*\*System\*\*, then \*\*Sample Rate\*\*/);
    expect(settings).toMatch(/\*\*Native USB Mode\*\* \(64 x 64: 64 channels each way\)/);
    expect(settings).toMatch(/\*\*Compatibility Mode\*\* \(34 x 34: 34 each way\)/);
    expect(settings).toMatch(/main mix moves to USB 33-34/);
    expect(settings).toMatch(/48 kHz is the default/);
    expect(settings).toMatch(/64S, the \*\*Select\*\* buttons arm Capture tracks, not channels/);
  });

  // Fact check on #1120: PreSonus's iPad crash note has a 2021 update (both named apps fixed), and Compatibility Mode for
  // a crash is our advice, not PreSonus's, everywhere it appears.
  it("dates the iPad crash to 2021, says the named apps were fixed, and labels Compatibility Mode for it as our advice", () => {
    const crash = /In 2021 some iPad apps crashed on launch with all 64 channels; PreSonus says the two it named have since been fixed\. If yours crashes, try Compatibility Mode \(our advice\)\./;
    expect(mdx).toMatch(crash);
    expect(guide.faqs.find((f) => /iPhone|iPad/.test(f.q))!.a).toMatch(crash);
    expect(MIXER_ROWS.find((r) => /StudioLive/.test(r.name))!.ipad).toMatch(/2021/);
    expect(mdx).not.toMatch(/causes some DAW apps/);
    const quick = mdx.slice(mdx.indexOf("**Quick start**"), mdx.indexOf("\n## "));
    expect(quick).toMatch(/try Compatibility Mode[^\n]*\(our advice\)/);
  });

  it("routes USB per slot in Home > Audio Routing > Digital Patching > USB Sends, with the default map and the two sources that differ", () => {
    const routing = section(mdx, "StudioLive USB routing", "StudioLive playback for virtual soundcheck");
    expect(routing).toMatch(/\*\*USB 1-32:\*\* channels 1-32/);
    expect(routing).toMatch(/\*\*USB 39-40:\*\* the main mix/);
    expect(routing).toMatch(/\*\*Audio Routing\*\*[\s\S]*\*\*Digital Patching\*\*, then \*\*USB Sends\*\*/);
    expect(routing).toMatch(/\*\*Available Source\*\*/);
    expect(routing).toMatch(/July 2026 manual shows these empty[^\n]*FlexMixes on 41-56/);
    expect(routing).toMatch(/SD tracks 1-32 are always channels 1-32/);
    expect(routing).toMatch(/64S, any input or mix can go to any of the 34 SD tracks/);
  });

  it("plays back over USB with the Input Source buttons and from SD with Soundcheck and Recall", () => {
    const play = section(mdx, "StudioLive playback for virtual soundcheck", "StudioLive tap points");
    expect(play).toMatch(/press and hold the \*\*USB\*\* button/);
    expect(play).toMatch(/\*\*Select\*\*/);
    expect(play).toMatch(/\*\*Analog\*\*/);
    expect(play).toMatch(/\*\*Soundcheck\*\*[\s\S]*\*\*Recall\*\*/);
    expect(play).toMatch(/\*\*Digital Return\*\*/);
    expect(play).toMatch(/Export to SD Card/);
  });

  it("says PreSonus doesn't document the default tap, gives the FlexMix points with pros and cons, and labels our reading", () => {
    const taps = section(mdx, "StudioLive tap points", "StudioLive on Mac, iPad and iPhone");
    expect(taps).toMatch(/PreSonus doesn't say/);
    expect(taps).toMatch(/\*\*Pre 1\*\*[^\n]*after the polarity switch, high-pass filter and gate/);
    expect(taps).toMatch(/\*\*Pre 2:\*\* after all the channel processing, before the fader/);
    expect(taps).toMatch(/\*\*Post:\*\* after the processing and the fader/);
    expect((taps.match(/Pro: /g) ?? []).length).toBeGreaterThanOrEqual(3);
    expect(taps).toMatch(/\(our reading\)/);
    expect(taps).toMatch(/\(our advice\)/);
    expect(taps).toMatch(/what the room heard \(our reading\)/);
    expect(taps).toMatch(/only that one channel turned up/);
    expect(taps).not.toMatch(/pre-EQ|raw input|post-preamp/i);
  });

  it("says PreSonus names iPads and iPhones in a general statement, not tested by us, records without Mixer Link, never unsupported", () => {
    const apple = section(mdx, "StudioLive on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/general statement/);
    expect(apple).toMatch(/haven't tested a StudioLive with an iPhone or iPad yet/);
    expect(apple).toMatch(/Camera Adapter/);
    expect(apple).toMatch(/doesn't charge/);
    expect(apple).toMatch(/USB-C Digital AV Multiport Adapter/);
    // Fact check on #1120: untested, so "should record", as on the Qu guide.
    expect(mdx).toMatch(/so it should record a StudioLive over USB, but we haven't tested it with one yet/);
    expect(mdx).not.toMatch(/records a StudioLive without Mixer Link/);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/unsupported|not supported by ShowRecorder/i);
    expect(mdx).not.toMatch(/ShowRecorder has recorded[^.]*StudioLive/);
    expect(guide.faqs.find((f) => /iPhone|iPad/.test(f.q))!.a).toMatch(/haven't tested/);
  });

  it("covers the Series III consoles and racks and leaves out the SE models in one line", () => {
    for (const m of ["64S", "32S", "32SX", "32SC", "32R", "24R", "16R"]) expect(mdx).toContain(m);
    // Fact check on #1120: no source mentions SE racks.
    expect(mdx).toMatch(/This guide doesn't cover the StudioLive SE models\./);
    expect(mdx).not.toMatch(/SE racks/);
  });

  it("cites PreSonus's own July 2026 console manual, and the research file no longer leans on the dealer copy", () => {
    expect(guide.sources).toContain("https://www.fmicassets.com/Damroot/Original/10153/OM_StudioLive-Series-III-Console-Mixers_EN.pdf");
    expect(mdx).not.toMatch(/ccisolutions/);
    const research = readFileSync(path.join(ROOT, "..", "docs", "research", "mixer-recording", "presonus-studiolive-iii.md"), "utf8");
    expect(research).toContain("fmicassets.com/Damroot/Original/10153/OM_StudioLive-Series-III-Console-Mixers_EN.pdf");
    expect(research).toMatch(/Differences from the old manual/);
  });
});

// Facts: docs/research/mixer-recording/ah-sq.md (#1068), checked again against Allen & Heath's help center (the SQ
// Firmware Reference Guide). Allen & Heath doesn't name the iPhone or iPad, and doesn't say where "1-to-1" starts.
describe("the Allen & Heath SQ guide's facts", () => {
  const mdx = body("ah-sq");
  const guide = MIXER_GUIDES.find((g) => g.slug === "ah-sq")!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's SQ row links it", () => {
    expect(guide.campaign).toBe("site-guide-ah-sq");
    expect(guide.mixer).toBe("Allen & Heath SQ");
    expect(MIXER_ROWS.find((r) => /SQ-5/.test(r.name))!.guide).toBe(guide.path);
  });

  it("gives 32 x 32 over USB-B at 48 or 96 kHz, set in Setup > Audio > Digital I/O, with no Mac driver", () => {
    expect(mdx).toMatch(/32 inputs and 32 outputs/);
    expect(mdx).toMatch(/\*\*Setup\*\* > \*\*Audio\*\* > \*\*Digital I\/O\*\*/);
    expect(mdx).toMatch(/USB Sample Rate/);
    expect(mdx).toMatch(/Core Audio compliant so drivers are not required/);
    expect(mdx).toMatch(/ASIO/);
    expect(mdx).toMatch(/bit depth[^.]*doesn't say/i);
  });

  it("records SQ-Drive: 16 tracks at 96 kHz or 32 at 48 kHz, 24-bit WAV, only patched channels, to a fast drive", () => {
    const ways = section(mdx, "Ways to record an SQ", "SQ recording settings");
    expect(ways).toMatch(/16 tracks at 96 kHz/);
    expect(ways).toMatch(/32 at 48 kHz/);
    expect(ways).toMatch(/24-bit/);
    expect(ways).toMatch(/Only USB channels that have been patched to will be recorded/);
    expect(ways).toMatch(/USB stick/);
    expect(ways).toMatch(/FAT32/);
    expect(ways).toMatch(/\*\*Utility\*\* > \*\*SQ-Drive\*\* > \*\*Multitrack\*\*/);
  });

  it("routes USB in the I/O screen: Main LR on 1-2 by default, then direct outs, and Tie Lines for raw inputs", () => {
    const routing = section(mdx, "SQ USB routing", "SQ playback for virtual soundcheck");
    expect(routing).toMatch(/\*\*I\/O\*\*/);
    expect(routing).toMatch(/Direct Outs/);
    expect(routing).toMatch(/Main LR to 1-2, then 1-to-1 direct outs/);
    expect(routing).toMatch(/Tie Lines/);
    expect(routing).toMatch(/\*\*Patch\*\*/);
    expect(routing).toMatch(/doesn't say which channel/);
  });

  it("plays back from USB returns patched in Inputs > Input Channel, with a patch library, and from SQ-Drive", () => {
    const play = section(mdx, "SQ playback for virtual soundcheck", "SQ tap points");
    expect(play).toMatch(/\*\*Input Channel\*\*/);
    expect(play).toMatch(/Library/);
    expect(play).toMatch(/same USB socket numbers/);
    expect(play).toMatch(/USB return/);
  });

  it("lists every Direct Out Source with what each adds, and Tie Lines as unprocessed, with Trim kept apart", () => {
    const taps = section(mdx, "SQ tap points", "SQ on Mac, iPad and iPhone");
    for (const t of ["Post Preamp", "Post HPF", "Post Gate", "Post Insert Return", "Post PEQ", "Post Comp", "Post Delay"]) {
      expect(taps).toContain(t);
    }
    expect(taps).toMatch(/affected only by the preamp gain/);
    expect(taps).toMatch(/Tie Line/);
  });

  // Fact check on #1117: A&H's signal path diagram puts Trim in the "Preamp/Trim/Width" block, before the first tap.
  it("says Gain and Trim are both in the recording, Trim at Post Preamp as our reading of A&H's diagram", () => {
    const taps = section(mdx, "SQ tap points", "SQ on Mac, iPad and iPhone");
    expect(taps).toMatch(/Gain and Trim are in the recording/);
    expect(taps).toMatch(/signal diagram puts it in the same block as the preamp, so Post Preamp probably includes it \(our reading\)/);
    expect(taps).not.toMatch(/neither has Trim|Trim is not at Post Preamp/);
    expect(guide.sources).toContain(
      "https://support.allen-heath.com/hc/en-gb/articles/4402940459537-SQ-Basic-Signal-Path-Diagrams-Input-Group-LR-Aux-Matrix",
    );
  });

  // Fact check on #1117: Main LR to 1-2 then direct outs is the Standard reset only; the Monitor reset leaves USB unassigned.
  it("ties the default USB map to a Standard reset, in the quick start, the routing section and the FAQ", () => {
    const standard = /After a \*\*Standard\*\* reset \(\*\*Setup\*\* > \*\*Mixer Config\*\* > \*\*Role\*\*\)/;
    const quick = mdx.slice(mdx.indexOf("**Quick start**"), mdx.indexOf("\n## "));
    expect(quick).toMatch(standard);
    expect(section(mdx, "SQ USB routing", "SQ playback for virtual soundcheck")).toMatch(standard);
    expect(mdx).not.toMatch(/A reset SQ/);
    expect(guide.faqs.find((f) => /Which USB channel/.test(f.q))!.a).toMatch(/After a Standard reset \(in Setup, on the Role tab\)/);
  });

  it("says Allen & Heath doesn't name the iPhone or iPad, not tested yet, no Mixer Link, never unsupported", () => {
    const apple = section(mdx, "SQ on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/class compliant/);
    expect(apple).toMatch(/not tested yet/);
    expect(mdx).toMatch(/no Mixer Link/);
    expect(mdx).not.toMatch(/unsupported/i);
    expect(mdx).not.toMatch(/ShowRecorder has recorded[^.]*SQ/);
  });

  it("cites only Allen & Heath pages", () => {
    expect(guide.sources.length).toBeGreaterThanOrEqual(5);
    for (const u of guide.sources) expect(u).toMatch(/^https:\/\/(support\.allen-heath\.com|www\.allen-heath\.com)\//);
  });
});

// Facts: docs/research/mixer-recording/soundcraft-signature-mtk.md (#1073). Maker facts come from the Signature MTK
// Recording Guide (both models) and the Signature 16, 22, 22MTK User Manual (Rev 1.1, September 2014; the 22 MTK
// only). Anything the manual says only of the 22 MTK is labeled as such, and our readings are labeled.
describe("the Soundcraft Signature MTK guide's facts", () => {
  const mdx = body("signature-mtk");
  const guide = MIXER_GUIDES.find((g) => g.slug === "signature-mtk")!;
  const row = MIXER_ROWS.find((r) => /Signature 12 MTK/.test(r.name))!;

  it("is in MIXER_GUIDES with its own campaign, and the hub's Signature MTK row links it", () => {
    expect(guide.campaign).toBe("site-guide-signature-mtk");
    expect(row.guide).toBe(guide.path);
  });

  it("builds its 'Pick your mixer' line only from the hub row's facts", () => {
    expect(guide.pick).toMatch(/14 channels over USB \(24 on the 22 MTK\)/);
    expect(guide.pick).toMatch(/No recording without a computer/);
    expect(guide.pick).toMatch(/iPad: yes, with a camera adapter, says Soundcraft/);
    expect(guide.pick).toMatch(/iPhone: not tested yet/);
    expect(row.usb).toMatch(/12 MTK: 14 in, 12 out\. 22 MTK: 24 in, 22 out/);
    expect(row.onboard).toBe("None.");
    expect(row.ipad).toMatch(/camera adapter/);
  });

  it("gives each model's USB channel count, 44.1 or 48 kHz, 24-bit, class compliant, and the Windows driver", () => {
    const ways = section(mdx, "Ways to record a Signature MTK", "Signature MTK recording settings");
    expect(ways).toMatch(/12 MTK:\*\* 14 channels to the computer, 12 back/);
    expect(ways).toMatch(/22 MTK:\*\* 24 channels to the computer, 22 back/);
    expect(ways).toMatch(/44\.1 or 48 kHz/);
    expect(ways).toMatch(/higher sample rates are not compatible/);
    expect(ways).toMatch(/24-bit/);
    expect(ways).toMatch(/USB 2\.0/);
    expect(ways).toMatch(/USB class compliant ASIO audio interface/);
    expect(ways).toMatch(/Soundcraft Multichannel USB Audio Driver V3\.20/);
    // No onboard recorder: say so plainly, and don't invent one.
    expect(ways).toMatch(/### With no computer: not possible/);
  });

  it("explains 'only 2 channels' as a non-MTK Signature, and gives the Windows streaming mode and buffer pairs", () => {
    const settings = section(mdx, "Signature MTK recording settings", "Signature MTK USB routing");
    expect(settings).toMatch(/^### Only 2 channels\? Check that the mixer says MTK$/m);
    expect(settings).toMatch(/Signature 16 and 22 consoles have 2-track USB/);
    expect(settings).toMatch(/\*\*Reliable\*\*[^\n]*1024 samples/);
    expect(settings).toMatch(/\*\*Low Latency\*\*[^\n]*128 samples/);
    expect(settings).toMatch(/distorted audio/);
  });

  it("gives the fixed map: inputs on USB 1-12 or 1-22, Master L/R post-fader on the last pair, stereo channels odd/even", () => {
    const routing = section(mdx, "Signature MTK USB routing", "Signature MTK playback for virtual soundcheck");
    expect(routing).toMatch(/\*\*12 MTK:\*\* USB 1-12 are input channels 1-12\. USB 13-14 are the Master L\/R/);
    expect(routing).toMatch(/\*\*22 MTK:\*\* USB 1-22 are input channels 1-22\. USB 23-24 are the Master L\/R/);
    expect(routing).toMatch(/POST-FADER/);
    expect(routing).toMatch(/odd[^\n]*left[^\n]*even[^\n]*right|left[^\n]*odd[^\n]*right[^\n]*even/i);
    // Aux buses on USB: no maker source; our reading, never a maker claim.
    expect(routing).toMatch(/aux[^\n]*\(our reading\)/i);
    expect(routing).toMatch(/does not affect the USB send/);
  });

  it("plays back with each channel's USB RTN button, which replaces the input post-gain, pre-EQ, while the send continues", () => {
    const play = section(mdx, "Signature MTK playback for virtual soundcheck", "Signature MTK tap points");
    expect(play).toMatch(/\*\*USB RTN\*\*/);
    expect(play).toMatch(/post-gain \(pre HPF \/ EQ\)/);
    expect(play).toMatch(/ALWAYS be SENT/);
    expect(play).toMatch(/disarm|turn off record/i);
    expect(play).toMatch(/11\/12[^\n]*21\/22/);
    expect(play).toMatch(/Audio MIDI Setup/);
  });

  it("gives one fixed tap, post-gain and pre-EQ, and leaves the limiter's place unstated", () => {
    const taps = section(mdx, "Signature MTK tap points", "Signature MTK on Mac, iPad and iPhone");
    expect(taps.split("\n").find((l) => l.trim() && !l.startsWith("##"))).toMatch(/^\*\*Set each channel's gain before you record\.\*\*/);
    expect(taps).toMatch(/post-gain, pre-EQ/);
    expect(taps).toMatch(/nothing to pick/);
    expect(taps).toMatch(/limiter[^\n]*not stated by Soundcraft/i);
    expect(taps).toMatch(/10 dB to 60 dB[^\n]*22 MTK/);
    expect(taps).not.toMatch(/before the limiter|after the limiter/);
  });

  it("says Mac needs no driver but isn't listed past 10.11, the iPad works per Soundcraft, the iPhone is not tested yet", () => {
    const apple = section(mdx, "Signature MTK on Mac, iPad and iPhone", "Sources");
    expect(apple).toMatch(/Apple® Core Audio drivers|Apple Core Audio drivers/);
    expect(apple).toMatch(/10\.7\.x Lion through 10\.11\.x El Capitan/);
    expect(apple).toMatch(/iPad:\*\* Soundcraft says it works with a camera adapter[^\n]*not tested yet/);
    expect(apple).toMatch(/iPhone:\*\* Soundcraft doesn't name it, and we haven't tested one yet/);
    expect(apple).toMatch(/Not for data/);
    expect(mdx).toMatch(
      /records every USB Channel from any class-compliant mixer[^\n]*should work[^\n]*We haven't tested it with a Signature MTK yet\. There is no Mixer Link for the Signature MTK/,
    );
    expect(mdx).not.toMatch(/unsupported|supported/i);
  });

  it("explains its terms for beginners the first time they come up", () => {
    expect(mdx).toMatch(/Class compliant means it works without a driver/);
    expect(mdx).toMatch(/A virtual soundcheck plays a recorded show back/);
    expect(mdx).toMatch(/The tap point is the place in each channel where the recording is taken/);
    expect(mdx).toMatch(/A DAW is a recording app/);
  });

  it("gives each Soundcraft document's date or edition in its Sources", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toMatch(/Rev 1\.1, September 2014/);
    expect(sources).toMatch(/Recording Guide[^\n]*no date or edition shown/);
    expect(sources).toContain("harman.helpjuice.com/en_US/soundcraft-signature-mtk-recording-guide");
  });

  it("notes in its research that both Soundcraft PDFs were read in full on 2026-11-07", () => {
    const notes = read("..", "docs", "research", "mixer-recording", "soundcraft-signature-mtk.md");
    expect(notes).toMatch(/Recording Guide[^\n]*User Manual[^\n]*read in full on 2026-11-07[^\n]*adn\.harmanpro\.com/);
  });
});
