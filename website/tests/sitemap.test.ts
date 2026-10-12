import robots from "@/app/robots";
import sitemap from "@/app/sitemap";
import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { DOCS } from "@/lib/docs";
import { SITE_URL } from "@/lib/site";

const ROOT = path.resolve(__dirname, "..");

describe("sitemap", () => {
  it("lists every page as a clean URL", () => {
    const urls = sitemap().map((entry) => entry.url);
    expect(urls).toEqual([
      "https://showrecorder.app",
      "https://showrecorder.app/features",
      "https://showrecorder.app/docs",
      ...DOCS.map((d) => `https://showrecorder.app/docs/${d.slug}`),
      "https://showrecorder.app/support",
      "https://showrecorder.app/privacy",
    ]);
  });

  it("lists every docs page that exists, and only those", () => {
    const onDisk = readdirSync(path.join(ROOT, "app", "docs"), { withFileTypes: true })
      .filter((e) => e.isDirectory() && existsSync(path.join(ROOT, "app", "docs", e.name, "page.mdx")))
      .map((e) => e.name)
      .sort();
    expect(DOCS.map((d) => d.slug).sort()).toEqual(onDisk);
  });

  it("never lists a .html URL or one with a trailing slash", () => {
    for (const { url } of sitemap()) {
      expect(url).not.toMatch(/\.html$/);
      expect(url).not.toMatch(/\/$/);
    }
  });
});

describe("robots", () => {
  it("allows everything and points at the sitemap", () => {
    const result = robots();
    expect(result.rules).toEqual({ userAgent: "*", allow: "/" });
    expect(result.sitemap).toBe(`${SITE_URL}/sitemap.xml`);
  });
});
