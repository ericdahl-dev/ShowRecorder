# Mackie DL32R

Source key used below:
- [OM] DL32R Owner's Manual (Mackie / LOUD Technologies, (c) 2015): https://mackie.com/img/file_resources/DL32R_OM.pdf
- [SS] DL32R spec sheet (Mackie, (c) 2015): https://mackie.com/img/file_resources/DL32R_SS.pdf
- [FAQ] Mackie DL32R FAQ: https://mackie.com/en/support/faq/dl32r.html . Returned HTTP 404 to direct fetches on 2026-11-06 (mackie.com serves an error page to scripts); wording below comes from search-engine excerpts of that page, so it is maker text we could not re-verify.
- [DL32S-SS] DL16S/DL32S spec sheet with block diagram (Mackie), used only as a comparison: https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf

## 1. USB audio to a computer

- USB-B ("USB B - Computer"): "32x32 channels of recording and playback to a connected computer over USB 2.0 by presenting the DL32R as an audio class 2.0 compliant device" [OM p.11].
- Spec: "USB - Streaming: USB 2.0 High Speed (as a device), USB-B ... 32 in / 32 out, 48 kHz, 16/24-bit" [OM spec; SS].
- Sample rate fixed 48 kHz; A/D/A 24-bit [OM spec].

## 2. Driverless status

- macOS: "connecting it to a Mac should work automatically with no additional drivers"; spec "Supported Mac OS [Audio Class 2.0 Compliant, no driver required]: OS X 10.8.4, 10.9, 10.10, 10.11" (2015 list; newer macOS not listed) [OM].
- Windows: "Driver installation required" (Windows 7, 8, 10) [OM spec].
- iPad: "Additionally, you may stream audio directly to and from an iPad using the iPad camera connection kit." [OM p.11]. iPhone not mentioned (unknown; same class-compliant device, so likely).
- No USB mode switch.

## 3. Onboard recording without a computer (USB drive on USB-A)

- Owner's manual text: "The DL32R's USB type A connector allows 32 channel (48 kHz, 24-bit) recording and playback to (and from) a USB hard drive." [OM p.11]
- Owner's manual and spec sheet spec table: "USB - HDD Recording / Playback ... USB 2.0 High Speed (as a host), USB-A ... 1-24 channel, 48 kHz, 16/24-bit (multichannel .wav) ... Supported Devices: USB 2.0 / 3.0 Class Compliant HDD ... HDD Format: FAT32 ... Bus Power: 5V, 1A max" [OM spec; SS].
- The two numbers conflict inside the same manual. A launch-era press summary said drive recording would be 24 channels at launch, rising to 32 later (secondary, via search excerpt; not verified). Publish as "24 channels per the spec table, 32 per the manual text and later firmware (unconfirmed)".
- Format: multichannel .wav [OM spec]. Whether that is one interleaved file or one file per channel: "multichannel .wav" suggests interleaved; unknown.
- Drive must be FAT32 [OM spec]. FAT32 caps a single file at 4 GB; how the DL32R handles that (file splitting): unknown.
- Drive size limit: unknown. Bus power 5 V 1 A max, so many portable hard drives may need their own power (inference from spec).

## 4. Recording settings

- 48 kHz only; 16 or 24-bit [OM spec]. Where 16 vs 24-bit is chosen for the drive: unknown (Master Fader app; menu not documented in sources we read).
- Clock: internal; Dante expansion card optional [SS]. No word clock documented (unknown).
- Drive and computer cannot run together: "USB A and USB B connectors may NOT be used simultaneously. If a hard drive is connected to USB A, it will take priority over anything connected to USB B ... the DAW recording interrupted" [OM p.11]; "Streaming and HDD Record / Playback are not available simultaneously." [OM spec footnote].

## 5. Routing (per-slot patching)

