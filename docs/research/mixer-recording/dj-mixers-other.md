# Other DJ mixers (Allen & Heath Xone:96 and Xone:PX5, Rane Seventy and Seventy-Two MKII, Denon DJ X1850 Prime): multitrack recording facts

Researched 2026-11-08. It follows the Pioneer DJM file ([`pioneer-djm.md`](pioneer-djm.md)) and uses the same labels.

**Sources.** Facts come from each maker's own manuals, release notes, download pages and product pages where we could get them.
- Some manuals were read as a copy of the maker's PDF on a dealer site. That still counts as maker (see README), and the source list names the host.
- Page numbers are the manuals' printed page numbers.
- Serato and Algoriddim (djay) are software companies, not the mixer makers. Their pages are labeled secondary, even when they are official support pages.
- Forum facts are labeled "per user reports" and list a URL.
- Prices are from retailer listings seen in search results on 2026-11-08 (the listing pages were not opened). Treat them as rough.

Source labels: [A-x] = Allen & Heath (maker). [R-x] = Rane (maker). [D-x] = Denon DJ (maker). [S-x] = secondary.

**ShowRecorder today.**
- It records any class-compliant USB audio interface as one WAV per channel (mono Stems named USB 01, USB 02 and so on).
- No mixer in this file has been tested with ShowRecorder (none on hand).
- Every mixer here sends audio to the computer as stereo pairs. The plan for DJ mixers is one stereo WAV per pair (#1088, #364). Until then a pair lands as two mono Stems.

## Summary

| Model | Channels to computer (record direction) | Fixed or selectable | Mac driver | iPhone/iPad | USB rate / bit depth | Status, rough US price |
|---|---|---|---|---|---|---|
| A&H Xone:96 | 12 ch = 6 stereo pairs, on **each** of two USB ports | Pairs 1-4 fixed to CH1-4 inputs; pair 5 = SEND 1 (pre or post fader); pair 6 = master mix or SEND 2 (switch) | **None: "macOS class compliant"** [A-1 p.21, p.24] | Not stated by A&H. On djay's iOS hardware list [S-3]; per user reports it works on iPad [S-4] | 44.1 to 96 kHz; 16 or 32-bit [A-1 p.26, p.35] | Current [A-3]; about $2,499 [S-7] |
| A&H Xone:PX5 | 10 ch = 5 stereo pairs | Pairs 1-4 fixed to CH1-4 inputs; pair 5 = master mix or FX SEND (switch) | **None: "Mac OS X CoreAudio/CoreMIDI class compliant"** [A-4 p.11, p.26, p.28] | Not stated by A&H. On djay's iOS hardware list [S-3] | 44.1 to 96 kHz; 24-bit [A-4 p.28] | Current [A-3]; about $1,799 [S-8] |
| Rane Seventy | **Not stated** by Rane or Serato | Not stated | Serato: "does not require manufacturer-specific drivers on Mac" [S-1]. Rane's guide: drivers are for Windows only [R-1 p.4] | **Serato: compatible with Serato DJ for iOS, "Connect it to your iPhone or iPad with a USB-C cable"** [S-1] | Converters "24-bit PCM, 48 kHz" [R-1 p.97]; USB rate not stated separately | Current (on Rane's downloads list) [R-3]; about $1,499 [S-9] |
| Rane Seventy-Two MKII | **Not stated** by Rane or Serato | Not stated | Serato: no manufacturer driver on Mac [S-2]. Rane's guide: drivers are for Windows only [R-2 p.3] | **Serato: same iOS statement as the Seventy** [S-2] | Converters "24-bit PCM, 48 kHz" [R-2 p.102] | **Legacy** on rane.com [R-5]; no current new price found |
| Denon DJ X1850 Prime | 10 ch = 5 stereo pairs (USB 1/2 to 9/10) | **Selectable**: a menu assigns CH1-4 and the master mix to the pairs [D-1 p.15] | Not stated in the guide. Denon offers a Windows driver only; no Mac driver is listed [D-2] | Not stated by Denon. On djay's iOS hardware list [S-3]; per user reports an iPad Pro worked after a power cycle [S-5] | 44.1, 48 or 96 kHz (menu) [D-1 p.15]; 24-bit listed for the digital output, USB bit depth not stated [D-1 p.74] | Current (on Denon's DJ mixers page) [D-3]; about $1,199 [S-10] |

