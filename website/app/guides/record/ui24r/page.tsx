import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { UI24R_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideUi24r);

// The Soundcraft Ui24R recording guide (#1072): the shared guide data, the body (content.mdx), then the questions,
// which the FAQPage data repeats.
export default function Ui24rGuidePage() {
  return (
    <>
      <GuideJsonLd slug="ui24r" />
      <Content />
      <MixerFaq faqs={UI24R_GUIDE_FAQS} />
    </>
  );
}
