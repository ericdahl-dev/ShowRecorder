# Behringer WING / WING Compact / WING Rack: multitrack recording facts

All three have built-in USB audio. Per the manual, "All WING models have the same digital I/O" [B-1]. The expansion slot holds the WING-LIVE SD card "by default", and "All WING models include the WING-LIVE card" [B-1].

Source labels: [B-x] = Behringer document (maker). [S-x] = secondary.

## 1. USB audio to a computer

- **Channels:** 48 in x 48 out.
  - Manual: "1 USB type B connector for ... 48 input/48 output audio interface" [B-1].
  - Product page: "48×48 channel USB 2.0 audio interface onboard" [B-2].
  - Spec: "USB 2.0 type B device (48 × 48 ch 24-bit audio and MIDI I/O)" [B-1][B-2].
- **Selectable count:** "USB AUDIO sets the number of available input and output channels when connecting the console to a computer via USB 2.0 from 2x2 up to 48x48 channels", at SETUP → AUDIO [B-1].
  - The steps are 2/2, 8/8, 16/16, 32/32 and 48/48. In and out are always the same size [B-5].
- **Bit depth:** 24-bit [B-1][B-2].
- **Sample rate:**
  - The console clock is set at SETUP → AUDIO → AUDIO CLOCK (Clock Rate, Sync Source) [B-1].
  - The console runs at 48 kHz or 44.1 kHz. The remote protocol document lists the master clock rate as "48000.0, 44100.0" and says processing runs "at 48 or 44.1 kHz" [B-5]. The manual's effect-latency table also lists both rates [B-1].
  - The spec tables say "40-bit floating point, 48 kHz" and list 48 kHz converters [B-1][B-2]. They don't mention 44.1 kHz.
  - Whether USB audio runs at 44.1 kHz is not stated in any maker document. It presumably follows the console clock (inference, not tested).
- **Connector:** USB 2.0 **Type B** (device) on the rear [B-1].
- **Front panel:** a USB **Type A** host port, "audio and data, 5 VDC, 1 A" [B-1]. It takes a USB stick for the 4-track recorder and player. "The port can also charge a portable device such as a phone or tablet" [B-3].

## 2. Driver status

- **macOS:** no maker document says "class compliant", and none names macOS for USB audio. The product page offers only a Windows USB ASIO driver [B-2]. One forum user says it "shows up as a class compliant USB audio device on my M4 MacMini" [S-1]. Status: secondary.
- **iPad:** conflicting forum reports. One user says iPads work; another says three iPads on iOS 18 did not [S-1]. Status: secondary, conflicting.
- **iPhone:** no source found, maker or forum. Status: unknown.
- **Linux:** one forum user says a Raspberry Pi 4 was plug and play [S-1]. Status: secondary.
- **Windows:** "The corresponding ASIO driver can be downloaded from behringer.com" [B-1].
- **Mode switch (USB audio vs disk):**
  - The rear USB-B port also works as a USB disk. At SETUP → GENERAL, "WING OS: changes the USB 2.0 connection to USB Disk mode for firmware updates" and "WING DATA: changes the USB 2.0 connection to USB Disk mode for preset transfer" [B-1].
  - "To disconnect the console from the computer or to return to audio playback via USB from the computer, eject the console as regularly done with a normal USB flash drive" [B-3].
  - Gotcha: if the console is showing as a disk (a red OS or DATA tag at the top of the WING screen [B-5]), eject it to get USB audio back.

## 3. Recording without a computer

- **WING-LIVE (SD), fitted to all models:**
  - "up to 64 channels of 48 kHz / 32-bit audio to be recorded onto a pair of SD or SDHC cards" [B-1].
  - "32 tracks to/from an SD card or 64 tracks to/from two linked SD cards" [B-1]. Over 32 channels, link both cards with the LINK CARDS button [B-1].
  - "Each card records multitrack WAV audio files of 8, 16 or 32 channels called a session", which is a **poly WAV**. Split it with the LiveSessions app from behringer.com [B-1].
  - Media: "SD cards must be formatted to FAT32 with an allocation unit size (cluster) of 32 kB. SD cards of up to 32 GB can be formatted directly on the console" [B-1].
  - The card writes an `X_LIVE` folder [B-1]. An optional 3V CR123 battery lets a recording be "stopped and saved in case of a power failure" [B-1].
  - Maximum card size and recording time: unknown in the WING manual. The X-LIVE spec of 1 to 32 GB is a likely analog, but not confirmed for WING-LIVE.
  - Sample rate: the manual says "48 kHz / 32-bit" [B-1]. The remote protocol document lists the card's read-only sample rate status as "44.1, 48" [B-5]. So a 44.1 kHz session may exist when the console runs at 44.1 kHz, but no maker text says so. Treat WING-LIVE at 44.1 kHz as unknown.
