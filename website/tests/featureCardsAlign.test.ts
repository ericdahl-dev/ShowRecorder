import { readFileSync } from "node:fs";
import path from "node:path";

// Website review item 17: on the home page's four-column feature grid a card with a one-line title started its body
// higher than its neighbor with a two-line title. From 1024px each card spans two rows of the grid (title, body) so
// the titles and the bodies line up across a row.

const css = readFileSync(path.resolve(__dirname, "..", "app", "globals.css"), "utf8");

describe("home feature cards", () => {
  it("share title and body rows across a row of the four-column grid, from 1024px", () => {
    const block = css.match(/@media \(min-width: 1024px\)\s*\{\s*\.cards--4 \.card\s*\{[^}]*\}/)?.[0] ?? "";
    expect(block).toMatch(/display:\s*grid/);
    expect(block).toMatch(/grid-template-rows:\s*subgrid/);
    expect(block).toMatch(/grid-row:\s*span 2/);
    expect(block).toMatch(/row-gap:\s*0/);
    expect(css).toMatch(/\.cards--4 \.card p\s*\{\s*margin-top:\s*0\b/);
  });
});
