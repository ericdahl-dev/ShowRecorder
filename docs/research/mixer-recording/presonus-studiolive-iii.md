# PreSonus StudioLive Series III (consoles 64S/32S/32SX/32SC/32/24/16, racks 32R/24R/16R)

Source key used below:
- [OM] StudioLive Series III Owner's Manual (PreSonus, (c) 2019; covers 64S, 32S, 32SX, 32SC and "Blue" 32/24/16 with firmware 2.0+). PreSonus's own download host returns 403 to scripts; this is the PreSonus PDF as hosted by dealer CCI Solutions: https://shop.ccisolutions.com/StoreFront/jsp/pdf/studioLive_seriesIII_ownersManual.pdf
- [RACK-OM] StudioLive Series III Rack Mixers Owner's Manual (PreSonus PDF, dealer-hosted): https://shop.ccisolutions.com/StoreFront/jsp/pdf/PRE-SLIII_rack_userGuide.pdf
- [CHART] PreSonus Series III mixer comparison chart (PreSonus PDF, dealer-hosted): https://shop.ccisolutions.com/StoreFront/jsp/pdf/PRE-seriesiii_mixer_comparison_chart.pdf
- [KB-IOS] PreSonus KB, Hardware iOS/iPadOS Compatibility: https://support.presonus.com/hc/en-us/articles/360059975732-PreSonus-Hardware-iOS-iPadOS-Compatibility
- [KB-64] PreSonus KB, Can my StudioLive utilize all 64 USB/AVB channels? (updated June 1, 2021): https://support.presonus.com/hc/en-us/articles/360062440371-StudioLive-Series-III-Can-my-StudioLive-utilize-all-64-USB-AVB-channels
- [KB-COMPAT] PreSonus KB, Compatibility Mode in Universal Control v4 (Dec 2022): https://support.presonus.com/hc/en-us/articles/11189120184845-Compatibility-Mode-in-Universal-Control-v4
- [KB-IFACE] PreSonus KB, Series III Interface Mode / WDM Primer (Oct 2020): https://support.presonus.com/hc/en-us/articles/360052084812-Series-III-Interface-Mode-WDM-Primer
- [KB-SD] PreSonus KB, Series III Console SD Card Recording and Playback (July 2021): https://support.presonus.com/hc/en-us/articles/4404701016973-StudioLive-Series-III-Console-SD-Card-Recording-and-Playback
- [KB-RACKSD] PreSonus KB, Rack Mount Mixers SD Card Stereo Recording and Playback: https://support.presonus.com/hc/en-us/articles/360050481392-StudioLive-Series-III-Rack-Mount-Mixers-SD-Card-Stereo-Recording-and-Playback
- [KB-AVB] PreSonus KB, Connecting the StudioLive 64S with two 32Rs using AVB (Aug 2025): https://support.presonus.com/hc/en-us/articles/360031210932-Series-III-Connecting-the-StudioLive-64S-with-two-32Rs-using-AVB

## 1. USB audio to a computer

| Model | USB I/O | SD recorder |
|---|---|---|
| 64S, 32S, 32SX, 32SC | 64x64 [CHART; KB-64] | 34 tracks [CHART "34x34"] |
| 32, 24, 16 (Series III "Blue" consoles) | 64x64 [CHART; KB-64] | 34 tracks [CHART] |
| 32R, 24R | 64x64 [CHART; KB-64]. Older rack manual says 38x38 [RACK-OM], superseded by firmware. | stereo only, 2x2 [CHART; KB-RACKSD] |
| 16R | 18x18 [CHART; RACK-OM]; raised to 24x24 by firmware 2.4 [KB-IFACE] | stereo only, 2x2 [CHART] |

- 64x64 is the routing pool, not the mixing channel count: "allows for the 32 channel StudioLives to have 64 USB/AVB Inputs (Returns) and 64 USB/AVB Outputs (Sends) to choose from"; only the 64S mixes 64 inputs [KB-64].
- Sample rate: "StudioLive Series III mixers can operate at 48 kHz or 44.1 kHz" [OM 12.1, System]. Factory default 48 kHz.
- Bit depth: A/D/A 24-bit [OM spec]. USB stream bit depth: not stated (unknown).
- Connector: "USB Recording Port: USB 2.0, Type-B" [OM spec; RACK-OM spec].

## 2. Driverless status

