# Soundcraft Ui24R

Checked 2026-11-06. Sources are numbered in section 9.

## 1. USB audio to a computer
- "32 x 32 USB Audio Interface" over the USB-B "DAW Connection" socket. [1]
- Sample rate: 48 kHz. Harman's DAW article says Pro Tools "Sample Rate NEEDS to be 48kHz", and Ableton "should automatically set to 48kHz". [3]
- Bit depth on USB: unknown.

## 2. Driverless status
- macOS: no driver needed. Harman: "Yes, the Ui24R is Core Audio compliant. If you are using a Mac, the Mac will recognize the Ui24R as an Audio Interface automatically." [2] Ui series on macOS Sequoia: "plug and play ... no additional driver needed". [4]
- The 2017 v1.0 manual says "requires the use of the Soundcraft SI Impact Audio Driver for multichannel USB playback and recording". The newer Harman FAQ limits that to PC. [1][2]
- iOS/iPadOS over USB: unknown (no maker source).
- Windows: needs the Soundcraft Multi-Channel USB Audio Driver (V3.20 or later). [2][3]
- Only one Ui24R can be connected to a computer at a time. Channels from a cascaded remote mixer do not reach the DAW. [5]

## 3. Onboard recording (no computer)
- Up to 22 tracks to a USB drive in the front "MEDIA - REC" socket, plus 2-track stereo recording. [1][6]
- Media (Harman FAQ): FAT32 only, 32 GB or less, write speed of 25 MB/s or more. USB 3.0 is required for multitrack. [1][7] An SD/microSD card in a USB adapter also works (FAT32, 32 GB or less, UHS-3/V30). [8]
- File format of the onboard multitrack: unknown from maker text. The Ui Session Maker converts imported files to "FLAC 24bit" for the multitrack player, which suggests the native multitrack format is FLAC, but nothing states it. [6][9] Correction to the brief: "WAV or FLAC" is not confirmed.
- 2-track: "2 TRK RECORD MODE" setting with 32-bit, 24-bit or 16-bit. [1]

## 4. Recording settings
- 48 kHz fixed (see section 1). 2-track bit depth: Settings > 2 TRK RECORD MODE. [1]
- Multitrack: PLAYER > MULTITRACK page (sessions, record button). Soundcheck mode can be engaged here or at SETTINGS > PATCHING > OVERVIEW. [1]

## 5. Routing (how sources reach each USB channel)
- USB sends to the DAW are fixed, not patchable. "No USB send patching is required on the Ui24R's end, it automatically is set ... First 10 channels are your Masters (L, R, Aux Buses 1-8), so the input channels start at patch point 11." [3]
  - USB 1-2 = Master L/R
  - USB 3-10 = AUX 1-8
  - USB 11-32 = channels/inputs 1-22 [1][3]
  - Harman (in an article tagged Si that also covers Ui): "Patching is not switchable on the Ui, so the sends to the DAW from the mixes is 3-10 (corresponding to Mix 1-8)." [10]
- The onboard multitrack tracks are "recorded directly from the mic preamps". Even if a channel is re-patched (for example to a DAW return), its track still records the physical input jack and preamp. [11]
- USB returns: SETTINGS > PATCHING > CHANNELS, then USB DAW 1-16/17-32 on top, then Patch 1:1 or individual points. Any of the 32 DAW returns can go to any channel, and from firmware V2 also directly to hardware outputs. [3][6] Channels 21-24 can take DAW or local inputs but not the internal multitrack player. [6]
- Virtual soundcheck from the onboard recorder: Soundcheck patch set, activated at SETTINGS > PATCHING > OVERVIEW or PLAYER > MULTITRACK. [1]
- When to use which:
  - Inputs: USB 11-32.
  - Main mix: USB 1-2. It is post-processing, per the forum, secondary.
  - A processed or post-fader version of a channel: use an AUX as a group. Set it to POST and POST PROC, send the channel at 0 dB, and record USB 3-10. [10]
  - Reordering tracks: not possible on the console.

## 6. Tap points
- Input tracks (onboard and USB 11-32): after the mic preamp, before processing and before the fader. [10][11]
  - Harman: "Recording from channels will only be pre-fader, pre-processing." [10]
  - Harman: "The tracks are recorded directly from the mic preamps." [11]
  - Analog preamp gain therefore affects the recording. Channel EQ, dynamics, HPF and fader do not (HPF placement relative to the tap is implied by "pre-processing", not stated).
- Secondary (Soundcraft forum, via search snippet; the page could not be fetched): "Post gain ... pre mute, pre gate, pre comp, pre EQ, pre fader". [12]
- Not selectable per channel. AUX sends have PRE/POST and PRE/POST PROCESSING options, which is the documented workaround. [1][10]

## 7. Gotchas
- DAW track numbers are offset by 10: input 1 arrives on USB 11. [3]
- The onboard recorder needs a fast FAT32 stick of 32 GB or less, which is getting hard to find. [7][8]
- The 2017 manual says a driver is required for USB audio. The current FAQ says not on Mac. A guide should cite the FAQ. [1][2]
- iPad support is unknown.

## 8. Confidence
| Fact | Confidence |
|---|---|
| 32x32 USB, 48 kHz | confirmed by maker |
| Mac Core Audio compliant, no driver; Windows driver | confirmed by maker |
| iOS/iPadOS | unknown |
| USB map 1-2 LR, 3-10 AUX, 11-32 inputs; not patchable | confirmed by maker |
| Input tap post-preamp, pre-processing, pre-fader | confirmed by maker |
| Onboard 22-track to USB, FAT32 32 GB or less, 25 MB/s | confirmed by maker |
| Onboard multitrack file format | unknown (FLAC implied) |
| USB bit depth | unknown |

## 9. Sources
1. Ui24R User Manual v1.0: https://www.soundcraft.com/en-US/product_documents/ui24r_manual_v1-0_web-pdf (5.6 Patching; 9.0 Media; 10.0 Settings)
2. Harman FAQ "Ui24R Core Audio Compliance": https://harman.helpjuice.com/sc-ui-series/ui24r-core-audio-compliance
3. Harman "Ui24R Multitrack Recording with a DAW": https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-multitrack-recording-with-a-daw
4. Harman "Ui series compatibility with macOS Sequoia": https://harman.helpjuice.com/en_US/sc-ui-series/ui-series-compatibility-with-macos-sequoia
5. Harman "Ui24R cascade mode does not allow more DAW channels": https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-cascade-mode-does-not-allow-more-daw-channels
6. Ui24R v2.0 User Guide Addendum: https://www.soundcraft.com/en-US/product_documents/ui24r_v2-0_user_guide_addendum-pdf
7. Harman "Ui24R USB direct recording requirements": https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-usb-direct-recording-requirements
8. Harman "SD and Micro SD for recording on the Ui24R": https://harman.helpjuice.com/en_US/sc-ui-series/sd-and-micro-sd-for-recording-on-the-ui24r
9. Harman "Creating playable multitrack session ...": https://harman.helpjuice.com/en_US/sc-ui-series/creating-playable-multitrack-session-from-imported-audio-files-on-ui24r-with-usb-stick
10. Harman "Recording from groups to achieve post-fader processing and effect": https://harman.helpjuice.com/en_US/sc-ui-series/recording-from-groups-to-achieve-post-fader-processing-and-effect
11. Harman "Ui24R record track labels": https://harman.helpjuice.com/en_US/sc-ui-series/ui24r-record-track-labels
12. Secondary, forum: https://proforums.harman.com/soundcraft/discussion/comment/198507
13. Product page: https://www.soundcraft.com/en-US/products/ui24r
