import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { featureGroups } from "@/lib/features";
import { DOCS } from "@/lib/docs";

const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");

// Choosing which USB Channels are armed (#991), for the day it ships: Pro, and Free records every channel.
describe("channel arming copy", () => {
  it("lists choosing the armed channels as a Pro feature", () => {
    const f = featureGroups.flatMap((g) => g.features).find((x) => x.title === "Choose which channels record");
    expect(f).toMatchObject({ tier: "pro" });
  });

  it("names it in each list of what Pro adds", () => {
    expect(read("lib", "llms.ts")).toMatch(/Pro adds [^"]*choosing which USB Channels record/);
    expect(read("app", "docs", "pricing", "page.mdx")).toMatch(/- Choosing which USB Channels record/);
    for (const m of ["xr18", "x32"]) expect(read("app", "mixers", m, "content.mdx")).toMatch(/\(\/docs\/pricing\) adds [^\n]*choosing which USB Channels record/);
  });

  it("has a docs page that covers how arming works", () => {
    expect(DOCS.map((d) => d.slug)).toContain("arming-channels");
    const page = path.resolve(__dirname, "..", "app", "docs", "arming-channels", "page.mdx");
    expect(existsSync(page)).toBe(true);
    const mdx = readFileSync(page, "utf8");
    for (const re of [/[Tt]ouch and hold a lane/, /meter still moves/, /during a Take/, /13 of 18 armed/, /Free and an ended Trial record every USB Channel/, /Templates/, /per hour/, /Ready/])
      expect(mdx).toMatch(re);
  });
});
