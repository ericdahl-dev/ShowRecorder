// The mixer recording guides (#1061): the hub at /guides/record lists every mixer
// with what it can record and how, and each mixer with a guide links to it.
//
// Every fact here comes from docs/research/mixer-recording/README.md (the summary table) and its detail files, where
// each one has a source and a confidence label. Never add a number or a capability that isn't there. Where the research
// says "unknown", the cell says so in plain words. "Maker" means the mixer maker's own manual, spec page or staff post.

export const GUIDES_HUB = "/guides/record";

export type MixerRow = {
  name: string;
  // A short line under the name: other models it covers, or how sure a fact is.
  note?: string;
  // What the mixer sends over USB to a computer, iPhone or iPad.
  usb: string;
  // Recording with no computer: a card, a USB stick or a drive.
  onboard: string;
  // Mac, iPad and iPhone, in plain words: maker-confirmed, a forum report, or not known yet.
  apple: string;
  // This mixer's guide, once it has one.
  guide?: string;
};

export const MIXER_ROWS: readonly MixerRow[] = [
  {
    name: "Behringer X32",
    note: "With the X-USB or X-LIVE card. Full size, Compact, Producer, Rack and Core.",
    usb: "Up to 32 in and 32 out through the card, at 44.1 or 48 kHz, 24-bit. With no card, no multitrack USB audio.",
    onboard: "X-LIVE card: 8, 16 or 32 channels to two SD cards. X-USB card: none. The console's USB stick port records stereo, 16-bit WAV.",
    apple: "Mac: works with no driver (maker), though Behringer's own OS lists stop at Mac OS X 10.12. iPhone and iPad: not documented by the maker, and not tested yet.",
  },
  {
    name: "Midas M32 and M32R",
    note: "With the DN32-USB or DN32-LIVE card.",
    usb: "DN32-USB: 32 in and 32 out, 48 kHz, 24-bit. DN32-LIVE: 32, 16, 8 or 2 channels.",
    onboard: "DN32-LIVE card: the same SD recorder as the X-LIVE. The console's USB stick port records stereo, 16-bit.",
    apple: "Mac: works with no driver (maker). iPhone and iPad: not documented by the maker, and not tested yet.",
  },
  {
    name: "Behringer WING, WING Rack and WING Compact",
    usb: "2 x 2 up to 48 x 48, 24-bit. The console runs at 44.1 or 48 kHz; USB at 44.1 kHz is not stated.",
    onboard: "WING-LIVE card: 64 channels on two SD cards. Front USB stick: 2 or 4 tracks.",
    apple: "Mac with no driver: forum reports only. iPad: reports conflict. iPhone: unknown.",
  },
  {
    name: "Behringer XR18 and Midas MR18",
    note: "Also the X18. Midas's manual confirms the MR18's USB specs; its iPad support comes only from retailers.",
    usb: "18 in and 18 out, or 2 x 2, at 44.1 or 48 kHz (48 by default).",
    onboard: "None for multitrack.",
    apple: "Mac: works with no driver (maker). iPad: yes, iOS 7 or later (Behringer, for the XR18). iPhone: not named by the maker, and not tested yet.",
  },
  {
    name: "Behringer XR12 and XR16, Midas MR12",
    usb: "No USB audio interface, so no multitrack over USB.",
    onboard: "Stereo WAV, 2 tracks, to a USB stick.",
    apple: "No multitrack on any computer, iPhone or iPad.",
  },
  {
    name: "Allen & Heath SQ-5, SQ-6, SQ-7 and SQ-Rack",
    usb: "32 in and 32 out, 48 or 96 kHz.",
    onboard: "SQ-Drive: 16 channels at 96 kHz or 32 at 48 kHz, 24-bit WAV, to a fast USB drive (the maker says most sticks are too slow). Or stereo.",
    apple: "Mac: class compliant (maker). iPhone and iPad: not named. Allen & Heath says no driver is needed on any system that supports class-compliant audio. Not tested yet.",
  },
  {
    name: "Allen & Heath Qu-5, Qu-6 and Qu-7",
    note: "The new Qu.",
    usb: "32 in and 32 out over USB-C, 48 or 96 kHz.",
    onboard: "SD card: 16 channels at 96 kHz or 32 at 48 kHz. USB stick: stereo.",
    apple: "Mac: class compliant. iPad: works but \"not officially supported\" (maker), with USB Stream Mode set to Multitrack. iPhone: not tested yet.",
  },
  {
    name: "Allen & Heath Qu-16, Qu-24, Qu-32, Qu-SB and Qu-Pac",
    note: "Qu Classic.",
    usb: "48 kHz. The Qu-16 sends 24 channels; the Qu-24, Qu-32 and Qu-Pac send 32.",
    onboard: "Qu-Drive: 18 tracks to a USB drive.",
    apple: "Mac: works. iPad: yes, says Allen & Heath staff on their forum. iPhone: not tested yet.",
  },
  {
    name: "Allen & Heath CQ-12T, CQ-18T and CQ-20B",
    usb: "CQ-12T 16 in, 16 out. CQ-18T 24 in, 22 out. CQ-20B 24 in, 24 out. 48 or 96 kHz.",
    onboard: "SD card: as many channels as USB at 48 kHz; 16 at 96 kHz on the CQ-18T and CQ-20B. USB stick: stereo.",
    apple: "Mac: works. iPad: yes, says Allen & Heath staff, with Stream Mode set to Multitrack. iPhone: not tested yet.",
  },
  {
    name: "Allen & Heath Avantis and Avantis Solo",
    usb: "No USB audio interface. Multitrack needs an option card (Dante, Waves, MADI or gigaACE).",
    onboard: "Stereo only, as 24-bit 96 kHz WAV.",
    apple: "No multitrack over USB on any computer, iPhone or iPad.",
  },
  {
    name: "Soundcraft Ui24R",
    usb: "32 in and 32 out, 48 kHz. Bit depth not stated.",
    onboard: "22 channels to a USB stick (FAT32, up to 32 GB). The file format is not stated by the maker.",
    apple: "Mac: works with no driver (maker). iPhone and iPad: not stated by the maker.",
  },
  {
    name: "Soundcraft Signature 12 MTK and 22 MTK",
    note: "Discontinued.",
    usb: "12 MTK: 14 in, 12 out. 22 MTK: 24 in, 22 out. 44.1 or 48 kHz, 24-bit.",
    onboard: "None.",
    apple: "Mac: works (Core Audio). iPad: yes, with a camera adapter (maker). iPhone: not tested yet.",
  },
  {
    name: "Yamaha TF1, TF3, TF5 and TF-Rack",
    usb: "34 in and 34 out, 48 kHz only, 24-bit.",
    onboard: "Stereo WAV to a USB drive.",
    apple: "Mac: class compliant (maker). iPhone and iPad: not stated by the maker.",
  },
  {
    name: "Yamaha DM3 and DM3 Standard",
    usb: "Up to 18 in and 18 out, 48 or 96 kHz.",
    onboard: "Stereo WAV or MP3 to USB storage.",
    apple: "Mac: Yamaha says its driver is required. iPhone and iPad: not stated, so assume no until someone tests it.",
  },
  {
    name: "Yamaha MG10XU, MG12XU, MG16XU and MG20XU",
    note: "The newer Yamaha MGX12 and MGX16 differ: Yamaha says iPhone and iPad recognize them, with up to 18 in on the MGX16 at 44.1 or 48 kHz.",
    usb: "Stereo only: 2 in and 2 out, up to 192 kHz.",
    onboard: "None.",
    apple: "Mac: USB Audio Class 2.0 compliant (maker). iPad: yes with a camera adapter, stereo only (maker).",
  },
  {
    name: "PreSonus StudioLive Series III",
    note: "Consoles, 32R, 24R and 16R.",
    usb: "64 in and 64 out (Native) or 34 x 34 (Compatibility), 44.1 or 48 kHz. 16R: 24 x 24.",
    onboard: "Consoles: 34 tracks to an SD card. Racks: stereo only.",
    apple: "Mac: works. iOS and iPadOS: class compliant (PreSonus support). The 64 x 64 mode crashes some iPad apps.",
  },
  {
    name: "Mackie DL32S, DL16S and DL32SE",
    usb: "32 in and 32 out (DL16S: 16 x 16), 48 kHz.",
    onboard: "None.",
    apple: "Mac: works with no driver. iPhone and iPad: not stated by the maker.",
  },
  {
    name: "Mackie DL32R",
    usb: "32 in and 32 out, 48 kHz.",
    onboard: "Multichannel WAV to a USB drive. The manual says 32 tracks in one place and 24 in another. The drive and a computer can't record at the same time.",
    apple: "Mac: works. iPad: yes, with a camera adapter (manual). iPhone: not tested yet.",
  },
  {
    name: "Zoom LiveTrak L-12, L-20 and L-20R",
    usb: "L-12: 14 in, 4 out. L-20: 22 in, 4 out. 44.1 or 48 kHz only; no USB audio at 96 kHz.",
    onboard: "SD card: 14 tracks (L-12) or 22 (L-20), WAV up to 24-bit 96 kHz.",
    apple: "iPad and iPhone: yes, named by Zoom, with the rear Class Compliant Mode switch on before power-on. Mac: Zoom offers a driver; use without one is not stated.",
  },
];
