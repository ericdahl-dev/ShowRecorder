# Mackie DL32S (and DL16S, DL32SE/DL16SE)

Source key used below:
- [OM] DL16S / DL32S Owner's Manual (Mackie / LOUD Audio, (c) 2018): https://mackie.com/img/file_resources/DL16S_DL32S_OM.pdf
- [SS] DL16S / DL32S spec sheet incl. block diagram on page 8 (Mackie): https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf
- [SE-OM] DL16SE / DL32SE Owner's Manual (Mackie): https://mackie.com/img/file_resources/DL16SE_DL32SE_OM.pdf
- [SE-SS] DL16SE / DL32SE spec sheet incl. block diagram on page 13 (Mackie): https://mackie.com/img/file_resources/DL16SE_DL32SE_SS[99].pdf
- [FAQ] Mackie DL32R FAQ page (same Master Fader app and I/O Patch view): https://mackie.com/en/support/faq/dl32r.html . Note: this page returned HTTP 404 to direct fetches on 2026-11-06 (mackie.com serves an error page to scripts); its wording below comes from search-engine excerpts of the page, so treat it as maker text not re-verified by us.

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
- iOS/iPadOS USB audio: not stated for DL32S/DL32SE (unknown). The older DL32R manual explicitly says audio can stream to/from an iPad via the camera connection kit (see mackie-dl32r.md); since the DL32S/SE are also UAC2 class compliant, iOS should work, but no Mackie source says so for these models. iOS mentions in [SS] refer to the Master Fader control app (iOS 11 or later).
- No USB mode switch or channel-count option documented.

## 3. Onboard recording without a computer

None. Recording requires a USB host (computer, or iPad/iPhone if it works). [OM ch.4: "recording and playback is possible when a computer is connected ... via the USB type B connector"].

## 4. Recording settings

- 48 kHz only; USB word length 16/24-bit (host decides) [OM spec].
- Clock: internal (no external sync documented; unknown).
- File format: decided by the recording app.

## 5. Routing (per-slot patching)

- **Per slot, any source.** "Any combination of channels or outputs may be selected as the record source and playback destination." [OM "USB Interface", OM ch.4; SE-OM].
- Where: Master Fader app, I/O Patch view, USB tab. [FAQ, DL32R wording]: the I/O Patch view has tabs Input A, Input B, Output, USB, Dante, Talkback; "USB: This tab is where the signal sources for USB inputs are selected. By default Mic Pre 1 will feed USB 1 and Mic Pre 2 will feed USB 2 etc. This section allows users a large amount of flexibility in what can be routed to the USB inputs." Whether the DL32S app shows the same tabs (it has no Dante card slot in the same way): unknown; assume USB tab exists.
- Sources available on the routing matrix [SS block diagram p.8]: each mic preamp ("To Routing Matrix", directly after the ADC), each channel's "Ch Direct Out to Routing Matrix", FX direct outs (pre-DSP and post-fader), plus the buses (Main LR, groups, auxes, matrix) feeding outputs. Exact list of bus sources offered on the USB tab: unknown (not in the docs we could read).
- Default: Mic Pre N to USB N [FAQ].
- Playback in (virtual soundcheck): each channel has A and B sources from the routing matrix [SS block diagram: "From Routing Matrix A / B"; spec "Full I/O routing with A/B sources per channel"]. Set the channel's source to the USB return (Input A/B tabs) to play tracks back through the channels. Spec sheet: "Perform a virtual sound check" [SS]. Playback from music apps on a computer arrives on the return channels [OM ch.4].
- When to use which: keep Mic Pre for raw multitrack (default); use Ch Direct Out for processed stems; route Main LR or an aux to spare USB slots if the app shows those sources (DL32S has only 32 USB sends, so a stereo mix costs two input tracks).

## 6. Tap points

From the maker block diagram [SS p.8; same structure on SE-SS p.13]:
- Input: phantom, preamp "Gain: 0 ~ +60dB (6dB steps w/ 1dB digital interpolation)", ADC, then "To Routing Matrix". This is the **Mic Pre** source: post analog gain, before everything digital.
- Channel strip order: A/B source select > meter > **Digital Trim** > polarity > Pre-DSP insert > **High Pass** > Gate > Comp > 4-band PEQ > Post-DSP insert > **Ch Direct Out to Routing Matrix** > mute > fader.
- So the two channel taps are: Mic Pre (pre-trim, pre-HPF, pre-everything) and Ch Direct Out (post-HPF/gate/comp/EQ, pre-mute, pre-fader). Per-slot choice, since each USB slot picks its own source.
- Digital Trim is a channel-strip control after the routing matrix; it does not affect the Mic Pre tap (per diagram). Analog gain does.
- Meters: [FAQ] "Input meters are fixed Pre DSP. Output meters are fixed Post Fader."
- Several devices controlling one mixer: the Master Fader app supports multiple controllers; "Access Limiting" exists on the DL series to stop other users changing things [DL32R SS wording; see mackie-dl32r.md]. A gain change made from any device with access changes the Mic Pre tap and so the recording (inference from the diagram, not a Mackie statement).

## 7. Gotchas

- 48 kHz only [SS].
- Windows needs the Mackie driver [OM].
- iOS USB audio not documented for DL32S/SE (unknown); camera adapter needed if it works; the DL32S is mains powered so it does not draw power from the phone (charging unknown).
- Default record feed is Mic Pre: HPF and digital trim are not in it [SS diagram]; use Ch Direct Out if processed stems are wanted.
- Preamp gain moves in 6 dB analog steps with 1 dB digital interpolation [SS].

## 8. Confidence

| Fact | Confidence |
|---|---|
| 32x32 (DL32S/SE), 16x16 (DL16S/SE), 48 kHz, 16/24-bit, USB-B | confirmed by maker |
| macOS class compliant UAC2, no driver; Windows driver | confirmed by maker |
| iOS USB audio for DL32S/SE | unknown |
| No onboard recorder | confirmed by maker |
| Any source to any USB slot | confirmed by maker (OM) |
| I/O Patch > USB tab, default Mic Pre N to USB N | maker FAQ (DL32R), not re-fetched; DL32S app layout unknown |
| Mic Pre tap pre-trim/HPF; Ch Direct Out post-EQ pre-fader | confirmed by maker (block diagram) |
| Gain change from another device affects recording | secondary (inference) |

## 9. Sources

- https://mackie.com/img/file_resources/DL16S_DL32S_OM.pdf
- https://mackie.com/img/file_resources/DL16S_DL32S_SS.pdf
- https://mackie.com/img/file_resources/DL16SE_DL32SE_OM.pdf
- https://mackie.com/img/file_resources/DL16SE_DL32SE_SS[99].pdf
- https://mackie.com/en/support/faq/dl32r.html (via search excerpts; 404 to direct fetch)
