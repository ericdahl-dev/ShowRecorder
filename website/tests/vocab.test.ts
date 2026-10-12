import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

// Scans the site's source text for words the product does not use (see ../CONTEXT.md, #248).
// It reads files rather than rendering them, so it catches copy in pages, MDX and components.
// This file lives outside app/ and components/ so it never scans its own list.

const ROOT = path.resolve(__dirname, "..");

const SCANNED: { dir: string; extensions: string[] }[] = [
  { dir: "app", extensions: [".tsx", ".mdx"] },
  { dir: "components", extensions: [".tsx"] },
];

const BANNED: { pattern: RegExp; instead: string }[] = [
  { pattern: /(?<!no )subscription/i, instead: 'Pro (only "No subscription" is allowed)' },
  { pattern: /Find mixers/, instead: '"Find Mixers"' },
  { pattern: /TestFlight/, instead: "nothing: the site describes the App Store app" },
  { pattern: /free trial/i, instead: '"14-day Trial"' },
  { pattern: /Premium/, instead: '"Pro"' },
  { pattern: /—/, instead: 'a spaced hyphen " - " or a new sentence (no em dash)' },
];

function sourceFiles(dir: string, extensions: string[]): string[] {
  const full = path.join(ROOT, dir);
  return readdirSync(full).flatMap((name) => {
    const entry = path.join(full, name);
    if (statSync(entry).isDirectory()) return sourceFiles(path.join(dir, name), extensions);
    return extensions.includes(path.extname(name)) ? [entry] : [];
  });
}

const files = SCANNED.flatMap(({ dir, extensions }) => sourceFiles(dir, extensions));

describe("site vocabulary", () => {
  it("finds the source files it scans", () => {
    const relative = files.map((f) => path.relative(ROOT, f));
    expect(relative).toContain(path.join("app", "page.tsx"));
    expect(relative).toContain(path.join("app", "privacy", "page.mdx"));
    expect(relative).toContain(path.join("components", "Footer.tsx"));
  });

  it.each(BANNED)("never uses $pattern", ({ pattern, instead }) => {
    const hits = files.flatMap((file) =>
      readFileSync(file, "utf8")
        .split("\n")
        .map((line, i) => ({ line, at: `${path.relative(ROOT, file)}:${i + 1}` }))
        .filter(({ line }) => pattern.test(line))
        .map(({ at, line }) => `${at}: ${line.trim()}`),
    );
    expect(hits, `Use ${instead}`).toEqual([]);
  });

  it("allows \"No subscription\" but not other uses of the word", () => {
    const [subscription] = BANNED;
    expect(subscription.pattern.test("No subscription.")).toBe(false);
    expect(subscription.pattern.test("Start your subscription")).toBe(true);
  });
});
