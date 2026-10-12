// Which mixers work today and which are planned. Shown on /features (#mixers) and summed up in the
// home page FAQ. Planned entries carry no dates and stay off the App Store listing.
// Sources: ericdahl-dev/ShowRecorder issues #199 (X32/M32), #364, #366, #367 (Pioneer DJM), #374 (Mac),
// and #416 to #425 (the mixer families being checked).

export type MixerEntry = { name: string; body: string };

export const worksNow: MixerEntry[] = [
  {
    name: "Behringer X Air XR18 and MR18",
    body: "18 USB Channels over USB, with channel names and colors read from the mixer over Wi-Fi (Mixer Link).",
  },
  {
    name: "Other class-compliant USB audio interfaces",
    body: "Every channel the interface sends is recorded. Names don't come from the mixer; with Pro you can type them.",
  },
];

// In the order they are being worked on.
export const planned: MixerEntry[] = [
  {
    name: "Behringer X32 and Midas M32",
    body: "Next. Recording over USB with names and colors from the mixer, as on the XR18.",
  },
  {
    name: "Pioneer DJM mixers",
    body: "Stems named from each model's own USB layout (Deck 1, Deck 2, Mic, Master and so on). Later, Markers where the track changes.",
  },
  {
    name: "ShowRecorder for Mac",
    body: "Not a mixer: the same recorder on a Mac. In the public TestFlight beta now, and on the Mac App Store after 1.0.",
  },
];

// Being checked, not promised: each needs USB audio that an iPhone or iPad accepts without a driver.
// One issue each (#417 to #425). Move an entry up to planned only once that check passes.
export const considering: string[] = [
  "Behringer Wing, Wing Compact and Wing Rack",
  "Allen & Heath Qu, SQ and CQ",
  "PreSonus StudioLive Series III",
  "Mackie DL16S, DL32S and DL32R",
  "Yamaha TF and DM series",
  "Midas HD96-24",
  "TASCAM Sonicview",
  "QSC TouchMix-30",
  "Soundcraft Ui24R",
];
