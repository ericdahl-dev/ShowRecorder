import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { ZOOM_L12_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideZoomL12);

// The Zoom LiveTrak L-12 and L-20 recording guide (#1080): the shared guide data, the body (content.mdx), then the
// questions, which the FAQPage data repeats.
export default function ZoomL12GuidePage() {
  return (
    <>
      <GuideJsonLd slug="zoom-l12" />
      <Content />
      <MixerFaq faqs={ZOOM_L12_GUIDE_FAQS} />
    </>
  );
}
