import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// A link to a mixer page with a word stuck on the end (/mixers/x32Tell, from a Facebook post on 2026-10-28)
// redirects to that mixer's page instead of a 404. nginx answers it: the site is a static export. Real pages
// are tried first, so a later page such as /mixers/x32-compact is served, not redirected.
// tests/nginx-redirects.sh runs the same config in nginx.
const ROOT = path.resolve(__dirname, "..");
const conf = readFileSync(path.join(ROOT, "nginx.conf"), "utf8");
const mixers = readdirSync(path.join(ROOT, "app", "mixers"), { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name);

// The map from a mistyped /mixers/ address to the mixer page it starts with.
function typoTargets(): [string, string][] {
  const block = conf.match(/map \$uri \$mixer_typo_target \{([^}]*)\}/)?.[1] ?? "";
  return [...block.matchAll(/^\s*"?~\*\^\/mixers\/([a-z0-9-]+)"?\s+\/mixers\/([a-z0-9-]+);/gm)].map((m) => [m[1], m[2]]);
}

describe("mistyped mixer page addresses", () => {
  it("has a redirect for every mixer page", () => {
    expect(mixers.length).toBeGreaterThan(0);
    expect(typoTargets().map(([prefix]) => prefix).sort()).toEqual([...mixers].sort());
  });

  it("sends each one to its own page, in lowercase", () => {
    for (const [prefix, target] of typoTargets()) expect(target).toBe(prefix);
  });

  it("lists longer names first, so a name that starts with another one wins", () => {
    const prefixes = typoTargets().map(([prefix]) => prefix);
    for (const [i, a] of prefixes.entries()) {
      for (const b of prefixes.slice(i + 1)) expect(b.startsWith(a) && b !== a).toBe(false);
    }
  });

  it("tries the real page before the redirect, and 404s anything else", () => {
    expect(conf).toMatch(/location \/mixers\/ \{\s*try_files \$uri \$uri\.html \$uri\/ @mixer_typo;\s*\}/);
    const named = conf.match(/location @mixer_typo \{([\s\S]*?)\n {4}\}/)?.[1] ?? "";
    expect(named).toMatch(/return 301 \$mixer_typo_target\$is_args\$args;/);
    expect(named).toMatch(/return 404;/);
  });

  it("never redirects a mixer page to itself, even if its file can't be read", () => {
    const named = conf.match(/location @mixer_typo \{([\s\S]*?)\n {4}\}/)?.[1] ?? "";
    const guard = named.search(/if \(\$uri = \$mixer_typo_target\) \{\s*return 404;\s*\}/);
    expect(guard).toBeGreaterThanOrEqual(0);
    expect(guard).toBeLessThan(named.indexOf("return 301"));
  });
});