- **USB stick recorder (front Type A port):** "4 tracks can be recorded and played back to/from a USB stick". It "supports recording 2- or 4-track WAV files at 16- or 24-bit resolution. The sample rate is determined in the SETUP → AUDIO screen" [B-1].
  - SETUP → GENERAL → USB HOST SPEED must be **HS** for 4 tracks and 24-bit. On **FS**, "USB recording on the front port is restricted to 2 channels and 16 bits" [B-1].

## 4. Recording settings

- **Clock rate and sync:** SETUP → AUDIO → AUDIO CLOCK. 44.1 or 48 kHz [B-1][B-5].
- **USB channel count:** SETUP → AUDIO → USB AUDIO: 2x2, 8x8, 16x16, 32x32 or 48x48 [B-1][B-5].
- **USB file format to a computer:** set by the recording app, not the console. The stream is 24-bit [B-1].
- **WING-LIVE:**
  - Per card, SD RECORD picks 8, 16 or 32 channels (open it with the arrow next to the SD CARD 1 or SD CARD 2 header) [B-1].
  - The recorder screen has a SETTINGS button for SHOW METERS, AUTO INPUT SELECT, STOP / PLAY / RECORD INPUT (automatic MAIN/ALT input switching) and FORMAT [B-1].
  - The SD bit depth is 32-bit, with no other choice described [B-1].
- **USB recorder:** 2 or 4 tracks, 16 or 24-bit, set in the recorder's top-right panel. REC PATH sets the folder on the stick [B-1]. Needs USB HOST SPEED = HS for 4 tracks or 24-bit [B-1].

## 5. Routing

**WING has a per-slot router.** Every output slot picks any single source, so there are no blocks of 8.

- **Path:** ROUTING → **OUTPUTS**. "The OUTPUTS screen allows you to route any Source to any digital or analog output. The left side of the screen shows the available outputs. All Output Groups are accessible on the dropdown menu at the top of the screen. The signal fed into the selected output is chosen on the right side of the screen" [B-1].
  - The manual describes the green lock icon ("Ensure that the lock icon is green before editing") and the "+1 AUTO" button on the ROUTING → CHANNELS screen [B-1]. The OUTPUTS text doesn't repeat them. The QSG's routing text says "Before editing, the unlock icon must be clicked on. When lit green, editing is" available [B-3]. Whether +1 AUTO is on OUTPUTS: unknown.
- **Output groups for recording:**
  - Computer: "Up to 48 channels can be recorded on a computer connected via USB to the rear panel" [B-3]. The remote protocol calls the output node "USB", slots 1 to 48 [B-5]. The on-screen group name in OUTPUTS is not quoted in the manual (unknown, presumably "USB" or "USB AUDIO").
  - SD: "**WLIVE REC**" routes up to 64 channels to the WING-LIVE card [B-1][B-3].
  - USB stick: "**RECORDER**" routes up to 4 tracks to the USB stick recorder [B-1][B-3].
- **Source groups you can pick per slot** [B-1]:
  - Raw inputs: Local In, Aux In (WING only), AES/EBU, AES50 A/B/C, StageConnect, USB Audio, Exp Card, Module
  - Bus (16 stereo), Main (4 stereo), Matrix (8 stereo)
  - Oscillator
  - USB Player
  - **User Signal**: copies of input channels, aux channels, buses, mains or matrices at a chosen point (see 6)
  - User Patches: stereo or M/S pairs of raw sources
