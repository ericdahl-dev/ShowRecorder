import type { Faq } from "@/lib/mixerFaqs";
import { BEST_APP_GUIDE, guideTrail } from "@/lib/mixerGuides";
import { PRO_PRICE_TEXT } from "@/lib/price";

// The comparison at /guides/best-app-record-digital-mixer-iphone (#1085): which app to multitrack record a digital
// mixer on an iPhone or iPad.
//
// Rules for this file:
// - Every fact about another app comes from that app's own App Store page (US store) or its maker's site, read on the
//   day in CHECKED, and each row links the page it came from. If the maker doesn't say it, the cell says "Not stated".
//   That means we could not find it on their page, not that the app lacks it.
// - Never a channel count or a price we did not read. Prices change, so the table says free, paid or in-app purchase
//   and the date, not an amount. ShowRecorder's Pro price is the one exception: it is ours (lib/price.ts).
// - ShowRecorder facts come from docs/tested-hardware.md and docs/research/mixer-recording/README.md. It is "the app
//   this site makes" everywhere on the page, so the affiliation is plain.

// The page's path, defined in lib/mixerGuides.ts (the hub links to it).
export { BEST_APP_GUIDE };

// The day every row was read.
export const CHECKED = "2026-11-07";

export type AppRow = {
  id: string;
  name: string;
  maker: string;
  // The page the facts come from, and any second maker page.
  source: string;
  extraSource?: string;
  price: string;
  // Does it save one file per channel?
  perChannel: string;
  // How many inputs it records at once.
  inputs: string;
  platforms: string;
  // Channel names from the mixer.
  names: string;
  // Editing and mixing on the device.
  editing: string;
};

export const NOT_STATED = "Not stated";

// ShowRecorder's own facts: the rigs it has recorded on, and the mixer research.
export const TESTED_HARDWARE_URL = "https://github.com/ericdahl-dev/ShowRecorder/blob/main/docs/tested-hardware.md";
export const RESEARCH_URL = "https://github.com/ericdahl-dev/ShowRecorder/blob/main/docs/research/mixer-recording/README.md";

export const APP_ROWS: readonly AppRow[] = [
  {
    id: "showrecorder",
    name: "ShowRecorder (the app this site makes)",
    maker: "Eric Dahl",
    source: TESTED_HARDWARE_URL,
    extraSource: RESEARCH_URL,
    price: `Free records every channel. Pro is a one-time in-app purchase, ${PRO_PRICE_TEXT} in the US at its launch price.`,
    perChannel: "Yes. One mono WAV file per channel, on the Free tier too.",
    inputs:
      "Every channel a class-compliant USB mixer sends. All 18 XR18 channels recorded on an iPhone (owner test, 2026-11-06) and verified on a Mac; a full-length show through a hub is still being tested.",
    platforms:
      "iPhone and iPad. Its listing also shows a Mac with Apple silicon (an iPad app, not verified for macOS) and Apple Vision, plus a native Mac app in a public TestFlight beta.",
    names:
      "With Pro, from an XR18 or MR18 and an X32 or M32 (Mixer Link); Free numbers the files. The X32 has been tested only against an emulator so far.",
    editing: "No. It records; you edit in a DAW afterward.",
  },
  {
    id: "manytrack",
    name: "Manytrack Recorder",
    maker: "Lutz Latta",
    source: "https://apps.apple.com/us/app/id6642668789",
    price: "Free. No in-app purchases listed.",
    perChannel: "Not stated. It saves .wav or .caf files.",
    inputs: "All channels the device exposes, \"eg 16 or 32 channels from digital sound mixers\".",
    platforms: "iPhone, iPad, Mac with Apple silicon (an iPad app, not verified for macOS) and Apple Vision.",
    names: NOT_STATED,
    editing: "Not stated. It plays all channels back to the device.",
  },
  {
    id: "cubasis",
    name: "Cubasis 3",
    maker: "Steinberg",
    source: "https://apps.apple.com/us/app/id1207839273",
    price: "Paid, with in-app purchases.",
    perChannel: "Not stated. It is a DAW with unlimited audio tracks.",
    inputs: "24 assignable physical inputs and outputs; how many record at once is not stated.",
    platforms: "iPhone, iPad and Apple Vision.",
    names: NOT_STATED,
    editing: "Yes. A full DAW: audio and MIDI editors, mixer, effects, export to Cubase.",
  },
  {
    id: "aum",
    name: "AUM",
    maker: "Kymatica",
    source: "https://apps.apple.com/us/app/id1055636344",
    extraSource: "https://kymatica.com/aum/help",
    price: "Paid. Its in-app purchases are tips.",
    perChannel: "Yes. Its manual says each recording-enabled channel is recorded as a separate file.",
    inputs: "Not stated as a number. It supports multi-channel audio interfaces and unlimited mixer channels.",
    platforms: "iPhone, iPad, iPod touch and Apple Vision.",
    names: NOT_STATED,
    editing: "Mixing and routing, yes. An audio editor is not stated.",
  },
  {
    id: "garageband",
    name: "GarageBand",
    maker: "Apple",
    source: "https://apps.apple.com/us/app/id408709785",
    extraSource: "https://support.apple.com/guide/garageband-iphone/chs392846e9/ios",
    price: "Free.",
    perChannel: "Each armed track takes its own input channel (Apple's guide).",
    inputs: "Not stated. Up to 32 tracks in a song; multitrack recording needs an audio interface.",
    platforms: "iPhone and iPad.",
    names: NOT_STATED,
    editing: "Yes. Arrange, trim and mix up to 32 tracks.",
  },
  {
    id: "multitrackdaw",
    name: "MultiTrack DAW",
    maker: "Harmonicdog",
    source: "https://apps.apple.com/us/app/id329322101",
    price: "Free, with in-app purchases. Recording is free; the unlock adds MIDI editing, time stretch and automation.",
    perChannel: "Not stated. Its listing says up to 32 inputs on 32 tracks, and it exports stems.",
    inputs: "Up to 32 inputs at once, all 32 tracks free.",
    platforms: "iPhone, iPad and Apple Vision.",
    names: NOT_STATED,
    editing: "Yes. Editing, crossfades, mixing with plug-ins.",
  },
  {
    id: "auria",
    name: "Auria",
    maker: "WaveMachine Labs",
    source: "https://apps.apple.com/us/app/id524122834",
    price: "Paid, with in-app purchases.",
    perChannel: "Not stated. Its listing says up to 24 tracks recorded at once, and it exports AAF sessions.",
    inputs: "Up to 24 tracks of simultaneous recording from a USB audio interface.",
    platforms: "iPad and Apple Vision.",
    names: NOT_STATED,
    editing: "Yes. Waveform editor, mixer with channel strips, plug-ins, automation.",
  },
  {
    id: "studiomini",
    name: "StudioMini",
    maker: "Otreus",
    source: "https://apps.apple.com/us/app/id329935264",
    price: "Free, with in-app purchases.",
    perChannel: NOT_STATED,
    inputs: NOT_STATED,
    platforms: "iPhone and iPad.",
    names: NOT_STATED,
    editing: "Punch-in and a simple mixer. Its listing says it isn't trying to replace a desktop DAW.",
  },
  {
    id: "multitrackrecorder",
    name: "MultiTrackRecorder",
    maker: "CHOKAKU KENKYUSHO",
    source: "https://apps.apple.com/us/app/id6465250065",
    price: "Free, with in-app purchases. Multi-channel recording needs a paid monthly or yearly plan.",
    perChannel: "Yes. It generates a separate file for each channel, WAV or M4A.",
    inputs: "Up to 16 channels at once.",
    platforms: "iPhone, iPad and iPod touch.",
    names: NOT_STATED,
    editing: "No. Its listing says it records only and does not mix.",
  },
];

