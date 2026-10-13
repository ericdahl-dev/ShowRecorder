# Developing ShowRecorder

For contributors and agents. The [README](../README.md) is for people using the app. Rules for agents are in [`CLAUDE.md`](../CLAUDE.md); the vocabulary is in [`CONTEXT.md`](../CONTEXT.md).

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

`scripts/verify.sh` runs the checks CI runs, but only those the branch's changes need: the vocabulary check, package tests, macOS and iOS Simulator builds, and the website's lint, tests and build. It prints its plan first; a docs-only change needs none (except `docs/release-notes/`, which the site's changelog test reads, so it runs the site checks), and a change to `verify.sh`, CI or an unlisted path runs everything. `VERIFY_ALL=1` runs everything, `VERIFY_QUICK=1` skips the macOS and iOS app builds and leaves them to CI (everything else runs as the changes need; a signed device build is skipped too, and CI doesn't run that one), `VERIFY_PLAN_ONLY=1` prints the plan and stops, and the header of `verify.sh` lists which paths pick which checks. Set `DEVICE_ID` and `DEVELOPMENT_TEAM` to also build for a device. The package tests, both app builds and the website run side by side, as CI runs them: each writes its own log, and at the end `verify.sh` prints each step's result and time and the log of any that failed. Each app build has its own build folder (`build/dd-mac`, `build/dd-ios`, `build/dd-device`; `DERIVED_DATA` changes the `build/dd` prefix), so they don't wait on each other; an older `build/dd` can be deleted. Ctrl-C stops every step. CI runs on every pull request on GitHub's free hosted `macos-26` runner and must pass before a PR merges.

### One heavy build at a time

Several agents often work on this Mac at once, in their own worktrees. Builds run side by side starve each other, and tests with time limits fail under the load. So every heavy build takes one lock, shared by all worktrees of the repo (`.git/verify.lock`), and a second one waits its turn and says so: "== Waiting for another build on this Mac to finish". Builds that hold the lock run at low priority (`nice -n 10`).

- `scripts/verify.sh` takes the lock itself. `VERIFY_PLAN_ONLY=1` never waits.
- `swift build`, `swift test`, `swift run` and `xcodebuild` builds and tests take it through the shims in `scripts/bin`. **Put `scripts/bin` first on your `PATH`** so they're used:

  ```sh
  export PATH="$HOME/Documents/GitHub/ericdahl.dev/ShowRecorder/scripts/bin:$PATH"
  ```

  Light commands run straight away: `swift --version`, `swift package describe` or `resolve`, `xcodebuild -list`, `-version`, `-showdestinations`, `-showsdks`. So does anything outside this repo; the shims then just run `/usr/bin/swift` or `/usr/bin/xcodebuild`.
- Builds `verify.sh` starts itself don't wait for it (`SHOWRECORDER_BUILD_LOCK_HELD=1`).
- **Every build is capped at N compile jobs,** so one build alone doesn't take the whole CPU either. N is `SHOWRECORDER_BUILD_JOBS`, or this Mac's cores less 4 (at least 1): 8 on a 12-core Mac.
  - The shims add `-j N` to `swift build`, `test` and `run` (right after the subcommand), and `-jobs N` to `xcodebuild`, unless you gave a count yourself.
  - `verify.sh` runs its package tests and both app builds at once, so it splits N between them (8 / 3 = 2 each). It calls the shims by path, so the cap holds even without `scripts/bin` on PATH.
- A queued build can take longer than an agent's 10-minute command limit, so agents run builds and tests as background tasks.
- Stop a build with Ctrl-C, or by signaling its whole process group (`kill -- -PGID`). A signal to `lockf` alone frees the lock while the build goes on, and the next build starts beside it.
- `scripts/build-lock.sh` has the details; `scripts/test-verify-lock.sh` and `scripts/test-build-lock.sh` test it with stand-in tools and a lock of their own, so they never wait on a real build.

`scripts/preflight.sh` builds an unsigned iOS Release app and checks what App Store Connect rejects a build for (icon, privacy manifest, export compliance, usage strings, version numbers); pass an `.xcarchive` to check one you already have. Set `BUILD_NUMBER` to override `CURRENT_PROJECT_VERSION` at build time. The marketing version stays in `project.yml`.

To run on a device, pick your own team in Xcode. After editing `project.yml`, run `xcodegen generate` and commit both files.

Debug and TestFlight builds include an 18-channel **Demo signal** input, so the record screen works in the simulator, or on a phone without a mixer. The App Store build never lists it.

## Releasing to TestFlight

Tag a version on `main` and push the tag:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

**Release branches.** While a version is in App Review, its fixes are kept apart from new work. `release/1.0` was cut from `v1.0.1`. A fix for 1.0 is merged to `main` first, then cherry-picked onto `release/1.0` (in a pull request to that branch, so CI runs) and tagged there, for example `v1.0.2`. New features merge only to `main` and ship in 1.1.x tags (`v1.1.1`, `v1.1.2`, …), which TestFlight lists apart from 1.0.x. When 1.1 goes to App Review, cut `release/1.1` from its tag the same way and move `main` to 1.2. Never merge `main` into a release branch. A tag runs the `release.yml` of the commit it points to, so a fix to that workflow must be cherry-picked to the release branch too.

The **Release** workflow runs two jobs side by side, one for iOS and one for macOS. Each archives the app, signs it with one fixed Apple Distribution certificate (see below), runs `scripts/preflight.sh` on the archive and uploads it to TestFlight. A failure in one never stops the other. Both builds share the tag's version and build number; App Store Connect keeps them apart by platform. The tag sets the marketing version (`v0.1.0` becomes `0.1.0`); the build number is the run number plus the attempt (for example `57.1`), so re-running a tag uploads a new, higher build instead of failing as a duplicate. It only runs for tags pushed to this repository, never for pull requests or forks, and refuses a tag that isn't on `main` or a `release/` branch. The build appears in App Store Connect under TestFlight after Apple finishes processing it, usually 5 to 15 minutes.

