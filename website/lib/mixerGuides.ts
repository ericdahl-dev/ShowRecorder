// The mixer recording guides (#1061): the hub at /guides/record lists every mixer
// with what it can record and how, and each mixer with a guide links to it.
//
// Every fact here comes from docs/research/mixer-recording/README.md (the summary table) and its detail files, where
// each one has a source and a confidence label, or from what Eric saw on his own mixer (an owner fact, labeled in the
// research). Never add a number or a capability that isn't there. Where the research says "unknown", the cell says so
// in plain words. "Maker" means the mixer maker's own manual, spec page or staff post.
//
// This file must not import lib/site.ts or lib/metadata.ts at run time: both build their lists from MIXER_GUIDES.

import type { Faq } from "@/lib/mixerFaqs";
import type { AppStoreCampaign } from "@/lib/site";
import type { Crumb } from "@/lib/structuredData";

export const GUIDES_HUB = "/guides/record";
// The shared guide every mixer guide links to (#1062).
export const TAP_POINT_GUIDE = "/guides/record/pre-or-post-fader";
// The best-app comparison (#1085). Its facts live in lib/bestApp.ts, which re-exports this; it is here because the
// hub's words (HUB_COPY) link to it, and lib/bestApp.ts already imports this file.
export const BEST_APP_GUIDE = "/guides/best-app-record-digital-mixer-iphone";

// Where the facts come from and how sure each one is: the research README in the app's public repository.
export const RESEARCH_URL = "https://github.com/ericdahl-dev/ShowRecorder/blob/main/docs/research/mixer-recording/README.md";

export type MixerRow = {
  name: string;
  // A short line under the name: other models it covers, or how sure a fact is.
  note?: string;
  // What the mixer sends over USB to a computer, iPhone or iPad.
  usb: string;
  // Recording with no computer: a card, a USB stick or a drive.
  onboard: string;
  // Mac, iPad and iPhone, each in plain words: maker-confirmed, a forum report, or not known yet.
  mac: string;
  ipad: string;
  iphone: string;
  // This mixer's guide, once it has one.
  guide?: string;
};

export const MIXER_ROWS: readonly MixerRow[] = [
  {
    name: "Behringer X32",
    note: "With the X-USB or X-LIVE card. Full size, Compact, Producer, Rack and Core.",
    usb: "Up to 32 in and 32 out through the card, at 44.1 or 48 kHz, 24-bit. With no card, no multitrack USB audio.",
    onboard: "X-LIVE card: 8, 16 or 32 channels to two SD cards. X-USB card: none. The console's USB stick port records stereo, 16-bit WAV.",
    mac: "Works with no driver (maker), though Behringer's own OS lists are years old.",
    ipad: "Not documented by the maker, and not tested yet.",
    iphone: "Not documented by the maker, and not tested yet.",
    guide: "/guides/record/x32",
  },
  {
    name: "Midas M32 and M32R",
    note: "With the DN32-USB or DN32-LIVE card.",
    usb: "DN32-USB: 32 in and 32 out, 48 kHz, 24-bit. DN32-LIVE: 32, 16, 8 or 2 channels.",
    onboard: "DN32-LIVE card: the same SD recorder as the X-LIVE. The console's USB stick port records stereo, 16-bit.",
    mac: "Works with no driver (maker).",
    ipad: "Not documented by the maker, and not tested yet.",
    iphone: "Not documented by the maker, and not tested yet.",
    guide: "/guides/record/m32",
  },
  {
    name: "Behringer WING, WING Rack and WING Compact",
    usb: "2 x 2 up to 48 x 48, 24-bit. The console runs at 44.1 or 48 kHz; USB at 44.1 kHz is not stated.",
    onboard: "WING-LIVE card: 64 channels on two SD cards. Front USB stick: 2 or 4 tracks.",
    mac: "One forum user reports it works with no driver; Behringer doesn't say.",
    ipad: "Reports differ; not tested yet.",
    iphone: "Not tested yet.",

    guide: "/guides/record/wing",
  },
  {
    name: "Behringer XR18 and Midas MR18",
    note: "Also the X18. Midas's own manual gives the MR18 the same USB specs and systems.",
    usb: "18 in and 18 out, or 2 x 2, at 44.1 or 48 kHz (48 by default). Each USB send has its own source and tap point.",
    onboard: "None for multitrack.",
    mac: "Works with no driver (maker).",
    ipad: "Yes, iOS 7 or later (Behringer for the XR18, Midas for the MR18).",
    iphone: "Not named by the maker. ShowRecorder (the app this site makes) has recorded all 18 XR18 channels on an iPhone.",
    guide: "/guides/record/xr18",
  },
  {
    name: "Behringer XR12 and XR16, Midas MR12",
    usb: "No USB audio interface, so no multitrack over USB.",
    onboard: "Stereo recording, 2 tracks, to a USB stick.",
    mac: "No multitrack: no USB audio interface.",
    ipad: "No multitrack: no USB audio interface.",
    iphone: "No multitrack: no USB audio interface.",
    guide: "/guides/record/xr12-xr16-mr12",
  },
  {
    name: "Allen & Heath SQ-5, SQ-6, SQ-7 and SQ-Rack",
    usb: "32 in and 32 out, 48 or 96 kHz.",
    onboard: "SQ-Drive: 16 channels at 96 kHz or 32 at 48 kHz, 24-bit WAV, to a fast USB drive (the maker says most sticks are too slow). Or stereo.",
    mac: "Class compliant (maker).",
    ipad: "Not named. Allen & Heath says no driver is needed on any system that supports class-compliant audio. Not tested yet.",
    iphone: "Not named. Allen & Heath says no driver is needed on any system that supports class-compliant audio. Not tested yet.",
    guide: "/guides/record/ah-sq",
  },
  {
    name: "Allen & Heath Qu-5, Qu-6 and Qu-7",
    note: "The new Qu.",
    usb: "32 in and 32 out over USB-C, 48 or 96 kHz.",
    onboard: "SD card: 16 channels at 96 kHz or 32 at 48 kHz. USB stick: stereo.",
    mac: "Class compliant.",
    ipad: "Allen & Heath says tablets and phones can work, but not every device is tested or officially supported; set USB Stream Mode to Multitrack. Not tested yet.",
    iphone: "Allen & Heath says tablets and phones can work, but not every device is tested or officially supported; set USB Stream Mode to Multitrack. Not tested yet.",
    guide: "/guides/record/qu",
  },
  {
    name: "Allen & Heath Qu-16, Qu-24, Qu-32, Qu-SB and Qu-Pac",
    note: "Qu Classic.",
    usb: "48 kHz. The Qu-16 sends 24 channels; the Qu-24, Qu-32, Qu-SB and Qu-Pac send 32.",
    onboard: "Qu-Drive: 18 tracks to a USB drive.",
    mac: "Works.",
    ipad: "iOS sees it as class compliant, says an Allen & Heath staff member on their forum. The iPad isn't named; not tested yet.",
    iphone: "Not named; not tested yet.",
    guide: "/guides/record/qu",
  },
  {
    name: "Allen & Heath CQ-12T, CQ-18T and CQ-20B",
    usb: "CQ-12T 16 in, 16 out. CQ-18T 24 in, 22 out. CQ-20B 24 in, 24 out. 48 or 96 kHz.",
    onboard: "SD card: as many channels as USB at 48 kHz; 16 at 96 kHz on the CQ-18T and CQ-20B. USB stick: stereo.",
    mac: "Works.",
    ipad: "Yes, says Allen & Heath staff, with Stream Mode set to Multitrack.",
    iphone: "Not tested yet.",
    guide: "/guides/record/ah-cq",
  },
  {
    name: "Allen & Heath Avantis and Avantis Solo",
    usb: "No USB audio interface. Multitrack needs an option card (Dante, Waves, MADI or gigaACE).",
    onboard: "Stereo only, as 24-bit 96 kHz WAV.",
    mac: "No multitrack over USB.",
    ipad: "No multitrack over USB.",
    iphone: "No multitrack over USB.",
  },
  {
    name: "Soundcraft Ui24R",
    usb: "32 in and 32 out, 48 kHz. Bit depth not stated.",
    onboard: "22 channels to a USB stick (FAT32, up to 32 GB). The file format is not stated by the maker; a 2017 review says WAV or FLAC.",
    mac: "Works with no driver (maker).",
    ipad: "Not stated by the maker; not tested yet.",
    iphone: "Not stated by the maker; not tested yet.",
    guide: "/guides/record/ui24r",
  },
  {
    name: "Soundcraft Signature 12 MTK and 22 MTK",
    note: "Discontinued.",
    usb: "12 MTK: 14 in, 12 out. 22 MTK: 24 in, 22 out. 44.1 or 48 kHz, 24-bit.",
    onboard: "None.",
    mac: "Uses Core Audio; current macOS not listed by Soundcraft.",
    ipad: "Yes, with a camera adapter (maker).",
    iphone: "Not tested yet.",
  },
  {
    name: "Yamaha TF1, TF3, TF5 and TF-Rack",
    usb: "34 in and 34 out, 48 kHz only, 24-bit.",
    onboard: "Stereo WAV to a USB hard disk or SSD (not a stick).",
    mac: "Class compliant (maker).",
    ipad: "Not stated by the maker; not tested yet.",
    iphone: "Not stated by the maker; not tested yet.",
  },
  {
    name: "Yamaha DM3 and DM3 Standard",
    usb: "Up to 18 in and 18 out, 48 or 96 kHz.",
    onboard: "Stereo WAV or MP3 to USB storage.",
    mac: "Yamaha says its driver is required.",
    ipad: "Not supported by Yamaha, and not tested.",
    iphone: "Not supported by Yamaha, and not tested.",
  },
  {
    name: "Yamaha MG10XU, MG12XU, MG16XU and MG20XU",
    note: "The newer Yamaha MGX12 and MGX16 differ: Yamaha says iPhone and iPad recognize them, with up to 18 in on the MGX16 at 44.1 or 48 kHz.",
    usb: "Stereo only: 2 in and 2 out, up to 192 kHz.",
    onboard: "None.",
    mac: "USB Audio Class 2.0 compliant (maker).",
    ipad: "Yes with a camera adapter, stereo only (maker). A USB-C iPad: not tested yet.",
    iphone: "A USB-C iPhone: not tested yet.",
  },
  {
    name: "PreSonus StudioLive Series III",
    note: "Consoles, 32R, 24R and 16R.",
    usb: "64 in and 64 out (Native) or 34 x 34 (Compatibility), 44.1 or 48 kHz. 16R: 18 or more, depending on firmware.",
    onboard: "Consoles: 34 tracks to an SD or SDHC card (up to 32 GB; SDXC not supported). Racks: stereo only.",
    mac: "Works.",
    ipad: "Class compliant (PreSonus support). In 2021 the 64 x 64 mode crashed two iPad apps; PreSonus says both have since been fixed.",
    iphone: "PreSonus lists the iPhone in a general statement; not tested by us.",
    guide: "/guides/record/presonus-studiolive-iii",
  },
  {
    name: "Mackie DL32S, DL16S, DL32SE and DL16SE",
    usb: "32 in and 32 out (DL16S: 16 x 16), 48 kHz.",
    onboard: "None.",
    mac: "Class compliant. DL32S/DL16S: current macOS not listed by Mackie; SE: macOS 10.15 or higher.",
    ipad: "Not tested yet.",
    iphone: "Not tested yet.",
    guide: "/guides/record/mackie-dl32s",
  },
  {
    name: "Mackie DL32R",
    usb: "32 in and 32 out, 48 kHz.",
    onboard: "Up to 32 tracks with current firmware (older units may show 24 until updated; our reading), 16 or 24-bit at 48 kHz, as one multichannel WAV per take, split into files under 2 GB, to a spinning USB hard drive formatted by the DL32R (no thumb drive, no hub). The drive and a computer can't be used at the same time.",
    mac: "Class compliant; current macOS not listed by Mackie.",
    ipad: "Yes, with a camera adapter (manual).",
    iphone: "Not tested yet.",
    guide: "/guides/record/mackie-dl32r",
  },
  {
    name: "Zoom LiveTrak L-12, L-20 and L-20R",
    usb: "L-12: 14 in, 4 out. L-20: 22 in, 4 out. 44.1 or 48 kHz only; no USB audio at 96 kHz.",
    onboard: "SD card: 14 tracks (L-12) or 22 (L-20), WAV up to 24-bit 96 kHz (L-12: 12 tracks at 96 kHz).",
    mac: "Install Zoom's driver.",
    ipad: "Yes, named by Zoom, with the rear Class Compliant Mode switch on (we suggest setting it before power-on) and a Lightning camera adapter. USB-C: not tested yet.",
    iphone: "Yes, named by Zoom, with the rear Class Compliant Mode switch on (we suggest setting it before power-on) and a Lightning camera adapter. USB-C: not tested yet.",

    guide: "/guides/record/zoom-l12",
  },
  {
    name: "Pioneer DJ DJM-A9, V10, 900NXS2, 750MK2, 450 and 250MK2",
    note: "DJ mixers. Every USB send is a stereo pair.",
    usb: "6 stereo pairs (12 channels) on the A9, V10, 900NXS2 and 750MK2; 4 pairs (8 channels) on the 450 and 250MK2. What each pair carries is set in Pioneer's Setting Utility; the FX Send pair is fixed.",
    onboard: "None for multitrack. Pioneer's DJM-REC iPhone app records the stereo mix.",
    mac: "A9: no audio driver needed (maker), class compliance not stated. The other five need Pioneer's Mac driver (maker).",
    ipad: "No multitrack support from Pioneer. The A9 manual says not to connect mobile devices to its computer USB ports; the other five need a Mac driver.",
    iphone: "No multitrack support from Pioneer. The A9 manual says not to connect mobile devices to its computer USB ports; the other five need a Mac driver.",
  },
];

