import type { ReactNode } from "react";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { GetBand } from "@/components/GetBand";
import { Screenshot } from "@/components/Screenshot";
import { SignupForm } from "@/components/SignupForm";
import { PAGES, pageMetadata } from "@/lib/metadata";
import { SHOTS } from "@/lib/screenshots";
import { ctaNote } from "@/lib/site";
import "./home.css";
import { faqPageJsonLd, jsonLdScript, softwareApplicationJsonLd } from "@/lib/structuredData";

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
    title: "A class-compliant USB mixer",
    body: "Any class-compliant USB mixer or audio interface records every channel it sends. With a Behringer X Air XR18 or MR18, Mixer Link adds names and colors; without it, you type names with Pro.",
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
    body: "Your Stems are in the Show's folder in the Files app. With Pro, the report, the Reaper project and a copy on your Drive are there too.",
  },
];

const plans = [
  {
    title: "Free",
    price: "$0",
    items: [
      "Records every USB Channel, on your iPhone or iPad",
      "Generic names on the files, such as USB 07",
      "Pre-roll, and up to 3 Markers per Take",
      "Crash recovery and the Apple Watch remote",
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
    price: "$4.99, once",
    items: [
      "Names and colors from the mixer, on the files",
      "Channel names you type, on the files",
      "A second Copy on a Drive, with Repair",
      "Unlimited Markers",
      "The Show report and Reaper project",
      "96 kHz recording",
      "Templates for each venue",
      "At a launch price, shared with Family Sharing and across your devices",
    ],
  },
];

// `a` is the plain answer (also used for the FAQ structured data); `node`, when set, is how it renders.
const faqs: { q: string; a: string; node?: ReactNode }[] = [
  {
    q: "Is the beta safe for a real gig?",
    a: "The beta is the next version, in testing before it comes to the App Store, and the recording works as described here: files are saved every 2 seconds, an app closed mid-Take finishes that Take the next time it opens, and a Take never stops because of a Trial or a limit. It is still new software, so record a test Take with your own mixer before the show, and keep a backup recording for a gig you can't repeat. A USB drive gives you a second Copy as you record.",
  },
  {
    q: "What does the beta cost?",
    a: "Nothing to join. Free records every USB Channel; to try the Pro features in the beta, start the 14-day Trial in Settings › Pro. Buying Pro in the beta isn't charged. TestFlight builds expire after 90 days, so install the newest build from TestFlight to carry on.",
  },
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
    a: "Any class-compliant USB mixer or audio interface records every channel it sends. Mixer Link adds channel names and colors for the Behringer X Air XR18 and MR18, which record 18 USB Channels; on other mixers you can type names with Pro. The Behringer X32 and Midas M32 work in the public beta now: all 32 USB Channels, with names and colors from the mixer. They come to the App Store in a later update. Planned next: Pioneer DJM mixers. Others, such as the Behringer Wing and Allen & Heath Qu and SQ, are being looked at. The list is under Supported mixers on the Features page.",
    node: (
      <>
        Any class-compliant USB mixer or audio interface records every channel it sends. Mixer Link adds channel names
        and colors for the Behringer X Air <a href="/mixers/xr18">XR18 and MR18</a>, which record 18 USB Channels; on
        other mixers you can type names with Pro. The Behringer <a href="/mixers/x32">X32 and Midas M32</a> work in the public beta
        now: all 32 USB Channels, with names and colors from the mixer. They come to the App Store in a later update.
        Planned next: Pioneer DJM mixers. Others, such as the Behringer Wing and Allen &amp; Heath Qu and SQ, are
        being looked at. The list is under Supported mixers on the Features page.
      </>
    ),
  },
  {
    q: "Can I record an XR18 without a computer?",
    a: "Yes. The XR18 and MR18 send all 18 channels over USB to whatever is plugged in, and ShowRecorder makes that your iPhone or iPad. You only need a computer later, to mix the Stems.",
    node: (
      <>
        Yes. The <a href="/mixers/xr18">XR18 and MR18</a> send all 18 channels over USB to whatever is plugged in, and
        ShowRecorder makes that your iPhone or iPad. You only need a computer later, to mix the Stems.
      </>
    ),
  },
  {
    q: "Can I record a church service or a rehearsal?",
    a: "Yes. Save a Template for each room with its channel names and Pre-roll, start a Show from it in one tap, and tap the flag at each song or part of the service.",
  },
  {
    q: "Where do the files go?",
    a: "Each Show has a folder for each Take, with one WAV file per channel; with Pro, a report and a Reaper project too. Open them from Shows in the app or in the Files app (On My iPhone or On My iPad, ShowRecorder), or, with Pro, on your Drive, and share them with AirDrop.",
  },
  {
    q: "What happens when the Trial ends?",
    a: "The app goes back to Free: new Takes still record every USB Channel, on the Device, with generic names and up to 3 Markers per Take. A Take in progress is never stopped, and every Show you recorded stays open, with all its files. You can buy Pro at any time.",
  },
  {
    q: "How does ShowRecorder compare with other apps?",
    a: "Side by side with Manytrack Recorder, a laptop with Reaper or Mixbus, X-Live and Auria, with a line on when each of the others is the better pick. See the comparison page.",
    node: (
      <>
        Side by side with Manytrack Recorder, a laptop with Reaper or Mixbus, X-Live and Auria, with a line on when
        each of the others is the better pick. See the <a href="/compare">comparison page</a>.
      </>
    ),
  },
  {
    q: "Can my family use Pro?",
    a: "Yes. Pro is a one-time purchase, shared with Family Sharing and across your devices.",
  },
  {
    q: "Is there an Android version?",
    a: "Not yet. An Android version is being considered, not promised: it needs its own app and testing on Android phones. Leave your email in the form below the pricing, and pick Android, to hear if it happens.",
    node: (
      <>
        Not yet. An Android version is being considered, not promised: it needs its own app and testing on Android
        phones. <a href="#launch-email">Leave your email</a>, and pick Android, to hear if it happens.
      </>
    ),
  },
  {
    q: "Is there a Mac version?",
    a: "Yes, in the public TestFlight beta now. The App Store release of 1.0 is for iPhone and iPad; the Mac follows on the Mac App Store.",
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
    <div className="home">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(softwareApplicationJsonLd()) }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(faqPageJsonLd(faqs)) }} />
      <section id="top" aria-labelledby="hero-title" className="hero">
        <div className="wrap hero-grid">
          <div>
            <h1 id="hero-title">Record every channel of your mixer on your iPhone. No laptop at the gig.</h1>
            <p className="lede">
              Plug your mixer into your iPhone over USB, press record, and get one 24-bit WAV file per channel,
              named from the mixer and ready for your DAW.
            </p>
            <p className="compat">
              Records any class-compliant USB mixer or audio interface. Mixer Link adds channel names and colors from the{" "}
              <a href="/mixers/xr18">XR18 and MR18</a> and the <a href="/mixers/x32">X32 and M32 (beta)</a>. Needs a
              USB-C iPhone 15 or later, or an iPad, on iOS 26.
            </p>
            <div className="hero-actions">
              <AppStoreBadge id="app-store-link" />
            </div>
          </div>
          <div className="devices">
            <Screenshot shot={SHOTS.heroIpad} sizes="(min-width: 1024px) 470px, 70vw" priority />
            <Screenshot shot={SHOTS.heroPhone} sizes="(min-width: 1024px) 150px, 45vw" priority />
          </div>
        </div>
      </section>

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

      <Section
        id="need"
        title="What you need"
        intro="A compatible mixer, an iPhone or iPad, and a cable. A USB drive is optional."
        className="sec-need"
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
        id="features"
        title="Multitrack recording, one file per channel"
        intro="ShowRecorder turns the USB audio from your mixer into one file per channel, written as you play, with nothing to set up on a laptop."
        className="sec-features"
      >
        <ul className="cards cards--4">
          {features.map((f, i) => (
            <li key={f.title} className={i < 4 ? "card" : "card card--more"}>
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
        id="pricing"
        title="Pricing"
        intro="ShowRecorder is free to download. Try everything for 14 days, then keep Free or buy Pro once."
        className="sec-pricing"
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
            <p className="buy">
              Buy Pro in the app: <strong>Settings › Pro</strong>. In the beta, buying Pro isn&apos;t charged, and the purchase
              isn&apos;t kept for the App Store version. <a href="/docs/pricing">Free, Trial and Pro in detail</a>
            </p>
          </div>
        </div>
      </Section>

      <Section id="email" title="Get ShowRecorder on the App Store">
        <div className="hero-actions">
          <AppStoreBadge id="app-store-link-email" />
          <p className="price">{ctaNote(false)}</p>
          <p className="safe">A Take never stops because of a Trial, a limit or a license.</p>
          <SignupForm />
          <p className="hero-links">
            <a className="see-need" href="#need">
              See what you need
            </a>
            <a className="see-need" href="/compare">
              Compare with other ways to record
            </a>
          </p>
        </div>
      </Section>

      <Section id="faq" title="Frequently asked questions" className="sec-faq">
        <div className="faq">
          {faqs.map((f) => (
            <details key={f.q}>
              <summary>
                <h3>{f.q}</h3>
                <span className="sign" aria-hidden="true" />
              </summary>
              <p>{f.node ?? f.a}</p>
            </details>
          ))}
        </div>
        <p className="more-link">
          More answers, step by step, are in the <a href="/docs">docs</a>.
        </p>
      </Section>

      <GetBand />
    </div>
  );
}
