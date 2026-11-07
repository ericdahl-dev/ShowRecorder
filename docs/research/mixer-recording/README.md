# Mixer facts for "how to multitrack record a <mixer>" guides

Researched 2026-11-06. Each mixer has a detail file in `<slug>.md` in this folder. A detail file has: USB spec, driver status, onboard recording, recording settings, routing (menu paths, defaults, per-slot vs block, sources, virtual soundcheck playback), tap points, gotchas, confidence per fact and source URLs. The table below summarizes them; check the detail file before you publish a number.

Confidence labels:
- **maker**: the maker's own manual, spec page, support article or staff post.
- **secondary**: retailer, forum user, review, or a third party's own text. A maker's own PDF read on a dealer or distributor site counts as maker, and the detail file names the host.
- **unknown**: no source found. We don't guess.

ShowRecorder context: it records over USB from any class-compliant interface. Mixer Link (names, colors, auto-gain) works only on XR18/MR18 and X32/M32. In `docs/tested-hardware.md`, the only verified rig is XR18 to a Mac over USB. ShowRecorder has also recorded all 18 XR18 channels on an iPhone (owner fact O-2 in xr18-mr18.md, 2026-11-06); a full-length show on an iPhone through a powered hub is still waiting on #327.

## iPhone/iPad without a computer: read this first

**Won't work as a multitrack source over USB:**
- **Behringer XR12 / XR16, Midas MR12.** There's no USB audio interface. The only USB port is Type-A for a 2-track stereo stick recording (maker manual). File: [`xr12-xr16-mr12.md`](xr12-xr16-mr12.md). MR12 is secondary.
- **Allen & Heath Avantis / Avantis Solo.** There's no USB audio interface at all. USB-A handles stereo record and playback only. Multitrack needs an I/O option card (Dante, Waves, MADI, gigaACE). Maker. File: [`ah-avantis.md`](ah-avantis.md).
- **Yamaha MG XU (MG10/12/16/20XU).** It is class compliant and works with an iPad through a camera kit (maker), but USB is **stereo only, 2 in / 2 out**. It records a stereo mix, not multitrack. The newer **Yamaha MGX** (MGX12/16) is different: Yamaha says iPad and iPhone are recognized automatically (USB-C cable or Lightning to USB 3 adapter), with up to 18 in on MGX16 at 44.1/48 kHz; at 88.2/96 kHz the MGX16 sends only 12 channel tracks (maker). File: [`yamaha-mg-xu.md`](yamaha-mg-xu.md).
- **Yamaha DM3.** The reference manual and owner's manual both say the Yamaha Steinberg USB Driver "is required for communication with a computer", and a Mac driver is published. Nothing shows it working driverless, so assume no iPhone/iPad until tested. Maker statement; iOS behavior unknown. File: [`yamaha-dm3.md`](yamaha-dm3.md).

**Unknown, so test before we claim it:**
- X32/M32 with X-USB, X-LIVE, DN32-USB or DN32-LIVE. macOS is driverless (maker). The DN32-USB is called "class-compliant" (maker). No maker statement covers iOS.
- WING family. Mac driverless is forum only. iPad reports conflict: one user's iPads work, another's three iPads on iOS 18 did not (secondary).
- Allen & Heath SQ. Class compliant on Mac (maker). The maker says the USB-B interface needs no drivers on any device or OS that supports class-compliant audio, but iOS is not named.
- Yamaha TF. Class compliant on Mac (maker); iOS is not stated.
- Soundcraft Ui24R. Core Audio with no driver on Mac (maker FAQ); iOS is not stated.
- Mackie DL32S / DL16S / DL32SE. Driverless on Mac; iOS is not stated.

