# Yamaha MG XU series (MG10XU, MG12XU, MG16XU, MG20XU) and the newer MGX series

Checked 2026-11-06. Sources are numbered in section 9.

## Part A: MG XU (analog, stereo USB only)

### 1. USB audio to a computer
- 2 IN / 2 OUT, "USB Audio Class 2.0 compliant, Sampling Frequency: Max 192 kHz, Bit Depth: 24-bit" (all four XU models, spec page). [1]
- MG10XU tech spec: 44.1, 48, 88.2, 96, 176.4 and 192 kHz. Data length: 16/24-bit with UAC 2.0, 24-bit with the Yamaha Steinberg USB Driver. Connector: USB Standard-B. [2]

### 2. Driverless status
- macOS: class compliant (UAC 2.0). [1][2]
- iOS/iPadOS: supported by the maker. The brochure says "connect ... to your iPhone / iPad (2 or later) using Apple's Camera Connection Kit / Lightning to USB Camera Adapter". [4] That is stereo only.
- Windows: the owner's manual says "you may need a dedicated USB driver" (Yamaha Steinberg USB Driver). [3]

### 3. Onboard recording
- None.

### 4. Recording settings
- Sample rate is set by the host (up to 192 kHz). No console menu.

### 5. Routing
- Fixed: "The sound of the stereo bus is output to the computer. (The [STEREO LEVEL] knob does not affect the sound.)" [3] So the USB send is the stereo bus, before the STEREO LEVEL control.
- USB return: channel 9/10 (MG10XU) [LINE/USB] switch set to USB. The [TO MON / TO STO] switch sends the USB return either to the monitor only or to the stereo bus. Use TO MON while recording to avoid a feedback loop. [3]

### 6. Tap points
- Only the stereo mix: post channel processing, post channel levels, and not affected by the STEREO LEVEL knob. [3] There are no per-channel feeds.

### 7. Gotchas
- Not a multitrack interface: only 2 channels (the stereo mix). A ShowRecorder guide must say this plainly. [1][2][3]

## Part B: MGX series (MGX16, MGX12, MGX16V, MGX12V; digital, 2025)

Relevant because MGX is Yamaha's newer "MG" line with multitrack USB.

### 1. USB audio to a computer
- USB MAIN (USB-C, USB 2.0 High Speed): [6]
  - With the Yamaha Steinberg USB Driver: MGX16/16V up to 22 in / 22 out; MGX12/12V up to 18/18.
  - Class compliant (UAC 2.0): MGX16/16V 18 in / 16 out; MGX12/12V 14 in / 12 out.
  - 32-bit, up to 96 kHz.
- USB SUB: UAC 1.0, 16-bit/48 kHz, 2 in / 2 out. [6]
- Mixer sample rate: 44.1, 48, 88.2 or 96 kHz. The [Follow USB] option makes it follow the computer. [5][6]

### 2. Driverless status
- macOS/Windows: the user guide tells you to install "TOOLS for MGX/URX", which installs the Yamaha Steinberg USB Driver. [5] Without it you get the UAC 2.0 counts above. [6]
- iOS/iPadOS: supported by the maker. "This product is automatically recognized by the iPad, iPhone ... There is no need to configure any settings." USB-C to USB-C cable, or the Lightning to USB 3 Camera Adapter. [5]
- Setting for iPhone/iPad: SETUP > Peripheral > USB Main > [Generic Driver Audio Channel Suppression]. "None" gives the full channel count; "2 Channels" restricts it to 2 in / 2 out. [5]
- What reaches an iPad with "None", per the signal table: [5]
  - MGX16: device inputs CH1-16 = CH1-16 Rec Out, and CH17-18 = USB MAIN A.
  - MGX12: CH1-12 Rec Out plus CH13-14 = USB MAIN A.

### 3. Onboard recording
- microSD: up to 16 tracks at 44.1/48 kHz, or 8 tracks at 88.2/96 kHz. WAV, 24-bit, up to 96 kHz. UHS-I/Class 10 or higher, exFAT supported. [5][6]
- Track count is chosen in pairs: microSD screen > RECORDER > [Track Count]. [5]

### 4. Recording settings
- Sample rate: SETUP > sampling frequency buttons, or [Follow USB]. [5]
- iPad channel limit: SETUP > Peripheral > USB Main. [5]

### 5. Routing
- USB DAW 1-16 (1-12 on MGX12) = "CH 1-16 Rec Out", fixed per channel. [5]
- USB MAIN A/B/C: three stereo pairs whose sources are chosen per pair in SETUP > USB menu > output source selection buttons (sources include channels; the full list is graphical). [5] Only MAIN A reaches an iPad on the generic driver. [5]

### 6. Tap points
- Per channel: Channel view > Channel settings > [Rec Point] lets you "select the point within the signal path from which to directly record the signal of a channel". [5]
- The available Rec Point choices: unknown. The block diagram labels near "Rec Point" read PRE/POST, but the positions are not described in text. [6]

### 7. Gotchas
- 22 tracks need the Yamaha driver. Class compliant gives 18 (MGX16), and an iPad gets 16 channel tracks plus one stereo pair. [5][6]

## 8. Confidence
| Fact | Confidence |
|---|---|
| MG XU 2x2 UAC 2.0, 24-bit, up to 192 kHz | confirmed by maker |
| MG XU USB send = stereo bus, pre STEREO LEVEL | confirmed by maker |
| MG XU on iPhone/iPad via Camera Connection Kit | confirmed by maker (brochure) |
| MGX UAC 2.0 18in/16out (16), 14/12 (12); driver 22/18 | confirmed by maker |
| MGX on iPad, no settings needed | confirmed by maker |
| MGX Rec Point options | unknown |

## 9. Sources
1. https://usa.yamaha.com/products/proaudio/mixers/mg_series_xu_model/specs.html
2. MG10XU technical specifications: https://usa.yamaha.com/files/download/other_assets/2/1507032/MG10XU_technical_specifications_En_B0.pdf
3. MG10XU owner's manual: https://usa.yamaha.com/files/download/other_assets/8/1506958/MG10XU_owners_manual_En_B0.pdf (Rear panel USB section; TO MON/TO STO)
4. MG series brochure: https://usa.yamaha.com/files/download/brochure/1/330961/mg_brochure_en_webcatalogue.pdf
5. MGX16V/16/12V/12 User Guide: https://usa.yamaha.com/files/download/other_assets/4/2926764/MGX16V_16_12V_12_user_guide_En_D0.pdf (connecting to Mac/Windows/iPad p.27-30; SETUP USB menu p.59; USB Main menu p.61; microSD RECORDER p.86; Rec Point p.99; USB MAIN signal name table p.204)
6. MGX technical specifications: https://usa.yamaha.com/files/download/other_assets/4/2927054/mgx16v_16_12v_12_technical_specifications_en_c0.pdf and https://usa.yamaha.com/products/proaudio/mixers/mgx/specs.html
