import { AppStoreBadge } from "@/components/AppStoreBadge";
import { trackAttrs } from "@/lib/analytics";
import { DEVICE_REQUIREMENT } from "@/lib/guide";
import { PAGE_DATES } from "@/lib/pageDates";
import { TESTFLIGHT_URL, type AppStoreCampaign } from "@/lib/site";
import type { Crumb } from "@/lib/structuredData";

// Pieces every mixer recording guide and the hub share (review batch 1 on #1081): the visible breadcrumb, the day the
// page was last checked, the call to get the app and the "ask us" line.

// Home > ... > the page, as a visible list. The page's BreadcrumbList JSON-LD uses the same trail.
export function Breadcrumbs({ trail }: { trail: readonly Crumb[] }) {
  const last = trail.length - 1;
  return (
    <nav aria-label="Breadcrumb" className="breadcrumbs">
      <ol>
        <li>
          <a href="/">Home</a>
        </li>
        {trail.map((c, i) =>
          i === last ? (
            <li key={c.path} aria-current="page">
              {c.name}
            </li>
          ) : (
            <li key={c.path}>
              <a href={c.path}>{c.name}</a>
            </li>
          ),
        )}
      </ol>
    </nav>
  );
}

// "Last checked 2026-11-06", from the page's date in PAGE_DATES (scripts/page-dates.mjs).
export function LastChecked({ path }: { path: string }) {
  const day = PAGE_DATES[path];
  if (!day) return null;
  return (
    <p className="last-checked">
      Last checked <time dateTime={day}>{day}</time>
    </p>
  );
}

// The same label everywhere, so it reads as one way to reach us.
export const ASK_US_LABEL = "Your mixer not listed, or not tested? Ask us";

export function AskUs() {
  return (
    <p className="ask-us">
      <a href="/support">{ASK_US_LABEL}</a>
    </p>
  );
}

// The App Store badge with the page's campaign, what the app runs on, and the Mac beta.
export function GetTheApp({ campaign }: { campaign: AppStoreCampaign }) {
  return (
    <div className="guide-get-app">
      <AppStoreBadge id="app-store-link" campaign={campaign} />
      <p className="guide-get-app-note">
        Runs on {DEVICE_REQUIREMENT}.
        {TESTFLIGHT_URL ? (
          <>
            {" "}
            <a href={TESTFLIGHT_URL} {...trackAttrs("join_beta_clicked", "testflight")}>
              Mac: join the TestFlight beta
            </a>
            .
          </>
        ) : null}
      </p>
    </div>
  );
}
