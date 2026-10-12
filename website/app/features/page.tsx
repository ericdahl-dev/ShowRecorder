import { featureGroups } from "@/lib/features";
import { PAGES, pageMetadata } from "@/lib/metadata";

export const metadata = pageMetadata(PAGES.features);

// Every feature, grouped, each marked Free or Pro in words (not color alone).
// Content: lib/features.ts (each entry cites the app source it was checked against).

function Tier({ tier }: { tier: "free" | "pro" }) {
  return <span className={`tier tier--${tier}`}>{tier === "pro" ? "Pro" : "Free"}</span>;
}

export default function FeaturesPage() {
  return (
    <div className="wrap features-page">
      <header className="features-head">
        <h1>Features</h1>
        <p className="lede">
          Everything ShowRecorder does on your iPhone or iPad, grouped by what it is for. Each feature says
          whether it is in Free or comes with Pro.
        </p>
        <dl className="tier-key">
          <div>
            <dt>
              <Tier tier="free" />
            </dt>
            <dd>In the free download, for everyone.</dd>
          </div>
          <div>
            <dt>
              <Tier tier="pro" />
            </dt>
            <dd>With Pro, a one-time $19.99, and during the 14-day Trial.</dd>
          </div>
        </dl>
        <p className="features-links">
          What each plan includes is in <a href="/docs/pricing">Free, 14-day Trial and Pro</a>. Prices are on
          the <a href="/#pricing">home page</a>.
        </p>
        <nav aria-label="Feature groups" className="group-jump">
          <ul>
            {featureGroups.map((g) => (
              <li key={g.id}>
                <a href={`#${g.id}`}>{g.title}</a>
              </li>
            ))}
          </ul>
        </nav>
      </header>

      {featureGroups.map((group) => (
        <section key={group.id} id={group.id} aria-labelledby={`${group.id}-title`} className="feature-group">
          <div className="section-head">
            <h2 id={`${group.id}-title`}>{group.title}</h2>
            {group.intro ? <p>{group.intro}</p> : null}
          </div>
          <ul className="cards cards--3">
            {group.features.map((f) => (
              <li key={f.title} className={`card feature feature--${f.tier}`}>
                <div className="feature-top">
                  <h3>{f.title}</h3>
                  <Tier tier={f.tier} />
                </div>
                <p>{f.body}</p>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
