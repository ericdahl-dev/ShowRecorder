import { GetBand } from "@/components/GetBand";
import { MixerFaq } from "@/components/MixerFaq";
import { MixerHero } from "@/components/MixerHero";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { XR18_FAQS } from "@/lib/mixerFaqs";
import { breadcrumbJsonLd, faqPageJsonLd, jsonLdScript, mixerApplicationJsonLd } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.mixersXR18);

// A mixer landing page (#482): the hero with the call to action, the body (content.mdx), and the shared closing band.
export default function XR18Page() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(mixerApplicationJsonLd(PAGES.mixersXR18)) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbJsonLd("XR18 and MR18", PAGES.mixersXR18.path)) }}
      />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(XR18_FAQS)) }} />
      <MixerHero
        eyebrow="Behringer XR18 and Midas MR18"
        title="XR18 and MR18 multitrack recording on iPhone and iPad"
        lede="All 18 USB Channels straight to your iPhone or iPad: one WAV file per channel, named after the channel on the mixer. No laptop at the show."
      />
      <Content />
      <MixerFaq faqs={XR18_FAQS} />
      <GetBand title="Record your XR18 or MR18" />
    </>
  );
}
