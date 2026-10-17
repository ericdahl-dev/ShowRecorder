import { AppIcon } from "@/components/AppIcon";
import { NAV, SITE_NAME } from "@/lib/site";

// Phones: the wordmark and the theme toggle on one row, the nav on a second row (no hamburger).
// 768 px and up: one sticky row. Internal links are plain <a> on purpose: every click is a full
// page load, so the inline script in lib/theme.ts marks the current link on each page.
export function Header() {
  return (
    <header className="site-header">
      <div className="wrap header-inner">
        <a href="/" className="brand" data-current-match="">
          <AppIcon size={32} priority />
          <span>{SITE_NAME}</span>
        </a>
        <nav aria-label="Main" className="site-nav">
          <ul>
            {NAV.map((item) => (
              <li key={item.href} className={item.wide ? "nav-wide" : undefined}>
                <a href={item.href} data-current-match={item.href === "/docs" ? "prefix" : ""}>
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        {/* Wired up by the inline script in lib/theme.ts; hidden when scripts do not run. */}
        <button
          type="button"
          id="theme-toggle"
          className="theme-toggle"
          aria-pressed="false"
          aria-label="Light appearance"
          title="Light appearance"
          suppressHydrationWarning
        >
          <svg
            aria-hidden="true"
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
          >
            <circle cx="12" cy="12" r="4.5" />
            <path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8" />
          </svg>
        </button>
      </div>
    </header>
  );
}
