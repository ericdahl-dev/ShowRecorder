import { AskUs, Breadcrumbs, GetTheApp, LastChecked } from "@/components/GuideParts";
import { MixerFaq } from "@/components/MixerFaq";
import { BEST_APP_GUIDE } from "@/lib/bestApp";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { GLOSSARY, HUB_FAQS, MIXER_GUIDES, MIXER_ROWS, RESEARCH_URL } from "@/lib/mixerGuides";
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
        <h1>How to multitrack record a digital mixer</h1>
        <LastChecked path={PAGES.guidesHub.path} />
        <p className="lede">
          Most digital mixers can record every channel to its own track. How they do it differs a lot: over USB to a
          computer, to a card or stick in the mixer, or to an iPad or iPhone. This page lists what each mixer can do, and
          each guide shows the settings and routing step by step.
        </p>
        <p className="features-links">
          Facts come from the makers&apos; own manuals and spec pages where we could find them. Where only a forum or a
          retailer says it, we say so. Where nobody says, we write &quot;not stated&quot; or &quot;unknown&quot; instead
          of guessing. Researched November 2026; check your mixer&apos;s manual and firmware before a show.{" "}
          <a href={RESEARCH_URL}>Sources and method</a>.
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
          <h2 id="mixers-title">What each mixer can record</h2>
          <p>
            &quot;Over USB&quot; is what the mixer sends to a computer, iPad or iPhone. &quot;With no computer&quot; is
            what it records by itself. Words like card out and class compliant are in the{" "}
            <a href="#glossary">glossary</a>.
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
          <h2 id="ways-title">Three ways to record every channel</h2>
        </div>
        <ul>
          <li>
            <strong>To a computer over USB.</strong> The mixer acts as a USB audio interface, and a DAW records each
            channel to its own track. On a Mac, most of the mixers above need no driver.
          </li>
          <li>
            <strong>To a card or stick in the mixer.</strong> Some mixers, or an option card in them, record many tracks
            to an SD card or a USB drive with no computer at all. Many others record only a stereo mix this way.
          </li>
          <li>
            <strong>To an iPad, iPhone or Mac with an app.</strong> A class-compliant mixer can send its channels to an
            iPad or iPhone over a USB cable. Some makers say their class-compliant mixers work with an iPad or iPhone;
            the table shows which, and says &quot;not tested yet&quot; where nobody has checked.
          </li>
        </ul>
        <p>
          Whichever way you record, you also choose where in each channel the recording is taken: before or after the
          gain, the EQ and the fader. <a href="/guides/record/pre-or-post-fader">Pre or post fader</a> explains each tap
          point, with pros and cons.
        </p>
        <p>
          The mixer powers nothing on the phone or tablet through its USB audio port. For a long show, use a powered
          USB-C hub, or a camera adapter that passes power through, so the iPhone or iPad charges while it records.
        </p>
        <p>
          To record a gig on an iPhone or iPad with no laptop, see{" "}
          <a href="/guides/record-gig-without-laptop">Record a gig without a laptop</a>. To choose the app,{" "}
          <a href={BEST_APP_GUIDE}>the best app to multitrack record a digital mixer on iPhone and iPad</a> compares
          nine of them.
        </p>
      </section>

      <section aria-labelledby="sr-title" className="feature-group doc">
        <div className="section-head">
          <h2 id="sr-title">Where ShowRecorder fits</h2>
        </div>
        <p>
          ShowRecorder records every USB Channel from any class-compliant mixer, one WAV file per channel, on a USB-C
          iPhone or iPad. Names and colors from the mixer (Mixer Link) work only with the{" "}
          <a href="/mixers/xr18">XR18 and MR18</a> and the <a href="/mixers/x32">X32 and M32</a>. Its X32 and M32
          support has run only against an X32 emulator so far.
        </p>
        <GetTheApp campaign="site-guides" />
      </section>

      <section aria-labelledby="glossary" className="feature-group doc">
        <div className="section-head">
          <h2 id="glossary">Glossary</h2>
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
