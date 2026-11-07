# Allen & Heath SQ series (SQ-5, SQ-6, SQ-7, SQ-Rack)

Scope: the original SQ line. SQ+ models have their own help-center articles (e.g. "SQ+. SQ-Drive and USB-B") that were not reviewed here.
Source keys: [KB-USB] = https://support.allen-heath.com/hc/en-gb/articles/45947079593105-SQ-SQ-Drive-and-USB-B ; [KB-PATCH] = https://support.allen-heath.com/hc/en-gb/articles/45261631285009-SQ-Connections-and-Patching ; [KB-ROUTE] = https://support.allen-heath.com/hc/en-gb/articles/45946654916753-SQ-Routing ; [KB-SETUP] = https://support.allen-heath.com/hc/en-gb/articles/45947065818769-SQ-Setup ; [KB-PROC] = https://support.allen-heath.com/hc/en-gb/articles/45946563062929-SQ-Processing ; [KB-UNDERSTAND] = https://support.allen-heath.com/hc/en-gb/articles/4402940155793-SQ-Understanding-SQ-USB-recording-and-playback ; [KB-RESET] = https://support.allen-heath.com/hc/en-gb/articles/45947235418385-SQ-Mix-System-Reset ; [FW] = https://support.allen-heath.com/hc/en-gb/articles/43757630905361-SQ-Firmware-Release-Notes

