import { GET as llmsFullTxt } from "@/app/llms-full.txt/route";
import { GET as llmsTxt } from "@/app/llms.txt/route";
import { readFileSync } from "node:fs";
import path from "node:path";
import { RELEASES } from "@/lib/changelog";
import { featureGroups, inBetaFeatures } from "@/lib/features";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { DOCS } from "@/lib/docs";
import { XR18_FAQS, X32_FAQS } from "@/lib/mixerFaqs";
import {
  breadcrumbJsonLd,
  faqPageJsonLd,
  jsonLdScript,
  mixerApplicationJsonLd,
  softwareApplicationJsonLd,
} from "@/lib/structuredData";
import { APP_STORE_URL, SITE_DESCRIPTION, SITE_URL } from "@/lib/site";

describe("structured data", () => {
  const data = softwareApplicationJsonLd();

  it("describes ShowRecorder as an iOS app that is free to download", () => {
    expect(data).toMatchObject({
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "ShowRecorder",
      url: SITE_URL,
      applicationCategory: "MultimediaApplication",
    });
    expect(data.operatingSystem).toMatch(/iOS/);
    expect(data.operatingSystem).toMatch(/macOS/);
  });

  it("lists two offers: Free at $0 and Pro at $19.99, one time", () => {
    expect(data.offers).toEqual([
      expect.objectContaining({ "@type": "Offer", name: "Free", price: "0", priceCurrency: "USD" }),
      expect.objectContaining({ "@type": "Offer", name: "Pro", price: "19.99", priceCurrency: "USD" }),
    ]);
    expect(data.offers[1].description).toMatch(/One-time/);
  });

  it("links the App Store only once there is an App Store link", () => {
    if (APP_STORE_URL) expect(data.installUrl).toBe(APP_STORE_URL);
    else expect(data).not.toHaveProperty("installUrl");
  });
});

