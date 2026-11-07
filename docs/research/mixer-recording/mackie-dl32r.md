# Mackie DL32R

Source key used below:
- [OM] DL32R Owner's Manual (Mackie / LOUD Technologies, (c) 2015): https://mackie.com/img/file_resources/DL32R_OM.pdf
- [SS] DL32R spec sheet (Mackie, (c) 2015): https://mackie.com/img/file_resources/DL32R_SS.pdf
- [RG] Master Fader Reference Guide V5.1 (Mackie, Feb 2026; covers DL32R, DL32S, DL16S). Mackie's own PDF, from Mackie's Master Fader Downloads page: https://help.mackie.com/hc/en-us/articles/14288356150159-Master-Fader-Downloads (its "Click here" opens Mackie's Brandfolder, file "Master Fader V5 1 RG"; the PDF itself is a signed storage URL, so we cite the page). Read on 2026-11-07 (Claude in Chrome); local text checked page by page. Page numbers below are the guide's own (they match the PDF page numbers) and were rechecked against V5.1.
- [RG5.0] Master Fader Reference Guide V5.0 (Mackie / LOUD, (c) 2018): the older edition, read first from the copy hosted by Mackie's Australian distributor Ambertech: https://www.ambertech.com.au/Documents/Master%20Fader_V5_0_RG-compressed.pdf . Secondary only; every [RG] point below is in V5.1.
- Dropped: Mackie's DL32R FAQ page (mackie.com/en/support/faq/dl32r.html). It showed an error page to scripts on 2026-11-06 and in a real browser on 2026-11-07, so it is no longer cited. Its meter wording is replaced by [RG p.38].
- [DL32S-SS] DL16S/DL32S spec sheet with block diagram (Mackie), used only as a comparison: https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf

## 1. USB audio to a computer

- USB-B ("USB B - Computer"): "32x32 channels of recording and playback to a connected computer over USB 2.0 by presenting the DL32R as an audio class 2.0 compliant device" [OM p.11].
- Spec: "USB - Streaming: USB 2.0 High Speed (as a device), USB-B ... 32 in / 32 out, 48 kHz, 16/24-bit" [OM spec; SS].
- Sample rate fixed 48 kHz; A/D/A 24-bit [OM spec].
- No channel-count or mode option is documented for USB-B [OM; RG].

## 2. Driverless status

- macOS: "connecting it to a Mac should work automatically with no additional drivers"; spec "Supported Mac OS [Audio Class 2.0 Compliant, no driver required]: OS X 10.8.4, 10.9, 10.10, 10.11" (2015 list; newer macOS not listed) [OM]. [RG p.210] repeats "A Mac should work automatically with no additional drivers."
- Windows: "Driver installation required" (Windows 7, 8, 10) [OM spec].
- iPad: "Additionally, you may stream audio directly to and from an iPad using the iPad camera connection kit." [OM p.11]. iPhone: not named by Mackie (unknown).
- No USB mode switch is documented [OM; RG].

## 3. Onboard recording without a computer (USB drive on USB-A)

- Track count: **1 to 32 tracks, chosen per recording.** [RG p.217]: "Using the pulldown menu, select how many tracks to record, 1-32." [RG p.210] (2026) and [OM p.11] text: "32 channel (48 kHz, 24-bit) recording and playback to (and from) a USB hard drive." [SS] feature list: "32x32 recording/playback direct to USB 2.0 hard drive".
  - The 2015 spec table in [OM] and [SS] says "1-24 channel, 48 kHz, 16/24-bit (multichannel .wav)". That table is older than [RG5.0] (2018) and [RG] V5.1 (2026), which both document 1-32. The release notes in [RG p.320] (Master Fader Version 3.2) say "The DL32R can now record and playback 32x32 channels to and from the external hard drive", and that the mixer firmware can't go back to V3.1 after the V3.2 update. Publish "up to 32 tracks (Mackie Master Fader guide); update the mixer and app first".
- Bit depth: 16 or 24 bits, chosen per recording [RG p.217]. Sample rate: 48 kHz [RG p.219; OM spec].
- File format: **one multichannel (interleaved) .wav per take**, holding 1 to 32 channels [RG p.221]: "The DL32R records to multichannel .wav files that contain between one and 32 channels (or tracks) in a single file." Most DAWs split it on import; Mackie suggests Sound Devices Wave Agent otherwise [RG p.221].
- File splitting: files are kept under 2 GB. The DL32R starts a new file "without any data loss" ("gapless recording"), so a long show is several .wav files per take; line them up end to end in the DAW [RG p.222]. Mackie's example: a 50-minute 24-channel recording gives 5 files.
- Folders: the drive holds "Music" (stereo playback files) and "Recordings" (one subfolder per take) [RG p.213, p.221].
- Drive type: [RG p.211, p.224] says use a "USB 2.0 or better spinning hard disk drive", "Do not use a thumb drive!" for recording (thumb drives are OK for stereo playback), dedicate the drive to the DL32R, format it in the DL32R (Format button in the Recording/Playback view), and do not use a USB hub. Bus-powered drives are OK "from 5V up to 1A". [OM spec]: "USB 2.0 / 3.0 Class Compliant HDD", "HDD Format: FAT32", "Bus Power: 5V, 1A max".
- Free space: recording cannot start, and stops, below 100 MB free [RG p.219, p.224].
- Drive size limit: not stated (unknown).

