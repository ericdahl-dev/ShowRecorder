import Image from "next/image";
import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/site";

// Placeholder home page. The real page is designed from the brand brief and IA doc (#350).
export default function Home() {
  return (
    <section className="mx-auto flex max-w-5xl flex-col items-center gap-10 px-4 py-16 text-center">
      <div className="flex flex-col items-center gap-4">
        <h1 className="text-4xl font-bold tracking-tight">{SITE_NAME}</h1>
        <p className="max-w-xl text-lg text-[var(--muted)]">{SITE_DESCRIPTION}</p>
      </div>
      <Image
        src="/images/iphone-01-recording.jpg"
        alt="ShowRecorder recording 18 USB Channels from an XR18, each meter named from the Mixer"
        width={600}
        height={1303}
        sizes="(max-width: 640px) 80vw, 300px"
        className="h-auto w-[300px] max-w-[80vw] rounded-3xl shadow-lg"
        priority
      />
    </section>
  );
}
