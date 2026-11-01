import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { DOCS } from "@/lib/docs";
import { featureGroups } from "@/lib/features";

// The Apple Watch remote docs page (/docs/apple-watch). A TestFlight tester said the watch "starts ok but won't stop"
// (2026-11-01): Stop is a press and hold on purpose. The page takes its facts from the watch app's code.
const SITE = path.resolve(__dirname, "..");
const REPO = path.resolve(SITE, "..");
const read = (...p: string[]) => readFileSync(path.join(SITE, ...p), "utf8");
const page = () => read("app", "docs", "apple-watch", "page.mdx");
const source = (p: string) => readFileSync(path.join(REPO, p), "utf8");

describe("the Apple Watch docs page", () => {
  it("exists and is in the docs list", () => {
    expect(existsSync(path.join(SITE, "app", "docs", "apple-watch", "page.mdx"))).toBe(true);
    expect(DOCS.map((d) => d.slug)).toContain("apple-watch");
  });

  it("is listed on the docs index and linked from Pricing and Getting started", () => {
    expect(read("app", "docs", "page.mdx")).toContain("(/docs/apple-watch)");
    expect(read("app", "docs", "pricing", "page.mdx")).toMatch(/- The \[Apple Watch remote\]\(\/docs\/apple-watch\)/);
    expect(read("app", "docs", "getting-started", "page.mdx")).toContain("(/docs/apple-watch)");
  });

  it("names the same hold time for Stop as HoldToStopButton.holdSeconds", () => {
    const seconds = Number(source("Watch/HoldToStopButton.swift").match(/static let holdSeconds = ([\d.]+)/)![1]);
    const words = seconds === 1 ? "1 second" : `${seconds} seconds`;
    expect(page()).toMatch(new RegExp(`press and hold[^.\\n]*${words}`, "i"));
    expect(page()).toMatch(/ring fills/);
  });

  it("says Marker is also the double tap, as the code makes it", () => {
    expect(source("Watch/RemoteView.swift")).toMatch(/\.handGestureShortcut\(\.primaryAction\)/);
    expect(page()).toMatch(/double tap[^.\n]*Marker/i);
  });

  it("quotes the watch's own messages word for word", () => {
    const model = source("Packages/ShowRecorderKit/Sources/WatchRemote/WatchRemoteModel.swift");
    for (const name of ["noLinkText", "openPhoneText", "tooLateText", "unconfirmedText"]) {
      const text = model.match(new RegExp(`static let ${name} = "([^"]+)"`))![1];
      expect(page(), name).toContain(`**${text}**`);
    }
    expect(page()).toContain("**The recording on the iPhone carries on.**");
    for (const text of ["Connecting…", "Sending…"]) expect(source("Watch/RemoteView.swift")).toContain(`"${text}"`);
    const problems = source("Packages/ShowRecorderKit/Sources/WatchRemote/WatchStatus.swift");
    for (const text of [...page().matchAll(/\*\*(iPhone low on space|A Copy stopped|Mixer Link lost)\*\*/g)].map((m) => m[1]))
      expect(problems).toContain(`"${text}"`);
    const limit = source("Packages/ShowRecorderKit/Sources/Recording/Entitlement.swift").match(/freeMarkerLimit = (\d+)/)![1];
    expect(page()).toContain(`**${limit} per Take on Free**`);
  });

  it("names the watchOS the watch app needs", () => {
    const watchOS = source("project.yml").match(/watchOS: "([\d.]+)"/)![1].replace(/\.0$/, "");
    expect(page()).toContain(`watchOS ${watchOS}`);
  });

  it("calls the watch remote Free, as the features list does", () => {
    const watch = featureGroups.flatMap((g) => g.features).find((f) => f.title === "Apple Watch remote");
    expect(watch?.tier).toBe("free");
    expect(page()).toMatch(/watch remote is part of Free/);
  });
});
