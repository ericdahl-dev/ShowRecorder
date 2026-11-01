import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// The site's MDX has no GFM plugin, so a Markdown table renders as one paragraph of pipes (what-gets-recorded, 2026-11-01).
// Write tables as lists or headings instead; they also read better on a phone.
function mdxFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return mdxFiles(p);
    return /\.mdx?$/.test(e.name) ? [p] : [];
  });
}

describe("MDX pages", () => {
  const appDir = path.resolve(__dirname, "..", "app");

  it("use no Markdown table, which the site would show as raw pipes", () => {
    const withTables = mdxFiles(appDir)
      .filter((f) => /^\s*\|?\s*:?-{3,}:?\s*\|/m.test(readFileSync(f, "utf8")))
      .map((f) => path.relative(appDir, f));
    expect(withTables).toEqual([]);
  });
});