- iOS/iPadOS: "All PreSonus USB Audio and MIDI interfaces / controllers work class compliant." StudioLive Series III mixers (consoles and racks) are listed as externally powered devices; connect with a Lightning to USB Camera Adapter; "Note that this does not allow you to charge your iOS/iPadOS device" (use the Lightning to USB 3 Camera Adapter with power to charge) [KB-IOS].
- macOS: covered by the same KB statement ("iOS/iPadOS much like macOS also support class device connectivity") [KB-IOS]. Confirmed class compliant per maker; PreSonus still ships Universal Control for Mac for control/routing.
- Windows: uses the Universal Control driver (Compatibility Mode and WDM notes in [KB-COMPAT], [KB-IFACE]). Exact "driver required" wording not captured; treat as "PreSonus driver (Universal Control) on Windows".
- USB configuration switches:
  - **Compatibility Mode (34x34) vs Native USB Mode (64x64)**: console Home > System; Universal Control Device Settings. Requires firmware 2.7.0+ and UC 4.0.0+. Introduced for Intel/Apple Silicon USB-controller problems; "all USB Sends and USB Returns beyond the 34x34 available channels shall be grayed out" in Digital Patching [KB-COMPAT].
  - **Interface Mode** (firmware 2.4+): console Home > System, or UC Settings. Rearranges USB returns to feed mix outputs directly; not available in Stage Box or Monitor Mixer mode [KB-IFACE]. Not needed for recording inputs.
- Known iPad issue: "StudioLive Series III mixers support a 64x64 USB 2.0 configuration. This causes some DAW apps on iPadOS to crash on launch" (Auria Pro, n-Track; both later patched: Auria sees it as 24x24, n-Track handles 64 in / 48 out) [KB-IOS]. Compatibility Mode (34x34) is the maker's lower-count option and is the obvious workaround, though PreSonus does not state that for iPad (inference).

## 3. Onboard recording without a computer (SD card)

- Consoles: "34-track SD recorder" [OM 2.2.6]; "capable of recording all 32 inputs plus the main left / right mix for a total of 34 channels" [KB-SD]. Applies to 32-channel consoles; the 24 and 16 are listed 34x34 on [CHART] (track count above physical channels is not explained; unknown).
- Format: Capture session on SD; "Session files recorded on the SD Card can be opened directly in Studio One and Capture" [OM 8]. Underlying audio file format: not stated in OM (unknown; commonly WAV, unverified).
- Media: "SD and SDHC cards up to 32 GB", format FAT32 recommended, run Speed Test first [OM 8]. KB requires "SDHC - Class 10 - U3 cards" [KB-SD]. SDXC (64 GB+): PreSonus has a KB titled "Can I use an SDXC SD Card (64GB+) for recording?" (not read; answer unknown).
- Racks: SD is stereo only; choose Main L/R, a FlexMix or a subgroup pair in UC > Capture [KB-RACKSD].
- Monitoring of errors: Rec Errors box turns yellow then red; card speed drops as it fills [OM 8.3].

## 4. Recording settings

- Sample rate: Home > System > Sample Rate (48 / 44.1 kHz) [OM 12.1]; also UC Device Settings on racks [KB Studio One article].
- Clock: Home > System > Network Clock (Internal for standalone; PTP with Milan AVB firmware) [OM 12.1; KB-AVB].
- USB channel count: Native 64x64 or Compatibility 34x34 (Home > System) [KB-COMPAT].
- SD arming: Live Recording section Edit button > New Session > Capture screen > "Arm All Tracks" (all 34: "record all 32 input channels and your Main mix") or "Select Arm Tracks" then each channel's Select button [OM 8.1, 8.3; KB-SD]. On the 64S the Select buttons arm Capture tracks, not channels [OM 8.3].

## 5. Routing (per-slot patching)

- **USB: fully per slot.** Home > Audio Routing > Digital Patching > USB Sends. "Selecting the USB Sends menu will allow you to patch any channel send or mix to any USB driver send. Select the USB driver send ... Then select the channel or mix from the Available Source list" [OM 12.3, 12.3.4]. Available sources: Inputs; Aux In A L/R; Aux In B L/R; Tape In L/R; Talkback; FlexMixes; FX Send Mixes (pre-effects processor); Subgroups A-D (32-channel models); Main Mix L/R; Mono bus (64S); Solo L/R [OM 12.3.4]. Reset Sends restores defaults.
- **USB defaults** [OM 14.2.4; KB-64]: 1-32 channel inputs; 33/34 Aux In 1; 35/36 Aux In 2; 37/38 Tape In; 39/40 Main L/R; 41-56 FlexMixes (KB-64); 57-64 unassigned (except 64S, where 1-64 are channels 1-64 [OM 14.2.4]).
- **SD: fixed on 32-channel models.** SD tracks 1-32 = channels 1-32 "(Fixed)"; only tracks 33-34 can take "any mix" (default Main L/R) [OM 12.3.5, 14.2.5]. On the 64S any input or mix can go to any of the 34 SD tracks [OM 12.3.5].
- When to use which: record the main mix or a FlexMix/subgroup alongside the inputs by patching it to a spare USB send (39/40 and 41-56 already carry Main and FlexMixes by default); reorder tracks in USB Sends; use the 64S SD patch to pick which 32 of 64 inputs go to card.
- Playback in (virtual soundcheck): Fat Channel Input Source buttons Analog / Network / USB / SD Card per channel; press and hold USB to multi-assign [OM 6.10]. For SD: load session, then "All Ch to SD Input" [OM 8.3; KB-SD]. Input patching: Digital Patching > Input Source [OM 12.3.1].

