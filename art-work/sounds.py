"""
Synthesise Slock's sound effects into Assets/Resources/Slock/Sounds/ (how loud each plays is set in Sounds.cs).

    python3 art-work/sounds.py        (run from the project folder; needs numpy)

Pellet1.wav .. Pellet6.wav   a jelly bubble "pop" with a short, round tone under it. Notes, picked by ear:
                             G#1 F2 A2 C3 A3 B3. Each pellet plays one at random, slightly detuned.
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join("Assets", "Resources", "Slock", "Sounds")
NOTES = [51.91, 87.31, 110.00, 130.81, 220.00, 246.94]  # Hz


def pellet(f, seed):
    rng = np.random.default_rng(seed)
    t = np.arange(int(SR * 0.25)) / SR
    # Tone: a water-drop bloop (pitch glides up a few percent in the first ~35 ms), kept low under the pop.
    glide = 1.0 - 0.07 * np.exp(-t / 0.012)
    phase = 2 * np.pi * np.cumsum(f * glide) / SR
    tone = np.sin(phase) * np.exp(-t / 0.04)
    tone += 0.08 * np.sin(2 * phase) * np.exp(-t / 0.025)
    tone += 0.03 * np.sin(2.76 * phase) * np.exp(-t / 0.012)
    # Pop: a bubble bursting, a quick upward chirp gone in ~15 ms...
    chirp = f * 0.5 * (1 + 1.6 * (1 - np.exp(-t / 0.006)))
    bubble = np.sin(2 * np.pi * np.cumsum(chirp) / SR) * np.exp(-t / 0.007) * 0.9
    # ...plus a soft, low-passed noise thump.
    noise = rng.standard_normal(len(t)) * np.exp(-t / 0.004)
    thump = np.convolve(noise, np.ones(28) / 28, mode="same") * 1.6
    sig = tone * 0.5 + bubble + thump
    sig *= np.minimum(1.0, t / 0.001)                 # no click at the start
    sig = np.tanh(1.6 * sig) / np.tanh(1.6)           # gentle saturation
    a = np.exp(-2 * np.pi * 2000 / SR)                # soften the highs (~2 kHz low-pass)
    y = 0.0
    for i, x in enumerate(sig):
        y = (1 - a) * x + a * y
        sig[i] = y
    fade = int(SR * 0.03)
    sig[-fade:] *= np.linspace(1, 0, fade)
    return sig / np.max(np.abs(sig)) * 0.8


def save(path, sig):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(sig, -1, 1) * 32767).astype(np.int16).tobytes())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    clips = {f"Pellet{i + 1}": pellet(f, i) for i, f in enumerate(NOTES)}
    for name, sig in clips.items():
        path = os.path.join(OUT, name + ".wav")
        save(path, sig)
        print(path)
