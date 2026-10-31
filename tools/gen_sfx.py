#!/usr/bin/env python3
"""Generate Downward Spiral's sound effects (original, procedurally synthesized).

    python3 tools/gen_sfx.py            -> game/assets/sfx/*.wav

Deterministic (fixed seed), stdlib only. 22.05 kHz mono 16-bit WAV.
"""
import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "sfx"
rng = random.Random(1337)


def env(i, n, attack=0.005, release=None):
    t = i / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = (1.0 - i / n) if release is None else math.exp(-t / release)
    return a * d


def noise():
    return rng.uniform(-1.0, 1.0)


def write(name, samples, gain=0.8):
    peak = max(1e-6, max(abs(s) for s in samples))
    k = gain / peak
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))


def lowpass(samples, a):
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def hit():
    n = int(0.16 * SR)
    thump = [math.sin(2 * math.pi * (110 - 60 * i / n) * i / SR) * env(i, n, 0.002, 0.05) for i in range(n)]
    crack = lowpass([noise() * env(i, n, 0.001, 0.02) for i in range(n)], 0.35)
    return [a + 0.7 * b for a, b in zip(thump, crack)]


def crit():
    base = hit()
    n = len(base)
    ring = [0.5 * math.sin(2 * math.pi * 880 * i / SR) * env(i, n, 0.001, 0.06) for i in range(n)]
    return [a + b for a, b in zip(base, ring)]


def whoosh():
    n = int(0.22 * SR)
    out, y = [], 0.0
    for i in range(n):
        a = 0.05 + 0.4 * math.sin(math.pi * i / n)
        y += a * (noise() - y)
        out.append(y * math.sin(math.pi * i / n))
    return out


def block():
    n = int(0.3 * SR)
    partials = [(523, 1.0), (1307, 0.6), (2113, 0.4), (3271, 0.25)]
    return [sum(amp * math.sin(2 * math.pi * f * i / SR) for f, amp in partials) * env(i, n, 0.001, 0.07)
            + 0.3 * noise() * env(i, n, 0.001, 0.01) for i in range(n)]


def spell():
    n = int(0.45 * SR)
    out, ph = [], 0.0
    for i in range(n):
        f = 300 + 900 * (i / n) ** 0.7
        ph += 2 * math.pi * f / SR
        out.append((math.sin(ph) + 0.4 * math.sin(2.01 * ph)) * env(i, n, 0.01, 0.2) + 0.15 * noise() * env(i, n, 0.0, 0.1))
    return out


def chime(notes, step=0.07, length=0.5):
    n = int((step * len(notes) + length) * SR)
    out = [0.0] * n
    for j, f in enumerate(notes):
        start = int(j * step * SR)
        for i in range(n - start):
            e = env(i, n - start, 0.003, 0.18)
            out[start + i] += (math.sin(2 * math.pi * f * i / SR) + 0.3 * math.sin(2 * math.pi * 2 * f * i / SR)) * e
    return out


def death():
    n = int(0.6 * SR)
    out, ph = [], 0.0
    for i in range(n):
        f = 160 * (1 - 0.7 * i / n)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * env(i, n, 0.005, 0.25) + 0.5 * noise() * env(i, n, 0.001, 0.05))
    return lowpass(out, 0.3)


def click():
    n = int(0.03 * SR)
    return [math.sin(2 * math.pi * 1800 * i / SR) * env(i, n, 0.0005, 0.006) for i in range(n)]


def chord(freqs, length):
    n = int(length * SR)
    return [sum(math.sin(2 * math.pi * f * i / SR) for f in freqs) * env(i, n, 0.02, length / 3) for i in range(n)]


def main():
    write("hit", hit())
    write("crit", crit())
    write("miss", whoosh(), 0.5)
    write("block", block(), 0.6)
    write("spell", spell(), 0.6)
    write("heal", chime([659, 784, 988]), 0.5)
    write("death", death())
    write("level_up", chime([523, 659, 784, 1047], 0.09, 0.7), 0.6)
    write("click", click(), 0.4)
    write("victory", chord([392, 494, 587], 0.4) + chord([523, 659, 784], 0.9), 0.6)
    write("defeat", chord([220, 262, 330], 0.5) + chord([196, 233, 294], 1.2), 0.6)
    print(f"wrote {len(list(OUT.glob('*.wav')))} files to {OUT}")


if __name__ == "__main__":
    main()
