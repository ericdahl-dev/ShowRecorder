import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { YAMAHA_MGX_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideYamahaMgx);

// The Yamaha MGX recording guide (#1076): the shared guide data, the body (content.mdx), then the questions, which the
// FAQPage data repeats. The older MG XU has its own short guide (/guides/record/yamaha-mg-xu).
export default function YamahaMgxGuidePage() {
  return (
    <>
      <GuideJsonLd slug="yamaha-mgx" />
      <Content />
      <MixerFaq faqs={YAMAHA_MGX_GUIDE_FAQS} />
    </>
  );
}
