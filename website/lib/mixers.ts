// Which mixers work today and which are planned. Shown on /features (#mixers) and summed up in the
// home page FAQ. Planned entries carry no dates and stay off the App Store listing.
// Sources: ericdahl-dev/ShowRecorder issues #199 (X32/M32), #364, #366, #367 (Pioneer DJM), #374 (Mac).

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
    body: "Not a mixer, but planned right after 1.0: the same recorder on a Mac.",
  },
];
