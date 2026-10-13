import { readFileSync } from "node:fs";
import path from "node:path";
import { PAGES } from "@/lib/metadata";
import { inBeta, worksNow } from "@/lib/mixers";

// Mixer landing pages: one per mixer family that works, with what is true for that mixer only.
// The X32 and M32 are in the public beta, so their page never suggests the App Store version records them.

const ROOT = path.resolve(__dirname, "..");
const x32Page = readFileSync(path.join(ROOT, "app", "mixers", "x32", "content.mdx"), "utf8");

describe("the X32 and M32 page", () => {
  it("has a title that fits a share card and names both mixers", () => {
    expect(PAGES.mixersX32.path).toBe("/mixers/x32");
    expect(PAGES.mixersX32.title.length).toBeLessThanOrEqual(60);
    expect(PAGES.mixersX32.title).toMatch(/X32/);
    expect(PAGES.mixersX32.title).toMatch(/M32/);
  });

  it("says the X32 and M32 are in the public beta and come to the App Store later", () => {
    expect(PAGES.mixersX32.description).toMatch(/public beta/);
    expect(x32Page).toMatch(/public beta/);
    expect(x32Page).toMatch(/later update/);
  });

  it("covers what is only true of the X32: 32 USB Channels, the USB card and a network for Mixer Link", () => {
    expect(x32Page).toMatch(/32 USB Channels/);
    expect(x32Page).toMatch(/X-USB/);
    expect(x32Page).toMatch(/Ethernet/);
  });

  it("is linked from the X32 entry in Supported mixers", () => {
    expect(inBeta.find((m) => /X32/.test(m.name))?.href).toBe("/mixers/x32");
  });
});

const xr18Page = readFileSync(path.join(ROOT, "app", "mixers", "xr18", "content.mdx"), "utf8");

describe("the XR18 and MR18 page", () => {
  it("has a title that fits a share card and names both mixers", () => {
    expect(PAGES.mixersXR18.path).toBe("/mixers/xr18");
    expect(PAGES.mixersXR18.title.length).toBeLessThanOrEqual(60);
    expect(PAGES.mixersXR18.title).toMatch(/XR18/);
    expect(PAGES.mixersXR18.title).toMatch(/MR18/);
  });

  it("covers what is only true of the X Air: 18 USB Channels, its own Wi-Fi, and the XR12 and XR16 sending none", () => {
    expect(xr18Page).toMatch(/18 USB Channels/);
    expect(xr18Page).toMatch(/Wi-Fi/);
    expect(xr18Page).toMatch(/XR12 and XR16/);
  });

  it("links the setup guide instead of repeating it", () => {
    expect(xr18Page).toMatch(/\]\(\/docs\/connecting-xr18\)/);
  });

  it("is linked from the XR18 entry in Supported mixers", () => {
    expect(worksNow.find((m) => /XR18/.test(m.name))?.href).toBe("/mixers/xr18");
  });
});

// #482 A: both mixer pages are product pages: a hero with the call to action at the top, the page body, and the
// shared closing band, with the same sections in the same order.
describe("mixer page structure", () => {
  const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
  const headings = (mdx: string) => [...mdx.matchAll(/^## (.+)$/gm)].map((m) => m[1]);

  for (const slug of ["x32", "xr18"]) {
    it(`/mixers/${slug} opens with the mixer hero and closes with the get band`, () => {
      const page = read("app", "mixers", slug, "page.tsx");
      const hero = page.indexOf("<MixerHero");
      const body = page.indexOf("<Content");
      const band = page.indexOf("<GetBand");
      expect(hero).toBeGreaterThan(-1);
      expect(body).toBeGreaterThan(hero);
      expect(band).toBeGreaterThan(body);
    });

    it(`/mixers/${slug} has its h1 in the hero only, not in the body`, () => {
      expect(read("app", "mixers", slug, "content.mdx")).not.toMatch(/^# /m);
    });
  }

  it("the hero puts the call to action and the price line together", () => {
    const hero = read("components", "MixerHero.tsx");
    expect(hero).toMatch(/<AppStoreBadge/);
    expect(hero).toMatch(/className="price"/);
    expect(hero).toMatch(/<Mark/);
    expect(hero).toMatch(/className="lede"/);
  });

  it("the home page uses the same closing band as the mixer pages", () => {
    expect(read("app", "page.tsx")).toMatch(/<GetBand/);
  });

  it("both pages have the same sections in the same order", () => {
    expect(headings(x32Page)).toEqual(headings(xr18Page));
  });
});

describe("the X32 page's call to action", () => {
  const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

  it("always points at the public beta, even once 1.0 is in the App Store (1.0 can't record an X32)", () => {
    const page = read("app", "mixers", "x32", "page.tsx");
    expect(page).toMatch(/<MixerHero[^>]*\sbeta[\s>]/);
    expect(page).toMatch(/<GetBand[^>]*\sbeta[\s>]/);
    expect(read("components", "AppStoreBadge.tsx")).toMatch(/beta/);
  });
});

describe("mixer page screenshots", () => {
  it("the XR18 page shows the recording screen and the Mixer Link settings, each with a caption", () => {
    expect(xr18Page).toMatch(/<Screenshot shot=\{SHOTS\.heroPhone\}/);
    expect(xr18Page).toMatch(/<Screenshot shot=\{SHOTS\.mixerLink\}/);
    expect(xr18Page.match(/<figure className="shot">[\s\S]*?<figcaption>[^<]+<\/figcaption>[\s\S]*?<\/figure>/g)).toHaveLength(2);
  });

  it("the X32 page shows no screenshot: none were made with an X32", () => {
    expect(x32Page).not.toMatch(/Screenshot|<figure/);
  });
});
