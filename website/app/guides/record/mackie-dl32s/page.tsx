import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { MACKIE_DL32S_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideMackieDL32S);

// The Mackie DL32S and DL16S recording guide (#1078): the shared guide data, the body (content.mdx), then the
// questions, which the FAQPage data repeats.
export default function MackieDL32SGuidePage() {
  return (
    <>
      <GuideJsonLd slug="mackie-dl32s" />
      <Content />
      <MixerFaq faqs={MACKIE_DL32S_GUIDE_FAQS} />
    </>
  );
}