**Maker says iPad works.** The iPhone is rarely named (exceptions: Zoom L-12/L-20 and Yamaha MGX); elsewhere "iPhone" stays unknown until we test:
- XR18/MR18: "iOS 7 or higher (iPad)".
- CQ: A&H staff, with stream mode set to Multitrack.
- New Qu-5/6/7: "works but not officially supported", with Multitrack stream mode.
- Qu Classic: A&H staff.
- PreSonus StudioLive III: KB article.
- Zoom L-12/L-20: iPad and iPhone named on the product pages, with the CLASS COMPLIANT MODE switch on. Zoom says MODE and SAMPLE RATE can't change after startup; setting all three switches before power-on is our advice.
- Mackie DL32R: manual, via iPad camera kit.
- Soundcraft Signature MTK: recording guide, via camera kit.
- Yamaha MGX: maker. MG XU also works, but stereo only.

**Power:** no mixer powers the iPhone over its USB-B or USB-C audio port.
- A&H staff say CQ's USB-A 5 V is for a drive only.
- PreSonus says the camera adapter "does not allow you to charge".
- Yamaha's MGX user guide recommends powering the iPhone/iPad during long use.
- The Soundcraft 22MTK has a separate 500 mA USB-A socket for charging a phone. It is not the audio port.

Guides should tell readers to use a powered USB-C hub or a camera adapter with power pass-through for long shows. This matches the hub advice in `docs/tested-hardware.md`.

## Summary table

Abbreviations:
- **USB rec ch**: channels the mixer sends to the computer (the record direction) / channels back.
- **Per-slot?**: can any source be patched into any USB slot, or are slots fixed or in blocks?
- **Default tap**: where in the channel the USB/record feed is taken, out of the box.