## 4. Recording settings

- USB-B (computer): 48 kHz only; 16 or 24-bit [OM spec]. Which word length is used is set by the computer's recording app (inference; Mackie does not say).
- Drive: Master Fader > Recording/Playback button (upper right of the navigation bar) > name the recording > track count 1-32 > 16 or 24 bits > Record [RG p.210, p.217-218]. Name, track count and bit depth can't be changed while recording [RG p.218]. Recording continues in the background if the iPad leaves the app [RG p.219].
- Clock: no word clock documented (unknown). Dante expansion card optional [SS]. The spec sheet has no clock line; the manual's LED appendix shows the DL32R can follow a Dante clock master with the card [OM].
- Drive and computer cannot run together: "USB A and USB B connectors may NOT be used simultaneously. If a hard drive is connected to USB A, it will take priority over anything connected to USB B ... the DAW recording interrupted" [OM p.11; RG p.210]; "Streaming and HDD Record / Playback are not available simultaneously." [OM spec footnote].

## 5. Routing (per-slot patching)

- Per slot, any source: "Any combination of channels or outputs may be selected as the record source and playback destination." (said for both USB A drive and USB B computer) [OM p.11; RG p.210].
- Where: Master Fader > I/O Patch button (upper right of the navigation bar) > **USB** tab. Rows are sources, columns are destinations; tap the crosshair to patch [RG p.196-199]. The DL32R I/O Patch has eight tabs: Mic Pre, Oscillator, Input A, Input B, USB, Output, Dante, Talkback [RG p.196-199]. The same USB tab feeds both the drive and the computer [RG p.210].
- Default: "mic pres 1-16/32 [source] are routed to USB 1-16/32 [destination]" [RG p.203].
- Sources on the USB tab [RG p.207, "I/O Patch at a Glance"]: Oscillator; Mic Pre 1-32; USB 1-32; Dante 1-32; Channel 1-32 Post-DSP; Return 1-4 Post-DSP; FX L/R Post-DSP; Main L/R Pre-Fader; Main L/R; Subgroups 1-6; Aux 1-14; FX Send 1-3; Matrix 1-6; Monitor L/R.
- Recording the main mix alongside inputs: Mackie's example patches Mic Pre 1-12 to USB 1-12, Main L/R to USB 13-14 and Aux 1-2 to USB 15-16 [RG p.203]. With 32 inputs in use there are no spare slots, so a stereo mix costs two input tracks.
- Reset: the tools button (upper left of I/O Patch) offers "Reset to Default" or "Clear" for the open tab. Patching is stored in snapshots [RG p.198, p.200].
- Playback / virtual soundcheck: each channel has Input A (default: mic pres) and Input B (default: USB returns) [RG p.199]. Switch channels to Input B to hear drive or computer playback. The Recording/Playback view has shortcuts "Channel A / B" (all channels) and "A Tracks / B Tracks" (only as many channels as the loaded file has tracks) [RG p.220, p.224]. Drive playback needs 48 kHz .wav; 44.1 kHz, AAC, MP3 and AIFF won't play [RG p.213]. Mackie notes multichannel files made in some DAWs "will only play back properly with 27 or fewer tracks" [RG p.223].

## 6. Tap points

From the maker block diagram [RG p.290-291, "DL32R Block Diagram"]:
- Input: phantom, preamp "Gain: 0 ~ +60dB (3dB steps)", ADC, then "To Routing Matrix". This is the **Mic Pre** source: after analog gain, before everything digital. Line inputs 25-32 add a -20 dB pad on TRS.
- Channel strip order: A/B source select > meter > **Digital Trim** > polarity > **High Pass** > Gate > Comp > 4-band PEQ > **Ch Direct Out to Routing Matrix** > mute > fader.
- So there are two per-channel record taps, chosen per USB slot:
  - **Mic Pre** (default): before digital trim, polarity, HPF, gate, comp, EQ, mute and fader.
  - **Channel N Post-DSP** (the "Ch Direct Out" on the diagram): after HPF, gate, comp and EQ, before mute and fader.