All five run on mains power (IEC socket). None is powered by USB, and none of the manuals says the USB port powers or charges a phone. See each section.

No maker source we read calls any of these five "class compliant" for iPhone or iPad, or describes recording every channel to an iPhone or iPad. A&H says class compliant for macOS only.

## Ranking for ShowRecorder

Ranked by what's known today. "Class compliant" means a maker or software-partner statement, not a test by us.

| Rank | Model | Class compliant? | Channels to the recorder | Stereo pairs or mono | Why this rank |
|---|---|---|---|---|---|
| 1 | Xone:96 | Mac: yes (maker). iOS: djay list and user reports only | 12 per USB port | 6 stereo pairs, no mono channels | Most channels, fixed and documented map, raw deck inputs on pairs 1-4. Maker says no Mac driver |
| 2 | X1850 Prime | Not stated by Denon. No Mac driver offered; djay iOS list | 10 | 5 stereo pairs, no mono channels | Denon's own page says it can "record multi-channel audio to laptops" [D-3]. Assignable pairs, including the master. Class compliance and the tap point are unconfirmed |
| 3 | Xone:PX5 | Mac: yes (maker). iOS: djay list only | 10 | 5 stereo pairs, no mono channels | Same design as the Xone:96 with one port and one fewer pair. Maker says no Mac driver |
| 4 | Seventy | Serato: no Mac driver, iPhone/iPad via USB-C | Unknown | Unknown | Best iOS statement of the five (Serato names the iPhone), but nobody publishes what it sends over USB. Only 2 deck channels |
| 5 | Seventy-Two MKII | Same Serato statements as the Seventy | Unknown | Unknown | Same unknowns as the Seventy, and it's a legacy product |

None of the five sends a microphone on its own USB channel. On the Xone and Denon mixers the mic is heard only in the master mix pair. On the Rane mixers it's not documented.

## Allen & Heath Xone:96

- **USB pair layout: verified** [A-1 p.23; A-2 p.4]. The same 12 sends go to both USB 1 and USB 2:
  - USB 1/2: CH1 (RIAA or LINE)
  - USB 3/4: CH2 (RIAA or LINE)
  - USB 5/6: CH3 (RIAA or LINE)
  - USB 7/8: CH4 (RIAA or LINE)
  - USB 9/10: SEND 1 (PRE or POST)
  - USB 11/12: SEND 2 or MST (the master mix)
- **What each pair carries:**
  - CH1-4: the channel's input. A rear LN/PH switch per channel sets line or phono (RIAA) level, "For DVS (CD/Vinyl timecode) control, or recording CH1 - 4 inputs via USB 1 or USB 2" [A-1 p.21]. That this is the raw input, before the channel's gain, EQ, filter and fader, is our reading of "(RIAA or LINE)"; A&H doesn't state the tap point in words.
  - USB 9/10: SEND 1, "switchable pre/post-FADER" [A-1 p.8, p.10].
  - USB 11/12: a front switch picks "MST (LR-MIX), or SEND 2" [A-1 p.16]. SEND 2 is "fixed post-FADER" [A-1 p.8].
  - Channels A and B (the two mic/return channels) have no USB send of their own [A-1 p.23]. A mic is only in the master mix.
  - Whether MST on USB 11/12 is before or after the MASTER knobs is not stated. The RECORD RCA output is "Pre-MASTER (MST) level" [A-1 p.21].
