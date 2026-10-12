/* eslint-disable @next/next/no-img-element -- a static SVG; next/image adds nothing for it in a static export */
import { APP_STORE_URL, TESTFLIGHT_URL } from "@/lib/site";

// The App Store slot used in the hero and the closing call. Driven by APP_STORE_URL in lib/site.ts.
//
// While APP_STORE_URL is null it renders a status, not a link: "Coming soon to the App Store",
// sized like the badge (52 px tall) so nothing moves when the real badge goes in.
//
// With APP_STORE_URL set it links to the App Store with Apple's official black "Download on the
// App Store" badge (public/images/app-store-badge.svg, from developer.apple.com, unmodified, 52 px
// tall). layout.tsx adds the apple-itunes-app tag from APP_STORE_ID.
export function AppStoreBadge({ id }: { id: "app-store-link" | "app-store-link-footer" }) {
  if (APP_STORE_URL) {
    return (
      <a id={id} className="store-badge" href={APP_STORE_URL}>
        {/* Apple's official badge from developer.apple.com Marketing Resources, unmodified. The black
            badge has its own grey border, so it reads on the Dark and light themes alike. */}
        <img src="/images/app-store-badge.svg" alt="Download on the App Store" width={156} height={52} />
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
