import { readFileSync } from "node:fs";
import path from "node:path";
import { featureGroups } from "@/lib/features";

// Mixer Link connects on Free, but a Free Take gives its Stems generic names (Entitlement: mixerLinkNames false on Free).
// A card marked Free must say so, or a reader expects named files without Pro.
const repo = path.resolve(__dirname, "..", "..");
const entitlement = readFileSync(path.join(repo, "Packages/ShowRecorderKit/Sources/Recording/Entitlement.swift"), "utf8");
const freeHidesNames = /case \.free:[\s\S]*?mixerLinkNames: false/.test(entitlement);
const card = featureGroups.flatMap((g) => g.features).find((f) => f.title === "Mixer Link");

describe("the Mixer Link card", () => {
  it("reads the Free rule from the app", () => {
    expect(card).toBeDefined();
  });

  it.runIf(freeHidesNames)("says the files take the names only with Pro", () => {
    expect(card?.tier).toBe("free");
    expect(card?.body).toMatch(/On Free, the names show on the meters/);
    expect(card?.body).toMatch(/files take them with Pro/);
  });
});
