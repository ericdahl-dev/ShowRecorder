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
  },
  {
    name: "Behringer WING, WING Rack and WING Compact",
    usb: "2 x 2 up to 48 x 48, 24-bit. The console runs at 44.1 or 48 kHz; USB at 44.1 kHz is not stated.",
    onboard: "WING-LIVE card: 64 channels on two SD cards. Front USB stick: 2 or 4 tracks.",
    mac: "Users report it works with no driver; Behringer doesn't say.",
    ipad: "Reports differ; not tested yet.",
    iphone: "Not tested yet.",
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
    note: "MR12 facts come from retailers, not Midas.",
    usb: "No USB audio interface, so no multitrack over USB.",
    onboard: "Stereo WAV, 2 tracks, to a USB stick.",
    mac: "No multitrack: no USB audio interface.",
    ipad: "No multitrack: no USB audio interface.",
    iphone: "No multitrack: no USB audio interface.",
  },
  {
    name: "Allen & Heath SQ-5, SQ-6, SQ-7 and SQ-Rack",
    usb: "32 in and 32 out, 48 or 96 kHz.",
    onboard: "SQ-Drive: 16 channels at 96 kHz or 32 at 48 kHz, 24-bit WAV, to a fast USB drive (the maker says most sticks are too slow). Or stereo.",
    mac: "Class compliant (maker).",
    ipad: "Not named. Allen & Heath says no driver is needed on any system that supports class-compliant audio. Not tested yet.",
    iphone: "Not named. Allen & Heath says no driver is needed on any system that supports class-compliant audio. Not tested yet.",
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
    ipad: "Class compliant (PreSonus support); the 64 x 64 mode crashes some iPad apps.",
    iphone: "PreSonus lists the iPhone in a general statement; not tested by us.",
  },
  {
    name: "Mackie DL32S, DL16S and DL32SE",
    usb: "32 in and 32 out (DL16S: 16 x 16), 48 kHz.",
    onboard: "None.",
    mac: "Class compliant; current macOS not listed by Mackie.",
    ipad: "Not tested yet.",
    iphone: "Not tested yet.",
  },
  {
    name: "Mackie DL32R",
    usb: "32 in and 32 out, 48 kHz.",
    onboard: "Up to 32 tracks with current firmware (older units likely show 24 until updated), 16 or 24-bit at 48 kHz, as one multichannel WAV per take, split into files under 2 GB, to a spinning USB hard drive formatted by the DL32R (no thumb drive, no hub). The drive and a computer can't be used at the same time.",
    mac: "Class compliant; current macOS not listed by Mackie.",
    ipad: "Yes, with a camera adapter (manual).",
    iphone: "Not tested yet.",
  },
  {
    name: "Zoom LiveTrak L-12, L-20 and L-20R",
    usb: "L-12: 14 in, 4 out. L-20: 22 in, 4 out. 44.1 or 48 kHz only; no USB audio at 96 kHz.",
    onboard: "SD card: 14 tracks (L-12) or 22 (L-20), WAV up to 24-bit 96 kHz (L-12: 12 tracks at 96 kHz).",
    mac: "Install Zoom's driver.",
    ipad: "Yes, named by Zoom, with the rear Class Compliant Mode switch on (we suggest setting it before power-on) and a Lightning camera adapter. USB-C: not tested yet.",
    iphone: "Yes, named by Zoom, with the rear Class Compliant Mode switch on (we suggest setting it before power-on) and a Lightning camera adapter. USB-C: not tested yet.",
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
    a: "Often, if the mixer sends its channels over USB as a class-compliant interface. Some makers say their mixers work with an iPad or iPhone; the table shows which, and says not tested yet where nobody has checked. The XR12, XR16 and Avantis have no USB audio interface, so they can't.",
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
};

// "<mixer> USB multitrack recording: settings and routing - ShowRecorder", the <title> of every mixer guide.
export function guideTitle(short: string): string {
  return `${short} USB multitrack recording: settings and routing - ShowRecorder`;
}

// "How to multitrack record a Behringer X32", "... an Allen & Heath Qu": the H1, the article headline and the
// llms.txt line of every mixer guide.
export function guideHeadline(mixer: string): string {
  return `How to multitrack record ${/^[AEIOU]/.test(mixer) ? "an" : "a"} ${mixer}`;
}

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
];
