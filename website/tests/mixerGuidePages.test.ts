import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { GuideJsonLd } from "@/components/GuideJsonLd";
import { tapPointsAnchor } from "@/components/TapPicks";
import { llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { MIXER_GUIDES, MIXER_ROWS, TAP_POINT_GUIDE, X32_METHOD_A, guideTitle } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { ROUTES } from "@/lib/site";

// The per-mixer recording guides (#1063, #1064). Every guide has the same shape (the template), checked here for
// each one; the mixer-specific facts are checked below. Facts come only from docs/research/mixer-recording/.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const headings = (mdx: string) => [...mdx.matchAll(/^## (.+)$/gm)].map((m) => m[1]);
const body = (slug: string) => read("app", "guides", "record", slug, "content.mdx");
const shell = (slug: string) => read("app", "guides", "record", slug, "page.tsx");

// The sections every mixer guide has, in this order. They name the mixer (review batch 1), so a heading quoted out of
// context still says which mixer it is about.
const TEMPLATE = (short: string) => [
  `Ways to record an ${short}`,
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

  it("opens with a short answer and a numbered quick start whose links reach its sections, before the caveats", () => {
    const top = mdx.slice(0, mdx.indexOf("\n## "));
    expect(top).toMatch(/\*\*Short answer\.\*\*/);
    const quick = top.slice(top.indexOf("**Quick start**"));
    expect(top.indexOf("**Quick start**")).toBeGreaterThan(top.indexOf("**Short answer.**"));
    expect(quick).toMatch(/^1\. /m);
    const ids = new Set(TEMPLATE(guide.short).map(slugify));
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
    const ways = section(mdx, `Ways to record an ${guide.short}`, `${guide.short} recording settings`);
    expect(ways).toMatch(/computer/i);
    expect(ways).toMatch(/no computer|without a computer/i);
    expect(ways).toMatch(/iPhone/);
  });

  it("links the shared tap-point guide, the hub, and the ShowRecorder page for this mixer, which links back", () => {
    expect(mdx).toContain(`](${TAP_POINT_GUIDE})`);
    expect(mdx).toContain("](/guides/record)");
    expect(mdx).toContain(`](${guide.productPage})`);
    expect(read("app", "mixers", guide.productPage.split("/").pop()!, "content.mdx")).toContain(`](${guide.path})`);
  });

  it("is the guide link in the hub table", () => {
    expect(MIXER_ROWS.filter((r) => r.guide === guide.path)).toHaveLength(1);
  });

  it("cites its sources: the maker's documents, with forum posts marked as such", () => {
    const sources = mdx.slice(mdx.indexOf("## Sources"));
    expect(sources).toMatch(/\]\(https:\/\/(cdn-media\.empowertribe\.com|www\.behringer\.com)\//);
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
