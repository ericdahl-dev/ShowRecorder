# Allen & Heath Qu series: new Qu-5/6/7 (and Qu-3, D variants) and Qu Classic (Qu-16/24/32/SB/Pac)

Two different generations. Keep them apart in any guide: new Qu = 96 kHz, USB-C interface, SD card multitrack. Qu Classic = 48 kHz, USB-B interface, Qu-Drive multitrack to a USB drive.

Source keys (new Qu): [Q-USB] = https://support.allen-heath.com/hc/en-gb/articles/48350897327889-Qu-Qu-Drive-and-USB-audio ; [Q-PATCH] = https://support.allen-heath.com/hc/en-gb/articles/48350711389457-Qu-Patching ; [Q-SETUP] = https://support.allen-heath.com/hc/en-gb/articles/48350696072593-Qu-Mixer-Setup ; [Q-ROUTE] = https://support.allen-heath.com/hc/en-gb/articles/48350799066257-Qu-Routing ; [Q-PROC] = https://support.allen-heath.com/hc/en-gb/articles/48350755314705-Qu-Processing ; [Q-CONN] = https://support.allen-heath.com/hc/en-gb/articles/48348179394705-Qu-Connections
Source keys (Classic): [C-USB] = https://support.allen-heath.com/hc/en-gb/articles/4402943975569-Qu-Classic-Qu-Drive-USB-Audio ; [C-DAW] = https://support.allen-heath.com/hc/en-gb/articles/4403019846033-Qu-Classic-How-do-I-route-audio-to-and-from-my-Qu-mixer-and-a-DAW ; [C-DRIVE] = https://support.allen-heath.com/hc/en-gb/articles/4402944132753-Qu-Classic-Understanding-Qu-Drive-and-USB-devices ; [C-SB] = https://support.allen-heath.com/hc/en-gb/articles/41599046080913-Qu-SB-Getting-Started-Guide ; [C-PAC] = https://support.allen-heath.com/hc/en-gb/articles/41402982389777-Qu-Pac-Getting-Started-Guide ; [KEITH] = https://forums.allen-heath.com/t/qu-usb-channel-i-o-clarification/12192 (A&H staff post, 2022)

