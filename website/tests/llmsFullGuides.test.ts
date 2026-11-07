import { readFileSync } from "node:fs";
import path from "node:path";
import { llmsFullTxt } from "@/lib/llms";
import { PAGE_DATES } from "@/lib/pageDates";
import { GLOSSARY, GUIDES_HUB, HUB_FAQS, MIXER_GUIDES, TAP_POINT_FAQS, TAP_POINT_GUIDE } from "@/lib/mixerGuides";

// llms-full.txt carries the full text of every recording guide, built from the guides' own MDX and FAQ lists, so an
// AI that reads the one file gets every fact on the guide pages.

const ROOT = path.resolve(__dirname, "..");
const mdx = (slug: string) => readFileSync(path.join(ROOT, "app", "guides", "record", slug, "content.mdx"), "utf8");
// A line of MDX as llms-full.txt shows it: links to the site's own pages are absolute.
const asText = (line: string) => line.replace(/\]\(\//g, "](https://showrecorder.app/");
const shortAnswer = (src: string) => src.split("\n").find((l) => /^\*\*(The )?[Ss]hort answer\.\*\*/.test(l)) ?? "";

const full = llmsFullTxt();
const GUIDE_FILES = [...MIXER_GUIDES.map((g) => ({ slug: g.slug, path: g.path })), { slug: "pre-or-post-fader", path: TAP_POINT_GUIDE }];

describe("llms-full.txt carries the recording guides in full", () => {
  it("has each guide's short answer", () => {
    for (const g of GUIDE_FILES) {
      const line = shortAnswer(mdx(g.slug));
      expect(line, g.slug).not.toBe("");
      expect(full, g.slug).toContain(asText(line));
    }
  });

  it("has every question and answer of every guide and the hub", () => {
    for (const f of [...HUB_FAQS, ...TAP_POINT_FAQS, ...MIXER_GUIDES.flatMap((g) => g.faqs)]) {
      expect(full).toContain(f.q);
      expect(full).toContain(f.a);
    }
  });

  it("keeps the guides' source labels word for word", () => {
    const labels = /\((our reading|our advice|[^()]*manual|not tested yet)\)|not tested yet/g;
    for (const g of GUIDE_FILES) {
      const src = mdx(g.slug);
      const found = src.match(labels) ?? [];
      const out = full.match(labels) ?? [];
      for (const l of new Set(found)) {
        expect(out.filter((o) => o === l).length, `${g.slug}: ${l}`).toBeGreaterThanOrEqual(src.match(new RegExp(l.replace(/[()]/g, "\\$&"), "g"))!.length);
      }
    }
  });

  it("leaks no JSX or MDX: no component tags, no imports, no comments, no braces", () => {
    expect(full).not.toMatch(/<\/?[A-Za-z][A-Za-z0-9]*[\s>/]/);
    expect(full).not.toMatch(/^import /m);
    expect(full).not.toMatch(/\{\/\*|\{[A-Za-z_]/);
  });

  it("gives each guide its title, URL, last-checked date and sources", () => {
    for (const g of GUIDE_FILES) {
      const title = mdx(g.slug).match(/^# (.+)$/m)![1];
      expect(full).toContain(`### ${title}\n\nURL: https://showrecorder.app${g.path}\n`);
      expect(full).toContain(`Last checked: ${PAGE_DATES[g.path]}`);
    }
    for (const g of MIXER_GUIDES) for (const url of g.sources) expect(full).toContain(`](${url})`);
  });

  it("has the hub's whole page: intro, table, the three ways, where ShowRecorder fits, glossary", () => {
    const hub = full.slice(full.indexOf("### How to multitrack record a digital mixer"));
    expect(hub).toContain(`URL: https://showrecorder.app${GUIDES_HUB}`);
    expect(hub).toContain(`Last checked: ${PAGE_DATES[GUIDES_HUB]}`);
    expect(hub).toContain("Most digital mixers can record every channel to its own track.");
    for (const h of ["What each mixer can record", "Three ways to record every channel", "Where ShowRecorder fits", "Glossary"]) {
      expect(hub).toContain(`#### ${h}`);
    }
    expect(hub).toContain("**To a card or stick in the mixer.**");
    expect(hub).toContain("Mixer Link) work only with the [XR18 and MR18](https://showrecorder.app/mixers/xr18)");
    for (const g of GLOSSARY) expect(hub).toContain(`- **${g.term}:** ${g.def}`);
  });
});