// Home > Recording guides > this page. The visible breadcrumb and the BreadcrumbList data share it.
export const bestAppTrail = guideTrail("Best app for iPhone and iPad", BEST_APP_GUIDE);

// The questions at the end of the page. The page shows these exact strings and its FAQPage JSON-LD repeats them.
export const BEST_APP_FAQS: readonly Faq[] = [
  {
    q: "What is the best app to multitrack record a digital mixer on an iPhone?",
    a: `It depends on the job. For a file per channel at no cost, ShowRecorder (the app this site makes). For editing and mixing on the device, Cubasis 3, or Auria on an iPad. For free and simple, Manytrack Recorder, MultiTrack DAW or GarageBand. Each app's facts come from its App Store page or the maker's site, checked ${CHECKED}.`,
  },
  {
    q: "Which iPhone apps save a separate file for each mixer channel?",
    a: "ShowRecorder saves one mono WAV per channel. MultiTrackRecorder says it makes a separate file for each channel, up to 16, with a paid monthly or yearly plan. AUM's manual says each recording-enabled channel is a separate file. MultiTrack DAW and Auria record several inputs at once, and Cubasis 3 lists 24 assignable inputs, but none of the three listings says each input becomes its own file. Manytrack Recorder's listing doesn't say how it saves channels.",
  },
  {
    q: "Is there a free app to record every channel of a mixer on an iPhone or iPad?",
    a: "Yes. Manytrack Recorder is free and records all the channels the mixer sends. MultiTrack DAW is free with all 32 tracks and up to 32 inputs at once. ShowRecorder's Free tier records every channel, one file each. GarageBand is free, but Apple doesn't state how many inputs it records at once.",
  },
  {
    q: "Which app is best for editing a multitrack recording on an iPad?",
    a: "Cubasis 3 or Auria. Both are full DAWs with editors, mixers and plug-ins, and Auria exports AAF sessions to desktop DAWs. ShowRecorder only records: edit its files in a DAW afterward.",
  },
  {
    q: "Is this comparison neutral?",
    a: 'ShowRecorder is the app this site makes, so we have an interest. To keep it fair, every fact about another app comes from that app\'s own App Store page or maker\'s site, with a link and the date we read it, and the page says when another app is the better pick. A cell that says "Not stated" means we could not find it, not that the app lacks it.',
  },
];
