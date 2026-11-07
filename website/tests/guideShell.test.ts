import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AskUs, Breadcrumbs, GetTheApp, LastChecked, ASK_US_LABEL } from "@/components/GuideParts";
import GuidesHubPage from "@/app/guides/record/page";
import { DEVICE_REQUIREMENT, GUIDE_STEPS } from "@/lib/guide";
import { llmsFullTxt, llmsTxt } from "@/lib/llms";
import { PAGES } from "@/lib/metadata";
import { GUIDES_HUB, HUB_FAQS, MIXER_GUIDES, MIXER_ROWS, RESEARCH_URL, guideTitle, guideTrail, titleOf } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { APP_STORE_CAMPAIGNS, REPO_URL, ROUTES, appStoreLink } from "@/lib/site";
import { breadcrumbListJsonLd, techArticleJsonLd } from "@/lib/structuredData";
import { capDay, localDay } from "../scripts/pageDatesLib.mjs";

// The shared shape of the mixer recording guides (review batch 1, #1081): breadcrumbs, the date a guide was last
// checked, the call to get the app, "ask us", and the lists (routes, titles, llms.txt) built from MIXER_GUIDES.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const html = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el);

describe("lists built from MIXER_GUIDES", () => {
  it("titles each guide as '<mixer> USB multitrack recording: settings and routing'", () => {
    expect(guideTitle("X32")).toBe("X32 USB multitrack recording: settings and routing - ShowRecorder");
  });

  it("gives every guide a route, a PAGES entry with that title, and an llms.txt line", () => {
    for (const g of MIXER_GUIDES) {
      expect(g.path).toBe(`${GUIDES_HUB}/${g.slug}`);
      expect(ROUTES).toContain(g.path);
      const page = (PAGES as Record<string, { path: string; title: string }>)[g.pageKey];
      expect(page.path).toBe(g.path);
      expect(page.title).toBe(titleOf(g));
      expect(llmsTxt()).toContain(`(https://showrecorder.app${g.path})`);
    }
    for (const src of [read("lib", "site.ts"), read("lib", "metadata.ts"), read("lib", "llms.ts")]) expect(src).toMatch(/MIXER_GUIDES/);
  });

  it("puts the guides under their own '## Guides' heading in llms.txt", () => {
    const txt = llmsTxt();
    const guides = txt.slice(txt.indexOf("## Guides"), txt.indexOf("## Docs"));
    expect(guides).toContain(`(https://showrecorder.app${GUIDES_HUB})`);
    expect(guides).toContain("(https://showrecorder.app/guides/record-gig-without-laptop)");
  });

  it("puts the hub table and the guide questions in llms-full.txt", () => {
    const full = llmsFullTxt();
    const part = full.slice(full.indexOf("## Recording guides, mixer by mixer"));
    expect(part).toMatch(/\| Model \| Over USB \| With no computer \| Mac \| iPad \| iPhone \|/);
    for (const row of MIXER_ROWS) expect(part).toContain(`| ${row.name} |`);
    for (const f of HUB_FAQS) expect(part).toContain(f.q);
    for (const g of MIXER_GUIDES) for (const f of g.faqs) expect(part).toContain(f.q);
  });
});

describe("breadcrumbs", () => {
  it("are three levels on a guide: Home > Recording guides > the guide, in JSON-LD and on the page", () => {
    const trail = guideTrail("X32", "/guides/record/x32");
    const data = breadcrumbListJsonLd(trail) as { itemListElement: { position: number; name: string; item: string }[] };
    expect(data.itemListElement.map((i) => i.name)).toEqual(["ShowRecorder", "Recording guides", "X32"]);
    expect(data.itemListElement[2].item).toBe("https://showrecorder.app/guides/record/x32");
    const nav = html(createElement(Breadcrumbs, { trail }));
    expect(nav).toMatch(/^<nav aria-label="Breadcrumb"/);
    expect(nav.match(/<li/g)).toHaveLength(3);
    expect(nav).toContain('href="/guides/record"');
    expect(nav).toMatch(/<li aria-current="page">X32<\/li>/);
  });

  it("are two levels on the hub, visible and in its JSON-LD", () => {
    const page = html(createElement(GuidesHubPage));
    expect(page).toMatch(/<nav aria-label="Breadcrumb"/);
    expect(page).toMatch(/<li aria-current="page">Recording guides<\/li>/);
    expect(page).toContain('"position":2,"name":"Recording guides"');
  });
});

describe("last checked", () => {
  it("shows the page's date from PAGE_DATES", () => {
    expect(html(createElement(LastChecked, { path: GUIDES_HUB }))).toContain(`Last checked <time dateTime="${PAGE_DATES[GUIDES_HUB]}">${PAGE_DATES[GUIDES_HUB]}</time>`);
  });

  // scripts/page-dates.mjs wrote 2026-11-07 for a page edited on the evening of 2026-11-06 (UTC, not local).
  it("never dates a page after the build day, and uses the local day", () => {
    expect(localDay(new Date(2026, 10, 6, 23, 50))).toBe("2026-11-06");
    expect(capDay("2026-11-07", "2026-11-06")).toBe("2026-11-06");
    expect(capDay("2026-11-05", "2026-11-06")).toBe("2026-11-05");
    const today = localDay(new Date());
    for (const d of Object.values(PAGE_DATES)) expect(d <= today, d).toBe(true);
  });
});