- **Recording processed channels:** create a User Signal from the channel, then route it to a USB, WLIVE REC or RECORDER slot.
- **Recording main mix or buses:** pick them directly from the Main, Bus or Matrix source groups. Whether those outputs are post-fader is not stated (unknown, presumably the bus output).
- **Default routing out of the box:** unknown. No maker text says what the USB, WLIVE REC or RECORDER slots carry after a factory reset. Tell readers to check and patch every slot themselves.
- **Playback (virtual soundcheck):**
  - ROUTING → SOURCES: source group "**WLIVE PLAY**" (up to 64) or "**USB PLAYER**" (4) [B-1]. From a computer, use the **USB Audio** source group (48 channels) [B-1].
  - Assign them per channel on ROUTING → CHANNELS [B-1].
  - Each channel has a **MAIN and an ALT input**. Patch the live source to MAIN and the playback to ALT. SETUP → AUDIO → INPUT SELECT toggles all 40 channels and 8 aux between them [B-1].
  - The WING-LIVE STOP / PLAY / RECORD INPUT settings can switch MAIN/ALT automatically with the transport [B-1].

## 6. Tap points

- **Raw source (Local In, AES50 and so on) to an output:** taken after the source's preamp gain. Gain, phantom and polarity are properties of the Source (ROUTING → SOURCES "allows you to determine the Sources' properties such as ... polarity, gain, phantom power") [B-1]. Channel processing is not applied.
- **Channel TAP point** (per input channel, set with the wrench icon on Channel Home), which feeds User Signals and TAP-mode sends [B-1]:
  1. **INPUT**: "immediately after the preamp, before any processing"
  2. **FILTER**: "after the low-cut and high-cut filters"
  3. **TAP 3**: between the 1st and 2nd processing slots
  4. **TAP 4**: between the 2nd and 3rd slots
  5. **TAP 5**: between the 3rd and 4th slots
  6. **PRE FDR**: between the 4th processing slot and the fader
  7. **POST FDR**: between the fader and INS2
  8. **POST PROC**: after INS2, before WIDTH
- The processing slot order (GATE, EQ, COMP, INS1) can be rearranged, so the meaning of TAP 3 to 5 depends on that order [B-1].
- **HPF:** INPUT is before the low-cut filter; FILTER is after it [B-1].
- **User Signals:**
  - "copies of any of the 40 input channels, 8 Aux channels, 16 Buses, 8 Matrices or 4 Main buses. The signal can be derived pre-fader (from the TAP point on Input channels) or post-fader."
  - Each is mono, with L, R or L+R choice. Two adjacent ones can make a stereo or M/S source [B-1].
  - Count: the manual's overview says "24 User Signals" (and separately "32 User Patches"). The routing section says the User Signal source group has "up to 48 signals ... as well as repatched external Sources if using User Patches" [B-1]. Treat the exact number of channel copies as unknown. Say "24 or more" if a guide needs a number.
- **Tap on other channel types:** fixed. "The TAP point on Aux Channels is fixed post insert point and pre-fader." "The TAP point in Bus channels is fixed post insert point 1 and pre-fader" [B-1].
- **Per channel or global:** the TAP point is per input channel. Each User Signal picks pre (TAP) or post fader.
- **Gain vs trim:** analog gain is on the Source; digital trim is in the channel ("TRIM: digital level control up to ±18 dB gain") [B-1]. The manual doesn't place TRIM against the INPUT tap. That the INPUT tap is before trim is our inference from "before any processing".
- **Shared stage box:**
  - Preamp remote: "the Source must be routed from the remote-controlled device to the remote-controlling device via AES50 and ENABLE HA REMOTE must be enabled" [B-1].
  - Whoever controls the headamp changes the raw record level. A gain-compensation feature: unknown (none found).

## 7. Gotchas

- **The rear USB-B port doubles as a USB disk** (WING OS / WING DATA). Eject the WING disk to get audio back [B-1][B-3].
- **Front USB recorder on FS speed** records only 2 tracks at 16-bit. Set USB HOST SPEED to HS [B-1].
- **iPad/iPhone:** conflicting forum reports for iPad (works for one user, three iPads on iOS 18 did not) [S-1]; nothing for iPhone. Test before promising.
- **WING-LIVE is a 32-bit poly WAV per 8/16/32-channel session.** Split it with LiveSessions. The SD format must be FAT32 with a 32 kB cluster size.
- **The USB stick recorder is 4 tracks maximum,** not a multitrack replacement.
- **The User Signal counts (24 vs "up to 48") disagree** within the same manual.

## 8. Confidence summary