describe("llms.txt", () => {
  it("summarizes the product and links every docs page", async () => {
    const res = llmsTxt();
    expect(res.headers.get("content-type")).toMatch(/^text\/plain/);
    const body = await res.text();
    expect(body).toMatch(/^# ShowRecorder\n\n> /);
    for (const d of DOCS) expect(body).toContain(`${SITE_URL}/docs/${d.slug}`);
    expect(body).toContain(`${SITE_URL}/privacy`);
  });
});

describe("home page share card", () => {
  it("uses the full home title, not just the app name", () => {
    const meta = pageMetadata(PAGES.home);
    expect(meta.openGraph?.title).toBe(PAGES.home.title);
    expect(meta.twitter?.title).toBe(PAGES.home.title);
  });
});

describe("FAQ structured data", () => {
  it("turns each question and answer into a schema.org Question", () => {
    const data = faqPageJsonLd([{ q: "Do I need the internet?", a: "No." }]);
    expect(data).toEqual({
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: [{ "@type": "Question", name: "Do I need the internet?", acceptedAnswer: { "@type": "Answer", text: "No." } }],
    });
  });

  it("escapes < so the JSON cannot close its script tag", () => {
    expect(jsonLdScript({ text: "</script>" })).not.toContain("<");
  });
});

describe("one description everywhere (#704)", () => {
  it("is the home description, the structured data description and the llms.txt summary", async () => {
    expect(PAGES.home.description).toBe(SITE_DESCRIPTION);
    expect(softwareApplicationJsonLd().description).toBe(SITE_DESCRIPTION);
    expect(await llmsTxt().text()).toContain(`> ${SITE_DESCRIPTION}`);
    expect(await llmsFullTxt().text()).toContain(`> ${SITE_DESCRIPTION}`);
  });

  it("is short enough for a search snippet", () => {
    expect(SITE_DESCRIPTION.length).toBeLessThanOrEqual(155);
  });

  it("keeps each docs description the same as the page's own meta description", () => {
    for (const d of DOCS) {
      const mdx = readFileSync(path.resolve(__dirname, "..", "app", "docs", d.slug, "page.mdx"), "utf8");
      expect(mdx).toContain(`description: "${d.description}"`);
    }
  });
});

describe("llms.txt facts (#704)", () => {
  it("states price, requirements, file format and what is in the beta", async () => {
    const body = await llmsTxt().text();
    expect(body).toMatch(/\$19\.99/);
    expect(body).toMatch(/Free records 2 USB Channels of your choice/);
    expect(body).toMatch(/iPhone 15 or later/);
    expect(body).toMatch(/mono 24-bit Broadcast WAV/);
    expect(body).toMatch(/public beta/);
    expect(body).toMatch(/Mac version/);
    for (const f of inBetaFeatures) expect(body).toContain(f.title);
  });

  it("says Pioneer DJM mixers are planned, not available", async () => {
    const body = await llmsTxt().text();
    expect(body).toMatch(/Planned, not available: Pioneer DJM/);
    expect(body).not.toMatch(/DJM[^.]*(records|supported)/i);
  });

  it("gives a one-line description to every docs page and both mixer pages", async () => {
    const body = await llmsTxt().text();
    for (const d of DOCS) expect(body).toContain(`${SITE_URL}/docs/${d.slug}): ${d.description}`);
    for (const page of [PAGES.mixersXR18, PAGES.mixersX32]) expect(body).toContain(`${SITE_URL}${page.path}): ${page.description}`);
  });

  it("has no em dash", async () => {
    expect(await llmsTxt().text()).not.toMatch(/\u2014/);
    expect(await llmsFullTxt().text()).not.toMatch(/\u2014/);
  });
});

describe("llms-full.txt (#704)", () => {
  it("serves plain text with every feature and every release", async () => {
    const res = llmsFullTxt();
    expect(res.headers.get("content-type")).toMatch(/^text\/plain/);
    const body = await res.text();
    for (const g of featureGroups) for (const f of g.features) expect(body).toContain(f.title);
    for (const f of inBetaFeatures) expect(body).toContain(f.title);
    for (const r of RELEASES) expect(body).toContain(`### ${r.version} (`);
  });

  it("marks TestFlight-only features as not in the App Store version", async () => {
    const body = await llmsFullTxt().text();
    const beta = body.slice(body.indexOf("### In the public beta"));
    expect(beta).toMatch(/Auto-gain/);
    expect(beta.indexOf("not in the App Store version")).toBeGreaterThan(-1);
  });
});

describe("mixer page structured data (#704)", () => {
  it("gives each mixer page its own SoftwareApplication with the same offers", () => {
    const xr18 = mixerApplicationJsonLd(PAGES.mixersXR18);
    expect(xr18).toMatchObject({ "@type": "SoftwareApplication", url: `${SITE_URL}/mixers/xr18`, description: PAGES.mixersXR18.description });
    expect(xr18.offers).toEqual(softwareApplicationJsonLd().offers);
  });

  it("builds a Home > page BreadcrumbList", () => {
    expect(breadcrumbJsonLd("XR18 and MR18", "/mixers/xr18").itemListElement).toEqual([
      { "@type": "ListItem", position: 1, name: "ShowRecorder", item: SITE_URL },
      { "@type": "ListItem", position: 2, name: "XR18 and MR18", item: `${SITE_URL}/mixers/xr18` },
    ]);
  });

  it.each([
    ["XR18_FAQS", XR18_FAQS],
    ["X32_FAQS", X32_FAQS],
  ])("%s has 4 to 6 questions, each a plain-text answer that is also in the FAQPage data", (_name, faqs) => {
    expect(faqs.length).toBeGreaterThanOrEqual(4);
    expect(faqs.length).toBeLessThanOrEqual(6);
    const data = faqPageJsonLd(faqs);
    expect(data.mainEntity.map((q) => q.acceptedAnswer.text)).toEqual(faqs.map((f) => f.a));
  });
});

describe("links to /compare (#704)", () => {
  const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");

  it("the home FAQ, the features page and the footer link it", () => {
    expect(read("app", "page.tsx")).toMatch(/How does ShowRecorder compare with other apps\?[\s\S]*href="\/compare"/);
    expect(read("app", "features", "page.tsx")).toMatch(/href="\/compare"/);
    expect(read("components", "Footer.tsx")).toMatch(/href="\/compare"/);
  });
});
