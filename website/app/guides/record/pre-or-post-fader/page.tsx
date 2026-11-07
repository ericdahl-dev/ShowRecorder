import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { PAGE_DATES } from "@/lib/pageDates";
import { RESEARCH_URL, TAP_POINT_FAQS, TAP_POINT_GUIDE, guideTrail } from "@/lib/mixerGuides";
import { breadcrumbListJsonLd, faqPageJsonLd, jsonLdScript, techArticleJsonLd } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideTapPoints);

// The shared tap-point guide (#1062): the body (content.mdx), then the questions, which the FAQPage data repeats.
export default function TapPointGuidePage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbListJsonLd(guideTrail("Pre or post fader", TAP_POINT_GUIDE))) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonLdScript(
            techArticleJsonLd({
              page: PAGES.guideTapPoints,
              headline: "Pre or post fader: which tap point to record",
              datePublished: "2026-11-06",
              dateModified: PAGE_DATES[TAP_POINT_GUIDE] ?? "2026-11-06",
              citations: [RESEARCH_URL],
            }),
          ),
        }}
      />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(TAP_POINT_FAQS)) }} />
      <Content />
      <MixerFaq faqs={TAP_POINT_FAQS} />
    </>
  );
}
