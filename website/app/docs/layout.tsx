import Link from "next/link";
import { DOCS, docHref } from "@/lib/docs";

// Docs shell: the list of doc pages beside the article at 1024 px and up, and a <details>
// disclosure above it on smaller screens (no scripts). The MDX pages render inside .doc via
// mdx-components.tsx. The current page's link gets aria-current from the inline script
// (data-current-match), because this layout is shared by every doc page.
function DocLinks() {
  return (
    <ul className="docs-links">
      <li>
        <Link href={docHref("")} data-current-match="">
          Overview
        </Link>
      </li>
      {DOCS.map((d) => (
        <li key={d.slug}>
          <Link href={docHref(d.slug)} data-current-match="">
            {d.title}
          </Link>
        </li>
      ))}
    </ul>
  );
}

export default function DocsLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="wrap docs-shell">
      <details className="docs-nav-mobile">
        <summary>Docs pages</summary>
        <nav aria-label="Docs">
          <DocLinks />
        </nav>
      </details>
      <nav aria-label="Docs" className="docs-nav-desktop">
        <p className="docs-nav-title">Docs</p>
        <DocLinks />
      </nav>
      <div className="docs-main">{children}</div>
    </div>
  );
}
