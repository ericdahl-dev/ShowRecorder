import { BETA_SUMMARY, RELEASES } from "@/lib/changelog";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { APP_STORE_URL, REPO_URL } from "@/lib/site";

export const metadata = pageMetadata(PAGES.changelog);

// Content: lib/changelog.ts. Uses the text-page styling (.doc) the MDX pages share.

function formatDate(iso: string): string {
  return new Date(`${iso}T12:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}

export default function ChangelogPage() {
  return (
    <div className="wrap">
      <article className="doc changelog">
        <h1>What&apos;s new</h1>
        <p>Every ShowRecorder version, newest first, and where you can get it.</p>
        {RELEASES.map((r) => (
          <section key={r.version} aria-labelledby={`v${r.version}`}>
            <h2 id={`v${r.version}`}>{r.version}</h2>
            <p className="updated">
              <time dateTime={r.date}>{formatDate(r.date)}</time> · {r.channel}
            </p>
            {r.summary ? <p>{r.summary}</p> : null}
            {r.channel === "App Store" && APP_STORE_URL ? (
              <p>
                <a href={APP_STORE_URL}>ShowRecorder on the App Store</a>
              </p>
            ) : null}
            <ul>
              {r.changes.map((c) => (
                <li key={c}>{c}</li>
              ))}
            </ul>
          </section>
        ))}
        <h2 id="beta">Before 1.0</h2>
        <p>
          {BETA_SUMMARY} Every commit is on <a href={REPO_URL}>GitHub</a>.
        </p>
      </article>
    </div>
  );
}
