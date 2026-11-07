import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { X32_GUIDE_FAQS } from "@/lib/mixerGuides";
import { breadcrumbJsonLd, faqPageJsonLd, jsonLdScript } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideX32);

// The X32 recording guide (#1063): the body (content.mdx), then the questions, which the FAQPage data repeats.
export default function X32GuidePage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbJsonLd("X32 recording guide", PAGES.guideX32.path)) }}
      />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(X32_GUIDE_FAQS)) }} />
      <Content />
      <MixerFaq faqs={X32_GUIDE_FAQS} />
    </>
  );
}
