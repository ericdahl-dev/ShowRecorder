import { readFileSync } from "node:fs";
import path from "node:path";
import { APP_ROWS, CHECKED, NOT_STATED } from "@/lib/bestApp";
import { llmsTxt } from "@/lib/llms";
import { PRO_PRICE_TEXT } from "@/lib/price";
import { PAGES } from "@/lib/metadata";
import { PAGE_DATES } from "@/lib/pageDates";
import { APP_STORE_CAMPAIGNS, ROUTES } from "@/lib/site";

// The "best app to multitrack record a digital mixer on iPhone and iPad" comparison (#1085).

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const PATH = "/guides/best-app-record-digital-mixer-iphone";

describe("the best-app guide", () => {
  it("is a route in the sitemap, with metadata, a date and an llms.txt line", () => {
    expect(ROUTES).toContain(PATH);
    expect(PAGES.guideBestApp.path).toBe(PATH);
    expect(PAGES.guideBestApp.title).toMatch(/best app/i);
    expect(PAGES.guideBestApp.title).toMatch(/iPhone/);
    expect(PAGE_DATES[PATH]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(llmsTxt()).toContain(`https://showrecorder.app${PATH})`);
    expect(read("app", "guides", "best-app-record-digital-mixer-iphone", "page.tsx")).toContain("pageMetadata(PAGES.guideBestApp)");
  });
});

describe("the best-app facts", () => {
  const others = APP_ROWS.filter((r) => r.id !== "showrecorder");

  it("covers the eight apps engines name, plus ShowRecorder", () => {
    const names = APP_ROWS.map((r) => r.name).join(" | ");
    for (const app of ["Manytrack Recorder", "Cubasis 3", "AUM", "GarageBand", "MultiTrack DAW", "Auria", "StudioMini", "MultiTrackRecorder"]) {
      expect(names).toContain(app);
    }
    expect(APP_ROWS).toHaveLength(9);
  });

  it("calls ShowRecorder the app this site makes", () => {
    expect(APP_ROWS.find((r) => r.id === "showrecorder")?.name).toMatch(/the app this site makes/);
  });

  it("links each other app's own App Store page or maker site, and dates the check", () => {
    expect(CHECKED).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    for (const r of others) {
      expect(r.source, r.id).toMatch(/^https:\/\/apps\.apple\.com\/us\/app\/id\d+$/);
      if (r.extraSource) expect(r.extraSource, r.id).toMatch(/^https:\/\/(kymatica\.com|support\.apple\.com)\//);
    }
  });

  it("never prints another app's price, only free, paid or in-app purchase", () => {
    for (const r of others) {
      expect(r.price, r.id).not.toMatch(/\$|€|£|\d/);
      expect(r.price, r.id).toMatch(/^(Free|Paid)/);
    }
  });

  it('says "Not stated" where the maker does not say', () => {
    for (const r of others) expect(r.names, r.id).toBe(NOT_STATED);
    expect(APP_ROWS.find((r) => r.id === "studiomini")?.inputs).toBe(NOT_STATED);
  });

  it("states ShowRecorder's limits: names need Pro, X32 only against an emulator", () => {
    const sr = APP_ROWS.find((r) => r.id === "showrecorder")!;
    expect(sr.price).toContain(PRO_PRICE_TEXT);
    expect(sr.price).toMatch(/launch price/);
    expect(sr.names).toMatch(/Pro/);
    expect(sr.names).toMatch(/X32[^.]*emulator/);
    expect(sr.inputs).toMatch(/18 XR18 channels/);
    expect(sr.editing).toMatch(/^No/);
  });
});

describe("the best-app page", () => {
  const dir = ["app", "guides", "best-app-record-digital-mixer-iphone"];
  const shell = read(...dir, "page.tsx");
  const page = read(...dir, "content.mdx");
  const headings = [...page.matchAll(/^##+ (.+)$/gm)].map((m) => m[1]);
  const section = (h: string) => {
    const at = page.indexOf(`### ${h}`);
    const next = page.indexOf("\n##", at + 4);
    return page.slice(at, next === -1 ? undefined : next);
  };

  it("gives a verdict for each use case", () => {
    for (const h of ["Cheapest", "Every channel as a separate file", "Editing on the device", "No laptop at a gig"]) {
      expect(headings, h).toContain(h);
    }
  });

  it("says plainly when another app is the better pick", () => {
    expect(section("Editing on the device")).toMatch(/Pick \*\*Cubasis 3\*\* or \*\*Auria\*\* here, not ShowRecorder/);
    expect(section("Cheapest")).toMatch(/Manytrack Recorder/);
    expect(section("Cheapest")).toMatch(/MultiTrack DAW/);
  });

  it("makes the affiliation clear and explains Not stated, the date and the price policy", () => {
    expect(page).toMatch(/ShowRecorder is the app this site makes/);
    expect(page).toMatch(/"Not stated"/);
    expect(page).toContain("{CHECKED}");
    expect(page).toMatch(/free, paid or in-app purchase/);
  });

  it("shows the table and lists every source", () => {
    expect(page).toContain("<BestAppTable />");
    expect(page).toContain("<BestAppSources />");
  });

  it("says ShowRecorder's X32 support is tested only against an emulator", () => {
    expect(section("No laptop at a gig")).toMatch(/X32[^.]*emulator/);
  });

  it("links the mixer guides hub, the no-laptop guide and /compare", () => {
    for (const href of ["](/guides/record)", "](/guides/record-gig-without-laptop)", "](/compare)"]) expect(page).toContain(href);
  });

  it("has breadcrumbs, a last-checked day, the app with its own campaign and the ask-us line", () => {
    expect(page).toMatch(/<Breadcrumbs trail=\{bestAppTrail\} \/>/);
    expect(page).toMatch(/<LastChecked path=\{BEST_APP_GUIDE\} \/>/);
    expect(page).toContain('<GetTheApp campaign="site-guide-best-app" />');
    expect(page).toContain("<AskUs />");
  });

  it("carries breadcrumb, article and FAQ data, and shows the same questions", () => {
    expect(shell).toMatch(/breadcrumbListJsonLd\(bestAppTrail\)/);
    expect(shell).toMatch(/techArticleJsonLd\(/);
    expect(shell).toMatch(/faqPageJsonLd\(BEST_APP_FAQS\)/);
    expect(shell).toMatch(/<MixerFaq faqs=\{BEST_APP_FAQS\}/);
  });

  it("is linked from the hub", () => {
    expect(read("app", "guides", "record", "page.tsx")).toContain("BEST_APP_GUIDE");
  });

  it("has its own App Store campaign, listed in the App Store Connect doc", () => {
    expect(APP_STORE_CAMPAIGNS).toContain("site-guide-best-app");
    expect(readFileSync(path.join(ROOT, "..", "docs", "app-store", "app-store-connect-steps.md"), "utf8")).toContain("`site-guide-best-app`");
  });

  it("has no em dashes or exclamation points in its prose", () => {
    expect(page).not.toMatch(/—/);
    const prose = page.replace(/^(import|export)[^\n]*$/gm, "").replace(/<[^>]+>/g, "");
    expect(prose).not.toMatch(/!(?!=)/);
  });
});
