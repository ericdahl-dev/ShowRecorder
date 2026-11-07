import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { GuideJsonLd } from "@/components/GuideJsonLd";
import { PAGES } from "@/lib/metadata";
import { MIXER_GUIDES } from "@/lib/mixerGuides";
import { SHOTS, type Shot } from "@/lib/screenshots";
import { mixerApplicationJsonLd, softwareApplicationJsonLd } from "@/lib/structuredData";

// App screenshots in the SoftwareApplication JSON-LD, so search and AI answers (ChatGPT search reads Bing) can show
// the app itself rather than the og:image banner.

type ImageObject = { "@type": string; url: string; contentUrl: string; width: number; height: number; caption: string };

const ROOT = path.resolve(__dirname, "..");

// A JPEG's pixel size, from its start-of-frame segment.
function jpegSize(file: string): { width: number; height: number } {
  const b = readFileSync(file);
  let i = 2;
  while (i < b.length) {
    const marker = b[i + 1];
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker))
      return { height: b.readUInt16BE(i + 5), width: b.readUInt16BE(i + 7) };
    i += 2 + b.readUInt16BE(i + 2);
  }
  throw new Error(`No frame size in ${file}`);
}

// The SoftwareApplication in a guide page's JSON-LD, as the page renders it.
function guideApplication(slug: string) {
  const html = renderToStaticMarkup(createElement(GuideJsonLd, { slug }));
  const blocks = [...html.matchAll(/<script type="application\/ld\+json">(.*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
  return blocks.find((b) => b["@type"] === "SoftwareApplication");
}

const PAGES_WITH_APP: [string, () => { screenshot?: ImageObject[] }][] = [
  ["the home page", () => softwareApplicationJsonLd()],
  ["the XR18 mixer page", () => mixerApplicationJsonLd(PAGES.mixersXR18)],
  [`the ${MIXER_GUIDES[0].slug} guide`, () => guideApplication(MIXER_GUIDES[0].slug)],
];

describe.each(PAGES_WITH_APP)("SoftwareApplication screenshots on %s", (_name, app) => {
  it("lists the app's screenshots", () => {
    expect(app().screenshot?.length ?? 0).toBeGreaterThan(0);
  });

  it("gives each one an absolute showrecorder.app URL to a file in public/, at the file's real size", () => {
    for (const s of app().screenshot ?? []) {
      expect(s["@type"]).toBe("ImageObject");
      expect(s.url).toMatch(/^https:\/\/showrecorder\.app\/images\/[^/]+\.jpg$/);
      expect(s.contentUrl).toBe(s.url);
      const file = path.join(ROOT, "public", new URL(s.url).pathname);
      expect(existsSync(file), file).toBe(true);
      expect({ width: s.width, height: s.height }, s.url).toEqual(jpegSize(file));
    }
  });

  it("captions each one with the alt text the home page shows it with", () => {
    const home = readFileSync(path.join(ROOT, "app", "page.tsx"), "utf8");
    for (const s of app().screenshot ?? []) {
      const src = new URL(s.url).pathname;
      const placed = Object.entries(SHOTS).flatMap(([key, p]) =>
        [p.dark, p.light].filter((shot: Shot) => shot.src === src).map((shot) => ({ key, shot })),
      );
      expect(placed.length, src).toBeGreaterThan(0);
      for (const { key, shot } of placed) {
        expect(home, key).toContain(`SHOTS.${key}`);
        expect(s.caption, src).toBe(shot.alt);
      }
    }
  });
});
