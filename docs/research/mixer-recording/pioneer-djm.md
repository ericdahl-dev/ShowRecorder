# Pioneer DJ DJM (DJM-A9, DJM-V10 / V10-LF, DJM-900NXS2, DJM-750MK2, DJM-450, DJM-250MK2): multitrack recording facts

Researched 2026-11-07 for #1089. It also answers #364's questions 1-3.

**Sources.** Every fact comes from Pioneer DJ's own manuals and pages, or from AlphaTheta, the company that makes them. Some manuals were read as a copy of Pioneer's PDF on a dealer or rental site. That still counts as maker (see README), and the source list names the host.
- Page numbers are the manuals' printed page numbers.
- Tap points come from each manual's block diagram. A line marked "our reading" is our interpretation of a drawing; Pioneer's text doesn't say it.
- Forum facts are labeled "per user reports" and list a URL.

Source labels: [P-x] = Pioneer DJ / AlphaTheta (maker). [O-x] = owner (Eric). [S-x] = secondary.

**ShowRecorder today.**
- It records any class-compliant USB audio interface as one WAV per channel.
- It has no DJM code yet. Stems are named USB 01, USB 02 and so on until #364 ships.
- No DJM has been tested (there's none on hand).
- **Plan:** record DJM sends as one stereo WAV per pair (#1088, #364). Today it records mono Stems named USB 01, USB 02.
- The pair map in #364 is built only from a "USB pair layout: verified" line below.

## Summary

| Model | USB send pairs to computer (record direction) | Pair contents chosen in the Setting Utility? | Mac driver | iPhone/iPad as a multitrack recorder | USB rate / bit depth | DJM-REC | Phone port power |
|---|---|---|---|---|---|---|---|
| DJM-A9 | 6 stereo pairs (12 ch) | Yes, USB1/2 to 9/10; USB11/12 fixed to FX SEND | **Mac: Setting Utility only, no audio driver** [P-1 p.13] | **Not supported by maker**: "Do not connect mobile devices to the USB Type-B or Type-C ports" [P-1 p.22]. Class compliance not stated | Not stated (mixer runs at 96 kHz internally) | Yes | USB-A "5 V / 2.1 A or less" |
| DJM-V10 / V10-LF | 6 stereo pairs (12 ch) | Yes, all 6 | Driver required (PC/Mac) | Not stated; driver-only per manual | Not stated (96 kHz internally) | Yes (both) | USB-A "5 V/2.1 A or less" |
| DJM-900NXS2 | 6 stereo pairs (12 ch) | Yes, USB1/2 to 9/10; USB11/12 = FX SEND only | Driver required (Mac OS X driver .pkg) | Not stated; driver-only per manual | "96 kHz/24-bit" (maker) | Yes | Not found |
| DJM-750MK2 | 6 stereo pairs (12 ch) | Yes, USB1/2 to 9/10; USB11/12 FX SEND, "Settings cannot be changed" | Driver required | Not stated; driver-only per manual | "48 kHz 24-bit" (maker) | Yes | USB-A "5 V/2.1 A or less" |
| DJM-450 | 4 stereo pairs (8 ch) | Yes, USB1/2 to 5/6; USB7/8 = FX SEND only | Driver required | Not stated; driver-only per manual | 48 kHz (spec); USB bit depth not stated | Yes | USB-A "5 V/1 A or less" |
| DJM-250MK2 | 4 stereo pairs (8 ch) | Yes, USB1/2 to 5/6; USB7/8 = FX SEND only | Driver required | Not stated; driver-only per manual | 48 kHz (spec); USB bit depth not stated | **No** (not on the list) | No phone port |

All six are USB 2.0 audio to a computer through the Setting Utility's MIXER OUTPUT tab (A9: [DJM-A9 Audio Output]; others: [Mixer Audio Output]). No Pioneer source we read calls any DJM "class compliant" or says a DJM records multitrack to an iPhone or iPad.

## Tap points shared by every model

Pioneer uses the same send names on all six. Each name sits at the same place in every block diagram [P-1 p.93, P-2 p.84, P-4 p.23, P-6 p.27, P-8 p.26, P-10 p.23]:

| Send name | Where it is taken | What it means for a recording |
|---|---|---|
| **CH# Control Tone (PHONO / LINE / DIGITAL / CD/LINE)** | Right after the channel's input selector, **before TRIM** | The raw input: before trim, EQ, Sound Color FX, Beat FX and the fader. Pioneer: "Outputs sound at the volume input to the unit regardless of the [USB Output Level] setting" and "Available for software applications that support the function" (it's the DVS timecode feed). Best for stems you'll remix. That an ordinary recorder records it like any other audio is our reading |
| **Pre CH# Fader** (A9 only) | After TRIM, Sound Color FX, Beat FX, EQ/ISO and the MULTI I/O insert; before the channel fader | Processed by the DJ's EQ and FX, but fader moves don't reach it |
| **Post CH# Fader** | After the channel fader. On A9, 900NXS2, 750MK2 and 450, after the post-fader Sound Color FX/Beat FX blocks; before the crossfader assign | Follows the fader: a closed fader means a silent track. The common choice on V10 (the manual's example screen) |
| **CROSSFADER A / B** | The crossfader A or B side bus | One side of the crossfader. V10-LF: "Not available for this unit" |
| **MIC** | Mic chain after low cut, mic EQ and mic FX | The mic only |
| **MIX (REC OUT)** | The master mix, taken off before the MASTER LEVEL control (our reading of the diagrams); A9 offers "with MIC" and "without MIC" | The stereo mix, the same as the REC OUT jacks. Pioneer's footnote: "For uses other than recording, be sure to set the DJ application so that no sound loop occurs" |
| **FX SEND (for rekordbox)** | The channel's FX send | For rekordbox's effects; not a recording source |
| **EXT1 / EXT2 (SEND EXTERNAL)** (V10/V10-LF) | The EXT 1/2 send buses | External effects sends |
| **AUX** (450, 250MK2) | AUX input after its trim | The AUX input |

**USB Output Level** (MIXER OUTPUT tab) is one level for all sends, except Control Tone, which ignores it [P-1 p.16, 19; P-4 p.19]. The manuals' example screens show 0 dB (A9, V10) and -19 dB (900NXS2, 750MK2, 450, 250MK2). Which value is the factory default isn't stated.

## DJM-A9

- **USB pair layout: verified** [P-1 p.16 screen, p.19 list]. The same layout is in Eric's screenshot [O-3].
  - USB1/2: MIX (REC OUT with MIC)
  - USB3/4: CH1
  - USB5/6: CH2
  - USB7/8: CH3
  - USB9/10: CH4
  - USB11/12: FX SEND (for rekordbox), fixed
- **Contents per pair** [P-1 p.19]:
  - USB1/2 offers MIX (REC OUT with MIC), MIX (REC OUT without MIC), Pre CH1-4 Fader, Post CH1-4 Fader, CROSSFADER A/B or MIC.
  - USB3/4 to 9/10 (CH#) offer CH# Control Tone PHONO/LINE/DIGITAL, Pre CH# Fader, Post CH# Fader, CROSSFADER A/B, MIC, or MIX (REC OUT with/without MIC).
  - "USB 11/12 is fixed to [FX SEND(for rekordbox)]".
  - The example screen on p.16 shows USB3/4 to 9/10 set to "CH# Control Tone PHONO". The manual doesn't say this is the factory default.
- **Menu path:** Mac: Finder > [Applications] > [Pioneer] > [DJM-A9] > [DJM-A9 Setting Utility] > [MIXER OUTPUT] tab > pull-down under [DJM-A9 Audio Output] [P-1 p.15-16].
- **Ports:** two computer ports, A and B, each with USB Type-B and Type-C. "USB Type-B / USB Type-C ... 2 sets" [P-1 p.91]. Two computers can connect at once. Each port's send goes to "USB A OUT" and "USB B OUT" [P-1 p.93].
- **Driver:** "If you use a Mac, only the Setting Utility will be installed"; Windows gets the audio driver too [P-1 p.13]. Pioneer doesn't call it class compliant (see Gaps).
- **iPhone/iPad:**
  - Pioneer: "Do not connect mobile devices to the USB Type-B or Type-C ports" [P-1 p.22].
  - Mobile devices go to the rear MULTI I/O USB Type-A port ("Do not use a USB hub") [P-1 p.22-23].
  - The block diagram's outputs from the mix include "USB: DJM-REC" (with and without MIC) [P-1 p.93]. That's the stereo feed DJM-REC records.
  - The same port also sends to and returns from an FX app (MULTI I/O) [P-1 p.42-45].
  - Per user reports, the A9 works driverless on iOS with djay. Another user in the same thread reported no input on an iPhone with a USB-C to Lightning cable: https://community.algoriddim.com/t/pioneer-djm-a9-class-compliant/19713 [S-1].
- **Rate:** "Sampling rate ... 96 kHz"; A/D 32-bit for channels; master/booth/rec/send D/A 32-bit [P-1 p.89]. The USB stream's rate and word length aren't stated. The SAMPLING RATE setting (44.1/48/88.2/96 kHz) is for DIGITAL MASTER OUT [P-1 p.76].
- **Power:** "USB Type-A ... Power supply 5 V / 2.1 A or less" [P-1 p.91]. Pioneer doesn't say it charges a phone. The computer ports list no power figure.

## DJM-V10 and DJM-V10-LF

- **USB pair layout: verified** [P-2 p.16 screen, p.19 list; P-3 p.19 list]. One pair per channel:
  - USB1/2: CH1
  - USB3/4: CH2
  - USB5/6: CH3
  - USB7/8: CH4
  - USB9/10: CH5
  - USB11/12: CH6
  - The example screen shows each pair on Post CH# Fader [P-2 p.16]. A mix pair exists only if the user picks MIX (REC OUT) for one of the six.
- **Contents per pair** [P-2 p.19]:
  - CH1/CH3/CH4/CH6 offer CH# Control Tone PHONO/LINE/DIGITAL, Post CH# Fader, FX SEND (for rekordbox dj), CROSSFADER A/B, MIC, MIX (REC OUT), EXT1 (SEND EXTERNAL) or EXT2 (SEND EXTERNAL).
  - CH2 and CH5 have no PHONO Control Tone (no phono inputs).
  - There's no Pre CH# Fader choice.
  - V10-LF: same list, but CROSSFADER A/B are "Not available for this unit" [P-3 p.19].
- **Menu path:** [Pioneer] > [DJM-V10 Setting Utility] from the applications list > [MIXER OUTPUT] tab > [Mixer Audio Output] [P-2 p.15-16].
- **Driver:** "To input or output your PC/Mac's audio to/from the unit, install the dedicated audio driver software ... If a PC/Mac without the audio driver software installed is connected to the unit, errors may occur" [P-2 p.13; P-3 same]. So it's driver-only per the maker.
- **iPhone/iPad:** the MULTI I/O (USB) Type-A port is for a mobile device [P-2 p.22, p.84]. Its block diagram also has a "USB: DJM-REC" output from the mix [P-2 p.84]. Multitrack to iOS: not stated.
- **Rate:** "Sampling rate ... 96 kHz"; master/booth D/A and channel A/D 32-bit [P-2 p.81]. USB rate and word length not stated.
- **Power:** "USB terminal Type A ... Power supply 5 V/2.1 A or less"; Type B, 2 sets [P-2 p.83; P-3 specifications].

## DJM-900NXS2

- **USB pair layout: verified** [P-4 p.19 screen, p.20 list]:
  - USB1/2: CH1
  - USB3/4: CH2
  - USB5/6: CH3
  - USB7/8: CH4
  - USB9/10: CH5, a free pair; the example screen shows MIX (REC OUT)
  - USB11/12: CH6, FX SEND only
- **Contents per pair** [P-4 p.20]:
  - CH1-4 offer CH# Control Tone PHONO, CD/LINE or DIGITAL, Post CH# Fader, CROSS FADER A/B, MIC or MIX (REC OUT).
  - CH5 (USB9/10) offers MIX (REC OUT), Post CH1-4 Fader, CROSS FADER A/B or MIC.
  - CH6 (USB11/12) is FX SEND only.
  - There's no Pre CH# Fader choice.
- **Menu path:** Mac: [Macintosh HD] > [Application] > [Pioneer] > [DJM-900NXS2] > [DJM-900NXS2 Settings Utility] > [MIXER OUTPUT] tab > [Mixer Audio Output] [P-4 p.19].
- **Pioneer's product page** says the USB sound card handles "stereo signals from 4 ins and 5 outs" [P-5]. That doesn't match the 6 pairs in the manual, unless the FX SEND pair isn't counted (our guess).
- **Driver:** the manual installs "DJM-900NXS2_AudioDriver.pkg" on Mac OS X [P-4 p.5]. Driver-only per the maker.
- **iPhone/iPad:** a "Mobile device connection terminal (USB port)" for FX apps (SEND/RETURN) and MIDI [P-4 p.8]. The block diagram shows it as "USB C" with its own send and return [P-4 p.23]. Multitrack to iOS: not stated.
- **Rate:** "Digital audio from the USB and SPD I/F is compatible with 96 kHz/24-bit high resolution audio" [P-4 p.3]. The Windows ASIO tab shows 44100, 48000 and 96000 Hz [P-4 p.19].
- **Power:** the manual we read has no spec table; the phone port's power is not found.

## DJM-750MK2

- **USB pair layout: verified** [P-6 p.23 screen, p.24 list]:
  - USB1/2: CH1
  - USB3/4: CH2
  - USB5/6: CH3
  - USB7/8: CH4
  - USB9/10: CH5, a free pair; the example screen shows REC OUT
  - USB11/12: CH6, FX SEND, "Settings cannot be changed"
- **Contents per pair** [P-6 p.24]:
  - CH1-4 offer CH# Control Tone PHONO or LINE, Post CH# Fader, CROSS FADER A/B, MIC or REC OUT.
  - CH5 offers REC OUT, Post CH1-4 Fader, CROSS FADER A/B or MIC.
- **Menu path:** Mac: [Macintosh HD] > [Application] > [Pioneer] > [DJM-750MK2] > [DJM-750MK2 Settings Utility] > [MIXER OUTPUT] [P-6 p.23].
- **Driver:** the Mac OS X install procedure is in [P-6 p.17-18, 21]. Driver-only per the maker.
  - "USB sound cards that allow connection to PC, Mac, or iOS devices" [P-6 p.3] is about the phone port for FX apps ("effects applications on iOS devices ... through a simple, single-USB cable connection"), not multitrack.
- **Rate:** "The USB sound card is compatible with 48 kHz 24-bit high-resolution audio" [P-6 p.3]. The quick start lists "Sampling rate 48 kHz" [P-7].
- **Power:** "Type A ... Power supply 5 V/2.1 A or less"; one B type [P-7 specifications].

## DJM-450

- **USB pair layout: verified** [P-8 p.23 screen, p.24 list]:
  - USB1/2: CH1
  - USB3/4: CH2
  - USB5/6: CH3, a free pair; the example screen shows REC OUT
  - USB7/8: CH4, FX SEND only
- **Contents per pair** [P-8 p.24]:
  - USB1/2 and 3/4 offer CH# Control Tone PHONO or LINE, Post CH# Fader, CROSS FADER A/B, MIC, AUX or REC OUT.
  - USB5/6 offers REC OUT, Post CH1/CH2 Fader, CROSS FADER A/B, MIC or AUX.
- **Menu path:** Mac: [Macintosh HD] > [Application] > [Pioneer] > [DJM-450] > [DJM-450 Settings Utility]. It also opens from rekordbox: [Preferences] > [Input channel] > [Settings Utility] [P-8 p.18, 22].
- **Driver:** Mac OS X driver install [P-8 p.15, 20]. Driver-only per the maker.
- **iPhone/iPad:** a "Mobile device connection terminal (USB port)" for FX apps [P-8 p.6]. Multitrack to iOS: not stated.
- **Rate:** "Sampling rate 48 kHz"; "MASTER D/A converter 24 bits"; "Other A/D and D/A converters 24 bits" [P-9 specifications]. The ASIO tab shows "48000Hz" [P-8 p.23]. USB word length not stated.
- **Power:** "USB terminal Type A ... Power supply 5 V/1 A or less"; one B type [P-9 specifications].

## DJM-250MK2

- **USB pair layout: verified** [P-10 p.20 screen, p.21 list]:
  - USB1/2: CH1
  - USB3/4: CH2
  - USB5/6: CH3, a free pair; the example screen shows REC OUT
  - USB7/8: CH4, FX SEND only
- **Contents per pair:** the same choices as the DJM-450 [P-10 p.21].
- **Menu path:** Mac: [Macintosh HD] > [Application] > [Pioneer] > [DJM-250MK2] > [DJM-250MK2 Settings Utility] > [MIXER OUTPUT] [P-10 p.20].
- **Driver:** "DJM-250MK2_AudioDriver.pkg" for Mac [P-10 p.17]. Driver-only per the maker.
- **iPhone/iPad:** there's no mobile device port. The only USB socket is "B type ... 1 set" [P-11 specifications]. The DJM-250MK2 isn't on DJM-REC's list [P-12].
- **Rate:** "Sampling rate 48 kHz", converters 24 bits [P-11 specifications]. USB word length not stated.
- **Power:** no USB-A port, so nothing to charge from.

## Built-in alternatives: DJM-REC and rekordbox

- **DJM-REC** (Pioneer's iPhone/iPad app) supports "DJM-V10, DJM-V10-LF, DJM-V5, DJM-A9, DJM-900NXS2, DJM-750MK2 and DJM-450" [P-12]. It connects with "a single USB cable" to a mixer "featuring digital send/return".
  - It controls the mixer's peak limiter and makes track time-stamps from fader information the mixer sends.
  - It is free, and paid features can be tried free for 30 days [P-12].
  - The block diagrams of the A9 and V10 show the feed it records as "USB: DJM-REC", a stereo copy of the mix [P-1 p.93, P-2 p.84].
  - It records **stereo only**, as WAV at 44.1 or 48 kHz, or AAC. That's from the App Store listing quoted in #364, not re-read for this note.
- **rekordbox recording:** none of the six manuals describes recording in rekordbox. They only warn about sound loops "for uses other than recording". Pioneer's 250MK2 product page says "The USB connection supports sound input and output, so you can record your mixes to your computer's hard drive" (via rekordbox DJ apps, not detailed). See Gaps.

## Gotchas for a guide

- **Control Tone isn't a "record" option by name.** Pioneer frames it as DVS timecode. It is still the cleanest per-channel source (pre-trim, pre-EQ, pre-fader). Our reading of the block diagrams.
- **Post CH# Fader goes silent when the fader is down.** On most models it also includes post-fader FX. Fine for a "what the crowd heard per deck" stem, not for remixing.
- **Only one or two pairs carry the mix.** V10 has no mix pair unless the user sets one. 900NXS2/750MK2 put it on USB9/10, and 450/250MK2 on USB5/6, but only if that pair is set to REC OUT (it can be a fader or the MIC).
- **The FX SEND pair is not useful audio for a recording.** Leave it out or label it.
- **The phone port is not the computer port.** On the A9, V10, 900NXS2, 750MK2 and 450, the USB-A "mobile device" port carries the MULTI I/O or SEND/RETURN stereo and DJM-REC's stereo. It doesn't carry the 12-channel computer interface (our reading of the block diagrams).

## Sources

- [P-1] DJM-A9 Instruction Manual, DRI1785-B (English), AlphaTheta: https://downloads.support.alphatheta.com/manuals/DJM_A9_DRI1785B_manual.pdf . A byte-identical copy is on 4Wall's site: https://cdn01.4wall.com/cms/rentals/files/f6835eb526b3d2.pdf
- [P-2] DJM-V10 Instruction Manual, DRI1643-B, Pioneer's PDF read on DJ Center (Estonia): https://djcenter.ee/images/kasutusjuhendid/Pioneer-DJM-V10.pdf
- [P-3] DJM-V10-LF Instruction Manual, DRI1663-A, Pioneer's PDF read on Adorama: https://www.adorama.com/col/productManuals/PIDJMV10LF.pdf
- [P-4] DJM-900NXS2 Operating Instructions, DRI1300-A, AlphaTheta: https://downloads.support.alphatheta.com/manuals/dj-mixers/DJM-900/DJM-900NXS2_DRI1300A_manual.pdf
- [P-5] DJM-900NXS2 product page (Pioneer DJ): https://www.pioneerdj.com/en-us/product/mixer/djm-900nxs2/black/specifications/
- [P-6] DJM-750MK2 Operating Instructions, DRI1470-A, Pioneer's PDF read on Leisuretec: https://leisuretec.co.uk/cdn/shop/files/DJM-750MK2_User_Manual.pdf
- [P-7] DJM-750MK2 Operating Instructions (Quick Start Guide), DRH1433-A, Pioneer's PDF read on Korn: https://cdn.korn.eu/documents/product/257702_i.pdf
- [P-8] DJM-450 Operating Instructions, DRI1406-A, Pioneer's PDF read on DJ Center: https://djcenter.ee/images/kasutusjuhendid/Pioneer-DJM-450.pdf
- [P-9] DJM-450 Quick Start Guide, DRH1396C, AlphaTheta: https://downloads.support.alphatheta.com/manuals/DJM_450_DRH1396C_quickstart_manual.pdf
- [P-10] DJM-250MK2 Operating Instructions, DRI1443-A, Pioneer's PDF read on Juno: https://imagescdn.juno.co.uk/manual/642661-01U.pdf
- [P-11] DJM-250MK2 Quick Start Guide, DRH1425D, AlphaTheta: https://downloads.support.alphatheta.com/manuals/DJM_250MK2_DRH1425D_quickstart_manual.pdf
- [P-12] DJM-REC page (Pioneer DJ): https://www.pioneerdj.com/en/product/software/djm-rec/dj-app/overview/
- [O-3] Owner screenshot (Eric, 2026-11-07) of the DJM-A9 manual's USB routing screen. It matches [P-1] p.16.
- [S-1] Algoriddim community, "Pioneer DJM A9 - Class Compliant" (per user reports): https://community.algoriddim.com/t/pioneer-djm-a9-class-compliant/19713
- Pioneer's support site (support.pioneerdj.com, support.alphatheta.com) refused automated reads (HTTP 403) on 2026-11-07. Its FAQs were not checked.

## Gaps

List these plainly in a guide, or leave them out:
- **Class compliance, every model:** no Pioneer source calls a DJM class compliant.
  - The A9 manual installs no audio driver on a Mac [P-1 p.13], but that isn't a class-compliance statement.
  - The other five install a Mac audio driver.
  - Per user reports, the A9 works on iOS [S-1], with conflicting results.
  - Untested by us.
- **iPhone/iPad multitrack, every model:** not supported in any Pioneer text. The A9 manual forbids mobile devices on its computer ports [P-1 p.22]. A powered-hub test (#364) would be against that instruction.
- **USB sample rate and word length:**
  - A9: not stated (96 kHz internal).
  - V10/V10-LF: not stated (96 kHz internal).
  - 450/250MK2: USB word length not stated (48 kHz, 24-bit converters).
  - Whether 900NXS2 USB runs at 44.1/48 kHz on a Mac without ASIO: not stated.
- **Factory default of each pair's contents:** not stated for any model. The pair lists above are the manuals' example screens. Pair *positions* (which USB pair is which channel slot) are verified; their *contents* depend on the Setting Utility.
- **Settings without a computer:** whether the Setting Utility's choices are kept in the mixer is not stated. We can't tell whether a DJM set up on a Mac keeps its routing when moved to another device.
- **900NXS2 "4 ins and 5 outs"** on the product page vs. 6 send pairs in the manual: unresolved.
- **Phone charging:** Pioneer lists a 5 V supply on the USB-A port (A9, V10/V10-LF, 750MK2: 2.1 A; 450: 1 A), but never says "charge". 900NXS2: not found. Computer ports: no power figure. Untested.
- **DJM-REC formats** (WAV 44.1/48 kHz, AAC, stereo only): from the App Store listing via #364, not from a Pioneer page read here.
- **rekordbox recording** with these mixers: not in the manuals. How rekordbox records (which inputs, format) isn't covered here.
- **Mac driver on current macOS:** the manuals list old macOS versions. Per a third-party page (Serato), Pioneer still ships macOS drivers for the 900NXS2 and V10: https://support.serato.com/hc/en-us/articles/202918970-Pioneer-DJ-Hardware-Drivers . Check Pioneer's support page before publishing.
- **DJM-S series and DJM-V5:** not researched in this pass. DJM-S USB multitrack is not covered.
- **Hardware:** no DJM tested with ShowRecorder (none on hand).