| Mixer | USB rec ch / rates | macOS driverless | iOS/iPadOS | Onboard recording (no computer) | Per-slot USB routing? | Default/available tap | Confidence | Detail file, key source |
|---|---|---|---|---|---|---|---|---|
| Behringer X32 (X-USB / X-LIVE card) | 32x32, 44.1/48 kHz, 24-bit; card modes 32/32, 16/16, 32/8, 8/32, 8/8, 2/2 (Setup > Card) | Yes, CoreAudio (maker OS lists stop at 10.12) | Unknown | X-LIVE: 8/16/32 ch, 32-bit poly WAV on 2 SD/SDHC (FAT32, 32 GB max each), about 200 min at 32 ch/44.1 kHz. X-USB: none. Console USB-A stick: stereo, 16-bit WAV | Card out in blocks of 8 (ROUTING > card out). From fw 4.0, User In/User Out allow per-slot sources (fw 4.15 release notes name "User Routing"; menu detail secondary) | Local/AES50 blocks = raw input (pre-processing, post-preamp gain). Out 1-16/P16/Aux Out slots have taps Input / Pre-EQ / Pre-Fader / Post-Fader (per slot) | Specs: maker. User routing: secondary | [`x32.md`](x32.md); https://www.behringer.com/en/products/0606-ABV |
| Midas M32 / M32R (DN32-USB / DN32-LIVE) | DN32-USB 32x32, 24-bit/48 kHz; DN32-LIVE 32/16/8/2 | Yes ("class-compliant ... no driver required", Klark Teknik) | Unknown | DN32-LIVE: same as X-LIVE. Console USB stick: stereo 16-bit | Same as X32 (blocks of 8); user routing secondary | Same as X32 | Specs: maker. User routing: secondary | [`m32.md`](m32.md) |
| Behringer WING / Rack / Compact | 48x48, 24-bit, USB 2.0 Type-B; count 2x2, 8x8, 16x16, 32x32 or 48x48 at SETUP > AUDIO; console clock 44.1 or 48 kHz (maker); USB at 44.1 not stated | Forum only (secondary) | Conflicting (secondary) | WING-LIVE card: 64 ch on 2 SD cards (32 each), 48 kHz/32-bit poly WAV, FAT32 32 kB clusters. Front USB stick: 2 or 4 tracks; needs USB HOST SPEED = HS for 4 tracks/24-bit (FS = 2 tracks/16-bit) | Yes, true per-slot router (ROUTING > OUTPUTS) | Channel taps INPUT, FILTER, TAP 3-5, PRE FDR, POST FDR, POST PROC via User Signals | Specs/routing: maker. Driverless: secondary | [`wing.md`](wing.md); WING user manual 2025-10-20 (empowertribe CDN) |
| Behringer XR18 / Midas MR18 | 18x18 or 2x2 (Setup > Audio/MIDI), 44.1/48 kHz (48 default), USB 2.0 Type-B | Yes, CoreAudio | **iPad: yes, iOS 7+ (maker, XR18)**; iPhone unknown; MR18 iOS secondary | None | Yes, per-slot USB sends in the Routing grid; default USB send map unknown | Maker block diagram feeds each channel to the patch at Pre Low Cut and Post Fader; per-USB-send tap choice and names secondary | XR18: maker. MR18: maker for USB specs, secondary for iOS | [`xr18-mr18.md`](xr18-mr18.md); https://www.behringer.com/en/products/0605-AAD |
| **Behringer XR12 / XR16, Midas MR12** | **None (no USB audio interface)** | n/a | **No** | 2-track stereo WAV to a USB-A stick (XR12: 16-bit, 44.1/48 kHz, maker) | n/a | n/a | XR: maker. MR12: secondary | [`xr12-xr16-mr12.md`](xr12-xr16-mr12.md); https://www.behringer.com/en/products/0605-AAC ; https://www.behringer.com/en/products/0605-AAB |
| Allen & Heath SQ-5/6/7, SQ-Rack | 32x32, 96 or 48 kHz, USB-B | Yes (maker) | Not named; maker says class compliant, no drivers on any OS that supports class-compliant devices. Untested | SQ-Drive: 16 ch @96k or 32 ch @48k, 24-bit mono WAV to a fast USB drive (maker: most sticks too slow); or stereo | Yes, each USB slot in the I/O screen; default LR to USB 1-2, then direct outs (which channel lands on USB 3: unknown) | Global direct-out source: Post Preamp / Post HPF / Post Gate / Post Insert Return / Post PEQ / Post Comp / Post Delay. Post Preamp excludes Trim. Tie Lines = raw post-preamp | Maker; iOS unknown | [`ah-sq.md`](ah-sq.md); https://www.allen-heath.com/hardware/sq/sq-5/ |
| A&H Qu (new Qu-5/6/7) | 32x32 USB-C, 96 or 48 kHz, 16/24-bit | Yes (class compliant) | Works, "not officially supported" (maker); needs USB Stream Mode = Multitrack | SD: 16 ch @96k or 32 ch @48k; USB-A stereo | Yes (I/O > Outputs > USB) | Direct-out point names unknown | Maker | [`ah-qu.md`](ah-qu.md); https://www.allen-heath.com/hardware/qu/qu-5/ |
| A&H Qu Classic (Qu-16/24/32/SB/Pac) | 48 kHz USB-B; Qu-16 sends 24, Qu-24/32/Pac send 32 | Yes | Yes per A&H staff (forum) | Qu-Drive 18 tracks to USB drive | Sends per slot; returns fixed 1:1 | Default Insert Send (post-preamp, no processing); switchable to Direct Out | Maker / staff | [`ah-qu.md`](ah-qu.md) |
| A&H CQ-12T / 18T / 20B | 16x16 / 24x22 / 24x24, 48 or 96 kHz, USB-B | Yes | **Yes, A&H staff: "class compliant ... can be used with an iPad"**; set Stream Mode = Multitrack | SD: matches USB counts at 48k; 16 ch at 96k on 18T/20B; USB-A stereo | Fixed: mono channels 1:1; only the last stereo pairs are assignable (last pair = Main LR by default) | Global CONFIG > Digital Audio > USB/SD > Source Point (option names forum only; factory default unknown); reportedly no post-fader | Maker / staff; tap names secondary | [`ah-cq.md`](ah-cq.md); https://forums.allen-heath.com/t/usb-interface/16038 |
| **A&H Avantis / Solo** | **No USB audio interface** | n/a | **No** | Stereo 24/96 WAV only; multitrack via option card | Via card: I/O > Virtual SoundCheck Record Send, Outputs, Tie Lines | Record Send/Tie Lines pre-trim; direct-out source global (8 points); Gain Tracking available | Maker (incl. Solo) | [`ah-avantis.md`](ah-avantis.md) |
| Soundcraft Ui24R | 32x32, 48 kHz (bit depth unknown) | Yes (Harman FAQ; supersedes the 2017 manual) | Unknown | 22 ch to a USB stick (FAT32, 32 GB max, 25 MB/s or faster); WAV or FLAC per a 2017 review (secondary), not stated by maker | **Fixed**: USB 1-2 Master, 3-10 AUX 1-8, 11-32 inputs 1-22 | Inputs pre-processing, pre-fader, straight from the preamp; use AUX as POST/POST PROC for processed tracks | Maker; USB tap from an Si-tagged Harman article; file format secondary | [`soundcraft-ui24r.md`](soundcraft-ui24r.md) |
| Soundcraft Signature 12 MTK / 22 MTK (discontinued) | 14 in/12 out; 24 in/22 out; 44.1/48 kHz, 24-bit, USB-B | Yes (Core Audio) | iPad via camera kit (maker) | None | Fixed 1:1; last pair = LR post-fader | Post-gain, pre-HPF/EQ | Maker | [`soundcraft-signature-mtk.md`](soundcraft-signature-mtk.md); https://harman.helpjuice.com/en_US/soundcraft-signature-mtk-recording-guide |
| Yamaha TF1/3/5/TF-Rack | 34x34, 48 kHz only, 24-bit, USB-B | Yes ("class compliant driver", Yamaha TF Live Recording guide) | Unknown | 2-track WAV to USB HDD/SSD | USB 1-32 fixed = CH1-32 direct outs; 33/34 = recorder source (ST, AUX pair, MTRX) | Per channel: Pre DG / Pre HPF / Pre Fader / Post ON (factory default unknown; check each channel in CH VIEW). CH33-40 and ST IN can't be recorded | Maker | [`yamaha-tf.md`](yamaha-tf.md); https://usa.yamaha.com/products/proaudio/mixers/tf/specs.html |
| **Yamaha DM3 / DM3 Standard** | Up to 18x18, 96/48 kHz, 32-bit; Driver Mode 1 = one 18x18 device, Mode 2 = four devices (2/2+2/2+2/2+12/12) | **Maker says the driver is required** | Unknown, unlikely | 2-track WAV/MP3 to USB storage | Yes, per port (SETUP > PATCH > OUTPUT); default USB 1-16 = INPUT 1-16, 17-18 = STEREO | Unknown | Maker | [`yamaha-dm3.md`](yamaha-dm3.md); https://usa.yamaha.com/products/proaudio/mixers/dm3/specs.html |
| **Yamaha MG XU** | **2 in/2 out only**, up to 192 kHz, UAC2 | UAC 2.0 compliant (maker); "no driver on Mac" is our inference | iPad via camera kit, **stereo only** | None | n/a (stereo bus before the STEREO LEVEL knob) | n/a | Maker | [`yamaha-mg-xu.md`](yamaha-mg-xu.md) |
| PreSonus StudioLive III (consoles, 32R/24R; 16R) | 64x64 (Native) or 34x34 (Compatibility), 44.1/48 kHz, USB-B; 16R 18x18 (2022 manual) or 24x24 (KB, fw 2.4): conflicting | Yes | **Yes (PreSonus KB)**; iPhone named only in a general statement; 64x64 crashes some iPadOS DAWs | Consoles: SD 34 tracks (32 + main); racks: stereo only. SDHC up to 32 GB, Class 10 U3, FAT32; SDXC not supported | Yes: Home > Audio Routing > Digital Patching > USB Sends. SD on 32-ch consoles: 1-32 fixed; 64S fully patchable | "Inputs" tap unknown (manual silent) | Maker; tap unknown | [`presonus-studiolive-iii.md`](presonus-studiolive-iii.md); https://support.presonus.com/hc/en-us/articles/360059975732 |
| Mackie DL32S / DL16S / DL32SE | 32x32 (16x16), 48 kHz, 16/24-bit, USB-B | Yes (UAC 2.0) | Unknown | None | Yes ("any combination of channels or outputs"); Master Fader I/O Patch > USB, default Mic Pre N to USB N (Master Fader 5 guide; SE models unknown) | "Mic Pre" = before trim, HPF, gate, comp, EQ; "Channel Post-DSP" (Ch Direct Out) = post-EQ, pre-mute/fader | Maker | [`mackie-dl32s.md`](mackie-dl32s.md) |
| Mackie DL32R | 32x32, 48 kHz, USB-B | Yes | **iPad: yes (manual, camera kit)**; iPhone unknown | 1-32 tracks (16 or 24-bit, 48 kHz) as one interleaved multichannel WAV per take, split under 2 GB, to a spinning USB hard drive formatted by the DL32R (no thumb drive, no hub). The 2015 spec table's "1-24" is older. **The drive and the computer can't be used at the same time** | Yes: I/O Patch > USB tab; Mic Pre, Channel Post-DSP, Main L/R (pre or post fader), Aux, Subgroup, Matrix; default Mic Pre N to USB N | Mic Pre (before trim/HPF) or Channel Post-DSP (after HPF/gate/comp/EQ, before mute/fader) | Maker (manual, spec sheet, Master Fader 5 guide on a distributor site) | [`mackie-dl32r.md`](mackie-dl32r.md) |
| Zoom LiveTrak L-12 / L-20 / L-20R | L-12 14 in/4 out; L-20 22 in/4 out; **USB 44.1/48 kHz only** (interface off at 96k) | Mac driver offered (macOS 10.14-26, Intel listed); driver-free not stated (unknown) | **Yes, iPad and iPhone (iOS 8/9-26, maker product pages); rear CLASS COMPLIANT MODE switch ON; Lightning camera adapter named** | SD: 14 tracks (L-12), 22 (L-20), WAV up to 24/96 | No: fixed order, channels then master L/R | L-12: post-comp, pre-EQ and low cut (USB and SD). L-20: SD REC SOURCE PRE/POST COMP (global); USB post-comp, pre-EQ regardless (manual text + block diagram, our reading) | Maker | [`zoom-livetrak-l12-l20.md`](zoom-livetrak-l12-l20.md); https://zoomcorp.com/en/us/digital-mixer-multi-track-recorders/digital-mixer-recorder/livetrak-l-12/ |

