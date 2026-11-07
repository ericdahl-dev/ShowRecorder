# Yamaha TF series (TF1, TF3, TF5, TF-Rack)

Checked 2026-11-06. Sources are numbered in section 9. Audited 2026-11-06 against the maker PDFs and pages listed there.

## 1. USB audio to a computer
- 34 x 34 over USB 2.0, Type-B "USB TO HOST" connector, 24-bit. [1][2][3]
- Spec pages for all four models: "PC/Mac (USB2.0) Recording 34 tracks, Playback 34 tracks". [1][2]
- Internal sample rate: 48 kHz (spec page, "Sampling frequency rate, Internal 48 kHz"). [1][2] The reference manual also has a "USB Sample Rate Mismatch" error that names a 44.1 kHz console case and tells you to match the computer to the console. [3] Whether the console can actually run at 44.1 kHz: unknown (the spec pages say only 48 kHz).

## 2. Driverless status
- macOS: class compliant. Yamaha's own guide says: "Computers running Mac OSX will use a class compliant driver, so do not need any additional installation ... check that 'Yamaha TF' is available" in Sound settings. [4] The TF downloads page lists the Yamaha Steinberg USB Driver only for Windows. [5] The guide dates from 2016 (OS X era); current macOS was not checked by Yamaha in that guide.
- iOS/iPadOS over USB TO HOST: unknown (no maker source). Being class compliant on macOS suggests it may work, but nobody has confirmed it.
- The TF's separate "iPad" USB-A connector on the top panel is for playing audio from an iPad/iPhone or a USB drive into ST IN 1, and for 2-track recording to a USB drive. It is not the multitrack interface. [3]
- Windows: needs the Yamaha Steinberg USB Driver (V2.1.9 for Win 11/10 on the downloads page). [4][5]
- Mode switches: none documented for USB TO HOST on TF.

## 3. Onboard recording (no computer)
- 2 tracks only: "2-track recording via USB Storage Device". [1][2]
- Format: "48 kHz, 24-bit stereo WAV". Playback: WAV or MP3 (MP3 at 44.1/48 kHz, 128-320 kbps). [3]
- Media: FAT32, 512-byte sectors (so drives over 2 TB will not work), allocation unit 4096 bytes or larger. Use an HDD or SSD for recording: "USB memory devices and iOS devices can be used for playback only". [3] The spec page says the same: thumb drives are not supported for recording. [1]
- "Simultaneous recording and playback is not supported." While recording, the signal being recorded can't be used as an input channel. A folder can hold at most 150 items. [3]

## 4. Recording settings
- Sample rate: 48 kHz (set by the console; the computer must match). [1][3][4] Bit depth on USB: 24-bit. [1]
- Where: RECORDER screen (cassette-tape icon on the toolbar) > INPUT/OUTPUT tab sets the 2-track record source and level. That same source also feeds USB 33/34. [3][4]
- Channel count options: none found in the manual; the interface is 34 x 34. [1][3]

## 5. Routing (how sources reach each USB channel)
- Fixed blocks, not patchable per slot:
  - USB 1-32 = Direct Out of input channels CH1-32. Each channel's direct out has an on/off switch and a choice of tap point. Path: touch the channel name > CH VIEW > Direct out point button and Direct out on/off button. [3] Yamaha's 2016 guide: "By default, TF-series channels 1-32 each have a Direct Output enabled via the USB TO HOST port." [4]
  - USB 33/34 = the RECORDER record source. The choices are ST L/R or a pair of mono AUX buses (1-8), plus MTRX 1/2 and MTRX 3/4 from V3.5. Path: RECORDER screen > INPUT/OUTPUT > RECORD source selection menu. [3][4]
