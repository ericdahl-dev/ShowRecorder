import { APP_STORE_URL } from "@/lib/site";

// Where the visit's campaign is kept in sessionStorage (it lasts until the tab closes).
export const CAMPAIGN_KEY = "showrecorder-ct";

type CampaignStorage = { getItem(key: string): string | null; setItem(key: string, value: string): void };

// The ct for this visit, first touch wins: the campaign already remembered for the visit if there is one, else this
// address's utm_campaign, which is then remembered. A campaign is 1 to 40 lowercase letters, digits or hyphens (40 is
// all a ct can hold); anything else is ignored, in the address and in storage. Any utm_source counts. Storage that is
// missing or throws (private mode, blocked site data) only loses the memory: this page still uses its own campaign.
// It refers to nothing outside itself, because adCampaignScript() copies it into the page as source.
export function rememberedCampaign(search: string, storage: CampaignStorage | null): string | null {
  const key = "showrecorder-ct";
  const valid = (value: string | null): value is string => value !== null && /^[a-z0-9-]{1,40}$/.test(value);
  try {
    const kept = storage ? storage.getItem(key) : null;
    if (valid(kept)) return kept;
  } catch {}
  const campaign = new URLSearchParams(search).get("utm_campaign");
  if (!valid(campaign)) return null;
  try {
    if (storage) storage.setItem(key, campaign);
  } catch {}
  return campaign;
}

// The ct a tagged address asks for, without any memory.
export function postCampaign(search: string): string | null {
  return rememberedCampaign(search, null);
}

// Run once after each page loads (app/layout.tsx). The pages are built ahead of time, so their App Store links carry
// the placement's ct; while the visit has a campaign (rememberedCampaign above), this swaps it in on every tagged App
// Store link on the page, so App Store Connect counts downloads per post or ad. Without JavaScript, or with no
// campaign, the links keep the placement's ct. It sets no cookies; the campaign is the only thing it keeps, in
// sessionStorage. rememberedCampaign is copied in as source, so the page and the tests run the same code.
export function postCampaignScript(): string {
  return `(function () {
  try {
    var rememberedCampaign = ${rememberedCampaign.toString()};
    var storage = null;
    try { storage = window.sessionStorage; } catch (e) {}
    var ct = rememberedCampaign(window.location.search, storage);
    if (!ct) return;
    var listing = ${JSON.stringify(`${APP_STORE_URL}?`)};
    var links = document.querySelectorAll("a[href]");
    for (var i = 0; i < links.length; i++) {
      var href = links[i].getAttribute("href");
      if (!href || href.indexOf(listing) !== 0) continue;
      var url = new URL(href);
      if (!url.searchParams.has("ct")) continue;
      url.searchParams.set("ct", ct);
      links[i].setAttribute("href", url.toString());
    }
  } catch (e) {}
})();`;
}
