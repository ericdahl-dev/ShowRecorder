import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { BetaLink } from "@/components/BetaLink";
import { MixerHero } from "@/components/MixerHero";
import { TESTFLIGHT_URL } from "@/lib/site";

// A quiet text link under the App Store badge for people who want new features early: the badge stays the main
// button. The mixer pages' click script reports it as mixer_page_cta_clicked (lib/analytics.ts). The pages' MDX
// can't load in tests, so the home page is checked in its source and the mixer pages through MixerHero.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const LINK_TEXT = "Or try new features early in the public beta";

function checkLink(html: string) {
  const link = html.match(new RegExp(`<a[^>]*>${LINK_TEXT}</a>`))?.[0] ?? "";
  expect(link).not.toBe("");
  expect(link).toContain(`href="${TESTFLIGHT_URL}"`);
  expect(link).toContain('data-track="join_beta_clicked"');
  expect(link).toContain('data-track-destination="testflight"');
}

describe("the public-beta link", () => {
  it("is a real, tracked link to TestFlight", () => {
    checkLink(renderToStaticMarkup(createElement(BetaLink)));
  });

  it("sits under the App Store badge on both mixer pages", () => {
    const html = renderToStaticMarkup(
      createElement(MixerHero, { eyebrow: "e", title: "t", lede: "l", campaign: "site-xr18" }),
    );
    checkLink(html);
    expect(html.indexOf(LINK_TEXT)).toBeGreaterThan(html.indexOf('id="app-store-link"'));
    for (const m of ["xr18", "x32"]) expect(read("app", "mixers", m, "page.tsx")).toMatch(/<MixerHero\b/);
  });

  it("sits under the App Store badge in the home hero", () => {
    const home = read("app", "page.tsx");
    expect(home).toMatch(/<AppStoreBadge id="app-store-link" campaign="site-home" \/>\s*<BetaLink \/>/);
  });

  it("is styled small and quiet, with a focus ring", () => {
    const css = read("app", "globals.css");
    expect(css).toMatch(/\.beta-link\s*\{[^}]*font-size/);
    expect(css).toMatch(/\.beta-link a:focus-visible\s*\{[^}]*outline/);
  });
});