- Per slot, any source: "Any combination of channels or outputs may be selected as the record source and playback destination." (said for both USB A drive and USB B computer) [OM p.11].
- Where: Master Fader app > I/O Patch view, tabs Input A, Input B, Output, USB, Dante, Talkback. "USB: This tab is where the signal sources for USB inputs are selected. By default Mic Pre 1 will feed USB 1 and Mic Pre 2 will feed USB 2 etc. This section allows users a large amount of flexibility in what can be routed to the USB inputs." To record, pick the USB sources in the USB tab and press Record [FAQ].
- Default: Mic Pre N to USB N [FAQ].
- Exact list of sources on the USB tab (direct outs, buses, main LR): unknown for the DL32R. On the DL32S block diagram the routing matrix carries mic pres, channel direct outs and FX direct outs [DL32S-SS]; the DL32R uses the same Master Fader engine, but we have no DL32R diagram.
- Recording the main mix alongside inputs: "Any combination of channels or outputs" implies outputs (mixes) can be record sources [OM]. With 32 inputs in use there are no spare slots on a 32-track path; with the drive at 24 channels (spec) even fewer.
- Playback / virtual soundcheck: channels have Input A and Input B sources [FAQ tabs; SS "Full I/O routing with A/B sources per channel"]; set them to the USB/drive returns. SS: "Multi-track recording & playback ... 32x32 recording/playback direct to USB 2.0".

## 6. Tap points

- Default USB source is "Mic Pre N" [FAQ]: the preamp output, before channel processing. On the related DL32S the mic pre feeds the routing matrix right after the ADC, before digital trim, HPF, gate, comp, EQ; a "Ch Direct Out" (post-EQ, pre-fader) is also offered [DL32S-SS]. DL32R-specific diagram: not found, so the Ch Direct Out option on the DL32R is unknown.
- Meters: "Input meters are fixed Pre DSP. Output meters are fixed Post Fader." [FAQ]
- Two (or more) iPads on one DL32R: the mixer supports many iOS devices ("Supports up to 20 separate iOS devices at once") and "Access Limiting allows flexible customization of user interface and prevents unwanted adjustments from other users" [SS]. Preamp gain is one physical setting per input, so a gain change from any iPad with access changes the Mic Pre record feed (inference; Mackie does not state it). Use Access Limiting to lock preamp gain on the monitor engineer's device.
- Gain range and steps: not given in [SS]; DL32S uses 0 to +60 dB in 6 dB steps with 1 dB digital interpolation [DL32S-SS] (DL32R unknown).

## 7. Gotchas

- USB drive and computer streaming are mutually exclusive; plugging a drive into USB-A kills a running computer recording [OM].
- Drive must be FAT32, USB 2.0/3.0 class-compliant, bus power 5 V 1 A max [OM spec].
- Drive channel count conflict: 24 (spec table) vs 32 (manual text) [OM].
- 48 kHz only [OM spec].
- Windows needs the Mackie driver [OM spec].
- iPad needs the camera connection kit [OM]. Lightning vs USB-C not discussed (2015 manual).
- Mac OS support list in the 2015 spec stops at 10.11 (class compliant, so newer macOS is expected to work; unconfirmed).

## 8. Confidence

| Fact | Confidence |
|---|---|
| 32x32 USB-B, 48 kHz, 16/24-bit, UAC2 class compliant, Mac no driver, Windows driver | confirmed by maker |
| iPad USB audio via camera connection kit | confirmed by maker |
| USB-A drive: FAT32, class compliant HDD, multichannel WAV, 48 kHz 16/24-bit | confirmed by maker |
| Drive channel count 24 vs 32 | confirmed by maker but contradictory; current value unknown |
| Drive and computer not simultaneous | confirmed by maker |
| Any source to any record slot | confirmed by maker (OM) |
| I/O Patch > USB tab, default Mic Pre N | maker FAQ, via search excerpt only |
| Ch Direct Out tap on DL32R | unknown (shown on DL32S diagram only) |
| Gain from second iPad affects recording | secondary (inference) |

## 9. Sources

- https://mackie.com/img/file_resources/DL32R_OM.pdf
- https://mackie.com/img/file_resources/DL32R_SS.pdf
- https://mackie.com/en/support/faq/dl32r.html (search excerpts; 404 to direct fetch)
- https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf (comparison only)
