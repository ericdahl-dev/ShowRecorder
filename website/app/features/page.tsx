import { featureGroups, inBetaFeatures } from "@/lib/features";
import { considering, inBeta, planned, worksNow } from "@/lib/mixers";
import { CONTACT_EMAIL, TESTFLIGHT_URL } from "@/lib/site";
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
        <h1>Features and supported mixers</h1>
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
            <li>
              <a href="#beta">In the beta</a>
            </li>
            <li>
              <a href="#mixers">Supported mixers</a>
            </li>
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

      <section id="beta" aria-labelledby="beta-title" className="feature-group">
        <div className="section-head">
          <h2 id="beta-title">In the beta</h2>
          <p>
            Coming in 1.1, and in the public TestFlight beta now.
            {TESTFLIGHT_URL ? (
              <>
                {" "}
                <a href={TESTFLIGHT_URL}>Join the beta</a> to try them.
              </>
            ) : null}
          </p>
        </div>
        <ul className="cards cards--3">
          {inBetaFeatures.map((f) => (
            <li key={f.title} className="card feature">
              <div className="feature-top">
                <h3>{f.title}</h3>
                <span className="tier tier--beta">Beta</span>
              </div>
              <p>{f.body}</p>
            </li>
          ))}
        </ul>
      </section>

      <section id="mixers" aria-labelledby="mixers-title" className="feature-group">
        <div className="section-head">
          <h2 id="mixers-title">Supported mixers</h2>
          <p>What works in the first App Store release, what is in the public beta, what is planned next, and what is being looked at. Planned support has no dates yet.</p>
        </div>
        <h3 className="mixers-sub">Works now</h3>
        <ul className="cards cards--3">
          {worksNow.map((m) => (
            <li key={m.name} className="card">
              <h3>{m.href ? <a href={m.href}>{m.name}</a> : m.name}</h3>
              <p>{m.body}</p>
            </li>
          ))}
        </ul>
        <h3 className="mixers-sub">In the public beta</h3>
        <ul className="cards cards--3">
          {inBeta.map((m) => (
            <li key={m.name} className="card">
              <h3>{m.href ? <a href={m.href}>{m.name}</a> : m.name}</h3>
              <p>{m.body}</p>
            </li>
          ))}
        </ul>
        <h3 className="mixers-sub">Planned</h3>
        <ol className="cards cards--3">
          {planned.map((m) => (
            <li key={m.name} className="card">
              <h3>{m.name}</h3>
              <p>{m.body}</p>
            </li>
          ))}
        </ol>
        <h3 className="mixers-sub">Being looked at</h3>
        <p className="mixers-note">
          Not promised. Each one needs USB audio that an iPhone or iPad accepts without a driver, and that is
          being checked mixer by mixer.
        </p>
        <ul className="mixers-considering">
          {considering.map((name) => (
            <li key={name}>{name}</li>
          ))}
        </ul>
        <p className="mixers-ask">
          Using another mixer? Tell us which at <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. It
          helps decide what comes next.
        </p>
      </section>
    </div>
  );
}