- Mackie describes both: "recording each input directly off the mic pre with no processing" (default) and routing "each of the post-DSP inputs to each of the USB outputs" for processed tracks [RG p.203-204].
- Main L/R is offered both pre-fader and post-fader [RG p.207].
- Gain spec [OM spec; SS]: XLR 0 to 60 dB, 1/4" -20 to 40 dB, both "digitally controlled analog" in 3 dB steps. Digital trim is a separate per-channel control after the routing matrix, so it does not reach the Mic Pre tap (per diagram).
- Meters: "The input meters display the input signal level to the channel before all channel processing. Changes made to the EQ, mute and fader do not affect these meters." [RG p.38]. The block diagram shows the channel meter right after A/B select, before digital trim [RG p.290-291]. (The output-meter point came only from the dropped FAQ page; not used.)
- Several iPads on one DL32R: up to 20 iOS devices [SS]. Access Limiting > Mic Preamps locks "48v, gain, trim and polarity" on a device [RG p.191, Access Limits]. Preamp gain is one physical setting per input, so a gain change from any device with access changes the Mic Pre record feed (inference from the diagram; Mackie does not state it). Lock Mic Preamps on every device except the one that owns gain.

## 7. Gotchas

- USB drive and computer streaming are mutually exclusive; plugging a drive into USB-A interrupts a running computer recording, and the DL32R won't reappear on the computer until USB-B is unplugged and replugged [OM p.11; RG p.210].
- Drive recording wants a spinning hard drive formatted in the DL32R, not a thumb drive, with no hub [RG p.211, p.224].
- Drive takes are one interleaved .wav per under-2 GB chunk, not one file per track [RG p.221-222].
- Drive track count: 2015 spec table says 1-24; the 2018 and 2026 guides and the manual text say 32; 32 came with Master Fader and mixer firmware V3.2 [OM; SS; RG p.210, p.320].
- 48 kHz only [OM spec].
- Windows needs the Mackie driver [OM spec].
- iPad needs the camera connection kit [OM]. Lightning vs USB-C not discussed (2015 manual).
- Mac OS support list in the 2015 spec stops at 10.11 (class compliant, so newer macOS is expected to work; not confirmed by Mackie).

## 8. Confidence

| Fact | Confidence |
|---|---|
| 32x32 USB-B, 48 kHz, 16/24-bit, UAC2 class compliant, Mac no driver, Windows driver | maker (OM, SS) |
| iPad USB audio via camera connection kit | maker (OM) |
| iPhone USB audio | unknown |
| Drive: 1-32 tracks, 16/24-bit, 48 kHz, one multichannel .wav per take, split under 2 GB | maker (RG V5.1, Mackie-hosted) |
| Drive: spinning HDD, no thumb drive, no hub, format in DL32R | maker (RG) |
| Drive: FAT32, class compliant HDD, 5 V 1 A bus power | maker (OM spec) |
| Drive and computer not simultaneous | maker (OM, RG) |
| Any source to any record slot; I/O Patch > USB tab; default Mic Pre N to USB N; source list | maker (RG) |
| Mic Pre tap pre-trim/HPF; Channel Post-DSP = post-EQ, pre-mute/fader | maker (RG block diagram p.290-291) |
| Gain 0-60 dB (XLR) in 3 dB steps | maker (OM spec, SS) |
| Access Limiting can lock mic preamp gain | maker (RG) |
| Gain from a second iPad changes the recording | inference from signal flow (not maker-stated) |

## 9. Sources

- https://mackie.com/img/file_resources/DL32R_OM.pdf
- https://mackie.com/img/file_resources/DL32R_SS.pdf
- https://help.mackie.com/hc/en-us/articles/14288356150159-Master-Fader-Downloads (Mackie Master Fader Reference Guide V5.1, Feb 2026, Mackie-hosted; main citation)
- https://www.ambertech.com.au/Documents/Master%20Fader_V5_0_RG-compressed.pdf (Mackie Master Fader Reference Guide V5.0, 2018, distributor-hosted; secondary)
- https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf (comparison only)

## Gaps

- iPhone: not named by Mackie. Say "not tested yet".
- iPad with USB-C: not discussed (2015 manual names the camera connection kit only). Say "camera adapter" without naming a model.
- macOS newer than 10.11: not listed by Mackie. Say "class compliant; current macOS not listed by Mackie".
- Drive track count: 32 in the 2018 and 2026 guides, 24 in the 2015 spec table. Say "up to 32 with current firmware and app" and add "older units may show 24 until updated" (inference).
- Firmware version that raised the drive to 32 tracks: V3.2 of Master Fader and the mixer firmware [RG p.320].
- Drive size limit and the file system the DL32R's own Format button writes: unknown (spec says FAT32). Leave out sizes.
- Word clock / external sync: not documented. Leave out.
- Which bit depth the computer stream uses: set by the recording app (inference). Say "the app chooses 16 or 24-bit".
- Main source document [RG] is Mackie's own V5.1 PDF, reached from help.mackie.com (2026-11-07). Cite it as "Mackie Master Fader Reference Guide V5.1"; the Ambertech V5.0 copy may stay as a secondary link.
- Gain change from a second device reaching the recording: our inference. Label it as advice, not a Mackie statement.
