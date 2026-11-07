import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { TAP_POINT_FAQS } from "@/lib/mixerGuides";
import { breadcrumbJsonLd, faqPageJsonLd, jsonLdScript } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideTapPoints);

// The shared tap-point guide (#1062): the body (content.mdx), then the questions, which the FAQPage data repeats.
export default function TapPointGuidePage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbJsonLd("Pre or post fader", PAGES.guideTapPoints.path)) }}
      />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(TAP_POINT_FAQS)) }} />
      <Content />
      <MixerFaq faqs={TAP_POINT_FAQS} />
    </>
  );
}
