<p align="center"><img src="design/AppIcon-mac-1024.png" width="128" alt="ShowRecorder icon: a red record ring around colored stem bars"></p>

# ShowRecorder

Record every channel of your mixer from an iPhone or iPad, or the Mac you already have.

You don't need a dedicated recording laptop. Plug a multichannel USB mixer or audio interface into a USB-C iPhone through a powered hub, or into the Mac mini in your rack or the MacBook at front of house, tap record, and you get a Show folder with one stem per channel. On mixers ShowRecorder knows how to talk to, each track is also named and colored from the mixer itself, so channel 7 arrives as `07 Lead Vocal.wav`, not `Input 7`. Behringer X-Air (XR18) and Midas MR18 are supported first; more mixers will follow.

> **Status: in development.** It isn't on the App Store yet. Builds go to testers through TestFlight (see [Releasing to TestFlight](#releasing-to-testflight)). The recording core works and is tested; the remaining MVP work is tracked in [issue #1](https://github.com/ericdahl-dev/ShowRecorder/issues/1) and the issues linked from it.

## What works today

- **Multitrack recording:**
  - One mono 24-bit, 48 kHz Broadcast WAV Stem per USB Channel, in `Show / Take NN / Stems` folders.
  - Each Stem's bext chunk carries its Source name and a time reference shared by every Stem in the Take.
- **Crash-safe files:** headers are committed every 2 seconds, so if the app is killed or loses power, the Stems still play up to the last commit. Stems switch to RF64 before they pass 4 GB.
- **Keeps recording when a Destination fails:**
  - With no Drive at record, the Take starts on the Device with a warning, and the Drive joins when it appears.
  - If the Device or Drive fails mid-Take, the other carries on, and the failed Copy picks up again when it comes back.
  - Each Gap is held as silence so Stems stay aligned, and is listed in `Take.json` and the report.
  - The Take finalizes with 60 s of space left on the last healthy Destination.
  - **Repair:** after the Take ends, each Copy's Gaps are filled from the other Copy, so both end identical. The record screen and report say whether each Copy is complete, has Gaps, Repaired or Repair failed.
- **Any multichannel USB input:** every channel the device sends is recorded, with no fixed channel count.
- **Pre-roll:** while Armed the recorder keeps the last seconds of audio, and a Take starts with them. Settings offers Off, 5, 10 or 20 s (10 s by default). The Show report and Reaper project line up with the Pre-roll.
- **Markers:**
  - A Marker button drops a named Marker at the current point in the Take. Markers are written into every Stem as cue points.
  - The Marker list on the record screen shows each Marker's time since record was pressed and renames it during the Take.
  - You can also rename a Marker after the Take, from the Show detail screen. The new name goes into `Take.json`, every Stem and the report and project.
  - The Reaper project gets a marker for each one.
- **Shows:**
  - New Show on the record screen takes a name and an optional venue. End Show closes it. A Show with no Take for 6 hours ends, and the next record starts a new one.
  - The open Show is kept in `Show.json` and survives a relaunch.
  - The Show list shows past Shows, newest first, with date, duration, Takes and the state of each Copy. It reads the files, so it covers the Drive too.
  - Show detail lists the Markers by Take and renames them.
- **Dropouts:** if the recorder can't keep up and audio is lost, the Stem holds silence for exactly that long, a Dropout Marker is added and the record screen shows a Dropout count. Dropouts are in `Take.json` and the Show report.
- **Settings:** input, Pre-roll, the Drive folder, time left on each Destination and the Mixer Link address are set in Settings (a sheet on iPhone and iPad, the Settings window on the Mac), and read-only during a Take.
- **Battery and heat:** the status strip shows battery level and, when the device is warm, heat. An unplugged device at 20% or less warns, and at 10% or less it is urgent. Serious heat warns and critical heat is urgent.
- **Keeps the Take safe:**
  - A Take survives its screen being torn down or rebuilt. Only Stop and the app ending end a Take.
  - On the Mac, closing the window during a Take asks whether to stop first.
  - If the USB route changes mid-Take, the Take moves to the new route, and a failed move is retried.
  - An Armed recorder nobody is using disarms 30 minutes after the screen locks or the app leaves the front.
