# Yamaha DM3 / DM3 Standard

Checked 2026-11-06. Sources are numbered in section 9. Audited 2026-11-06 against the maker PDFs and pages listed there.

## 1. USB audio to a computer
- Up to 18 in / 18 out, "96 kHz/32-bit audio interface", USB Type-B "USB TO HOST" connector, USB 2.0. [1][2][3]
- The spec page says: "PC/Mac Recording 18 track, Playback 18 track" and "USB Type-B, USB2.0". [1]
- Sample rate: the console's leader clock is 48 kHz or 96 kHz (SETUP > WORD CLOCK). The spec page lists "96 kHz / 48 kHz". [1][2] 44.1 kHz is not listed.
- Bit depth: the reference manual's spec table gives USB TO HOST "Data Length 32-bit". [2]
- Firmware V2.0 added a second USB "Driver Mode" (details in section 2). [2][5]

## 2. Driverless status
- Yamaha says a driver is required, without naming an operating system:
  - Reference manual: "It is necessary to install Yamaha Steinberg USB Driver in order to communicate with a computer." [2]
  - Owner's manual: "Installing Yamaha Steinberg USB Driver is required for communication with a computer." [3]
- The DM3 downloads page lists a Mac driver: "Yamaha Steinberg USB Driver V3.1.7 for Mac macOS 26, 15-11 (Intel/Apple silicon)" and V2.1.4 for macOS 10.15-10.13, plus V2.1.9 for Windows 11/10. [4] (The TF page lists only the Windows driver.)
- macOS without the driver: unknown.
  - Secondary (Ardour forum, 2024-08-12): a user who set one up on a Mac believed the driver was needed, partly because from V2.0 "the DM3 can present itself as 4 different audio interfaces". [6]
  - Secondary (same thread): a user quotes a Yamaha support reply saying the driver requirement "let us think, that a none USB class compliant audio interface is used, but we cannot confirm that". [6]
- iOS/iPadOS: unknown. No Yamaha source names iPhone or iPad for USB audio on DM3. The iPad is named only for wireless control apps such as DM3 StageMix, not for audio. [2][3] Treat it as unsupported until someone tests it, because the maker says a driver is required.
- Windows: Yamaha Steinberg USB Driver V2.1.9. [4]
- Mode switch: SETUP > USB section > "Driver Mode", Mode1 or Mode2. Changing it prompts a console restart. [2] Per the manual's table: [2]
  - Mode1: Windows WDM1 2/2 + ASIO 18/18; Mac 18 in / 18 out.
  - Mode2: Windows WDM1-3 2/2 each + ASIO 12/12; Mac 2/2 + 2/2 + 2/2 + 12/12 (four devices).
  - Yamaha's V2.0 news release: "Mode 1, which allows 18 channels to be connected to a single application, Mode 2 allows connection to up to four applications". [5]
  - So multitrack to one app needs Mode1 (18 ch). Mode2 caps the multitrack device at 12.
  - The factory setting of Driver Mode: not stated in the manual (unknown).

## 3. Onboard recording (no computer)
- 2-track only: "Recording 2 track" on the spec page. The RECORDER records "a 2 MIX source (STEREO or MIX channel)". [1][2]
- Formats: WAV 48 kHz/24-bit or WAV 96 kHz/24-bit (96k needs the 96 kHz leader clock); MP3 48 kHz at 128/256/320 kbps. [2]
- Media: FAT32 or exFAT (exFAT from V2.0). [2][5]
  - The manual says to use a device "that can write at the speed of a HDD or SSD" and to test it first. [2] The spec page lists recording to "USB hard disk / SSD / flash memory". [1] So a fast flash drive is allowed, but test it.
  - A WAV file is capped at 2 GB. The V2.0 news release says recording "will continue as multiple, seamless 2Gb WAV files". [5] The manual (C0) only says "split the data when it exceeds 2 GB". [2]
  - At most 150 items per folder. [2]

## 4. Recording settings
- Clock: SETUP > WORD CLOCK > leader clock 48 kHz or 96 kHz. [2] The computer must match, or the console shows "USB Sample Rate Mismatch". [2]
- USB bit depth: 32-bit per the manual. [2] What bit depth a DAW reports: unknown (depends on the driver; not tested).
- Driver Mode: SETUP > USB section (Mode1/Mode2). [2]
- Channel count: fixed at 18 in Mode1; 12 for the multitrack device in Mode2. No other count options were found. [2]
- Onboard format: RECORDER screen > recording format menu. Record source: RECORDER PATCH screen. [2]

## 5. Routing (how sources reach each USB channel)
- Per-port patching. USB 1-18 are output ports, patched from SETUP > PATCH > OUTPUT (select the destination port, then the source channel). [2] For output channels (MIX, MATRIX, STEREO), the OUTPUT screen > OUTPUT CH PATCH screen does the same from the channel side. [2]
- Defaults: "USB 1-16 = INPUT 1-16, USB 17-18 = STEREO L/R" (manual table "Default values of IN/OUT patches", p.356). [2]
- Which source channels the USB ports offer: only partly documented in text. The manual says output ports can carry "output signals of output-related channels (MIX, MATRIX, STEREO (L/R), monitor signals (MONITOR OUT L/R channel) and direct output signals of INPUT channels)". That passage is about OMNI OUT and I/O devices; that the same list applies to USB is likely but not stated. [2]
- Insert points can also use USB ports: INSERT screen > INSERT OUT/IN PATCH = USB. Using them takes USB channels away from recording. [2]
- Virtual soundcheck: SETUP > PATCH > INPUT, menu "All USB", or per channel via INPUT CH PATCH > USB. Only CH1-16 can be switched to USB ("assign the [USB TO HOST] connector ... as the input source for CH 1-16"). With USB as the source, the gain slider becomes digital gain. [2]
- When to use which:
  - The default gives 16 inputs plus the stereo mix.
  - To record a MIX or MATRIX instead of the stereo mix, re-patch USB 17-18.
  - Any USB port can be re-patched one at a time, which also allows reordering. The total is 18.

