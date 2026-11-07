# Yamaha DM3 / DM3 Standard

Checked 2026-11-06. Sources are numbered in section 9.

## 1. USB audio to a computer
- Up to 18 in / 18 out, "96 kHz/32-bit audio interface", USB Type-B "USB TO HOST" connector (USB 2.0 per the spec page). [1][2][3]
- The spec page says: "PC/Mac Recording 18 track, Playback 18 track". [1]
- Sample rate: the console's leader clock is 48 kHz or 96 kHz (SETUP > WORD CLOCK). [2]
- Firmware V2.0 added a second USB "Driver Mode" (details in section 2). [2][5]

## 2. Driverless status
- Yamaha says a driver is required, without naming an operating system:
  - Reference manual: "It is necessary to install Yamaha Steinberg USB Driver in order to communicate with a computer." [2]
  - Owner's manual: "Installing Yamaha Steinberg USB Driver is required for communication with a computer." [3]
- Correction to the brief: the DM3 downloads page does list a Mac driver. It offers "Yamaha Steinberg USB Driver V3.1.7 for Mac macOS 26, 15-11" and V2.1.4 for macOS 10.13-10.15, as well as the Windows driver. [4] (The TF page lists only the Windows driver.)
- macOS without the driver: unknown.
  - Secondary (Ardour forum, 2024-08-12): a user who set one up on a Mac believed the driver was needed, partly because from V2.0 "the DM3 can present itself as 4 different audio interfaces". [6]
  - Secondary (same thread): a user quotes a Yamaha support reply saying the driver requirement "let us think, that a none USB class compliant audio interface is used, but we cannot confirm that". [6]
- iOS/iPadOS: unknown (no maker source). Treat it as unsupported until someone tests it, because the maker says a driver is required.
- Windows: Yamaha Steinberg USB Driver V2.1.9. [4]
- Mode switch: SETUP > (USB section) "Driver Mode", Mode1 or Mode2. Changing it prompts a console restart. [2] Per the manual's table: [2]
  - Mode1: Windows WDM1 2/2 + ASIO 18/18; Mac 18 in / 18 out.
  - Mode2: Windows WDM1-3 2/2 each + ASIO 12/12; Mac 2/2 + 2/2 + 2/2 + 12/12 (four devices).
  - Yamaha's V2.0 news release: "Mode 1, which allows 18 channels to be connected to a single application, Mode 2 allows connection to up to four applications". [5]
  - So multitrack to one app needs Mode1 (18 ch). Mode2 caps the multitrack device at 12.

## 3. Onboard recording (no computer)
- 2-track only: "Recording 2 track" on the spec page. The RECORDER records "a 2 MIX source (STEREO or MIX channel)". [1][2]
- Formats: WAV 48 kHz/24-bit or WAV 96 kHz/24-bit (96k needs the 96 kHz leader clock); MP3 48 kHz at 128/256/320 kbps. [2]
- Media: FAT32 or exFAT (exFAT from V2.0). Speed must match an HDD/SSD. A WAV file is capped at 2 GB, and recording continues as seamless 2 GB files. At most 150 items per folder. [2][5]

## 4. Recording settings
- Clock: SETUP > WORD CLOCK > leader clock 48 kHz or 96 kHz. [2] USB bit depth "32-bit" per the manual. [2]
- Driver Mode: SETUP > USB section (Mode1/Mode2). [2]
- Onboard format: RECORDER (INPUT/OUTPUT) screen > recording format menu. Record source: RECORDER PATCH screen. [2]

