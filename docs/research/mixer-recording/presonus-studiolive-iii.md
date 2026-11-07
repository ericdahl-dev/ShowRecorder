# PreSonus StudioLive Series III (consoles 64S/32S/32SX/32SC/32/24/16, racks 32R/24R/16R)

Source key used below:
- [OM] StudioLive Series III Console Mixers Owner's Manual, PreSonus's current English copy (PDF created July 2026; its title page reads "StudioLive Series III SE Consoles" and it covers the SE 32/24/16, the 64S, 32S, 32SX, 32SC and the "Blue" 32/24/16 with firmware 2.0+), on PreSonus's own asset host, found 2026-11-07 via presonus.com Support Downloads: https://www.fmicassets.com/Damroot/Original/10153/OM_StudioLive-Series-III-Console-Mixers_EN.pdf . Every console fact below that cites [OM] was re-checked against this copy on 2026-11-07; see "Differences from the old manual" below. The older copy we first used (PreSonus PDF, (c) 2019, hosted by dealer CCI Solutions, https://shop.ccisolutions.com/StoreFront/jsp/pdf/studioLive_seriesIII_ownersManual.pdf) is no longer cited.
- [TS-32S] StudioLive 32S tech sheet (PreSonus): https://www.fmicassets.com/Damroot/Original/10154/TS_studiolive32s_EN.pdf
- [RACK-OM] StudioLive Series III Rack Mixers Owner's Manual (PreSonus, PDF dated 13 Oct 2022), on PreSonus's own download host: https://pae-web.presonusmusic.com/downloads/products/pdf/StudioLive_Series_III_Rack_Mixers_OwnersManual_EN_13102022.pdf
- [RACK-OM-OLD] Older rack manual (PreSonus PDF, dealer-hosted): https://shop.ccisolutions.com/StoreFront/jsp/pdf/PRE-SLIII_rack_userGuide.pdf
- [CHART] PreSonus Series III comparison chart, current copy ((c) 2025; lists the SE consoles, the 64S/32S/32SX/32SC and the 32R/24R/16R, but no longer the "Blue" 32/24/16): https://www.fmicassets.com/Damroot/Original/10154/SUP_StudioLive-Series-III-Comaparison-Chart.pdf
- [CHART-OLD] Earlier chart that also listed the "Blue" 32/24/16 at 64x64 USB and 34x34 SD: https://pae-web.presonusmusic.com/downloads/products/pdf/seriesiii_mixer_comparison_chart.pdf
- [KB-IOS] PreSonus KB, Hardware iOS/iPadOS Compatibility (published April 26, 2021): https://support.presonus.com/hc/en-us/articles/360059975732-PreSonus-Hardware-iOS-iPadOS-Compatibility
- [KB-64] PreSonus KB, Can my StudioLive utilize all 64 USB/AVB channels? (updated June 1, 2021): https://support.presonus.com/hc/en-us/articles/360062440371-StudioLive-Series-III-Can-my-StudioLive-utilize-all-64-USB-AVB-channels
- [KB-COMPAT] PreSonus KB, Compatibility Mode in Universal Control v4 (Dec 2022): https://support.presonus.com/hc/en-us/articles/11189120184845-Compatibility-Mode-in-Universal-Control-v4
- [KB-IFACE] PreSonus KB, Series III Interface Mode / WDM Primer (Oct 2020): https://support.presonus.com/hc/en-us/articles/360052084812-Series-III-Interface-Mode-WDM-Primer
- [KB-SD] PreSonus KB, Series III Console SD Card Recording and Playback (July 2021): https://support.presonus.com/hc/en-us/articles/4404701016973-StudioLive-Series-III-Console-SD-Card-Recording-and-Playback
- [KB-SDHC] PreSonus KB, Which SDHC Card should be used with StudioLive Series III Console and Rack mixers? (reviewed Nov 30, 2020): https://support.presonus.com/hc/en-us/articles/115000219906
- [KB-SDXC] PreSonus KB, Can I use an SDXC SD Card (64GB+) for recording? (updated Feb 17, 2021): https://support.presonus.com/hc/en-us/articles/360056572451
- [KB-RACKSD] PreSonus KB, Rack Mount Mixers SD Card Stereo Recording and Playback (reviewed Nov 29, 2021): https://support.presonus.com/hc/en-us/articles/360050481392-StudioLive-Series-III-Rack-Mount-Mixers-SD-Card-Stereo-Recording-and-Playback
- [KB-CAPTURE] PreSonus KB, Capture - USB Recording/Playback Setup (Series III) (July 2022): https://support.presonus.com/hc/en-us/articles/7059582068493-Capture-USB-Recording-Playback-Setup-Series-III
- [KB-AVB] PreSonus KB, Connecting the StudioLive 64S with two 32Rs using AVB (Aug 2025): https://support.presonus.com/hc/en-us/articles/360031210932-Series-III-Connecting-the-StudioLive-64S-with-two-32Rs-using-AVB

