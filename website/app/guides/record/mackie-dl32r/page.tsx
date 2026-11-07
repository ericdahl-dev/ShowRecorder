import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { DL32R_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideMackieDL32R);

// The Mackie DL32R recording guide (#1079): the shared guide data, the body (content.mdx), then the questions, which
// the FAQPage data repeats.
export default function MackieDL32RGuidePage() {
  return (
    <>
      <GuideJsonLd slug="mackie-dl32r" />
      <Content />
      <MixerFaq faqs={DL32R_GUIDE_FAQS} />
    </>
  );
}
