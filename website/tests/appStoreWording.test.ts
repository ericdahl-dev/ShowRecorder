import { readFileSync } from "node:fs";
import path from "node:path";
import { facts } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";

// iOS 1.1 is on the App Store; the Mac and the 1.2 builds are TestFlight only. The home FAQ and the privacy wording
// must say so: the App Store version sends nothing, the TestFlight builds send crash reports and usage.

const ROOT = path.resolve(__dirname, "..");
const home = readFileSync(path.join(ROOT, "app", "page.tsx"), "utf8");
const questions = [...home.matchAll(/^\s*q: "([^"]+)"/gm)].map((m) => m[1]);
const answer = (q: string) => {
  const start = home.indexOf(`q: "${q}"`);
  return home.slice(start, home.indexOf("\n  },", start));
};

describe("home FAQ for an app on the App Store", () => {
  it("has questions to check", () => {
    expect(questions.length).toBeGreaterThan(5);
  });

  it("asks no question about \"the beta\"", () => {
    expect(questions.filter((q) => /\bthe beta\b/i.test(q))).toEqual([]);
  });

  it("says the App Store version is for iPhone and iPad and the Mac is in the TestFlight beta", () => {
    const mac = answer("Is there a Mac version?");
    expect(mac).toMatch(/App Store version \(1\.1\.21\) is for iPhone and iPad/);
    expect(mac).toMatch(/TestFlight beta/);
    expect(mac).not.toMatch(/release of 1\.0/);
  });

  it("does not say nothing is sent anywhere without naming the App Store version", () => {
    expect(home).not.toMatch(/Nothing is sent anywhere\./);
    expect(answer("Do I need an internet connection?")).toMatch(/App Store version sends nothing/);
  });
});

describe("privacy wording names the App Store version", () => {
  it("in llms.txt", () => {
    const line = facts().find((l) => l.startsWith("- Privacy:"))!;
    expect(line).toMatch(/App Store version collects no data/);
    expect(line).toMatch(/TestFlight .*crash reports and usage/);
    expect(line).toMatch(/Share crash reports and usage/);
    expect(line).not.toMatch(/^- Privacy: no data is collected/);
  });

  it("in the privacy page description", () => {
    expect(PAGES.privacy.description).toMatch(/App Store version of ShowRecorder collects no data/);
    expect(PAGES.privacy.description).toMatch(/TestFlight/);
  });
});
