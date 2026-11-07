// The steps of the guide at /guides/record-gig-without-laptop. The page lists them and its HowTo structured data
// repeats them (howToJsonLd in lib/structuredData.ts), so the two never disagree. Plain text: the page adds the links.
export type GuideStep = { name: string; text: string };

// What ShowRecorder runs on, in the words this guide and the mixer recording guides' "get the app" box share.
export const DEVICE_REQUIREMENT = "a USB-C iPhone (iPhone 15 or later) on iOS 26, or a USB-C iPad on iPadOS 26";

export const GUIDE_STEPS: readonly GuideStep[] = [
  {
    name: "Install ShowRecorder",
    text: `Get ShowRecorder free from the App Store on ${DEVICE_REQUIREMENT}.`,
  },
  {
    name: "Set what the mixer sends over USB",
    text: "On the mixer, choose the signal each USB Channel carries: the input, pre EQ, pre fader or post fader. To mix later in a DAW, the input or pre EQ is the usual pick.",
  },
  {
    name: "Plug the mixer into the iPhone or iPad",
    text: "Connect the mixer's USB port to the phone or tablet, ideally through a powered USB-C hub so it charges all night. The meters come alive, one per USB Channel.",
  },
  {
    name: "Link the mixer for channel names",
    text: "Join the mixer's network (the XR18's own Wi-Fi, or a router on the X32's Ethernet port), open Settings, then Mixer Link, and tap Find Mixers. The meters take the mixer's names and colors.",
  },
  {
    name: "Record a test Take, then the show",
    text: "Press record for a minute at soundcheck and play it back. At the show, press record once and tap the flag at each song to drop a Marker.",
  },
  {
    name: "Open the files in your DAW",
    text: "After the show, copy the Show folder to your computer with AirDrop or the Files app and drag the WAV files into Reaper, Logic, Pro Tools or any DAW.",
  },
];
