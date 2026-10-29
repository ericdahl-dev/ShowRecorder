# Reply to a Guideline 2.1 "can't test without hardware" rejection

Ready to paste into the Resolution Center if App Review rejects 1.1 under Guideline 2.1 (App Completeness) or 2.1(a) because it needs a mixer or other hardware to test. Eric's call (2026-10-13): no video; point to the Demo signal. Adjust the first line to the reviewer's wording.

The Demo signal is offered when StoreKit's `AppTransaction` says the build is in the sandbox environment (`DemoSignalAvailability`): Debug and TestFlight builds, and App Review if it reviews in the sandbox, as it does for in-app purchases. That last part isn't confirmed. If a reviewer reports there's no Demo signal, the built-in microphone fallback in step 1 still works, and the next build needs another way to show it in review.

---

Hello, and thank you for reviewing ShowRecorder.

You can review the whole app without a mixer or any other hardware. The build under review includes a Demo signal for this (it is for testing, so the version on the App Store doesn't show it):

1. Open Settings (the gear, top right; on a Mac, ShowRecorder > Settings) > Recording > Audio interface, and choose "Demo signal (18 channels)". It plays a test signal on 18 channels.
2. Close Settings. The record screen shows 18 level meters. Press the red button to record, the flag to add a Marker, and the square to stop.
3. Tap "Shows" to see the recording: one WAV file per channel, a Show report and a Reaper project. On iPhone and iPad they are also in the Files app (On My iPhone > ShowRecorder).
4. The in-app purchases are in Settings > Pro: the free 14-day Trial, ShowRecorder Pro, and Restore Purchases.
5. With a paired Apple Watch, open ShowRecorder on the watch while the iPhone is Ready on the Demo signal: Record, Marker and Stop (a one-second press and hold) control the iPhone.

If the Demo signal isn't listed, choose the built-in microphone in the same place: it uses the same screens with one channel.

Only these need a real mixer: the channel names and colors it reads from the mixer over the local network, and the 32 channels of an X32 or M32. Everything else, including recording, Markers, the files, the Show report, the purchases and the watch app, works with the Demo signal.

If anything doesn't work as described, please tell us what you see and we'll fix it right away.

---

Before sending: check that step 1's path still matches the build under review, and drop step 5 if the version has no watch app.
