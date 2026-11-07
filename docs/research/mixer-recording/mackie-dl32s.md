# Mackie DL32S (and DL16S, DL32SE/DL16SE)

Source key used below:
- [OM] DL16S / DL32S Owner's Manual (Mackie / LOUD Audio, (c) 2018): https://mackie.com/img/file_resources/DL16S_DL32S_OM.pdf
- [SS] DL16S / DL32S spec sheet incl. block diagram on page 8 (Mackie): https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf
- [SE-OM] DL16SE / DL32SE Owner's Manual (Mackie): https://mackie.com/img/file_resources/DL16SE_DL32SE_OM.pdf
- [SE-SS] DL16SE / DL32SE spec sheet incl. block diagram on page 13 (Mackie): https://mackie.com/img/file_resources/DL16SE_DL32SE_SS[99].pdf
- [RG] Master Fader Reference Guide V5.0 (Mackie / LOUD, (c) 2018; covers DL16S, DL32S, DL32R; not the SE models). Mackie's own PDF, read from the copy hosted by Mackie's Australian distributor Ambertech, because we could not find it on mackie.com: https://www.ambertech.com.au/Documents/Master%20Fader_V5_0_RG-compressed.pdf . Page numbers are the guide's own.
- [FAQ] Mackie DL32R FAQ page: https://mackie.com/en/support/faq/dl32r.html . Returned HTTP 404 to direct fetches on 2026-11-06; known only from search-engine excerpts. Superseded here by [RG].

Note: mackie.com product pages render via JavaScript and returned an error page to scripts; the PDFs above download fine.

## 1. USB audio to a computer

- DL32S: 32 in / 32 out, 48 kHz, 16/24-bit; USB 2.0 High Speed (as a device), USB-B [OM spec; SS].
- DL16S: 16 in / 16 out, same format [OM spec; SS].
- DL32SE / DL16SE: 32x32 / 16x16, 48 kHz, 16/24-bit, USB-B [SE-OM spec].
- Sample rate is fixed 48 kHz ("Sample Rate: 48 kHz") [SS; SE-OM].
- No USB drive / SD recorder on DL32S or DL32SE (only the USB-B device port is documented) [OM; SE-OM].

## 2. Driverless status

- macOS: "presenting the DL mixer as an audio class 2.0 compliant device ... connecting it to a Mac should work automatically with no additional drivers" [OM "USB Interface"; SE-OM]. Spec: "Supported Mac OS [Audio Class 2.0 Compliant, no driver required]: macOS 10.13, 10.14" (DL32S) [OM]; "macOS 10.15 or higher required" (DL32SE) [SE-OM].
- Windows: "Driver installation required" (Windows 10; Windows 10 or 11 for SE) [OM; SE-OM]. "PC users: install the latest driver from the Mackie website" [OM ch.4].
- iOS/iPadOS USB audio: not stated for DL32S/DL32SE (unknown). The older DL32R manual says audio can stream to/from an iPad via the camera connection kit (see mackie-dl32r.md). The DL32S/SE are also UAC2 class compliant, so iOS may work, but no Mackie source says so for these models. iOS mentions in [SS] and [OM] refer to the Master Fader control app (iOS 11 or later). [RG p.210] says recording on DL16S/DL32S "occurs outside of Master Fader".
- No USB mode switch or channel-count option documented [OM; RG].

## 3. Onboard recording without a computer

None. Recording requires a USB host. [OM ch.4: "recording and playback is possible when a computer is connected ... via the USB type B connector"].

## 4. Recording settings