// The hub's own questions, from the hub's text and table. The page shows them and its FAQPage JSON-LD repeats them.
export const HUB_FAQS: readonly Faq[] = [
  {
    q: "Which digital mixers can multitrack record without a computer?",
    a: "Some can, with a card or a drive: the X32 with an X-LIVE card and the M32 with a DN32-LIVE card (SD cards), the WING with its WING-LIVE card, the SQ to a fast USB drive, the new Qu and the CQ to an SD card, the Qu Classic to a USB drive, the Ui24R to a USB stick, the StudioLive Series III consoles to an SD card, the Mackie DL32R to a hard drive and the Zoom LiveTrak to an SD card. Many others, such as the XR18, record only stereo or nothing by themselves.",
  },
  {
    q: "Can I multitrack record a mixer on an iPad or iPhone?",
    a: "Often, if the mixer sends its channels over USB as a class-compliant interface. Some makers say their mixers work with an iPad or iPhone; the table shows which, and says not tested yet where nobody has checked. The XR12, XR16, MR12 and Avantis have no USB audio interface, so they can't.",
  },
  {
    q: "Do I need a driver to record a mixer on a Mac?",
    a: "Usually not: most mixers in the table work on a Mac with no driver. The Yamaha DM3 needs Yamaha's driver, and for the Zoom LiveTrak, install Zoom's driver.",
  },
  {
    q: "How do I keep an iPhone or iPad charged while it records a mixer?",
    a: "The mixer powers nothing on the phone or tablet through its USB audio port. For a long show, use a powered USB-C hub, or a camera adapter that passes power through.",
  },
];

// The hub's own words, as Markdown with only **bold** and [links](...). The page renders them with InlineMarkdown and
// llms-full.txt prints them as they are, so the two never differ.
export const HUB_COPY = {
  title: "How to multitrack record a digital mixer",
  lede: "Most digital mixers can record every channel to its own track. How they do it differs a lot: over USB to a computer, to a card or stick in the mixer, or to an iPad or iPhone. This page lists what each mixer can do, and each guide shows the settings and routing step by step.",
  method: `Facts come from the makers' own manuals and spec pages where we could find them. Where only a forum or a retailer says it, we say so. Where nobody says, we write "not stated" or "unknown" instead of guessing. Researched November 2026; check your mixer's manual and firmware before a show. [Sources and method](${RESEARCH_URL}).`,
  pickTitle: "Pick your mixer",
  pickOthers: "Every other mixer, in the table",
  tableTitle: "What each mixer can record",
  tableIntro: `"Over USB" is what the mixer sends to a computer, iPad or iPhone. "With no computer" is what it records by itself. Words like card out and class compliant are in the [glossary](#glossary).`,
  waysTitle: "Three ways to record every channel",
  ways: [
    "**To a computer over USB.** The mixer acts as a USB audio interface, and a recording app on the computer (a [DAW](#glossary)) records each channel to its own track. On a Mac, most of the mixers above need no driver.",
    "**To a card or stick in the mixer.** Some mixers, or an option card in them, record many tracks to an SD card or a USB drive with no computer at all. Many others record only a stereo mix this way.",
    `**To an iPad, iPhone or Mac with an app.** A [class-compliant](#glossary) mixer can send its channels to an iPad or iPhone over a USB cable. Some makers say their class-compliant mixers work with an iPad or iPhone; the table shows which, and says "not tested yet" where nobody has checked.`,
  ],
  waysAfter: [
    `Whichever way you record, you also choose where in each channel the recording is taken: before or after the gain, the EQ and the fader. [Pre or post fader](${TAP_POINT_GUIDE}) explains each tap point, with pros and cons.`,
    "The mixer powers nothing on the phone or tablet through its USB audio port. For a long show, use a powered USB-C hub, or a camera adapter that passes power through, so the iPhone or iPad charges while it records.",
    `To record a gig on an iPhone or iPad with no laptop, see [Record a gig without a laptop](/guides/record-gig-without-laptop). To choose the app, [the best app to multitrack record a digital mixer on iPhone and iPad](${BEST_APP_GUIDE}) compares nine of them.`,
  ],
  fitsTitle: "Where ShowRecorder fits",
  fits: "ShowRecorder records every USB Channel from any class-compliant mixer, one WAV file per channel, on a USB-C iPhone or iPad. Names and colors from the mixer (Mixer Link) work only with the [XR18 and MR18](/mixers/xr18) and the [X32 and M32](/mixers/x32). Its X32 and M32 support has run only against an X32 emulator so far.",
  glossaryTitle: "Glossary",
} as const;

// The line under a guide in "Pick your mixer" when ShowRecorder has Mixer Link for it, linking to its ShowRecorder page.
export function pickMixerLink(productPage: string): string {
  return `Mixer Link: ShowRecorder takes the channel names and colors from this mixer ([how it works](${productPage})).`;
}

