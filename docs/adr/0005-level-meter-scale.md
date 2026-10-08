# Level meter scale and thresholds

Each USB Channel's meter shows a VU-style Average level against a Target band of -18 to -15 dBFS, with a separate Peak bar, so the operator sets gain for clean peaks and a healthy average rather than for the loudest hit. The terms are defined in [CONTEXT.md](../../CONTEXT.md#levels); this records why.

**The band.** -18 dBFS is the digital reference for 0 VU in the EBU R 68 convention; SMPTE uses -20 dBFS. Neither is a single standard, so we picked -18 and made the band 3 dB wide, -18 to -15. Live sources have peaks roughly 12 to 18 dB above their average, so an average in the band keeps peaks below full scale with headroom. Stems are 24-bit, so recording quieter costs little, while clipping can't be undone. The band is fixed until a setting is built.

**The average.** It is a VU reading, calibrated so 0 VU is the RMS of a steady sine (the average rectified level times pi/(2*sqrt 2), about 1.11). The needle is second-order: it reaches 99% of a steady level in 300 ms with about 1% overshoot (damping 0.826, natural frequency 13.969 rad/s) and falls the same way. Because it is a filter in time, the reading does not depend on how audio is cut into windows.

**The colors.** The average bar is keyed to the band (low, on target, hot) and is never red, because a high average is not a fault. The peak bar is keyed to the Peak itself: green up to -18, yellow above -18 up to -6, red above -6. The held-peak line turns red and thicker above -3 so color is not the only cue.

**The clip mark.** It sets at a Peak of 0.999 linear, within about 0.01 dB of full scale, so -0.5 dBFS does not count. It is kept by the Recorder, not the screen, so it survives a view change and the end of a Take.

**What the Take records.** `Take.json` stores per-USB-Channel `peakDbfs` and `averageDbfs` (-80 for a silent channel; absent in Takes made before this), and the report shows them in a Levels table. The peak is the loudest meter window's peak. The average is the power average of the VU levels: the square root of the frame-weighted mean of the squares of each window's level. Both are counted from when record is pressed, not from the Pre-roll. `Channels.csv` and the Reaper project do not carry levels.

## Consequences

- The numbers live in `VUMeter.swift`, `ChannelMeter.swift` and `TakeLevels.swift` in `Recording`, in `Recorder.clipLevel` and `Recorder.clippedChannels`, and in the view `App/MeterGrid.swift`. Changing one is a change to this ADR.
- A channel can be on target and still show a red peak bar; the two bars answer different questions.
- Takes made before levels were recorded have no level data, so the report has nothing to show for them.
