# ShowRecorder

A live multitrack recorder for iPhone, iPad and Mac that captures every channel of a digital mixer and labels each one from the mixer's own channel names and colors.

## Language

### Recording

**Show**:
One event being recorded, such as a gig, service or rehearsal. It carries the name, venue and notes, and holds one or more Takes.
_Avoid_: Session, project, event

**Take**:
One continuous recording from start to stop within a Show. It has a single sample timeline shared by all its Stems.
_Avoid_: Recording, session, clip

**Armed**:
The state in which the recorder is receiving audio and filling the Pre-roll but not yet writing a Take.
_Avoid_: Standby, ready, monitoring

**Pre-roll**:
The audio from just before record is pressed that becomes the start of the Take.
_Avoid_: Pre-record buffer, lookback

**Marker**:
A named point at a sample position within one Take, placed by the operator, a Snapshot load or a Mixer Trigger.
_Avoid_: Cue, locator, flag

**Stem**:
The audio file for one USB Channel within a Take, named after that channel's Source.
_Avoid_: Track file, channel file

**Template**:
A saved Show setup on one device: the Mixer address, Show name pattern, Pre-roll length and Mixer Trigger choices. One Template can be the default.
_Avoid_: Preset, profile, rig

### Storage

**Destination**:
A place a Take is written to. There are two, written at the same time, and neither is the primary.
_Avoid_: Backup, primary, target

**Drive**:
The external storage Destination, such as an SSD on the hub or a Mac volume.
_Avoid_: SSD, external disk

**Device**:
The internal storage Destination on the iPhone, iPad or Mac running the app.
_Avoid_: Internal, local, phone storage

**Copy**:
One Take's Stems as written to one Destination, as in "the Drive copy" and "the Device copy".
_Avoid_: Backup, mirror

**Gap**:
A stretch of a Take that is missing from one Copy because its Destination was unavailable. It is held as silence until Repaired.
_Avoid_: Dropout, hole

**Repair**:
Filling a Copy's Gaps from the other Copy after the Take ends.
_Avoid_: Sync, heal, restore

**Dropout**:
A stretch of a Take whose samples reached neither Copy because the recorder couldn't keep up. It is held as silence of the exact length and marked.
_Avoid_: Gap, glitch, overrun (in user-facing text)

### Levels

Levels are in dBFS: 0 is full scale, and silence reads -80. The scale and thresholds are in [ADR 0005](docs/adr/0005-level-meter-scale.md).

**Peak**:
The highest level a USB Channel reaches, measured per meter window of about 33 ms. The wide peak bar shows it: it jumps to a new peak and falls 15% per 1/30 s. The bar is green up to -18, yellow above -18 up to -6 and red above -6. A held-peak line across the bar holds 1.5 s, then falls 40 dB per second; it turns red and thicker (4 pt instead of 2 pt) above -3, so color is not the only cue. A level that reaches full scale is "clipping".
_Avoid_: Max, spike, transient

**Average level**:
How loud a USB Channel is on average, read like a VU meter: 0 VU is the level of a steady sine at its RMS, and the needle rises to 99% of a steady level in 300 ms with about 1% overshoot. The narrower average bar shows it. It is low (cool blue-gray) below -18, on target (green) from -18 to -15 inclusive and hot (orange) above -15. It is never red.
_Avoid_: RMS, loudness, volume, gain

**Target band**:
The range of Average level to aim for: -18 to -15 dBFS, fixed for now. A faint shaded band marks it on every lane. -18 dBFS is the digital reference for 0 VU in the EBU R 68 convention (SMPTE uses -20 dBFS), so the band is a convention, not a single standard. Live sources have peaks roughly 12 to 18 dB above their average, so this average leaves headroom below full scale, and 24-bit recording leaves enough resolution that recording quieter costs little.
_Avoid_: Sweet spot, safe zone, green zone

**Clip mark**:
A red triangle with an exclamation mark above a USB Channel's lane, shown when its Peak reaches 0.999 linear (within about 0.01 dB of full scale) in any meter window. A Peak of -0.5 dBFS is not a clip. It stays until the operator taps that lane, a new Take starts or the recorder is disarmed, and it stays after a Take ends.
_Avoid_: Clip (alone), overload, red light

### Mixer

**Mixer**:
The digital mixing desk the recorder connects to for audio and channel information, such as an XR18 or MR18.
_Avoid_: Console, desk, board

**Mixer Link**:
The connection over which the recorder reads Source names and colors, Snapshots and Mixer Triggers from the Mixer. It is separate from the USB audio, and recording never depends on it.
_Avoid_: OSC connection, control link

**USB Channel**:
One of the numbered audio channels the mixer sends to the recorder over USB. Every USB Channel is recorded in every Take.
_Avoid_: Input, track

**Source**:
Whatever the mixer routes to a USB Channel: an input channel, the aux input, a bus or the main mix. It carries the name and color shown for the Stem.
_Avoid_: Channel (unqualified), input

**Snapshot**:
A saved mixer scene stored on the mixer. Loading one can rename, re-route and re-mute channels.
_Avoid_: Scene, preset

**Mixer Trigger**:
A mixer control the operator has set aside to drive the recorder: one press is one action, such as start, stop or drop a Marker.
_Avoid_: Remote button, hotkey, GPI

### Licensing

**Pro**:
The one-time unlock that records every USB Channel and adds the Show report, Reaper export, Templates and Mixer Triggers.
_Avoid_: Premium, full version, paid tier

**Trial**:
A 14-day period after first launch in which everything Pro does is available.
_Avoid_: Demo, free trial (in UI copy say "14-day Trial")

**Free**:
What the app does without Pro or a Trial: records 2 USB Channels of the operator's choice.
_Avoid_: Lite, basic

**Show-Safe Promise**:
The rule that a Take never stops, and audio is never withheld, because of a Trial, limit or license; limits are checked only when record is pressed.
_Avoid_: Recording guarantee
