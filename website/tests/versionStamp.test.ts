import { readFileSync } from "node:fs";
import path from "node:path";
import { RELEASES } from "@/lib/changelog";
import { COMPARE_FAQS } from "@/lib/compare";
import { facts } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { softwareApplicationJsonLd } from "@/lib/structuredData";

// The current versions, read from the changelog so they move with each release, plus the X32 caveat, the compare
// answer about file names, and the charset llms-full.txt needs for "›".

const ROOT = path.resolve(__dirname, "..");
const newest = (channel: string) => RELEASES.find((r) => r.channel === channel)!;

describe("current versions from the changelog", () => {
  it("llms.txt names the newest App Store and TestFlight versions", () => {
    const body = facts().join("\n");
    expect(body).toContain(`App Store version: ${newest("App Store").version}`);
    expect(body).toContain(`TestFlight beta: ${newest("TestFlight beta").version}`);
  });

  it("llms.txt says when it was last updated, from the newest release date", () => {
    expect(facts().join("\n")).toContain(`- Last updated: ${RELEASES[0].date}`);
  });

  it("the SoftwareApplication JSON-LD has the App Store version as softwareVersion", () => {
    expect(softwareApplicationJsonLd()).toMatchObject({ softwareVersion: newest("App Store").version });
  });
});

describe("the X32 page description", () => {
  it("says it is tested against an emulator so far", () => {
    expect(PAGES.mixersX32.description).toMatch(/tested against an emulator so far/);
  });
});

describe("compare: a separate file for each channel", () => {
  it("says names from the mixer on the files are Pro, on the XR18, MR18, X32 and M32", () => {
    const a = COMPARE_FAQS.find((f) => f.q === "Does ShowRecorder save a separate file for each channel?")!.a;
    expect(a).toMatch(/with Pro/i);
    expect(a).toMatch(/XR18, MR18, X32 (and|or) M32/);
  });
});

describe("nginx serves text as UTF-8", () => {
  it("sets charset utf-8 for text/plain and text/xml", () => {
    const conf = readFileSync(path.join(ROOT, "nginx.conf"), "utf8");
    expect(conf).toMatch(/^\s*charset utf-8;/m);
    expect(conf).toMatch(/^\s*charset_types text\/plain text\/xml;/m);
  });
});
