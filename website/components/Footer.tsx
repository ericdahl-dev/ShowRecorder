import Link from "next/link";
import { AppIcon } from "@/components/AppIcon";
import { CONTACT_EMAIL, ISSUES_URL, SITE_NAME, TRADEMARK_LINE } from "@/lib/site";

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
              <Link href="/features" data-current-match="">
                Features
              </Link>
            </li>
            <li>
              <Link href="/docs" data-current-match="">
                Docs
              </Link>
            </li>
            <li>
              <Link href="/support" data-current-match="">
                Support
              </Link>
            </li>
            <li>
              <Link href="/privacy" data-current-match="">
                Privacy
              </Link>
            </li>
            <li>
              <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
            </li>
            <li>
              <a href={ISSUES_URL}>Report a problem</a>
            </li>
          </ul>
        </nav>
        <p className="legal">{TRADEMARK_LINE}</p>
        <p className="legal">Copyright 2026 Eric Dahl</p>
      </div>
    </footer>
  );
}