## Routing: block vs per-slot (owner's question)

- **X32 / M32: blocks of 8.** ROUTING > card out sends four 8-channel blocks to the card. Local and AES50 input blocks give the raw input. To record the main mix, buses or a tapped channel:
  - **Before fw 4.0:** stage them first in Out 1-16, P16 or Aux Out (each slot has its own tap point), then send that block to the card.
  - **Fw 4.0 and later:** User In / User Out let you pick any source per slot, with 48 User Out slots. Those slots have no tap points of their own, so tapped signals still go through Out 1-16 or P16. The X32 4.15 release notes name "User Routing", but the menu detail is secondary (forum and ControlBooth). M32 user routing is also secondary.
  - When to use which: blocks for a straight 1:1 input record. User routing when you want the main LR or buses alongside 30 inputs, a different channel order, or different tap points per track.
- **Per-slot routers:** WING (ROUTING > OUTPUTS), XR18/MR18 (Routing grid), SQ (I/O screen), new Qu (I/O > Outputs > USB), Qu Classic (sends), DM3 (SETUP > PATCH > OUTPUT), PreSonus III (Digital Patching > USB Sends), Mackie DL (I/O Patch > USB), Avantis via option card (I/O screen).
- **Fixed maps:** Ui24R, Signature MTK, Zoom LiveTrak, Yamaha TF (1-32 fixed, only 33/34 selectable), CQ (only the last stereo pairs assignable).

