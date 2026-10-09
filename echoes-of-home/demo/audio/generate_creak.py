"""Reproducible original placeholder creak (no external asset licensing)."""
import math
import random
import struct
import wave
from pathlib import Path
rng = random.Random(440)
rate = 22050
samples = []
phase = 0.0
for i in range(int(rate * 0.55)):
    t = i / rate
    phase += 2 * math.pi * (160 + 90 * math.sin(t * 9)) / rate
    envelope = math.sin(math.pi * t / 0.55) ** 2
    friction = 0.4 + 0.6 * max(0, math.sin(t * 83))
    value = envelope * friction * (0.22 * math.sin(phase) + 0.1 * rng.uniform(-1, 1))
    samples.append(struct.pack('<h', int(value * 32767)))
with wave.open(str(Path(__file__).with_name('floor_creak.wav')), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(b''.join(samples))
