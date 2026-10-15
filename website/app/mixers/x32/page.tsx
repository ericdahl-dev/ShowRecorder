import { GetBand } from "@/components/GetBand";
import { MixerHero } from "@/components/MixerHero";
import { PAGES, pageMetadata } from "@/lib/metadata";
import Content from "./content.mdx";

export const metadata = pageMetadata(PAGES.mixersX32);

// A mixer landing page (#482): the hero with the call to action, the body (content.mdx), and the shared closing band.
export default function X32Page() {
  return (
    <>
      <MixerHero
        eyebrow="Behringer X32 and Midas M32"
        title="X32 and M32 multitrack recording on iPhone and iPad (beta)"
        lede="Every USB Channel of the mixer straight to your iPhone or iPad: one WAV file per channel, named after the channel on the mixer. No laptop at front of house."
        price="Public beta. Free to download, 14-day Trial of everything."
        beta
      />
      <Content />
      <GetBand title="Record your X32 or M32" beta>
        X32 and M32 recording is in the public beta now, and comes to the App Store in a later update. Free to download,
        with a 14-day Trial of everything.
      </GetBand>
    </>
  );
}
