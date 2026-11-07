# Soundcraft Ui24R

Checked 2026-11-06. Sources are numbered in section 9.

## 1. USB audio to a computer
- "32 x 32 USB Audio Interface" over the USB-B "DAW Connection" socket. [1]
- Sample rate: 48 kHz. Harman's DAW article says Pro Tools "Sample Rate NEEDS to be 48kHz", and Ableton "should automatically set to 48kHz". [3]
- Bit depth on USB: unknown (no maker source states it).
- The manual calls it "a 32 x 32 USB Audio Interface with CORE Audio and ASIO drivers". [1]

## 2. Driverless status
- macOS: no driver needed. Harman: "Yes, the Ui24R is Core Audio compliant. If you are using a Mac, the Mac will recognize the Ui24R as an Audio Interface automatically." [2] Ui series on macOS Sequoia: "plug and play ... no additional driver needed". [4]
- The 2017 v1.0 manual says "requires the use of the Soundcraft SI Impact Audio Driver for multichannel USB playback and recording". The newer Harman FAQ limits that to PC. [1][2]
- iOS/iPadOS over USB: unknown (no maker source).
- Windows: needs the Soundcraft Multi-Channel USB Audio Driver (V3.20 or later). [2][3]
- Only one Ui24R can be connected to a computer at a time. Channels from a cascaded remote mixer do not reach the DAW. [5]

## 3. Onboard recording (no computer)
- Up to 22 tracks to a USB drive in the front "MEDIA - REC" socket, plus 2-track stereo recording. [1][6] The manual: "multitrack record up to 22 separate tracks which can then be imported into any DAW software". [1]
- Media: "formatted in FAT32 only", "32GB or less in size", read/write speed "25mb/s or higher" (Harman FAQ). [7] The manual adds: "Multi-track USB Playback will require a minimum of USB 3.0 with a transfer rate of 25mb/s." [1] The FAQ does not mention a USB version. An SD/microSD card in a USB adapter also works (FAT32, 32 GB or less, UHS-3/V30). [8]
- A speed buffer indicator in the player goes green, yellow, orange, then shows an error if the stick is too slow. [1]
- File format of the onboard multitrack: **secondary only.** No maker document we read states it. A 2017 Sound On Sound review (linked from the soundcraft.com product page) says "the multitrack format is either uncompressed WAV or the more space-efficient FLAC" and that "The USB bit depth and file format can be chosen within the settings page." [14] The Ui Session Maker converts imported files to "FLAC 24bit" for the multitrack player. [6][9] Exact menu name for the multitrack format setting: unknown.
- 2-track: "2 TRK RECORD MODE" setting with 32-bit, 24-bit or 16-bit (the manual's description line says "sample rate", but the options are bit depths). [1]

## 4. Recording settings
- 48 kHz fixed for USB to a DAW (see section 1). [3] The onboard recorder's sample rate is not stated by the maker (unknown).
- 2-track bit depth: Settings > 2 TRK RECORD MODE. [1]
- Multitrack bit depth and WAV/FLAC choice: in Settings per one secondary source (2017 review). [14] Which bit depths are offered: unknown.
- Multitrack: PLAYER > MULTITRACK page (sessions, record button). Soundcheck mode can be engaged here or at SETTINGS > PATCHING > OVERVIEW. [1] Track selection is on the Multitrack Config page, whose track labels can be wrong after re-patching (see section 6). [11]
- Clock: no word clock or external sync documented (unknown).

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
  - Harman (article tagged for Si, body also covers the Ui; not Ui24R-specific): "Recording from channels will only be pre-fader, pre-processing." [10]
  - Harman (Ui24R article, onboard recorder only): "The tracks are recorded directly from the mic preamps." Re-patching a channel does not change this: "the record 'send' is the physical input jack and preamp on the mixer." [11]
  - No maker source says in so many words that USB 11-32 use the same point as the onboard recorder. Both sources point that way.
  - Analog preamp gain therefore affects the recording. Channel EQ, dynamics, HPF and fader do not (HPF placement relative to the tap is implied by "pre-processing", not stated).
- Secondary (Soundcraft forum, via search snippet; the page could not be fetched): "Post gain ... pre mute, pre gate, pre comp, pre EQ, pre fader". [12]
- Not selectable per channel. AUX sends have PRE/POST and PRE/POST PROCESSING options, which is the documented workaround. [1][10]

## 7. Gotchas
- DAW track numbers are offset by 10: input 1 arrives on USB 11. [3]
- The onboard recorder needs a fast FAT32 stick of 32 GB or less, which is getting hard to find. [7][8]
- The 2017 manual says a driver is required for USB audio. The current FAQ says not on Mac. A guide should cite the FAQ. [1][2]
- iPad and iPhone over USB are unknown (no maker source).
- Onboard multitrack track labels on the Multitrack Config page can show the patched label rather than the physical input that is really recorded. [11]

## 8. Confidence
| Fact | Confidence |
|---|---|
| 32x32 USB, 48 kHz | maker |
| Mac Core Audio compliant, no driver; Windows driver | maker |
| iOS/iPadOS | unknown |
| USB map 1-2 LR, 3-10 AUX, 11-32 inputs; not patchable | maker |
| Onboard tap = physical input and preamp, pre-processing | maker (Ui24R article [11]) |
| USB 11-32 tap pre-fader, pre-processing | maker, but from an Si-tagged article that covers Ui generally [10] |
| Onboard 22-track to USB, FAT32 32 GB or less, 25 MB/s | maker |
| USB 3.0 for multitrack | maker manual (playback sentence); not in the FAQ |
| Onboard multitrack format WAV or FLAC, set in Settings | secondary (2017 review) |
| Onboard recorder sample rate | unknown |
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
14. Secondary, review: Mike Crofts, "Soundcraft Ui24R", Sound On Sound, August 2017 (linked from soundcraft.com as https://www.soundcraft.com/en-US/product_reviews/soundcraft-ui24r): https://www.soundonsound.com/reviews/soundcraft-ui24r

## Gaps

- iPhone and iPad over USB: no maker source. Say "not tested yet".
- Onboard multitrack file format: secondary only (WAV or FLAC). Say "WAV or FLAC, set in Settings (per a 2017 review)" or leave out. Bit-depth options and exact menu name unknown.
- Onboard recorder sample rate: not stated by the maker. Leave out, or test.
- USB bit depth to a computer: unknown. Leave out.
- USB 11-32 tap: Harman's wording comes from an Si-tagged article; the Ui24R-specific article covers only the onboard recorder. Say "pre-processing, pre-fader, per Harman" and avoid naming the exact point (for example "pre-HPF") as fact.
- HPF before or after the input tap: implied by "pre-processing", not stated. Say "before channel processing".
- Main mix on USB 1-2 being post-processing: forum only. Label it.
- USB stick larger than 32 GB: Harman says 32 GB or less. Don't repeat forum reports of larger sticks working.
- Clock / sync: not documented. Leave out.
