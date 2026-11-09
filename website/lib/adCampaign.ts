import { APP_STORE_URL } from "@/lib/site";

// The ct for a visit from a paid Facebook ad: the ad's utm_campaign when the page address has utm_source=facebook,
// utm_medium=paid and a campaign of the form fbad-<name> (lowercase letters, digits and hyphens, 39 characters at
// most, inside the 40 a ct can hold), else null. Nothing else from the address ever reaches a link.
export function adCampaign(search: string): string | null {
  const query = new URLSearchParams(search);
  const campaign = query.get("utm_campaign");
  if (query.get("utm_source") !== "facebook" || query.get("utm_medium") !== "paid" || campaign === null) return null;
  return /^fbad-[a-z0-9-]{1,34}$/.test(campaign) ? campaign : null;
}

// Run once after the page loads (app/layout.tsx). The pages are built ahead of time, so their App Store links carry
// the placement's ct; for a visit from a paid Facebook ad this swaps in the ad's campaign on every tagged App Store
// link on the page, so App Store Connect counts downloads per ad. It reads only this page's address and stores
// nothing (no cookies, no storage), so the next page's links are the plain placement ones again. adCampaign above is
// copied in as source, so the page and the tests run the same check.
export function adCampaignScript(): string {
  return `(function () {
  try {
    var adCampaign = ${adCampaign.toString()};
    var ct = adCampaign(window.location.search);
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
