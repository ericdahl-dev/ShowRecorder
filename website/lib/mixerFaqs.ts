// The questions an engineer asks before trying ShowRecorder with a mixer, one list per mixer page (#704).
// The page shows these exact strings (components/MixerFaq.tsx) and the FAQPage JSON-LD repeats them, so the
// structured data never says anything the page doesn't. Answers are plain text; keep them true to the page body.
export type Faq = { q: string; a: string };

export const XR18_FAQS: readonly Faq[] = [
  {
    q: "Can I record an XR18 or MR18 to an iPhone without a laptop?",
    a: "Yes. Over USB the mixer sends all 18 channels to whatever it is plugged into. ShowRecorder records them on a USB-C iPhone (iPhone 15 or later) or a USB-C iPad, one WAV file per channel.",
  },
  {
    q: "How many channels does it record?",
    a: "All 18 USB Channels: the 16 inputs and the aux line in, recorded in step with each other. Free records 2 USB Channels of your choice; the 14-day Trial and Pro record all 18.",
  },
  {
    q: "Does it work with the XR12 and XR16?",
    a: "No. The XR12 and XR16 send no multichannel USB audio, so they can't be multitracked this way.",
  },
  {
    q: "How do the files get the channel names from the mixer?",
    a: "Over the Mixer Link, ShowRecorder reads each channel's name and color from the mixer on its Wi-Fi, or on the network the mixer is connected to. Recording itself needs only the USB cable.",
  },
  {
    q: "How much space does a Show take?",
    a: "About 9.3 GB per hour for 18 channels at 48 kHz, on the iPhone or iPad and again on the drive if you use one. The record screen shows the time left.",
  },
  {
    q: "What does it cost?",
    a: "ShowRecorder is free to download, with a 14-day Trial of everything. Pro is a one-time $19.99 purchase, with no subscription.",
  },
];

export const X32_FAQS: readonly Faq[] = [
  {
    q: "Can I record an X32 or M32 to an iPad without a laptop?",
    a: "Yes, in the public beta. ShowRecorder records all 32 USB Channels from the mixer's USB card on a USB-C iPhone (iPhone 15 or later) or a USB-C iPad, one WAV file per channel. It has run against an X32 emulator, not yet against a real mixer, so try it at a rehearsal first.",
  },
  {
    q: "Is it in the App Store?",
    a: "Not for the X32 or M32 yet. The App Store version records the XR18 and MR18. X32 and M32 recording is in the public beta now and comes to the App Store in a later update.",
  },
  {
    q: "What do I need?",
    a: "A Behringer X32 with the X-USB card, or a Midas M32, M32R or M32C with the DN32-USB card, a USB-C iPhone or iPad, and a USB-B to USB-C cable. For channel names and colors, a Wi-Fi router plugged into the mixer's Ethernet port.",
  },
  {
    q: "Does it work with the X-LIVE or DN32-LIVE card?",
    a: "Those cards haven't been tested. If you have one, tell us how it goes.",
  },
  {
    q: "How much space does a Show take?",
    a: "About 16.6 GB per hour for 32 channels at 48 kHz, on the iPhone or iPad and again on the drive if you use one. The record screen shows the time left.",
  },
  {
    q: "What does it cost?",
    a: "ShowRecorder is free to download. Free records 2 USB Channels of your choice; the 14-day Trial and Pro record all 32. Pro is a one-time $19.99 purchase, with no subscription.",
  },
];
