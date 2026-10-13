import { readFileSync } from "node:fs";
import path from "node:path";
import { PAGES } from "@/lib/metadata";
import { inBeta } from "@/lib/mixers";

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
