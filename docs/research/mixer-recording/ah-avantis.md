# Allen & Heath Avantis / Avantis Solo

Source keys: [AV-PAGE] = https://www.allen-heath.com/hardware/avantis/ ; [AV-SOLO] = https://www.allen-heath.com/hardware/avantis/avantis-solo/ ; [AV-GSG] = https://support.allen-heath.com/hc/en-gb/articles/40468836946065-Avantis-Getting-Started-Guide ; [AV-UTIL] = https://support.allen-heath.com/hc/en-gb/articles/39867376134033-Utility ; [AV-IO] = https://support.allen-heath.com/hc/en-gb/articles/39863634007185-I-O ; [AV-ROUTE] = https://support.allen-heath.com/hc/en-gb/articles/39862914224145-Routing ; [AV-PROC] = https://support.allen-heath.com/hc/en-gb/articles/39862260219025-Processing ; [AV-FW] = https://support.allen-heath.com/hc/en-gb/articles/44018705862289-Avantis-Firmware-Release-Notes ; [NET] = https://www.allen-heath.com/hardware/audio-networking/

## 1. USB audio to a computer
- None. No USB audio interface is listed for Avantis. Feature list: "USB stereo playback", "Internal storage for stereo playback and recording", "2 I/O Ports, both capable of 128×128 operation at 96kHz – for optional cards inc. Dante, MADI and gigaACE" [AV-PAGE]. The Getting Started Guide lists "USB stereo recording and playback" and describes the USB sockets as for show files, firmware, and USB playback/recording only [AV-GSG].
- Connectors: front-panel USB 3.0 socket and a rear USB 2.0 socket, both type A host ports for drives [AV-GSG]. No USB-B/USB-C device port documented.
- Multitrack to a computer requires an I/O Port option card: Dante 64x64, Dante 128x128, Waves V3, gigaACE, fibreACE, superMADI, DX Link, AES3 [NET]; "multitrack recording" is named as a use of the I/O Ports [AV-PAGE]. Both ports run up to 128x128 at 96 kHz [AV-PAGE].
- Retailer claim "USB is stereo only": confirmed by the maker's own feature list above (no multichannel USB). A user feature request for USB multitrack: https://forums.allen-heath.com/t/usb-multitrack/11250 (secondary).

## 2. Driverless status
- macOS / iOS / Windows over USB: not applicable (no USB audio device port).
- Via option cards: Dante needs Dante Virtual Soundcard or Dante hardware on the computer; Waves needs SoundGrid driver. Driverless status on iOS for those paths: unknown (and generally not a USB class-compliant path). No A&H source checked for these third-party drivers.
- No mode switch for USB.

## 3. Onboard recording without a computer
- Stereo only. Utility > USB Audio / Manager: "Set up and manage stereo recording to the local internal storage, and playback from USB or the internal storage." Recording format: "Stereo .WAV files (24bit 96kHz)" [AV-UTIL].
- Recordings go to internal storage and are copied to a USB drive with "Copy to USB" [AV-UTIL]. Remaining internal space shown in Tracks/Recordings tabs [AV-UTIL].
- Record source: "Select the channels to be recorded by touching the Assign button" [AV-UTIL]; V1.10 expanded stereo record options "to include Tie Lines, PAFL or FX Unit outputs" [AV-FW].
- Playback: mono/stereo WAV 16/24-bit 44.1/48/96 kHz, MP3, FLAC from USB or internal storage [AV-UTIL].
- No multitrack onboard recorder (none documented).

## 4. Recording settings
- Stereo recorder: fixed 24-bit 96 kHz WAV [AV-UTIL]. No sample-rate option documented.
- Multitrack via cards: sample rate/bit depth set by the card and network (e.g. Dante); not covered here (unknown for this fact base).
- Clock: BNC Word Clock on the console [AV-PAGE]; clock source setting location not checked: unknown.

## 5. Routing (multitrack via I/O Port card)
- I/O screen > Outputs: patch Mixes, Direct Outs, RackExtra FX or PAFL to any output, including I/O Port channels; per crosspoint (per slot), any source to any slot [AV-IO]. Hold the Patch button and draw a line to patch 1:1 [AV-IO].
- I/O screen > Tie Lines: any source (e.g. local preamp inputs) straight to one or more destinations, "splits the signals straight after the preamp so they are unaffected by Digital Trim or Direct Out Source" [AV-IO].
- I/O screen > Virtual SoundCheck: pick the I/O Port, a 1:1 channel patch and a Range. Modes: Inactive / Record Send / Virtual SoundCheck. "Record Send sends the pre-trim audio from the Input Channels to the I/O Port for multitrack recording purposes" and temporarily overrides the normal output patch to that port. Virtual SoundCheck feeds the input channels from the I/O Port; can be disabled per channel in Processing > Preamp [AV-IO]. Not stored in scenes [AV-IO].
- When to use which: Record Send for a raw pre-trim multitrack plus VSC; Direct Outs when the processed channel is wanted ("For multitrack recording applications other than Virtual SoundCheck, where the recording of the processed channel is required, go to I/O / Outputs and patch Input Direct Outs instead") [AV-IO]; Mixes/Matrix/Main patched to extra I/O Port slots to record buses alongside [AV-IO].
- Default out of the box: unknown (depends on template Show).