Details and menu paths are in each detail file in this folder, section 5.

## Tap points: pros and cons (shared section for every guide)

This section is general recording practice, not a maker claim. Mixer-specific names and positions are in each detail file, section 6.

| Tap | Common names | Pros | Cons | Use it when |
|---|---|---|---|---|
| Analog in / post-preamp, before digital trim | X32 "Local/AES50 in" block, A&H Tie Line / "Post Preamp", Avantis Record Send, Mackie "Mic Pre", Yamaha TF "Pre DG", Ui24R inputs | Raw and unprocessed. Survives trim, EQ, mute and fader moves. Best for virtual soundcheck, since playback comes back in at the same point | Preamp gain is still baked in: a gain change mid-show changes the track level, and a clip at the preamp is permanent. Before the HPF, so rumble and handling noise are kept | The default for multitrack you'll remix later, and for virtual soundcheck |
| Post-gain/trim, pre-EQ (incl. post-HPF variants) | X32 "Pre-EQ", A&H "Post HPF", TF "Pre HPF", MTK "post-gain, pre-EQ"; nearby, Zoom L-12 (post-comp, pre-EQ) | Clean tracks, and the digital trim is included. A post-HPF variant removes rumble | Trim moves change the recording. HPF settings get baked in on post-HPF taps | Clean multitrack where the engineer uses trim to set level |
| Post-EQ / post-dynamics / post-processing (pre-fader) | X32 "Pre-Fader", A&H "Post Comp/Post Delay", WING "POST PROC", Mackie "Ch Direct Out" | Matches the FOH sound, so tracks are "ready" | EQ and compression are baked in and can't be undone in the remix. A bad compressor setting ruins the take | Quick release-ready recordings, streaming feeds |
| Post-fader | X32 "Post-Fader", WING "POST FDR", TF "Post ON", A&H via mix sends | Follows the show mix exactly | Fader down or a muted channel means a silent track. Every fader ride is baked into the recording | Bus/mix recordings, not channel stems |
| Main mix / buses (LR, aux, groups, matrix) | Every mixer's "Main LR"/"ST" slots | A reference mix. Matrix or audience-mic mixes are handy for video | Reflects room-corrected FOH balance (too little of loud stage instruments) | Record alongside stems as a reference track |