## 5. Routing (how sources reach each USB channel)
- Per-port patching. USB OUT 1-18 are output ports, patched from SETUP > PATCH > OUTPUT (select the port, then the source channel) or from OUTPUT > OUTPUT CH PATCH. [2]
- Defaults: "USB 1-16 = INPUT 1-16, USB 17-18 = STEREO L/R". [2]
- Which source channels the USB ports offer: only partly documented in text. The manual says output ports can carry "output signals of output-related channels (MIX, MATRIX, STEREO (L/R), monitor signals (MONITOR OUT L/R channel) and direct output signals of INPUT channels)". That passage is about OMNI OUT and I/O devices; that the same list applies to USB is likely but not stated. [2]
- Insert points can also use USB ports: INSERT screen > INSERT OUT/IN PATCH = USB. Using them takes USB channels away from recording. [2]
- Virtual soundcheck: SETUP > PATCH > INPUT, menu "All USB", or per channel via INPUT CH PATCH > USB. Only CH1-16 can be switched to USB ("assign the [USB TO HOST] connector ... as the input source for CH 1-16"). With USB as the source, the gain slider becomes digital gain. [2]
- When to use which:
  - The default gives 16 inputs plus the stereo mix.
  - To record a MIX or MATRIX instead of the stereo mix, re-patch USB 17-18.
  - Any USB port can be re-patched one at a time, which also allows reordering. The total is 18.

## 6. Tap points
- No selectable "direct out point" setting was found in the reference manual (C0, published 01/2025).
- What tap feeds USB when a port is patched to "INPUT n": unknown.
- Related points that do exist: [2]
  - Insert point: Pre EQ / Pre Fader / Post ON.
  - Pre-fader send point (BUS SETUP): Pre EQ / Pre Fader.
  - Meter points: PRE HPF / PRE FADER / POST ON for inputs.
- Analog gain vs digital gain: the INPUT screen has a separate digital gain box. [2] Whether the USB feed is before or after it: unknown.

## 7. Gotchas
- A driver is required per Yamaha, and a Mac driver exists. iPhone/iPad support is unproven and doubtful.
- Driver Mode must be Mode1 to get 18 channels into one app. Mode2 splits the channels into 2/2/2/12. [2][5]
- Only 16 mic inputs plus 2 slots (18 total), and onboard recording is 2-track only.
- The USB 96 kHz claim comes from the manual. The bit depth on the host side depends on the driver.

## 8. Confidence
| Fact | Confidence |
|---|---|
| 18x18 USB, Type-B, 48/96 kHz | confirmed by maker |
| Driver required (Yamaha Steinberg USB Driver), Mac driver offered | confirmed by maker |
| Class compliant on macOS without the driver | unknown (secondary says no) |
| iOS/iPadOS | unknown |
| Driver Mode1/Mode2 channel splits | confirmed by maker |
| Default USB patch 1-16 = INPUT 1-16, 17-18 = STEREO | confirmed by maker |
| Per-port output patching for USB | confirmed by maker |
| Tap point of INPUT n on USB | unknown |
| Onboard 2-track WAV 48k/96k 24-bit, MP3 | confirmed by maker |

## 9. Sources
1. https://usa.yamaha.com/products/proaudio/mixers/dm3/specs.html
2. DM3 Series Reference Manual (C0, 01/2025): https://usa.yamaha.com/files/download/other_assets/6/1626436/DM3_RM_En_C0.pdf (USB TO HOST p.~31; RECORDER p.64-71; SETUP USB section "Driver Mode" p.92; WORD CLOCK p.104; PATCH p.111; INSERT p.198-199; default patches p.356). HTML version: https://manual.yamaha.com/pa/mixers/dm3/rm/en-US/
3. DM3 Owner's Manual: https://usa.yamaha.com/files/download/other_assets/1/1525801/dm3_en_om_b1.pdf
4. https://usa.yamaha.com/products/proaudio/mixers/dm3/downloads.html and https://usa.yamaha.com/support/updates/yamaha_steinberg_usb_driver_v317_for_mac.html
5. Yamaha DM3 V2 firmware news release (2024-05-16): https://in.yamaha.com/en/news_events/2024/0516_dm3_v2.html
6. Secondary, forum: https://discourse.ardour.org/t/yamaha-mixers-on-linux/110559
7. DM3 block diagram: https://usa.yamaha.com/files/download/other_assets/7/1619577/DM3_BD_En_C0.pdf
