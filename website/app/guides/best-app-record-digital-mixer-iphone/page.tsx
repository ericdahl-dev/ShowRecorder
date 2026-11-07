import { MixerFaq } from "@/components/MixerFaq";
import { APP_ROWS, BEST_APP_FAQS, BEST_APP_GUIDE, bestAppTrail } from "@/lib/bestApp";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { PAGE_DATES } from "@/lib/pageDates";
import { breadcrumbListJsonLd, faqPageJsonLd, jsonLdScript, techArticleJsonLd } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideBestApp);

const PUBLISHED = "2026-11-07";

// The best-app comparison (#1085): the body (content.mdx, with the table from lib/bestApp.ts), then the questions,
// which the FAQPage data repeats. The article cites every page a row's facts come from.
export default function BestAppGuidePage() {
  const citations = APP_ROWS.flatMap((r) => (r.extraSource ? [r.source, r.extraSource] : [r.source]));
  const data = [
    breadcrumbListJsonLd(bestAppTrail),
    techArticleJsonLd({
      page: PAGES.guideBestApp,
      headline: "The best app to multitrack record a digital mixer on iPhone and iPad",
      datePublished: PUBLISHED,
      dateModified: PAGE_DATES[BEST_APP_GUIDE] ?? PUBLISHED,
      citations,
    }),
    faqPageJsonLd(BEST_APP_FAQS),
  ];
  return (
    <>
      {data.map((d, i) => (
        <script key={i} type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(d) }} />
      ))}
      <Content />
      <MixerFaq faqs={BEST_APP_FAQS} />
    </>
  );
}
