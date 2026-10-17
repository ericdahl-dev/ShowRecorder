import { readFileSync } from "node:fs";
import path from "node:path";

// Website review items 7 and 8: a focused element never hides under the sticky header, and the compare table is
// usable on a phone (a caption, a sticky first column that leaves room, and a hint that it scrolls sideways).

const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");
const css = read("app", "globals.css");
const compare = read("app", "compare", "page.tsx");

describe("sticky header and focus", () => {
  it("scroll-padding-top on the page keeps a focused element clear of the header (WCAG 2.4.11)", () => {
    const html = [...css.matchAll(/(?:^|\n)html\s*\{([^}]*)\}/g)].map((m) => m[1]).join("\n");
    expect(html).toMatch(/scroll-padding-top:\s*calc\(var\(--header-h\) \+ 16px\)/);
  });
});

describe("compare table on a phone", () => {
  it("the scroll region keeps its name and the table gets a caption", () => {
    expect(compare).toMatch(/role="region" aria-labelledby="table-title" tabIndex=\{0\}/);
    expect(compare).toMatch(/<caption className="sr-only">[^<]+<\/caption>/);
  });

  it("tells phone users the table scrolls sideways, and only phone users", () => {
    expect(compare).toMatch(/className="compare-hint"/);
    expect(css).toMatch(/\.compare-hint\s*\{[^}]*display:\s*none/);
    expect(css).toMatch(/@media \(max-width: 639px\)\s*\{[\s\S]*?\.compare-hint\s*\{[^}]*display:\s*block/);
  });

  it("narrows the sticky first column on a phone so a second column shows", () => {
    expect(css).toMatch(/@media \(max-width: 639px\)\s*\{[\s\S]*?\.compare-table tbody th\s*\{[^}]*width:\s*7rem/);
  });
});