describe("getting the app from a guide", () => {
  it("has the guide campaigns, each listed in the App Store Connect doc", () => {
    const doc = readFileSync(path.join(ROOT, "..", "docs", "app-store", "app-store-connect-steps.md"), "utf8");
    const guideCampaigns = APP_STORE_CAMPAIGNS.filter((ct) => ct === "site-guides" || ct.startsWith("site-guide-"));
    expect(guideCampaigns).toEqual(expect.arrayContaining(["site-guides", "site-guide-x32", "site-guide-xr18", "site-guide-taps"]));
    for (const ct of guideCampaigns) expect(doc, ct).toContain(`\`${ct}\``);
  });

  it("links the badge with the page's campaign, says what device it needs, and offers the Mac beta", () => {
    const out = html(createElement(GetTheApp, { campaign: "site-guides" }));
    expect(out).toContain(appStoreLink("site-guides")!.replace(/&/g, "&amp;"));
    expect(out).toContain(DEVICE_REQUIREMENT);
    expect(out).toMatch(/Mac: join the TestFlight beta/);
    expect(GUIDE_STEPS[0].text).toContain(DEVICE_REQUIREMENT);
  });

  it("puts the badge on the pricing page", () => {
    expect(read("app", "docs", "pricing", "page.mdx")).toMatch(/<AppStoreBadge [^>]*campaign="site-docs"/);
  });
});

describe("ask us", () => {
  it("has one label, linking to /support", () => {
    const out = html(createElement(AskUs));
    expect(out).toContain('href="/support"');
    expect(out).toContain(ASK_US_LABEL);
  });

  it("puts the email first and the chat second on /support", () => {
    const support = read("app", "support", "page.mdx");
    expect(support.indexOf("mailto:")).toBeGreaterThan(-1);
    expect(support.indexOf("mailto:")).toBeLessThan(support.indexOf("<ChatButton"));
    expect(support).toMatch(/>\{CONTACT_EMAIL\}<\/a>/);
  });
});

describe("the hub", () => {
  const page = () => html(createElement(GuidesHubPage));

  // The table roles stay: phones stack the rows with display: block, which drops table semantics in some browsers.
  it("splits Mac, iPad and iPhone into their own columns", () => {
    expect(page()).toMatch(/>Mac<\/th><th scope="col" role="columnheader">iPad<\/th><th scope="col" role="columnheader">iPhone<\/th>/);
    for (const row of MIXER_ROWS) for (const k of ["mac", "ipad", "iphone"] as const) expect(row[k].trim(), `${row.name} ${k}`).not.toBe("");
  });

  it("has a glossary, a sources-and-method link, its FAQ, the ask-us line and the app", () => {
    const out = page();
    expect(out).toMatch(/<h2 id="glossary"/);
    for (const term of ["Tap point", "+M", "Card out", "AES50", "P16", "Class compliant", "DAW", "Virtual soundcheck", "CoreAudio"]) expect(out).toContain(term);
    expect(RESEARCH_URL).toBe(`${REPO_URL}/blob/main/docs/research/mixer-recording/README.md`);
    expect(out).toContain(`href="${RESEARCH_URL}"`);
    expect(out).toMatch(/Sources and method/);
    expect(out).toContain('"@type":"FAQPage"');
    for (const f of HUB_FAQS) expect(out).toContain(f.q);
    expect(out).toContain(ASK_US_LABEL);
    expect(out).toContain(appStoreLink("site-guides")!.replace(/&/g, "&amp;"));
    expect(out).toContain('href="/guides/record-gig-without-laptop"');
  });

  it("is linked from the no-laptop guide's Next section", () => {
    const next = read("app", "guides", "record-gig-without-laptop", "page.mdx").split("## Next")[1];
    expect(next).toContain(`](${GUIDES_HUB})`);
  });
});

describe("TechArticle data", () => {
  it("names the page, its dates, the author, the publisher and the sources", () => {
    const data = techArticleJsonLd({
      page: { path: "/guides/record/x32", title: "X32 - ShowRecorder", description: "d" },
      headline: "How to multitrack record a Behringer X32",
      datePublished: "2026-11-06",
      dateModified: "2026-11-06",
      citations: ["https://example.com/manual.pdf"],
    }) as Record<string, unknown>;
    expect(data["@type"]).toBe("TechArticle");
    expect(data.headline).toBe("How to multitrack record a Behringer X32");
    expect(data.url).toBe("https://showrecorder.app/guides/record/x32");
    expect(data.author).toMatchObject({ name: "Eric Dahl" });
    expect(data.publisher).toMatchObject({ name: "ShowRecorder" });
    expect(data.citation).toEqual(["https://example.com/manual.pdf"]);
  });
});
