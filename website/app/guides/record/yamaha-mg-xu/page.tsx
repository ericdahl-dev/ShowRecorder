import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { YAMAHA_MGXU_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideYamahaMgxu);

// The Yamaha MG XU recording guide (#1076): the shared guide data, the body (content.mdx), then the questions, which
// the FAQPage data repeats. The MG XU sends only a stereo mix, so the guide says so and points to the MGX guide.
export default function YamahaMgxuGuidePage() {
  return (
    <>
      <GuideJsonLd slug="yamaha-mg-xu" />
      <Content />
      <MixerFaq faqs={YAMAHA_MGXU_GUIDE_FAQS} />
    </>
  );
}
