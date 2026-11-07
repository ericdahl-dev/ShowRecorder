# Behringer WING / WING Compact / WING Rack: multitrack recording facts

All three have built-in USB audio and ship with the WING-LIVE SD card. Per the manual, "All WING models have the same digital I/O" [B-1].

Source labels: [B-x] = Behringer document (maker). [S-x] = secondary.

## 1. USB audio to a computer

- **Channels:** 48 in x 48 out.
  - Manual: "1 USB type B connector for ... 48 input/48 output audio interface" [B-1].
  - Product page: "48×48 channel USB 2.0 audio interface onboard" [B-2].
  - Spec: "USB 2.0 type B device (48 x 48 ch 24-bit audio and MIDI I/O)" [B-3].
- **Selectable count:** "USB AUDIO sets the number of available input and output channels ... from 2x2 up to 48x48 channels", at SETUP → AUDIO [B-1].
- **Bit depth:** 24-bit [B-3].
- **Sample rate:**
  - The console clock is set at SETUP → AUDIO → AUDIO CLOCK (Clock Rate, Sync Source) [B-1].
  - The manual's effect-latency table lists both 44.1 kHz and 48 kHz [B-1], so both clock rates exist.
  - Whether USB runs at 44.1 kHz is not stated: unknown, though it presumably follows the console clock.
  - The processing spec says "40-bit floating point, 48 kHz" [B-1].
- **Connector:** USB 2.0 **Type B** (device) on the rear [B-1][B-3].
- **Front panel:** a USB **Type A** host port for a USB stick (4-track recorder and player, data). It also charges a phone or tablet, rated "5 VDC, 1 A" [B-3].

## 2. Driver status

- **macOS:** the maker documents do not use the word "class compliant". They mention only the Windows ASIO driver [B-1]. Forum users report it is USB class compliant on an M4 Mac mini and on a Raspberry Pi [S-1]. Status: secondary.
- **iOS / iPadOS:** conflicting forum reports. One user says iPads work; another says three iPads on iOS 18 did not [S-1]. Status: unknown (secondary, conflicting).
- **Windows:** "The corresponding ASIO driver can be downloaded from behringer.com" [B-1].
- **Mode switch:**
  - The rear USB-B port is also used as a mass-storage device for firmware and data. "USB MSD ACCESS controls the content that will show up when connected to a computer via USB."
  - "To disconnect the console from the computer or to return to audio playback via USB from the computer, eject the console as regularly done with a normal USB flash drive" [B-3].
  - Gotcha: if the console is showing as a disk (WING OS / WING DATA), eject it to get USB audio back.

## 3. Recording without a computer

- **WING-LIVE (SD), fitted to all models:**
  - "up to 64 channels of 48 kHz / 32-bit audio to be recorded onto a pair of SD or SDHC cards" [B-1].
  - "32 tracks to/from an SD card or 64 tracks to/from two linked SD cards" [B-1].
  - "Each card records multitrack WAV audio files of 8, 16 or 32 channels called a session", which is a **poly WAV**. Split it with the LiveSessions app from behringer.com [B-1].
  - Media: "SD cards must be formatted to FAT32 with an allocation unit size (cluster) of 32 kB. SD cards of up to 32 GB can be formatted directly on the console" [B-1].
  - The card writes an `X_LIVE` folder [B-1]. Optional CR123 battery [B-1].
  - Maximum card size and recording time: unknown in the WING manual. The X-LIVE spec of 1 to 32 GB is a likely analogue, but not confirmed for WING-LIVE.
  - WING-LIVE at 44.1 kHz: unknown; the manual says "48 kHz / 32-bit".
- **USB stick recorder (front Type A port):** "4 tracks can be recorded and played back to/from a USB stick". It "supports recording 2- or 4-track WAV files at 16- or 24-bit resolution. The sample rate is determined in the SETUP → AUDIO screen" [B-1].

## 4. Recording settings

