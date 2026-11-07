import { readFileSync } from "node:fs";
import path from "node:path";
import { APP_ROWS, BEST_APP_FAQS, CHECKED } from "@/lib/bestApp";
import { llmsFullTxt } from "@/lib/llms";
import { PAGE_DATES } from "@/lib/pageDates";
import { BEST_APP_GUIDE, GLOSSARY, GUIDES_HUB, HUB_FAQS, MIXER_GUIDES, TAP_POINT_FAQS, TAP_POINT_GUIDE } from "@/lib/mixerGuides";

// llms-full.txt carries the full text of every recording guide, built from the guides' own MDX and FAQ lists, so an
// AI that reads the one file gets every fact on the guide pages.

const ROOT = path.resolve(__dirname, "..");
// A guide's MDX, by its URL path: app/<path>/content.mdx.
const mdx = (p: string) => readFileSync(path.join(ROOT, "app", ...p.split("/").filter(Boolean), "content.mdx"), "utf8");
// A line of MDX as llms-full.txt shows it: links to the site's own pages are absolute.
const asText = (line: string) => line.replace(/\]\(\//g, "](https://showrecorder.app/");
const shortAnswer = (src: string) => src.split("\n").find((l) => /^\*\*(The )?[Ss]hort answer\.\*\*/.test(l)) ?? "";

const full = llmsFullTxt();
// One guide's part of llms-full.txt: from its "### <title>" line to the next "### " heading.
const section = (title: string) => {
  const start = full.indexOf(`### ${title}\n`);
  if (start < 0) return "";
  const rest = full.slice(start + 4);
  const next = rest.search(/^### /m);
  return next < 0 ? rest : rest.slice(0, next);
};
const GUIDE_FILES = [
  ...MIXER_GUIDES.map((g) => ({ slug: g.slug, path: g.path })),
  { slug: "pre-or-post-fader", path: TAP_POINT_GUIDE },
  { slug: "best-app", path: BEST_APP_GUIDE },
];

describe("llms-full.txt carries the recording guides in full", () => {
  it("has each guide's short answer", () => {
    for (const g of GUIDE_FILES) {
      const line = shortAnswer(mdx(g.path));
      expect(line, g.slug).not.toBe("");
      expect(full, g.slug).toContain(asText(line));
    }
  });

  it("has every question and answer of every guide and the hub", () => {
    for (const f of [...HUB_FAQS, ...TAP_POINT_FAQS, ...BEST_APP_FAQS, ...MIXER_GUIDES.flatMap((g) => g.faqs)]) {
      expect(full).toContain(f.q);
      expect(full).toContain(f.a);
    }
  });

  // Counted inside each guide's own section (its ### title to the next ###), so a label lost from one guide can't be
  // made up for by the same label in another guide or in a FAQ elsewhere.
  it("keeps every source label in its own guide's section, word for word", () => {
    const labels = /\((our reading|our advice|[^()]*manual|not tested yet)\)|not tested yet|haven't tested/g;
    const count = (text: string) => {
      const n = new Map<string, number>();
      for (const l of text.match(labels) ?? []) n.set(l, (n.get(l) ?? 0) + 1);
      return n;
    };
    for (const g of GUIDE_FILES) {
      const src = mdx(g.path).replace(/\{\/\*[\s\S]*?\*\/\}/g, "");
      const inSection = count(section(src.match(/^# (.+)$/m)![1]));
      for (const [label, n] of count(src)) expect(inSection.get(label) ?? 0, `${g.slug}: ${label}`).toBeGreaterThanOrEqual(n);
    }
  });

  it("leaks no JSX or MDX: no component tags, no imports, no comments, no braces", () => {
    expect(full).not.toMatch(/<\/?[A-Za-z][A-Za-z0-9]*[\s>/]/);
    expect(full).not.toMatch(/^import /m);
    expect(full).not.toMatch(/\{\/\*|\{[A-Za-z_]/);
  });

  it("gives each guide its title, URL, last-checked date and sources", () => {
    for (const g of GUIDE_FILES) {
      const title = mdx(g.path).match(/^# (.+)$/m)![1];
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

  it("has the best-app guide's table, every app's facts and its sources", () => {
    const part = section("The best app to multitrack record a digital mixer on iPhone and iPad");
    expect(part).toMatch(/\| App \| Price model \| A file per channel \| Channels at once \| Runs on \| Channel names from the mixer \| Editing on the device \|/);
    for (const r of APP_ROWS) {
      for (const v of [r.name, r.maker, r.price, r.perChannel, r.inputs, r.platforms, r.names, r.editing]) expect(part, r.id).toContain(v.replace(/\|/g, "/"));
      expect(part, r.id).toContain(`](${r.source})`);
      if (r.extraSource) expect(part, r.id).toContain(`](${r.extraSource})`);
    }
    expect(part).toContain(`read on ${CHECKED}`);
  });
});