// Words the guides use, defined once on the hub; each guide links here.
export const GLOSSARY: readonly { term: string; def: string }[] = [
  { term: "Tap point", def: "The place in a channel where the recording feed is taken: the raw input, before or after EQ, or after the fader." },
  { term: "+M", def: "A tap marked +M follows the channel mute: a muted channel records silence. The XR18 shows these on each USB send." },
  { term: "Card out", def: "On the X32, the routing page that picks what the USB card sends, in blocks of 8 channels." },
  { term: "AES50", def: "Behringer and Midas's digital link to a stage box. On the X32, the AES50 blocks are the stage box inputs." },
  { term: "P16", def: "Behringer's personal monitor output. On the X32 its 16 slots each have a tap point, so they can stage signals for card out." },
  { term: "Class compliant", def: "Works without a driver: the computer, iPad or iPhone sees the mixer as a standard USB audio device." },
  { term: "2 x 2, 18 x 18, 32/32", def: "How many channels USB sends to the computer and back. A mixer left at 2 x 2 sends only 2." },
  { term: "DAW", def: "Digital audio workstation: the app on a computer that records and mixes, such as Reaper, Logic or Pro Tools." },
  { term: "Virtual soundcheck", def: "Playing a recorded show back through the mixer's channels over USB, to set the mix with no band on stage." },
  {
    term: "Mixer Link",
    def: "ShowRecorder takes each channel's name and color from the mixer, so every track is named for you. It works only with the XR18 and MR18 and the X32 and M32; the X32 and M32 support has run only against an X32 emulator so far.",
  },
  { term: "CoreAudio", def: "Apple's audio system on the Mac. A mixer that is CoreAudio compatible works on a Mac with no driver." },
];

// A mixer guide at /guides/record/<slug>. Its route, PAGES entry, title, llms.txt line and hub link all come from here.
export type MixerGuide = {
  slug: string;
  path: string;
  // The key of its PAGES entry (lib/metadata.ts), which the page passes to pageMetadata().
  pageKey: string;
  // The mixer's short name, for the title, the breadcrumb and the section headings: "X32".
  short: string;
  // The full name, for the H1 and the article headline: "Behringer X32".
  mixer: string;
  // Its short facts in plain words, under its name in the hub's "Pick your mixer" list. From its hub rows.
  pick: string;
  description: string;
  // The day the guide was first published.
  published: string;
  // The ShowRecorder page for this mixer, which links back. Only mixers with Mixer Link have one (not the Qu).
  productPage?: string;
  // How many hub rows link to this guide, when it covers more than one (the Qu: new Qu and Qu Classic).
  hubRows?: number;
  faqs: readonly Faq[];
  faqsName: string;
  // The URLs in its Sources section, which the TechArticle data cites.
  sources: readonly string[];
  campaign: AppStoreCampaign;
  // The setting the tap-point guide's short answer names for this mixer.
  tapPick: string;
  // True for a mixer with no USB audio, which can't multitrack (the XR12, XR16 and MR12): its title and H1 say
  // "How to record", and it has no "every USB Channel" or Mixer Link line.
  noMultitrack?: true;
};

// "<mixer> USB multitrack recording: settings and routing - ShowRecorder", the <title> of every mixer guide. A guide
// for a mixer that can't multitrack passes its own headline instead (see noMultitrack).
export function guideTitle(short: string, headline?: string): string {
  return headline ? `${headline} - ShowRecorder` : `${short} USB multitrack recording: settings and routing - ShowRecorder`;
}

// "How to multitrack record a Behringer X32", "... an Allen & Heath Qu": the H1, the article headline and the
// llms.txt line of every mixer guide. "How to record a ..." for a mixer that can't multitrack (the XR12).
export function guideHeadline(mixer: string, noMultitrack = false): string {
  return `How to ${noMultitrack ? "record" : "multitrack record"} ${/^[AEIOU]/.test(mixer) ? "an" : "a"} ${mixer}`;
}

// A guide's own headline and <title>, with its noMultitrack override applied.
export const headlineOf = (g: MixerGuide) => guideHeadline(g.mixer, g.noMultitrack);
export const titleOf = (g: MixerGuide) => guideTitle(g.short, g.noMultitrack ? headlineOf(g) : undefined);

// Home > Recording guides > the page.
export function guideTrail(name: string, path: string): Crumb[] {
  return [
    { name: "Recording guides", path: GUIDES_HUB },
    { name, path },
  ];
}

export const guideBySlug = (slug: string) => MIXER_GUIDES.find((g) => g.slug === slug);
// The questions on the tap-point guide. The page shows these exact strings and its FAQPage JSON-LD repeats them.
export const TAP_POINT_FAQS: readonly Faq[] = [
  {
    q: "Should I record pre-fader or post-fader?",
    a: "For channel tracks you will mix later, record pre-fader: from the raw input, or after gain and trim but before EQ. A post-fader tap follows every fader move, and a fader that is down or a muted channel records a silent track. Use post-fader for mixes and buses.",
  },
  {
    q: "Does changing the gain during the show change my recording?",
    a: "Yes. Even the earliest tap is after the analog preamp, so a gain change changes the track level, and a clip at the preamp is in the file for good. Trim, EQ and fader moves don't reach the raw input tap.",
  },
  {
    q: "Which tap is best for virtual soundcheck?",
    a: "The raw input, before the digital trim. The playback comes back in at the same point, so the channel's trim, EQ and dynamics work on it as they did on the live input.",
  },
  {
    q: "Should I record pre-EQ or post-EQ?",
    a: "Pre-EQ, if you want to mix the tracks later: EQ and compression after the tap are baked in and can't be undone. Post-EQ gives tracks that sound like front of house, which suits a quick release or a streaming feed.",
  },
];

// The questions on the X32 guide.
export const X32_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can an X32 multitrack record without a computer?",
    a: "Only with the X-LIVE card. It records 8, 16 or 32 channels to two SD or SDHC cards, up to 32 GB each, as one multichannel 32-bit WAV per session: up to 200 minutes at 32 channels and 44.1 kHz. The top-panel USB stick port records stereo only, and the X-USB card can't record by itself.",
  },
  {
    q: "How do I send the main mix or buses to USB on an X32?",
    a: "Card out works in blocks of 8. Put the main mix or a bus in an Out 1-16 or P16 slot, with its tap point, then pick that block (for example Out 9-16) on the card out tab. On firmware 4.0 or later you can also point single User Out slots at those staged slots (per user reports; no Behringer manual describes it).",
  },
  {
    q: "Does the X32 USB card need a driver?",
    a: "Not on a Mac: Behringer says the X-USB and X-LIVE are CoreAudio compatible with no driver. On Windows, install Behringer's ASIO driver.",
  },
  {
    q: "Are the card's Local inputs pre or post fader?",
    a: "Before everything in the channel. The Local and AES50 blocks on card out are the raw inputs, after the preamp and converter, so the channel's EQ, dynamics and fader don't change them. Preamp gain does.",
  },
];

// The questions on the XR18 and MR18 guide.
export const XR18_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can an XR18 multitrack record without a computer?",
    a: "Not by itself. The XR18 has no USB port for a stick or drive, only the type-B audio port. Plug it into something that records over USB, such as a computer or an iPad, and it sends up to 18 channels, once the USB interface is set to 18 x 18.",
  },
  {
    q: "Does the XR18 need a driver on a Mac?",
    a: "No. Behringer says it is CoreAudio compatible on a Mac, and Midas says the same of the MR18. On Windows, install the maker's ASIO driver.",
  },
  {
    q: "How do I choose what goes to each USB channel on an XR18?",
    a: "Open Routing (the up and down arrow icon at the top of the Main View) and use the Inputs/USB grid: tap a box to move the orange dots, or pick the USB sends from the menu under the folder icon. Each USB send has its own source.",
  },
  {
    q: "Can I choose pre or post fader for each USB channel on an XR18?",
    a: "Yes. On the USB Sends page of Routing, each USB Send has its own Signal Source and Signal Tap: Analog, Input, Pre EQ, Post EQ, Pre Fader and Post Fader, most with a +M version that goes silent when the channel is muted. For a recording you will remix, pick Input. We saw this on a real XR18; Behringer's V1.0 manual doesn't describe it.",
  },
  {
    q: "Can the XR12 or XR16 multitrack record?",
    a: "Not over USB. They have no USB audio interface. They record stereo to a USB stick.",
  },
  {
    q: "Why does my recorder see only 2 channels from the XR18?",
    a: "The USB interface can be set to 18 x 18 or 2 x 2 in Setup, on the Audio/MIDI tab. At 2 x 2 it sends only 2 channels. Set it to 18 x 18 for a multitrack.",
  },
  {
    q: "What sample rate does the XR18 record at?",
    a: "48 kHz by default, or 44.1 kHz, set in Setup on the Audio/MIDI tab. Mute the main LR fader before you change it, because pops can occur.",
  },
];

// The questions on the Qu guide, from docs/research/mixer-recording/ah-qu.md. There is no Qu product page, so the
// guide owns the iPad question. The first one is the question AI answers found nothing for (baseline 2026-11-06).
export const QU_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I multitrack record a Qu-16 to an iPad?",
    a: "Allen & Heath staff say yes: iOS sees a Qu as a class-compliant multichannel device, so a multichannel recording app sees its channels (a stereo app may see only the first two). We haven't tested it yet, and Allen & Heath doesn't name the iPad. The Qu-16 sends 24 channels over USB at 48 kHz; the Qu-24, Qu-32, Qu-SB and Qu-Pac send 32. The new Qu-5, Qu-6, Qu-7 and Qu-3 send 32 at 48 or 96 kHz with USB Stream Mode set to Multitrack.",
  },
  {
    q: "Can a Qu multitrack record without a computer?",
    a: "Yes. The new Qu records up to 16 channels at 96 kHz or 32 at 48 kHz to an SDHC card (up to 32 GB), one 24-bit WAV per channel. A Qu Classic records 18 tracks (16 mono plus a stereo pair), 48 kHz 24-bit WAV, to a USB drive with Qu-Drive; Allen & Heath says most USB sticks are too slow.",
  },
  {
    q: "Why does my app see only 2 channels from a Qu?",
    a: "On a new Qu, USB Stream Mode is probably on Stereo, which sends only USB 1 and 2. Set it to Multitrack in SETUP > Audio > Sync & USB. A Qu Classic has no stream mode, but a stereo app may see only the first two channels; use a multichannel recording app.",
  },
  {
    q: "Does a Qu need a driver?",
    a: "Not on a Mac: both generations work there with no driver. On Windows, install Allen & Heath's driver; on a new Qu, all 32 channels need ASIO.",
  },
  {
    q: "Is a Qu's USB recording pre or post fader?",
    a: "On a Qu Classic, USB takes each channel's Insert Send by default: directly after the preamp, with no channel processing. You can switch it to Direct Outs with one global source point. On a new Qu, patch the input direct outs to USB; they include all processing before the Direct Out Source point you pick.",
  },
];

