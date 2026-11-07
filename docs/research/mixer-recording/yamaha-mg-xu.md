# Yamaha MG XU series (MG10XU, MG12XU, MG16XU, MG20XU) and the newer MGX series

Checked 2026-11-06. Sources are numbered in section 9. Audited 2026-11-06 against the maker PDFs listed there.

Don't mix the two up. **MG XU** (MG10XU to MG20XU) is analog with a stereo-only USB port. **MGX** (MGX12/16, 2025) is digital with multitrack USB. Part A is MG XU, Part B is MGX.

## Part A: MG XU (analog, stereo USB only)

### 1. USB audio to a computer
- 2 IN / 2 OUT, "USB Audio Class 2.0 compliant, Sampling Frequency: Max 192 kHz, Bit Depth: 24-bit" (all four XU models, spec page). [1]
- MG10XU tech spec: 44.1, 48, 88.2, 96, 176.4 and 192 kHz. Data length: 16/24-bit with UAC 2.0, 24-bit with the Yamaha Steinberg USB Driver. Connector: USB Standard-B. [2]
- Only the MG10XU manual and spec sheet were read. The other XU models share the spec page line above. [1]

### 2. Driverless status
- Yamaha says the USB port is "USB Audio Class 2.0 compliant". [1][2] Yamaha does not say "no driver on Mac" in words. macOS supports UAC 2.0 without a driver, so driverless on Mac is our inference from the class compliance claim.
- The owner's manual says "you may need a dedicated USB driver" and points to the Yamaha site. It does not name an operating system. [3]
- iOS/iPadOS: named by the maker, stereo only.
  - Brochure text: "connect ... to your iPhone / iPad (2 or later) using Apple's Camera Connection Kit / Lightning to USB Camera Adapter". [4]
  - The brochure's per-model boxes name only the iPad: "Works with the iPad (2 or later) through the Apple iPad Camera Connection Kit / Lightning to USB Camera Adapter". [4]
  - The brochure predates USB-C iPhones and iPads. USB-C devices are not named.

### 3. Onboard recording
- None. No recorder or card slot is listed. [1][3]

### 4. Recording settings
- No console menu for USB. The manual describes no sample-rate control on the mixer. [3] That the computer sets the rate (up to 192 kHz) is our inference.
- Playback level from the computer: an attenuator (-24 dB to 0 dB) set with the [PROGRAM] knob (MG10XU). [3]

### 5. Routing
- Fixed: "The sound of the stereo bus is output to the computer. (The [STEREO LEVEL] knob does not affect the sound.)" [3] So the USB send is the stereo bus, before the STEREO LEVEL control.
- USB return: on the MG10XU, channel 9/10 [LINE/USB] switch set to USB. The [TO MON / TO STO] switch sends the USB return either to the monitor only or to the stereo bus. [3]
  - Yamaha: "If you set the switch to [TO STO] when you use the DAW software, a loop may be produced, possibly resulting in feedback." Use TO MON while recording. [3]
  - Other XU models: the return channel numbers were not checked.

### 6. Tap points
- Only the stereo mix: post channel processing, post channel levels, and not affected by the STEREO LEVEL knob. [3] There are no per-channel feeds.

### 7. Gotchas
- Not a multitrack interface: only 2 channels (the stereo mix). A ShowRecorder guide must say this plainly. [1][2][3]

## Part B: MGX series (MGX16, MGX12, MGX16V, MGX12V; digital, 2025)

Relevant because MGX is Yamaha's newer "MG" line with multitrack USB.

### 1. USB audio to a computer
- USB MAIN (USB-C, USB 2.0 High Speed): [5][6]
  - With the Yamaha Steinberg USB Driver: MGX16/16V up to 22 in / 22 out; MGX12/12V up to 18/18.
  - Class compliant (UAC 2.0): MGX16/16V 18 in / 16 out; MGX12/12V 14 in / 12 out.
  - 32-bit, up to 96 kHz.
- USB SUB: UAC 1.0, 16-bit/48 kHz, 2 in / 2 out. [5][6]
- Mixer sample rate: 44.1, 48, 88.2 or 96 kHz. The [Follow USB] option makes it follow the computer. [5][6]
- At 88.2/96 kHz the MGX16 sends only 12 per-channel tracks (DAW 1-12), the same as the MGX12. At 44.1/48 kHz it sends 16. (USB MAIN signal name table, Windows and Mac.) [5]

### 2. Driverless status
- macOS/Windows: the user guide tells you to install "TOOLS for MGX/URX", which installs the Yamaha Steinberg USB Driver. [5] Without it you get the UAC 2.0 counts above. [5][6]
- iOS/iPadOS: named by the maker, iPhone included. "This product is automatically recognized by the iPad, iPhone or Android device once connected. There is no need to configure any settings." [5]
  - USB-C iPhone/iPad: USB-C to USB-C cable to USB MAIN or USB SUB. [5]
  - Lightning iPhone/iPad: Apple Lightning to USB 3 Camera Adapter plus a USB-A to USB-C cable. [5]
  - Use USB MAIN for multitrack. USB SUB is 2 in / 2 out. [5][6]
  - Power: Yamaha recommends powering the iPhone/iPad during long use, through Apple's USB-C Digital AV Multiport Adapter. [5]
