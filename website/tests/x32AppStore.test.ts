import { readFileSync } from "node:fs";
import path from "node:path";
import { GET as llmsTxt } from "@/app/llms.txt/route";
import { RELEASES } from "@/lib/changelog";
import { ROWS } from "@/lib/compare";
import { inBetaFeatures } from "@/lib/features";
import { PAGES } from "@/lib/metadata";
import { X32_FAQS } from "@/lib/mixerFaqs";
import { inBeta, worksNow } from "@/lib/mixers";
import { SIGNUP_INTERESTS } from "@/lib/signup";
import { SITE_DESCRIPTION, TRADEMARK_LINE } from "@/lib/site";
import { softwareApplicationJsonLd } from "@/lib/structuredData";

// X32 and M32 support is in the App Store app: in release/1.1 (1.1.18, on sale since 2026-10-31) MixerFamily,
// X32Driver, names, colors and re-patch naming have no availability rule. Only X32AutoGainAvailability is Debug
// and TestFlight, so auto-gain on the X32 and M32 stays in the beta. It has run only against an X32 emulator (#503),
// so every page still says to try it at a rehearsal first. Reverses #999 except for auto-gain.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const sentences = (text: string) => text.split(/(?<=[.!?])\s+/);
// A sentence that names the X32 or M32 says beta, a later update or "not in the App Store" only about auto-gain.
const beta = /\bbeta\b|later update|after 1\.0|App Store (later|yet)|not from the App Store/i;
const onlyAutoGainBeta = (text: string) =>
  sentences(text)
    .filter((s) => /X32|M32/.test(s) && beta.test(s) && !/auto-gain/i.test(s))
    .map((s) => s.trim());

const x32Body = read("app", "mixers", "x32", "content.mdx");
const x32Page = read("app", "mixers", "x32", "page.tsx");

describe("X32 and M32 in the App Store app (1.1.18)", () => {
  it("Supported mixers lists the X32 and M32 under works now, linked to their page, and not in the beta", () => {
    expect(worksNow.find((m) => /X32.*M32/.test(m.name))?.href).toBe("/mixers/x32");
    expect(inBeta.map((m) => m.name).join(" ")).not.toMatch(/X32|M32/);
  });

  it("the X32 page says it is in the App Store, and no longer calls it beta or later", () => {
    expect(x32Body).toMatch(/App Store/);
    expect(onlyAutoGainBeta(x32Body)).toEqual([]);
    expect(x32Body).not.toMatch(/In the beta, start the 14-day Trial|Buying Pro in the beta/);
  });

  it("the X32 page keeps the emulator warning near the top: a rehearsal first, and tell us how it goes", () => {
    const callout = x32Body.match(/^> .+$/m)?.[0] ?? "";
    expect(x32Body.indexOf(callout)).toBeLessThan(x32Body.indexOf("## What you get"));
    expect(callout).toMatch(/emulator/);
    expect(callout).toMatch(/rehearsal/);
    expect(callout).toMatch(/tell us/i);
  });

  it("the X32 page's call to action is the App Store, not the beta", () => {
    expect(x32Page).not.toMatch(/<MixerHero[^>]*\sbeta[\s>]/);
    expect(x32Page).not.toMatch(/<GetBand[^>]*\sbeta[\s>]/);
    expect(onlyAutoGainBeta(x32Page)).toEqual([]);
  });

  it("the X32 questions say it is in the App Store", () => {
    const answer = X32_FAQS.find((f) => /App Store/.test(f.q))?.a ?? "";
    expect(answer).toMatch(/^Yes/);
    expect(onlyAutoGainBeta(X32_FAQS.map((f) => `${f.q} ${f.a}`).join(" "))).toEqual([]);
  });

  it("the home title fits a share card, and the trademark line names the X32, M32 and Midas", () => {
    expect(PAGES.home.title.length).toBeLessThanOrEqual(60);
    for (const name of ["X32", "M32", "Midas"]) expect(TRADEMARK_LINE).toContain(name);
  });

  it("auto-gain on the X32 and M32 stays in the beta", () => {
    expect(inBetaFeatures.map((f) => f.title)).toContain("Auto-gain on the X32 and M32");
  });

  it("the 1.1.18 entry lists X32 and M32 support with the emulator caveat", () => {
    const text = RELEASES.find((r) => r.version === "1.1.18")!.changes.join(" ");
    expect(text).toMatch(/X32 and Midas M32[^.]*32 USB Channels/);
    expect(text).toMatch(/emulator/);
  });

  it("titles, descriptions, structured data and llms.txt don't call X32 recording beta", async () => {
    for (const text of [
      SITE_DESCRIPTION,
      PAGES.features.description,
      PAGES.mixersX32.title,
      PAGES.mixersX32.description,
      PAGES.mixersX32.image?.alt ?? "",
      softwareApplicationJsonLd().featureList.join(". "),
      SIGNUP_INTERESTS.map((i) => i.label).join(". "),
      ROWS.flatMap((r) => Object.values(r.cells)).join(" "),
      await (await llmsTxt()).text(),
    ])
      expect(onlyAutoGainBeta(text), text).toEqual([]);
  });

  it.each([
    ["app", "page.tsx"],
    ["app", "features", "page.tsx"],
    ["app", "support", "page.mdx"],
    ["app", "docs", "troubleshooting", "page.mdx"],
    ["app", "docs", "what-gets-recorded", "page.mdx"],
    ["app", "docs", "auto-gain", "page.mdx"],
    ["components", "Footer.tsx"],
  ].map((p) => [p.join("/"), p] as const))("%s calls only X32 auto-gain beta", (_, p) => {
    expect(onlyAutoGainBeta(read(...p).replace(/\s+/g, " "))).toEqual([]);
  });
});