### Mixer-specific caveats to repeat in guides

- **Gain changes reach "raw" taps.** Even the earliest digital tap is after the analog preamp.
  - The X32 maker manual says FOH gain changes "can be heard in the recording".
  - Avantis has Gain Tracking, which compensates the channel trim. But Record Send and Tie Lines are before trim, so a monitor engineer's preamp change on a shared stage box still changes the recording. This is our inference from two maker statements.
  - PreSonus (Preamp Permissions) and Mackie DL32R (Access Limiting) can lock who changes gain. That a gain change otherwise reaches the record feed is our inference from the signal flow.
  - No gain compensation was found for X32/M32/WING shared stage boxes (unknown).
- **Digital trim vs analog gain.** Where a mixer has both (A&H, Yamaha "DG" = digital gain, WING, Mackie), the earliest tap is before trim (WING: our inference, not a manual statement; SQ: maker says Post Preamp is "affected only by the preamp gain"). Tell readers to set the analog gain for headroom and leave level riding to the trim and fader.
- **HPF placement.**
  - Ui24R inputs, Mackie "Mic Pre", A&H "Post Preamp" and TF "Pre DG" are before the HPF.
  - TF has both "Pre DG" and "Pre HPF" points; see [`yamaha-tf.md`](yamaha-tf.md) for the order.
  - Zoom L-12 puts low cut in the EQ section, which suggests its pre-EQ tap excludes the low cut (inference).
