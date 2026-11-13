#!/usr/bin/env python3
"""Original short, quiet three-tone chime, synthesized locally without third-party assets."""
import argparse
import io
import math
from pathlib import Path
import struct
import wave


def sound():
    rate = 24000
    duration = 0.24
    samples = []
    for i in range(int(rate * duration)):
        t = i / rate
        value = 0.0
        for start, frequency in [(0.0, 660), (0.045, 880), (0.09, 1320)]:
            age = t-start
            if 0 <= age < 0.15:
                envelope = math.sin(math.pi * age / 0.15) ** 2
                value += 0.065 * envelope * math.sin(2*math.pi*frequency*age)
        samples.append(struct.pack("<h", round(32767*value)))
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(b"".join(samples))
    return buffer.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "Sources/LearningCore/Resources/achievement.wav"
    data = sound()
    if args.check:
        if not path.exists() or path.read_bytes() != data:
            raise SystemExit("Звук достижений не соответствует авторскому генератору")
    else:
        path.write_bytes(data)
    print("Оригинальный звук: mono PCM 24 kHz / 0,24 с; ресурс воспроизводим.")


if __name__ == "__main__":
    main()
