// Copy for /compare (#704): ShowRecorder next to the other ways to record a mixer.
//
// Rules for this file:
// - Claim only what the product's own listing or page says. "Not mentioned" means we could not find it on the page
//   we read, not that the product lacks it. Sources, read in October 2026: Manytrack Recorder and Auria on the US
//   App Store; X-Live on a retailer's product page (Turra Music); the laptop column is general knowledge of a DAW.
// - Free records every USB Channel, with generic names (#705). The X32, M32 and Mac are in the beta. No DJM claims.

export const AS_OF = "October 2026";

export type ProductId = "showrecorder" | "manytrack" | "laptop" | "xlive" | "auria";

export const PRODUCTS: readonly { id: ProductId; name: string; pickIt: string }[] = [
  {
    id: "showrecorder",
    name: "ShowRecorder",
    pickIt:
      "Pick ShowRecorder if you want a separate file for every channel, named after the channel on the mixer, on a phone or tablet you already carry, with a second copy on a Drive as you record.",
  },
  {
    id: "manytrack",
    name: "Manytrack Recorder",
    pickIt:
      "Pick Manytrack if it must be free, if you want to play the channels back to the mixer for a soundcheck, or if you use Apple Vision. Its listing describes all three.",
  },
  {
    id: "laptop",
    name: "A laptop with Reaper or Mixbus",
    pickIt:
      "Pick the laptop if you will mix on it anyway, or already have a rig you trust. It is more to carry and power at front of house, and you name every track yourself.",
  },
  {
    id: "xlive",
    name: "Behringer X-Live",
    pickIt:
      "Pick X-Live if you own an X32 and want the recorder inside the mixer, with no phone and no cable. It works in the X32 only.",
  },
  {
    id: "auria",
    name: "Auria",
    pickIt:
      "Pick Auria if you want a full DAW on the iPad, with plug-ins, to edit and mix as well as record, and 24 simultaneous tracks is enough.",
  },
];

export const ROWS: readonly { label: string; cells: Record<ProductId, string> }[] = [
  {
    label: "Price",
    cells: {
      showrecorder:
        "Free to download, and records every USB Channel, with generic names. Pro is a one-time $4.99 at its launch price, with a 14-day Trial. No subscription.",
      manytrack: "Free. Its listing shows no in-app purchases.",
      laptop: "The laptop, plus a paid license for the software.",
      xlive: "A card you buy for the X32, plus SD cards.",
      auria: "Paid. Its US listing shows $24.99, with in-app purchases for Auria Pro and plug-ins.",
    },
  },
  {
    label: "Separate Stem for each channel",
    cells: {
      showrecorder: "Yes. One mono 24-bit WAV file per USB Channel, in step with each other.",
      manytrack:
        "Its listing says it records every channel the device sends, and does not say how the files are saved. Its one review, from an XR18 user, reports a single stereo file.",
      laptop: "Yes. One track per input, the way a DAW records.",
      xlive: "Yes. Up to 32 channels to SD card as WAV files.",
      auria: "Yes. Its listing says up to 24 tracks of simultaneous recording with a compatible USB audio interface.",
    },
  },
  {
    label: "Channel names from the mixer",
    cells: {
      showrecorder:
        "Yes, from an XR18 or MR18 over the mixer's Wi-Fi. The X32 and M32 work in the public beta. From other interfaces the files are named by channel number, or you type names with Pro.",
      manytrack: "Its listing does not mention channel names.",
      laptop: "Not on its own. You name each track yourself.",
      xlive: "The product page we read does not mention channel names.",
      auria: "Its listing does not mention channel names.",
    },
  },
  {
    label: "Safety copy on a Drive",
    cells: {
      showrecorder:
        "Yes. Every Take is written to the iPhone or iPad and to a USB drive at the same time. If the drive drops out, recording carries on and the gap is filled in afterward.",
      manytrack:
        "Not as you record. Its listing says you can copy a recording to a computer over USB afterward, or share it by AirDrop, Files or iCloud.",
      laptop: "You set it up yourself, for example with a second recorder.",
      xlive:
        "It has two SD card slots. The page we read describes them as independent, and does not mention a mirrored copy.",
      auria: "Its listing does not mention it.",
    },
  },
  {
    label: "Crash recovery",
    cells: {
      showrecorder:
        "Yes. Files are saved every 2 seconds, and the app finishes a cut-off Take the next time it opens.",
      manytrack: "Its listing does not mention it.",
      laptop: "It depends on the software. We have not compared them.",
      xlive: "The product page we read does not mention it.",
      auria: "Its listing does not mention it.",
    },
  },
  {
    label: "Markers",
    cells: {
      showrecorder: "Yes. Tap the flag during a Take. Markers go into every file and the Reaper project.",
      manytrack: "Its listing does not mention them.",
      laptop: "Yes. Both have markers.",
      xlive: "Yes. The page we read says you can set markers while recording or playing back.",
      auria: "Its listing does not mention them.",
    },
  },
  {
    label: "DAW and Reaper export",
    cells: {
      showrecorder:
        "Plain WAV files with time stamps that open in any DAW. With Pro or the Trial, each Show also has a Reaper project. Share by AirDrop or the Files app.",
      manytrack:
        "WAV or CAF files, shared by AirDrop, Files, iCloud or USB to a computer. No Reaper project is mentioned.",
      laptop: "Already in the DAW.",
      xlive: "WAV files on the SD card, which open in any DAW.",
      auria: "It is a DAW, so you mix inside it.",
    },
  },
  {
    label: "Platforms",
    cells: {
      showrecorder:
        "iPhone and iPad. A Mac version is in the public TestFlight beta, and follows on the Mac App Store.",
      manytrack: "iPhone, iPad, a Mac with Apple silicon, and Apple Vision.",
      laptop: "Mac, Windows and Linux.",
      xlive: "A card for the X32 only. The XR18 has no card slot.",
      auria: "iPad and Apple Vision.",
    },
  },
];

export const COMPARE_FAQS: readonly { q: string; a: string }[] = [
  {
    q: "Is there a free multitrack recorder for iPhone and iPad?",
    a: "Yes, two. Manytrack Recorder is free, with no in-app purchases listed. ShowRecorder is free to download and records every USB Channel, with generic names; Pro is a one-time $4.99 at its launch price and comes with a 14-day Trial. There is no subscription.",
  },
  {
    q: "Does ShowRecorder save a separate file for each channel?",
    a: "Yes. Each USB Channel becomes its own mono 24-bit WAV file, called a Stem, named after the channel on an XR18 or MR18. Manytrack's listing does not say how it saves channels, and its one review reports a single stereo file.",
  },
  {
    q: "Can I use X-Live with an XR18?",
    a: "No. X-Live is an expansion card for the X32 only, and the XR18 has no card slot. An XR18 sends all 18 channels over USB, which ShowRecorder records on an iPhone or iPad.",
  },
  {
    q: "Do I still need a laptop with Reaper or Mixbus?",
    a: "Not to record. ShowRecorder records the Stems and writes a Reaper project for each Show with Pro or the Trial, so a laptop is only for mixing afterward. If you will mix on a laptop anyway and trust that setup, recording on it is a fair choice.",
  },
  {
    q: "How current is this comparison?",
    a: `It is as of ${AS_OF}, written from each product's App Store listing or product page. A row that says a listing does not mention something means we could not find it, not that the product lacks it. Check the maker's page before you buy.`,
  },
];
