import { GetBand } from "@/components/GetBand";
import { MixerHero } from "@/components/MixerHero";
import { PAGES, pageMetadata } from "@/lib/metadata";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.mixersXR18);

// A mixer landing page (#482): the hero with the call to action, the body (content.mdx), and the shared closing band.
export default function XR18Page() {
  return (
    <>
      <MixerHero
        eyebrow="Behringer XR18 and Midas MR18"
        title="XR18 and MR18 multitrack recording on iPhone and iPad"
        lede="All 18 USB Channels straight to your iPhone or iPad: one WAV file per channel, named after the channel on the mixer. No laptop at the show."
        price="Free to download, 14-day Trial of everything."
      />
      <Content />
      <GetBand title="Record your XR18 or MR18" />
    </>
  );
}
