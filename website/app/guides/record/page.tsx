import { AskUs, Breadcrumbs, GetTheApp, LastChecked } from "@/components/GuideParts";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { InlineMarkdown } from "@/components/InlineMarkdown";
import { GLOSSARY, HUB_COPY, HUB_FAQS, MIXER_GUIDES, MIXER_ROWS } from "@/lib/mixerGuides";
import { breadcrumbListJsonLd, faqPageJsonLd, jsonLdScript } from "@/lib/structuredData";

export const metadata = pageMetadata(PAGES.guidesHub);

// The hub of the mixer recording guides (#1061). Facts: lib/mixerGuides.ts, from docs/research/mixer-recording/.
// The guides cover every way to record a mixer, not only ShowRecorder; ShowRecorder lines stay short and true.
const COLUMNS = [
  ["usb", "Over USB"],
  ["onboard", "With no computer"],
  ["mac", "Mac"],
  ["ipad", "iPad"],
  ["iphone", "iPhone"],
] as const;

const TRAIL = [{ name: "Recording guides", path: PAGES.guidesHub.path }];

// "Read the X32 guide": the guide's short name, from MIXER_GUIDES.
const guideName = (path: string) => MIXER_GUIDES.find((g) => g.path === path)?.short;

export default function GuidesHubPage() {
  return (
    <>
    <div className="wrap features-page compare-page guides-hub">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbListJsonLd(TRAIL)) }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(HUB_FAQS)) }} />
      <Breadcrumbs trail={TRAIL} />
      <header className="features-head">
        <h1>{HUB_COPY.title}</h1>
        <LastChecked path={PAGES.guidesHub.path} />
        <p className="lede">
          <InlineMarkdown text={HUB_COPY.lede} />
        </p>
        <p className="features-links">
          <InlineMarkdown text={HUB_COPY.method} />
        </p>
      </header>

      {MIXER_GUIDES.length ? (
        <nav aria-labelledby="pick-title" className="guides-pick">
          <h2 id="pick-title">Pick your mixer</h2>
          <ul>
            {MIXER_GUIDES.map((g) => (
              <li key={g.slug}>
                <a href={g.path}>{g.mixer}</a>
              </li>
            ))}
            <li>
              <a href="#mixers-title">Every other mixer, in the table</a>
            </li>
          </ul>
        </nav>
      ) : null}

      <section aria-labelledby="mixers-title" className="feature-group">
        <div className="section-head">
          <h2 id="mixers-title">{HUB_COPY.tableTitle}</h2>
          <p>
            <InlineMarkdown text={HUB_COPY.tableIntro} />
          </p>
        </div>
        <div className="compare-scroll" role="region" aria-labelledby="mixers-title" tabIndex={0}>
          {/* The roles keep it a table for screen readers when phones stack the rows (display: block; globals.css). */}
          <table className="compare-table guides-table" role="table">
            <caption className="sr-only">What each digital mixer can record, over USB and with no computer</caption>
            <thead role="rowgroup">
              <tr role="row">
                <th scope="col" role="columnheader">
                  Model
                </th>
                {COLUMNS.map(([, label]) => (
                  <th key={label} scope="col" role="columnheader">
                    {label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody role="rowgroup">
              {MIXER_ROWS.map((row) => (
                <tr key={row.name} role="row">
                  <th scope="row" role="rowheader">
                    {row.guide ? <a href={row.guide}>{row.name}</a> : row.name}
                    {row.note ? <span className="row-note">{row.note}</span> : null}
                    {row.guide ? (
                      <a className="row-note" href={row.guide}>
                        Read the {guideName(row.guide) ?? ""} guide
                      </a>
                    ) : null}
                  </th>
                  {COLUMNS.map(([key, label]) => (
                    <td key={key} role="cell" data-product={label}>
                      {row[key]}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <AskUs />
      </section>

      <section aria-labelledby="ways-title" className="feature-group doc">
        <div className="section-head">
          <h2 id="ways-title">{HUB_COPY.waysTitle}</h2>
        </div>
        <ul>
          {HUB_COPY.ways.map((w) => (
            <li key={w}>
              <InlineMarkdown text={w} />
            </li>
          ))}
        </ul>
        {HUB_COPY.waysAfter.map((p) => (
          <p key={p}>
            <InlineMarkdown text={p} />
          </p>
        ))}
      </section>

      <section aria-labelledby="sr-title" className="feature-group doc">
        <div className="section-head">
          <h2 id="sr-title">{HUB_COPY.fitsTitle}</h2>
        </div>
        <p>
          <InlineMarkdown text={HUB_COPY.fits} />
        </p>
        <GetTheApp campaign="site-guides" />
      </section>

      <section aria-labelledby="glossary" className="feature-group doc">
        <div className="section-head">
          <h2 id="glossary">{HUB_COPY.glossaryTitle}</h2>
        </div>
        <dl className="glossary">
          {GLOSSARY.map((g) => (
            <div key={g.term}>
              <dt>{g.term}</dt>
              <dd>{g.def}</dd>
            </div>
          ))}
        </dl>
      </section>
    </div>
    <MixerFaq faqs={HUB_FAQS} />
    </>
  );
}