## 1. USB audio to a computer
- Channels: 32 in x 32 out simultaneously over USB-B. "The USB-B connection allows 32 inputs and 32 outputs simultaneously at either 96kHz or 48kHz." [KB-USB]. Product pages: "built-in 32×32 96kHz audio interface" (https://www.allen-heath.com/hardware/sq/sq-5/), SQ-Rack "32×32 96kHz USB interface that is ASIO and Core Audio compliant" (https://www.allen-heath.com/hardware/sq/sq-rack/).
- Sample rates: 96 kHz or 48 kHz (one setting shared by USB-B and SQ-Drive). The core always runs at 96 kHz; 48 kHz mode uses sample-rate conversion between core and USB. [KB-SETUP]
- Bit depth over USB-B: unknown (no maker statement found for the stream; SQ-Drive files are 24-bit [KB-USB]).
- Connector: USB-B on the mixer, USB 2.0. "SQ conforms to USB 2.0 standards" ... "USB-A to USB-B cable" [KB-USB]. A&H advise a USB 2.0 port and avoiding some xHCI USB 3.0 controllers [KB-USB].

## 2. Driverless status
- macOS: driverless. "The SQ is Core Audio compliant so drivers are not required." [KB-USB]. Supported from macOS 10.12 per troubleshooting article https://support.allen-heath.com/hc/en-gb/articles/4402939458193-SQ-Troubleshooting-issues-with-the-SQ-USB-B-interface
- iOS/iPadOS: unknown. No SQ-specific maker statement found. (Class compliance for Core Audio suggests it should enumerate on iPadOS, but that is inference, not a source.)
- Windows: needs A&H ASIO/WDM driver; WDM only uses USB 1-2, all 32x32 needs ASIO [KB-USB]. Listed Windows 7 (64-bit), 8, 10 [KB-UNDERSTAND].
- Mode switch: no stereo/multitrack stream-mode setting is documented for SQ (unlike CQ/new Qu). The relevant switches are the USB sample rate and (pre-1.6 firmware) the "USB Source" toggle between SQ-Drive and USB-B (see section 4).

## 3. Onboard recording (SQ-Drive, USB-A on the surface)
- Multitrack: up to 16 ch at 96 kHz or 32 ch at 48 kHz; 24-bit mono uncompressed WAV, one file per channel, in `<SQ-DRIVE>:\AHSQ\USBMTK\SQ-MT001` etc., named by USB channel + source name (e.g. `01KikIn.WAV`). [KB-USB]
- Only patched USB channels are recorded (since V1.5.0) [KB-USB], [FW].
- Stereo: 24-bit interleaved WAV at 96 or 48 kHz from USB outputs 1&2, in `AHSQ\USBREC` (`SQ-ST001.WAV`...). [KB-USB]
- Media: FAT32; min 2 GB, max 2 TB drive; 4 GB per file = about 4 h per track at 96 kHz / 8 h at 48 kHz (multitrack), 2 h / 4 h (stereo). Most USB sticks are too slow; use a fast external HDD/SSD; format on the SQ before use. [KB-USB], [KB-UNDERSTAND]
- 48 kHz / 32-channel option added in V1.5.0 [FW].

## 4. Recording settings
- Sample rate: Setup > Audio > Digital I/O > "USB Sample Rate" = 96kHz or 48kHz; applies to both USB-B and SQ-Drive. Restart DAW/app after changing if USB-B is connected. [KB-USB], [KB-SETUP]. (Older article says Setup > Audio > USB page [KB-UNDERSTAND].)
- Clock: Setup > Audio > Digital I/O > Audio Clock Source = Internal / SLink / I/O Port. [KB-SETUP]
- USB mode/source: "To view or change USB mode, press the 'Setup' key, then touch the 'Audio' tab followed by the 'USB' tab." [KB-PATCH]. Current behavior: USB inputs come from USB-B unless SQ-Drive playback is running, then switch back automatically [KB-USB]. Older firmware: a "USB Source" toggle (I/O > USB tab > USB Source, USB B vs SQ-Drive) had to be set to USB B for computer streaming [troubleshooting article above; KB-UNDERSTAND says SQ-Drive was the default]. V1.6.0 added "Simultaneous use of USB A and USB B for both 48kHz and 96kHz", "USB system overhaul" and "Lower latency USB streaming" [FW].
- Recording to SQ-Drive and to USB-B: both get the same USB output patch simultaneously [KB-USB]. But older article lists "SQ-Drive Playback/Recording ... + Playback/Recording from USB B ... not supported simultaneously" [KB-UNDERSTAND], which predates V1.6.0. Treat simultaneous use as firmware-dependent.
- File format: WAV only (see 3). Channel count options: 16 (96k) or 32 (48k) on SQ-Drive; always 32x32 on USB-B.

## 5. Routing
- Patch screen: press I/O. Tabs on the far left: Outputs > Direct Outs (channel direct outs to any output socket), Outputs > Mix Outs (LR, Aux, Group, Matrix), Outputs > Rack FX (FX returns), Outputs > Listen Out (PAFL, talkback), and Tie Lines (any input socket straight to any output socket, no processing). Sockets are columns along the top; the USB sockets have their own column tab ("USB-B and SQ-Drive Channels"). Touch "Patch" to enable editing; touch-and-hold a block and turn the rotary for sequential (diagonal) patching. [KB-PATCH]
- Per-slot patching: yes. Each of the 32 USB output sockets can be fed independently from any direct out, any mix output (LR, Aux, Group, Matrix), FX return, listen/talkback, or any input socket via Tie Line [KB-PATCH]. So you can mix taps per track: Tie Lines for raw post-preamp inputs, Direct Outs for processed inputs, plus LR or a matrix on the last pair. A&H suggest matrices for recording "a single mix or combination of mixes ... with additional mix processing and level control" [KB-ROUTE].
- Default (Reset Mix Settings: Standard): "SQ to USB: Main LR to 1-2, then 1-to-1 direct outs"; "USB to SQ: USB 1-2 to input channel 47-48" [KB-RESET]. Monitor role reset: SQ to USB unassigned [KB-RESET]. Older article: "By default, Tie Lines are used for input channel sends to USB" [KB-UNDERSTAND] (older firmware; conflicts with current reset table).
- Block sizes: patching is per crosspoint, no fixed blocks; sequential patching is a convenience. Stereo SQ-Drive recording always records USB outputs 1&2 [KB-USB].
- Playback / virtual soundcheck: patch USB input sockets to input channels in I/O > Inputs > Input Channel, or per channel in the Preamp source ("USB Port") [KB-PATCH], [KB-PROC]. Input Channel Patch Libraries (press Library on the Input Channel tab) store/recall the whole input patch "for virtual soundcheck" [KB-PATCH]. VSC article: https://support.allen-heath.com/hc/en-gb/articles/4402941921553-SQ-Virtual-Soundcheck-using-the-USB-B-connection . SQ-Drive multitrack plays back on the same USB socket numbers it was recorded from [KB-USB].

## 6. Tap points
- Direct Out Source (global, all channels): Routing screen > "Dir Out" button. Options, in order: Post Preamp, Post HPF, Post Gate, Post Insert Return, Post PEQ, Post Comp, Post Delay. Per-channel direct out level -inf to +10 dB. Global switches choose whether direct outs follow faders and mutes (and DCAs/mute groups). [KB-ROUTE], [KB-UNDERSTAND]
- Tie Lines: "unprocessed (post socket analogue preamp) audio" not affected by faders or mutes, no input channel used. [KB-PATCH], [KB-UNDERSTAND]
- HPF: after the preamp; "Post Preamp" direct-out tap is pre-HPF, "Post HPF" includes it. [KB-ROUTE]
- Gain vs trim: Gain 0 to +60 dB is the analog preamp, controlled digitally and belonging to the socket ("not a part of the channel processing"); Trim -24 to +24 dB is digital and part of channel processing. [KB-PROC]. So Tie Lines and "Post Preamp" direct outs include analog gain; Trim affects direct outs only (Tie Lines skip channel processing).
- Shared stage box: no SQ gain-tracking feature was found in SQ docs. Because Tie Lines and direct outs are post analog preamp, any preamp gain change on a shared AR/DX/Dante box by another operator changes the record level. (Inference from the above; "unknown" whether SQ offers compensation.)

## 7. Gotchas
- Firmware matters: USB-A plus USB-B simultaneously and the USB overhaul arrived in V1.6.0 [FW]; older units may need the USB Source set to USB B before a computer sees audio.
- SQ-Drive at 96 kHz records only 16 channels; switch to 48 kHz for 32 [KB-USB].
- USB sticks are usually too slow for multitrack; SQ-Drive is FAT32 with a 4 GB per-file cap [KB-UNDERSTAND].
- Some USB 3.0 (xHCI) ports don't support the isochronous transfer used for audio [KB-USB].
- Changing the USB sample rate while connected may require restarting the app/DAW [KB-USB].
- SQ USB-B is a computer-side (device) port; the mixer does not power an iPad over it (no maker statement either way; unknown).

## 8. Confidence
| Fact | Confidence |
|---|---|
| 32x32 USB-B at 96/48 kHz | confirmed by maker |
| Core Audio class compliant, no Mac driver | confirmed by maker |
| Windows needs ASIO/WDM driver | confirmed by maker |
| iOS/iPadOS works | unknown |
| USB stream bit depth | unknown |
| SQ-Drive 16 ch @96k / 32 ch @48k, 24-bit mono WAV | confirmed by maker |
| Per-slot USB patch from direct outs, mixes, matrices, FX, tie lines | confirmed by maker |
| Default patch: LR to USB 1-2, then 1-to-1 direct outs | confirmed by maker (current reset table; older article differs) |
| Direct out source list (Post Preamp ... Post Delay), global | confirmed by maker |
| Tie lines = post preamp, unprocessed | confirmed by maker |
| No gain tracking on SQ | unknown (not found) |

## 9. Sources
- https://support.allen-heath.com/hc/en-gb/articles/45947079593105-SQ-SQ-Drive-and-USB-B
- https://support.allen-heath.com/hc/en-gb/articles/45261631285009-SQ-Connections-and-Patching
- https://support.allen-heath.com/hc/en-gb/articles/45946654916753-SQ-Routing
- https://support.allen-heath.com/hc/en-gb/articles/45947065818769-SQ-Setup
- https://support.allen-heath.com/hc/en-gb/articles/45946563062929-SQ-Processing
- https://support.allen-heath.com/hc/en-gb/articles/45947235418385-SQ-Mix-System-Reset
- https://support.allen-heath.com/hc/en-gb/articles/4402940155793-SQ-Understanding-SQ-USB-recording-and-playback
- https://support.allen-heath.com/hc/en-gb/articles/4402941921553-SQ-Virtual-Soundcheck-using-the-USB-B-connection
- https://support.allen-heath.com/hc/en-gb/articles/4402939458193-SQ-Troubleshooting-issues-with-the-SQ-USB-B-interface
- https://support.allen-heath.com/hc/en-gb/articles/43757630905361-SQ-Firmware-Release-Notes
- https://www.allen-heath.com/hardware/sq/sq-5/
- https://www.allen-heath.com/hardware/sq/sq-rack/
