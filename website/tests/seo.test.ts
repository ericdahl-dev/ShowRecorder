import { GET as llmsTxt } from "@/app/llms.txt/route";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { DOCS } from "@/lib/docs";
import { softwareApplicationJsonLd } from "@/lib/structuredData";
import { APP_STORE_URL, SITE_URL } from "@/lib/site";

describe("structured data", () => {
  const data = softwareApplicationJsonLd();

  it("describes ShowRecorder as an iOS app that is free to download", () => {
    expect(data).toMatchObject({
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "ShowRecorder",
      url: SITE_URL,
      applicationCategory: "MultimediaApplication",
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    });
    expect(data.operatingSystem).toMatch(/iOS/);
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
