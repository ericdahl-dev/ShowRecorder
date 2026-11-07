import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { M32_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideM32);

// The Midas M32 recording guide (#1065): the shared guide data, the body (content.mdx), then the questions, which the
// FAQPage data repeats. It follows the X32 guide and calls out the differences: the DN32 cards and the M32 LIVE.
export default function M32GuidePage() {
  return (
    <>
      <GuideJsonLd slug="m32" />
      <Content />
      <MixerFaq faqs={M32_GUIDE_FAQS} />
    </>
  );
}
