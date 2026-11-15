# AES67 spike: findings (#1235)

A throwaway spike, not app code. It receives one AES67 stream (RTP, L24, 48 kHz, 8 channels, 1 ms packets, multicast) and writes one 24-bit WAV per channel. It runs on macOS against a software sender on the same Mac.

**Measured** means run here on 2026-11-15, on an M5 Pro Mac running macOS 27, with multicast on loopback (lo0, TTL 0). The en0 counters show the stream never went out on the LAN. **Reasoned** means worked out, not run. **Unverified** means not checked on a device or against a primary source.

Loopback can't lose or reorder packets the way a real switch, Wi-Fi bridge or a busy USB-C Ethernet adapter can. So the loss and reordering numbers below show the receiver's bookkeeping is right; they say nothing about a real Dante network. The jitter here mostly comes from the Python sender's timing.

## What's here

| Path | What |
|---|---|
| `Sources/AES67Core` | SDP parsing, RTP header parsing, sequence and timestamp unwrapping, the reassembler (orders packets by RTP timestamp, waits 20 ms for late ones, then writes silence for the gap), loss, jitter and drift stats, and the per-channel WAV writer |
| `Sources/aes67rec` | The CLI: joins the group with BSD sockets (`SO_REUSEPORT`, 4 MB `SO_RCVBUF`, kernel arrival stamps on the monotonic clock), then records and prints a JSON report |
| `Tests/AES67CoreTests` | 8 unit tests: SDP, RTP header, wraparound, reorder, gap, duplicate, WAV bytes |
| `tools/aes67_send.py` | The sender: 1 ms packets, a random first sequence number and timestamp, and options to drop, swap or duplicate packets. Channels 1-7 are sines at 375-3000 Hz; channel 8 is a ramp of the sample index, so every sample can be checked |
| `tools/check_wavs.py` | Checks the WAVs bit for bit against what the sender sent |

```sh
swift build -c release
python3 tools/aes67_send.py --seconds 0 --sdp-out /tmp/s.sdp          # write the SDP
.build/release/aes67rec --sdp /tmp/s.sdp --out /tmp/rec --stats /tmp/rec.json &
python3 tools/aes67_send.py --seconds 600 --sdp-out /tmp/s.sdp
python3 tools/check_wavs.py /tmp/rec
```

## Does a 10-minute recording come out clean? Yes (measured, on loopback)

8 channels, 600 s, with nothing else heavy running on the Mac:

| | |
|---|---|
| Packets | 600,000 sent, 600,000 received; 0 lost, 0 reordered, 0 duplicated, 0 gaps, 0 late |
| WAVs | 8 × 28,800,000 frames (600.000 s, 86.4 MB each), **bit-exact** on every channel, across the 16-bit sequence wrap (9 times) and the 24-bit ramp wrap |
| Jitter (arrival minus RTP time, drift removed) | p50 34 µs, p99 81 µs, p99.9 163 µs, max 9.8 ms. RFC 3550 jitter ended at 11 µs, with a highest value of 0.8 ms |
| Longest gap between packets | 10.8 ms. The sender reports its worst send was 9.75 ms late, with 167 packets more than 1 ms late, so that maximum is the sender's own stall |
| Reorder buffer | never held more than 1 packet; the 20 ms window was never used |
| Drift | -0.02 ppm against the kernel's monotonic arrival stamps (one machine, one clock). Against the wall clock it was +184 ppm, because macOS slews the wall clock, so any clock work must use monotonic time |

The bookkeeping and fault handling were checked separately (measured). In a 20 s run, the sender dropped every 997th packet, swapped every 101st pair and duplicated every 503rd. The receiver reported exactly what was injected: 20 lost, 20 gaps (960 frames of silence), 198 reordered and 39 duplicates. The WAVs had the right length, the only wrong samples were the silence in those 960 frames, and no sample shifted.

An independent sender was also checked (measured). ffmpeg (libavformat 63) sent 2-channel `pcm_s24be` RTP for 10 s, using its own packet sizes (156 and 204 frames, not 1 ms). The receiver wrote 480,000 frames per channel with 0 lost, and the channels measured 499.9 Hz and 1499.9 Hz, the right pitch and order. So the byte order and channel interleave aren't a bug the spike's own sender and receiver happen to share. ffmpeg wouldn't send multicast through lo0: nothing arrived, and the en0 counter rose by about the stream's size, so this check used unicast to 127.0.0.1. GStreamer isn't installed.

## How much CPU does it take? About 2% of one core for 8 channels (measured on the Mac)

- Over the 10-minute run: 11.5 CPU seconds in 600 s, so **1.9% of one M5 Pro core** for 1,000 packets/s and 8 WAVs. `ps` samples every 10 s ranged from 0.9% to 2.4%.
- This is one thread doing everything: receive, reorder, swap the byte order, and write to the files. Nothing was tuned: the WAV writer appends byte by byte and uses `FileHandle.write` with 64 KB per channel.
- Memory: 7 MB at the start and 38 MB at the end. The growth is the spike's own jitter statistics, which keep 16 bytes per packet. The recording path's memory is flat.

## How much work is following the PTP clock? A recorder doesn't need to (reasoned)