Secrets (repository secrets, kept in Infisical project `showrecorder`, `prod`): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the `.p8` contents), `DEVELOPMENT_TEAM`, `DIST_CERT_P12_BASE64` (an Apple Distribution certificate with its private key, exported as `.p12` and run through `base64`) and `DIST_CERT_PASSWORD` (the `.p12` password). The Mac job also needs `MAC_INSTALLER_CERT_P12_BASE64` and `MAC_INSTALLER_CERT_PASSWORD`: a **Mac Installer Distribution** certificate (developer.apple.com > Certificates > +, or Xcode > Settings > Accounts > Manage Certificates), exported the same way. It signs the installer package a Mac upload is. Without those two secrets the Mac job prints a warning and stops, and the iOS job still uploads. The Mac job uses the profile `ShowRecorder CI Mac App Store` (type `MAC_APP_STORE`), which `scripts/ci_profile.py` makes the same way as the iOS one.

The iPhone app embeds the Live Activity widget extension (#136), bundle ID `dev.ericdahl.ShowRecorder.LiveActivity`. The iOS job signs it with a second profile, `ShowRecorder CI Live Activity App Store`. Each target picks its profile from `APP_PROFILE_NAME` or `EXTENSION_PROFILE_NAME` (see `project.yml`), so the workflow no longer passes one `PROVISIONING_PROFILE_SPECIFIER` for both. On the first release after this change, `ci_profile.py` registers the extension's bundle ID in the developer account (`CREATE_BUNDLE_ID=1`). The Mac app embeds no extension.

**Why a fixed certificate:** the first setup used cloud-managed signing, which asks Apple for a new development certificate on every run (each run is a new machine). Apple caps certificates per account, so releases eventually failed with `Your account has reached the maximum number of certificates`. Now each run imports the same Distribution certificate into a temporary keychain, `scripts/ci_profile.py` fetches (or makes) the App Store profile `ShowRecorder CI App Store` through the App Store Connect API, and the archive is signed manually. Nothing is created per run. The certificate expires after a year: make a new one (Keychain Access > Request a Certificate from a Certificate Authority, then developer.apple.com > Certificates > Apple Distribution), export it as `.p12`, and update the two secrets. Keep an encrypted copy of the `.p12` and its password off the Mac.

After the upload, the workflow waits for Apple to process the build (up to 40 minutes), then sets its **What to Test**, adds it to the external TestFlight group and submits it for Beta App Review, through the same App Store Connect key (`scripts/testflight_notes.py`). The text is `docs/release-notes/<tag>.md` when that file exists (write it in plain words before tagging, for example `docs/release-notes/v0.1.12.md`: what is new, then what to try), otherwise the titles of the pull requests merged since the previous tag, otherwise a fixed line; it is cut to Apple's 4000 characters. Internal testers get the build as soon as it is processed; external testers get it once Beta App Review approves it. If this step fails it prints a warning and the release still succeeds: set it by hand in App Store Connect.

If an upload fails, open the run's **Archive**, **Check the archive** or **Upload to TestFlight** step. The same output is attached to the run as the `release-logs` artifact. Common causes:

| Message | Cause and fix |
|---|---|
| Preflight `FAIL:` line | Something App Store Connect would reject (icon, privacy manifest, compliance key, version). Run `scripts/preflight.sh` locally and fix it. |
| `Authentication failed` or `401` | The key, issuer or `.p8` secret is wrong, or the key was revoked. Make a new key and update the secrets. |
| `Cloud signing permission error` / `No profiles for 'dev.ericdahl.ShowRecorder'` | Cloud-managed signing needs an **Admin** API key; App Manager can upload but can't create the distribution certificate. A key's role can't be edited, so create a new Admin key and update `ASC_KEY_ID` and `ASC_KEY_P8`. (Now the key must still be able to create profiles.) |
| `Choose a certificate to revoke` | Only from the old cloud-managed setup. If it appears, the workflow is not using the fixed certificate: check `DIST_CERT_P12_BASE64` and `DIST_CERT_PASSWORD` exist. |
| `security import` fails, or `No Apple Distribution identity` | The `.p12` secret is empty or the password is wrong. Re-export it and update both secrets. |
| `serial mismatch` from `ci_profile.py` | The certificate in the secret was revoked or isn't in this team. Make and store a new one. |
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

- [`CONTEXT.md`](../CONTEXT.md): the project's vocabulary (Show, Take, Stem, USB Channel, Source, Mixer Link…). Code, issues and UI copy use these terms.
- [`docs/adr/`](adr): architecture decisions, including the [level meter scale](adr/0005-level-meter-scale.md).
- [Issue #1](https://github.com/ericdahl-dev/ShowRecorder/issues/1): the product requirements and user stories.

## How it behaves, in detail

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
- **Meters and levels** ([ADR 0005](adr/0005-level-meter-scale.md)):
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

Also built since this list was first written: Templates (venue setups), Find mixers, a sample-rate choice up to 96 kHz, crash recovery of a cut-off Take, Dropouts for interrupted input, and Pro, the 14-day Trial and the Free limit (on in every build since #371). Not built yet: Mixer Triggers, Snapshot Markers, Mixer Link over USB, sharing a Show, and editing a Show afterward. See the [open issues](https://github.com/ericdahl-dev/ShowRecorder/issues) and the [App Store launch milestone](https://github.com/ericdahl-dev/ShowRecorder/milestone/1).

