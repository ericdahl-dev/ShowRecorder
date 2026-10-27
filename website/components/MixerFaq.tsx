import type { Faq } from "@/lib/mixerFaqs";

// The questions at the end of a mixer page (#704). The page's FAQPage JSON-LD (lib/structuredData.ts) is built
// from the same list, so the structured data matches what is shown.
export function MixerFaq({ faqs }: { faqs: readonly Faq[] }) {
  return (
    <div className="wrap">
      <section aria-labelledby="mixer-faq-title" className="doc mixer-faq">
        <h2 id="mixer-faq-title">Frequently asked questions</h2>
        <div className="faq">
          {faqs.map((f) => (
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
    </div>
  );
}