| Fact | Confidence |
|---|---|
| USB 48x48, 24-bit, USB 2.0 Type B; count steps 2/8/16/32/48 | maker |
| Console clock 44.1 or 48 kHz | maker (protocol doc and manual latency table; spec table lists only 48) |
| USB audio at 44.1 kHz | unknown (presumably follows the clock) |
| Windows ASIO driver | maker |
| macOS class compliant / no driver | secondary |
| iPad | secondary, conflicting |
| iPhone | unknown |
| WING-LIVE 64 ch on two cards (32 each), 48 kHz/32-bit, 8/16/32-ch sessions, FAT32 32 kB cluster | maker |
| WING-LIVE at 44.1 kHz | unknown (protocol doc hints at it) |
| USB stick recorder 2/4 tracks, 16/24-bit, HS needed for 4 tracks/24-bit | maker |
| Per-slot routing ROUTING → OUTPUTS, groups WLIVE REC / RECORDER | maker |
| TAP points INPUT … POST PROC | maker |
| On-screen USB output group label; default routing; User Signal count | unknown |

## 9. Sources

- [B-1] WING / WING COMPACT / WING RACK User Manual, Firmware 3.1, 2025-10-20 (linked from the WING product page; re-read 2026-11-06): https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf
- [B-2] WING product page (re-read 2026-11-06): https://www.behringer.com/en/products/0603-AEN
- [B-3] WING Quick Start Guide, multi-language, linked from the WING product page (English section): https://cdn-media.empowertribe.com/c5ff61e785861bc4f4fe7bec6839f7ed/BE_0603-AFC_WING_QSG_Multi-Language.pdf . This replaces the earlier Adorama-hosted copy of the WING Compact QSG; the quotes used here are in the maker copy.
- [B-4] WING firmware 3.1.2 release notes (nothing recording-specific): https://cdn-media.empowertribe.com/9773eacaebb1ba29df804c96d69cfca1/WING-firmware-3.1.2_release-notes.pdf
- [B-5] WING Remote Protocols V3.1.0 (for firmware 3.1.0 and later), linked from the WING product page. Written by Patrick-Gilles Maillot and published by Behringer, so treated as maker: https://cdn-media.empowertribe.com/2106004e217b8eb2639d93672823eef5/WING_Remote-Protocols-3.1-03.pdf
  - "All digital processing takes place on 40-bit floating point Digital Signal Processors, at 48 or 44.1 kHz"
  - `/$globals/clkrate` "48000.0, 44100.0" Master clock rate
  - `/$globals/usbacfg` "2/2, 8/8, 16/16, 32/32, 48/48" USB Input/Output configuration
  - `/cards/wlive/1/$stat/rate` "44.1, 48" Cards W-Live 1 sample rate [RO]
  - `/io/out/USB/1` … "1..48" USB Output Audio node
- [S-1] behringer.world, "Is WING USB audio class compliant?" (re-read 2026-11-06), https://behringer.world/viewtopic.php?p=13151
  - "The WING shows up as a class compliant USB audio device on my M4 MacMini."
  - "All my Ipads works perfect with my Wing rack without any software driver."
  - The opening poster tested two 10th-generation iPads and an iPad mini 6 on iOS 18.3.x through a Satechi port extender: "All three wont work with my WING usb connection". An RME Octamic XTC worked on the same setup, and a Raspberry Pi 4 was plug and play.

## Gaps

- iPhone: no source at all. Say "not tested yet".
- iPad: forum only, and the reports conflict. Say "reports differ; not tested yet". Don't promise it works.
- Mac without a driver: one forum user only. Say "users report it works without a driver; Behringer doesn't state it".
- USB audio at 44.1 kHz: not stated. Tell readers to use 48 kHz, or say "44.1 kHz on USB not confirmed".
- WING-LIVE at 44.1 kHz: the manual says 48 kHz only. Say 48 kHz.
- Factory default routing for USB, WLIVE REC and RECORDER: unknown. Don't describe a default; tell readers to patch every slot.
- The on-screen name of the USB output group in ROUTING → OUTPUTS: not quoted. Describe it as "the USB group" without quoting a label, or check on a console or WING Edit first.
- Whether Main, Bus and Matrix sources are post-fader: unknown. Don't state it.
- The number of User Signals (24 vs up to 48): unclear. Avoid a number, or say "at least 24".
- Whether the INPUT tap is before digital TRIM: inference only. Say "right after the preamp" (maker words) rather than "before trim".
- Gain compensation on a shared stage box: none found. Say a gain change at the headamp changes the recording.
- WING-LIVE maximum card size and recording time: not in the manual. Leave out.
- "+1 AUTO" on the OUTPUTS screen: only documented for CHANNELS. Leave out of output steps.