The support.presonus.com pages return 403 to plain fetches; on 2026-11-06 we read the KB articles through the site's public help-center API (`/api/v2/help_center/en-us/articles/<id>.json`).

## 1. USB audio to a computer

| Model | USB I/O | SD recorder |
|---|---|---|
| 64S, 32S, 32SX, 32SC | 64x64 [CHART; KB-64] | 34 tracks [CHART "34x34"; KB-SD] |
| 32, 24, 16 (Series III "Blue" consoles) | 64x64 [CHART-OLD; KB-64] | 34 tracks [CHART-OLD; OM 2.2.6] |
| 32R, 24R | 64x64 [CHART; KB-64; RACK-OM]. The older rack manual says 38x38 [RACK-OM-OLD], superseded. | stereo only, 2x2 [CHART; KB-RACKSD] |
| 16R | 18x18 [CHART; RACK-OM 2022]. [KB-IFACE] says firmware 2.4 raises it to 24x24. The sources conflict; see below. | stereo only, 2x2 [CHART] |

- 64x64 is the routing pool, not the mixing channel count: "allows for the 32 channel StudioLives to have 64 USB/AVB Inputs (Returns) and 64 USB/AVB Outputs (Sends) to choose from"; only the 64S mixes 64 inputs [KB-64].
- 16R conflict: [KB-IFACE] (Oct 2020, firmware 2.4) says "the StudioLive 16R now has it's USB I/O updated to support an increased I/O count ... 24x24 USB I/O". The 2022 rack manual and the comparison chart still say 18x18. Which one current firmware gives: unknown without a test.
- Sample rate: "StudioLive Series III mixers can operate at 48 kHz or 44.1 kHz" [OM 12.1, System]. The OM spec table lists "Sampling Rate: 48 kHz"; the 32S tech sheet lists "44.1 and 48 kHz" [TS-32S]. A factory default is not stated in words.
- Bit depth: A/D/A 24-bit [OM spec]; rack feature list: "48 kHz and 44.1 kHz operation with 24-bit resolution" [RACK-OM]. USB stream word length is not stated separately (unknown).
- Connector: "USB Recording Port: USB 2.0, Type-B" [OM spec; RACK-OM-OLD spec].

## 2. Driverless status

- iOS/iPadOS: "All PreSonus USB Audio and MIDI interfaces / controllers work class compliant." "PreSonus USB Audio mixers, interfaces and controllers will work when directly connected for audio / MIDI recording with iOS/iPadOS devices: iPad Pro, iPad, iPad Air, iPad Mini, iPod Touch, and iPhones." StudioLive Series III mixers (consoles and racks) are listed as externally powered devices. Connect with a Lightning to USB Camera Adapter; "Note that this does not allow you to charge your iOS/iPadOS device" (use the Lightning to USB 3 Camera Adapter with power to charge) [KB-IOS]. The KB names iPhones as a class, not a tested model list.
- macOS: covered by the same KB statement ("iOS/iPadOS much like macOS also support class device connectivity") [KB-IOS]. PreSonus still ships Universal Control for Mac for control and routing.
- Mac USB note: for Macs advised to use Compatibility Mode, PreSonus says connect directly, "no USB hubs", and on USB-C-only Macs use Apple's own USB-C to USB adapter [KB-COMPAT].
- Windows: uses the Universal Control driver (Compatibility Mode and WDM notes in [KB-COMPAT], [KB-IFACE]). Exact "driver required" wording not captured; treat as "PreSonus driver (Universal Control) on Windows".
- USB configuration switches:
  - **Compatibility Mode (34x34) vs Native USB Mode (64x64)**: console Home > System; Universal Control > Device Settings. Requires firmware 2.7.0+ and UC 4.0.0+. Introduced for Intel/Apple Silicon USB-controller problems [KB-COMPAT]. With fewer channels, sends and returns beyond 34 are not available (KB wording paraphrased).
  - **Interface Mode** (firmware 2.4+): console Home > System, or UC Settings. Rearranges USB returns to feed mix outputs directly; not available in Stage Box or Monitor Mixer mode [KB-IFACE]. Not needed for recording inputs.
