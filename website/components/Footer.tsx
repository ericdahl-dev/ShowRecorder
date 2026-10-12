import Link from "next/link";
import { CONTACT_EMAIL, SITE_NAME } from "@/lib/site";

export function Footer() {
  return (
    <footer className="border-t border-[var(--border)] text-sm text-[var(--muted)]">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-4 px-4 py-6">
        <p>
          &copy; {new Date().getFullYear()} {SITE_NAME}
        </p>
        <nav aria-label="Footer" className="flex gap-6">
          <Link href="/privacy" className="hover:underline">
            Privacy
          </Link>
          <Link href="/support" className="hover:underline">
            Support
          </Link>
          <a href={`mailto:${CONTACT_EMAIL}`} className="hover:underline">
            Contact
          </a>
        </nav>
      </div>
    </footer>
  );
}
