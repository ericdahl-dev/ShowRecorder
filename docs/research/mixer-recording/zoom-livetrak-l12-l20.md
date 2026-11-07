# Zoom LiveTrak L-12 and L-20 (plus L-20R notes)

Source key used below:
- [L12-OM] L-12 Operation Manual (Zoom, current EN PDF): https://zoomcorp.com/media/documents/E_L-12_4.pdf
- [L20-OM] L-20 Operation Manual (Zoom): https://zoomcorp.com/media/documents/E_L-20_OperationManual.pdf
- [L20R-OM] L-20R Operation Manual (Zoom): https://zoomcorp.com/media/documents/E_L-20R.pdf
- [DRV2] L-12/L-20/L-20R audio driver version 2 supplementary manual (Zoom, Sept 2020): https://zoomcorp.com/media/documents/L-12_L-20_L-20R_Driver_V2manual_en.pdf
- [L12-PAGE] L-12 product page: https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/
- [L20-PAGE] L-20 product page: https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-20/
- [L12-SUP] L-12 support/downloads page: https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/l-12-support/
- [L20-SUP] L-20 support/downloads page: https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-20/livetrak-l-20-support/

## 1. USB audio to a computer

| | L-12 | L-20 / L-20R |
|---|---|---|
| To computer (record) | 14 ch: channels 1-12 + master L/R [L12-OM spec "Recording: 14 channels"] | 22 ch: channels 1-20 + master L/R [L20-OM spec "Recording: 22 channels"; L20R-OM same] |
| From computer (playback) | 4 ch, assignable to stereo channels 9/10 and 11/12 [L12-OM] | 4 ch, assignable to stereo channels 17/18 and 19/20 [L20-OM] |
| Sample rate as interface | 44.1/48 kHz only [L12-OM spec; L12-PAGE "In Audio Interface mode, the L-12 can record up to 48 kHz"] | 44.1/48 kHz only [L20-OM spec] |
| Bit depth (interface) | 24-bit [L12-OM spec] | 24-bit [L20-OM spec] |
| Connector | "USB DEVICE port", USB 2.0 (connector shape not named in text; it is a USB device port) [L12-OM] | same [L20-OM] |

Separate "USB HOST" port (USB 2.0) is for USB flash drives (project save/load, audio file import/export), not for live multitrack recording [L12-OM, L20-OM].

## 2. Driverless status

- Rear-panel **CLASS COMPLIANT MODE** switch: "Use this to turn Class Compliant Mode ON/OFF. Set it to ON when connected to an iOS device." [L12-OM p.21; L20-OM same wording]
- "Class compliant mode, which enables connection with iOS devices, is also supported." [L12-OM intro; L12-PAGE; L20-PAGE; L20R-OM]
- iOS connection: "use a Lightning to USB camera adapter (or Lightning to USB 3 camera adapter)" [L12-OM "Connecting to a computer"; L20-OM same]. USB-C iPhone/iPad: not mentioned (unknown).
- Windows and Mac: the manual's procedure is "Download the ZOOM L-12 Driver ... Launch the installer" [L12-OM "Installing the driver"]; driver V2 has a control panel on both Windows and Mac [DRV2]. Whether macOS works with Class Compliant Mode ON and no driver: not stated explicitly by Zoom (the manual only ties class-compliant mode to iOS). Treat macOS driverless as "likely, unconfirmed".
- Mode switches that matter (all rear panel, read at power-on):
  - **MODE** switch: USB HOST / CARD READER / AUDIO INTERFACE. "This cannot be changed after starting up." [L12-OM]
  - **SAMPLE RATE** switch: 44.1 / 48 / 96 kHz. "This cannot be changed after starting up." [L12-OM]
  - **CLASS COMPLIANT MODE** switch: ON for iOS [L12-OM]
- iPhone power: the L-12 runs from its AD-19 AC adapter (DC12 V/2 A) [L12-OM spec]; it does not need power from the phone. Whether it charges the phone: unknown (no source).

## 3. Onboard recording without a computer (SD card)

| | L-12 | L-20 / L-20R |
|---|---|---|
| Tracks | 14 at 44.1/48 kHz, 12 at 96 kHz [L12-OM spec] | 22 at 44.1/48/96 kHz [L20-OM spec] |
| Format | WAV 44.1/48/96 kHz, 16/24-bit, mono/stereo [L12-OM spec] | same [L20-OM spec] |
| Media | 16 MB-2 GB SD, 4-32 GB SDHC, 64-512 GB SDXC [L12-OM spec] | same [L20-OM spec] |
| File split | "If the file size exceeds 2GB during recording, a new file will be created automatically ... recording will continue without pause", suffixes "-01", "-02" [L12-OM "Audio files"] | same behavior expected (not re-checked) |
| File names | TRACK01-TRACK08 (mono), TRACK09_10, TRACK11_12 (stereo), MASTER (stereo) [L12-OM] | unknown (not checked) |

Records to SD and to the computer at the same time when in Audio Interface mode at 44.1/48 kHz [L12-PAGE: "can record up to 48 kHz to a computer and an SD card simultaneously"; L20-PAGE].

## 4. Recording settings

