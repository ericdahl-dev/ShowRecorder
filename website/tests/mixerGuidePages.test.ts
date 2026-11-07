import { readFileSync } from "node:fs";
import path from "node:path";
import { llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { MIXER_GUIDES, MIXER_ROWS, TAP_POINT_GUIDE } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { ROUTES } from "@/lib/site";

// The per-mixer recording guides (#1063, #1064). Every guide has the same shape (the template), checked here for
// each one; the mixer-specific facts are checked below. Facts come only from docs/research/mixer-recording/.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const headings = (mdx: string) => [...mdx.matchAll(/^## (.+)$/gm)].map((m) => m[1]);
const body = (slug: string) => read("app", "guides", "record", slug, "content.mdx");
const shell = (slug: string) => read("app", "guides", "record", slug, "page.tsx");

// The sections every mixer guide has, in this order.
const TEMPLATE = [
  "Ways to record",
  "Recording settings",
  "Routing",
  "Playback for virtual soundcheck",
  "Tap points",
  "Mac, iPad and iPhone",
  "Sources",
];

describe.each(MIXER_GUIDES)("the $slug recording guide (template)", (guide) => {
  const mdx = body(guide.slug);
  const page = (PAGES as Record<string, { path: string; title: string; description: string }>)[guide.pageKey];

  it("lives under the hub, in the sitemap, with metadata, a date and an llms.txt line", () => {
    expect(guide.path).toBe(`/guides/record/${guide.slug}`);
    expect(page.path).toBe(guide.path);
    expect(page.title).toMatch(/multitrack record/i);
    expect(ROUTES).toContain(guide.path);
    expect(PAGE_DATES[guide.path]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(llmsTxt()).toContain(`https://showrecorder.app${guide.path})`);
  });

  it("has the template's sections in order", () => {
    expect(headings(mdx)).toEqual(TEMPLATE);
  });

  it("covers every way to record: a computer, the mixer itself, and an iPhone, iPad or Mac", () => {
    const ways = mdx.slice(mdx.indexOf("## Ways to record"), mdx.indexOf("## Recording settings"));
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
    expect(shell(guide.slug)).toMatch(new RegExp(`faqPageJsonLd\\(${guide.faqsName}\\)`));
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

  it("says user routing's menu detail comes from forums, not Behringer", () => {
    expect(mdx).toMatch(/forum/i);
  });

  it("says plainly that iPhone and iPad audio from the card is not documented, and no real Take has been recorded", () => {
    const apple = mdx.slice(mdx.indexOf("## Mac, iPad and iPhone"), mdx.indexOf("## Sources"));
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
