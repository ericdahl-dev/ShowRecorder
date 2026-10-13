import { readFileSync } from "node:fs";
import path from "node:path";
import { PAGES } from "@/lib/metadata";
import { inBeta, worksNow } from "@/lib/mixers";

// Mixer landing pages: one per mixer family that works, with what is true for that mixer only.
// The X32 and M32 are in the public beta, so their page never suggests the App Store version records them.

const ROOT = path.resolve(__dirname, "..");
const x32Page = readFileSync(path.join(ROOT, "app", "mixers", "x32", "page.mdx"), "utf8");

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

const xr18Page = readFileSync(path.join(ROOT, "app", "mixers", "xr18", "page.mdx"), "utf8");

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
