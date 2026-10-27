import { readFileSync } from "node:fs";
import path from "node:path";

// Website review items 7 and 8: a focused element never hides under the sticky header, and the compare table is
// usable on a phone (a caption, and on a phone each row stacked with the product named in each cell).

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

  it("stacks each row on a phone instead of scrolling it, and stays a table for screen readers", () => {
    expect(css).toMatch(/@media \(max-width: 639px\)\s*\{[\s\S]*?\.compare-table td::before\s*\{[^}]*content:\s*attr\(data-product\)/);
    expect(compare).toMatch(/<table className="compare-table" role="table">/);
    expect(compare).toMatch(/role="rowheader"/);
    expect(compare).toMatch(/role="columnheader"/);
  });
});
