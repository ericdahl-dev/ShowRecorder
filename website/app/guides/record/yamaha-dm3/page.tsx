import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { YAMAHA_DM3_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideYamahaDm3);

// The Yamaha DM3 recording guide (#1075): the shared guide data, the body (content.mdx), then the questions,
// which the FAQPage data repeats.
export default function YamahaDm3GuidePage() {
  return (
    <>
      <GuideJsonLd slug="yamaha-dm3" />
      <Content />
      <MixerFaq faqs={YAMAHA_DM3_GUIDE_FAQS} />
    </>
  );
}