- **Clock rate and sync:** SETUP → AUDIO → AUDIO CLOCK [B-1].
- **USB channel count:** SETUP → AUDIO → USB AUDIO, 2x2 up to 48x48 [B-1].
- **WING-LIVE:** the recorder screen (icons at the top of the main display) has a SETTINGS button for SHOW METERS, AUTO INPUT SELECT, STOP/PLAY/RECORD INPUT (automatic MAIN/ALT input switching) and FORMAT [B-1]. The SD bit depth is fixed at 32-bit; the 8/16/32-channel session size is per card [B-1].
- **USB recorder:** 2 or 4 tracks, 16 or 24-bit, set in the recorder's top-right panel [B-1].

## 5. Routing

**WING has a per-slot router.** Every output slot picks any single source, so there are no blocks of 8.

- **Path:** ROUTING → **OUTPUTS**. "The OUTPUTS screen allows you to route any Source to any digital or analog output. The left side of the screen shows the available outputs. All Output Groups are accessible on the dropdown menu at the top of the screen. The signal fed into the selected output is chosen on the right side" [B-1].
  - Unlock first: "Ensure that the lock icon is green before editing" [B-1].
  - "+1 AUTO" steps to the next slot for quick patching [B-1].
- **Output groups for recording:**
  - Computer: "Up to 48 channels can be recorded on a computer connected via USB to the rear panel" [B-3]. The exact output-group label for USB under OUTPUTS is not quoted in the manual (unknown, presumably "USB").
  - SD: "**WLIVE REC**" routes up to 64 channels to the WING-LIVE card [B-1].
  - USB stick: "**RECORDER**" routes up to 4 tracks to the USB stick recorder [B-1].
- **Source groups you can pick per slot** [B-1]:
  - Raw inputs: Local In, Aux In (WING only), AES/EBU, AES50 A/B/C, StageConnect, USB Audio, Exp Card, Module
  - Bus (16 stereo), Main (4 stereo), Matrix (8 stereo)
  - Oscillator
  - USB Player
  - **User Signal**: copies of input channels, aux channels, buses, mains or matrices at a chosen point (see 6)
  - User Patches: stereo or M/S pairs of raw sources
- **Recording processed channels:** create a User Signal from the channel, then route it to a USB, WLIVE REC or RECORDER slot.
- **Recording main mix or buses:** pick them directly from the Main, Bus or Matrix source groups. Whether those outputs are post-fader is not stated (unknown, presumably the bus output).
- **Default routing out of the box:** unknown.
- **Playback (virtual soundcheck):**
  - ROUTING → SOURCES (CHANNELS screen): source group "**WLIVE PLAY**" (up to 64) or "**USB PLAYER**" (4); USB Audio is also a source group [B-1].
  - Each channel has a **MAIN and an ALT input**. SETUP → AUDIO → INPUT SELECT toggles all 40 channels and 8 aux between them [B-1].
  - The WING-LIVE STOP/PLAY/RECORD INPUT settings can switch MAIN/ALT automatically with the transport [B-1].

## 6. Tap points

- **Raw source (Local In, AES50 and so on) to an output:** taken after the source's preamp gain. Gain, phantom and polarity are properties of the Source (ROUTING → SOURCES: "activate phantom power ... invert the polarity") [B-1][B-3]. Channel processing is not applied.
- **Channel TAP point** (per input channel, set with the wrench icon on Channel Home), which feeds User Signals and TAP-mode sends [B-1]:
  1. **INPUT**: "immediately after the preamp, before any processing"
  2. **FILTER**: after the low-cut and high-cut filters
  3. **TAP 3**: between the 1st and 2nd processing slots
  4. **TAP 4**: between the 2nd and 3rd slots
  5. **TAP 5**: between the 3rd and 4th slots
  6. **PRE FDR**
  7. **POST FDR**: between the fader and INS2
  8. **POST PROC**: after INS2, before WIDTH
