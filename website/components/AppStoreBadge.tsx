import { APP_STORE_URL, TESTFLIGHT_URL } from "@/lib/site";

// The App Store slot used in the hero and the closing call. Driven by APP_STORE_URL in lib/site.ts.
//
// While APP_STORE_URL is null it renders a status, not a link: "Coming soon to the App Store",
// sized like the badge (52 px tall) so nothing moves when the real badge goes in.
//
// When the app is live:
//   1. Set APP_STORE_URL in lib/site.ts to the App Store link.
//   2. Replace the text inside the <a> below with Apple's official "Download on the App Store"
//      badge SVG from Apple's Marketing Resources (https://developer.apple.com/app-store/marketing/guidelines/),
//      unmodified, at least 40 px tall, with alt="Download on the App Store". Use the black badge on
//      the Dark site and the white one in the light theme (two <img>s with the only-dark and
//      only-light classes). Do not draw a lookalike badge.
//   3. Add the apple-itunes-app meta tag in app/layout.tsx once the App Store ID is known.
export function AppStoreBadge({ id }: { id: "app-store-link" | "app-store-link-footer" }) {
  if (APP_STORE_URL) {
    return (
      <a id={id} className="store-slot is-live" href={APP_STORE_URL}>
        Download on the App Store
      </a>
    );
  }
  // Before release: the public beta. A plain button, not an App Store lookalike.
  if (TESTFLIGHT_URL) {
    return (
      <a id={id} className="store-slot is-live" href={TESTFLIGHT_URL}>
        Join the public beta on TestFlight
      </a>
    );
  }
  return (
    <p id={id} className="store-slot is-placeholder">
      <span className="rec-dot" aria-hidden="true" />
      <span>Coming soon to the App Store</span>
    </p>
  );
}