// The questions on the Zoom LiveTrak L-12 and L-20 guide (#1080). Facts: docs/research/mixer-recording/zoom-livetrak-l12-l20.md.
export const ZOOM_L12_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record a Zoom L-12 or L-20 to an iPhone or iPad?",
    a: "Yes, Zoom names both. Set the rear CLASS COMPLIANT MODE switch to ON and the MODE switch to AUDIO INTERFACE, at 44.1 or 48 kHz, before you turn the mixer on, and connect with Apple's Lightning to USB Camera Adapter. A USB-C iPhone or iPad is not named by Zoom and not tested yet.",
  },
  {
    q: "Can the L-12 or L-20 multitrack record without a computer?",
    a: "Yes, to an SD card: 14 tracks on the L-12 (12 at 96 kHz) and 22 on the L-20, as WAV files at 16 or 24-bit, up to 96 kHz. Each file starts a new one when it passes 2 GB, with no gap.",
  },
  {
    q: "Does the L-12 or L-20 need a driver on a Mac?",
    a: "Install Zoom's driver. Zoom's manual has you install it on a Mac and on Windows, and ties the driver-free Class Compliant Mode only to iOS. Whether a Mac works with no driver is not stated by Zoom.",
  },
  {
    q: "Can I record the L-12 or L-20 at 96 kHz over USB?",
    a: "No. At 96 kHz the audio interface is off; only the SD card records. Over USB the L-12 and L-20 run at 44.1 or 48 kHz, 24-bit.",
  },
  {
    q: "Can I choose which channels go to each USB channel on the L-12 or L-20?",
    a: "No. The order is fixed: each input channel goes to the USB channel with the same number, and the master L/R comes last. No monitor mix can go to USB or the SD card. Zoom's driver version 2 can move the master to computer channels 1 and 2, on a Mac or Windows only.",
  },
  {
    q: "Are L-12 and L-20 recordings pre or post fader?",
    a: "Pre-fader and after each channel's compressor; before the EQ too, per Zoom's block diagrams (our reading). Leave the COMP knob at zero for clean tracks. On the L-20, MENU > REC/PLAY > REC SOURCE = PRE COMP gives uncompressed SD tracks; USB tracks still follow the compressor (per Zoom's block diagram).",
  },
  {
    q: "Why does my iPhone or computer see no audio from the L-12 or L-20?",
    a: "Check the rear switches: MODE must be AUDIO INTERFACE, SAMPLE RATE 44.1 or 48 kHz (at 96 kHz the audio interface is off), and for an iPhone or iPad CLASS COMPLIANT MODE must be ON. MODE and SAMPLE RATE are read at power-on (Zoom); set CLASS COMPLIANT MODE before power-on too (our advice). Change them with the mixer off, then turn it on again.",
  },
];

// The questions on the Mackie DL32R guide (#1079). Facts: docs/research/mixer-recording/mackie-dl32r.md.
export const DL32R_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I multitrack record a Mackie DL32R to an iPad or iPhone?",
    a: "Mackie's manual names the iPad: \"you may stream audio directly to and from an iPad using the iPad camera connection kit.\" The DL32R sends 32 channels at 48 kHz as a class-compliant USB device. Mackie doesn't name the iPhone, and nobody has tested one with a DL32R yet. The manual dates from 2015, so a USB-C iPad is not tested yet either.",
  },
  {
    q: "Can a DL32R multitrack record without a computer?",
    a: "Yes, to a USB hard drive on its USB A port: 16 or 24-bit at 48 kHz, as one multichannel WAV per take, split into files under 2 GB with no gap. Mackie's Master Fader guide (V5.0 and the 2026 V5.1) says 1 to 32 tracks; the 2015 spec table says 1 to 24 (see the guide). Mackie says to use a spinning hard drive formatted by the DL32R, not a thumb drive, and no USB hub.",
  },
  {
    q: "Can the DL32R record to a drive and a computer at the same time?",
    a: "No. Mackie: \"USB A and USB B connectors may NOT be used simultaneously.\" A drive on USB A takes priority and interrupts a computer recording, and the computer won't see the DL32R again until you unplug and replug USB B.",
  },
  {
    q: "Does the DL32R need a driver?",
    a: "Not on a Mac: it is USB Audio Class 2.0 compliant, and Mackie says a Mac should work with no extra driver. Mackie's 2015 list stops at OS X 10.11, so current macOS is not listed. On Windows, Mackie says a driver installation is required.",
  },
  {
    q: "Is DL32R USB recording pre or post fader?",
    a: "For the channels, pre-fader either way. The default source, Mic Pre, is straight after the analog preamp: before digital trim, HPF, gate, compressor, EQ, mute and fader. Channel Post-DSP comes after the HPF, gate, compressor and EQ, before mute and fader (per Mackie's block diagram). You pick one per USB slot in I/O Patch > USB.",
  },
  {
    q: "How do I record the main mix along with the channels on a DL32R?",
    a: "In Master Fader, open I/O Patch, the USB tab, and patch Main L/R (post-fader, or Pre-Fader) to two USB slots. With all 32 inputs in use there are no spare slots, so a stereo mix costs two input tracks.",
  },
];

// The questions on the Behringer WING guide (#1066). Facts: docs/research/mixer-recording/wing.md.
export const WING_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record a Behringer WING to an iPhone or iPad?",
    a: "Not tested yet. Behringer names no iPhone or iPad for USB audio. For the iPad, forum reports differ: one user says their iPads work with a WING Rack, another says three iPads on iOS 18 did not. Nobody has reported an iPhone. Test yours before a show.",
  },
  {
    q: "Does the WING need a driver on a Mac?",
    a: "One forum user reports it works on a Mac with no driver; Behringer doesn't say. Behringer offers an ASIO driver for Windows only.",
  },
  {
    q: "Can the WING multitrack record without a computer?",
    a: "Yes. Every WING model comes with the WING-LIVE card: up to 64 channels at 48 kHz, 32-bit, onto two SD cards (32 each). Each card writes one multichannel WAV per session, which Behringer's LiveSessions app splits into tracks. The front USB port also records 2 or 4 tracks to a USB stick.",
  },
  {
    q: "How do I route channels to USB on a WING?",
    a: "On ROUTING > OUTPUTS, pick the USB output group and choose a source for each slot, 1 to 48. Any source can go in any slot: raw inputs, buses, the mains, or a User Signal copy of a channel. Behringer doesn't say what the slots carry out of the box, so check and patch every slot yourself.",
  },
  {
    q: "Why does my computer see only 2 or 8 channels from the WING?",
    a: "Check SETUP > AUDIO > USB AUDIO: it sets 2 x 2, 8 x 8, 16 x 16, 32 x 32 or 48 x 48 channels. If the WING shows up as a disk instead (a red OS or DATA tag on its screen), eject that disk on the computer to get USB audio back.",
  },
  {
    q: "Are WING recordings pre or post fader?",
    a: "You choose. A raw input (Local In, AES50) on a USB slot is taken after the preamp gain, with no channel processing. For a channel, make a User Signal: it copies the channel at its TAP point (INPUT, FILTER, TAP 3 to 5, PRE FDR, POST FDR or POST PROC) or post-fader.",
  },
  {
    q: "How do I do a virtual soundcheck on a WING?",
    a: "Each channel has a MAIN and an ALT input. Patch the live source to MAIN and the playback (USB Audio from a computer, WLIVE PLAY from the SD cards) to ALT on ROUTING > CHANNELS, then switch all channels at once with SETUP > AUDIO > INPUT SELECT.",
  },
];

// The questions on the Midas M32 guide (#1065). Facts: docs/research/mixer-recording/m32.md, and x32.md where it
// says the X32 facts apply (labeled).
export const M32_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can an M32 multitrack record without a computer?",
    a: "Only with the DN32-LIVE card, fitted to the M32 LIVE and M32R LIVE. It records 8, 16 or 32 channels to two SD or SDHC cards (FAT32, up to 32 GB each), as uncompressed multichannel 32-bit WAV at the console's 44.1 or 48 kHz: up to 200 minutes at 32 channels and 44.1 kHz on two 32 GB cards. The top-panel USB stick port records stereo only, and the DN32-USB card can't record by itself.",
  },
  {
    q: "Is recording an M32 the same as recording an X32?",
    a: "Mostly. The M32 shares the X32's routing and firmware family, and its manual describes the same card out tab, in blocks of 8. The differences are the cards: Klark Teknik's DN32-USB (USB only) and DN32-LIVE (USB plus two SD slots) instead of Behringer's X-USB and X-LIVE.",
  },
  {
    q: "Does the DN32-USB card need a driver on a Mac?",
    a: "No. Klark Teknik calls the DN32-USB class compliant and CoreAudio compatible, with no driver required. On Windows, install the ASIO driver.",
  },
  {
    q: "Can I record an M32 to an iPhone or iPad?",
    a: "Not documented, and not tested yet. No Midas or Klark Teknik document lists iOS or iPadOS for the DN32-USB or DN32-LIVE. The DN32-USB is class compliant, which suggests it may work, but that is not a confirmation.",
  },
  {
    q: "How do I send the main mix or buses to USB on an M32?",
    a: "Card out works in blocks of 8. Put the main mix or a bus in an Out 1-16 or P16 slot, with its tap point, then pick that block (for example Out 9-16) on the card out tab. User Out routing on firmware 4.x probably works as on the X32, per user reports (our reading); no Midas document describes it.",
  },
];

