import { readFileSync } from "node:fs";
import path from "node:path";
import { GUIDE_STEPS } from "@/lib/guide";
import { llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { PAGE_DATES } from "@/lib/pageDates";
import { ROUTES } from "@/lib/site";
import { howToJsonLd } from "@/lib/structuredData";

// The guide for "record XR18 multitrack without laptop": a laptop isn't needed to multitrack an XR18 or X32.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const PATH = "/guides/record-gig-without-laptop";
const page = read("app", "guides", "record-gig-without-laptop", "page.mdx");
// The words a reader sees: the MDX without imports, exports, JSX tags and link targets, plus the rendered steps.
const prose =
  page
    .replace(/^(import|export)[^\n]*(\n(?!\n)[^\n]*)*/gm, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/\{[^}]*\}/g, " ")
    .replace(/\]\([^)]*\)/g, "]") +
  " " +
  GUIDE_STEPS.map((s) => `${s.name} ${s.text}`).join(" ");
const words = prose.split(/\s+/).filter((w) => /[A-Za-z0-9]/.test(w)).length;

describe("the no-laptop guide", () => {
  it("is a route in the sitemap, with metadata, a date and an llms.txt line", () => {
    expect(ROUTES).toContain(PATH);
    expect(PAGES.guideNoLaptop.path).toBe(PATH);
    expect(PAGES.guideNoLaptop.title).toMatch(/without a laptop/i);
    expect(PAGES.guideNoLaptop.description).toMatch(/XR18/);
    expect(PAGE_DATES[PATH]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(llmsTxt()).toContain(`https://showrecorder.app${PATH}`);
  });

  it("is 600 to 900 words", () => {
    expect(words).toBeGreaterThanOrEqual(600);
    expect(words).toBeLessThanOrEqual(900);
  });

  it("says what you need, what you get, and the honest limits", () => {
    expect(prose).toMatch(/iPhone 15 or later/);
    expect(prose).toMatch(/iOS 26/);
    expect(prose).toMatch(/USB-C iPad/);
    expect(prose).toMatch(/class-compliant/);
    expect(prose).toMatch(/one (mono )?(24-bit )?WAV file per channel/i);
    expect(prose).toMatch(/with Pro/i);
    expect(prose).toMatch(/emulator/);
    expect(prose).toMatch(/hub/);
    expect(prose).toMatch(/Lightning/);
  });

  it("links to the existing docs instead of repeating them", () => {
    for (const doc of ["/docs/usb-cable-and-setup", "/docs/mixer-link", "/docs/usb-drive", "/docs/daw", "/docs/pricing"]) {
      expect(page).toContain(`(${doc})`);
    }
  });

  it("has HowTo structured data built from its steps", () => {
    expect(page).toMatch(/howToJsonLd\(/);
    const data = howToJsonLd(PAGES.guideNoLaptop, GUIDE_STEPS);
    expect(data["@type"]).toBe("HowTo");
    expect(data.step).toHaveLength(GUIDE_STEPS.length);
    expect(GUIDE_STEPS.length).toBeGreaterThanOrEqual(4);
  });

  it("is linked from the home page and both mixer pages", () => {
    expect(read("app", "page.tsx")).toContain(`href="${PATH}"`);
    expect(read("app", "mixers", "xr18", "content.mdx")).toContain(`](${PATH})`);
    expect(read("app", "mixers", "x32", "content.mdx")).toContain(`](${PATH})`);
  });

  it("has no em dashes", () => {
    expect(page).not.toMatch(/—/);
    expect(read("lib", "guide.ts")).not.toMatch(/—/);
  });
});