## 6. Tap points
- Global Direct Output Source (Routing screen drop-down, all channels): Post Preamp, Post LPF, Post Gate, Post Insert A Return, Post PEQ, Post Compressor, Post Insert B Return, Post Delay [AV-ROUTE] (list quoted as published; "Post LPF" presumably covers the HPF/LPF filter block, which sits in the Filter page [AV-PROC]: inference). Options (hold Options): Follow Fader, Follow Mute, Follow All (DCA level and mute too) [AV-ROUTE]. Per-channel Direct Out level [AV-ROUTE].
- Record Send: always pre-trim, ignores the Direct Out Source [AV-IO].
- Tie Lines: straight after the preamp, before Digital Trim [AV-IO].
- Gain vs trim: preamp gain is remote control of the socket preamp; Trim +/-24 dB is "part of the channel, not the preamp" [AV-PROC].
- Gain Tracking: "When Gain Tracking is activated, Trim automatically changes to compensate for preamp gain changes ... where a single preamp is accessible by two mixers - e.g. when using a DT168 or DT164-W with two Avantis mixers." Preamp on Surface can be turned off to prevent accidental gain changes on shared preamps [AV-PROC].
- Effect on the record feed: Record Send and Tie Lines are post-preamp, pre-trim, so another console's gain change on a shared preamp DOES change the recorded level; Gain Tracking only compensates the channel (post-trim) path, so direct outs at Post Preamp or later would be compensated (inference from the two maker statements above; not stated directly).

## 7. Gotchas
- No USB multitrack and no USB audio interface at all; an iPhone/iPad cannot record Avantis multitrack over USB. Multitrack needs an option card (Dante, Waves, MADI, gigaACE...) plus a matching recorder [AV-PAGE], [NET].
- Onboard recording is stereo 24/96 WAV to internal storage, then copy to USB [AV-UTIL].
- Record Send overrides the normal output patch to the chosen I/O Port while active [AV-IO].
- Firmware is current: V2.02 (October 2026) per [AV-FW]; V2.0 (April 2026) added dPack expansion to 96 channels [AV-FW], [AV-PAGE].
- Avantis Solo: same platform, "2 I/O Ports (128×128)" [AV-SOLO]; same USB limits assumed (the family feature list covers both; Solo-specific USB statement not found).

## 8. Confidence
| Fact | Confidence |
|---|---|
| No multichannel USB audio; USB is stereo playback/record via drive and internal storage | confirmed by maker |
| Multitrack via I/O Port cards (Dante, Waves, MADI, gigaACE...), 128x128 @96k per port | confirmed by maker |
| Stereo recorder 24-bit 96 kHz WAV | confirmed by maker |
| Record Send pre-trim; Tie Lines post-preamp pre-trim | confirmed by maker |
| Direct Out Source list | confirmed by maker |
| Gain Tracking compensates trim on shared preamps | confirmed by maker |
| Shared-preamp gain change hits Record Send / Tie Lines recording | inference from maker statements |
| iOS path for multitrack | not applicable over USB; card paths unknown |
| Avantis Solo identical USB behavior | secondary/inference |

## 9. Sources
- https://www.allen-heath.com/hardware/avantis/
- https://www.allen-heath.com/hardware/avantis/avantis-solo/
- https://www.allen-heath.com/hardware/audio-networking/
- https://support.allen-heath.com/hc/en-gb/articles/40468836946065-Avantis-Getting-Started-Guide
- https://support.allen-heath.com/hc/en-gb/articles/39867376134033-Utility
- https://support.allen-heath.com/hc/en-gb/articles/39863634007185-I-O
- https://support.allen-heath.com/hc/en-gb/articles/39862914224145-Routing
- https://support.allen-heath.com/hc/en-gb/articles/39862260219025-Processing
- https://support.allen-heath.com/hc/en-gb/articles/44018705862289-Avantis-Firmware-Release-Notes
- https://forums.allen-heath.com/t/usb-multitrack/11250 (secondary, user)