- **Driver:**
  - macOS: "an Apple Mac CoreAudio and CoreMIDI class compliant interface and works on macOS platforms without any requirement to install hardware device drivers" [A-1 p.24]. Mac setup check: Audio MIDI Setup should show 12 input and 12 output channels [A-1 p.26].
  - Windows: an ASIO driver from A&H is required [A-1 p.24]. The current release, v4.6.70 (December 2021), supports Windows 10 and 11 [A-2 p.1].
  - iOS/iPadOS: not mentioned anywhere in the guide or release notes.
- **iPhone/iPad:**
  - A&H: nothing found. No tablet, phone or camera-adapter text in the guide.
  - djay (Algoriddim) lists the Xone:96 under its iOS hardware filter [S-3].
  - Per user reports, a djay user played out with it on an iPad ("Works great with Xone 96", 2022), and an Algoriddim staff reply says all channels can be used at once on iPad (2024) [S-4]. That's djay, not a multitrack recorder.
- **Rate and bit depth:** "Supported Sample Rates: 44.1 kHz / 48kHz / 88.2kHz / 96kHz", "Supported Bit depth: 16 bit / 32 bit" [A-1 p.35]. The headline says "32Bit/96kHz" [A-1 p.21].
- **Ports and power:** USB-B, Hi-Speed USB 2.0, two ports [A-1 p.21, p.36]. Mains power, "100 to 240V AC", "Consumption 45W max" [A-1 p.36]. Nothing about powering a connected device.
- **Status and price:** current on A&H's Xone page [A-3]. About $2,499 at US dealers [S-7].

## Allen & Heath Xone:PX5

- **USB pair layout: verified** [A-4 p.28, "DEFAULT USB AUDIO ROUTING"]:
  - USB 1/2: CH1 (RIAA or LINE)
  - USB 3/4: CH2 (RIAA or LINE)
  - USB 5/6: CH3 (RIAA or LINE)
  - USB 7/8: CH4 (RIAA or LINE)
  - USB 9/10: MASTER or FX SEND
- **What each pair carries:**
  - CH1-4: as on the Xone:96, a rear LN/PH switch sets the level, "For CD / Vinyl timecode control, or to record Channel input via USB" [A-4 p.9]. Raw input before gain/EQ/fader is our reading.
  - USB 9/10: a rear switch, "Set CH9-10 USB SND to MST or FX to route LR MIX, or FX SEND output via USB. For pre-MASTER level stereo LR MIX recording to computer" [A-4 p.11]. A&H's Traktor recording example sets this switch to MST [A-4 p.40].
  - Channel A (mic/aux) has no USB send of its own [A-4 p.28].
  - The manual calls this table "DEFAULT", but no other routing is described. Only the USB 9/10 switch changes anything.
- **Driver:**
  - Mac: "a Mac CoreAudio and CoreMIDI class compliant interface and works on Apple Mac platforms without hardware device drivers" [A-4 p.26]; "No Driver installation is required for operation with Mac OS X" [A-4 p.28].
  - Windows: A&H driver required [A-4 p.26]. Release v4.6.70 (December 2021) supports Windows 10 and 11 [A-7 p.1].
  - iOS/iPadOS: not mentioned.
- **iPhone/iPad:** A&H: nothing found. djay lists the PX5 under iOS [S-3]. We found no first-hand iPad report we could open.
- **Rate and bit depth:** "Supported Sample Rates: 44.1 kHz / 48kHz / 88.2kHz / 96kHz", "Bit depth: 24Bit" [A-4 p.28].
- **Ports and power:**
  - The rear-panel list says "USB (Type A)" for the soundcard socket [A-4 p.11]. The same manual says to use "a type A-B USB cable" to the laptop [A-4 p.23], and the quick start's key shows "USB (TYPE A-B)" [A-5]. A type A-B cable means the mixer end is Type-B, so the "Type A" line looks like a misprint (our reading).
  - Mains, 100 to 240 V [A-4 p.11]; "Consumption 35W max" [A-6 p.7].