## 6. Tap points
- No selectable "direct out point" setting was found in the reference manual (C0, published 01/2025). The words "direct out" appear once, in the OMNI OUT passage quoted above. [2]
- The DM3 block diagram (C0) draws no direct-out tap for CH1-16. It shows only the insert point, the send points and the meter points. [7]
- What tap feeds USB when a port is patched to "INPUT n": unknown.
- Firmware V3.10 (2026-09-10) is current. [8] The V3.10 notes list only new Dante I/O support. The V3.00 notes were not checked, and the C0 manual predates V3. So a direct-out point added in V3 can't be ruled out.
- Related points that do exist: [2][7]
  - Insert point: Pre EQ / Pre Fader / Post ON.
  - Pre-fader send point (BUS SETUP): Pre EQ / Pre Fader.
  - Meter points for inputs: Pre DG / Pre HPF / Pre Fader / Post ON (block diagram). The manual's meter screen lists PRE HPF / PRE FADER / POST ON.
- Analog gain vs digital gain: the INPUT screen has a separate digital gain box, and the block diagram puts DIGITAL GAIN after the analog gain and before the HPF. [2][7] Whether the USB feed is before or after digital gain: unknown.

## 7. Gotchas
- A driver is required per Yamaha, and a Mac driver exists. iPhone/iPad support is not named by Yamaha and is doubtful.
- Driver Mode must be Mode1 to get 18 channels into one app. Mode2 splits the channels into 2/2/2/12. [2][5]
- Only 16 mic inputs plus 2 slots (18 total), and onboard recording is 2-track only. [1][2]
- Virtual soundcheck covers CH1-16 only. [2]

## 8. Confidence
| Fact | Confidence |
|---|---|
| 18x18 USB 2.0, Type-B, 48/96 kHz, 32-bit | maker |
| Driver required (Yamaha Steinberg USB Driver), Mac driver offered | maker |
| Class compliant on macOS without the driver | unknown (one forum user believes the driver is needed: secondary) |
| iOS/iPadOS | unknown |
| Driver Mode1/Mode2 channel splits | maker |
| Default USB patch 1-16 = INPUT 1-16, 17-18 = STEREO | maker |
| Per-port output patching for USB | maker |
| Virtual soundcheck on CH1-16 only | maker |
| Tap point of INPUT n on USB | unknown |
| Onboard 2-track WAV 48k/96k 24-bit, MP3; seamless 2 GB files | maker |

- Guide check (2026-11-07, #1075): the C0 reference manual and the C0 block diagram still show no USB or direct-out tap setting for CH1-16. The manual names the Mac only in the Driver Mode table and MIDI port names. The DM3 firmware update guide (B1) says to check the version in SETUP > ABOUT. The V3.00 notes are still unchecked (the firmware page returned 403).

## 9. Sources
1. https://usa.yamaha.com/products/proaudio/mixers/dm3/specs.html
2. DM3 Series Reference Manual (C0, 01/2025): https://usa.yamaha.com/files/download/other_assets/6/1626436/DM3_RM_En_C0.pdf (USB TO HOST p.~31; RECORDER p.64-71; SETUP USB section "Driver Mode" p.92; WORD CLOCK p.104; PATCH p.111; OUTPUT CH PATCH p.230; INSERT p.198-199; default patches p.356; USB TO HOST data length in the spec appendix). HTML version: https://manual.yamaha.com/pa/mixers/dm3/rm/en-US/
3. DM3 Owner's Manual: https://usa.yamaha.com/files/download/other_assets/1/1525801/dm3_en_om_b1.pdf
4. https://usa.yamaha.com/products/proaudio/mixers/dm3/downloads.html and https://usa.yamaha.com/support/updates/yamaha_steinberg_usb_driver_v317_for_mac.html
5. Yamaha DM3 V2 firmware news release (2024-05-16): https://usa.yamaha.com/news_events/2024/0516_dm3_v2.html (also https://in.yamaha.com/en/news_events/2024/0516_dm3_v2.html)
6. Secondary, forum: https://discourse.ardour.org/t/yamaha-mixers-on-linux/110559
7. DM3 block diagram (C0): https://usa.yamaha.com/files/download/other_assets/7/1619577/DM3_BD_En_C0.pdf
8. DM3 Firmware V3.10 page: https://usa.yamaha.com/support/updates/dm3_firm.html

## Gaps
- Tap point of USB "INPUT n": not documented by Yamaha. Don't name a tap. Say "Yamaha doesn't say where the USB feed is taken; test before relying on it".
- Digital gain in or out of the recording: unknown. Don't promise either.
- Firmware V3.x changes to USB or direct outs: V3.00 notes not checked. Say "checked against the V2-era manual".
- macOS without the driver: unknown. Tell readers to install the Yamaha Steinberg USB Driver.
- iPhone/iPad over USB: not named by Yamaha, and Yamaha says a driver is required. Say "not supported by Yamaha; not tested".
- Factory Driver Mode setting: unknown. Tell readers to check SETUP > USB and pick Mode1.
- Which sources the USB ports offer beyond INPUT/STEREO: likely the same list as OMNI OUT, but not stated for USB. Label it "likely".
- Bit depth a DAW sees: unknown. Say "32-bit per Yamaha" only for the console side.
