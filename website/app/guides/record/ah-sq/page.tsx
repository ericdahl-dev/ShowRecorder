import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { AH_SQ_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideAhSq);

// The Allen & Heath SQ recording guide (#1068): the shared guide data, the body (content.mdx), then the questions,
// which the FAQPage data repeats.
export default function AhSqGuidePage() {
  return (
    <>
      <GuideJsonLd slug="ah-sq" />
      <Content />
      <MixerFaq faqs={AH_SQ_GUIDE_FAQS} />
    </>
  );
}