AES67 senders are locked to a PTPv2 grandmaster, and their RTP timestamps count samples of that clock. The SDP's `a=mediaclk:direct=<offset>` gives the offset, and `a=ts-refclk` names the grandmaster ([AES67](https://en.wikipedia.org/wiki/AES67); [Hildebrand, AES67/ST 2110 synchronization](https://www.aimsalliance.org/wp-content/uploads/2022/11/Clocking-Synchronization-in-RTP-RAVENNA_AES67-ST2110-AVB-and-IPMX-Andreas-Hildebrand.pdf)). For a recorder, that means:

- **Placing samples needs no PTP.** The spike writes sample N where RTP timestamp origin+N says. The files come out at the sender's clock rate with no resampling, whatever the phone's clock does. The 10-minute run did exactly that.
- **Lining up 4 streams needs no PTP either,** provided all the senders lock to the same grandmaster. Their `timestamp - mediaclk offset` is then one shared timeline. Line each stream up by that value, put the same timestamp at sample 0 of every file, and fill gaps per stream.
- **PTP matters only if we:** (a) mix network audio with the iPhone's own clock (live monitoring out of the phone's speaker or headphones, or recording a USB mixer at the same time); (b) want to show that a stream is "locked to grandmaster X"; or (c) want to reject a stream whose timestamps don't match PTP time. Case (a) is an adaptive resampler driven by a drift estimate, and the spike's `TimingStats.driftPPM` already measures that drift without PTP.
- **Cost:** a passive listener that reads PTP Announce and Sync messages to show the grandmaster and lock state would take about 1-2 days. A full PTPv2 follower, with delay requests, a servo and software timestamps, would take about 1-2 weeks and isn't needed for recording. On macOS a normal user could bind UDP 319 and 320 and join 224.0.1.129 (measured). On iOS this is unverified; the same multicast entitlement would cover it.

## What would 4 streams (32 channels) need? (reasoned from the 1-stream numbers)

- **Network:** each 8-channel, 1 ms flow is 1,000 packets/s of 1,164-byte payloads, about 10 Mbit/s on the wire with the RTP, UDP, IP and Ethernet headers. Four flows come to 4,000 packets/s and about 40 Mbit/s, fine for any 100 Mbit or gigabit USB-C Ethernet adapter. Dante Brooklyn II sends AES67 only in 239.x and at most 8 channels per flow (#1234). 4 flows are 4 joins on one socket or four sockets.
- **CPU:** 4 × 1.9% is about 8% of one M5 Pro core as written. An iPhone core is slower, and the byte-by-byte writer is easy to speed up, so expect roughly 5-15% of one core. That's unverified until it runs on a phone.
- **Disk:** 32 × 144 KB/s = 4.6 MB/s, about 16.6 GB an hour. That's the same as a 32-channel USB recording at 48 kHz/24-bit.
- **Code beyond the spike:** a per-stream reassembler (this one), one timeline across the flows built from `mediaclk`, a "flow missing" state for each flow, and SDP entry, typed or pasted. SAP discovery on 239.255.255.255:9875 is extra (about 2 days).
- **Real-time rules (ADR 0002):** the spike receives and writes files on one thread. In the app, the receive thread should only copy packets into a lock-free ring. Ordering and file writes happen off it, as the USB path does now.

## The iOS port: realistic, with risks outside the code (unverified on a device)

- **Entitlement:** `com.apple.developer.networking.multicast` is restricted; Apple approves it on request, and applying for it is one of the first steps Eric chose (#1235). Without it, iOS won't let the app join a multicast group. The app also needs `NSLocalNetworkUsageDescription` and the user's yes at the local-network prompt.
- **Hardware:** an iPhone or iPad with USB-C and a class-compliant USB-C Ethernet adapter. To stay off Wi-Fi, join on the Ethernet interface by name (`IP_BOUND_IF` / `imr_interface`). The spike already picks the interface (`--iface`).
- **Sockets:** the spike uses plain BSD sockets, which exist on iOS. Network.framework's `NWConnectionGroup` is the other option. Both need the entitlement.
- **Background:** whether the app keeps receiving with the screen locked during a show is the biggest unknown. Today the app stays alive through its audio session; with no USB input active, that is unverified.
- **No Dante hardware here.** We haven't tested against a real Brooklyn II or a real network. Ultimo and UltimoX Dante devices can't send AES67 at all (#1234). Dante Controller setup by the user is a support burden.

## Verdict

Recording 32 channels of AES67 on an iPhone looks **realistic technically**. Receiving, ordering and writing a stream is small and cheap: about 2% of one Mac core per 8 channels, and bit-exact for 10 minutes. A recorder doesn't need a PTP stack. The risks are outside the code: the entitlement approval, behavior in the background, real-network loss over USB-C Ethernet, and access to AES67-capable Dante hardware for testing.

Rough effort for 32 channels in the app, after the entitlement arrives and with a test device and AES67 sender on hand:

| Work | Estimate |
|---|---|
| Receiver into ShowRecorderKit as an input: ring buffer, ADR 0002 split, tests | 1 week |
| 4 flows on one timeline, missing-flow state, SDP entry (typed or pasted) | 1 week |
| UI, availability rule (Debug first), Pro gating, guide | 1 week |
| Device Takes on a real Dante/AES67 network, background behavior, adapter quirks | 1 week+ |
| Optional: SAP discovery (2 days); passive PTP lock display (1-2 days) | |

So about **4-5 weeks**, plus however long Apple takes with the entitlement. Before building, the cheap next step is #1234 step 1 (Mac plus Dante Virtual Soundcard, no code). Then repeat this spike over a real switch with a Brooklyn II device, if we can borrow one.
