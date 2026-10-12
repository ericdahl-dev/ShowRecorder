import type { ReactNode } from "react";
import { AppIcon } from "@/components/AppIcon";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { Mark } from "@/components/Mark";
import { Screenshot } from "@/components/Screenshot";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { SHOTS } from "@/lib/screenshots";
import { CONTACT_EMAIL } from "@/lib/site";
import { softwareApplicationJsonLd } from "@/lib/structuredData";

export const metadata = pageMetadata(PAGES.home);

// Copy: scratchpad ia.md (#350), with the site-wide corrections: "iPhone and iPad", lowercase
// "mixer" in prose, "Coming soon to the App Store", Mac named once (in the FAQ).

// Only the iPhone images have a 1x/2x srcset; their frames are at most 240 px wide.
const FIGURE_SIZES = "240px";

const features: { title: string; body: ReactNode }[] = [
  {
    title: "One file per channel",
    body: "One 24-bit Broadcast WAV per USB Channel, at the mixer's 48 kHz or up to 96 kHz on interfaces that offer it. An 18-channel mixer gives you 18 Stems in step with each other.",
  },
  {
    title: "Named from your mixer",
    body: (
      <>
        On the mixer&apos;s Wi-Fi, ShowRecorder reads your channel names and colors, so channel 3 arrives as{" "}
        <span className="file">&ldquo;03 Snare.wav&rdquo;</span>, not <span className="file">&ldquo;USB 03&rdquo;</span>.
        Find Mixers locates the mixer on the network; there is no IP address to type.
      </>
    ),
  },
  {
    title: "A second copy as you record",
    body: "Add a USB drive and every Take is written to the Device and the Drive at once. If the Drive drops out, the missing part is filled back in from the other Copy after the Take.",
  },
  {
    title: "Nothing lost to a crash",
    body: "Files are saved every 2 seconds. If the app is closed mid-Take, it finishes that Take the next time it opens. A phone call or another app taking the audio leaves silence of the exact length, marked, so every file stays in sync with your video.",
  },
  {
    title: "Pre-roll and Markers",
    body: "A Take starts with the seconds before you pressed record, so the count-in isn't lost. Tap the flag to mark a song or a moment; Markers go into the files and your DAW project.",
  },
  {
    title: "Ready to mix",
    body: "Each Show gets a report (Takes, levels, any Gaps) and a Reaper project with every track and Marker in place.",
  },
  {
    title: "Templates for each venue",
    body: "Save a room's setup (channel names, mixer, Show name and Pre-roll) and start a Show from it in one tap.",
  },
  {
    title: "Built for the stage",
    body: "Big level meters with a target band, clip marks you can see across the room, a Sunlight appearance for bright stages and a Dark one for dark rooms. Works with VoiceOver.",
  },
];

const needs = [
  {
    title: "A compatible mixer",
    body: "A Behringer X Air XR18 or MR18 gives you 18 USB Channels with names and colors. Other class-compliant USB audio interfaces record too, without names.",
  },
  {
    title: "An iPhone or iPad",
    body: "A USB-C iPhone (iPhone 15 or later) or an iPad, on iOS 26 or iPadOS 26.",
  },
  {
    title: "A cable or a powered hub",
    body: "A USB-C cable connects your mixer. A powered USB-C hub lets the iPhone or iPad charge while the mixer and a USB drive are plugged in.",
  },
  {
    title: "Storage",
    body: "About 9.3 GB per hour for 18 channels at 48 kHz. The app shows the recording time left. A USB drive for a second Copy is optional; an SSD works best.",
  },
  {
    title: "Wi-Fi (optional)",
    body: "Join the mixer's network to get channel names and colors. No internet is needed.",
  },
];

const steps = [
  {
    title: "Plug in",
    body: "Connect your mixer's USB. ShowRecorder arms it and the meters come alive.",
  },
  {
    title: "Link the mixer",
    body: "Open Settings, then Mixer Link, then Find Mixers to get your channel names. Or start from a Template.",
  },
  {
    title: "Press record",
    body: "The Take starts with the Pre-roll from before your press. Tap the flag to add Markers as you go.",
  },
  {
    title: "Press stop",
    body: "Your Stems, the report and the Reaper project are in the Show's folder, in the Files app and on your Drive.",
  },
];