- Sample rate: rear SAMPLE RATE switch, set before power-on [L12-OM].
- Bit depth (SD): MENU > REC / PLAY > REC FORMAT [L12-OM "Changing the recording format"]. Overdubs keep the original file's bit depth.
- USB bit depth: 24-bit fixed [L12-OM spec].
- 96 kHz limits: L-12 records tracks 1-12 only; SEND EFX, EQ, OVER DUB and **audio interface disabled**; MONITOR OUT = MASTER only [L12-OM]. L-20: SEND EFX 1/2, EQ, OVER DUB, audio interface disabled [L20-OM]. Format the SD card before recording at 96 kHz.
- Clock: internal only (no word clock or external sync mentioned; unknown beyond that).
- File format: WAV (BWF details unknown).

## 5. Routing

- **Per-slot patching: none.** USB and SD slots are fixed: "After applying its compressor, each input channel always outputs its signal to the corresponding USB audio channel. Channels 1-12 and the stereo signal output from the master fader are sent to the computer (14 channels total)." [L12-OM "Using audio interface functions"; L20-OM same with 1-20 / 22]. No aux/monitor mix can be sent to USB or SD.
- **Only reorder option:** driver version 2 lets the post-master-fader L/R be sent as computer channels 1/2 (inputs then start at 3). Set in the ZOOM L-12/L-20 Control Panel > Channel tab (Windows: Control Panel > Hardware and Sound; Mac: driver control panel) [DRV2]. Whether this applies in Class Compliant Mode (iOS): unknown; it is a driver setting, so assume not.
- Arming SD tracks: press each channel's REC/PLAY button (lit red), then REC [L12-OM "Recording"].
- Main mix: always included as the last stereo pair (MASTER) on both SD and USB.
- Virtual soundcheck: SD playback, REC/PLAY button lit green: "Playback signals are input before the equalizer" and input jacks are disabled on that channel [L12-OM]. USB playback from a computer only reaches stereo channels 9/10 and 11/12 on L-12 via their USB buttons ("switched to the USB audio channel signal (before EQ)") [L12-OM]; so USB virtual soundcheck of all mono channels is not possible; use SD playback.

## 6. Tap points

- L-12 SD and USB: post-compressor, pre-EQ (fixed). "The signals for each channel are recorded after passing through their compressors" [L12-OM]; USB "Inputs: The signals from channels 1-12 after they pass through their compressors" [L12-OM]. Product page: "Tracks are recorded pre-EQ and effects" [L12-PAGE]. The record point is therefore after the analog GAIN knob and the one-knob compressor, before EQ, LOW CUT, fader and pan.
- LOW CUT (75 Hz, 12 dB/oct on L-12) is inside the EQ section ("When this button is lit, HIGH, MID, LOW and LOW CUT are bypassed") [L12-OM]. Inference: low cut is not in the recording. Confidence: secondary (inferred from maker text, not stated outright).
- L-20 / L-20R SD: selectable **REC SOURCE**: MENU > REC/PLAY > REC SOURCE = PRE COMP or POST COMP (global, not per channel) [L20-OM p.83; L20R-OM]. L-20 USB: manual still says "after they pass through their compressors" [L20-OM]; whether REC SOURCE also changes the USB feed: unknown.
- No digital trim; gain is the analog GAIN knob per channel [L12-OM]. No shared-stage-box scenario.
- Recommendation for clean multitrack: leave the channel compressor at zero (L-12) or set REC SOURCE = PRE COMP (L-20) if you want uncompressed stems.

## 7. Gotchas

- USB interface max 48 kHz; at 96 kHz the audio interface is disabled entirely [L12-OM, L20-OM].
- USB is only 4 channels back from the computer, into the stereo channels; no full USB virtual soundcheck [L12-OM].
- MODE, SAMPLE RATE and CLASS COMPLIANT switches are read only at power-on; flip them before turning on [L12-OM].
- Compression is baked into L-12 recordings (USB and SD) if the channel COMP knob is up [L12-OM].
- Auto power off after 10 hours unused (can be disabled) [L12-OM].
- Lightning camera adapter required for iOS [L12-OM, L12-PAGE].

## 8. Confidence

| Fact | Confidence |
|---|---|
| USB 14-in/4-out (L-12), 22-in/4-out (L-20/L-20R), 44.1/48 kHz, 24-bit | confirmed by maker |
| Class Compliant Mode switch for iOS, camera adapter needed | confirmed by maker |
| macOS works driverless in class-compliant mode | unknown (not stated) |
| USB-C iPhone/iPad | unknown |
| SD 14 tracks (L-12, 12 at 96k), 22 (L-20), WAV 16/24-bit, 2 GB file split | confirmed by maker |
| Fixed USB/SD order, no per-slot patching | confirmed by maker |
| Master on USB 1/2 via driver V2 control panel | confirmed by maker (driver only) |
| L-12 tap post-comp pre-EQ | confirmed by maker |
| Low cut not in recording | secondary (inference) |
| L-20 REC SOURCE PRE/POST COMP for SD | confirmed by maker |
| L-20 REC SOURCE effect on USB | unknown |

L-8: not researched (time).

## 9. Sources

- https://zoomcorp.com/media/documents/E_L-12_4.pdf
- https://zoomcorp.com/media/documents/E_L-20_OperationManual.pdf
- https://zoomcorp.com/media/documents/E_L-20R.pdf
- https://zoomcorp.com/media/documents/L-12_L-20_L-20R_Driver_V2manual_en.pdf
- https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/
- https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-20/
- https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/l-12-support/
- https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-20/livetrak-l-20-support/
