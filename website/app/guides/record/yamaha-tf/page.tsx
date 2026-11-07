import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { YAMAHA_TF_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideYamahaTf);

// The Yamaha TF recording guide (#1074): the shared guide data, the body (content.mdx), then the questions,
// which the FAQPage data repeats.
export default function YamahaTfGuidePage() {
  return (
    <>
      <GuideJsonLd slug="yamaha-tf" />
      <Content />
      <MixerFaq faqs={YAMAHA_TF_GUIDE_FAQS} />
    </>
  );
}