- Known iPad issue: "StudioLive Series III mixers support a 64x64 USB 2.0 configuration. This causes some DAW apps on iPadOS to crash on launch" (Auria Pro, n-Track) [KB-IOS]. Compatibility Mode (34x34) is the maker's lower-count option and the obvious workaround, but PreSonus does not say so for iPad (inference).

## 3. Onboard recording without a computer (SD card)

- Consoles: "34-track SD recorder" [OM 2.2.6]; "capable of recording all 32 inputs plus the main left / right mix for a total of 34 channels" [KB-SD]; "Inputs Channels 1-32 plus a Stereo assignable track for the Main Mix, Aux Mixes, etc." [KB-SDHC]. The 24 and 16 consoles are also listed as 34x34 on [CHART]; how tracks above their channel count are used is not explained (unknown).
- Format: Capture session on SD; "Session files recorded on the SD Card can be opened directly in Studio Pro and Capture - no conversion or exporting necessary" [OM 8.3] (the old copy said Studio One). The underlying audio file format is not stated in any maker source we read (unknown).
- Media: "SD and SDHC cards up to 32 GB", FAT32, run Speed Test first [OM 8]. Requires "SDHC - Class 10 - U3 cards" [KB-SD]. The mixer is "SDHC UHS-I"; UHS-II cards work no faster [KB-SDHC]. **SDXC (64 GB and larger) is not supported**: "SDXC Cards (64GB and higher) are currently not supported with PreSonus StudioLive mixers" [KB-SDXC]. Reformatting an SDXC card to FAT32 may work but is unsupported [KB-SDXC; KB-SDHC].
- Racks: SD is stereo only; choose Main L/R, a FlexMix or a subgroup pair in UC > Capture [KB-RACKSD].
- Error monitoring: Rec Errors box turns yellow then red; card speed drops as it fills [OM 8.3].
- Computer recordings back to SD: Capture 3 > Session > Export to SD Card makes a session the console can play for virtual soundcheck (PreSonus KB 7428384416269, https://support.presonus.com/hc/en-us/articles/7428384416269).

## 4. Recording settings

- Sample rate: Home > System > Sample Rate (48 / 44.1 kHz) [OM 12.1]. On racks, the equivalent setting in Universal Control: location not confirmed in a maker source we read (unknown).
- Clock: Home > System > Network Clock. The 2026 OM: "For most applications this can be set to 'PTP Clock (Default)'" [OM 12.1]. (The old copy and [KB-AVB] described Internal for standalone use; see Differences.)
- USB channel count: Native 64x64 or Compatibility 34x34 (Home > System) [KB-COMPAT].
- SD arming: Live Recording section Edit button > Speed Test > New Session > Capture screen > "Arm All Tracks" (all 34: "record all 32 input channels and your Main mix") or "Select Arm Tracks" then each channel's Select button [OM 8.1, 8.3; KB-SD]. On the 64S the Select buttons arm Capture tracks, not channels [OM 8.3]. After recording, touch "Save and Close" so the session can be played back [KB-SD].
- Capture on a computer: Capture auto-detects the mixer and makes one mono track per input channel [KB-CAPTURE].

## 5. Routing (per-slot patching)

- **USB: fully per slot.** Home > Audio Routing > Digital Patching > USB Sends (2026 OM 12.3, 12.3.4: the Audio Routing button on the Home screen, then Digital Patching). "Selecting the USB Sends menu will allow you to patch any channel send or mix to any USB driver send. Select the USB driver send ... Then select the channel or mix from the Available Source list" [OM 12.3.4]. Available sources: Inputs; Aux In A L/R; Aux In B L/R; Tape In L/R; Talkback; FlexMixes; FX Send Mixes (pre-effects processor); Subgroups A-D (32-channel models only); Main Mix L/R; Mono bus (64S only); Solo L/R [OM 12.3.4]. Reset Sends restores defaults.
- **USB defaults** [OM 14.2.4; KB-64]: 1-32 channel inputs; 33/34 Aux In 1; 35/36 Aux In 2; 37/38 Tape In; 39/40 Main L/R. Above 40 the sources differ: [KB-64] says 41-56 FlexMixes and 57-64 unassigned "(except on the 64S)"; the 2026 [OM 14.2.4] table shows USB 41-64 empty ("---") on every model, and on the 64S channels 1-39 on USB 1-39 with USB 40-64 empty. The guide tells readers to check the USB Sends screen.
- **SD: fixed on 32-channel models.** SD tracks 1-32 = channels 1-32 "(Fixed)"; only tracks 33-34 can take "any mix" (default Main L/R) [OM 12.3.5, 14.2.5]. On the 64S any input or mix can go to any of the 34 SD tracks [OM 12.3.5].
- When to use which: record the main mix or a FlexMix/subgroup alongside the inputs by patching it to a spare USB send (39/40 and 41-56 already carry Main and FlexMixes by default); reorder tracks in USB Sends; use the 64S SD patch to pick which 32 of 64 inputs go to card.
- Playback in (virtual soundcheck): Fat Channel Input Source buttons Analog / Network / USB / SD Card per channel; press and hold USB to multi-assign [OM 6.10]. For SD: load session, then "All Ch to SD Input" [OM 8.3; KB-SD]. Input patching: Digital Patching > Input Source [OM 12.3.1]. In Capture, the Digital Return button patches tracks back to the mixer [KB-CAPTURE].

## 6. Tap points

- **Tap point of the "Inputs" sources on USB and SD: unknown.** The owner's manual lists "Inputs" as a USB send source but does not say where in the channel it is taken. The block diagrams are "too large to be included" and are referred to the PreSonus website [OM 14.3; RACK-OM 5.6]. We did not find the diagram PDFs on presonus.com or in the KB (searched 2026-11-06). Do not publish a tap point until checked on hardware or in the block diagram.
- No per-channel or global USB tap selector is documented. The only documented pick-off choices are for aux sends: Pre 1 (after polarity, high-pass filter, gate), Pre 2 (after all Fat Channel processing, before fader), Post [OM 5.2.1]. These apply to FlexMix sends, which can themselves be patched to USB, so a FlexMix gives a known tap if one is needed.
- "FX Send Mixes (pre-effects processor)" are available on USB [OM 12.3.4].
- Gain: analog XMAX preamp gain per channel; line inputs bypass the preamp but have "+20 dB of digital gain" [OM 3.2.1]. User permission "Preamps" locks "Input trim, Digital Gain, Phantom Power, Polarity, High Pass Filter, and Input Delay" [OM 12.2.3]. Whether digital gain is upstream of the USB "Inputs" tap: unknown.
- Shared stage box (NSB or a rack in Stagebox mode over AVB): preamp control is assigned to one console via **Preamp Permissions** in Remote I/O Setup (formerly Stagebox Setup) [KB-AVB]. Analog preamp gain is upstream of any digital tap, so a gain change by the console holding preamp permission changes every recording from that box (inference, not maker-stated). A second console without permission cannot change it.

## 7. Gotchas

- 64x64 USB crashes some iPadOS DAWs at launch [KB-IOS]; Compatibility Mode drops to 34x34 [KB-COMPAT].
- iPad/iPhone is not charged through the plain camera adapter; the mixer is externally powered and does not need bus power [KB-IOS].
- 32-channel consoles: SD tracks 1-32 are hard-wired to channels 1-32 [OM 14.2.5]; rack models record only stereo to SD [KB-RACKSD].
- SD: SDHC up to 32 GB, Class 10 U3, FAT32, run Speed Test; SDXC not supported [OM 8; KB-SD; KB-SDXC].
- Sample rate is 44.1 or 48 kHz only; no 96 kHz [OM 12.1].
- 16R USB count: 18x18 or 24x24 depending on source (see section 1) [CHART; RACK-OM; KB-IFACE].
- If Capture/DAW playback is routed back while tracks are still armed, feedback loops can occur; un-arm the tracks [KB-CAPTURE].

## 8. Confidence

| Fact | Confidence |
|---|---|
| 64x64 USB on all consoles and 32R/24R | maker (KB-64, CHART, RACK-OM) |
| 16R 18x18 vs 24x24 after fw 2.4 | maker, but sources conflict |
| 44.1/48 kHz only, USB 2.0 Type-B | maker (OM) |
| Class compliant on iOS/iPadOS and macOS, camera adapter, no charging | maker (KB-IOS) |
| iPhone named by PreSonus | maker, generic statement for all PreSonus USB mixers (not a model test) |
| 64x64 crashes some iPad DAWs | maker (KB-IOS) |
| Compatibility Mode 34x34, Home > System | maker (KB-COMPAT) |
| SD 34 tracks (32 + stereo) consoles, stereo only racks | maker (OM, KB-SD, KB-RACKSD) |
| SDHC only, SDXC unsupported | maker (KB-SDXC, KB-SDHC) |
| SD audio file format | unknown |
| USB stream bit depth | unknown |
| USB per-slot patching, source list, defaults 1-40 | maker (OM 2026) |
| USB defaults above 40 | maker, but OM 2026 and KB-64 conflict |
| SD fixed 1-32 on 32-ch consoles, free on 64S | maker (OM 2026) |
| Tap point of USB/SD "Inputs" | unknown |
| Gain change on shared stage box changes the recording | inference from signal flow (not maker-stated) |

## Differences from the old manual (re-checked 2026-11-07)

Every console fact above that cites [OM] was re-read in PreSonus's current copy (fmicassets.com, PDF created July 2026). What changed:

- **Scope:** the current manual also covers the StudioLive SE 32, SE 24 and SE 16; its illustrations show an SE 32. The guide doesn't cover the SE models (one line says so), and PreSonus also sells SE racks (SE 16R/24R/32R), which we haven't researched.
- **Studio One is now Studio Pro:** SD sessions "can be opened directly in Studio Pro and Capture" [OM 8.3].
- **Network Clock default:** now described as "PTP Clock (Default)" for most applications [OM 12.1]. The guide says to leave it at its default unless you use AVB.
- **USB default table above USB 40:** the 2026 table shows USB 41-64 empty on all models, and the 64S with channels 1-39 on USB 1-39 and USB 40-64 empty [OM 14.2.4]. [KB-64] (updated 2021) says FlexMixes on 41-56. The guide states both and says to check the USB Sends screen. We did not find a statement of which one current firmware does (unknown without a test).
- **Firmware updates:** downloaded from a "My Fender account" [OM 12.1.4]. PreSonus's support notes now name "Fender Universal Control v5" [KB-COMPAT]; on 2026-11-07 the presonus.com Support Downloads page listed Fender Universal Control 5.1 and 64S firmware 3.4.0 (coordinator's check, not re-verified here).
- **Unchanged:** 48 or 44.1 kHz [OM 12.1]; USB 2.0 Type-B and A/D/A 24-bit [OM 14.1]; 34-track SD recorder [OM 2.2.6, 8.3]; SD/SDHC up to 32 GB, FAT32, Speed Test [OM 8, 3.3]; Arm All Tracks "all 32 input channels and your Main mix" [OM 8.3]; the 64S SD note [OM 8.3, 12.3.5]; SD tracks 1-32 "(Fixed)" on all 32-channel models and only 33-34 patchable [OM 12.3.5, 14.2.5]; the USB Sends source list [OM 12.3.4]; Input Source buttons Analog/Network/USB/SD Card with press-and-hold multi-assign [OM 6.10.1]; aux send points Pre 1/Pre 2/Post [OM 5.2.1]; line inputs bypass the preamp with "+20 dB of digital gain" [OM 3.2.1]; the block diagram is still "too large to be included in this manual" [OM 14.3], so the USB/SD "Inputs" tap point is still unknown.
- **Compatibility Mode** is still not in the manual's System screen list [OM 12.1]; it comes only from [KB-COMPAT] (Home > System; UC Device Settings). [KB-COMPAT] also gives the Compatibility Mode USB send patch: channels 1-32 on USB 1-32, Main L/R on USB 33-34, sends and returns beyond 34 grayed out.
- **Stage box menu name:** the 2026 manual still calls it "Stagebox Setup" under Audio Routing [OM 12.3]; [KB-AVB] (Aug 2025) calls it Remote I/O Setup. Not used in the guide.
- **Comparison chart:** the current chart (2025) still gives the 16R 18x18 USB and the racks 2x2 SD; it no longer lists the "Blue" 32/24/16, so their counts rest on [CHART-OLD] and [KB-64].