## 6. Tap points

- **Tap point of the "Inputs" sources on USB and SD: unknown.** The owner's manual lists "Inputs" as a USB send source but does not say whether that is post-preamp/pre-Fat Channel or later; the block diagrams are "too large to be included" and are referred to the PreSonus website [OM 14.3]. No KB article found that states it. Do not publish a tap point until checked on hardware or in the block diagram PDF.
- No per-channel or global USB tap selector is documented. The only documented pick-off choices are for aux sends: Pre 1 (after polarity, high-pass filter, gate), Pre 2 (after all Fat Channel processing, before fader), Post [OM 5.2.1]. These apply to FlexMix sends, which can themselves be patched to USB.
- "FX Send Mixes (pre-effects processor)" are available on USB [OM 12.3.4].
- Gain: analog XMAX preamp gain per channel; line inputs bypass the preamp but have "+20 dB of digital gain" [OM 3.2.1]. "Preamp Trim and Digital Gain" are lockable user permissions [OM 12.2.3]. Whether digital gain is upstream of the USB "Inputs" tap: unknown.
- Shared stage box (NSB or a rack in Stagebox mode over AVB): preamp control is assigned to one console via **Preamp Permissions** in Remote I/O Setup (formerly Stagebox Setup) [KB-AVB]. Analog preamp gain is upstream of any digital tap, so a gain change by the console holding preamp permission changes every recording from that box (inference, not maker-stated). A second console without permission cannot change it.

## 7. Gotchas

- 64x64 USB crashes some iPadOS DAWs at launch [KB-IOS]; Compatibility Mode drops to 34x34 [KB-COMPAT].
- iPad/iPhone is not charged through the camera adapter; the mixer is externally powered and does not need bus power [KB-IOS].
- 32-channel consoles: SD tracks 1-32 are hard-wired to channels 1-32 [OM 14.2.5]; rack models record only stereo to SD [KB-RACKSD].
- SD: SDHC up to 32 GB, Class 10 U3, FAT32, run Speed Test [OM 8; KB-SD].
- Sample rate is 44.1 or 48 kHz only; no 96 kHz [OM 12.1].
- 16R has fewer USB channels (18x18, 24x24 after firmware 2.4) [CHART; KB-IFACE].
- If Capture/DAW playback is routed back while tracks are still armed, feedback loops can occur (PreSonus KB 7059582068493).

## 8. Confidence

| Fact | Confidence |
|---|---|
| 64x64 USB on all consoles and 32R/24R | confirmed by maker (KB + chart) |
| 16R 18x18, 24x24 after fw 2.4 | confirmed by maker |
| 44.1/48 kHz only, USB 2.0 Type-B | confirmed by maker |
| Class compliant on iOS/iPadOS and macOS, camera adapter, no charging | confirmed by maker |
| 64x64 crashes some iPad DAWs | confirmed by maker |
| Compatibility Mode 34x34, Home > System | confirmed by maker |
| SD 34 tracks (32 + main) consoles, stereo only racks | confirmed by maker |
| SD file format | unknown |
| USB per-slot patching, source list, defaults | confirmed by maker |
| SD fixed 1-32 on 32-ch consoles, free on 64S | confirmed by maker |
| Tap point of USB/SD "Inputs" | unknown |
| Gain change on shared stage box affects recording | secondary (inference from signal flow) |

## 9. Sources

- https://shop.ccisolutions.com/StoreFront/jsp/pdf/studioLive_seriesIII_ownersManual.pdf
- https://shop.ccisolutions.com/StoreFront/jsp/pdf/PRE-SLIII_rack_userGuide.pdf
- https://shop.ccisolutions.com/StoreFront/jsp/pdf/PRE-seriesiii_mixer_comparison_chart.pdf
- https://support.presonus.com/hc/en-us/articles/360059975732-PreSonus-Hardware-iOS-iPadOS-Compatibility
- https://support.presonus.com/hc/en-us/articles/360062440371-StudioLive-Series-III-Can-my-StudioLive-utilize-all-64-USB-AVB-channels
- https://support.presonus.com/hc/en-us/articles/11189120184845-Compatibility-Mode-in-Universal-Control-v4
- https://support.presonus.com/hc/en-us/articles/360052084812-Series-III-Interface-Mode-WDM-Primer
- https://support.presonus.com/hc/en-us/articles/4404701016973-StudioLive-Series-III-Console-SD-Card-Recording-and-Playback
- https://support.presonus.com/hc/en-us/articles/360050481392-StudioLive-Series-III-Rack-Mount-Mixers-SD-Card-Stereo-Recording-and-Playback
- https://support.presonus.com/hc/en-us/articles/360031210932-Series-III-Connecting-the-StudioLive-64S-with-two-32Rs-using-AVB
- https://support.presonus.com/hc/en-us/articles/7059582068493-Capture-USB-Recording-Playback-Setup-Series-III