// The questions on the Mackie DL32S and DL16S guide (#1078). Facts: docs/research/mixer-recording/mackie-dl32s.md.
export const MACKIE_DL32S_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record a Mackie DL32S to an iPhone or iPad?",
    a: "Not tested yet. Mackie doesn't name the iPhone or iPad for the DL32S or DL16S. The mixer is a USB Audio Class 2.0 compliant device that works on a Mac with no driver, so an iPhone or iPad may work, but nobody has tested it. Master Fader, Mackie's iOS app, controls the mixer; Mackie says recording happens outside Master Fader, so you need a recording app.",
  },
  {
    q: "Can the DL32S multitrack record without a computer?",
    a: "No. The DL32S has no onboard recorder: Mackie's manual says recording and playback need a computer connected to its USB-B port. The DL32R is the Mackie DL mixer that records to a USB hard drive by itself.",
  },
  {
    q: "Does the DL32S need a driver?",
    a: "Not on a Mac: Mackie says it is an audio class 2.0 compliant device that should work with no additional drivers. Mackie lists macOS 10.13 and 10.14; newer macOS is not listed. On Windows, install Mackie's driver.",
  },
  {
    q: "How do I choose what goes to each USB channel on a DL32S?",
    a: "In Master Fader, open I/O Patch (upper right of the navigation bar) and the USB tab. Rows are sources and columns are destinations; tap a crosshair to patch. Any source can go to any USB channel. By default, Mic Pre 1-32 go to USB 1-32.",
  },
  {
    q: "Is the DL32S's USB recording pre or post fader?",
    a: "By default it is the Mic Pre: after the analog gain, before the Digital Trim, polarity, high pass filter, gate, compressor, EQ, mute and fader. Patch Channel Post-DSP instead for tracks after the EQ and dynamics, still before the mute and fader. Main L/R is offered pre-fader and post-fader.",
  },
  {
    q: "Can I record the main mix with the channels on a DL32S?",
    a: "Yes. Patch Main L/R (pre or post fader) to two USB channels in I/O Patch > USB, as Mackie's own example does. On the DL32S the mix takes two of the 32 USB channels, which leaves 30 for inputs.",
  },
  {
    q: "How do I play tracks back into a DL32S for a virtual soundcheck?",
    a: "Each channel has an Input A, the mic pres by default, and an Input B, the USB returns by default. Play the tracks from the computer over USB and switch the channels to Input B; switch back to Input A for the show.",
  },
  {
    q: "What sample rate does the DL32S record at?",
    a: "48 kHz only. USB carries 16 or 24-bit; the recording app picks which (our reading: Mackie doesn't say).",
  },
];

// The questions on the Soundcraft Ui24R guide (#1072). Facts: docs/research/mixer-recording/soundcraft-ui24r.md.
export const UI24R_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record a Soundcraft Ui24R to an iPhone or iPad?",
    a: "Soundcraft doesn't say: not tested yet. Harman says a Mac sees the Ui24R as an audio interface with no driver, but no Soundcraft or Harman document names the iPhone or iPad.",
  },
  {
    q: "Can the Ui24R multitrack record without a computer?",
    a: "Yes, up to 22 tracks to a USB drive in the front MEDIA - REC socket. Harman asks for a FAT32 drive of 32 GB or less that reads and writes at 25 MB/s or faster. The file format is not stated by Soundcraft; a 2017 review says WAV or FLAC, set in the settings page.",
  },
  {
    q: "Does the Ui24R need a driver on a Mac?",
    a: "No. Harman: \"Yes, the Ui24R is Core Audio compliant. If you are using a Mac, the Mac will recognize the Ui24R as an Audio Interface automatically.\" Windows needs the Soundcraft Multi-Channel USB Audio Driver, V3.20 or later.",
  },
  {
    q: "Which USB channel is each input on the Ui24R?",
    a: "The map is fixed: USB 1-2 are the Master L/R, USB 3-10 are AUX 1-8, and USB 11-32 are inputs 1-22. So input 1 arrives on USB 11. No USB send patching is needed or possible.",
  },
  {
    q: "Are Ui24R recordings pre or post fader?",
    a: "Pre-fader. Harman: \"Recording from channels will only be pre-fader, pre-processing.\" Harman's quote comes from an article that covers the Si and Ui series. The preamp gain is in the recording; the channel EQ, dynamics and fader are not (our reading). For a post-fader or processed track, use an AUX set to POST and POST PROC as a group, and record its USB channel (3-10).",
  },
  {
    q: "What sample rate does the Ui24R record at?",
    a: "48 kHz over USB to a computer. Harman says Pro Tools \"Sample Rate NEEDS to be 48kHz\". The sample rate of the onboard USB drive recorder and the USB bit depth are not stated by Soundcraft.",
  },
  {
    q: "How do I play a Ui24R recording back for a virtual soundcheck?",
    a: "From a computer, go to SETTINGS > PATCHING > CHANNELS, pick USB DAW 1-16 or 17-32 at the top, and use Patch 1:1 or patch each channel. From the USB drive, turn on the Soundcheck patch in SETTINGS > PATCHING > OVERVIEW or on the PLAYER > MULTITRACK page.",
  },
];

// The questions on the Allen & Heath CQ guide (#1070). Facts: docs/research/mixer-recording/ah-cq.md.
export const AH_CQ_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record an Allen & Heath CQ to an iPhone or iPad?",
    a: "An iPad, yes, says Allen & Heath staff: the CQ's USB-B audio interface is class compliant. Set Stream Mode to Multitrack first, or the iPad sees only 2 channels. Allen & Heath doesn't name the iPhone, and we haven't tested either yet.",
  },
  {
    q: "Why does my CQ show only 2 channels?",
    a: "Stream Mode is set to Stereo. Go to CONFIG > Digital Audio > USB/SD and set Stream Mode to Multitrack. Stereo sends only one stereo pair, for phones and tablets that can't take more.",
  },
  {
    q: "How many channels does a CQ send over USB?",
    a: "The CQ-12T sends 16 channels to the computer and takes 16 back. The CQ-18T sends 24 and takes 22. The CQ-20B sends 24 and takes 24. All three run at 48 or 96 kHz.",
  },
  {
    q: "Can the CQ multitrack record without a computer?",
    a: "Yes, to an SD card (SDHC, up to 32 GB, UHS-I, class 10). The CQ-12T records 16 tracks. The CQ-18T and CQ-20B record 24 at 48 kHz, or 16 at 96 kHz. Each track is a mono 24-bit WAV file. A USB stick in the USB-A port records only stereo.",
  },
  {
    q: "Which USB channel is each input on the CQ?",
    a: "Mono inputs are fixed: input 1 goes to USB 1, input 7 to USB 7, and so on. The last few USB channels are stereo pairs you choose in CONFIG > Digital Audio > USB/SD > Channel Assignment. The last pair is the main mix (Main LR) out of the box.",
  },
  {
    q: "Are CQ recordings pre or post fader?",
    a: "Pre-fader, users report. One setting, Source Point, chooses how much channel processing goes to USB and SD: none, some or all. Users say there's no post-fader option, and we couldn't confirm one. To record a mix after the faders, put Main LR or an output mix in one of the stereo pairs.",
  },
  {
    q: "How do I play a CQ recording back for a virtual soundcheck?",
    a: "Go to CONFIG > INPUTS, select the channels, and set Input Source to USB/SD. The channels then play from the computer over USB, or from the SD card while the CQ is playing a multitrack.",
  },
];

// The questions on the PreSonus StudioLive Series III guide (#1077). Facts: docs/research/mixer-recording/presonus-studiolive-iii.md.
export const STUDIOLIVE_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record a StudioLive Series III to an iPhone or iPad?",
    a: "PreSonus says its USB mixers work with iPads and iPhones for recording, with no driver, and lists the StudioLive Series III. That is a general statement, not a test of each device, and we haven't tested a StudioLive yet. In 2021 some iPad apps crashed on launch with all 64 channels; PreSonus says the two it named have since been fixed. If yours crashes, try Compatibility Mode (our advice).",
  },
  {
    q: "Can a StudioLive Series III record without a computer?",
    a: "The consoles can: 34 tracks (channels 1-32 and a stereo mix) to an SD or SDHC card of up to 32 GB, formatted FAT32. PreSonus asks for Class 10 U3 cards and says SDXC cards are not supported. The rack mixers record only stereo to SD.",
  },
  {
    q: "Which USB channel is each input on a StudioLive?",
    a: "By default, USB 1-32 carry channels 1-32, and on the 32-channel models USB 39-40 carry the main mix. In Compatibility Mode the main mix moves to USB 33-34. You can change any USB channel in Home > Audio Routing > Digital Patching > USB Sends.",
  },
  {
    q: "Why does my StudioLive show 64 USB channels but only mix 32?",
    a: "The 64 x 64 is a pool of USB slots to choose from, not 64 mixing channels. The 32-channel models mix 32 inputs; only the 64S mixes 64. Compatibility Mode cuts USB to 34 x 34 for computers that struggle with 64.",
  },
  {
    q: "Are StudioLive recordings pre or post fader?",
    a: "PreSonus doesn't say where the default USB and SD input tracks are taken. Record a short test, move a fader and the EQ, and listen (our advice). For a known point, send a FlexMix set to Pre 1, Pre 2 or Post to a spare USB channel.",
  },
  {
    q: "What sample rate does a StudioLive Series III record at?",
    a: "48 kHz (the default) or 44.1 kHz, set in Home > System > Sample Rate. The converters are 24-bit; PreSonus doesn't state the USB bit depth.",
  },
  {
    q: "How do I play a StudioLive recording back for a virtual soundcheck?",
    a: "Over USB, press and hold a channel's USB Input Source button and press the Select button of each channel to play back. From the SD card, press Soundcheck, pick the session and press Recall. Press Soundcheck again, or switch the channels back to Analog, for the show.",
  },
];

