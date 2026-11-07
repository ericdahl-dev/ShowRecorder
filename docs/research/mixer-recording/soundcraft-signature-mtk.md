# Soundcraft Signature 12 MTK and 22 MTK

Checked 2026-11-06. Sources are numbered in section 9. Both models are marked "Discontinued" on soundcraft.com. [3]

## 1. USB audio to a computer
- 12 MTK: 14 in / 12 out. 22 MTK: 24 in / 22 out. "Up to 48khz, 24-bit". Standard USB 2.0, Type-B socket. [1][2]
- Sample rates: 44.1 and 48 kHz only. The REAPER walkthrough says "44.1 kHz recording should be entered as 44100 and 48 kHz ... as 48000. NOTE: higher sample rates are not compatible". [2]
- 22 MTK: the USB-A socket next to PHANTOM POWER is for power only, "Not for data". It "supplies USB 2.0 compliant 500mA", for example a USB lamp "or a mobile phone". [4] The 12 MTK is not covered by [4] (unknown).

## 2. Driverless status
- macOS: no driver. "MAC computers do not require these drivers as the Signature MTK USB audio interface uses Apple Core Audio drivers." [1]
- iOS/iPadOS: maker says it works. The USB port is "compatible with any MAC or PC as well as an iPad (using a Camera Connectivity Kit)". [1]
- The product page lists Mac support only for "Mac OS 10.7.x Lion through 10.11.x El Capitan". It predates current macOS, so there is no maker statement for newer versions. [3]
- Windows: Soundcraft Multichannel USB ASIO/WDM driver (V3.20) with a control panel for buffer size and streaming mode. [1][3]
- Mode switches: none documented. [1][4]

## 3. Onboard recording
- None.

## 4. Recording settings
- Sample rate is set by the host: 44.1 or 48 kHz, 24-bit. [1][2] The 22 MTK spec lists "Multi-channel USB Audio (22MTK) - Sampling rate: 44.1kHz / 48kHz". [4]
- On Windows, buffer size and streaming mode are set in the Soundcraft driver control panel. [1]
- Clock: the console has no word clock or clock menu documented (unknown).
- File format: decided by the recording app.

## 5. Routing (how sources reach each USB channel)
- Fixed, not patchable: [1][4]
  - USB 1-12 (12 MTK) or 1-22 (22 MTK) = input channels 1-n, numbered by console channel. 22 MTK: "Signature input channels 1-22 use USB audio channels 1-22." [4]
  - Stereo channels send L on the odd number and R on the even number. On a mic/line stereo channel such as 9/10, the mic or L/mono jack goes to the odd USB channel and the R jack to the even one. [1]
  - USB 13/14 (12 MTK) or 23/24 (22 MTK) = Master L/R, "always active", post-fader. [1][4]
  - Aux buses to USB: no maker source mentions it, and no option was found. Treat as not possible (unknown, not maker-stated).
- Returns: per channel, the USB RTN button on each strip. USB channel n replaces input n "post-gain (pre HPF / EQ) and the analogue audio path will be broken". Used for virtual soundcheck, DAW inserts and playback. [1][4]
  - The send never stops: "The analogue input to an input channel will ALWAYS be SENT via the corresponding USB audio channel", even with USB RTN on. [4] So arm only the tracks you mean to record, or the DAW can record its own playback.
- Stereo playback: channels 11/12 (12 MTK) or 21/22 (22 MTK), which are excluded from interval mute. [1]
- When to use which:
  - Inputs: USB 1-n.
  - Main mix: the last pair. It is analog-summed and converted after the summing, so it needs a healthy fader level. [1]
  - Reordering: not possible on the console.

## 6. Tap points
- Input channels: "ALWAYS send their post-gain, pre-EQ signal". The return replaces the signal "just after the USB output tap: post-gain, pre-EQ" and "post-gain (pre HPF / EQ)". [1][4]
  - So the tap is after the analog gain, before the HPF, EQ and fader.
  - Whether the channel's dbx limiter (on selected channels) is before or after the tap: not stated (unknown).
  - It is a single fixed point, not selectable. There is no digital trim (the console is analog).
  - 22 MTK gain range: 10 dB to 60 dB. [4] 12 MTK: not checked.
- Master L/R: post-fader, after analog summing. [1]

