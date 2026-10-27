import { trackAttrs } from "@/lib/analytics";
import { AppIcon } from "@/components/AppIcon";
import { CONTACT_EMAIL, ISSUES_URL, REPO_URL, SITE_NAME, TRADEMARK_LINE } from "@/lib/site";

export function Footer() {
  return (
    <footer className="site-footer">
      <div className="wrap">
        <p className="footer-brand">
          <AppIcon size={28} />
          <span>{SITE_NAME}</span>
        </p>
        <nav aria-label="Footer">
          <ul className="footer-links">
            <li>
              <a href="/features" data-current-match="" suppressHydrationWarning>
                Features
              </a>
            </li>
            <li>
              <a href="/compare" data-current-match="" suppressHydrationWarning>
                Compare
              </a>
            </li>
            <li>
              <a href="/docs" data-current-match="" suppressHydrationWarning>
                Docs
              </a>
            </li>
            <li>
              <a href="/changelog" data-current-match="" suppressHydrationWarning>
                What&apos;s new
              </a>
            </li>
            <li>
              <a href="/support" data-current-match="" suppressHydrationWarning>
                Support
              </a>
            </li>
            <li>
              <a href="/privacy" data-current-match="" suppressHydrationWarning>
                Privacy
              </a>
            </li>
            <li className="footer-wide">
              <a href={`mailto:${CONTACT_EMAIL}`} {...trackAttrs("contact_email_clicked")}>{CONTACT_EMAIL}</a>
            </li>
            <li>
              <a href={ISSUES_URL}>Report a problem</a>
            </li>
            <li>
              <a href={REPO_URL}>Source on GitHub</a>
            </li>
          </ul>
        </nav>
        <nav aria-label="Supported mixers">
          <ul className="footer-links">
            <li className="footer-group footer-wide">Supported mixers</li>
            <li>
              <a href="/mixers/xr18" data-current-match="" suppressHydrationWarning>
                XR18 and MR18
              </a>
            </li>
            <li>
              <a href="/mixers/x32" data-current-match="" suppressHydrationWarning>
                X32 and M32 (beta)
              </a>
            </li>
          </ul>
        </nav>
        <p className="legal">{TRADEMARK_LINE}</p>
        <p className="legal">Copyright 2026 Eric Dahl</p>
      </div>
    </footer>
  );
}