// The questions on the Allen & Heath SQ guide (#1068). Facts: docs/research/mixer-recording/ah-sq.md.
export const AH_SQ_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I record an Allen & Heath SQ to an iPhone or iPad?",
    a: "Not tested yet. Allen & Heath says the SQ's USB-B interface needs no driver on any device that supports class-compliant audio, but it doesn't name the iPhone or iPad. A Mac works with no driver.",
  },
  {
    q: "Can an SQ multitrack record without a computer?",
    a: "Yes, with SQ-Drive: up to 16 tracks at 96 kHz or 32 at 48 kHz, one 24-bit WAV per track, to a drive in the SQ's USB-A socket. Use a fast external hard drive or SSD; Allen & Heath says most USB sticks are too slow. Only the USB channels you patched are recorded.",
  },
  {
    q: "How many channels does the SQ send over USB?",
    a: "32 to the computer and 32 back, at 48 or 96 kHz. Set the rate in Setup > Audio > Digital I/O > USB Sample Rate. A Mac needs no driver; Windows needs Allen & Heath's ASIO driver for all 32.",
  },
  {
    q: "Which USB channel is each input on the SQ?",
    a: "You choose, in the I/O screen. After a Standard reset (in Setup, on the Role tab), USB 1-2 carry the main mix and the channels follow. Other setups may differ, and Allen & Heath doesn't say which channel lands on USB 3, so check I/O before the show.",
  },
  {
    q: "Are SQ recordings pre or post fader?",
    a: "You choose. The channel direct outs have one Direct Out Source for every channel, from Post Preamp (only the preamp gain) to Post Delay (all processing), and switches for following the faders and mutes. For tracks you can mix later, pick Post Preamp and leave the fader and mute following off (our advice).",
  },
  {
    q: "How do I play an SQ recording back for a virtual soundcheck?",
    a: "Send each track out on its own USB output in your recording app. On the SQ, press I/O > Inputs > Input Channel and patch the USB sockets to the channels. Save that patch in an input patch library (press Library) so you can switch between the stage and USB in one step.",
  },
];

// The questions on the Behringer XR12 / XR16 and Midas MR12 guide (#1067). Facts:
// docs/research/mixer-recording/xr12-xr16-mr12.md. These mixers have no USB audio, so the answers say so plainly.
export const XR12_GUIDE_FAQS: readonly Faq[] = [
  {
    q: "Can I multitrack record a Behringer XR12, XR16 or Midas MR12?",
    a: "No. These mixers have no USB audio interface, so they can't send each channel to a computer, iPhone or iPad. They record only a stereo mix (2 tracks) to a USB flash drive. To record every channel on its own track, use an XR18 or MR18.",
  },
  {
    q: "Can I record an XR12, XR16 or MR12 on an iPhone or iPad?",
    a: "Not the channels: there is no USB audio to send. The X AIR and M AIR apps (tablet, phone and computer) only control the mixer, over Wi-Fi or a network cable. To keep a recording, plug a USB flash drive into the mixer and record the stereo mix.",
  },
  {
    q: "What file does the XR12, XR16 or MR12 record to the USB stick?",
    a: "A stereo WAV file. Behringer gives the XR12 as 16-bit at 44.1 or 48 kHz. Midas gives the MR12 as 16-bit at 44.1 or 48 kHz, matching the mixer's sample rate. For the XR16, Behringer says only \"stereo files\".",
  },
  {
    q: "How do I change the sample rate on an XR12, XR16 or MR12?",
    a: "In the app, open the Setup page and the Audio/MIDI tab. The mixer runs at 48 kHz unless you change it to 44.1 kHz. Pull down or mute the main fader (Main LR) first, or the speakers may pop.",
  },
  {
    q: "Can I do a virtual soundcheck with an XR12, XR16 or MR12?",
    a: "Not with separate tracks. The mixer plays a stereo file from the USB stick back into one stereo channel, so you hear the whole mix, not each instrument on its own fader.",
  },
];

// The X32 guide's Method A, card out blocks of 8: the page lists these steps and its HowTo data repeats them.
export const X32_METHOD_A: readonly { name: string; text: string }[] = [
  { name: "Open card out", text: "Press ROUTING and go to the card out tab." },
  { name: "Pick four blocks", text: "Turn encoders 1 to 4 to pick the block of 8 for card outputs 1-8, 9-16, 17-24 and 25-32." },
  { name: "Confirm", text: "Press each encoder to confirm." },
];