- **A low channel-count mode sends only a few channels.** X32/M32 card modes 8/8 and 2/2 (Setup > Card), XR18 2x2 (Setup > Audio/MIDI), WING 2x2 to 32x32 (SETUP > AUDIO) and CQ/new Qu Stream Mode "Stereo" all cut what the recorder sees (maker, per detail file). Check this first when a recorder shows only 2 or 8 channels (question 9 below).
- **Phantom power** sits at the preamp and doesn't affect taps. Switching it on while recording makes a pop on that track.
- **Fixed-tap mixers can't be changed.** On Ui24R, MTK, Zoom and TF 1-32, the reader picks only on/off, or for TF the per-channel point. For a processed or post-fader version on Ui24R, use an AUX set to POST / POST PROC (maker).

## Ten most common questions about recording from digital mixers

Evidence is Google autocomplete, pulled on 2026-11-06 via suggestqueries.google.com, plus forum thread titles reached during research. Reddit was not checked.

1. **How do I multitrack record my mixer to a computer/Mac?** "how to record x32 on mac", "how to record from x32 into logic", "x32 recording to computer", "soundcraft ui24r recording to daw", "how to multitrack record behringer x32", "how to multitrack record on behringer wing".
2. **Can I record every channel to a USB stick or SD card without a computer?** "x32 record to usb stick", "x32 record to sd card", "xr18 record to usb stick", "sq5 multitrack recording usb stick", "qu 16 multitrack recording usb", "soundcraft ui24r recording to usb stick", "behringer wing usb stick recording". The answer differs a lot per mixer: X32 USB-A and XR18 do stereo only.
3. **How do I route channels to USB / the card?** "x32 usb recording routing", "x32 card output routing", "x32 card input routing", "behringer wing usb recording setup".
4. **What format and settings does it record in?** "x32 usb recording format", "behringer wing usb recording format", "x32 usb stick format", "soundcraft ui24r recording quality".
5. **How do I record from the mixer to my iPhone/iPad?** "record mixer to iphone", "how do i record from my mixer to my phone", "app to record from mixer to phone", "xr18 record to ipad", "record from mixer to ipad". Forum titles: "Recording to iPad/GarageBand?" and "iPad connection - CQ18T via USB" (A&H forums).
6. **Is it class compliant / do I need a driver?** "is behringer x32 class compliant", "x32 card driver", "class compliant digital mixer". Forum titles: "Is WING USB audio class compliant?" (behringer.world), "Are Qu mixers class compliant with iOS devices?" (A&H forums), "Does the Cubasis 3 with iPad Pro work with Yamaha DM3" (Steinberg forums).
7. **Pre-fader or post-fader for recording?** "pre fader vs post fader recording", "x32 card out post fader".
8. **How do I play the tracks back for a virtual soundcheck?** "virtual soundcheck x32", "virtual soundcheck behringer wing", "virtual soundcheck m32", "virtual soundcheck xr18", "virtual soundcheck avantis", "x32 usb recorder playback".
9. **Why isn't it recording, or why only 2 channels?** "x32 usb recording problem", "behringer x32 usb recorder not working", "x32 erkennt usb stick nicht". Forum titles: "only two USB channels are sent to vMix from a digital Mixer (Yamaha TF3)" (vMix forums); CQ app showing only L/R until Stream Mode = Multitrack (A&H forum 16038).
10. **Can I record buses or aux inputs too, and which mixer is best for multitrack?** "x32 record aux inputs", "best digital mixer for multitrack recording", "best digital mixer for live recording".

Also frequent: "how to record live band practice", "how to record a gig", "how to record live music from mixer".

## Biggest open items (worth a real-device test before publishing)

- iPhone (not iPad) over USB for any mixer other than the XR18. No maker names the iPhone. XR18: all 18 channels recorded (O-2); a full show through a powered hub is #327.
- iOS with X32/M32 cards, WING, SQ, TF, Ui24R and DL32S.
- PreSonus III "Inputs" tap point; DM3 tap point; new Qu direct-out point names; CQ source-point names (forum only).
- Ui24R onboard file format (secondary only); PreSonus 16R USB count (maker sources conflict); WING USB and WING-LIVE at 44.1 kHz (console clock 44.1 is maker-confirmed).
- X32/M32 user-routing menu paths from a maker source.
