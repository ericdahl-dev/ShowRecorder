import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { APP_STORE_URL } from "@/lib/site";

// 1.0 is on the App Store (#382): the hero and closing slots link to the listing with Apple's badge.
describe("App Store badge (#382)", () => {
  it("links to the App Store listing", () => {
    expect(APP_STORE_URL).toBe("https://apps.apple.com/app/id6820213310");
  });

  it.each(["app-store-link", "app-store-link-email"] as const)("the %s slot is Apple's badge, linking to APP_STORE_URL", (id) => {
    const html = renderToStaticMarkup(createElement(AppStoreBadge, { id }));
    expect(html).toContain(`href="${APP_STORE_URL}"`);
    expect(html).toContain('src="/images/app-store-badge.svg" alt="Download on the App Store"');
  });
});