## 9. Sources

- https://www.fmicassets.com/Damroot/Original/10153/OM_StudioLive-Series-III-Console-Mixers_EN.pdf (PreSonus, current console manual)
- https://www.fmicassets.com/Damroot/Original/10154/TS_studiolive32s_EN.pdf
- https://www.fmicassets.com/Damroot/Original/10154/SUP_StudioLive-Series-III-Comaparison-Chart.pdf
- https://pae-web.presonusmusic.com/downloads/products/pdf/StudioLive_Series_III_Rack_Mixers_OwnersManual_EN_13102022.pdf
- https://shop.ccisolutions.com/StoreFront/jsp/pdf/PRE-SLIII_rack_userGuide.pdf (PreSonus PDF, dealer-hosted, older)
- https://pae-web.presonusmusic.com/downloads/products/pdf/seriesiii_mixer_comparison_chart.pdf
- https://support.presonus.com/hc/en-us/articles/360059975732-PreSonus-Hardware-iOS-iPadOS-Compatibility
- https://support.presonus.com/hc/en-us/articles/360062440371-StudioLive-Series-III-Can-my-StudioLive-utilize-all-64-USB-AVB-channels
- https://support.presonus.com/hc/en-us/articles/11189120184845-Compatibility-Mode-in-Universal-Control-v4
- https://support.presonus.com/hc/en-us/articles/360052084812-Series-III-Interface-Mode-WDM-Primer
- https://support.presonus.com/hc/en-us/articles/4404701016973-StudioLive-Series-III-Console-SD-Card-Recording-and-Playback
- https://support.presonus.com/hc/en-us/articles/115000219906
- https://support.presonus.com/hc/en-us/articles/360056572451
- https://support.presonus.com/hc/en-us/articles/360050481392-StudioLive-Series-III-Rack-Mount-Mixers-SD-Card-Stereo-Recording-and-Playback
- https://support.presonus.com/hc/en-us/articles/360031210932-Series-III-Connecting-the-StudioLive-64S-with-two-32Rs-using-AVB
- https://support.presonus.com/hc/en-us/articles/7059582068493-Capture-USB-Recording-Playback-Setup-Series-III
- https://support.presonus.com/hc/en-us/articles/7428384416269

