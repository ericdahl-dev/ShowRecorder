import { readFileSync } from "node:fs";
import path from "node:path";
import { AS_OF, COMPARE_FAQS, PRODUCTS, ROWS } from "@/lib/compare";
import { faqPageJsonLd } from "@/lib/structuredData";

// The /compare page: ShowRecorder next to the other ways to record a mixer. The copy is fair and dated,
// claims only what each product's own listing says, and keeps to the pricing and beta rules in CLAUDE.md.

const page = readFileSync(path.resolve(__dirname, "../app/compare/page.tsx"), "utf8");
const sentences = (text: string) => text.split(/(?<=[.!?])\s+/);
const everyText = [
  ...PRODUCTS.flatMap((p) => [p.name, p.pickIt]),
  ...ROWS.flatMap((r) => [r.label, ...Object.values(r.cells)]),
  ...COMPARE_FAQS.flatMap((f) => [f.q, f.a]),
];

describe("compare data", () => {
  it("compares ShowRecorder with Manytrack, a laptop with Reaper or Mixbus, X-Live and Auria", () => {
    expect(PRODUCTS.map((p) => p.id)).toEqual(["showrecorder", "manytrack", "laptop", "xlive", "auria"]);
    expect(PRODUCTS.map((p) => p.name)).toEqual([
      "ShowRecorder",
      "Manytrack Recorder",
      "A laptop with Reaper or Mixbus",
      "Behringer X-Live",
      "Auria",
    ]);
  });

  it("has the requested rows, each with a cell for every product", () => {
    expect(ROWS.map((r) => r.label)).toEqual([
      "Price",
      "Separate Stem for each channel",
      "Channel names from the mixer",
      "Safety copy on a Drive",
      "Crash recovery",
      "Markers",
      "DAW and Reaper export",
      "Platforms",
    ]);
    for (const row of ROWS) {
      for (const p of PRODUCTS) expect(row.cells[p.id]?.trim(), `${row.label} / ${p.id}`).toBeTruthy();
    }
  });

  it("gives every other option a 'when to pick' line, and ShowRecorder one too", () => {
    for (const p of PRODUCTS) expect(p.pickIt).toMatch(/^Pick /);
  });

  it("is dated October 2026", () => {
    expect(AS_OF).toBe("October 2026");
  });

  it("keeps Free at every USB Channel and Pro as a one-time purchase", () => {
    const price = ROWS[0].cells.showrecorder;
    expect(price).toMatch(/every USB Channel/);
    expect(price).not.toMatch(/2 USB Channels/);
    expect(price).toMatch(/one-time/);
    expect(price).toMatch(/No subscription/);
  });

  it("never mentions the DJM or Pioneer", () => {
    for (const text of everyText) expect(text).not.toMatch(/DJM|Pioneer/);
  });

  it("says the X32, M32 and Mac are in the beta wherever ShowRecorder's side names them", () => {
    const ours = [...ROWS.map((r) => r.cells.showrecorder), PRODUCTS[0].pickIt];
    for (const s of ours.flatMap(sentences)) {
      if (/X32|M32|\bMac\b/.test(s)) expect(s, s).toMatch(/beta/i);
    }
  });

  it("reports Manytrack's one review as it is, and claims no Stems for it", () => {
    const manytrack = ROWS[1].cells.manytrack;
    expect(manytrack).toMatch(/one review/);
    expect(manytrack).toMatch(/single stereo file/);
    expect(manytrack).not.toMatch(/^Yes/);
  });

  it("says X-Live is X32 only and the XR18 has no card", () => {
    expect(ROWS.find((r) => r.label === "Platforms")?.cells.xlive).toMatch(/X32 only.*XR18 has no card/);
  });

  it("has FAQ answers that are plain text", () => {
    expect(COMPARE_FAQS.length).toBeGreaterThanOrEqual(4);
    for (const f of COMPARE_FAQS) {
      expect(f.q).toMatch(/\?$/);
      expect(f.a).not.toMatch(/[<>]/);
    }
  });
});

describe("compare page", () => {
  it("sets its own metadata at /compare", () => {
    expect(page).toMatch(/export const metadata = pageMetadata\(\{\s*path: "\/compare",/);
  });

  it("writes FAQ structured data from the same questions it shows", () => {
    expect(page).toMatch(/faqPageJsonLd\(COMPARE_FAQS\)/);
    const ld = faqPageJsonLd(COMPARE_FAQS);
    expect(ld.mainEntity).toHaveLength(COMPARE_FAQS.length);
  });

  it("names the product in each cell, so a phone can stack a row instead of scrolling it", () => {
    expect(page).toMatch(/<td key=\{p\.id\} role="cell" data-product=\{p\.name\}>/);
  });

  it("shows the date next to the table", () => {
    expect(page).toMatch(/as of \{AS_OF\}/i);
  });
});