## 7. Gotchas
- Discontinued, and the official macOS support list stops at 10.11. Current macOS is likely to work because it uses Core Audio, but Soundcraft has not said so. [1][3]
- 48 kHz maximum. [1][2][4]
- Gain staging on the analog preamp sets the recording level directly (follows from the post-gain tap). [1][4]
- The non-MTK Signature 16 and 22 have only 2-channel USB. Check the model name says MTK. [4]

## 8. Confidence
| Fact | Confidence |
|---|---|
| 14x12 / 24x22, up to 48 kHz 24-bit, USB 2.0 Type-B | maker |
| 44.1 and 48 kHz only | maker |
| Mac no driver (Core Audio); iPad via Camera Connection Kit | maker |
| iPhone | unknown |
| Fixed map; last pair = LR post-fader | maker |
| Input tap post-gain, pre-HPF/EQ, fixed | maker |
| dbx limiter before or after the tap | unknown |
| Aux buses to USB | unknown (no option found) |
| Current macOS support | unknown (listed up to 10.11) |

## 9. Sources
1. Soundcraft Signature MTK Recording Guide (Harman): https://harman.helpjuice.com/en_US/soundcraft-signature-mtk-recording-guide
2. Same guide as PDF: https://www.soundcraft.com/en-US/product_documents/soundcraft_signaturemtk_recordingguide-pdf-9360dc07-d05a-411b-8759-b15f6664b458 (Graph 1; REAPER sample rate note)
3. Product pages: https://www.soundcraft.com/en-US/products/signature-22-mtk and https://www.soundcraft.com/en-US/products/signature-12-mtk
4. Signature 16, 22, 22MTK User Manual: https://www.soundcraft.com/en-US/product_documents/soundcraft_signature_16-22_user_guide-pdf-90501050-7f3c-46c3-8d93-50a286334ded (USB I/O; USB RTN; section 7.2)

Note: spec quotes for the 22 MTK USB socket, sample rates and gain range come from source 4, which does not cover the 12 MTK.

Editions: the Recording Guide PDF (source 2) shows no date or edition; its file was made in March 2016. The help-center page (source 1) says "Updated at February 10th, 2026" and has the same text. The User Manual (source 4) is Rev 1.1, "E&OE September 2014", part no. 5056808.

The Recording Guide PDF and the User Manual PDF were read in full on 2026-11-07 (`pdftotext -layout`), as downloaded from soundcraft.com, which redirects to adn.harmanpro.com. They match the notes above. Added from that read, for the guide (#1073):
- 22 MTK bit depth: "Bit Depth: 16-bit, 24-bit" (source 4, specs).
- Mute: "a pre-fade mute and so does not affect the USB send on the Signature 22MTK console" (source 4, 5.1.1).
- Limiters: on the 22 MTK, "channels 1 and 2 incorporate switchable input limiters" (source 4, 4.1). Place relative to the USB tap still not stated.
- The Signature 16 and 22 (no MTK) "have 2-track USB input and output functionality", with a USB SEND switch for the main mix or Aux 1-2 (source 4, 7.1).
- Windows control panel: "Reliable" with 1024 samples is clean; "Low Latency" with 128; "Reliable" with 64 "would result in distorted audio" (source 2).
- Before playback, turn off record "to avoid recording over your recorded show" (source 2, REAPER).
- Mac stereo playback: Audio MIDI Setup, Configure Speakers, outputs 11/12 (21/22 on the 22 MTK) (source 2).

## Gaps

- iPhone: not named by Soundcraft. Say "not tested yet".
- iPad with USB-C: not discussed (the guide names a Camera Connection Kit only). Say "camera adapter".
- macOS newer than 10.11: not listed. Say "uses Core Audio; current macOS not listed by Soundcraft".
- dbx limiter position relative to the USB tap: unknown. Don't say the recording is "before the limiter".
- Aux buses to USB: no maker statement. Say "only inputs and Main L/R reach USB" and label it as what the docs show.
- 12 MTK: USB power socket, gain range and spec sample-rate line were checked only in the 22 MTK manual. Leave 12 MTK specifics out or label them.
- Clock / sync: not documented. Leave out.
- Phone power: the 22 MTK has a separate 500 mA USB-A charging socket (not the audio port). Whether it keeps an iPhone charged during a show: unknown. Recommend a powered adapter.
