"""
Synthesise Slock's sound effects (how loud each plays is set in the game's sound script).

    python3 art-work/sounds.py SlugClick SlugReload BigPop      (from the project folder; needs numpy)

Builds only the clips named (so it never overwrites sounds made elsewhere); with none, lists them. Clips go to
sounds/. (The pellet pops themselves were made in Audacity.)

BigPop               a big jelly bubble "pop" with a round tone under it: a power pellet or a pellet powerup.
SlugClick            one slug picked up: a clip snapping in (a metallic slide-clack, then the lock click).
SlugReload           slugs refilled: a quick reload, three fast clicks into the final clack.
"""
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = "sounds"


def lowpass(sig, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    y = 0.0
    out = np.empty_like(sig)
    for i, x in enumerate(sig):
        y = (1 - a) * x + a * y
        out[i] = y
    return out


def pellet(f, seed, size=1.0, length=0.25):
    """A bubble pop at pitch `f`. `size` stretches its decays: bigger bubbles ring longer."""
    rng = np.random.default_rng(seed)
    t = np.arange(int(SR * length)) / SR
    # Tone: a water-drop bloop (pitch glides up a few percent in the first ~35 ms), kept low under the pop.
    glide = 1.0 - 0.07 * np.exp(-t / (0.012 * size))
    phase = 2 * np.pi * np.cumsum(f * glide) / SR
    tone = np.sin(phase) * np.exp(-t / (0.04 * size))
    tone += 0.08 * np.sin(2 * phase) * np.exp(-t / (0.025 * size))
    tone += 0.03 * np.sin(2.76 * phase) * np.exp(-t / (0.012 * size))
    # Pop: a bubble bursting, a quick upward chirp gone in ~15 ms...
    chirp = f * 0.5 * (1 + 1.6 * (1 - np.exp(-t / (0.006 * size))))
    bubble = np.sin(2 * np.pi * np.cumsum(chirp) / SR) * np.exp(-t / (0.007 * size)) * 0.9
    # ...plus a soft, low-passed noise thump.
    noise = rng.standard_normal(len(t)) * np.exp(-t / (0.004 * size))
    thump = np.convolve(noise, np.ones(28) / 28, mode="same") * 1.6
    sig = tone * 0.5 + bubble + thump
    sig *= np.minimum(1.0, t / 0.001)                 # no click at the start
    sig = np.tanh(1.6 * sig) / np.tanh(1.6)           # gentle saturation
    sig = lowpass(sig, 2000)                          # soften the highs
    fade = int(SR * 0.03)
    sig[-fade:] *= np.linspace(1, 0, fade)
    return sig / np.max(np.abs(sig)) * 0.8


def click(rng, pitch=1.0, weight=1.0, ring=0.02):
    """One mechanical click: a sharp, band-limited snap plus a short metallic ring (inharmonic partials)."""
    t = np.arange(int(SR * 0.12)) / SR
    snap = rng.standard_normal(len(t)) * np.exp(-t / 0.0015)
    snap = snap - lowpass(snap, 1200 * pitch)         # keep the bright part: a crisp edge, not a thud
    metal = sum(a * np.sin(2 * np.pi * f * pitch * t + rng.uniform(0, 6.28)) * np.exp(-t / (ring * d))
                for f, a, d in [(1730, 0.5, 1.0), (2990, 0.35, 0.7), (4410, 0.25, 0.5), (6170, 0.15, 0.35)])
    body = np.sin(2 * np.pi * 180 * pitch * t) * np.exp(-t / 0.012) * 0.6 * weight  # the bolt's weight
    return (snap * 0.9 + metal + body) * weight


def mix(events, length):
    """Lay clicks (start time in seconds, signal) into one clip."""
    sig = np.zeros(int(SR * length))
    for start, part in events:
        i = int(SR * start)
        n = min(len(part), len(sig) - i)
        sig[i:i + n] += part[:n]
    sig = np.tanh(1.3 * sig) / np.tanh(1.3)
    fade = int(SR * 0.02)
    sig[-fade:] *= np.linspace(1, 0, fade)
    return sig / np.max(np.abs(sig)) * 0.8


def slug_click():
    rng = np.random.default_rng(7)
    # A clip snapping in: the slide (lighter, higher), then the lock (heavier, lower) 70 ms later.
    return mix([(0.0, click(rng, 1.15, 0.6)), (0.07, click(rng, 0.85, 1.0, 0.03))], 0.22)


def slug_reload():
    rng = np.random.default_rng(11)
    # A quick reload: three fast clicks, each a touch higher (rounds going in), then the clack home.
    events = [(k * 0.055, click(rng, 1.0 + k * 0.06, 0.55)) for k in range(3)]
    events.append((0.2, click(rng, 0.8, 1.1, 0.035)))
    return mix(events, 0.36)


def save(path, sig):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(sig, -1, 1) * 32767).astype(np.int16).tobytes())


CLIPS = {
    "BigPop": lambda: pellet(65.41, 3, size=2.2, length=0.4),  # C2, ringing about twice as long as a pellet pop
    "SlugClick": slug_click,
    "SlugReload": slug_reload,
}

if __name__ == "__main__":
    names = sys.argv[1:]
    if not names:
        print("Name the clips to build:", " ".join(CLIPS))
    for name in names:
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name + ".wav")
        save(path, CLIPS[name]())
        print(path)
