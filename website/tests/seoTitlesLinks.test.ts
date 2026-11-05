import { readFileSync } from "node:fs";
import path from "node:path";
import sitemap from "@/app/sitemap";
import { PAGE_DATES } from "@/lib/pageDates";
import { PAGES } from "@/lib/metadata";
import { NAV, ROUTES, SITE_URL } from "@/lib/site";
import { THEME_SCRIPT } from "@/lib/theme";

// Search wording and internal links: "multitrack" in the headline and titles, header links that lead to real pages,
// cross-links between the mixer pages and the docs, and a sitemap with each page's own last-edit date.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

describe("titles and headline", () => {
  it("the home H1 says multitrack next to every channel", () => {
    const h1 = read("app", "page.tsx").match(/<h1 id="hero-title">([^<]+)<\/h1>/)?.[1] ?? "";
    expect(h1).toMatch(/multitrack every channel/i);
  });

  it("the features title names multitrack recording features and supported mixers", () => {
    expect(PAGES.features.title).toMatch(/^Multitrack recording features and supported mixers - /);
  });

  it("the changelog title has the product's keywords", () => {
    expect(PAGES.changelog.title).toMatch(/^What's new in /);
    expect(PAGES.changelog.title).toMatch(/multitrack recorder for iPhone/);
  });
});

describe("header links", () => {
  it("Setup, Pricing and FAQ lead to real pages, with the home anchors kept for the home page", () => {
    const byLabel = Object.fromEntries(NAV.map((n) => [n.label, n]));
    expect(byLabel.Setup).toMatchObject({ href: "/docs/getting-started", home: "/#need" });
    expect(byLabel.Pricing).toMatchObject({ href: "/docs/pricing", home: "/#pricing" });
    expect(byLabel.FAQ).toMatchObject({ href: "/support", home: "/#faq" });
    for (const n of NAV) expect(n.href.startsWith("/#")).toBe(false);
  });

  it("the header carries the home anchor and the inline script uses it on the home page", () => {
    expect(read("components", "Header.tsx")).toMatch(/data-home-href=\{item\.home\}/);
    expect(THEME_SCRIPT).toMatch(/data-home-href/);
  });
});

describe("cross-links", () => {
  it.each(["xr18", "x32"])("the %s page links to the DAW doc and the comparison", (m) => {
    const body = read("app", "mixers", m, "content.mdx");
    expect(body).toMatch(/\]\(\/docs\/daw\)/);
    expect(body).toMatch(/\]\(\/compare\)/);
  });

  it("every docs page links to the mixer pages", () => {
    const layout = read("app", "docs", "layout.tsx");
    expect(layout).toMatch(/href="\/mixers\/xr18"/);
    expect(layout).toMatch(/href="\/mixers\/x32"/);
  });
});

describe("sitemap dates", () => {
  it("has a last-edit date for every route", () => {
    for (const r of ROUTES) expect(PAGE_DATES[r], r).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("gives each page its own date, not one date for all", () => {
    const entries = sitemap();
    for (const e of entries) {
      const route = e.url === SITE_URL ? "/" : e.url.slice(SITE_URL.length);
      expect(e.lastModified).toBe(PAGE_DATES[route]);
    }
    expect(new Set(entries.map((e) => e.lastModified)).size).toBeGreaterThan(1);
  });
});
