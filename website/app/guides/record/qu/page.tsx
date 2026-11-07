import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { QU_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideQu);

// The Allen & Heath Qu recording guide (#1069): the new Qu and Qu Classic on one page. The shared guide data, the body
// (content.mdx), then the questions, which the FAQPage data repeats.
export default function QuGuidePage() {
  return (
    <>
      <GuideJsonLd slug="qu" />
      <Content />
      <MixerFaq faqs={QU_GUIDE_FAQS} />
    </>
  );
}