const plans = [
  {
    title: "Free",
    price: "$0",
    items: [
      "Records 2 USB Channels of your choice",
      "Names and colors from the mixer",
      "Pre-roll, Markers and a Drive Copy",
      "Every past Show stays open",
    ],
  },
  {
    title: "14-day Trial",
    price: "$0 for 14 days",
    items: [
      "Everything in Pro, at no cost",
      "Start it once, at first launch or in Settings",
      "When it ends, the app goes back to Free; a Take in progress is never stopped",
    ],
  },
  {
    title: "Pro",
    price: "$19.99, once",
    items: [
      "Every USB Channel",
      "Channel names you type, on the files",
      "The Show report and Reaper project",
      "96 kHz recording",
      "Templates for each venue",
      "Shared with Family Sharing, across your iPhone and iPad",
    ],
  },
];

const faqs = [
  {
    q: "How much space does a Show take?",
    a: "About 9.3 GB per hour for 18 channels at 48 kHz, on each place it is written to. Fewer channels take less: 2 channels take about 1 GB per hour. The record screen shows the time left on the Device and the Drive.",
  },
  {
    q: "Do I need an internet connection?",
    a: "No. Recording needs only the USB cable. Joining the mixer's Wi-Fi adds channel names and colors, and that is a local network, not the internet. Nothing is sent anywhere.",
  },
  {
    q: "Which mixers work?",
    a: "The Behringer X Air XR18 and MR18 record 18 USB Channels with names and colors. Other class-compliant USB audio interfaces record every channel they send, without names from the mixer; you can type names with Pro. Planned next: the Behringer X32 and Midas M32, then Pioneer DJM mixers. The list is under Supported mixers on the Features page.",
  },
  {
    q: "Where do the files go?",
    a: "Each Show has a folder for each Take, with one WAV file per channel, a report and a Reaper project. Open them from Shows in the app, in the Files app (On My iPhone or On My iPad, ShowRecorder), or on your Drive, and share them with AirDrop.",
  },
  {
    q: "What happens when the Trial ends?",
    a: "The app goes back to Free: new Takes record 2 USB Channels of your choice. A Take in progress is never stopped, and every Show you recorded stays open, with all its files. You can buy Pro at any time.",
  },
  {
    q: "Can my family use Pro?",
    a: "Yes. Pro is a one-time purchase, shared with Family Sharing and across your iPhone and iPad.",
  },
  {
    q: "Is there a Mac version?",
    a: "Not in 1.0, which is for iPhone and iPad. It follows right after.",
  },
  {
    q: "What if the Drive is unplugged during a Take?",
    a: "Recording carries on to the Device. When the Drive comes back it rejoins, and after the Take the missing part is filled in from the Device Copy.",
  },
];