## Gaps

- "Inputs" tap point on USB and SD: unknown. Don't say "raw", "pre-EQ" or "post-preamp". If the guide needs a known tap, describe a FlexMix with Pre 1 or Pre 2 sends, and say plainly that the default input tap is not documented.
- Whether digital gain and trim reach the recorded "Inputs": unknown. Leave out.
- SD audio file format: unknown. Say "a Capture session that opens in Capture and Studio One".
- USB stream bit depth: unknown. Say "24-bit converters" only.
- 16R USB channel count: 18x18 or 24x24 depending on source and firmware. Say "18 or more, depending on firmware" or test first.
- SD track use on 24 and 16 consoles beyond their channel count: unknown. Leave out.
- iPhone: PreSonus names iPhones only in a general statement. Say "PreSonus lists iPhone as supported; not tested by us".
- USB-C iPads/iPhones: the KB says USB-C devices are compatible but gives adapter steps mostly for Lightning. Say "camera adapter (Lightning) or USB-C adapter".
- Rack sample-rate menu path in Universal Control: not confirmed. Leave out the path.
- Windows driver wording: not captured. Say "install Universal Control on Windows".
- The console owner's manual is now PreSonus's own current copy (fmicassets.com, July 2026). The dealer-hosted 2019 copy is no longer cited.
- USB 41-64 defaults: the 2026 manual and KB-64 disagree. Say both and point to the USB Sends screen.
