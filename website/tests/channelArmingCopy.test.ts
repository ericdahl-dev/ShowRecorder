import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { DOCS } from "@/lib/docs";
import { featureGroups, inBetaFeatures } from "@/lib/features";

// Choosing which USB Channels record (#991). On for everyone in the app since #1138, but the App Store version is
// still 1.1, so the site lists it in the beta until 1.2 reaches the App Store. The facts come from the app's own code.
const SITE = path.resolve(__dirname, "..");
const REPO = path.resolve(SITE, "..");
const read = (...p: string[]) => readFileSync(path.join(SITE, ...p), "utf8");
const swift = (p: string) => readFileSync(path.join(REPO, p), "utf8");
const pagePath = path.join(SITE, "app", "docs", "arming-channels", "page.mdx");
const page = () => readFileSync(pagePath, "utf8");

const TITLE = "Choose which channels record";

describe("choosing which channels record", () => {
  it("is a Pro feature in the beta list, not yet with the App Store features", () => {
    expect(inBetaFeatures.find((f) => f.title === TITLE)).toMatchObject({ tier: "pro" });
    expect(featureGroups.flatMap((g) => g.features).map((f) => f.title)).not.toContain(TITLE);
  });

  it("has a docs page in the docs list and on the docs index", () => {
    expect(existsSync(pagePath)).toBe(true);
    expect(DOCS.map((d) => d.slug)).toContain("arming-channels");
    expect(read("app", "docs", "page.mdx")).toContain("(/docs/arming-channels)");
  });

  it("says on the page that it is in the beta for now", () => {
    expect(page()).toMatch(/public beta/);
    expect(page()).toContain("(/features#beta)");
  });

  it("uses the app's own words for the menu and the header", () => {
    const item = swift("Packages/ShowRecorderKit/Sources/Recording/ChannelArmMenuItem.swift");
    for (const name of ["Don't arm channel", "Arm channel"]) {
      expect(item).toContain(`"${name}"`);
      expect(page()).toContain(`**${name} 5**`);
    }
    const state = swift("Packages/ShowRecorderKit/Sources/Recording/RecordScreenState.swift");
    expect(state).toContain("of \\(s.usbChannelCount) armed");
    expect(page()).toContain("13 of 18 armed");
    const none = state.match(/noChannelArmedText = "([^"]+)"/)?.[1];
    expect(none).toBeDefined();
    expect(page()).toContain(none!);
  });

  it("covers how arming works: touch and hold, a dimmed lane still meters, locked during a Take, Free records all", () => {
    for (const re of [/[Tt]ouch and hold a channel's meter/, /meter still moves/, /during a Take/, /Free and an ended Trial record every USB Channel/, /per hour/])
      expect(page()).toMatch(re);
  });

  it("is listed in what a Template saves", () => {
    expect(read("app", "docs", "templates", "page.mdx")).toMatch(/- \*\*Which USB Channels are armed\*\*[^\n]*\(\/docs\/arming-channels\)/);
  });
});
