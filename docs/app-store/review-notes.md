# App Review notes (paste into App Store Connect, version 1.0, App Review Information > Notes)

ShowRecorder records a live multitrack from a Behringer X Air mixer (XR18 / MR18) connected over USB: one WAV file per mixer channel. No account and no sign-in.

Testing without a mixer:
1. Open Settings (the gear, top right) > Recording > Input and choose "Demo signal (18 channels)". It plays a test signal on 18 channels so every screen works without hardware. (If that option isn't listed, the app records from the built-in microphone, which works the same way with one channel.)
2. Close Settings. The record screen shows the level meters. Press the red button to record, the flag to add a Marker, and the square to stop (it asks first).
3. Tap "Shows" to see the recording. Each Show folder (also in the Files app, On My iPhone > ShowRecorder) has one WAV per channel, a Show report and a Reaper project.

In-app purchases:
- "14-day Trial" is a free non-consumable that unlocks everything for 14 days. Start it from Settings > Pro > Start 14-day Trial. The screen before it states how long it lasts, what Free keeps afterwards (2 USB channels of the user's choice) and the price of Pro.
- "ShowRecorder Pro" is a one-time non-consumable (Family Sharing on): Settings > Pro > Buy Pro, or "See what Pro adds".
- Restore Purchases is in Settings > Pro.
- Free and Pro differ only when record is pressed. A recording in progress is never stopped or cut short by a Trial ending or by the Free limit.

Network: the optional Mixer Link talks to the mixer on the local network (OSC over UDP port 10024) to read channel names; Find mixers asks the local network for X Air mixers. Nothing is sent to the internet and no data is collected.

Microphone permission is used to record the USB audio input (and the built-in microphone if the user chooses it).
