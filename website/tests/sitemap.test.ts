import robots from "@/app/robots";
import sitemap from "@/app/sitemap";
import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { RELEASES } from "@/lib/changelog";
import { DOCS } from "@/lib/docs";
import { AI_CRAWLERS, SITE_URL } from "@/lib/site";

const ROOT = path.resolve(__dirname, "..");

describe("sitemap", () => {
  it("lists every page as a clean URL", () => {
    const urls = sitemap().map((entry) => entry.url);
    expect(urls).toEqual([
      "https://showrecorder.app",
      "https://showrecorder.app/features",
      "https://showrecorder.app/docs",
      ...DOCS.map((d) => `https://showrecorder.app/docs/${d.slug}`),
      "https://showrecorder.app/mixers/xr18",
      "https://showrecorder.app/mixers/x32",
      "https://showrecorder.app/compare",
      "https://showrecorder.app/changelog",
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

describe("sitemap lastmod", () => {
  it("gives every page the date of the newest release", () => {
    for (const entry of sitemap()) {
      expect(entry.lastModified).toBe(RELEASES[0].date);
      expect(entry.lastModified).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    }
  });
});

describe("robots", () => {
  it("names the AI crawlers and allows them everywhere", () => {
    const rules = robots().rules as { userAgent: string; allow: string }[];
    for (const bot of ["GPTBot", "OAI-SearchBot", "ClaudeBot", "PerplexityBot", "Google-Extended", "Applebot-Extended"]) {
      expect(AI_CRAWLERS).toContain(bot);
    }
    for (const bot of AI_CRAWLERS) expect(rules).toContainEqual({ userAgent: bot, allow: "/" });
  });

  it("allows everything and points at the sitemap", () => {
    const result = robots();
    expect(result.rules).toContainEqual({ userAgent: "*", allow: "/" });
    expect(result.sitemap).toBe(`${SITE_URL}/sitemap.xml`);
  });
});
