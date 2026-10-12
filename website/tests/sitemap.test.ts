import robots from "@/app/robots";
import sitemap from "@/app/sitemap";
import { SITE_URL } from "@/lib/site";

describe("sitemap", () => {
  it("lists the home, privacy and support pages as clean URLs", () => {
    const urls = sitemap().map((entry) => entry.url);
    expect(urls).toEqual([
      "https://showrecorder.app",
      "https://showrecorder.app/privacy",
      "https://showrecorder.app/support",
    ]);
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