- The processing slot order (GATE, EQ, COMP, INS1) can be rearranged, so the meaning of TAP 3 to 5 depends on that order [B-1].
- **User Signals:**
  - "copies of any of the 40 input channels, 8 Aux channels, 16 Buses, 8 Matrices or 4 Main buses. The signal can be derived pre-fader (from the TAP point on Input channels) or post-fader."
  - Each is mono, with L, R or L+R choice [B-1].
  - Count: the manual says "24 User Signals" in one place and "up to 48 signals" in the routing section [B-1]. Treat the exact number as unknown; it may be 24 plus 24 User Patches, or a firmware change.
- **Tap on other channel types:** fixed. On aux channels it is "post insert point and pre-fader". On buses it is "post insert point 1 and pre-fader" [B-1].
- **Per channel or global:** the TAP point is per input channel. Each User Signal picks pre (TAP) or post fader.
- **Digital trim:** in the channel ("TRIM: digital level control up to ±18 dB gain") [B-1], so it is after an INPUT tap.
- **Shared stage box:**
  - Preamp remote: "the Source must be routed from the remote-controlled device to the remote-controlling device via AES50 and ENABLE HA REMOTE must be enabled" [B-1].
  - Whoever controls the headamp changes the raw record level. A gain-compensation feature: unknown (none found).

## 7. Gotchas

- **The rear USB-B port doubles as a mass-storage device.** Eject the WING disk to get audio back [B-3].
- **iPad/iPhone:** conflicting forum reports (works for one user, three iPads on iOS 18 did not) [S-1]. Test before promising.
- **WING-LIVE is a 32-bit poly WAV per 8/16/32-channel session.** Split it with LiveSessions. The SD format must be FAT32 with a 32 kB cluster size.
- **The USB stick recorder is 4 tracks maximum,** not a multitrack replacement.
- **The two User Signal counts (24 vs 48) disagree** within the same manual.

## 8. Confidence summary

| Fact | Confidence |
|---|---|
| USB 48x48, 24-bit, USB 2.0 Type B, selectable 2x2 to 48x48 | confirmed by maker |
| Windows ASIO driver | confirmed by maker |
| macOS class compliant / no driver | secondary |
| iOS/iPadOS | unknown (conflicting secondary) |
| WING-LIVE 64 ch on two cards (32 each), 48 kHz/32-bit, 8/16/32-ch sessions, FAT32 32 kB cluster | confirmed by maker |
| USB stick recorder 2/4 tracks, 16/24-bit | confirmed by maker |
| Per-slot routing ROUTING → OUTPUTS, groups WLIVE REC / RECORDER | confirmed by maker |
| TAP points INPUT … POST PROC | confirmed by maker |
| USB output group label; default routing; 44.1 kHz on USB/SD | unknown |

## 9. Sources

- [B-1] WING / WING COMPACT / WING RACK User Manual, Firmware 3.1, 2025-10-20 (linked from the WING product page): https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf
- [B-2] WING product page: https://www.behringer.com/en/products/0603-AEN
- [B-3] WING Compact Quick Start Guide (ManualsLib "Simplified" copy, hosted by Adorama): https://www.adorama.com/col/productManuals/BEHWINGCM.pdf
- [B-4] WING firmware 3.1.2 release notes (nothing recording-specific): https://cdn-media.empowertribe.com/9773eacaebb1ba29df804c96d69cfca1/WING-firmware-3.1.2_release-notes.pdf
- [S-1] behringer.world, "Is WING USB audio class compliant?" (re-read 2026-11-06), https://behringer.world/viewtopic.php?p=13151
  - "The WING shows up as a class compliant USB audio device on my M4 MacMini."
  - "All my Ipads works perfect with my Wing rack without any software driver."
  - The opening poster tested two 10th-generation iPads and an iPad mini 6 on iOS 18.3.x through a Satechi port extender: "All three wont work with my WING usb connection". An RME Octamic XTC worked on the same setup, and a Raspberry Pi 4 was plug and play.
