import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { STUDIOLIVE_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideStudioLive);

// The PreSonus StudioLive Series III recording guide (#1077): the shared guide data, the body (content.mdx), then the
// questions, which the FAQPage data repeats.
export default function StudioLiveGuidePage() {
  return (
    <>
      <GuideJsonLd slug="presonus-studiolive-iii" />
      <Content />
      <MixerFaq faqs={STUDIOLIVE_GUIDE_FAQS} />
    </>
  );
}
