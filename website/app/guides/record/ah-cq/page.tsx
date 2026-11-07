import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { AH_CQ_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideAhCq);

// The Allen & Heath CQ recording guide (#1070): the shared guide data, the body (content.mdx), then the questions,
// which the FAQPage data repeats.
export default function AhCqGuidePage() {
  return (
    <>
      <GuideJsonLd slug="ah-cq" />
      <Content />
      <MixerFaq faqs={AH_CQ_GUIDE_FAQS} />
    </>
  );
}