## 1. USB audio to a computer
New Qu (Qu-5/6/7, also Qu-3):
- 32 in x 32 out over USB-C. Product page: "USB-C Audio interface for multichannel record/playback (32×32)" (https://www.allen-heath.com/hardware/qu/qu-5/); "Multitrack mode provides all 32 input and 32 output sockets" [Q-USB].
- Sample rate 96 kHz or 48 kHz; core always runs at 96 kHz, 48 kHz uses sample-rate conversion [Q-SETUP].
- Bit depth over USB: unknown. (Recordings to SD/USB-A are 24-bit [Q-USB].)
- Connector: USB-C, "Conforms to USB 2.0 standard. Class compliant USB and MIDI interface." [Q-CONN]. Separate USB-A port for stereo record/playback and data [Q-USB].
Qu Classic:
- To computer: Qu-16 "can record up to 24 tracks to your Mac or PC" (https://www.allen-heath.com/hardware/qu/qu-classic/qu-16/); Qu-24, Qu-32, Qu-Pac "up to 32 tracks" (product pages under https://www.allen-heath.com/hardware/qu/qu-classic/); Qu-SB and Qu-Pac guides: "32 in, 32 out USB streaming" [C-SB], [C-PAC].
- From computer: returns are fixed 1-to-1 into input channels sourced from USB [C-DAW]. On Qu-16, USB 17&18 feed ST1; on Qu-24, ST channels from USB 25-30; on Qu-32/SB/Pac, all 32 returns go to the 32 mono channels [C-DAW]. Exact Qu-16 return count: unknown (inferred 22 from 16 mono + 3 stereo channels; not stated by maker).
- Sample rate: 48 kHz (Qu Classic are "the original 48kHz models", https://www.allen-heath.com/hardware/qu/qu-classic/). USB stream bit depth: unknown.
- Connector: USB-B, "high speed USB 2.0" [C-SB].

## 2. Driverless status
- macOS: driverless on both generations. New Qu: "Core Audio compliant so no driver is required" [Q-USB]. Classic: "class-compliant on Mac OS X" (https://www.allen-heath.com/hardware/qu/qu-classic/qu-sb/).
- iOS/iPadOS: new Qu, maker: "It is possible to connect the Qu as an Audio/MIDI interface to any device which supports Class Compliant devices, including tablets and phones, though it is not possible for all devices to be tested and officially supported." [Q-USB]. Classic, A&H staff (Keith): "on macOS and iOS the Qu is class compliant so with multichannel apps it will be seen as a multichannel device, but with stereo apps, you may only see two channels ... with iOS, it will often use just the first two it sees" [KEITH]. User reports of iPad use: https://forums.allen-heath.com/t/are-qu-mixers-class-compliant-with-ios-devices/15891 (secondary).
- Windows: ASIO/WDM driver from A&H for both generations; all 32 channels need ASIO [Q-USB].
- Mode switch (new Qu only): SETUP > Audio > Sync & USB > "USB Stream Mode" = Stereo or Multitrack. Stereo uses only USB sockets 1&2 "for compatibility with tablets and phones"; Multitrack exposes all 32x32 [Q-USB], [Q-SETUP]. An iPhone/iPad multitrack recorder needs Multitrack mode. Qu Classic: no stream mode switch documented.

## 3. Onboard recording without a computer
New Qu:
- Multitrack to SD card (SDHC up to 32 GB, UHS-I, Class 10): up to 16 ch at 96 kHz or 32 ch at 48 kHz; mono 24-bit uncompressed WAV per channel in `AH_QU\USBMTK\<subfolder>`, named e.g. `03SnrTop.WAV`. 4 GB per file: about 4 h at 96 kHz / 8 h at 48 kHz. [Q-USB], [Q-CONN]. Product page: "SD Card Slot ... (16×16@96kHz, 32×32@48kHz)".
- Only patched USB sockets record; at 96 kHz "Up to 16 (first 16 patched)" [Q-PATCH].
- Stereo to USB-A (FAT32): 24-bit interleaved WAV from USB outputs 1&2, in `AH_QU\USBREC`; 2 h at 96 kHz / 4 h at 48 kHz [Q-USB].
- USB-A and SD cannot record/play at the same time; SD record and playback are exclusive [Q-USB].
Qu Classic:
- Qu-Drive (USB-A drive): stereo plus 18-track multitrack, WAV 48 kHz 24-bit [C-DRIVE]; "18 channels of 48kHz, 24bit recording and playback" = 16 mono + a selectable stereo pair (product pages). Multitrack fed from USB sends 1-18; stereo from sends 17-18 [C-SB], [C-PAC].
- FAT32, 2 GB to 2 TB drive, 4 GB per file (about 8 h per track); most USB sticks too slow; format on the Qu [C-DRIVE]. Playback imports must be 18 mono 48k/24-bit files [C-DRIVE].
- Classic: Qu-Drive playback + multitrack recording to USB-B is supported simultaneously [C-DRIVE].

## 4. Recording settings
- New Qu: SETUP > Audio > Sync & USB: Audio Clock Source (Internal / SLink / Dante on D models), USB Stream Mode (Stereo/Multitrack), USB Sample Rate (96/48 kHz, shared by USB-C, USB-A and SD) [Q-SETUP]. Format storage: UTILITY > USB Utility > Status/Format [Q-USB]. Recorder screens: UTILITIES > Qu Drive > Stereo / Multitrack [Q-USB]. Only recordings matching the current sample rate can be played back [Q-USB].
- Qu Classic: fixed 48 kHz. USB send source (CH/ST): Setup > I/O Patch > USB Audio, toggle "Insert Send" or "Direct Outs", Apply [C-USB]. Global USB Source (Qu-Drive vs USB B Streaming) chooses where USB returns come from [C-DAW], [C-PAC].

## 5. Routing
New Qu:
- Path: I/O > Outputs > USB. "There are 32 USB output sockets available to patch to. These feed the USB-C connection to a computer or device, as well as the USB-A and SD Card for Qu Drive recording." [Q-PATCH]
- Per slot: yes. Each USB output socket takes one source chosen from a pop-up of "any Qu XCVI core output, including Mix Outputs, FX Returns and Input Direct Outputs"; any source can go to several sockets [Q-PATCH]. Quick Patch (three-line menu, top right) patches many at once; "+1" patches the next socket with the next logical source [Q-PATCH].
- Sockets used: USB-C Stereo = 1-2; USB-C Multitrack = 1-32; USB-A = 1-2; SD @48k = up to 32 (patched only); SD @96k = up to 16 (first 16 patched) [Q-PATCH].
- Default: "By default, USB output channels 1&2 are fed from the Main LR mix" [Q-USB]. Default for sockets 3-32: unknown.
- Playback/VSC: patch input channels from USB sockets in I/O > Inputs or PROCESSING > Source [Q-PATCH]; Input Channel Patch Library (LIBRARY key on I/O > Inputs) stores/recalls the whole input patch [Q-PATCH]. The dedicated stereo USB channel always takes USB inputs 1&2 [Q-USB]. SD multitrack playback returns on the same USB socket numbers [Q-USB].
Qu Classic:
- Path: Setup > I/O Patch > USB Audio (also in Qu-Pad). Each USB send is assignable: highlight, turn the rotary, Fn (+1) for the next channel, Apply [C-DAW]. Any Qu output can be patched (input channels via Insert Send or Direct Out, mixes, Main LR, etc.) [C-SB].
- Default: factory patch "configured ... to accommodate the most common configuration", e.g. Main LR on sends 17&18 for Qu-Drive stereo [C-DAW].
- Returns are fixed 1-to-1 (cannot be re-patched); choose channel source = USB per channel and Global USB Source = USB B Streaming [C-DAW], [KEITH].

## 6. Tap points
New Qu:
- Input direct outs: ROUTING > Direct Out (input channel) > Global Direct Out Settings > Source; "each source point includes all preceding processing". Per-channel Level. Global switches: Follow Mute, Follow Fader, Follow DCA Mute, Follow DCA Fader, Follow Mute Group [Q-ROUTE]. Names of the direct-out source points: unknown (not listed in the article).
- SD/USB records direct outs: "Set Input Direct Output source to choose whether channel processing will be recorded" [Q-USB]. No tie-line or insert-send tap for USB is documented for the new Qu: unknown.
- Gain is analog preamp; Trim is digital +/-24 dB in PROCESSING > Input [Q-PROC]. Preamp controls belong to the socket, so patching one socket to two channels shares gain [Q-PATCH].
- HPF position relative to direct-out taps: unknown.
Qu Classic:
- Default USB/Qu-Drive tap = channel Insert Send, "directly after the preamp", no channel processing [C-USB], [C-DAW]. Alternative: Direct Outs with global source Post Preamp / Post Insert / Post EQ / Post Comp / Post Delay, follow fader/mute options, per-channel Direct Out Trim (Routing > Sel on an input) [C-USB]. A&H: "Live show multitrack recording typically uses the channel Insert Sends so that live mixing does not affect the recording" [C-SB].
- Shared stage box / gain tracking: not documented for Qu: unknown. Insert Send and post-preamp taps follow any analog gain change.

## 7. Gotchas
- New Qu: set USB Stream Mode = Multitrack, or an iPad/iPhone sees only 2 channels [Q-USB].
- New Qu SD at 96 kHz only records the first 16 patched sockets [Q-PATCH].
- USB-A stereo and SD multitrack share resources; not at the same time [Q-USB].
- Classic: iOS stereo apps use USB 1-2 only; multichannel apps see all channels [KEITH].
- Classic Qu-16 sends 24 tracks, not 32 (product page).
- Classic returns are fixed 1-to-1; reorder in the app, not on the mixer [C-DAW].
- iPad power: the Qu USB-C/USB-B port is the device side; no maker statement on powering a phone/tablet: unknown. (A&H's CQ advice is a camera adapter with power pass-through; see ah-cq.md.)
- Some USB 3.0 (xHCI) ports fail with isochronous audio [Q-USB].

## 8. Confidence
| Fact | Confidence |
|---|---|
| New Qu 32x32 USB-C, 96/48 kHz | confirmed by maker |
| New Qu class compliant; phones/tablets possible but not officially supported | confirmed by maker |
| New Qu Stereo/Multitrack stream mode | confirmed by maker |
| New Qu SD 16 @96k / 32 @48k, 24-bit WAV | confirmed by maker |
| New Qu per-socket USB patch (mixes, FX returns, direct outs) | confirmed by maker |
| New Qu direct-out source point names | unknown |
| Classic iOS class compliance | confirmed by maker staff (forum) |
| Classic Qu-16 24 tracks / others 32 to computer | confirmed by maker |
| Classic Qu-16 USB return count | unknown |
| Classic Qu-Drive 18 tracks 48k/24-bit | confirmed by maker |
| Classic default tap Insert Send (post preamp) | confirmed by maker |
| USB stream bit depth (both) | unknown |
| Gain tracking (both) | unknown |

## 9. Sources
- https://support.allen-heath.com/hc/en-gb/articles/48350897327889-Qu-Qu-Drive-and-USB-audio
- https://support.allen-heath.com/hc/en-gb/articles/48350711389457-Qu-Patching
- https://support.allen-heath.com/hc/en-gb/articles/48350696072593-Qu-Mixer-Setup
- https://support.allen-heath.com/hc/en-gb/articles/48350799066257-Qu-Routing
- https://support.allen-heath.com/hc/en-gb/articles/48350755314705-Qu-Processing
- https://support.allen-heath.com/hc/en-gb/articles/48348179394705-Qu-Connections
- https://support.allen-heath.com/hc/en-gb/articles/4402943975569-Qu-Classic-Qu-Drive-USB-Audio
- https://support.allen-heath.com/hc/en-gb/articles/4403019846033-Qu-Classic-How-do-I-route-audio-to-and-from-my-Qu-mixer-and-a-DAW
- https://support.allen-heath.com/hc/en-gb/articles/4402944132753-Qu-Classic-Understanding-Qu-Drive-and-USB-devices
- https://support.allen-heath.com/hc/en-gb/articles/41599046080913-Qu-SB-Getting-Started-Guide
- https://support.allen-heath.com/hc/en-gb/articles/41402982389777-Qu-Pac-Getting-Started-Guide
- https://www.allen-heath.com/hardware/qu/qu-5/
- https://www.allen-heath.com/hardware/qu/qu-6-qu-6d/
- https://www.allen-heath.com/hardware/qu/qu-classic/ (and /qu-16/, /qu-24/, /qu-32/, /qu-pac/, /qu-sb/)
- https://forums.allen-heath.com/t/qu-usb-channel-i-o-clarification/12192 (A&H staff)
- https://forums.allen-heath.com/t/are-qu-mixers-class-compliant-with-ios-devices/15891 (secondary, user)
