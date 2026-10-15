import { GetBand } from "@/components/GetBand";
import { MixerFaq } from "@/components/MixerFaq";
import { MixerHero } from "@/components/MixerHero";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { X32_FAQS } from "@/lib/mixerFaqs";
import { breadcrumbJsonLd, faqPageJsonLd, jsonLdScript, mixerApplicationJsonLd } from "@/lib/structuredData";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.mixersX32);

// A mixer landing page (#482): the hero with the call to action, the body (content.mdx), and the shared closing band.
export default function X32Page() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(mixerApplicationJsonLd(PAGES.mixersX32)) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(breadcrumbJsonLd("X32 and M32", PAGES.mixersX32.path)) }}
      />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(X32_FAQS)) }} />
      <MixerHero
        eyebrow="Behringer X32 and Midas M32"
        title="X32 and M32 multitrack recording on iPhone and iPad (beta)"
        lede="Every USB Channel of the mixer straight to your iPhone or iPad: one WAV file per channel, named after the channel on the mixer. No laptop at front of house."
        beta
      />
      <Content />
      <MixerFaq faqs={X32_FAQS} />
      <GetBand title="Record your X32 or M32" beta>
        X32 and M32 recording is in the public beta now, and comes to the App Store in a later update.
      </GetBand>
    </>
  );
}
