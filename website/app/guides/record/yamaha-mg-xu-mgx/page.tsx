import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { YAMAHA_MG_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideYamahaMG);

// The Yamaha MG XU and MGX recording guide (#1076): the shared guide data, the body (content.mdx), then the questions,
// which the FAQPage data repeats. The MG XU sends only a stereo mix over USB; the MGX sends each channel.
export default function YamahaMgGuidePage() {
  return (
    <>
      <GuideJsonLd slug="yamaha-mg-xu-mgx" />
      <Content />
      <MixerFaq faqs={YAMAHA_MG_GUIDE_FAQS} />
    </>
  );
}