- **Status and price:** current on A&H's Xone page [A-3]. About $1,799 at US dealers [S-8].

## Rane Seventy

- **USB channel layout: not found.** Neither the Rane user guide nor Rane's product page nor Serato's quickstart says how many audio channels the mixer sends to a computer, or what they carry. A search of Rane's forum and retailer pages found nothing either.
  - What the guide does say: the two USB Type-B ports "send and receive audio and MIDI control information to and from the computer" [R-1 p.8].
  - Mic 1 "Clean Feed": "When this setting is On, Serato DJ Pro will not receive audio from the Seventy's Mic 1 Input while recording is in progress" [R-1 p.17]. That suggests Serato's recording includes the mic unless this is on. It doesn't tell us the channel map.
- **Driver:**
  - Rane's guide: "Windows users only: The Rane Control Panel contains drivers required for Windows" [R-1 p.4].
  - Serato: "does not require manufacturer-specific drivers on Mac operating systems and is plug-and-play with Serato DJ Pro. You may be asked to install the Rane Control Panel" [S-1].
  - Rane's downloads page labels the Mac file "Seventy Control Panel/Driver - macOS v1.0.5" [R-3]. The guide and Serato say the Mac needs no driver, so we read this as the settings app (our reading).
  - Neither Rane nor Serato uses the words "class compliant".
- **iPhone/iPad:**
  - Serato: "This hardware is compatible with Serato DJ for iOS ... Connect it to your iPhone or iPad with a USB-C cable" [S-1]. That's the plainest phone statement in this file, but it's from Serato and is about DJ playback, not multitrack recording.
  - djay's iOS filter did **not** show the Seventy, but it didn't show it under the Mac filter either, so that result is unclear [S-3].
