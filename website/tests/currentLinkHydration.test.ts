import { readFileSync } from "node:fs";
import { join } from "node:path";

const read = (...p: string[]) => readFileSync(join(__dirname, "..", ...p), "utf8");

// The inline script in lib/theme.ts sets aria-current="page" on these links before React hydrates, so
// each one must tell React the attribute is expected to differ, as the theme toggle does for
// aria-pressed (#982). Without it every page logs a hydration error in development.
describe("links the inline script marks as the current page (#982)", () => {
  const files = ["components/Header.tsx", "components/Footer.tsx", "app/docs/layout.tsx"];

  it.each(files)("every data-current-match link in %s allows the attribute to differ at hydration", (file) => {
    const tags = read(file).match(/<a\b[^>]*data-current-match[^>]*>/g) ?? [];
    expect(tags.length).toBeGreaterThan(0);
    for (const tag of tags) expect(tag).toMatch(/\bsuppressHydrationWarning\b/);
  });
});
