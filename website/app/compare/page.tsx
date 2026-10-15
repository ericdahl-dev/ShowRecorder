import { GetBand } from "@/components/GetBand";
import { AS_OF, COMPARE_FAQS, PRODUCTS, ROWS } from "@/lib/compare";
import { pageMetadata } from "@/lib/metadata";
import { faqPageJsonLd, jsonLdScript } from "@/lib/structuredData";

export const metadata = pageMetadata({
  path: "/compare",
  title: "ShowRecorder compared with Manytrack, Reaper, X-Live and Auria - ShowRecorder",
  description: "How ShowRecorder compares with Manytrack Recorder, a laptop with Reaper or Mixbus, X-Live and Auria, and when to pick each of the others.",
});

// A fair, dated comparison (#704). Content: lib/compare.ts, which records where each claim comes from.
export default function ComparePage() {
  const others = PRODUCTS.filter((p) => p.id !== "showrecorder");
  return (
    <div className="wrap features-page compare-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(COMPARE_FAQS)) }} />
      <header className="features-head">
        <h1>ShowRecorder compared with the other ways to record a mixer</h1>
        <p className="lede">
          Four other ways to get every channel of a mixer onto a recording, side by side with ShowRecorder, as of{" "}
          {AS_OF}. Each one has a line on when it is the better pick.
        </p>
        <p className="features-links">
          A row that says a listing does not mention something means we could not find it on the page we read, not
          that the product lacks it. Check the maker&apos;s page before you buy.
        </p>
      </header>

      <section aria-labelledby="table-title" className="feature-group">
        <div className="section-head">
          <h2 id="table-title">Side by side, as of {AS_OF}</h2>
        </div>
        <div className="compare-scroll" role="region" aria-labelledby="table-title" tabIndex={0}>
          <table className="compare-table">
            <thead>
              <tr>
                <td />
                {PRODUCTS.map((p) => (
                  <th key={p.id} scope="col">
                    {p.name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {ROWS.map((row) => (
                <tr key={row.label}>
                  <th scope="row">{row.label}</th>
                  {PRODUCTS.map((p) => (
                    <td key={p.id}>{row.cells[p.id]}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section aria-labelledby="pick-title" className="feature-group">
        <div className="section-head">
          <h2 id="pick-title">When to pick the other one</h2>
          <p>These are good tools. Here is when each of them suits you better than ShowRecorder does.</p>
        </div>
        <ul className="cards cards--3">
          {others.map((p) => (
            <li key={p.id} className="card">
              <h3>{p.name}</h3>
              <p>{p.pickIt}</p>
            </li>
          ))}
        </ul>
        <p className="more-link">{PRODUCTS[0].pickIt}</p>
      </section>

      <section id="faq" aria-labelledby="faq-title" className="feature-group">
        <div className="section-head">
          <h2 id="faq-title">Questions</h2>
        </div>
        <div className="faq">
          {COMPARE_FAQS.map((f) => (
            <details key={f.q}>
              <summary>
                <h3>{f.q}</h3>
                <span className="sign" aria-hidden="true" />
              </summary>
              <p>{f.a}</p>
            </details>
          ))}
        </div>
      </section>

      <GetBand title="Try ShowRecorder" />
    </div>
  );
}
