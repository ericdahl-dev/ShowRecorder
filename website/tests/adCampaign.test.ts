import { readFileSync } from "node:fs";
import path from "node:path";
import { Fragment, createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { GetBand } from "@/components/GetBand";
import { MixerHero } from "@/components/MixerHero";
import { adCampaign, adCampaignScript } from "@/lib/adCampaign";
import { APP_STORE_URL, appStoreLink } from "@/lib/site";

// A visitor from a paid Facebook ad lands with ?utm_source=facebook&utm_medium=paid&utm_campaign=fbad-<ad>. The App
// Store links on that page then carry the ad as their ct, so App Store Connect counts downloads per ad. Only a
// campaign that fits the fbad- pattern is used; anything else keeps the page's own ct.
const ad = (campaign: string, extra = "") => `?utm_source=facebook&utm_medium=paid&utm_campaign=${campaign}${extra}`;

describe("adCampaign", () => {
  it.each(["fbad-xr18", "fbad-church", "fbad-x32"])("uses the paid Facebook campaign %s", (campaign) => {
    expect(adCampaign(ad(campaign))).toBe(campaign);
  });

  // fbad- plus at most 34 characters: 39 in all, inside the 40 a ct can hold.
  it("allows the longest campaign, fbad- plus 34 characters", () => {
    const longest = `fbad-${"a".repeat(34)}`;
    expect(adCampaign(ad(longest))).toBe(longest);
  });

  it.each([
    ["no query", ""],
    ["no campaign", "?utm_source=facebook&utm_medium=paid"],
    ["an organic Facebook post", "?utm_source=facebook&utm_campaign=fbad-xr18"],
    ["another medium", "?utm_source=facebook&utm_medium=social&utm_campaign=fbad-xr18"],
    ["another source", "?utm_source=reddit&utm_medium=paid&utm_campaign=fbad-xr18"],
    ["a campaign without the fbad- prefix", ad("xr18-group")],
    ["just the prefix", ad("fbad-")],
    ["capital letters", ad("fbad-XR18")],
    ["an underscore", ad("fbad-xr_18")],
    ["a space", ad("fbad-xr%2018")],
    ["markup", ad("fbad-%3Cscript%3E")],
    ["an ampersand", ad("fbad-x%26ct%3Devil")],
    ["a line break", ad("fbad-xr18%0A")],
    ["a campaign one character too long", ad(`fbad-${"a".repeat(35)}`)],
    ["a campaign far too long", ad(`fbad-${"a".repeat(200)}`)],
    ["Fbad- with a capital", ad("Fbad-xr18")],
  ])("keeps the page's own ct for %s", (_, search) => {
    expect(adCampaign(search)).toBeNull();
  });

  it("uses the first utm_campaign when the address repeats it", () => {
    expect(adCampaign(ad("fbad-xr18", "&utm_campaign=fbad-x32"))).toBe("fbad-xr18");
  });
});

describe("adCampaignScript", () => {
  it("runs on every page after it loads", () => {
    const layout = readFileSync(path.join(__dirname, "..", "app", "layout.tsx"), "utf8");
    expect(layout).toMatch(/<Script id="ad-campaign" strategy="afterInteractive">\s*\{adCampaignScript\(\)\}\s*<\/Script>/);
  });

  // The privacy page says the site stores nothing in the browser; this keeps that true.
  it("stores nothing in the browser", () => {
    expect(adCampaignScript()).not.toMatch(/cookie|localStorage|sessionStorage|indexedDB/i);
  });
});

// The mixer pages are the ad landing pages. Their HTML is built ahead of time with the page's own ct; after the page
// loads, adCampaignScript() (in app/layout.tsx) retags the App Store links from the address of this visit. Here it
// runs against the links in the rendered hero and closing band, with only the page address as input.
type FakeLink = { href: string; getAttribute(name: string): string | null; setAttribute(name: string, value: string): void };

function linksIn(html: string): FakeLink[] {
  return [...html.matchAll(/<a\b[^>]*\bhref="([^"]*)"/g)].map((m) => {
    const link: FakeLink = {
      href: m[1].replace(/&amp;/g, "&"),
      getAttribute: (name) => (name === "href" ? link.href : null),
      setAttribute: (name, value) => {
        if (name === "href") link.href = value;
      },
    };
    return link;
  });
}

function visit(html: string, search: string): string[] {
  const links = linksIn(html);
  const window = { location: { search } };
  const document = { querySelectorAll: () => links };
  new Function("window", "document", adCampaignScript())(window, document);
  return links.map((l) => l.href).filter((href) => href.startsWith(APP_STORE_URL!));
}

const mixerPages = [
  ["/mixers/xr18", "site-xr18", "site-xr18-footer"],
  ["/mixers/x32", "site-x32", "site-x32-footer"],
] as const;

describe.each(mixerPages)("the App Store links on %s", (_, hero, footer) => {
  const html = renderToStaticMarkup(
    createElement(
      Fragment,
      null,
      createElement(MixerHero, { campaign: hero, eyebrow: "", title: "", lede: "" }),
      createElement(GetBand, { title: "", campaign: footer }),
    ),
  );
  const pageDefault = [appStoreLink(hero), appStoreLink(footer)];

  it("carry the ad's campaign for a visit from a paid Facebook ad", () => {
    expect(visit(html, ad("fbad-church"))).toEqual([
      "https://apps.apple.com/app/id6820213310?pt=117729664&ct=fbad-church&mt=8",
      "https://apps.apple.com/app/id6820213310?pt=117729664&ct=fbad-church&mt=8",
    ]);
  });

  it.each([
    ["a bad campaign", ad("fbad-%3Cb%3E")],
    ["an organic post", "?utm_source=facebook&utm_campaign=fbad-xr18"],
    ["no query", ""],
  ])("keep the page's own campaign for %s", (_, search) => {
    expect(visit(html, search)).toEqual(pageDefault);
  });
});
