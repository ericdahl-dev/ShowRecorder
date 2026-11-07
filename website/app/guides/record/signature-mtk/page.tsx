import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { SIGNATURE_MTK_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideSignatureMtk);

// The Soundcraft Signature MTK recording guide (#1073): the shared guide data, the body (content.mdx), then the
// questions, which the FAQPage data repeats.
export default function SignatureMtkGuidePage() {
  return (
    <>
      <GuideJsonLd slug="signature-mtk" />
      <Content />
      <MixerFaq faqs={SIGNATURE_MTK_GUIDE_FAQS} />
    </>
  );
}
