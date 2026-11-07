# Soundcraft Signature 12 MTK and 22 MTK

Checked 2026-11-06. Sources are numbered in section 9. Both models are marked "Discontinued" on soundcraft.com. [3]

## 1. USB audio to a computer
- 12 MTK: 14 in / 12 out. 22 MTK: 24 in / 22 out. "Up to 48khz, 24-bit". Standard USB 2.0, Type-B socket. [1][2]
- Sample rates: 44.1 and 48 kHz only. The REAPER walkthrough says "44.1 kHz recording should be entered as 44100 and 48 kHz ... as 48000. NOTE: higher sample rates are not compatible". [2]
- The USB-A socket near PHANTOM POWER is for power only (lamps, charging), not data. [4]

## 2. Driverless status
- macOS: no driver. "MAC computers do not require these drivers as the Signature MTK USB audio interface uses Apple Core Audio drivers." [1]
- iOS/iPadOS: maker says it works. The USB port is "compatible with any MAC or PC as well as an iPad (using a Camera Connectivity Kit)". [1]
- The product page lists Mac support only for "Mac OS 10.7.x Lion through 10.11.x El Capitan". It predates current macOS, so there is no maker statement for newer versions. [3]
- Windows: Soundcraft Multichannel USB ASIO/WDM driver (V3.20) with a control panel for buffer size and streaming mode. [1][3]
- Mode switches: none on the console.

## 3. Onboard recording
- None.

## 4. Recording settings
- Sample rate is set by the host: 44.1 or 48 kHz, 24-bit. [1][2]

## 5. Routing (how sources reach each USB channel)
- Fixed, not patchable: [1][4]
  - USB 1-12 (12 MTK) or 1-22 (22 MTK) = input channels 1-n, numbered by console channel.
  - Stereo channels send L on the odd number and R on the even number. On a mic/line stereo channel such as 9/10, the mic or L/mono jack goes to the odd USB channel and the R jack to the even one. [1]
  - USB 13/14 (12 MTK) or 23/24 (22 MTK) = Master L/R, "always active", post-fader. [1][4]
  - Aux buses cannot be sent to USB on MTK: no option found.
- Returns: per channel, the USB RTN button on each strip. USB channel n replaces input n "post-gain (pre HPF / EQ) and the analogue audio path will be broken". Used for virtual soundcheck, DAW inserts and playback. [1][4]
- Stereo playback: channels 11/12 (12 MTK) or 21/22 (22 MTK), which are excluded from interval mute. [1]
- When to use which:
  - Inputs: USB 1-n.
  - Main mix: the last pair. It is analog-summed and converted after the summing, so it needs a healthy fader level. [1]
  - Reordering: not possible on the console.

## 6. Tap points
- Input channels: "ALWAYS send their post-gain, pre-EQ signal". The return replaces the signal "just after the USB output tap: post-gain, pre-EQ" and "post-gain (pre HPF / EQ)". [1][4]
  - So the tap is after the analog gain, before the HPF, EQ, dbx limiter and fader.
  - It is a single fixed point, not selectable. There is no digital trim (the console is analog).
- Master L/R: post-fader, after analog summing. [1]

## 7. Gotchas
- Discontinued, and the official macOS support list stops at 10.11. Core Audio class compliance makes current macOS likely but unconfirmed by the maker. [1][3]
- 48 kHz maximum.
- Gain staging on the analog preamp sets the recording level directly.

## 8. Confidence
| Fact | Confidence |
|---|---|
| 14x12 / 24x22, up to 48 kHz 24-bit, USB 2.0 Type-B | confirmed by maker |
| 44.1 and 48 kHz only | confirmed by maker |
| Mac no driver (Core Audio); iPad via Camera Connection Kit | confirmed by maker |
| Fixed map; last pair = LR post-fader | confirmed by maker |
| Input tap post-gain, pre-HPF/EQ, fixed | confirmed by maker |
| Current macOS support | unknown (listed up to 10.11) |

## 9. Sources
1. Soundcraft Signature MTK Recording Guide (Harman): https://harman.helpjuice.com/en_US/soundcraft-signature-mtk-recording-guide
2. Same guide as PDF: https://www.soundcraft.com/en-US/product_documents/soundcraft_signaturemtk_recordingguide-pdf-9360dc07-d05a-411b-8759-b15f6664b458 (Graph 1; REAPER sample rate note)
3. Product pages: https://www.soundcraft.com/en-US/products/signature-22-mtk and https://www.soundcraft.com/en-US/products/signature-12-mtk
4. Signature 16, 22, 22MTK User Manual: https://www.soundcraft.com/en-US/product_documents/soundcraft_signature_16-22_user_guide-pdf-90501050-7f3c-46c3-8d93-50a286334ded (USB I/O; USB RTN; section 7.2)
