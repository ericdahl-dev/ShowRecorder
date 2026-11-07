# Allen & Heath CQ series (CQ-12T, CQ-18T, CQ-20B)

Source keys: [CQ-CONFIG] = https://support.allen-heath.com/hc/en-gb/articles/48456934886545-CQ-CONFIG-screens ; [CQ-HOME] = https://support.allen-heath.com/hc/en-gb/articles/48457057592721-CQ-HOME-screens ; [CQ-HOWTO] = https://support.allen-heath.com/hc/en-gb/articles/48456861200017-CQ-How-to ; [CQ-USBB] = https://support.allen-heath.com/hc/en-gb/articles/31464715078929-CQ-USB-B-Routing ; [CQ-STREAM] = https://support.allen-heath.com/hc/en-gb/articles/19338440353425-CQ-Multitrack-streaming-using-CQ ; [CQ-SD] = https://support.allen-heath.com/hc/en-gb/articles/19853352600337-CQ-Multitrack-Recording-and-Playback-from-SD-Card ; [CQ-CONN] = https://support.allen-heath.com/hc/en-gb/articles/48456773235473-CQ-Connections ; [KEITH] = https://forums.allen-heath.com/t/usb-interface/16038 (A&H staff)

## 1. USB audio to a computer
- Channels (to computer x from computer): CQ-12T 16x16, CQ-18T 24x22, CQ-20B 24x24, all at 48/96 kHz [CQ-HOWTO]. Product pages: CQ-20B "24×24 USB-B interface (48/96kHz)" (https://www.allen-heath.com/hardware/cq/cq-20b/); CQ-18T "24×22"; CQ-12T "16×16". Note the USB-B Routing table lists 24 downstream slots for the 18T, of which USB 21-22 are "N/A" [CQ-USBB].
- Sample rate: 48 or 96 kHz, one setting for USB-A, USB-B and SD [CQ-CONFIG].
- Bit depth over USB: unknown (SD/USB-A files are 24-bit [CQ-HOME]).
- Connector: USB-B (device), "Conforms to USB 2.0 standard. Class compliant USB-B interface." Plus USB-A host port for drive record/playback and data [CQ-CONN].

## 2. Driverless status
- macOS: "CQ mixers are Core Audio compliant on MacOS so no driver is required" [CQ-STREAM].
- iOS/iPadOS: A&H staff: "CQ's USB-B audio interface is class compliant, so yes, it can be used with an iPad." [KEITH]. A user then confirmed multichannel output from an iPad app (StageTraxx) after switching to Multitrack mode (same thread, secondary). Another user records CQ-18 to iPad in Cubasis (https://forums.allen-heath.com/t/recording-to-ipad-garageband/15620, secondary).
- Windows: ASIO driver from A&H ("for lower latency connection with Windows systems") [CQ-HOWTO], [CQ-STREAM].
- Mode switch: CONFIG > Digital Audio (symbols) > USB/SD > "Stream Mode" = Stereo or Multitrack. Stereo sends only the pair assigned as "Stereo L/R"; "Set to Stereo for streaming or recording with mobile devices that do not support multichannel audio devices. Set to Multitrack for multichannel recording to and from a DAW." [CQ-CONFIG]. A&H staff: "for more than stereo ... you need to ensure you're set to multitrack" [KEITH].

## 3. Onboard recording without a computer
- Multitrack to SD card only (not USB-A): CQ-12T 16x16 (48 or 96 kHz); CQ-18T 24x22 @48 kHz or 16x16 @96 kHz; CQ-20B 24x24 @48 kHz or 16x16 @96 kHz [CQ-SD]. Product pages match (CQ-20B SD 24×24 @48k / 16×16 @96k).
- Format: mono 24-bit uncompressed WAV per channel in `AHCQ\USBMTK\<subfolder>`, named channel number + name (`03SnrTop.WAV`); 4 GB per file = about 4 h @96k / 8 h @48k [CQ-HOME].
- Media: full-size SD, "SDHC, Up to 32GB, UHS-I, Class 10"; format in the CQ (HOME > SYSTEM > USB/SD) [CQ-CONN], [CQ-HOWTO]. Max armed channels depends on card speed ("Armed X of Y") [CQ-HOME].
- Stereo to USB-A drive (FAT32): 24-bit interleaved WAV in `AHCQ\USBREC`, from the pair assigned to Stereo L/R; 2 h @96k / 4 h @48k [CQ-HOME].
- USB-A audio/data and SD record/playback share resources and cannot run together [CQ-HOME].

## 4. Recording settings
- All in CONFIG > Digital Audio (symbols) > USB/SD: Source Point (input tap for USB/SD), Sample Rate (48/96 kHz), Stream Mode (Stereo/Multitrack), Channel Assignment (last stereo pairs) [CQ-CONFIG]. The help text also calls it "Config>USB S/D>Channel Assignment" [CQ-USBB].
- SD recorder: HOME > RECORD > Multitrack; arm per channel, then Record in the transport bar [CQ-SD].
- SD 48 kHz multitracks cannot play back when set to 96 kHz and vice versa [CQ-CONFIG].
- Clock: no external clock option documented (CQ has no digital audio network port; network port is control only [CQ-CONN]). Treat as internal only (inference).
- File format: WAV only.

## 5. Routing
- Fixed blocks, not per-slot: "All mono (or stereo linked) channels are always patched to their matching channel number. e.g. CQ input 7 is being sent to USB channel 7." [CQ-HOWTO]. "Mono input channels are permanently assigned to USB/SD outputs." [CQ-CONFIG]
- Assignable slots (to computer/SD): CQ-12T USB 11-16 as 3 stereo pairs; CQ-18T and CQ-20B USB 17-24 as 4 stereo pairs [CQ-USBB]. Each pair can carry "stereo line inputs, FX units, Main LR output or outputs 1-6" [CQ-CONFIG]. "The last stereo pair is set to Main LR by default"; that pair is also the USB-A stereo recording and the Stereo stream-mode source [CQ-CONFIG]. So: record the main mix or a monitor/output mix in the assignable pairs alongside the fixed input channels; no reordering of input channels on the mixer.
- From computer (fixed): USB 1-10 to Ch 1-10 on all; 12T: USB 11-12 ST1, 13-14 USB L/R, 15-16 BT; 18T: USB 11-16 Ch 11-16, 17-18 ST1, 19-20 USB L/R, 23-24 BT; 20B: USB 11-16 Ch 11-16, 17-18 ST1, 19-20 ST2, 21-22 USB L/R, 23-24 BT [CQ-USBB].
- Playback/VSC: CONFIG > INPUTS, select channels (Multi Select), set Input Source = USB/SD [CQ-STREAM]. When SD multitrack playback is running the source is the SD card, otherwise USB-B [CQ-CONFIG]. The stereo "soft" inputs can be switched to the digital source from the preamp screen of a Complete channel (A&H staff, [KEITH]).
- Default out of the box: mono inputs 1:1, last stereo pair = Main LR [CQ-CONFIG]. Other pairs' defaults: unknown.

## 6. Tap points
- One global Source Point for all USB/SD input sends: "Choose whether the signal being sent to USB/SD from input channels includes no input channel processing, some processing, or all processing." [CQ-CONFIG]. Option names (secondary, users): Post Preamp, Post HPF, Post Gate, Post Insert Return, Post EQ, Post Compressor, Post AMM (https://forums.allen-heath.com/t/13551 via forum search; also topics 24279, 25965). Default reported as Post AMM by users (topic 14728, secondary).
- No post-fader option: users report USB sends ignore faders and mutes (https://forums.allen-heath.com/t/post-fader-as-global-source-point-for-usb/25766, secondary feature request).
- Gain vs trim: Gain (analog, with Gain Assistant Auto Set/Auto Gain) only on analog sources; Trim is digital, on stereo line inputs and digital (USB/SD) sources [CQ-CONFIG]. "Level - Displays the post-preamp (pre-processing) input level." [CQ-CONFIG].
- Auto Gain: when on, it "automatically reduce[s] the preamp gain ... if high levels are detected" [CQ-CONFIG]; that changes the recorded level mid-show at any tap.
- Shared stage box / gain sharing: not applicable (CQ has no stage box or digital split). The "gain sharing" in CQ docs is the AMM algorithm, not preamp sharing [CQ-CONFIG].

## 7. Gotchas
- Stream Mode must be Multitrack for an iPhone/iPad to see more than 2 channels [CQ-CONFIG], [KEITH].
- iPad power: the USB-A 5 V "is designed only to power a USB drive"; use a camera connection kit/dongle with power pass-through (A&H staff, [KEITH]). User: "the CQ doesnt charge my ipad battery" (topic 15620, secondary).
- Multitrack onboard is SD only; USB-A drive is stereo only (and the Source Point has no effect on that stereo mix; topic 24279, secondary).
- At 96 kHz SD is limited to 16 channels on the 18T/20B [CQ-SD].
- USB-A and SD cannot be used at the same time [CQ-HOME].
- One global tap point; no per-channel tap and no fader-following option (secondary).

## 8. Confidence
| Fact | Confidence |
|---|---|
| 16x16 / 24x22 / 24x24 USB-B, 48/96 kHz | confirmed by maker |
| Core Audio compliant, no Mac driver | confirmed by maker |
| Works with iPad (class compliant) | confirmed by maker staff (forum) |
| Stereo vs Multitrack stream mode | confirmed by maker |
| SD multitrack counts, 24-bit WAV | confirmed by maker |
| Mono channels fixed 1:1, last pairs assignable, last pair Main LR default | confirmed by maker |
| Source Point option names | secondary |
| Default Source Point Post AMM | secondary |
| USB stream bit depth | unknown |
| USB-A cannot power iPad | confirmed by maker staff (forum) |

## 9. Sources
- https://support.allen-heath.com/hc/en-gb/articles/48456934886545-CQ-CONFIG-screens
- https://support.allen-heath.com/hc/en-gb/articles/48457057592721-CQ-HOME-screens
- https://support.allen-heath.com/hc/en-gb/articles/48456861200017-CQ-How-to
- https://support.allen-heath.com/hc/en-gb/articles/31464715078929-CQ-USB-B-Routing
- https://support.allen-heath.com/hc/en-gb/articles/19338440353425-CQ-Multitrack-streaming-using-CQ
- https://support.allen-heath.com/hc/en-gb/articles/19853352600337-CQ-Multitrack-Recording-and-Playback-from-SD-Card
- https://support.allen-heath.com/hc/en-gb/articles/48456773235473-CQ-Connections
- https://www.allen-heath.com/hardware/cq/cq-20b/ (and /cq-18t/, /cq-12t/)
- https://forums.allen-heath.com/t/usb-interface/16038 (A&H staff)
- https://forums.allen-heath.com/t/recording-to-ipad-garageband/15620 (secondary)
- https://forums.allen-heath.com/t/13551 , /t/24279 , /t/25965 , /t/14728 , /t/25766 (secondary, users)
