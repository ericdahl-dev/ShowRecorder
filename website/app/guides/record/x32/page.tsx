import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { X32_GUIDE_FAQS, X32_METHOD_A } from "@/lib/mixerGuides";
import { howToJsonLd, jsonLdScript } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideX32);

// The X32 recording guide (#1063): the shared guide data, Method A's steps as HowTo data (the page lists the same
// steps), the body (content.mdx), then the questions.
export default function X32GuidePage() {
  return (
    <>
      <GuideJsonLd slug="x32" />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonLdScript(howToJsonLd(PAGES.guideX32, X32_METHOD_A, "Send X32 inputs to the USB card in blocks of 8")),
        }}
      />
      <Content />
      <MixerFaq faqs={X32_GUIDE_FAQS} />
    </>
  );
}
