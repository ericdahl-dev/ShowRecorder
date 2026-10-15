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
    expect(PAGES.mixersX32.title.length).toBeLessThanOrEqual(62);
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

  // #482 B: said plainly, near the top, as its own callout: only an emulator so far.
  it("says near the top that it was tested only against an emulator, and to try it first at a rehearsal or beside the usual recorder", () => {
    const callout = x32Page.match(/^> .+$/m)?.[0] ?? "";
    expect(x32Page.indexOf(callout)).toBeLessThan(x32Page.indexOf("## What you get"));
    expect(callout).toMatch(/emulator/);
    expect(callout).toMatch(/rehearsal/);
    expect(callout).toMatch(/usual recorder/);
  });

  it("says setup should show 32 USB Channels, and to tell us if it doesn't", () => {
    expect(x32Page).toMatch(/should show \*\*32 USB Channels\*\*/);
    expect(x32Page).toMatch(/If it doesn't, tell us/);
  });

  it("says the X-LIVE and DN32-LIVE cards are untested", () => {
    expect(x32Page).toMatch(/X-LIVE and DN32-LIVE cards haven't been tested/);
  });

  // #503: no X32 USB card's name has been seen yet; if one isn't recognized, the names never appear.
  // The sign of a name we don't recognize is no Mixer Link section, not missing names (no router does that too).
  it("asks testers who see no Mixer Link section with the mixer plugged in for the USB name their card shows", () => {
    expect(x32Page).toMatch(/If Settings has no \*\*Mixer Link\*\* section with the mixer plugged in, tell us the name under \*\*Settings › Audio interface\*\*/);
  });

  it("is linked from the X32 entry in Supported mixers", () => {
    expect(inBeta.find((m) => /X32/.test(m.name))?.href).toBe("/mixers/x32");
  });
});

const xr18Page = readFileSync(path.join(ROOT, "app", "mixers", "xr18", "content.mdx"), "utf8");

describe("the XR18 and MR18 page", () => {
  it("has a title that fits a share card and names both mixers", () => {
    expect(PAGES.mixersXR18.path).toBe("/mixers/xr18");
    expect(PAGES.mixersXR18.title.length).toBeLessThanOrEqual(62);
    expect(PAGES.mixersXR18.title).toMatch(/XR18/);
    expect(PAGES.mixersXR18.description).toMatch(/MR18/);
  });

  it("covers what is only true of the X Air: 18 USB Channels, its own Wi-Fi, and the XR12 and XR16 sending none", () => {
    expect(xr18Page).toMatch(/18 USB Channels/);
    expect(xr18Page).toMatch(/Wi-Fi/);
    expect(xr18Page).toMatch(/XR12 and XR16/);
  });

  it("links the setup guide instead of repeating it", () => {
    expect(xr18Page).toMatch(/\]\(\/docs\/usb-cable-and-setup\)/);
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

// #482 E: these are pages for people who haven't got the app yet, so they use plain words, not the app's own terms.
// "Mixer Link", "Find Mixers" and "USB Channels" stay: the app shows them, and the pages teach them.
describe("mixer pages in plain words", () => {
  for (const [name, page] of [["x32", x32Page], ["xr18", xr18Page]] as const) {
    it(`/mixers/${name} has none of the app's own terms`, () => {
      expect(page).not.toMatch(/\b(Arms?|Armed|Takes?|Stems?|Pre-roll|Show report)\b/);
    });
  }

  // When 1.0 is approved, update "Where to get it" on the XR18 page and this test together.
  it("the XR18 page says once where it stands: 1.0 in App Review, the public beta open now", () => {
    expect(xr18Page.match(/App Review/g)?.length).toBe(1);
    expect(xr18Page.match(/public beta/g)?.length).toBe(1);
  });
});

// #482 C: beta testers start the Trial so every channel records, and know a TestFlight purchase isn't charged.
describe("the beta Trial line", () => {
  for (const slug of ["x32", "xr18"]) {
    it(`/mixers/${slug} tells beta testers to start the 14-day Trial, and that TestFlight doesn't charge`, () => {
      const body = readFileSync(path.join(ROOT, "app", "mixers", slug, "content.mdx"), "utf8");
      const pricing = body.slice(body.indexOf("## Free, Trial and Pro"), body.indexOf("## Where to get it"));
      expect(pricing).toMatch(/In the beta, start the 14-day Trial in \*\*Settings › Pro\*\*/);
      expect(pricing).toMatch(/Buying Pro in the beta isn't charged, and doesn't carry over to the App Store version/);
    });
  }
});

// #482 D: the facts a buyer checks before trying it.
describe("mixer page facts", () => {
  // A section between two headings; a renamed heading fails here instead of slicing the wrong text.
  const section = (body: string, from: string, to: string) => {
    expect(body).toContain(from);
    expect(body).toContain(to);
    return body.slice(body.indexOf(from), body.indexOf(to));
  };

  for (const slug of ["x32", "xr18"]) {
    const body = readFileSync(path.join(ROOT, "app", "mixers", slug, "content.mdx"), "utf8");

    it(`/mixers/${slug} names the cable, the hub for long shows, the iOS and iPadOS version, and the Mac in testing`, () => {
      const needs = section(body, "## What you need", "## Set it up");
      expect(needs).toMatch(/USB-B to USB-C cable/);
      expect(needs).toMatch(/powered USB-C hub/);
      expect(needs).toMatch(/iOS 26/);
      expect(needs).toMatch(/USB-C iPad on iPadOS 26/);
      expect(needs).toMatch(/A Mac version is in testing \(macOS 26\)/);
    });

    it(`/mixers/${slug} gives Pro's price, one time, without making the Trial sound paid`, () => {
      const pricing = section(body, "## Free, Trial and Pro", "## Where to get it");
      expect(pricing).toMatch(/Pro is a one-time \$19\.99 purchase/);
      expect(pricing).not.toMatch(/Trial and Pro\]\(\/docs\/pricing\), a one-time/);
    });
  }

  it("the X32 page names the M32 models by their Midas names, and which card each has", () => {
    const x32 = readFileSync(path.join(ROOT, "app", "mixers", "x32", "content.mdx"), "utf8");
    expect(x32).toMatch(/M32, M32R or M32C/);
    expect(x32).toMatch(/M32 LIVE and M32R LIVE/);
    expect(x32).not.toMatch(/M32 \(full size, Compact, Producer or Rack\)/);
  });
});

// #704: the mixer pages are linked from the places a visitor starts, and the X32 page leads on to the docs.
describe("links to the mixer pages", () => {
  const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

  it("the home hero and FAQ link both mixer pages", () => {
    const home = read("app", "page.tsx");
    for (const href of ["/mixers/xr18", "/mixers/x32"]) {
      expect(home.match(new RegExp(`href="${href}"`, "g"))?.length).toBeGreaterThanOrEqual(2);
    }
  });

  it("the footer has a Supported mixers group with both pages", () => {
    const footer = read("components", "Footer.tsx");
    expect(footer).toMatch(/aria-label="Supported mixers"/);
    expect(footer).toMatch(/href="\/mixers\/xr18"/);
    expect(footer).toMatch(/href="\/mixers\/x32"/);
  });

  it("the X32 page links to the docs", () => {
    expect(x32Page).toMatch(/\]\(\/docs\)/);
  });
});
