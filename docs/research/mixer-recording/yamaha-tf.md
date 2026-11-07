# Yamaha TF series (TF1, TF3, TF5, TF-Rack)

Checked 2026-11-06. Sources are numbered in section 9.

## 1. USB audio to a computer
- 34 x 34 over USB 2.0, Type-B "USB TO HOST" connector, 24-bit PCM. [1][2][3]
- Spec pages for all four models: "PC/Mac (USB2.0) Recording 34 tracks, Playback 34 tracks". [1][2]
- Internal sample rate: 48 kHz (spec page, "Sampling frequency rate, Internal 48 kHz"). [1][2] The reference manual also has a "USB Sample Rate Mismatch" error that names a 44.1 kHz console case and tells you to match the computer to the console. [3] Whether the console can actually run at 44.1 kHz: unknown (the spec pages say only 48 kHz).

## 2. Driverless status
- macOS: class compliant. Yamaha's own guide says: "Computers running Mac OSX will use a class compliant driver, so do not need any additional installation ... check that 'Yamaha TF' is available" in Sound settings, and the Yamaha Steinberg USB Driver is "for Windows (not needed for Mac OS)". [4] The TF downloads page lists the Yamaha Steinberg USB Driver only for Windows. [5]
- iOS/iPadOS over USB TO HOST: unknown (no maker source). Being class compliant on macOS suggests it may work, but nobody has confirmed it. The TF's separate "iPad" USB-A connector on the top panel is for playing audio from an iPad/iPhone (ST IN 1) and for 2-track USB storage. It is not the multitrack interface. [3]
- Windows: needs the Yamaha Steinberg USB Driver (V2.1.9 for Win 11/10 on the downloads page). [4][5]
- Mode switches: none documented for USB TO HOST on TF.

## 3. Onboard recording (no computer)
- 2 tracks only: "2-track recording via USB Storage Device". [1][2]
- Format: "48 kHz, 24-bit stereo WAV". Playback: WAV or MP3 (MP3 at 44.1/48 kHz, 128-320 kbps). [3]
- Media: FAT32, 512-byte sectors (so drives over 2 TB will not work), allocation unit 4096 bytes or larger. Use an HDD or SSD for recording: "USB memory devices and iOS devices can be used for playback only". [3] The spec page says the same: thumb drives are not supported for recording. [1]
- Recording and playback cannot run at the same time. A folder can hold at most 150 items. [3]

## 4. Recording settings
- Sample rate: 48 kHz (set by the console; the computer must match). [1][3][4] Bit depth on USB: 24-bit. [1]
- Where: RECORDER screen (cassette-tape icon on the toolbar) > INPUT/OUTPUT tab sets the 2-track record source and level. That same source also feeds USB 33/34. [3][4]
- Channel count options: fixed 34 x 34.

## 5. Routing (how sources reach each USB channel)
- Fixed blocks, not patchable per slot:
  - USB 1-32 = Direct Out of input channels CH1-32. Each channel's direct out has an on/off switch and a choice of tap point. Path: touch the channel name > CH VIEW > Direct out point button and Direct out on/off button. By default, channels 1-32 each have a Direct Output enabled to USB TO HOST. [3][4]
  - USB 33/34 = the RECORDER record source. The choices are ST L/R or a pair of mono AUX buses (1-8), plus MTRX 1/2 and MTRX 3/4 from V3.5. Path: RECORDER screen > INPUT/OUTPUT > RECORD source selection menu. [3][4]
- CH33-40 (not on TF1) and the stereo input channels have no Direct Out, "so they cannot be recorded". [4]
- TF1 and TF-Rack have 16 local mic inputs but still have CH1-32 (32 mono channels). [1][2] CH17-32 carry signal only from Tio1608-D, Dante or USB sources. [3]
- With an NY64-D card, the same CH1-32 direct outs also feed SLOT OUT 1-32 (Quick Config table). [3]
- Main mix or buses: only through USB 33/34 (one stereo pair: ST L/R, an AUX pair or a MATRIX pair). [3][4]
- Virtual soundcheck: per channel, INPUT screen > input source "USB". Menu key > "All USB" sets USB as the source for all channels on the fader layer. Per the guide, TF1/TF3 need the shortcut run again on the second layer (select CH32). [3][4] When USB is the source, the gain slider becomes digital gain and +48V is hidden. [3]
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
- The 2016 guide recommends "Pre DG" (no EQ, dynamics or effects) for live recording and virtual soundcheck, and lists Pre Fader and Post Fader as the alternatives. [4]
- Analog gain (head amp) is always before every tap. Digital gain sits between Pre DG and Pre HPF, so Pre DG is the earliest digital point. [3]
- HPF placement: Pre DG and Pre HPF are both before the HPF. Pre Fader and Post ON are after it. [3]
- Which tap is the factory default: unknown. The 2016 guide's screenshot implies Pre DG, but the text does not state it.
- Gain compensation / shared Tio gain affecting the feed: unknown (no maker statement found).

## 7. Gotchas
- Only 32 inputs are recordable. CH33-40 and ST IN cannot be recorded; the only extra is one stereo pair on 33/34. [4]
- The Mac must run at 48 kHz, or the console shows "USB Sample Rate Mismatch". [3][4]
- Onboard recording is 2-track only, and thumb drives are not supported for it. [1][3]
- iPad/iPhone over USB TO HOST is unverified.

## 8. Confidence
| Fact | Confidence |
|---|---|
| 34x34, 24-bit, 48 kHz, USB 2.0 Type-B | confirmed by maker |
| macOS class compliant, no driver | confirmed by maker (2016 guide) |
| iOS/iPadOS multitrack | unknown |
| USB 1-32 = CH1-32 direct outs; 33/34 = recorder source | confirmed by maker |
| Tap points Pre DG / Pre HPF / Pre Fader / Post ON | confirmed by maker |
| Default tap point | unknown |
| Onboard 2-track 48k/24 WAV, FAT32 | confirmed by maker |

## 9. Sources
1. https://usa.yamaha.com/products/proaudio/mixers/tf/specs.html
2. https://usa.yamaha.com/products/proaudio/mixers/tf-rack/specs.html
3. TF Series Reference Manual V4.5: https://usa.yamaha.com/files/download/other_assets/8/392718/tf5_en_rm_v45_j0.pdf (RECORDER screen p.15-16; CH VIEW direct out p.77; INPUT screen and All USB; error messages; Quick Config table p.106)
4. Yamaha "TF series Live Recording with Steinberg Nuendo Live" (Aug 2016): https://usa.yamaha.com/files/download/other_assets/5/1199125/TF_series_Live_Recording_en.pdf
5. https://usa.yamaha.com/products/proaudio/mixers/tf/downloads.html
6. TF V3.5 block diagram: https://usa.yamaha.com/files/download/other_assets/8/811748/tfv3.5_mixer_blockdiagram.pdf
