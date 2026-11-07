import { readFileSync } from "node:fs";
import path from "node:path";
import { llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { TAP_POINT_FAQS } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { ROUTES } from "@/lib/site";

// The shared guide every mixer guide links to (#1062): which tap point to record, pre or post fader.
// Source: the tap-point section of docs/research/mixer-recording/README.md (general practice, not a maker claim).

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const PATH = "/guides/record/pre-or-post-fader";
const shell = read("app", "guides", "record", "pre-or-post-fader", "page.tsx");
const page = read("app", "guides", "record", "pre-or-post-fader", "content.mdx");
const headings = [...page.matchAll(/^##+ (.+)$/gm)].map((m) => m[1]);

describe("the tap-point guide", () => {
  it("is a route in the sitemap, with metadata, a date and an llms.txt line", () => {
    expect(ROUTES).toContain(PATH);
    expect(PAGES.guideTapPoints.path).toBe(PATH);
    expect(PAGES.guideTapPoints.title).toMatch(/pre or post fader/i);
    expect(PAGE_DATES[PATH]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(llmsTxt()).toContain(`https://showrecorder.app${PATH})`);
  });

  it("covers each tap point, earliest first, then the main mix and buses", () => {
    const order = [/before (the )?(digital )?trim|raw input/i, /before EQ/i, /after EQ/i, /after the fader/i, /main mix/i];
    const at = order.map((re) => headings.findIndex((h) => re.test(h)));
    for (const i of at) expect(i).toBeGreaterThan(-1);
    expect([...at].sort((a, b) => a - b)).toEqual(at);
  });

  it("gives pros, cons and when to use each tap", () => {
    expect(page.match(/\*\*Pros\.\*\*/g)?.length).toBeGreaterThanOrEqual(5);
    expect(page.match(/\*\*Cons\.\*\*/g)?.length).toBeGreaterThanOrEqual(5);
    expect(page.match(/\*\*Use it\b/g)?.length).toBeGreaterThanOrEqual(5);
  });

  it("warns that a pulled-down fader or a mute records silence on a post-fader tap", () => {
    expect(page).toMatch(/silent track/i);
  });

  it("covers the caveats: gain changes reach the raw tap, digital trim vs analog gain, HPF, phantom, shared stage boxes", () => {
    for (const re of [/gain change/i, /digital trim/i, /HPF|high-pass/i, /phantom/i, /stage box/i, /only 2 or 8 channels/]) expect(page).toMatch(re);
  });

  it("says it is general practice, not a maker's claim", () => {
    expect(page).toMatch(/general recording practice/i);
  });

  it("shows the same questions it puts in its FAQPage data", () => {
    expect(shell).toMatch(/faqPageJsonLd\(TAP_POINT_FAQS\)/);
    expect(shell).toMatch(/<MixerFaq faqs=\{TAP_POINT_FAQS\}/);
    expect(TAP_POINT_FAQS.some((f) => /pre.?fader or post.?fader/i.test(f.q))).toBe(true);
  });

  it("is linked from the hub", () => {
    expect(read("app", "guides", "record", "page.tsx")).toContain(`href="${PATH}"`);
  });

  it("has no em dashes or exclamation points in its prose", () => {
    expect(page).not.toMatch(/—/);
    const prose = page.replace(/^(import|export)[^\n]*$/gm, "").replace(/<[^>]+>/g, "");
    expect(prose).not.toMatch(/!(?!=)/);
  });
});
