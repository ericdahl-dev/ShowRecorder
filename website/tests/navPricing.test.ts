import { readFileSync } from "node:fs";
import path from "node:path";
import { DOCS } from "@/lib/docs";
import { NAV } from "@/lib/site";

// Website review item 9: Compare and Support in the header where there is room (1024px and up), the five anchors
// everywhere else (the footer has the rest), and "Pricing" named the same in the nav and where it leads.

const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");
const css = read("app", "globals.css");

describe("header nav", () => {
  it("keeps the five anchors first and adds Compare and Support after them, marked wide", () => {
    expect(NAV.map((n) => n.label)).toEqual(["Features", "Setup", "Pricing", "Docs", "FAQ", "Compare", "Support"]);
    expect(NAV.filter((n) => n.wide).map((n) => n.href)).toEqual(["/compare", "/support"]);
    expect(NAV.slice(0, 5).some((n) => n.wide)).toBe(false);
  });

  it("Header marks the wide items, which CSS shows only from 1024px", () => {
    expect(read("components", "Header.tsx")).toMatch(/item\.wide \? "nav-wide"/);
    expect(css).toMatch(/\.site-nav \.nav-wide\s*\{\s*display:\s*none/);
    expect(css).toMatch(/@media \(min-width: 1024px\)\s*\{\s*\.site-nav \.nav-wide\s*\{\s*display:\s*list-item/);
  });

  it("phones and tablets still reach Compare and Support from the footer", () => {
    const footer = read("components", "Footer.tsx");
    expect(footer).toMatch(/\/compare/);
    expect(footer).toMatch(/\/support/);
  });
});

describe("Pricing is named Pricing", () => {
  it("the docs list, the docs page and its metadata title say Pricing", () => {
    expect(DOCS.find((d) => d.slug === "pricing")?.title).toBe("Pricing");
    const page = read("app", "docs", "pricing", "page.mdx");
    expect(page).toMatch(/title: "Pricing: Free, 14-day Trial and Pro - ShowRecorder"/);
    expect(page).toMatch(/^# Pricing$/m);
  });

  it("the home section heading and the links to the docs page say Pricing", () => {
    expect(read("app", "page.tsx")).toMatch(/id="pricing"\s+title="Pricing"/);
    expect(read("app", "features", "page.tsx")).toMatch(/<a href="\/docs\/pricing">Pricing<\/a>/);
    expect(read("app", "docs", "page.mdx")).toMatch(/\[Pricing\]\(\/docs\/pricing\)/);
    expect(read("app", "docs", "troubleshooting", "page.mdx")).toMatch(/\[Pricing\]\(\/docs\/pricing\)/);
  });
});
