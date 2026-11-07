import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { XR18_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideXR18);

// The XR18 and MR18 recording guide (#1064): the shared guide data, the body (content.mdx), then the questions, which
// the FAQPage data repeats.
export default function XR18GuidePage() {
  return (
    <>
      <GuideJsonLd slug="xr18" />
      <Content />
      <MixerFaq faqs={XR18_GUIDE_FAQS} />
    </>
  );
}
