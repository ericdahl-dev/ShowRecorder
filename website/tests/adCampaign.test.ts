import { readFileSync } from "node:fs";
import path from "node:path";
import { Fragment, createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { GetBand } from "@/components/GetBand";
import { MixerHero } from "@/components/MixerHero";
import { CAMPAIGN_KEY, postCampaign, postCampaignScript, rememberedCampaign } from "@/lib/adCampaign";
import { APP_STORE_URL, appStoreLink } from "@/lib/site";

// A visitor from a tagged post or ad lands with ?utm_source=<place>&utm_campaign=<post>. The post's campaign becomes
// the ct of the site's App Store links for the rest of the visit, so App Store Connect counts downloads per post.
const tagged = (campaign: string, extra = "") => `?utm_source=facebook&utm_campaign=${campaign}${extra}`;

describe("postCampaign", () => {
  it.each(["fbad-xr18", "xr18-group-beta-1-2", "x32-group-beta-1-2", "reddit-x32", "a", "2026"])("uses the campaign %s", (campaign) => {
    expect(postCampaign(tagged(campaign))).toBe(campaign);
  });

  it.each(["reddit", "email", "forum"])("uses a campaign from %s too", (source) => {
    expect(postCampaign(`?utm_source=${source}&utm_campaign=spring-post`)).toBe("spring-post");
  });

  it("allows the longest campaign, 40 characters, all a ct can hold", () => {
    const longest = "a".repeat(40);
    expect(postCampaign(tagged(longest))).toBe(longest);
  });

  it.each([
    ["no query", ""],
    ["no campaign", "?utm_source=facebook"],
    ["an empty campaign", tagged("")],
    ["capital letters", tagged("XR18-group")],
    ["an underscore", tagged("xr_18")],
    ["a space", tagged("xr%2018")],
    ["a dot", tagged("xr18.group")],
    ["markup", tagged("%3Cscript%3E")],
    ["an ampersand", tagged("x%26ct%3Devil")],
    ["a line break", tagged("xr18%0A")],
    ["a campaign one character too long", tagged("a".repeat(41))],
    ["a campaign far too long", tagged("a".repeat(200))],
  ])("ignores %s", (_, search) => {
    expect(postCampaign(search)).toBeNull();
  });

  it("uses the first utm_campaign when the address repeats it", () => {
    expect(postCampaign(tagged("xr18-group", "&utm_campaign=x32-group"))).toBe("xr18-group");
  });
});

// The visit's memory: sessionStorage, which lasts until the tab closes. A fake stands in for it here.
function fakeStorage(start: Record<string, string> = {}) {
  const items = new Map(Object.entries(start));
  return {
    items,
    getItem: (key: string) => items.get(key) ?? null,
    setItem: (key: string, value: string) => void items.set(key, value),
  };
}

const brokenStorage = {
  getItem: (): string | null => {
    throw new Error("SecurityError");
  },
  setItem: () => {
    throw new Error("QuotaExceededError");
  },
};

describe("rememberedCampaign (first touch wins)", () => {
  it("remembers the campaign of the page the visit landed on", () => {
    const storage = fakeStorage();
    expect(rememberedCampaign(tagged("xr18-group"), storage)).toBe("xr18-group");
    expect(storage.items.get(CAMPAIGN_KEY)).toBe("xr18-group");
    expect(rememberedCampaign("", storage)).toBe("xr18-group");
  });

  it("keeps the first campaign when a later page has another", () => {
    const storage = fakeStorage();
    rememberedCampaign(tagged("xr18-group"), storage);
    expect(rememberedCampaign(tagged("x32-group"), storage)).toBe("xr18-group");
  });

  it("remembers nothing for a bad campaign, so a later good one still counts", () => {
    const storage = fakeStorage();
    expect(rememberedCampaign(tagged("%3Cb%3E"), storage)).toBeNull();
    expect(storage.items.size).toBe(0);
    expect(rememberedCampaign(tagged("x32-group"), storage)).toBe("x32-group");
  });

  it("is null for a visit with no campaign", () => {
    expect(rememberedCampaign("", fakeStorage())).toBeNull();
  });

  it("ignores a stored value that is not a campaign", () => {
    const storage = fakeStorage({ [CAMPAIGN_KEY]: "<b>bad</b>" });
    expect(rememberedCampaign("", storage)).toBeNull();
    expect(rememberedCampaign(tagged("x32-group"), storage)).toBe("x32-group");
  });

  it("still uses this page's campaign when storage is blocked", () => {
    expect(rememberedCampaign(tagged("xr18-group"), brokenStorage)).toBe("xr18-group");
    expect(rememberedCampaign("", brokenStorage)).toBeNull();
  });

  it("still uses this page's campaign when there is no storage at all", () => {
    expect(rememberedCampaign(tagged("xr18-group"), null)).toBe("xr18-group");
  });
});

describe("postCampaignScript", () => {
  it("runs on every page after it loads", () => {
    const layout = readFileSync(path.join(__dirname, "..", "app", "layout.tsx"), "utf8");
    expect(layout).toMatch(/<Script id="post-campaign" strategy="afterInteractive">\s*\{postCampaignScript\(\)\}\s*<\/Script>/);
  });

  // The privacy page says the site sets no cookies and keeps only this campaign, for the visit.
  it("sets no cookies and keeps nothing past the visit", () => {
    expect(postCampaignScript()).not.toMatch(/cookie|localStorage|indexedDB/i);
  });

  it("is on the privacy page", () => {
    const privacy = readFileSync(path.join(__dirname, "..", "app", "privacy", "page.mdx"), "utf8");
    expect(privacy).not.toMatch(/stores nothing in your browser or on your device, unless you open the chat \(see below\)\./);
    expect(privacy).toMatch(/keeps that name in your browser until you close the tab/);
  });
});

// The pages are built ahead of time with each placement's own ct. After a page loads, postCampaignScript() (in
// app/layout.tsx) retags its App Store links with the visit's campaign. Here it runs against the links in rendered
// pages, with the page address and a fake sessionStorage as its only inputs.
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

// Opens a page in a tab: runs the script with the page's links, its address and the tab's storage, and returns the
// App Store links as they then are.
function openPage(html: string, search: string, storage: object | "blocked"): string[] {
  const links = linksIn(html);
  const window = { location: { search } };
  Object.defineProperty(window, "sessionStorage", {
    get() {
      if (storage === "blocked") throw new Error("SecurityError");
      return storage;
    },
  });
  const document = { querySelectorAll: () => links };
  new Function("window", "document", postCampaignScript())(window, document);
  return links.map((l) => l.href).filter((href) => href.startsWith(APP_STORE_URL!));
}

const store = (ct: string) => `https://apps.apple.com/app/id6820213310?pt=117729664&ct=${ct}&mt=8`;

const mixerPage = renderToStaticMarkup(
  createElement(
    Fragment,
    null,
    createElement(MixerHero, { campaign: "site-xr18", eyebrow: "", title: "", lede: "" }),
    createElement(GetBand, { title: "", campaign: "site-xr18-footer" }),
  ),
);
const homePage = renderToStaticMarkup(createElement(AppStoreBadge, { id: "app-store-link", campaign: "site-home" }));

describe("App Store links during a visit", () => {
  it("carry the post's campaign instead of the placement's on the landing page", () => {
    expect(openPage(mixerPage, tagged("xr18-group-beta-1-2"), fakeStorage())).toEqual([
      store("xr18-group-beta-1-2"),
      store("xr18-group-beta-1-2"),
    ]);
  });

  it("carry the first post's campaign on every later page of the visit", () => {
    const tab = fakeStorage();
    openPage(mixerPage, tagged("fbad-xr18"), tab);
    expect(openPage(homePage, "", tab)).toEqual([store("fbad-xr18")]);
    expect(openPage(homePage, tagged("x32-group"), tab)).toEqual([store("fbad-xr18")]);
  });

  it("keep the placement's campaign on a visit with no campaign", () => {
    expect(openPage(mixerPage, "", fakeStorage())).toEqual([appStoreLink("site-xr18"), appStoreLink("site-xr18-footer")]);
    expect(openPage(homePage, "?utm_source=facebook", fakeStorage())).toEqual([appStoreLink("site-home")]);
  });

  it("keep the placement's campaign for a bad campaign", () => {
    expect(openPage(homePage, tagged("%3Cb%3E"), fakeStorage())).toEqual([appStoreLink("site-home")]);
  });

  it("still carry the landing page's campaign when storage is blocked", () => {
    expect(openPage(homePage, tagged("xr18-group"), "blocked")).toEqual([store("xr18-group")]);
    expect(openPage(homePage, "", "blocked")).toEqual([appStoreLink("site-home")]);
  });
});
