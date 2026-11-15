import { readFileSync } from "node:fs";
import path from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { createElement } from "react";
import { Footer } from "@/components/Footer";
import { FACEBOOK_URL } from "@/lib/site";

// The ShowRecorder Facebook Page gets its followers from the site (Eric, 2026-11-15): a footer link on every page
// and a line on the support page.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

describe("the Facebook Page link", () => {
  it("is the ShowRecorder Page", () => {
    expect(FACEBOOK_URL).toBe("https://www.facebook.com/profile.php?id=61596288844683");
  });

  it("is in the footer on every page", () => {
    const html = renderToStaticMarkup(createElement(Footer));
    expect(html).toContain(`href="${FACEBOOK_URL.replace(/&/g, "&amp;")}"`);
    expect(html).toContain("Facebook");
  });

  it("is on the support page", () => {
    const page = read("app", "support", "page.mdx");
    expect(page).toContain("FACEBOOK_URL");
    expect(page).toMatch(/Follow ShowRecorder on Facebook/);
  });
});
