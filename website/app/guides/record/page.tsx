import { PAGES, pageMetadata } from "@/lib/metadata";
import { MIXER_ROWS } from "@/lib/mixerGuides";
import { breadcrumbJsonLd, jsonLdScript } from "@/lib/structuredData";

export const metadata = pageMetadata(PAGES.guidesHub);

// The hub of the mixer recording guides (#1061). Facts: lib/mixerGuides.ts, from docs/research/mixer-recording/.
// The guides cover every way to record a mixer, not only ShowRecorder; ShowRecorder lines stay short and true.
const COLUMNS = ["Over USB", "With no computer", "Mac, iPad and iPhone"] as const;

export default function GuidesHubPage() {
  return (
    <div className="wrap features-page compare-page guides-hub">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbJsonLd("Recording guides", PAGES.guidesHub.path)) }}
      />
      <header className="features-head">
        <h1>How to multitrack record a digital mixer</h1>
        <p className="lede">
          Most digital mixers can record every channel to its own track. How they do it differs a lot: over USB to a
          computer, to a card or stick in the mixer, or to an iPad or iPhone. This page lists what each mixer can do, and
          each guide shows the settings and routing step by step.
        </p>
        <p className="features-links">
          Facts come from the makers&apos; own manuals and spec pages where we could find them. Where only a forum or a
          retailer says it, we say so. Where nobody says, we write &quot;not stated&quot; or &quot;unknown&quot; instead
          of guessing. Researched November 2026; check your mixer&apos;s manual and firmware before a show.
        </p>
      </header>

      <section aria-labelledby="mixers-title" className="feature-group">
        <div className="section-head">
          <h2 id="mixers-title">What each mixer can record</h2>
          <p>
            &quot;Over USB&quot; is what the mixer sends to a computer, iPad or iPhone. &quot;With no computer&quot; is
            what it records by itself.
          </p>
        </div>
        <div className="compare-scroll" role="region" aria-labelledby="mixers-title" tabIndex={0}>
          <table className="compare-table guides-table" role="table">
            <caption className="sr-only">What each digital mixer can record, over USB and with no computer</caption>
            <thead role="rowgroup">
              <tr role="row">
                <th scope="col" role="columnheader">
                  Model
                </th>
                {COLUMNS.map((c) => (
                  <th key={c} scope="col" role="columnheader">
                    {c}
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
                        Read the guide
                      </a>
                    ) : null}
                  </th>
                  <td role="cell" data-product={COLUMNS[0]}>
                    {row.usb}
                  </td>
                  <td role="cell" data-product={COLUMNS[1]}>
                    {row.onboard}
                  </td>
                  <td role="cell" data-product={COLUMNS[2]}>
                    {row.apple}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
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
            iPad or iPhone over a USB cable. Few makers name the iPhone, so the table says &quot;not tested yet&quot;
            where nobody has checked.
          </li>
        </ul>
        <p>
          The mixer powers nothing on the phone or tablet through its USB audio port. For a long show, use a powered
          USB-C hub, or a camera adapter that passes power through, so the iPhone or iPad charges while it records.
        </p>
      </section>

      <section aria-labelledby="sr-title" className="feature-group doc">
        <div className="section-head">
          <h2 id="sr-title">Where ShowRecorder fits</h2>
        </div>
        <p>
          ShowRecorder records every USB Channel from any class-compliant mixer, one WAV file per channel, on a USB-C
          iPhone or iPad. Names and colors from the mixer (Mixer Link) work only with the{" "}
          <a href="/mixers/xr18">XR18 and MR18</a> and the <a href="/mixers/x32">X32 and M32</a>. The X32 and M32
          have been tested only against an emulator so far.
        </p>
      </section>
    </div>
  );
}
