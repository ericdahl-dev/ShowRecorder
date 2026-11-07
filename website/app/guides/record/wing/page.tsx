import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { WING_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideWing);

// The Behringer WING, WING Compact and WING Rack recording guide (#1066): the shared guide data, the body
// (content.mdx), then the questions, which the FAQPage data repeats.
export default function WingGuidePage() {
  return (
    <>
      <GuideJsonLd slug="wing" />
      <Content />
      <MixerFaq faqs={WING_GUIDE_FAQS} />
    </>
  );
}