- Setting for iPhone/iPad: SETUP > Peripheral > USB Main > [Generic Driver Audio Channel Suppression]. "None" gives the full channel count; "2 Channels" restricts it to 2 in / 2 out. [5]
- What reaches an iPad/iPhone with "None", per the signal table: [5]
  - MGX16: device inputs CH1-16 = CH1-16 Rec Out, and CH17-18 = USB MAIN A.
  - MGX12: CH1-12 Rec Out plus CH13-14 = USB MAIN A.
  - Whether the 88.2/96 kHz limit of 12 also applies on iPad/iPhone: the iPad table doesn't say (unknown).

### 3. Onboard recording
- microSD: up to 16 tracks at 44.1/48 kHz, or 8 tracks at 88.2/96 kHz. WAV, 24-bit, up to 96 kHz. UHS-I/Class 10 or higher, exFAT supported. [5][6]
- Track count is chosen in pairs: microSD screen > RECORDER > [Track Count]. [5]

### 4. Recording settings
- Sample rate: SETUP > sampling frequency buttons, or [Follow USB]. [5]
- iPad/iPhone channel limit: SETUP > Peripheral > USB Main. [5]

### 5. Routing
- USB DAW 1-16 (1-12 on MGX12) = "CH 1-16 Rec Out", fixed per channel. [5]
- USB MAIN A/B/C: three stereo pairs whose sources are chosen per pair in SETUP > USB menu > output source selection buttons (sources include channels; the full list is graphical). [5] Only MAIN A reaches an iPad/iPhone on the generic driver. [5]

### 6. Tap points
- Per channel: Channel view > Channel settings > [Rec Point] lets you "select the point within the signal path from which to directly record the signal of a channel". [5]
- The available Rec Point choices: unknown. The block diagram labels near "Rec Point" read PRE/POST, but the positions are not described in text. [6]

### 7. Gotchas
- 22 tracks need the Yamaha driver. Class compliant gives 18 (MGX16), and an iPad/iPhone gets 16 channel tracks plus one stereo pair. [5][6]
- At 88.2/96 kHz the MGX16 drops to 12 channel tracks on a computer. [5]

## 8. Confidence
| Fact | Confidence |
|---|---|
| MG XU 2x2 UAC 2.0, 24-bit, up to 192 kHz | maker |
| MG XU driverless on Mac | our inference from maker "UAC 2.0 compliant" |
| MG XU USB send = stereo bus, pre STEREO LEVEL | maker (MG10XU manual) |
| MG XU on iPhone/iPad via camera kit | maker (brochure; boxes name iPad only) |
| MG XU USB-C iPhone/iPad | unknown |
| MGX UAC 2.0 18in/16out (16), 14/12 (12); driver 22/18 | maker |
| MGX16 12 channel tracks at 88.2/96 kHz on a computer | maker (signal table) |
| MGX on iPad and iPhone, no settings needed | maker |
| MGX Rec Point options | unknown |

## 9. Sources
1. https://usa.yamaha.com/products/proaudio/mixers/mg_series_xu_model/specs.html
2. MG10XU technical specifications: https://usa.yamaha.com/files/download/other_assets/2/1507032/MG10XU_technical_specifications_En_B0.pdf
3. MG10XU owner's manual: https://usa.yamaha.com/files/download/other_assets/8/1506958/MG10XU_owners_manual_En_B0.pdf (Rear panel USB section; TO MON/TO STO chart; attenuator)
4. MG series brochure: https://usa.yamaha.com/files/download/brochure/1/330961/mg_brochure_en_webcatalogue.pdf
5. MGX16V/16/12V/12 User Guide: https://usa.yamaha.com/files/download/other_assets/4/2926764/MGX16V_16_12V_12_user_guide_En_D0.pdf (connecting to Mac/Windows/iPad/iPhone p.27-31; SETUP USB menu p.59; USB Main menu p.61; microSD RECORDER p.86; Rec Point p.99; digital I/O table p.196; USB MAIN signal name table p.204-205)
6. MGX technical specifications: https://usa.yamaha.com/files/download/other_assets/4/2927054/mgx16v_16_12v_12_technical_specifications_en_c0.pdf and https://usa.yamaha.com/products/proaudio/mixers/mgx/specs.html

## Gaps
- MG XU multitrack: not possible. Say "stereo mix only" every time.
- MG XU on a Mac without a driver: Yamaha says UAC 2.0 compliant, not "no driver". Say "class compliant per Yamaha".
- MG XU with a USB-C iPhone or iPad: not named by Yamaha. Say "not tested yet".
- MG12XU/16XU/20XU USB return channels: not checked. Don't name the channel; say "the channel with the USB switch".
- MGX Rec Point choices: not listed in text. Don't name them; tell readers to check Channel settings > Rec Point.
- MGX 88.2/96 kHz on iPad/iPhone: channel count not stated. Tell readers to use 44.1 or 48 kHz for 16 tracks.
