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
const A_SHORT: Record<string, string> = { Qu: "a", DL32R: "a", WING: "a" };
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
    // Only the Qu, the Zoom, the DL32R and the WING have none; a Mixer Link guide that lost its product page must fail here, not skip.
    expect(guide.productPage === undefined).toBe(["qu", "zoom-l12", "mackie-dl32r", "wing"].includes(guide.slug));
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
      /\]\(https:\/\/(cdn-media\.empowertribe\.com|www\.behringer\.com|support\.allen-heath\.com|www\.allen-heath\.com|zoomcorp\.com|mackie\.com)\//,
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
    expect(mdx).toMatch(/after the Mic Pre tap \(block diagram\)/);
    expect(mdx).not.toMatch(/sound like front of house/);
    expect(mdx).toMatch(/Use it for processed tracks \(our advice\)\./);
    expect(guide.faqs.find((f) => /pre or post fader/.test(f.q))!.a).toMatch(/^For the channels, pre-fader either way\./);
    expect(MIXER_ROWS.find((r) => r.name === "Mackie DL32R")!.onboard).toMatch(/\(older units may show 24 until updated; our reading\)/);
  });

  it("cites the Master Fader 5 guide as Mackie's, hosted by a distributor", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toMatch(/ambertech\.com\.au/);
    expect(sources).toMatch(/distributor/);
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
