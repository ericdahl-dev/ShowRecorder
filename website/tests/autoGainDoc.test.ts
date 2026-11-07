import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { DOCS } from "@/lib/docs";

// The auto-gain docs page (/docs/auto-gain). A TestFlight tester couldn't find auto-gain (2026-11-01): it was only a
// Pro bullet. The page takes its facts from the app's own code, so these checks read the Swift sources.
const SITE = path.resolve(__dirname, "..");
const REPO = path.resolve(SITE, "..");
const read = (...p: string[]) => readFileSync(path.join(SITE, ...p), "utf8");
const page = () => read("app", "docs", "auto-gain", "page.mdx");
const swift = (p: string) => readFileSync(path.join(REPO, p), "utf8");

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

describe("the auto-gain docs page", () => {
  it("exists and is in the docs list", () => {
    expect(existsSync(path.join(SITE, "app", "docs", "auto-gain", "page.mdx"))).toBe(true);
    expect(DOCS.map((d) => d.slug)).toContain("auto-gain");
  });

  it("is listed on the docs index and linked from Pricing and the XR18 page", () => {
    expect(read("app", "docs", "page.mdx")).toContain("(/docs/auto-gain)");
    expect(read("app", "docs", "pricing", "page.mdx")).toMatch(/- Auto-gain on an XR18 or MR18[^\n]*\(\/docs\/auto-gain\)/);
    expect(read("app", "mixers", "xr18", "content.mdx")).toContain("(/docs/auto-gain)");
  });

  it("follows autoGainCopy: Pro on the XR18 and MR18, the X32 and M32 only in the public beta", () => {
    const mdx = page();
    expect(mdx).toMatch(/XR18 or MR18/);
    expect(mdx).toMatch(/\bPro\b/);
    expect(mdx).toMatch(/\bTrial\b/);
    expect(mdx).toMatch(/X32 and M32[^.\n]*public beta/);
    expect(mdx).not.toMatch(/not in the App Store release/);
  });

  it("names the same target level as the auto-gain rule", () => {
    const target = swift("Packages/ShowRecorderKit/Sources/AutoGain/AutoGainRule.swift").match(/targetDbfs: Double = (-?\d+)/)![1];
    expect(page()).toContain(`${target} dBFS`);
  });

  it("quotes every reason the sheet gives when auto-gain can't run, word for word", () => {
    const source = swift("Packages/ShowRecorderKit/Sources/Recording/AutoGainAvailability.swift");
    const messages = [...source.matchAll(/^\s*"([^"\n]+)"\s*$/gm)].map((m) => m[1]);
    expect(messages.length).toBe(8);
    // The app writes "Settings › Mixer Link"; the docs write "Settings > Mixer Link".
    const mdx = page().replace(/›/g, ">");
    for (const message of messages) {
      const pattern = escape(message.replace(/›/g, ">")).replace(/\\\\\\\([^)]*\\\)/g, ".+?");
      expect(mdx, message).toMatch(new RegExp(pattern));
    }
  });

  it("names the Gain button and Undo", () => {
    // The Gain button's word lives in the kit since #1036 (TransportLink).
    expect(swift("Packages/ShowRecorderKit/Sources/Recording/TransportColumnLayout.swift")).toContain('case .gain: "Gain"');
    expect(page()).toMatch(/\*\*Gain\*\*/);
    expect(page()).toMatch(/\*\*Undo\*\*/);
    expect(page()).toMatch(/\*\*Undo all\*\*/);
    expect(page()).toMatch(/\*\*Auto-gain all channels\*\*/);
  });
});
