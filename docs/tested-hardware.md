# Tested hardware

Rigs that ShowRecorder has recorded on, checked on real hardware (not the Simulator). A rig not listed here may well work: any class-compliant USB audio interface records, and an X Air mixer adds channel names and colors over Wi-Fi. If yours works or doesn't, [tell us](https://github.com/ericdahl-dev/ShowRecorder/issues).

## Verified

| Device | Interface | Connection | What was checked | Result |
|---|---|---|---|---|
| MacBook Pro 16-inch (2023, M2 Max), macOS 27 | Behringer XR18 | USB cable straight to the Mac | 18 USB Channels with independent signal; a Take with every Stem | 18 Stems, 0 Dropouts |
| MacBook Pro 16-inch (2023, M2 Max), macOS 27 | Behringer XR18 | Wi-Fi (Mixer Link) | Channel names and colors; Find mixers with no address typed | Names on every Stem; found in under 4 s, 3 of 3 |
| MacBook Pro 16-inch (2023, M2 Max), macOS 27 | Audient EVO 4 | USB | A Take at 96 kHz; switching the interface's sample rate | Recorded at 96 kHz |
| iPhone (TestFlight build) | Behringer XR18 | Wi-Fi (Mixer Link) | Find mixers with no address typed | Found |

## Waiting on the hardware session (#327)

The rig most people will use isn't verified yet. These rows are filled in from #327:

| Device | Hub | Drive | Interface | 18 channels | Charges while recording | 3-hour locked-screen Take |
|---|---|---|---|---|---|---|
| iPhone (USB-C) | _model to note_ | _model to note_ | XR18 | | | |
| iPad | | | XR18 | | | |

## What to look for in a hub

- **Powered USB-C with power pass-through**, so the iPhone charges while the mixer and a drive are plugged in. An 18-channel Take for 3 hours drains a phone otherwise.
- **USB 2.0 or faster** for the mixer. 18 channels at 48 kHz, 24-bit is about 2.6 MB/s.
- **A data port for the Drive.** About 9.3 GB per hour for 18 channels at 48 kHz.
