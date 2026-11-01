import { readFileSync } from "node:fs";
import path from "node:path";
import { inBetaFeatures } from "@/lib/features";

// The iPhone's hold-to-stop is on only in Debug and TestFlight builds; the App Store build keeps tap and confirm.
// Getting started must describe both, so a tester holding the square isn't told to expect a question.
const repo = path.resolve(__dirname, "..", "..");
const read = (p: string) => readFileSync(path.join(repo, p), "utf8");
const level = read("Packages/ShowRecorderKit/Sources/Recording/HoldToStopAvailability.swift").match(/level: AvailabilityLevel = \.(\w+)/)?.[1];
const holdSeconds = Number(read("Packages/ShowRecorderKit/Sources/Recording/HoldToStopGesture.swift").match(/holdSeconds = ([\d.]+)/)?.[1]);
const gettingStarted = read("website/app/docs/getting-started/page.mdx");

describe("stopping a Take on the iPhone", () => {
  it("reads the rule and hold time from the app", () => {
    expect(level).toBeDefined();
    expect(holdSeconds).toBeGreaterThan(0);
  });

  it.runIf(level === "debugAndTestFlight")("getting started says the beta stops with a hold and no question", () => {
    const step = gettingStarted.split("\n").find((l) => /Press the square to stop/.test(l)) ?? "";
    expect(step).toMatch(/Stop Take/);
    expect(step).toMatch(/public beta/);
    expect(step).toMatch(new RegExp(`press and hold the square for about ${holdSeconds === 1 ? "a second" : `${holdSeconds} seconds`}`));
  });

  it.runIf(level === "debugAndTestFlight")("the beta features list includes hold to stop", () => {
    expect(inBetaFeatures.some((f) => /hold/i.test(f.title) && /stop/i.test(f.title))).toBe(true);
  });
});
