import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { APP_STORE_URL, TESTFLIGHT_URL } from "@/lib/site";

// 1.0 is on the App Store (#382): the slots link to the listing with Apple's badge; a beta-only mixer page stays on TestFlight.
describe("App Store badge (#382)", () => {
  it("is Apple's badge, linking to the App Store listing", () => {
    const html = renderToStaticMarkup(createElement(AppStoreBadge, { id: "app-store-link" }));
    expect(APP_STORE_URL).toBe("https://apps.apple.com/app/id6820213310");
    expect(html).toContain(`href="${APP_STORE_URL}"`);
    expect(html).toContain('src="/images/app-store-badge.svg" alt="Download on the App Store"');
  });

  it("stays on the public beta where the page asks for it", () => {
    const html = renderToStaticMarkup(createElement(AppStoreBadge, { id: "app-store-link", beta: true }));
    expect(html).toContain(`href="${TESTFLIGHT_URL}"`);
  });
});