// The per-mixer guides, in the order the sitemap and llms.txt list them. The template test
// (tests/mixerGuidePages.test.ts) checks each one.
export const MIXER_GUIDES: readonly MixerGuide[] = [
  {
    slug: "x32",
    path: "/guides/record/x32",
    pageKey: "guideX32",
    short: "X32",
    mixer: "Behringer X32",
    pick: "With a USB card, up to 32 channels to a computer. With an X-LIVE card, up to 32 to SD cards, no computer needed. iPhone and iPad: not tested yet.",
    description:
      "Multitrack record an X32 with an X-USB or X-LIVE card, to a computer or to SD cards (iPhone not tested yet): settings, card out blocks and tap points.",
    published: "2026-11-06",
    productPage: "/mixers/x32",
    faqs: X32_GUIDE_FAQS,
    faqsName: "X32_GUIDE_FAQS",
    sources: [
      "https://cdn-media.empowertribe.com/651b847b3f4443c2b64487af85e1d74a/8849630134302.pdf",
      "https://cdn-media.empowertribe.com/e452c7959c0d4002908c23044a9558a7/8849399545886.pdf",
      "https://cdn-media.empowertribe.com/2d70beac1fae4381ad62fe8a432ff6fd/QSG_BE_0606-ABU_X-LIVE_WW.pdf",
      "https://cdn-media.empowertribe.com/bb23e8fae45174d1ffa9702b6fdaf040/X32-firmware-4.15_release-notes.pdf",
      "https://www.behringer.com/en/products/0603-ACE",
      "https://www.behringer.com/en/products/0606-abu",
      "https://www.behringer.com/en/products/0606-ABV",
      "https://behringer.world/viewtopic.php?p=4722",
      "https://behringer.world/viewtopic.php?p=8704",
      "https://behringer.world/viewtopic.php?p=9167",
      "https://behringer.world/viewtopic.php?p=10364",
      "https://survivethegig.com/x32-firmware-version-4-00/",
    ],
    campaign: "site-guide-x32",
    tapPick: "a Local block (the raw inputs) on card out",
  },
  {
    slug: "xr18",
    path: "/guides/record/xr18",
    pageKey: "guideXR18",
    short: "XR18",
    mixer: "Behringer XR18 or Midas MR18",
    pick: "18 channels over USB to a computer, iPad or iPhone. Records no multitrack by itself.",
    description:
      "Multitrack record an XR18 or MR18 over USB: to a computer, an iPad or an iPhone. Settings, the USB routing grid, virtual soundcheck and tap points.",
    published: "2026-11-06",
    productPage: "/mixers/xr18",
    faqs: XR18_GUIDE_FAQS,
    faqsName: "XR18_GUIDE_FAQS",
    sources: [
      "https://cdn-media.empowertribe.com/ffe0de45e14541f797928d639a8933b2/M_BE_0605-AAA_X-AIR_EN.pdf",
      "https://www.behringer.com/en/products/0605-AAD",
      "https://cdn-media.empowertribe.com/f4e89140f9994eed93e4f2a4e086c578/M_MI_0605-AAF_MR18-MR12_EN.pdf",
    ],
    campaign: "site-guide-xr18",
    tapPick: "the Input tap on each USB send",
  },
  {
    slug: "qu",
    path: "/guides/record/qu",
    pageKey: "guideQu",
    short: "Qu",
    mixer: "Allen & Heath Qu",
    pick: "Up to 32 channels over USB (24 on the Qu-16). Records by itself: the new Qu to an SD card, the Qu Classic to a USB drive. iPhone and iPad: not tested yet.",
    description:
      "Multitrack record a Qu-16, Qu-24, Qu-32, Qu-SB, Qu-Pac or Qu-5/6/7 over USB, or to an SD card or drive: settings, routing, tap points. iPad not tested yet.",
    published: "2026-11-07",
    hubRows: 2,
    faqs: QU_GUIDE_FAQS,
    faqsName: "QU_GUIDE_FAQS",
    sources: [
      "https://support.allen-heath.com/hc/en-gb/articles/48350897327889-Qu-Qu-Drive-and-USB-audio",
      "https://support.allen-heath.com/hc/en-gb/articles/48350711389457-Qu-Patching",
      "https://support.allen-heath.com/hc/en-gb/articles/48350696072593-Qu-Mixer-Setup",
      "https://support.allen-heath.com/hc/en-gb/articles/48350799066257-Qu-Routing",
      "https://support.allen-heath.com/hc/en-gb/articles/48350755314705-Qu-Processing",
      "https://support.allen-heath.com/hc/en-gb/articles/48348179394705-Qu-Connections",
      "https://support.allen-heath.com/hc/en-gb/articles/39796618451729-Qu-5-6-7-Getting-Started-Guide",
      "https://support.allen-heath.com/hc/en-gb/articles/52578169245073-Qu-3-Getting-Started-Guide",
      "https://www.allen-heath.com/hardware/qu/qu-5/",
      "https://www.allen-heath.com/hardware/qu/qu-6-qu-6d/",
      "https://support.allen-heath.com/hc/en-gb/articles/4402943975569-Qu-Classic-Qu-Drive-USB-Audio",
      "https://support.allen-heath.com/hc/en-gb/articles/4403019846033-Qu-Classic-How-do-I-route-audio-to-and-from-my-Qu-mixer-and-a-DAW",
      "https://support.allen-heath.com/hc/en-gb/articles/4402944132753-Qu-Classic-Understanding-Qu-Drive-and-USB-devices",
      "https://support.allen-heath.com/hc/en-gb/articles/41599046080913-Qu-SB-Getting-Started-Guide",
      "https://support.allen-heath.com/hc/en-gb/articles/41402982389777-Qu-Pac-Getting-Started-Guide",
      "https://www.allen-heath.com/hardware/qu/qu-classic/",
      "https://www.allen-heath.com/hardware/qu/qu-classic/qu-16/",
      "https://www.allen-heath.com/hardware/qu/qu-classic/qu-sb/",
      "https://forums.allen-heath.com/t/qu-usb-channel-i-o-clarification/12192",
    ],
    campaign: "site-guide-qu",
    tapPick: "Qu Classic: the channel Insert Send (the factory default, straight after the preamp). New Qu: the input direct outs, with the Direct Out Source set to the point you want",
  },
  {
    slug: "zoom-l12",
    path: "/guides/record/zoom-l12",
    pageKey: "guideZoomL12",
    short: "L-12 and L-20",
    mixer: "Zoom LiveTrak L-12 or L-20",
    pick: "14 channels (L-12) or 22 (L-20) over USB. Records every channel by itself to an SD card. Zoom names the iPhone and iPad (Lightning adapter; USB-C not tested yet).",
    description:
      "Multitrack record a Zoom LiveTrak L-12 or L-20 to a computer, an iPhone or iPad (named by Zoom) or its SD card: rear switches, USB order and tap points.",
    published: "2026-11-07",
    faqs: ZOOM_L12_GUIDE_FAQS,
    faqsName: "ZOOM_L12_GUIDE_FAQS",
    sources: [
      "https://zoomcorp.com/media/documents/E_L-12_4.pdf",
      "https://zoomcorp.com/media/documents/E_L-20_OperationManual.pdf",
      "https://zoomcorp.com/media/documents/E_L-20R.pdf",
      "https://zoomcorp.com/media/documents/L-12_L-20_L-20R_Driver_V2manual_en.pdf",
      "https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/",
      "https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-20/",
      "https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/l-12-support/",
    ],
    campaign: "site-guide-zoom-l12",
    tapPick: "the fixed tap (after the compressor, before the EQ), with the COMP knob at zero",
  },
  {
    slug: "mackie-dl32r",
    path: "/guides/record/mackie-dl32r",
    pageKey: "guideMackieDL32R",
    short: "DL32R",
    mixer: "Mackie DL32R",
    pick: "32 channels over USB to a computer. Records up to 32 tracks by itself to a USB hard drive. iPad: yes, with a camera adapter. iPhone: not tested yet.",
    description:
      "Multitrack record a Mackie DL32R over USB to a computer or iPad, or to a USB hard drive: settings, I/O Patch routing, tap points. iPhone not tested yet.",
    published: "2026-11-07",
    faqs: DL32R_GUIDE_FAQS,
    faqsName: "DL32R_GUIDE_FAQS",
    sources: [
      "https://mackie.com/img/file_resources/DL32R_OM.pdf",
      "https://mackie.com/img/file_resources/DL32R_SS.pdf",
      "https://help.mackie.com/hc/en-us/articles/14288356150159-Master-Fader-Downloads",
      "https://www.ambertech.com.au/Documents/Master%20Fader_V5_0_RG-compressed.pdf",
    ],
    campaign: "site-guide-mackie-dl32r",
    tapPick: "Mic Pre (the default on each USB slot, before trim, HPF and EQ)",
  },
  {
    slug: "wing",
    path: "/guides/record/wing",
    pageKey: "guideWing",
    short: "WING",
    mixer: "Behringer WING, WING Compact or WING Rack",
    pick: "Up to 48 channels over USB to a computer. With a WING-LIVE card, 64 channels to SD cards, no computer needed. iPhone and iPad: not tested yet.",
    description:
      "Multitrack record a Behringer WING over USB or to its WING-LIVE SD cards: settings, per-slot routing, tap points, playback. iPhone not tested yet.",
    published: "2026-11-07",
    faqs: WING_GUIDE_FAQS,
    faqsName: "WING_GUIDE_FAQS",
    sources: [
      "https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf",
      "https://cdn-media.empowertribe.com/c5ff61e785861bc4f4fe7bec6839f7ed/BE_0603-AFC_WING_QSG_Multi-Language.pdf",
      "https://cdn-media.empowertribe.com/2106004e217b8eb2639d93672823eef5/WING_Remote-Protocols-3.1-03.pdf",
      "https://www.behringer.com/en/products/0603-AEN",
      "https://behringer.world/viewtopic.php?p=13151",
    ],
    campaign: "site-guide-wing",
    tapPick: "the raw inputs (Local In, AES50) on the USB slots, or a User Signal at the channel's INPUT tap",
  },
  {
    slug: "m32",
    path: "/guides/record/m32",
    pageKey: "guideM32",
    short: "M32",
    mixer: "Midas M32",
    pick: "With a DN32-USB card, 32 channels to a computer. With a DN32-LIVE card, records to SD cards, no computer needed. iPhone and iPad: not tested yet.",
    description:
      "Multitrack record a Midas M32, M32R or M32C with a DN32-USB or DN32-LIVE card, to a computer or SD cards (iPhone not tested yet): settings, routing, taps.",
    published: "2026-11-07",
    productPage: "/mixers/x32",
    faqs: M32_GUIDE_FAQS,
    faqsName: "M32_GUIDE_FAQS",
    sources: [
      "https://cdn-media.empowertribe.com/5a30d52258104865a4392b99550ee1f9/M32_M_EN.pdf",
      "https://cdn-media.empowertribe.com/019427b1584f42aab500bf0dc082ace5/QSG_MI_0603-AEO_M32%20LIVE.pdf",
      "https://www.sgssistemas.lv/uploads/resources/107/en/klark-teknik-dn32-usb-p0bif-product-information-document.pdf",
      "https://leisuretec.co.uk/cdn/shop/files/M32R_LIVE_Quick_Start_Guide.pdf",
      "https://www.manualslib.com/manual/819691/Midas-M32.html?page=33",
      "https://www.manualslib.com/manual/819691/Midas-M32.html?page=34",
      "https://cdn-media.empowertribe.com/e452c7959c0d4002908c23044a9558a7/8849399545886.pdf",
      "https://cdn-media.empowertribe.com/2d70beac1fae4381ad62fe8a432ff6fd/QSG_BE_0606-ABU_X-LIVE_WW.pdf",
      "https://behringer.world/viewtopic.php?p=8704",
      "https://www.controlbooth.com/goto/post?id=417239",
    ],
    campaign: "site-guide-m32",
    tapPick: "a Local block (the raw inputs) on card out",
  },
  {
    slug: "mackie-dl32s",
    path: "/guides/record/mackie-dl32s",
    pageKey: "guideMackieDL32S",
    short: "DL32S",
    mixer: "Mackie DL32S or DL16S",
    pick: "32 channels over USB (16 on the DL16S) to a computer. Records nothing by itself. iPhone and iPad: not tested yet.",
    description:
      "Multitrack record a Mackie DL32S or DL16S over USB to a computer (iPhone and iPad not tested yet): 48 kHz, I/O Patch USB routing, virtual soundcheck, taps.",
    published: "2026-11-07",
    faqs: MACKIE_DL32S_GUIDE_FAQS,
    faqsName: "MACKIE_DL32S_GUIDE_FAQS",
    sources: [
      "https://mackie.com/img/file_resources/DL16S_DL32S_OM.pdf",
      "https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf",
      "https://mackie.com/img/file_resources/DL16SE_DL32SE_OM.pdf",
      "https://mackie.com/img/file_resources/DL32R_OM.pdf",
      "https://help.mackie.com/hc/en-us/articles/14288356150159-Master-Fader-Downloads",
      "https://www.ambertech.com.au/Documents/Master%20Fader_V5_0_RG-compressed.pdf",
    ],
    campaign: "site-guide-mackie-dl32s",
    tapPick: "Mic Pre, the default on the I/O Patch USB tab (after the analog gain, before the Digital Trim and high pass filter)",
  },
  {
    slug: "ui24r",
    path: "/guides/record/ui24r",
    pageKey: "guideUi24r",
    short: "Ui24R",
    mixer: "Soundcraft Ui24R",
    pick: "32 channels over USB to a computer. Records 22 channels by itself to a USB stick. iPhone and iPad: not stated by Soundcraft, not tested yet.",
    description:
      "Multitrack record a Soundcraft Ui24R to a computer or USB drive: the fixed USB map, 48 kHz, playback, the tap point. iPhone and iPad not tested yet.",
    published: "2026-11-07",
    faqs: UI24R_GUIDE_FAQS,
    faqsName: "UI24R_GUIDE_FAQS",
    sources: [
      "https://www.soundcraft.com/en-US/product_documents/ui24r_manual_v1-0_web-pdf",
      "https://www.soundcraft.com/en-US/product_documents/ui24r_v2-0_user_guide_addendum-pdf",
      "https://harman.helpjuice.com/sc-ui-series/ui24r-core-audio-compliance",
      "https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-multitrack-recording-with-a-daw",
      "https://harman.helpjuice.com/en_US/sc-ui-series/ui-series-compatibility-with-macos-sequoia",
      "https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-cascade-mode-does-not-allow-more-daw-channels",
      "https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-usb-direct-recording-requirements",
      "https://harman.helpjuice.com/en_US/sc-ui-series/sd-and-micro-sd-for-recording-on-the-ui24r",
      "https://harman.helpjuice.com/en_US/sc-ui-series/creating-playable-multitrack-session-from-imported-audio-files-on-ui24r-with-usb-stick",
      "https://harman.helpjuice.com/en_US/sc-ui-series/recording-from-groups-to-achieve-post-fader-processing-and-effect",
      "https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-record-track-labels",
      "https://www.soundonsound.com/reviews/soundcraft-ui24r",
    ],
    campaign: "site-guide-ui24r",
    tapPick: "the fixed tap (straight after the mic preamp, before processing and the fader); there is nothing to set",
  },
  {
    slug: "ah-cq",
    path: "/guides/record/ah-cq",
    pageKey: "guideAhCq",
    short: "CQ",
    mixer: "Allen & Heath CQ",
    description:
      "Multitrack record an Allen & Heath CQ-12T, CQ-18T or CQ-20B to a computer, iPad or SD card: Stream Mode, the fixed USB map, playback, the Source Point.",
    published: "2026-11-07",
    faqs: AH_CQ_GUIDE_FAQS,
    faqsName: "AH_CQ_GUIDE_FAQS",
    sources: [
      "https://support.allen-heath.com/hc/en-gb/articles/48456934886545-CQ-CONFIG-screens",
      "https://support.allen-heath.com/hc/en-gb/articles/48457057592721-CQ-HOME-screens",
      "https://support.allen-heath.com/hc/en-gb/articles/48456861200017-CQ-How-to",
      "https://support.allen-heath.com/hc/en-gb/articles/31464715078929-CQ-USB-B-Routing",
      "https://support.allen-heath.com/hc/en-gb/articles/19338440353425-CQ-Multitrack-streaming-using-CQ",
      "https://support.allen-heath.com/hc/en-gb/articles/19853352600337-CQ-Multitrack-Recording-and-Playback-from-SD-Card",
      "https://support.allen-heath.com/hc/en-gb/articles/48456773235473-CQ-Connections",
      "https://www.allen-heath.com/hardware/cq/cq-12t/",
      "https://www.allen-heath.com/hardware/cq/cq-18t/",
      "https://www.allen-heath.com/hardware/cq/cq-20b/",
      "https://forums.allen-heath.com/t/usb-interface/16038",
      "https://forums.allen-heath.com/t/13551",
      "https://forums.allen-heath.com/t/14728",
      "https://forums.allen-heath.com/t/post-fader-as-global-source-point-for-usb/25766",
      "https://forums.allen-heath.com/t/recording-to-ipad-garageband/15620",
    ],
    pick: "16 channels over USB (24 on the CQ-18T and CQ-20B) to a computer. Records as many by itself to an SD card. iPad: yes, says Allen & Heath staff. iPhone: not tested yet.",
    campaign: "site-guide-ah-cq",
    tapPick: "the Source Point in CONFIG > Digital Audio > USB/SD, one setting for every channel (pick how much processing you want; users report no post-fader option)",
  },
  {
    slug: "presonus-studiolive-iii",
    path: "/guides/record/presonus-studiolive-iii",
    pageKey: "guideStudioLive",
    short: "StudioLive",
    mixer: "PreSonus StudioLive Series III",
    pick: "Up to 64 channels over USB (16R: 18 or more). The consoles record 34 tracks by themselves to an SD card; the racks record stereo only. iPhone: named by PreSonus in a general statement, not tested by us.",
    description:
      "Multitrack record a PreSonus StudioLive Series III over USB or to an SD card: 64 or 34 channels, routing, playback, tap points. iPhone not tested yet.",
    published: "2026-11-07",
    faqs: STUDIOLIVE_GUIDE_FAQS,
    faqsName: "STUDIOLIVE_GUIDE_FAQS",
    sources: [
      "https://www.fmicassets.com/Damroot/Original/10153/OM_StudioLive-Series-III-Console-Mixers_EN.pdf",
      "https://www.fmicassets.com/Damroot/Original/10154/TS_studiolive32s_EN.pdf",
      "https://www.fmicassets.com/Damroot/Original/10154/SUP_StudioLive-Series-III-Comaparison-Chart.pdf",
      "https://pae-web.presonusmusic.com/downloads/products/pdf/StudioLive_Series_III_Rack_Mixers_OwnersManual_EN_13102022.pdf",
      "https://support.presonus.com/hc/en-us/articles/360059975732-PreSonus-Hardware-iOS-iPadOS-Compatibility",
      "https://support.presonus.com/hc/en-us/articles/360062440371-StudioLive-Series-III-Can-my-StudioLive-utilize-all-64-USB-AVB-channels",
      "https://support.presonus.com/hc/en-us/articles/11189120184845-Compatibility-Mode-in-Universal-Control-v4",
      "https://support.presonus.com/hc/en-us/articles/360052084812-Series-III-Interface-Mode-WDM-Primer",
      "https://support.presonus.com/hc/en-us/articles/4404701016973-StudioLive-Series-III-Console-SD-Card-Recording-and-Playback",
      "https://support.presonus.com/hc/en-us/articles/115000219906",
      "https://support.presonus.com/hc/en-us/articles/360056572451",
      "https://support.presonus.com/hc/en-us/articles/360050481392-StudioLive-Series-III-Rack-Mount-Mixers-SD-Card-Stereo-Recording-and-Playback",
      "https://support.presonus.com/hc/en-us/articles/7059582068493-Capture-USB-Recording-Playback-Setup-Series-III",
      "https://support.presonus.com/hc/en-us/articles/7428384416269",
    ],
    campaign: "site-guide-presonus-studiolive-iii",
    tapPick: "the default Inputs on USB 1-32 (PreSonus doesn't say where on the channel they are taken), or a FlexMix at Pre 1, Pre 2 or Post for a known point",
  },
  {
    slug: "ah-sq",
    path: "/guides/record/ah-sq",
    pageKey: "guideAhSq",
    short: "SQ",
    mixer: "Allen & Heath SQ",
    description:
      "Multitrack record an Allen & Heath SQ-5, SQ-6 or SQ-7 over USB or to SQ-Drive: settings, patching, playback, taps. iPhone and iPad not tested yet.",
    published: "2026-11-07",
    faqs: AH_SQ_GUIDE_FAQS,
    faqsName: "AH_SQ_GUIDE_FAQS",
    sources: [
      "https://support.allen-heath.com/hc/en-gb/articles/45947079593105-SQ-SQ-Drive-and-USB-B",
      "https://support.allen-heath.com/hc/en-gb/articles/45261631285009-SQ-Connections-and-Patching",
      "https://support.allen-heath.com/hc/en-gb/articles/45946654916753-SQ-Routing",
      "https://support.allen-heath.com/hc/en-gb/articles/4402940459537-SQ-Basic-Signal-Path-Diagrams-Input-Group-LR-Aux-Matrix",
      "https://support.allen-heath.com/hc/en-gb/articles/45947065818769-SQ-Setup",
      "https://support.allen-heath.com/hc/en-gb/articles/45946563062929-SQ-Processing",
      "https://support.allen-heath.com/hc/en-gb/articles/45947235418385-SQ-Mix-System-Reset",
      "https://support.allen-heath.com/hc/en-gb/articles/4402940155793-SQ-Understanding-SQ-USB-recording-and-playback",
      "https://support.allen-heath.com/hc/en-gb/articles/4402941921553-SQ-Virtual-Soundcheck-using-the-USB-B-connection",
      "https://support.allen-heath.com/hc/en-gb/articles/4402939458193-SQ-Troubleshooting-issues-with-the-SQ-USB-B-interface",
      "https://support.allen-heath.com/hc/en-gb/articles/43757630905361-SQ-Firmware-Release-Notes",
      "https://support.allen-heath.com/hc/en-gb/articles/41332471203985-SQ-5-SQ-6-SQ-7-Getting-Started-Guide",
    ],
    pick: "32 channels over USB to a computer, at 48 or 96 kHz. Records by itself to a fast USB drive: 16 channels at 96 kHz or 32 at 48 kHz. iPhone and iPad: not tested yet.",
    campaign: "site-guide-ah-sq",
    tapPick: "Direct Out Source set to Post Preamp (only the preamp gain, before the filter, EQ and fader), in Routing > Dir Out",
  },
  {
    slug: "xr12-xr16-mr12",
    path: "/guides/record/xr12-xr16-mr12",
    pageKey: "guideXR12",
    short: "XR12, XR16 or MR12",
    mixer: "Behringer XR12, XR16 or Midas MR12",
    description:
      "The XR12, XR16 and MR12 can't multitrack: no USB audio. They record a stereo WAV to a USB stick. How to do that, and which mixer records every channel.",
    published: "2026-11-07",
    faqs: XR12_GUIDE_FAQS,
    faqsName: "XR12_GUIDE_FAQS",
    sources: [
      "https://cdn-media.empowertribe.com/ffe0de45e14541f797928d639a8933b2/M_BE_0605-AAA_X-AIR_EN.pdf",
      "https://www.behringer.com/en/products/0605-AAB",
      "https://www.behringer.com/en/products/0605-AAC",
      "https://cdn-media.empowertribe.com/f4e89140f9994eed93e4f2a4e086c578/M_MI_0605-AAE_MR18-MR12_EN.pdf",
      "https://www.midasconsoles.com/en/products/0605-AAE",
    ],
    campaign: "site-guide-xr12-xr16-mr12",
    tapPick: "none for multitrack: these mixers record only a stereo mix to a USB stick, and neither maker says where that mix is taken",
    noMultitrack: true,
  },
];