- **Layouts:** the record screen has portrait and landscape layouts. In portrait it shows the Take's elapsed time. On iPad the meters span the screen width.
- **Mixer Link over Wi-Fi** (X-Air mixers today):
  - Enter the mixer's IP and each meter shows its Source's name and color.
  - Names are frozen into the Stems and `Take.json` when record is pressed.
  - Mute, fader and input source are saved with each Take when the mixer reports them.
- **Meters and levels** ([ADR 0005](docs/adr/0005-level-meter-scale.md)):
  - Each USB Channel has a wide peak bar, a narrower average bar in front and a held-peak line across both.
  - The average is a VU reading. A faint Target band, -18 to -15 dBFS, is shaded on every lane: the average bar is blue-gray below it, green in it and orange above it, and never red.
  - The peak bar is green up to -18 dBFS, yellow up to -6 and red above. The held-peak line turns red and thicker above -3.
  - A red Clip mark appears above a channel that reaches full scale. It stays until you tap that lane, start a new Take or disarm.
  - Each Take records every channel's peak and average in `Take.json`, and the report has a Levels table.
- **After the show:**
  - Each Show gets an HTML report and a CSV channel list.
  - Each Show gets a Reaper project with one track per USB Channel, Takes laid end to end and a marker at each Take.
- **Mac and iOS input:**
  - On the Mac, any Core Audio device, with hot-plug: plug in a mixer and it's armed.
  - On iPhone and iPad, the current USB route.
  - Recording continues with the screen locked, in the background and through interruptions.

