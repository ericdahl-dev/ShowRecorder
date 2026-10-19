// Screenshots on the site, in public/images/. Each placement has a Dark image (the site's default
// theme) and a light one; components/Screenshot shows the one matching the theme.
//
// - The iPad App Store set (ipad-0N-*) is in the Dark appearance, except 05-sunlight.
// - The iPhone App Store set (iphone-0N-*) is light; iphone-dark-0N-* is the same set in Dark
//   (no 05: the Sunlight shot is light in both themes).
// - recording-dark.jpg, armed-dark.jpg, shows-dark.jpg, recording-sunlight.jpg and the other iPad
//   shots are not used. recording-dark.jpg and armed-dark.jpg in particular: they show "Demo signal", "Drive not set",
//   an unlinked mixer and a yellow "No Drive" warning, which read as a problem state.

export type Device = "phone" | "ipad";

export type Shot = {
  src: string;
  src2x?: string;
  width: number;
  height: number;
  alt: string;
  device: Device;
};

const PHONE = { width: 600, height: 1303, device: "phone" as const };
const IPAD = { width: 900, height: 1200, device: "ipad" as const };

function phone(name: string, alt: string): Shot {
  return { ...PHONE, src: `/images/iphone-${name}.jpg`, src2x: `/images/iphone-${name}@2x.jpg`, alt };
}

// iphone-dark-0N-*.jpg (600 w) and @2x (1200 w) are made from the Dark App Store captures
// (1320 x 2868) the same way as the light set: sips --resampleWidth, JPEG quality 80.
function phoneDark(name: string, alt: string): Shot {
  return {
    ...PHONE,
    src: `/images/iphone-dark-${name}.jpg`,
    src2x: `/images/iphone-dark-${name}@2x.jpg`,
    alt,
  };
}

function ipad(name: string, alt: string): Shot {
  return { ...IPAD, src: `/images/ipad-${name}.jpg`, alt };
}

// Alt text describes what each screen shows (ia.md section 6). The Dark captures show slightly
// different times and sizes, so they have their own.
const RECORDING_ALT =
  "ShowRecorder on iPhone during a Take: 18 colored level meters labeled from the mixer, a Take timer at 0:21 and the stop and Marker buttons.";
const MARKERS_ALT =
  "The Markers list for a Take: Marker 1, 2 and 3 at 1:07, 1:09 and 1:10, each with an edit button.";
const SHOW_ALT = "A Show with four Takes. Each Take lists its Markers and its 18 Stems.";
const SUNLIGHT_ALT =
  "The record screen in the Sunlight appearance: a white background, black text and strong meter colors for bright stages.";
const MIXER_LINK_ALT =
  'Settings showing the Drive with 126 GB free, the recording time left on the Device and the Drive, and the Mixer Link up to "Skeyelab XR18" over Wi-Fi, with a Find Mixers button.';
const PRO_ALT =
  "The Pro screen: names and colors from the mixer and channel names you type, on the files, a second Copy on a Drive with Repair, unlimited Markers, the Show report and the Reaper project, 96 kHz recording and Templates, with Buy Pro and Restore Purchases.";

const RECORDING_DARK_ALT =
  "ShowRecorder on iPhone during a Take: 18 colored level meters labeled from the mixer, a Take timer at 0:28 and the stop and Marker buttons.";
const MARKERS_DARK_ALT =
  "The Markers list for a Take: Marker 1, 2 and 3 at 1:04, 1:08 and 1:10, each with an edit button.";
const MIXER_LINK_DARK_ALT =
  'Settings showing the Drive with 118 GB free, the recording time left on the Device and the Drive, and the Mixer Link up to "Skeyelab XR18" over Wi-Fi, with a Find Mixers button.';

export const SHOTS = {
  heroIpad: {
    dark: ipad(
      "01-recording",
      'ShowRecorder on iPad during a Take: 18 level meters named Kick, Snare, Hi-hat, Toms, Overheads, Bass, Guitars, Keys, Lead Vox, three BGVs, Playback and Click, with recording time left on the Device and the Drive and the mixer "Skeyelab XR18" linked.',
    ),
    light: ipad(
      "05-sunlight",
      'ShowRecorder on iPad during a Take in the Sunlight appearance: 18 level meters named from the mixer on a white background, with recording time left on the Device and the Drive and the mixer "Skeyelab XR18" linked.',
    ),
  },
  heroPhone: {
    dark: phoneDark("01-recording", RECORDING_DARK_ALT),
    light: phone("01-recording", RECORDING_ALT),
  },
  markers: {
    dark: phoneDark("02-markers", MARKERS_DARK_ALT),
    light: phone("02-markers", MARKERS_ALT),
  },
  show: {
    dark: phoneDark("04-show", SHOW_ALT),
    light: phone("04-show", SHOW_ALT),
  },
  sunlight: {
    dark: phone("05-sunlight", SUNLIGHT_ALT),
    light: phone("05-sunlight", SUNLIGHT_ALT),
  },
  mixerLink: {
    dark: phoneDark("03-mixer-link", MIXER_LINK_DARK_ALT),
    light: phone("03-mixer-link", MIXER_LINK_ALT),
  },
  pro: {
    dark: phoneDark("06-pro", PRO_ALT),
    light: phone("06-pro", PRO_ALT),
  },
} satisfies Record<string, { dark: Shot; light: Shot }>;
