import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { XR18_GUIDE_FAQS } from "@/lib/mixerGuides";
import { breadcrumbJsonLd, faqPageJsonLd, jsonLdScript } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideXR18);

// The XR18 and MR18 recording guide (#1064): the body (content.mdx), then the questions, which the FAQPage data repeats.
export default function XR18GuidePage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbJsonLd("XR18 and MR18 recording guide", PAGES.guideXR18.path)) }}
      />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(XR18_GUIDE_FAQS)) }} />
      <Content />
      <MixerFaq faqs={XR18_GUIDE_FAQS} />
    </>
  );
}
