# ShowRecorder: notes for agents

## TestFlight is live (since 2026-10-07)

- App Store Connect app record `ShowRecorder`, bundle ID `dev.ericdahl.ShowRecorder`, team `5HR8E5CWR7` (a paid team, although Xcode labels it "Personal Team").
- Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`: it archives the iOS app, signs it with cloud-managed signing, runs `scripts/preflight.sh` on the archive and uploads to TestFlight. Builds so far: `v0.1.0`, `v0.1.1`, `v0.1.2`. The README section "Releasing to TestFlight" has the details and a table for reading a failed upload.
- iOS only. The Mac app is not in TestFlight.
- The build number is `run_number.run_attempt`; the marketing version comes from the tag. Never edit `CURRENT_PROJECT_VERSION` in `project.yml` for a release.
- Secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `DEVELOPMENT_TEAM`) are GitHub repo secrets, sourced from Infisical project `showrecorder` (`prod`). The key must be an **Admin** App Store Connect key, or cloud signing fails. Never print or commit them.
- Run `scripts/preflight.sh` before anything that touches the icon, Info.plist, the privacy manifest or entitlements.
- The Demo signal is compiled into Release but offered only in Debug and TestFlight builds, never the App Store build (`DemoSignalAvailability`).

## Rules

- Do not push a release tag unless Eric asks for it in this conversation; a tag uploads a build to his testers.
- CI must be green on `main` before a tag. Tag a commit that is on `main`.
- Eric tests on a real iPhone through TestFlight. Say plainly when something has only been checked in the Simulator or by tests.
- Open pull requests with `gh pr merge --auto --squash`.
- `./scripts/verify.sh` must pass before a PR.
