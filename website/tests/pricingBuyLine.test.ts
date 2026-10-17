import { readFileSync } from "node:fs";
import path from "node:path";

// The home page's "Free, Trial and Pro" section: where Pro is bought, and no stale price in a screenshot.

const home = readFileSync(path.resolve(__dirname, "..", "app", "page.tsx"), "utf8");
const pricing = home.slice(home.indexOf('id="pricing"'), home.indexOf('id="faq"'));

describe("home pricing section", () => {
  it("says where to buy Pro and how the beta treats a purchase", () => {
    expect(pricing).toMatch(/Buy Pro in the app: <strong>Settings › Pro<\/strong>/);
    expect(pricing).toMatch(/In the beta, buying Pro isn&apos;t charged, and the purchase\s+isn&apos;t kept for the App Store version/);
  });

  it("links to the full pricing page", () => {
    expect(pricing).toContain('href="/docs/pricing"');
  });

  it("shows no Pro screenshot until it is retaken at the $4.99 launch price (it said $19.99)", () => {
    expect(pricing).not.toContain("SHOTS.pro");
  });
});
