import { readFileSync } from "node:fs";
import path from "node:path";
import { featureGroups, inBetaFeatures } from "@/lib/features";
import { RELEASES } from "@/lib/changelog";

// Auto-gain is in the App Store with Pro on X Air; on the X32 and M32 it stays in the beta (#997).
describe("auto-gain copy for 1.1", () => {
  it("lists auto-gain as a Pro feature on the XR18 and MR18", () => {
    const f = featureGroups.flatMap((g) => g.features).find((x) => x.title === "Auto-gain");
    expect(f).toMatchObject({ tier: "pro" });
    expect(f?.body).toMatch(/XR18 or MR18/);
  });

  it("keeps only the X32 and M32 auto-gain in the beta", () => {
    expect(inBetaFeatures.map((f) => f.title)).toContain("Auto-gain on the X32 and M32");
    expect(inBetaFeatures.map((f) => f.title)).not.toContain("Auto-gain");
  });

  it("no longer calls auto-gain Debug and TestFlight only in the docs", () => {
    const mdx = readFileSync(path.resolve(__dirname, "..", "app", "docs", "what-gets-recorded", "page.mdx"), "utf8");
    expect(mdx).not.toMatch(/not in the App Store release/);
    expect(mdx).toMatch(/XR18 or MR18/);
  });

  it("names auto-gain in each list of what Pro adds", () => {
    const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");
    expect(read("lib", "llms.ts")).toMatch(/Pro adds [^"]*auto-gain on an XR18 or MR18/);
    expect(read("app", "docs", "pricing", "page.mdx")).toMatch(/- Auto-gain on an XR18 or MR18/);
    expect(read("app", "mixers", "xr18", "content.mdx")).toMatch(/\(\/docs\/pricing\) adds [^\n]*auto-gain/);
  });

  it("lists the Apple Watch remote and the Live Activity as 1.1 features, not beta", () => {
    const all = featureGroups.flatMap((g) => g.features.map((f) => f.title));
    for (const t of ["Apple Watch remote", "Live Activity"]) {
      expect(all).toContain(t);
      expect(inBetaFeatures.map((f) => f.title)).not.toContain(t);
    }
  });

  it("says the beta section is what isn't in the App Store version yet", () => {
    const page = readFileSync(path.resolve(__dirname, "..", "app", "features", "page.tsx"), "utf8");
    expect(page).not.toMatch(/Coming in 1\.1/);
    expect(page).toMatch(/in ShowRecorder 1\.1 on the App Store/);
  });

  it("names every 1.1 feature offered to everyone in the 1.1.18 entry, and the X32 only as beta", () => {
    const text = RELEASES.find((r) => r.version === "1.1.18")!.changes.join(" ");
    for (const re of [/Auto-gain/, /Apple Watch/, /Live Activity/, /re-patch/, /USB routing changes during a Take/, /Drive shows by its name/])
      expect(text).toMatch(re);
    expect(text).toMatch(/X32 and M32, auto-gain stays in the public beta/);
  });
});
