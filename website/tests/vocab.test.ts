import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

// Scans the site's source text for words the product does not use (see ../CONTEXT.md, #248).
// It reads files rather than rendering them, so it catches copy in pages, MDX, components and the
// lib/ files that hold copy (site description, page metadata, alt text).
// This file lives outside app/ and components/ so it never scans its own list.

const ROOT = path.resolve(__dirname, "..");

const SCANNED: { dir: string; extensions: string[] }[] = [
  { dir: "app", extensions: [".tsx", ".mdx"] },
  { dir: "components", extensions: [".tsx"] },
  { dir: "lib", extensions: [".ts"] },
];

const MIXER_CAPITAL = /\bMixer\b(?! Link)|(?<!Find )\bMixers\b/;

// In MDX, bold text quotes the app's own UI strings ("No Mixer answered.", "Mixer IP address"),
// which keep the app's capitals; an entry with skipUiStrings ignores them.
const BANNED: { pattern: RegExp; instead: string; skipUiStrings?: boolean }[] = [
  { pattern: /(?<!no )subscription/i, instead: 'Pro (only "No subscription" is allowed)' },
  { pattern: /Find mixers/, instead: '"Find Mixers"' },
  // TestFlight is allowed while the public beta is linked (TESTFLIGHT_URL, before 1.0 is released).
  // Put this back when the App Store badge replaces it:
  // { pattern: /TestFlight/, instead: "nothing: the site describes the App Store app" },
  { pattern: /free trial/i, instead: '"14-day Trial"' },
  { pattern: /Premium/, instead: '"Pro"' },
  { pattern: /—/, instead: 'a spaced hyphen " - " or a new sentence (no em dash)' },
  { pattern: /iPhone, iPad and Mac/, instead: '"iPhone and iPad" (1.0 is iPhone and iPad; the Mac follows)' },
  // "mixer" is lowercase in prose; only the glossary terms "Mixer Link" and "Find Mixers" keep the capital.
  {
    pattern: MIXER_CAPITAL,
    instead: 'lowercase "mixer" (capitals only in "Mixer Link", "Find Mixers" and quoted UI strings)',
    skipUiStrings: true,
  },
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
    expect(relative).toContain(path.join("app", "docs", "getting-started", "page.mdx"));
    expect(relative).toContain(path.join("lib", "features.ts"));
    expect(relative).toContain(path.join("lib", "site.ts"));
  });

  it.each(BANNED)("never uses $pattern", ({ pattern, instead, skipUiStrings }) => {
    const hits = files.flatMap((file) =>
      readFileSync(file, "utf8")
        .split("\n")
        .map((line, i) => ({ line, at: `${path.relative(ROOT, file)}:${i + 1}` }))
        .filter(({ line }) =>
          pattern.test(skipUiStrings && file.endsWith(".mdx") ? line.replace(/\*\*[^*]+\*\*/g, "") : line),
        )
        .map(({ at, line }) => `${at}: ${line.trim()}`),
    );
    expect(hits, `Use ${instead}`).toEqual([]);
  });

  it("allows Mixer Link and Find Mixers but no other capital Mixer", () => {
    expect(MIXER_CAPITAL.test("Open Settings, then Mixer Link, then Find Mixers.")).toBe(false);
    expect(MIXER_CAPITAL.test("Named from your mixer")).toBe(false);
    expect(MIXER_CAPITAL.test("Named from the Mixer")).toBe(true);
    expect(MIXER_CAPITAL.test("Mixers that work")).toBe(true);
  });

  it("allows \"No subscription\" but not other uses of the word", () => {
    const [subscription] = BANNED;
    expect(subscription.pattern.test("No subscription.")).toBe(false);
    expect(subscription.pattern.test("Start your subscription")).toBe(true);
  });
});
