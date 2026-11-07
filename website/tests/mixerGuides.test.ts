import { readFileSync } from "node:fs";
import path from "node:path";
import { llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { GUIDES_HUB, MIXER_ROWS } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { ROUTES } from "@/lib/site";

// Mixer recording guides (#1061, milestone "Mixer recording guides"): a hub that lists every mixer with what it can
// record and how, and one guide per mixer under it. Facts come only from docs/research/mixer-recording/.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

describe("the mixer recording guides hub", () => {
  it("lives at /guides/record, in the sitemap, with metadata, a date and an llms.txt line", () => {
    expect(GUIDES_HUB).toBe("/guides/record");
    expect(PAGES.guidesHub.path).toBe(GUIDES_HUB);
    expect(PAGES.guidesHub.title).toMatch(/multitrack record/i);
    expect(ROUTES).toContain(GUIDES_HUB);
    expect(PAGE_DATES[GUIDES_HUB]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(llmsTxt()).toContain(`https://showrecorder.app${GUIDES_HUB})`);
  });

  it("lists every mixer in the research table, each with USB channels, onboard recording and iPhone, iPad and Mac status", () => {
    const research = readFileSync(path.join(ROOT, "..", "docs", "research", "mixer-recording", "README.md"), "utf8");
    const table = research.slice(research.indexOf("## Summary table"), research.indexOf("## Routing: block vs per-slot"));
    const researchRows = table.split("\n").filter((l) => /^\| (?!Mixer \||---)/.test(l));
    expect(MIXER_ROWS).toHaveLength(researchRows.length);
    for (const row of MIXER_ROWS) {
      expect(row.name.trim()).not.toBe("");
      expect(row.usb.trim()).not.toBe("");
      expect(row.onboard.trim()).not.toBe("");
      for (const k of ["mac", "ipad", "iphone"] as const) expect(row[k].trim(), `${row.name} ${k}`).not.toBe("");
    }
  });

  it("says plainly which mixers send no multitrack over USB", () => {
    for (const name of [/XR12/, /Avantis/, /MG10XU/]) {
      const row = MIXER_ROWS.find((r) => name.test(r.name));
      expect(row, String(name)).toBeDefined();
      expect(row!.usb).toMatch(/no |stereo only|2 in/i);
    }
  });

  // Makers rarely name the iPhone (Zoom does); elsewhere it stays "not tested yet" until someone records with one. The
  // XR18 is the exception we tested ourselves: an iPhone Take of all 18 channels (owner fact O-2, 2026-11-06).
  it("calls the iPhone confirmed only where the maker names it, or where ShowRecorder recorded with one", () => {
    const yes = MIXER_ROWS.filter((r) => /^yes/i.test(r.iphone)).map((r) => r.name);
    expect(yes).toEqual([expect.stringMatching(/Zoom/)]);
    expect(MIXER_ROWS.find((r) => /X32/.test(r.name))!.iphone).toMatch(/not documented|unknown|not tested/i);
    expect(MIXER_ROWS.find((r) => /XR18/.test(r.name))!.iphone).toMatch(/ShowRecorder \(the app this site makes\) has recorded all 18 XR18 channels on an iPhone/);
  });

  it("is linked both ways with the ShowRecorder mixer pages, and from the footer", () => {
    const hub = read("app", "guides", "record", "page.tsx");
    expect(hub).toContain('href="/mixers/xr18"');
    expect(hub).toContain('href="/mixers/x32"');
    expect(read("app", "mixers", "xr18", "content.mdx")).toContain(`](${GUIDES_HUB})`);
    expect(read("app", "mixers", "x32", "content.mdx")).toContain(`](${GUIDES_HUB})`);
    expect(read("components", "Footer.tsx")).toContain(`href="${GUIDES_HUB}"`);
  });

  it("renders the table as HTML with a header per column, so it reads on a phone and to a screen reader", () => {
    const hub = read("app", "guides", "record", "page.tsx");
    expect(hub).toMatch(/<table/);
    expect(hub).toMatch(/scope="col"/);
    expect(hub).toMatch(/data-product=/);
  });

  it("has no em dashes or exclamation points", () => {
    const text = read("app", "guides", "record", "page.tsx") + read("lib", "mixerGuides.ts");
    expect(text).not.toMatch(/—/);
    expect(text.replace(/!==?|!\w|!\(/g, "")).not.toMatch(/!/);
  });
});
