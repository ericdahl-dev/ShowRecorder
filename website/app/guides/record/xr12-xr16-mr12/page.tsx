import { GuideJsonLd } from "@/components/GuideJsonLd";
import { MixerFaq } from "@/components/MixerFaq";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { XR12_GUIDE_FAQS } from "@/lib/mixerGuides";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.guideXR12);

// The Behringer XR12 / XR16 and Midas MR12 recording guide (#1067): the shared guide data, the body (content.mdx), then
// the questions, which the FAQPage data repeats. These mixers have no USB audio, so the guide says so and points to the
// XR18/MR18 guide.
export default function Xr12GuidePage() {
  return (
    <>
      <GuideJsonLd slug="xr12-xr16-mr12" />
      <Content />
      <MixerFaq faqs={XR12_GUIDE_FAQS} />
    </>
  );
}
