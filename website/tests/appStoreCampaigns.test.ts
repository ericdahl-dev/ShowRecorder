import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { facts } from "@/lib/llms";
import { APP_STORE_CAMPAIGNS, APP_STORE_ID, APP_STORE_PROVIDER_TOKEN, APP_STORE_URL, appStoreLink, campaignLink } from "@/lib/site";
import { softwareApplicationJsonLd } from "@/lib/structuredData";

// Every App Store link carries Apple's campaign parameters (pt, ct, mt=8) once the provider token is set, so App
// Analytics shows downloads by where the click came from. One helper builds them; ct names the placement. Apple
// ignores ct without pt, so with no token the links are the plain listing.

const ROOT = path.resolve(__dirname, "..");
const params = (url: string) => new URL(url).searchParams;

function files(p: string): string[] {
  const full = path.join(ROOT, p);
  if (statSync(full).isFile()) return [p];
  return readdirSync(full).flatMap((name) => files(path.join(p, name)));
}

describe("campaignLink", () => {
  it("with a provider token, is the listing with pt, ct for the placement and mt=8", () => {
    const url = campaignLink(APP_STORE_URL!, "site-home", "123456");
    expect(url.startsWith(`${APP_STORE_URL}?`)).toBe(true);
    expect(params(url).get("pt")).toBe("123456");
    expect(params(url).get("ct")).toBe("site-home");
    expect(params(url).get("mt")).toBe("8");
  });

  it("with no provider token, is the plain listing", () => {
    expect(campaignLink(APP_STORE_URL!, "site-home", null)).toBe(APP_STORE_URL);
  });

  it("appStoreLink uses the token in lib/site.ts", () => {
    expect(appStoreLink("site-x32")).toBe(campaignLink(APP_STORE_URL!, "site-x32", APP_STORE_PROVIDER_TOKEN));
  });

  it("has campaign names of 40 characters or fewer, each once", () => {
    expect(APP_STORE_CAMPAIGNS.length).toBeGreaterThan(5);
    for (const ct of APP_STORE_CAMPAIGNS) expect(ct.length).toBeLessThanOrEqual(40);
    expect(new Set(APP_STORE_CAMPAIGNS).size).toBe(APP_STORE_CAMPAIGNS.length);
  });
});

describe("tagged App Store links", () => {
  it("the badge links with the campaign it is given", () => {
    const html = renderToStaticMarkup(createElement(AppStoreBadge, { id: "app-store-link", campaign: "site-xr18" }));
    expect(html).toContain(`href="${appStoreLink("site-xr18")!.replace(/&/g, "&amp;")}"`);
  });

  it("llms.txt uses the llms campaign", () => {
    expect(facts().join("\n")).toContain(`App Store: ${appStoreLink("llms")}`);
  });

  it("the JSON-LD install and download links use the site-schema campaign", () => {
    const data = softwareApplicationJsonLd() as { installUrl?: string; downloadUrl?: string };
    expect(data.installUrl).toBe(appStoreLink("site-schema"));
    expect(data.downloadUrl).toBe(appStoreLink("site-schema"));
  });

  // lib/bestApp.ts cites other apps' own App Store pages as sources (#1085). It may name those, never ShowRecorder's.
  const OTHER_APPS_SOURCES = path.join("lib", "bestApp.ts");

  it("no page or component types the App Store address itself", () => {
    const hits = ["app", "components", "lib"]
      .flatMap(files)
      .filter((f) => /\.(tsx?|mdx?)$/.test(f) && f !== path.join("lib", "site.ts") && f !== OTHER_APPS_SOURCES)
      .filter((f) => /apps\.apple\.com/.test(readFileSync(path.join(ROOT, f), "utf8")));
    expect(hits).toEqual([]);
  });

  it("the best-app sources never type ShowRecorder's own App Store address", () => {
    expect(readFileSync(path.join(ROOT, OTHER_APPS_SOURCES), "utf8")).not.toContain(APP_STORE_ID);
  });
});

describe("the provider token is set (117729664, from App Store Connect)", () => {
  it("tags every site link with pt, the placement's ct and mt=8", () => {
    expect(APP_STORE_PROVIDER_TOKEN).toBe("117729664");
    expect(appStoreLink("site-home")).toBe("https://apps.apple.com/app/id6820213310?pt=117729664&ct=site-home&mt=8");
    expect(appStoreLink("llms")).toBe("https://apps.apple.com/app/id6820213310?pt=117729664&ct=llms&mt=8");
  });
});
