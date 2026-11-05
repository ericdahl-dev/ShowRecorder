import { trackAttrs } from "@/lib/analytics";
import { TESTFLIGHT_URL } from "@/lib/site";

// A quiet text link under the App Store badge, for people who want new features early. The badge stays the main
// button. On the mixer pages the click script reports it as mixer_page_cta_clicked (lib/analytics.ts).
export function BetaLink() {
  if (!TESTFLIGHT_URL) return null;
  return (
    <p className="beta-link">
      <a href={TESTFLIGHT_URL} {...trackAttrs("join_beta_clicked", "testflight")}>
        Or try new features early in the public beta
      </a>
    </p>
  );
}
