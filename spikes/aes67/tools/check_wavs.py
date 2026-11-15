#!/usr/bin/env python3
"""Checks the receiver's WAVs bit for bit against what aes67_send.py sent.

The last channel is the ramp (n mod 2^24); its first sample gives the sample index n0 the recording starts at.
Every other channel must equal the sender's sine at n0+i. Prints, per channel: length, wrong samples, silent
(zero) samples where audio was expected, and the frequency from zero crossings.

  check_wavs.py DIR            (expects DIR/aes67-ch01.wav ...)
"""
import glob
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aes67_send import PERIOD, RATE, sine_sample  # noqa: E402


def read_wav(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE", path
    assert int.from_bytes(data[34:36], "little") == 24, "not 24-bit"
    size = int.from_bytes(data[40:44], "little")
    return data[44:44 + size]


def s24(b, i):
    v = int.from_bytes(b[i * 3:i * 3 + 3], "little")
    return v - (1 << 24) if v & 0x800000 else v


def zero_crossing_hz(b, seconds=1.0, skip=0):
    n = min(len(b) // 3 - skip, int(RATE * seconds))
    ups = 0
    prev = s24(b, skip)
    for i in range(skip + 1, skip + n):
        v = s24(b, i)
        if prev < 0 <= v:
            ups += 1
        prev = v
    return ups / (n / RATE)


def main():
    d = sys.argv[1]
    files = sorted(glob.glob(os.path.join(d, "aes67-ch*.wav")))
    C = len(files)
    chans = [read_wav(f) for f in files]
    ramp = chans[-1]
    frames = len(ramp) // 3
    n0 = int.from_bytes(ramp[0:3], "little")
    result = {"channels": C, "frames": frames, "seconds": frames / RATE, "n0": n0, "perChannel": []}
    chunk = PERIOD * 500
    for c, b in enumerate(chans):
        is_ramp = c == C - 1
        if is_ramp:
            def expect_bytes(start, count):
                return b"".join(((n0 + start + i) & 0xFFFFFF).to_bytes(3, "little") for i in range(count))
        else:
            pattern = b"".join((sine_sample(c, n) & 0xFFFFFF).to_bytes(3, "little") for n in range(PERIOD))
            def expect_bytes(start, count, pattern=pattern):
                off = (n0 + start) % PERIOD
                reps = (off + count) // PERIOD + 2
                return (pattern * reps)[off * 3:(off + count) * 3]
        wrong = silent = 0
        first_wrong = None
        for start in range(0, frames, chunk):
            count = min(chunk, frames - start)
            got = b[start * 3:(start + count) * 3]
            exp = expect_bytes(start, count)
            if got == exp:
                continue
            for i in range(count):
                g = got[i * 3:i * 3 + 3]
                if g != exp[i * 3:i * 3 + 3]:
                    wrong += 1
                    if g == b"\0\0\0":
                        silent += 1
                    if first_wrong is None:
                        first_wrong = start + i
        entry = {"channel": c + 1, "kind": "ramp" if is_ramp else "sine", "frames": len(b) // 3,
                 "wrongSamples": wrong, "silentSamples": silent, "firstWrongFrame": first_wrong}
        if not is_ramp:
            entry["zeroCrossingHz"] = round(zero_crossing_hz(b, skip=min(frames // 2, RATE)), 1)
        result["perChannel"].append(entry)
    result["bitExact"] = all(e["wrongSamples"] == 0 for e in result["perChannel"])
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