- **Rate:** converters "AKM High Definition Audio; 24-bit PCM, 48 kHz" [R-1 p.97; R-6]. Whether USB also runs at 44.1 kHz: not stated.
- **Ports and power:** two USB Type-B ports for computers, two USB Type-A ports for Twelve controllers ("Do not connect USB drives to these ports") [R-1 p.8, p.98]. Rane's product page: the two ports let "two laptops to be connected at once" [R-6]. Power: IEC, 100-240 V, "Consumption: 30 W" [R-1 p.98]. Nothing about powering a phone.
- **Status and price:** current (listed on Rane's downloads page, not on the legacy page) [R-3, R-5]. About $1,499 [S-9].

## Rane Seventy-Two MKII

- **USB channel layout: not found**, for the same reasons as the Seventy. The guide's wording is the same: the USB Type-B ports "send and receive audio and MIDI control information" [R-2 p.8]. Mic 1 Clean Feed: "When Clean Feed is On, the Mic 1 will not pass audio when recording in Serato DJ Pro" [R-2 p.10].
- **Driver:**
  - Rane's guide: "Windows users only: The Rane Control Panel contains drivers required for Windows" [R-2 p.3].
  - Serato: no manufacturer-specific driver on Mac, plug-and-play [S-2].
  - Rane's downloads: "Seventy-Two MKII Windows Driver v1.0.8" and a "Seventy-Two Control Panel - macOS v1.1.2" [R-4].
- **iPhone/iPad:**
  - Serato: compatible with Serato DJ for iOS, iPhone or iPad over a USB-C cable [S-2].
  - djay lists the Seventy-Two MKII under iOS [S-3]. djay 5.5's release notes, quoted on Algoriddim's forum, add "native integration with display support (macOS, Windows, iOS)" [S-6].
- **Rate:** converters "24-bit PCM, 48 kHz" [R-2 p.102].
- **Ports and power:** two USB Type-B, two USB Type-A for controllers [R-2 p.8, p.103]. IEC, 100-240 V, "Consumption: 30 W" [R-2 p.103].
- **Status and price:** listed under **Legacy** on rane.com [R-5], so treat it as discontinued. No current new price found (unverified).

## Denon DJ X1850 Prime

- **USB pair layout: selectable, verified in outline** [D-1 p.15, Utility menu > Advanced Audio > USB Audio]:
  - "CH1-4/Master/Cue Assign: These settings determine which USB audio channels (1/2-9/10) will receive the audio signal from Channels 1-4 (CH1-CH4), and the master mix (Master)."
  - That's 5 stereo pairs (10 channels) carrying the four channels and the master mix.
  - **Factory default assignment: not stated.** Our reading: Broadcast Mode "allows you to send the master signal to your computer over USB audio channels 1-2" and disables DVS on Channel 1 [D-1 p.15], which suggests USB 1/2 normally carries Channel 1.
  - "Output Level" is an offset for "the master mix sent to your computer over a USB connection: -20dB to +20dB" [D-1 p.15].
  - Mic 1 and Mic 2 have no USB send of their own in this list.
  - **Tap point: not stated.** Whether the channel sends are before or after the Level knob, EQ, filter, effects or fader isn't in the guide.
- **Driver:**
  - The guide doesn't mention a driver for any operating system.
  - Denon's downloads page lists "X1850 Prime Windows Driver" v1.0.4 and firmware updaters for Mac and Windows (v1.7). No Mac driver is listed [D-2].
  - Denon doesn't use the words "class compliant". That a Mac needs no driver is our inference from the downloads page.
- **iPhone/iPad:**
  - Denon: nothing found.
  - djay lists the X1850 Prime under its iOS filter [S-3].
  - Per user reports, an iPad Pro on USB1 with a USB-C to USB-B cable gave no sound at first, then "Got it working" after what the user thought was a power cycle (Engine DJ forum, 2023-12-29) [S-5].
- **Rate and bit depth:** "Sampling Rate: This is the sampling rate of the USB audio signal: 44.1kHz, 48kHz, or 96kHz" [D-1 p.15]. Specs list "Digital Output ... Bit Depth 24-bit" [D-1 p.74]; that line is about the coaxial digital output. USB bit depth: not stated.
- **Ports and power:**
  - Two USB ports on the top panel, "Use standard USB cables to connect computers to these USB ports" [D-1 p.9]. **Connector type not stated**: the spec table's connection list doesn't include them [D-1 p.74]. Unverified.
  - Denon's product page: "Dual USB Audio Connections ... connect to DJ software and record multi-channel audio to laptops" [D-3].
  - Power: IEC with locking connector, 100-240 V, "Consumption 65 W" [D-1 p.74]. Nothing about powering a connected device.
- **Status and price:** current on Denon's DJ mixers page [D-3]. About $1,199 at US dealers [S-10].

## Gotchas for a guide

- **Stereo pairs everywhere.** Each deck channel arrives as two USB channels (left and right). Today ShowRecorder writes them as two mono Stems; the stereo-pair plan (#1088, #364) fits these mixers too.
- **Mics are only in the mix.** None of the five documents a separate mic channel over USB. A reader who wants the MC on its own track needs another input.
- **Xone pair 5/6 needs a switch.** On the Xone:96 (front, USB 11/12) and PX5 (rear, USB 9/10), the master mix reaches USB only when the switch is on MST. Otherwise it's an effects send.
- **X1850 pairs can move.** The menu can reassign which pair carries which channel, so a fixed name map would be wrong for some users.
- **Two computer ports.** The Xone:96, both Ranes and the X1850 have two USB ports for two laptops; the PX5 has one. On the Xone:96 both ports get the same 12 sends [A-1 p.23], so either port works for a recorder. On the others, whether both ports carry the same sends is not stated.

## Sources

- [A-1] XONE:96 User Guide, AP11645 issue 2, Allen & Heath's PDF read on Gear4music: https://r2.gear4music.com/media/82/827295/download_827295.pdf
- [A-2] XONE:96 PC Software Release Notes v4.6.70 (December 2021), Allen & Heath: https://www.allen-heath.com/content/uploads/2023/06/X96_SRN_4670_2.pdf
- [A-3] Allen & Heath Xone series page, read in Chrome on 2026-11-08 (lists Xone:96 and Xone:PX5): https://www.allen-heath.com/hardware/xone-series/ . Product page: https://www.allen-heath.com/hardware/xone-series/xone96/
- [A-4] XONE:PX5 User Guide, AP10733 issue 2, Allen & Heath's PDF read on Juno: https://imagescdn.juno.co.uk/manual/622531-01U.pdf
- [A-5] XONE:PX5 Quick Start Guide, AP10316 issue 2, Allen & Heath's PDF read on Gear4music: https://r2.gear4music.com/media/29/291892/download_291892.pdf
- [A-6] Xone:PX5 Technical Datasheet, Allen & Heath's PDF read on Leisuretec: https://leisuretec.co.uk/cdn/shop/files/XONE_PX5_Technical_Datasheet.pdf
- [A-7] XONE:PX5 PC Software Release Notes v4.6.70 (December 2021), Allen & Heath: https://www.allen-heath.com/content/uploads/2023/06/XPX5_PCSRN_4670_2.pdf
- [R-1] Seventy User Guide v1.3, Rane: https://cdn.inmusicbrands.com/rane/seventy/Seventy_User_Guide_v1-3_zyx.pdf
- [R-2] Seventy-Two MKII User Guide v1.4, Rane: https://cdn.inmusicbrands.com/rane/seventy-twoMKII/Seventy-Two_MKII-UserGuide-v1.4.pdf
- [R-3] Rane downloads, Seventy, read in Chrome on 2026-11-08: https://www.rane.com/downloads/?product=Seventy
- [R-4] Rane downloads, Seventy-Two MKII, read in Chrome on 2026-11-08: https://www.rane.com/downloads/?product=Seventy-Two%20MKII
- [R-5] Rane legacy products page (lists Seventy-Two MKII and Seventy-Two), read on 2026-11-08: https://www.rane.com/products/legacy/ . Product page: https://www.rane.com/seventy-two-mk2/
- [R-6] Rane Seventy product page, read on 2026-11-08: https://www.rane.com/seventy/
- [D-1] X1850 PRIME User Guide v1.4, Denon DJ: https://cdn.inmusicbrands.com/denondj/X1850Prime/X1850%20PRIME%20-%20User%20Guide%20-%20v1.4.pdf
- [D-2] Denon DJ downloads page, X1850 Prime section, read on 2026-11-08: https://www.denondj.com/downloads
- [D-3] Denon DJ X1850 PRIME product page, read on 2026-11-08: https://www.denondj.com/x1850%20prime-x1850primexus.html . Listed on https://www.denondj.com/products/dj-mixers.html
- [S-1] Serato, "RANE SEVENTY Quickstart Guide": https://support.serato.com/hc/en-us/articles/17935506000143-RANE-SEVENTY-Quickstart-Guide (the A-Trak Edition page says the same: https://support.serato.com/hc/en-us/articles/10173628040463)
- [S-2] Serato, "RANE SEVENTY-TWO MKII Quickstart Guide": https://support.serato.com/hc/en-us/articles/10173635877647-RANE-SEVENTY-TWO-MKII-Quickstart-Guide
- [S-3] Algoriddim djay hardware list, iOS filter, read in Chrome on 2026-11-08: https://www.algoriddim.com/hardware#ios . Under iOS it showed Xone:96, Xone:PX5, X1850 Prime, Seventy-Two and Seventy-Two MKII. The Seventy showed under neither the iOS nor the Mac filter, though it is on the unfiltered list.
- [S-4] Algoriddim community, "Allen & Heath Xone:96 iOS compatibility" (per user reports, 2021-2024): https://community.algoriddim.com/t/allen-heath-xone-96-ios-compatibility/15059
- [S-5] Engine DJ community, "iPad sound output to X1850" (per user reports, 2023-12-29): https://community.enginedj.com/t/ipad-sound-output-to-x1850/53545
- [S-6] Algoriddim community, "Compatibility: RANE Seventy vs. Seventy-Two MKII with djay Pro" (quotes djay 5.5 release notes, 2025-10-21): https://community.algoriddim.com/t/compatibility-rane-seventy-vs-seventy-two-mkii-with-djay-pro/32150
- [S-7] Xone:96 price: Dale Pro Audio and Hollywood DJ listings, $2,499 (search results, 2026-11-08): https://daleproaudio.com/products/allen-and-heath-xone-96-professional-dj-mixer , https://hollywooddj.com/products/allen-heath-xone-96-analogue-dj-mixer-with-audio-interface
- [S-8] Xone:PX5 price: Hollywood DJ listing, $1,799 (search results, 2026-11-08): https://hollywooddj.com/products/allen-heath-xone-px5-4-1-dj-performance-mixer
- [S-9] Seventy price: DJTechTools store, $1,499 (search results, 2026-11-08): https://store.djtechtools.com/products/rane-seventy
- [S-10] X1850 Prime price: zZounds and Performance Audio, $1,199 (search results, 2026-11-08): https://zzounds.com/productreview--DENX1850PRIME , https://performanceaudio.com/products/denon-dj-x1850-prime-professional-4-channel-dj-club-mixer-with-smart-hub
- Allen & Heath's site refused automated reads (HTTP 403) on 2026-11-08; its pages were read in Chrome. A&H's support-site copy of the PX5 guide was not opened. Serato's support pages also refused automated reads and were read in Chrome.

## Gaps

- **Rane USB channel map (Seventy and Seventy-Two MKII):** not found in any Rane or Serato text. How many channels, which carry the decks, and whether a mix pair exists are all unknown.
- **iPhone/iPad, every model:** no mixer maker in this file mentions iPhone, iPad, tablets or camera adapters. The only phone statements are Serato's (Rane) and djay's hardware list, both for DJ playback, not multitrack recording.
- **Class compliance on iOS:** A&H says "macOS class compliant" only. Denon and Rane never use the term.
- **X1850:** factory default pair assignment, tap point of the channel sends, USB bit depth and USB connector type are not stated.
- **Xone tap points:** that CH1-4 sends are the raw inputs (pre-gain, pre-EQ, pre-fader) is our reading of the routing tables; A&H doesn't say it in words. Whether the Xone:96's MST send on USB 11/12 is pre-master is not stated.
- **Xone:96 32-bit USB:** whether the 32-bit mode is integer or float, and how iOS handles it, is not stated.
- **Phone power:** none of the five lists power on a computer USB port. Untested.
- **Seventy-Two MKII price:** legacy product, no current new price found.
- **Hardware:** none of these five tested with ShowRecorder (none on hand).

## Open questions only a hands-on test can answer

1. Does each mixer show up on an iPhone (USB-C, and Lightning with the camera adapter) with all its channels, or only 2? Start with the Xone:96 and X1850, which publish 10-12 channels.
2. What do the Rane Seventy and Seventy-Two MKII actually send over USB: how many channels, and which deck, mix or mic is on each?
3. On the X1850, what is the factory pair assignment, and are the channel sends before or after the Level knob, EQ and fader?
4. On the Xone mixers, are CH1-4 really raw (does turning a channel's gain, EQ or fader change the USB track)?
5. Does the Xone:96 open on iOS at 32-bit, and does ShowRecorder handle it, or does it need 16-bit?
6. Can ShowRecorder record from one Xone:96 port while a DJ plays from a laptop on the other port?
7. Does any of them power or charge the phone over the USB cable, or is a powered hub required for a full show (as with the XR18, #327)?
