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

import type { Faq } from "@/lib/mixerFaqs";

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
    note: "Also the X18. Midas's manual confirms the MR18's USB specs; its iPad support comes only from retailers.",
    usb: "18 in and 18 out, or 2 x 2, at 44.1 or 48 kHz (48 by default).",
    onboard: "None for multitrack.",
    mac: "Works with no driver (maker).",
    ipad: "Yes, iOS 7 or later (Behringer, for the XR18).",
    iphone: "Not named by the maker. ShowRecorder (the app this site makes) has recorded all 18 XR18 channels on an iPhone.",
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
  },
  {
    name: "Allen & Heath Qu-16, Qu-24, Qu-32, Qu-SB and Qu-Pac",
    note: "Qu Classic.",
    usb: "48 kHz. The Qu-16 sends 24 channels; the Qu-24, Qu-32, Qu-SB and Qu-Pac send 32.",
    onboard: "Qu-Drive: 18 tracks to a USB drive.",
    mac: "Works.",
    ipad: "iOS sees it as class compliant, says an Allen & Heath staff member on their forum. The iPad isn't named; not tested yet.",
    iphone: "Not named; not tested yet.",
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
  productPage: string;
  faqs: readonly Faq[];
  faqsName: string;
  // The URLs in its Sources section, which the TechArticle data cites.
  sources: readonly string[];
  campaign: AppStoreCampaign;
  // The setting the tap-point guide's short answer names for this mixer.
  tapPick: string;
};

// The per-mixer guides, in the order the sitemap and llms.txt list them.
export const MIXER_GUIDES: readonly MixerGuide[] = [];

// "<mixer> USB multitrack recording: settings and routing - ShowRecorder", the <title> of every mixer guide.
export function guideTitle(short: string): string {
  return `${short} USB multitrack recording: settings and routing - ShowRecorder`;
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
