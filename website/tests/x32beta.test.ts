import { readFileSync } from "node:fs";
import path from "node:path";
import { GET as llmsTxt } from "@/app/llms.txt/route";
import { PAGES } from "@/lib/metadata";
import { inBeta, planned } from "@/lib/mixers";
import { TRADEMARK_LINE } from "@/lib/site";
import { softwareApplicationJsonLd } from "@/lib/structuredData";

// The X32 and M32 are in the public beta, not the App Store 1.0 (XR18 and MR18). Every place the
// site names them says so, and none of it suggests the App Store version records an X32.

const sentences = (text: string) => text.split(/(?<=[.!?])\s+/);
// A sentence naming the X32 next to the App Store must also say beta or later.
const honest = (text: string) =>
  sentences(text).every((s) => !(/X32|M32/.test(s) && /App Store/.test(s)) || /beta|later update/i.test(s));

describe("X32 and M32 in the public beta", () => {
  it("the home title fits a share card and isn't about one mixer", () => {
    expect(PAGES.home.title.length).toBeLessThanOrEqual(60);
    expect(PAGES.home.title).not.toMatch(/XR18/);
  });

  it("the home and features descriptions name the X32 and M32 as in the beta, not planned", () => {
    for (const page of [PAGES.home, PAGES.features]) {
      expect(page.description).toMatch(/X32/);
      expect(page.description).toMatch(/beta/);
      expect(page.description).not.toMatch(/planned/);
      expect(honest(page.description)).toBe(true);
    }
  });

  it("the mixer list has the X32 and M32 in the beta, out of planned", () => {
    expect(inBeta.map((m) => m.name).join(" ")).toMatch(/X32.*M32/);
    expect(planned.map((m) => m.name).join(" ")).not.toMatch(/X32/);
  });

  it("the features page lists the beta mixers under their own heading", () => {
    const page = readFileSync(path.resolve(__dirname, "../app/features/page.tsx"), "utf8");
    expect(page).toMatch(/In the public beta<\/h3>\s*<ul[^>]*>\s*\{inBeta\.map/);
  });

  it("the home FAQ says the X32 and M32 are in the public beta, not planned next", () => {
    const page = readFileSync(path.resolve(__dirname, "../app/page.tsx"), "utf8");
    expect(page).not.toMatch(/Planned next: the Behringer X32/);
    expect(page).toMatch(/X32 and Midas M32[^"]*public beta/);
    expect(honest(page)).toBe(true);
  });

  it("the trademark line names the X32, M32 and Midas", () => {
    for (const name of ["X32", "M32", "Midas"]) expect(TRADEMARK_LINE).toContain(name);
  });

  it("structured data and llms.txt mention the X32 beta honestly", async () => {
    expect(softwareApplicationJsonLd().featureList.join(" ")).toMatch(/X32[^,]*beta/);
    const body = await llmsTxt().text();
    expect(body).toMatch(/X32/);
    expect(body).toMatch(/public beta/);
    expect(honest(body)).toBe(true);
  });
});
