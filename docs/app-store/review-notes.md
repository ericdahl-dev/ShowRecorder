# App Review notes (paste into App Store Connect, version 1.1, App Review Information > Notes; 1.0 notes in git history)

ShowRecorder records a live multitrack from a mixer connected over USB: a Behringer X Air (XR18 / MR18, 18 channels) or, new in 1.1, a Behringer X32 or Midas M32 (32 channels). One WAV file per mixer channel. No account and no sign-in. The same app runs on iPhone, iPad and Mac (macOS 26); on the Mac, Settings opens from ShowRecorder > Settings (Command-comma), and "Tap" below means click.

Testing without a mixer:
1. Open Settings (the gear, top right) > Recording > Audio interface and choose "Demo signal (18 channels)". It plays a test signal on 18 channels so every screen works without hardware. (If that option isn't listed, the app records from the built-in microphone, which works the same way with one channel.)
2. Close Settings. The record screen shows the level meters. Press the red button to record, the flag to add a Marker, and the square to stop (it asks first).
3. Tap "Shows" to see the recording. Each Show folder has one WAV per channel, a Show report and a Reaper project. On iPhone and iPad it is also in the Files app (On My iPhone > ShowRecorder); on a Mac, choosing a Drive folder in Settings > Storage puts a copy of every Show there, in Finder.

In-app purchases:
- "14-day Trial" is a free non-consumable that unlocks everything for 14 days. Start it from Settings > Pro > Start 14-day Trial. The screen before it states how long it lasts, what Free keeps afterwards (2 USB channels of the user's choice) and the price of Pro.
- "ShowRecorder Pro" is a one-time non-consumable (Family Sharing on): Settings > Pro > Buy Pro, or "See what Pro adds".
- Restore Purchases is in Settings > Pro.
- Free and Pro differ only when record is pressed. A recording in progress is never stopped or cut short by a Trial ending or by the Free limit.

What needs a mixer: the 32 channels of an X32 or M32, channel names from the Mixer Link, and Auto-gain (only shown with an X Air or X32 connected over USB and Mixer Link up; it moves the mixer's preamps, never during a recording). The Demo signal shows every other screen.

Network: the optional Mixer Link talks to the mixer on the local network (OSC over UDP port 10024 for X Air mixers, 10023 for the X32 and M32) to read channel names; Find Mixers asks the local network for X Air and X32 mixers. Nothing is sent to the internet and no data is collected.

Microphone permission is used to record the USB audio input (and the built-in microphone if the user chooses it).
