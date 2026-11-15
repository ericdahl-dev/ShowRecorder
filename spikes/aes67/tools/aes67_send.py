#!/usr/bin/env python3
"""A software AES67 sender for the spike (#1235): RTP L24, 48 kHz, 1 ms packets, to a multicast group.

Every sample is a pure function of (channel, sample index n), so check_wavs.py can check the WAVs bit for bit:
  channels 1..C-1: a sine at 375, 500, 750, 1000, 1500, 2000, 3000 Hz (each divides 48 kHz, so it repeats exactly)
  channel C:       a ramp, n mod 2^24, so any missing, repeated or misplaced sample shows
Faults can be injected to exercise the receiver's reorder and gap code: --drop-every, --swap-every, --dup-every.

  aes67_send.py --channels 8 --seconds 600 --sdp-out stream.sdp [--iface 127.0.0.1] [--group 239.69.83.67]
"""
import argparse
import math
import os
import random
import socket
import struct
import sys
import time

RATE = 48000
FREQS = [375, 500, 750, 1000, 1500, 2000, 3000]
PERIOD = 384  # LCM of 48000/f over FREQS
AMP = 0.5 * (2**23 - 1)


def sine_sample(ch, n):
    f = FREQS[ch % len(FREQS)]
    return int(round(AMP * math.sin(2 * math.pi * f * (n % PERIOD) / RATE)))


def b24(v):
    return (v & 0xFFFFFF).to_bytes(3, "big")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--group", default="239.69.83.67")
    p.add_argument("--port", type=int, default=5004)
    p.add_argument("--iface", default="127.0.0.1")
    p.add_argument("--ttl", type=int, default=0, help="0 keeps the packets on this host")
    p.add_argument("--channels", type=int, default=8)
    p.add_argument("--ptime-ms", type=float, default=1.0)
    p.add_argument("--seconds", type=float, default=10)
    p.add_argument("--pt", type=int, default=98)
    p.add_argument("--ts-start", type=int, default=None, help="first RTP timestamp (default random)")
    p.add_argument("--seq-start", type=int, default=None)
    p.add_argument("--drop-every", type=int, default=0)
    p.add_argument("--swap-every", type=int, default=0, help="send packet k+1 before packet k")
    p.add_argument("--dup-every", type=int, default=0)
    p.add_argument("--sdp-out")
    a = p.parse_args()

    C = a.channels
    frames = int(RATE * a.ptime_ms / 1000)
    # One 384-frame cycle of the sine channels, per frame, pre-packed.
    sines = [b"".join(b24(sine_sample(c, n)) for c in range(C - 1)) for n in range(PERIOD)]

    ts0 = a.ts_start if a.ts_start is not None else random.getrandbits(32)
    seq0 = a.seq_start if a.seq_start is not None else random.getrandbits(16)
    ssrc = random.getrandbits(32)

    if a.sdp_out:
        with open(a.sdp_out, "w") as f:
            f.write(
                "v=0\n"
                f"o=- {ssrc} 0 IN IP4 {a.iface}\n"
                "s=ShowRecorder AES67 spike sender\n"
                f"c=IN IP4 {a.group}/32\n"
                "t=0 0\n"
                "a=clock-domain:PTPv2 0\n"
                f"m=audio {a.port} RTP/AVP {a.pt}\n"
                f"i={C} channels\n"
                f"a=rtpmap:{a.pt} L24/{RATE}/{C}\n"
                f"a=ptime:{a.ptime_ms:g}\n"
                "a=ts-refclk:ptp=IEEE1588-2008:00-00-00-00-00-00-00-00:0\n"
                "a=mediaclk:direct=0\n"
                "a=recvonly\n"
            )

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(a.iface))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, a.ttl)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
    dest = (a.group, a.port)

    def build(k):
        n = k * frames
        ts = (ts0 + n) & 0xFFFFFFFF
        seq = (seq0 + k) & 0xFFFF
        hdr = struct.pack("!BBHII", 0x80, a.pt, seq, ts, ssrc)
        body = b"".join(sines[(n + i) % PERIOD] + b24(n + i) for i in range(frames))
        return hdr + body

    total = int(a.seconds * 1000 / a.ptime_ms)
    period = a.ptime_ms / 1000
    late_max = 0.0
    late_over_1ms = 0
    sent = dropped = swapped = duped = 0
    held = None
    start = time.perf_counter() + 0.05
    cpu0 = time.process_time()
    print(f"sending {C} ch, {frames} frames/packet, {total} packets to {a.group}:{a.port} via {a.iface}, "
          f"ts0 {ts0} seq0 {seq0}", flush=True)
    for k in range(total):
        deadline = start + k * period
        while True:
            d = deadline - time.perf_counter()
            if d <= 0:
                break
            if d > 0.0003:
                time.sleep(d - 0.0002)
        late = time.perf_counter() - deadline
        late_max = max(late_max, late)
        if late > 0.001:
            late_over_1ms += 1
        pkt = build(k)
        if a.drop_every and k % a.drop_every == a.drop_every - 1:
            dropped += 1
            continue
        if a.swap_every and k % a.swap_every == a.swap_every - 2 and k + 1 < total:
            held = pkt
            continue
        s.sendto(pkt, dest)
        sent += 1
        if held is not None:
            s.sendto(held, dest)
            sent += 1
            swapped += 1
            held = None
        if a.dup_every and k % a.dup_every == a.dup_every - 1:
            s.sendto(pkt, dest)
            duped += 1
    cpu = time.process_time() - cpu0
    print(f"done: sent {sent} (dropped {dropped}, swapped {swapped}, duplicated {duped}); "
          f"pacing: worst {late_max*1000:.2f} ms late, {late_over_1ms} packets >1 ms late; "
          f"sender cpu {cpu / max(a.seconds, 1e-9) * 100:.1f}%", flush=True)


if __name__ == "__main__":
    sys.exit(main())