- 48 kHz only; USB word length 16/24-bit [OM spec]. Which word length is used is set by the recording app (inference; Mackie does not say).
- Clock: internal; no external sync documented (unknown).
- File format: decided by the recording app.
- Computer setup: [OM ch.4] gives a numbered primer (connect USB, then pick the DL16S/DL32S as input and output device in the computer's sound settings and in the DAW).

## 5. Routing (per-slot patching)

- **Per slot, any source.** "Any combination of channels or outputs may be selected as the record source and playback destination." [OM "USB Interface", OM ch.4; SE-OM].
- Where (DL16S/DL32S): Master Fader > I/O Patch button (upper right of the navigation bar) > **USB** tab [RG p.196-199]. Rows are sources, columns are destinations; tap the crosshair to patch. The DL16S and DL32S I/O Patch has seven tabs: Mic Pre, Oscillator, Input A, Input B, USB, Output, Talkback (no Dante tab; the DL32R has eight) [RG p.196-199]. USB destinations: USB 1-16 (DL16S) or USB 1-32 (DL32S) [RG p.197].
- DL32SE / DL16SE: the menu path is not in [RG] (it predates them) and was not found in [SE-OM]. Unknown; do not assume it matches.
- Default: "mic pres 1-16/32 [source] are routed to USB 1-16/32 [destination]" [RG p.203].
- Sources on the USB tab [RG p.207, "I/O Patch at a Glance"]: Oscillator; Mic Pre; USB; Channel 1-32 Post-DSP; Return Post-DSP; FX L/R Post-DSP; Main L/R Pre-Fader; Main L/R; Subgroups 1-6; Aux 1-14; FX Send 1-3; Matrix 1-6; Monitor L/R. The table is shared with the DL32R (it also lists Dante, which needs the DL32R's card). Exact counts on the DL16S/DL32S (for example how many auxes) are not broken out in the table; check them in the app.
- Recording a mix alongside inputs: Mackie's example patches Mic Pre 1-12 to USB 1-12, Main L/R to USB 13-14 and Aux 1-2 to USB 15-16 [RG p.203]. On the DL32S, a stereo mix costs two of the 32 USB sends.
- Reset: the tools button (upper left of I/O Patch) offers "Reset to Default" or "Clear" for the open tab. Patching is stored in snapshots [RG p.198, p.200].
- Playback in (virtual soundcheck): each channel has Input A (default: mic pres) and Input B (default: USB returns) [RG p.199]. "The most common use for this is for virtual sound check, switching between the mic pres and USB returns" [RG p.199]. [SS] block diagram: "From Routing Matrix A / B"; spec "Perform a virtual sound check" [SS].
- When to use which: keep Mic Pre for raw multitrack (default); use Channel Post-DSP for processed stems; patch Main L/R or an aux to spare USB slots for a reference mix.

## 6. Tap points

From the maker block diagram [SS p.8; same structure on SE-SS p.13; RG p.282]:
- Input: phantom, preamp "Gain: 0 ~ +60dB (6dB steps w/ 1dB digital interpolation)", ADC, then "To Routing Matrix". This is the **Mic Pre** source: after analog gain, before everything digital.
- Channel strip order: A/B source select > meter > **Digital Trim** > polarity > Pre-DSP insert > **High Pass** > Gate > Comp > 4-band PEQ > Post-DSP insert > **Ch Direct Out to Routing Matrix** > mute > fader.
- So the two per-channel taps, chosen per USB slot:
  - **Mic Pre** (default): before digital trim, polarity, HPF, gate, comp, EQ, mute and fader.
  - **Channel N Post-DSP** (the "Ch Direct Out" on the diagram; "Channel 1-32, Post-DSP" in the I/O Patch table [RG p.207]): after HPF, gate, comp and EQ, before mute and fader.
- Main L/R is offered both pre-fader and post-fader [RG p.207].
- Digital Trim is a channel-strip control after the routing matrix; it does not affect the Mic Pre tap (per diagram). Analog gain does.
- Meters: the block diagram shows the channel meter right after A/B select, before digital trim [SS p.8].
- Several devices controlling one mixer: Access Limiting > Mic Preamps locks "48v, gain, trim and polarity" on a device [RG, Access Limits section]. A gain change made from any device with access changes the Mic Pre tap and so the recording (inference from the diagram, not a Mackie statement).

## 7. Gotchas

- 48 kHz only [SS].
- Windows needs the Mackie driver [OM].
- iOS USB audio not documented for DL32S/SE (unknown). If it works, a camera adapter is needed (inference from the DL32R manual). The DL32S is mains powered, so it does not draw power from the phone; whether it charges the phone is unknown.
- Default record feed is Mic Pre: HPF and digital trim are not in it [SS diagram]; use Channel Post-DSP if processed stems are wanted.
- Preamp gain moves in 6 dB analog steps with 1 dB digital interpolation [SS].
- Mac support list: macOS 10.13 and 10.14 for DL32S [OM]; newer macOS not listed (class compliant, so expected to work; not confirmed by Mackie).

## 8. Confidence

| Fact | Confidence |
|---|---|
| 32x32 (DL32S/SE), 16x16 (DL16S/SE), 48 kHz, 16/24-bit, USB-B | maker (OM, SS, SE-OM) |
| macOS class compliant UAC2, no driver; Windows driver | maker (OM, SE-OM) |
| iOS USB audio for DL32S/SE | unknown |
| No onboard recorder | maker (OM, SE-OM) |
| Any source to any USB slot | maker (OM) |
| DL16S/DL32S: I/O Patch > USB tab, default Mic Pre N to USB N, source list | maker (RG, distributor-hosted copy) |
| DL16SE/DL32SE menu path | unknown |
| Mic Pre tap pre-trim/HPF; Channel Post-DSP post-EQ pre-fader | maker (block diagram) |
| Access Limiting can lock mic preamp gain | maker (RG) |
| Gain change from another device changes the recording | inference from signal flow (not maker-stated) |

## 9. Sources

- https://mackie.com/img/file_resources/DL16S_DL32S_OM.pdf
- https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf
- https://mackie.com/img/file_resources/DL16SE_DL32SE_OM.pdf
- https://mackie.com/img/file_resources/DL16SE_DL32SE_SS[99].pdf
- https://www.ambertech.com.au/Documents/Master%20Fader_V5_0_RG-compressed.pdf (Mackie Master Fader Reference Guide V5.0, distributor-hosted)
- https://mackie.com/en/support/faq/dl32r.html (via search excerpts; 404 to direct fetch)

## Gaps

- iPhone and iPad: not named by Mackie for DL32S, DL16S or the SE models. Say "not tested yet".
- DL32SE / DL16SE menu path for USB patching: not found. Don't reuse the DL32S path for SE guides without checking.
- Exact bus counts offered on the DL32S USB tab: the maker table is shared with the DL32R. Say "auxes, subgroups, matrix and Main L/R" without numbers.
- Which bit depth the stream uses: set by the recording app (inference). Say "the app chooses 16 or 24-bit".
- Clock / external sync: not documented. Leave out.
- macOS newer than 10.14 for DL32S: not listed by Mackie. Say "class compliant; current macOS not listed by Mackie".
- Phone charging from the mixer: unknown. Tell readers to use a powered adapter or hub.
- Main source for the menu path [RG] is Mackie's PDF on a distributor's site. Cite it as "Mackie Master Fader 5 Reference Guide".
- Gain change from a second device reaching the recording: our inference. Label it as advice.
