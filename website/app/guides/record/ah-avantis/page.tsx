import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { AH_AVANTIS_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideAhAvantis);

// The Allen & Heath Avantis recording guide (#1071): the shared guide data, the body (content.mdx), then the
// questions, which the FAQPage data repeats.
export default function AhAvantisGuidePage() {
  return (
    <>
      <GuideJsonLd slug="ah-avantis" />
      <Content />
      <MixerFaq faqs={AH_AVANTIS_GUIDE_FAQS} />
    </>
  );
}