function Section({
  id,
  title,
  intro,
  children,
  className = "",
}: {
  id: string;
  title: string;
  intro?: string;
  children: ReactNode;
  className?: string;
}) {
  const headingId = `${id}-title`;
  return (
    <section id={id} aria-labelledby={headingId} className={`section ${className}`.trim()}>
      <div className="wrap">
        <div className="section-head">
          <h2 id={headingId}>{title}</h2>
          {intro ? <p>{intro}</p> : null}
        </div>
        {children}
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        // "<" is escaped so the JSON can never close the script tag early.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApplicationJsonLd()).replace(/</g, "\\u003c") }}
      />
      <section id="top" aria-labelledby="hero-title" className="hero">
        <div className="wrap hero-grid">
          <div>
            <p className="eyebrow">
              <Mark />
              For iPhone and iPad
            </p>
            <h1 id="hero-title">Record every channel of your mixer on your iPhone or iPad.</h1>
            <p className="lede">
              Plug in a Behringer X Air XR18 or MR18, press record, and get one 24-bit WAV file per channel,
              named after what&apos;s on it and ready for your DAW. No recording laptop at the gig.
            </p>
            <div className="hero-actions">
              <AppStoreBadge id="app-store-link" />
              <p className="price">Free to download, 14-day Trial of everything.</p>
              <a className="see-need" href="#need">
                See what you need
              </a>
            </div>
          </div>
          <div className="devices">
            <Screenshot shot={SHOTS.heroIpad} sizes="(min-width: 1024px) 380px, 70vw" priority />
            <Screenshot shot={SHOTS.heroPhone} sizes="(min-width: 1024px) 240px, 45vw" priority />
          </div>
        </div>
      </section>

      <Section
        id="features"
        title="Every channel, its own file"
        intro="ShowRecorder turns the USB audio from your mixer into one file per channel, written as you play, with nothing to set up on a laptop."
      >
        <ul className="cards cards--4">
          {features.map((f) => (
            <li key={f.title} className="card">
              <h3>{f.title}</h3>
              <p>{f.body}</p>
            </li>
          ))}
        </ul>
        <div className="figures">
          <figure className="shot">
            <Screenshot shot={SHOTS.markers} sizes={FIGURE_SIZES} />
            <figcaption>Markers as you record, with the time of each one.</figcaption>
          </figure>
          <figure className="shot">
            <Screenshot shot={SHOTS.show} sizes={FIGURE_SIZES} />
            <figcaption>Every Take in a Show, with its Markers and its 18 Stems.</figcaption>
          </figure>
          <figure className="shot">
            <Screenshot shot={SHOTS.sunlight} sizes={FIGURE_SIZES} />
            <figcaption>The Sunlight appearance for bright stages.</figcaption>
          </figure>
        </div>
        <p className="more-link">
          <a href="/features">See every feature</a>
        </p>
      </Section>

      <Section
        id="need"
        title="What you need"
        intro="A compatible mixer, an iPhone or iPad, and a cable. A USB drive is optional."
      >
        <div className="need-grid">
          <ul className="need-list">
            {needs.map((n) => (
              <li key={n.title}>
                <h3>{n.title}</h3>
                <p>{n.body}</p>
              </li>
            ))}
          </ul>
          <figure className="shot">
            <Screenshot shot={SHOTS.mixerLink} sizes={FIGURE_SIZES} />
            <figcaption>Settings: the Drive, the Mixer Link and Find Mixers.</figcaption>
          </figure>
        </div>
      </Section>

      <Section id="how" title="How a show goes">
        <ol className="steps">
          {steps.map((s) => (
            <li key={s.title}>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </li>
          ))}
        </ol>
      </Section>

      <section id="promise" aria-labelledby="promise-title" className="promise">
        <div className="wrap">
          <div className="inner">
            <span className="rec-dot" aria-hidden="true" />
            <h2 id="promise-title">The Show-Safe Promise</h2>
            <p className="vow">
              A Take never stops, and your audio is never held back, because of a Trial, a limit or a license.
              Limits are checked only when you press record. Your past Shows are never locked.
            </p>
            <p className="after">
              A recording stops when you stop it, or if every place it is writing to runs out of space. Nothing
              else ends a Take.
            </p>
          </div>
        </div>
      </section>

      <Section
        id="pricing"
        title="Free, Trial and Pro"
        intro="ShowRecorder is free to download. Try everything for 14 days, then keep Free or buy Pro once."
      >
        <div className="pricing-grid">
          <div>
            <ul className="plans">
              {plans.map((p) => (
                <li key={p.title} className={p.title === "Pro" ? "plan plan--pro" : "plan"}>
                  <h3>{p.title}</h3>
                  <p className="price">{p.price}</p>
                  <ul>
                    {p.items.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </li>
              ))}
            </ul>
            <p className="once">One-time purchase. No subscription.</p>
          </div>
          <figure className="shot">
            <Screenshot shot={SHOTS.pro} sizes={FIGURE_SIZES} />
            <figcaption>The Pro screen in the app.</figcaption>
          </figure>
        </div>
      </Section>

      <Section id="faq" title="Questions">
        <div className="faq">
          {faqs.map((f) => (
            <details key={f.q}>
              <summary>
                <h3>{f.q}</h3>
                <span className="sign" aria-hidden="true" />
              </summary>
              <p>{f.a}</p>
            </details>
          ))}
        </div>
        <p className="more-link">
          More answers, step by step, are in the <a href="/docs">docs</a>.
        </p>
      </Section>

      <section id="get" aria-labelledby="get-title" className="section closing">
        <div className="wrap">
          <div className="inner">
            <AppIcon size={96} />
            <h2 id="get-title">Record your next Show</h2>
            <p>
              ShowRecorder is coming soon to the App Store for iPhone and iPad. Until then, the public beta is
              open on TestFlight. Free to download, with a 14-day Trial of everything.
            </p>
            <AppStoreBadge id="app-store-link-footer" />
            <p className="ask">
              Questions before then? Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
            </p>
          </div>
        </div>
      </section>
    </>
  );
}