Not built yet: Templates, Mixer Triggers, Snapshot Markers, Mixer Link over USB, sharing a Show, editing a Show afterward, the Pro unlock and Trial, and the Free channel limit (today every channel is recorded). See the [open issues](https://github.com/ericdahl-dev/ShowRecorder/issues).

## The rig

| Part | Notes |
|---|---|
| A multichannel USB mixer or audio interface | Class-compliant over USB, so iOS and macOS see it without a driver. Every channel it sends is recorded. |
| USB-C iPhone (15 or later) or iPad, or any Mac | iOS/iPadOS/macOS 26. |
| Powered USB-C hub | Charges the phone while the mixer and the SSD are connected. |
| SSD | Optional. Without one, Takes go to the Device only. About 0.5 GB per channel per hour at 48 kHz/24-bit (about 9.3 GB per hour for 18 channels). |
| The mixer's network | Optional, for channel names and colors on supported mixers. |

### Mixer integration

| Mixer | Recording | Names and colors |
|---|---|---|
| Behringer XR18, Midas MR18 | 18 USB Channels | Yes, over Wi-Fi (USB not built yet) |
| Behringer XR12/XR16 | No multichannel USB | n/a |
| Behringer X32/M32 (X-USB card) | Should work as a 32-channel USB interface (untested) | Planned ([#199](https://github.com/ericdahl-dev/ShowRecorder/issues/199)) |
| Other class-compliant mixers and interfaces | Should work (untested) | Not yet |

A list of tested hubs and SSDs will follow the first hardware check ([#4](https://github.com/ericdahl-dev/ShowRecorder/issues/4)).

## The Show-Safe Promise

A Take never stops, and audio is never held back, because of a trial, a limit or a license. Limits are checked only when record is pressed. See [ADR 0004](docs/adr/0004-one-time-pro-unlock-and-show-safe-limits.md).

## Building

Requirements: Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (only needed if you change `project.yml`).

```sh
# Domain logic and tests, no hardware needed
cd Packages/ShowRecorderKit
swift test

# The app (the generated Xcode project is committed)
open ShowRecorder.xcodeproj
```

To build from the command line without a signing team:

```sh
xcodebuild -project ShowRecorder.xcodeproj -scheme ShowRecorder \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

`scripts/verify.sh` runs the same checks as CI (package tests, macOS and iOS Simulator builds); set `DEVICE_ID` and `DEVELOPMENT_TEAM` to also build for a device. CI runs on every pull request on GitHub's free hosted `macos-26` runner and must pass before a PR merges.

`scripts/preflight.sh` builds an unsigned iOS Release app and checks what App Store Connect rejects a build for (icon, privacy manifest, export compliance, usage strings, version numbers); pass an `.xcarchive` to check one you already have. Set `BUILD_NUMBER` to override `CURRENT_PROJECT_VERSION` at build time. The marketing version stays in `project.yml`.

To run on a device, pick your own team in Xcode. After editing `project.yml`, run `xcodegen generate` and commit both files.

Debug and TestFlight builds include an 18-channel **Demo signal** input, so the record screen works in the simulator, or on a phone without a mixer. The App Store build never lists it.

## Releasing to TestFlight

Tag a version on `main` and push the tag:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The **Release** workflow archives the iOS app, signs it with cloud-managed signing, runs `scripts/preflight.sh` on the archive and uploads it to TestFlight. The tag sets the marketing version (`v0.1.0` becomes `0.1.0`); the build number is the run number plus the attempt (for example `57.1`), so re-running a tag uploads a new, higher build instead of failing as a duplicate. It only runs for tags pushed to this repository, never for pull requests or forks, and refuses a tag that isn't on `main`. The build appears in App Store Connect under TestFlight after Apple finishes processing it, usually 5 to 15 minutes.

Secrets (repository secrets, kept in Infisical project `showrecorder`, `prod`): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the `.p8` contents) and `DEVELOPMENT_TEAM`.

If an upload fails, open the run's **Archive**, **Check the archive** or **Upload to TestFlight** step. The same output is attached to the run as the `release-logs` artifact. Common causes:

| Message | Cause and fix |
|---|---|
| Preflight `FAIL:` line | Something App Store Connect would reject (icon, privacy manifest, compliance key, version). Run `scripts/preflight.sh` locally and fix it. |
| `Authentication failed` or `401` | The key, issuer or `.p8` secret is wrong, or the key was revoked. Make a new key and update the secrets. |
| `Cloud signing permission error` / `No profiles for 'dev.ericdahl.ShowRecorder'` | Cloud-managed signing needs an **Admin** API key; App Manager can upload but can't create the distribution certificate. A key's role can't be edited, so create a new Admin key and update `ASC_KEY_ID` and `ASC_KEY_P8`. |
| `bundle version must be higher` | A build with that number already exists. Re-run the workflow; the attempt number raises it. |
| `Tag ... is not on main` | Merge first, then tag the merged commit. |

## How the code is laid out

```
App/                         SwiftUI app (iOS, iPadOS, macOS), a thin layer
Packages/ShowRecorderKit/
  AudioIO                    The audio I/O boundary and a fake device for tests
  CoreAudioIO                Mac input (AUHAL) and iOS input (AVAudioSession + RemoteIO)
  Recording                  The Recorder: Armed state, meters, the real-time ring buffer,
                             writer thread, Shows, Takes, Take.json
  BroadcastWave              Stem writer (BWF, crash-safe headers, RF64)
  OSC                        Open Sound Control encoding and decoding
  MixerLink                  Mixer drivers (X-Air over UDP 10024) and the Mixer Link
  ShowReport                 Per-Show HTML report and CSV
  ProjectExport              DAW project export (Reaper first)
```

The audio callback never allocates, takes locks, logs or touches the file system ([ADR 0002](docs/adr/0002-swift-real-time-audio-path.md)). Most tests drive a full recording session with a fake audio device and a fake X-Air mixer on a loopback UDP port, then check the files on disk.

## Artwork

`design/render-artwork.swift` draws the app icon (iOS and Mac) and the 1280×640 social preview with Core Graphics: `swift design/render-artwork.swift design`. Copy the icons into `App/Assets.xcassets/AppIcon.appiconset` after changing them.

## Documentation

- [`CONTEXT.md`](CONTEXT.md): the project's vocabulary (Show, Take, Stem, USB Channel, Source, Mixer Link…). Code, issues and UI copy use these terms.
- [`docs/adr/`](docs/adr): architecture decisions, including the [level meter scale](docs/adr/0005-level-meter-scale.md).
- [Issue #1](https://github.com/ericdahl-dev/ShowRecorder/issues/1): the product requirements and user stories.

## License

Source-available under the [Functional Source License, Version 1.1, MIT Future License](LICENSE.md) (FSL-1.1-MIT). You can read, change and use the code for anything except a competing product. Each release becomes MIT two years after it's published. See [ADR 0003](docs/adr/0003-fsl-license-app-store.md).

Contributions are welcome. Because the app ships on the App Store, outside contributions will need a contributor agreement; open an issue before starting anything large.

Copyright 2026 Eric Dahl.
