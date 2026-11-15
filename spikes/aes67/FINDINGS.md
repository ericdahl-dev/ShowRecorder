# AES67 spike: findings (#1235)

## Status (2026-11-15, paused)

**Works (measured on macOS, multicast over loopback lo0 with TTL 0; the en0 counters show nothing left the Mac):**
- `aes67rec` (the Swift package here) parses the SDP, joins 239.69.83.67:5004, puts packets back in order by RTP timestamp, fills gaps with silence, and writes one 24-bit WAV per channel. 8 unit tests pass.
- `tools/aes67_send.py` sends L24/48000/8 at 1 ms ptime. `tools/check_wavs.py` checks the WAVs bit for bit: channels 1-7 are sines, and channel 8 is a ramp of the sample index.
- A clean 10 s run crossed the 16-bit sequence wrap and the 32-bit timestamp wrap: 10,000 packets, 0 lost, 0 reordered, 0 gaps, and all 8 WAVs bit-exact. Receiver CPU was 1.4% of one core, with 8 MB resident.
- A 20 s run with faults injected: the receiver's counts match what the sender injected. 20 dropped = 20 lost = 20 gaps (960 frames), 198 swapped = 198 reordered, and 39 duplicated = 39 duplicates. The WAVs are 960,000 frames long, as expected; the only wrong samples are the silent ones in the 960 dropped frames, and no sample shifted. Receiver CPU was 2.3%.
- Clock drift: -0.7 ppm against the kernel's monotonic arrival stamps (sender and receiver are on the same machine, so near 0 is expected), but -195 ppm against the wall clock, because macOS slews the wall clock. Any clock work must use monotonic time.
- Jitter in the 10 s run (mostly the Python sender's pacing): transit spread p50 0.5 ms, p99 1.0 ms, p99.9 2.8 ms, max 6.2 ms. The 20 ms reorder window is ample here.

**Left:**
- The 10-minute run (loss, reordering, jitter, CPU) and the bit-exact check of its WAVs.
- A short interop run with ffmpeg as an independent sender (GStreamer isn't installed).
- Answers to the four questions: following the PTP clock, CPU, 4 streams (32 channels), and the iOS port (multicast entitlement, USB-C Ethernet). Loopback says nothing about loss on a real network.