- From V4.5, SETUP > PREFERENCE (Preference icon) > "USB 1/2 Output (V4.5 and later): Selects the signals to be output to channels 1 and 2 of the USB TO HOST connector." The choices: Ch 1/2 Direct, ST L/R, AUX or MTRX ("Ch 1/2 Direct is the output before the fader, and ST L/R, AUX, and MTRX are the outputs after the fader"). The factory setting is not stated. [3] (Added 2026-11-07 for the guide, #1074.)
- The V4.5 reference manual says nothing about the Mac or a driver; the Mac statement comes only from the 2016 guide [4]. V4.5 is still the newest reference manual on the downloads page (firmware is V4.56, 2025-06-04). [5]
- CH33-40 (not on TF1) and the stereo input channels have no Direct Out, "so they cannot be recorded". [4]
- TF1 and TF-Rack have 16 local mic inputs but still have CH1-32 (32 mono channels). [1][2] CH17-32 carry signal only from Tio1608-D, Dante or USB sources. [3]
- With an NY64-D card, the same CH1-32 direct outs also feed SLOT OUT 1-32 (Quick Config table). [3]
- Main mix or buses: only through USB 33/34 (one stereo pair: ST L/R, an AUX pair or a MATRIX pair). [3][4]
- Virtual soundcheck: per channel, INPUT screen > input source "USB". INPUT screen Menu key > "All USB" switches the channels on the selected layer to USB, so run it once per layer: [3]
  - TF5: CH1-32, then CH33-40.
  - TF3: CH1-24, then CH25-32, then CH33-40.
  - TF1 / TF-Rack: CH1-16, then CH17-32.
  - When USB is the source, the gain slider becomes digital gain and +48V is hidden. [3]
- When to use which:
  - Inputs: always USB 1-32.
  - Main mix or a monitor mix alongside: set the record source to ST or an AUX/MTRX pair and take USB 33/34.
  - Reordering tracks: not possible on the console; reorder in the app.

## 6. Tap points (USB 1-32 = per-channel direct out)
- Options, per channel (reference manual V4.5): [3]
  - "Pre DG: Before the digital gain"
  - "Pre HPF: Before the high-pass filter"
  - "Pre Fader: Before the fader"
  - "Post ON: directly after the [ON] key; CH1-CH8 are directly after the AUTOMIXER"
- The 2016 guide recommends "Pre DG" (no EQ, dynamics or effects) for live recording and virtual soundcheck, and names "Pre Fader" and "Post Fader" as the alternatives. [4] Its "Post Fader" is the V4.5 manual's "Post ON". The guide does not mention Pre HPF.
- Analog gain (head amp) is before every tap. Digital gain sits between Pre DG and Pre HPF, so Pre DG is the earliest digital point. [3][6]
- HPF placement: Pre DG and Pre HPF are both before the HPF. Pre Fader and Post ON are after it. [3][6]
- Which tap is the factory default: unknown. The 2016 guide's CH VIEW screenshot shows "Pre DG", but it is from a user scene ("A08 Crave Record"), not a fresh console, and the text does not state a default. [4] The V4.5 manual does not state one either. [3]
- Gain compensation / shared Tio gain affecting the feed: unknown (no maker statement found).

## 7. Gotchas
- Only 32 inputs are recordable. CH33-40 and ST IN cannot be recorded; the only extra is one stereo pair on 33/34. [4]
- The Mac must run at 48 kHz, or the console shows "USB Sample Rate Mismatch". [3][4]
- Onboard recording is 2-track only, and thumb drives are not supported for it. [1][3]
- Check each channel's Direct out point and on/off before a show, since the factory point is not documented. [3][4]
- iPad/iPhone over USB TO HOST is unverified.

## 8. Confidence
| Fact | Confidence |
|---|---|
| 34x34, 24-bit, 48 kHz, USB 2.0 Type-B | maker |
| macOS class compliant, no driver | maker (2016 guide) |
| iOS/iPadOS multitrack | unknown |
| USB 1-32 = CH1-32 direct outs, on by default; 33/34 = recorder source | maker |
| Tap points Pre DG / Pre HPF / Pre Fader / Post ON | maker |
| Default tap point | unknown |
| All USB per layer (TF5/TF3/TF1) | maker |
| Onboard 2-track 48k/24 WAV, FAT32 | maker |

## 9. Sources
1. https://usa.yamaha.com/products/proaudio/mixers/tf/specs.html
2. https://usa.yamaha.com/products/proaudio/mixers/tf-rack/specs.html
3. TF Series Reference Manual V4.5: https://usa.yamaha.com/files/download/other_assets/8/392718/tf5_en_rm_v45_j0.pdf (RECORDER screen p.15-16; INPUT screen and All USB p.57; CH VIEW direct out p.77; error messages; Quick Config table p.106; block diagram in the appendix)
4. Yamaha "TF series Live Recording with Steinberg Nuendo Live" (Aug 2016): https://usa.yamaha.com/files/download/other_assets/5/1199125/TF_series_Live_Recording_en.pdf
5. https://usa.yamaha.com/products/proaudio/mixers/tf/downloads.html
6. TF V3.5 block diagram: https://usa.yamaha.com/files/download/other_assets/8/811748/tfv3.5_mixer_blockdiagram.pdf

## Gaps
- Factory default direct-out point: not stated by Yamaha. Don't say "Pre DG by default". Tell readers to open CH VIEW and set the point on every channel.
- iPhone/iPad over USB TO HOST: not named by Yamaha. Say "not tested yet".
- macOS driverless: stated in a 2016 Yamaha guide only. Say "class compliant per Yamaha"; don't promise a specific macOS version.
- 44.1 kHz: the spec says 48 kHz only. Tell readers to set the computer to 48 kHz.
- Shared stage box (Tio1608-D) gain reaching the recording: no maker statement. Leave it out or label it "our inference".
