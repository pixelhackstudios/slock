"""Makes the Slock teaser video: renders the Blender scene, synthesizes the soundtrack, adds the
post effects and encodes Builds/Trailer/slock_teaser.mp4.

    python3 tools/trailer/make_trailer.py            # full quality (long render)
    python3 tools/trailer/make_trailer.py --preview  # half resolution, low samples, quick look
    python3 tools/trailer/make_trailer.py --post     # skip rendering, redo sound + post + encode

Needs Blender (flatpak org.blender.Blender, or set SLOCK_BLENDER), ffmpeg, numpy and Pillow.
The soundtrack is 120 BPM and every hit comes from the impacts.json written by scene.py, so
the sound and the picture stay locked together when the timing changes.
"""
import json, os, shlex, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Builds" / "Trailer"
PREVIEW = "--preview" in sys.argv
FRAMES = OUT / ("preview" if PREVIEW else "frames")
VIDEO = OUT / ("slock_teaser_preview.mp4" if PREVIEW else "slock_teaser.mp4")
BLENDER = shlex.split(os.environ.get("SLOCK_BLENDER", "flatpak run org.blender.Blender"))
SR = 48000
rng = np.random.default_rng(11)


def render():
    cmd = BLENDER + ["-b", "--python", str(ROOT / "tools" / "trailer" / "scene.py"), "--"]
    if PREVIEW:
        cmd.append("--preview")
    subprocess.run(cmd, check=True)


# ---------------------------------------------------------------------------------------------
# sound
def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR

def band_noise(seconds, lo, hi):
    n = int(seconds * SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spec[(freqs < lo) | (freqs > hi)] = 0
    out = np.fft.irfft(spec, n)
    return out / (np.abs(out).max() + 1e-9)

def sweep(t, f0, f1, rate):
    """Sine whose pitch falls exponentially from f0 toward f1."""
    freq = f1 + (f0 - f1) * np.exp(-t * rate)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)

def kick():
    t = t_axis(0.45)
    return np.tanh(2.5 * sweep(t, 160, 45, 30) * np.exp(-t * 7)) * 0.9

def boom(amp):
    t = t_axis(1.8)
    body = np.tanh(3 * sweep(t, 90, 28, 6) * np.exp(-t * 2.2))
    crack = band_noise(1.8, 1500, 9000) * np.exp(-t * 28)
    rumble = band_noise(1.8, 30, 250) * np.exp(-t * 3.5)
    return (body + 0.55 * crack + 0.5 * rumble) * amp

def hit(amp):
    t = t_axis(0.8)
    snap = band_noise(0.8, 250, 5000) * np.exp(-t * 16)
    body = sweep(t, 220, 70, 18) * np.exp(-t * 9)
    return np.tanh(1.6 * (snap + 0.9 * body)) * amp

def tick(amp):
    t = t_axis(0.12)
    return band_noise(0.12, 2500, 11000) * np.exp(-t * 70) * amp * 2.2

def whoosh(amp):
    """Rises into the frame it's keyed to; returns (sound, samples before the key frame)."""
    lead, tail = 0.45, 0.2
    t = t_axis(lead + tail)
    env = np.where(t < lead, (t / lead) ** 2.5, np.exp(-(t - lead) * 18))
    lo = band_noise(lead + tail, 200, 1200)
    hi = band_noise(lead + tail, 1200, 6000)
    mix = t / (lead + tail)
    return (lo * (1 - mix) + hi * mix) * env * (0.5 + amp), int(lead * SR)

def riser(seconds):
    t = t_axis(seconds)
    k = t / seconds
    tone = np.sin(2 * np.pi * np.cumsum(110 * 8 ** k) / SR) * (1 + 0.5 * np.sin(2 * np.pi * (4 + 20 * k) * t))
    return (0.35 * tone + 0.6 * band_noise(seconds, 2000, 12000)) * k ** 2.5 * 0.7

def saw(freq, seconds, harmonics=10):
    t = t_axis(seconds)
    return sum(np.sin(2 * np.pi * freq * h * t) / h for h in range(1, harmonics + 1)) * 0.6

def soundtrack(info):
    fps, end = info["fps"], info["end"]
    frame_s = lambda f: (f - 1) / fps
    total = int((end / fps + 2.0) * SR)
    L, R = np.zeros(total), np.zeros(total)

    def put(sig, f, pan=0.0, offset=0):
        i = int(frame_s(f) * SR) - offset
        sig = sig[max(0, -i):]
        i = max(i, 0)
        n = min(len(sig), total - i)
        L[i:i + n] += sig[:n] * (1 - pan) ** 0.5
        R[i:i + n] += sig[:n] * (1 + pan) ** 0.5

    beat = lambda k: 1 + 15 * k
    # groove: kick on the beat, hats on the off-beat, a dark saw bass on the eighths
    live = [(41, 106), (151, 406)]
    roots = [55.0, 55.0, 43.65, 49.0]               # A A F G, one bar each
    for k in range(40):
        f = beat(k)
        if not any(a <= f < b for a, b in live):
            continue
        put(kick(), f)
        put(band_noise(0.1, 7000, 15000) * np.exp(-t_axis(0.1) * 45) * 0.25, f + 7.5, pan=0.3 if k % 2 else -0.3)
        root = roots[(k // 4) % 4]
        for half in (0, 7.5):
            t = t_axis(0.22)
            put(saw(root, 0.22) * np.exp(-t * 9) * 0.35, f + half)
    # the hits from the edit
    for f, amp, kind in info["impacts"]:
        if kind == "boom":
            put(boom(amp), f)
        elif kind == "hit":
            put(hit(amp), f, pan=float(rng.uniform(-0.25, 0.25)))
        elif kind == "tick":
            put(tick(amp), f, pan=float(rng.uniform(-0.5, 0.5)))
        elif kind == "whoosh":
            sig, lead = whoosh(amp)
            put(sig, f, offset=lead)
        elif kind == "riser":
            nxt = min(fi for fi, _, k in info["impacts"] if k == "boom" and fi > f)
            put(riser((nxt - f) / fps), f)
    # closing chord under the final lockup
    final = next(f for f, a, k in info["impacts"] if k == "boom" and f > 400)
    secs = (end - final) / fps + 1.5
    t = t_axis(secs)
    env = np.minimum(t / 0.05, 1) * np.exp(-t * 0.35)
    pad = sum(saw(fr, secs, 6) for fr in (55, 110, 130.81, 164.81)) * env * 0.18
    put(pad, final)

    mix = np.stack([L, R], 1)
    mix = np.tanh(mix / (np.abs(mix).max() + 1e-9) * 1.6) * 0.89
    fade = np.ones(total)
    fade_start = int(frame_s(end - 10) * SR)
    fade[fade_start:] = np.linspace(1, 0, total - fade_start) ** 2
    mix *= fade[:, None]
    return (mix * 32767).astype(np.int16)

def write_wav(path, pcm):
    import wave
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------------------------
# picture: flashes, chromatic aberration on the hits, vignette, grain, fades
def post_frames(info):
    files = sorted(FRAMES.glob("f_*.png"))
    if not files:
        sys.exit(f"No frames in {FRAMES} - render first.")
    w, h = Image.open(files[0]).size
    yy, xx = np.mgrid[0:h, 0:w]
    r2 = ((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2
    vignette = (1 - 0.32 * r2.clip(0, 2))[..., None].astype(np.float32)
    px = w / 1920
    end = info["end"]

    def env(f, kinds, decay):
        return sum(a * np.exp(-(f - fi) / decay) for fi, a, k in info["impacts"] if k in kinds and f >= fi)

    for path in files:
        f = int(path.stem.split("_")[1])
        img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255
        shift = int(round((1 + 14 * min(env(f, ("boom", "hit"), 3.0), 1.2)) * px))
        if shift:
            img[..., 0] = np.roll(img[..., 0], shift, axis=1)
            img[..., 2] = np.roll(img[..., 2], -shift, axis=1)
        flash = min(env(f, ("boom",), 1.6), 1.0) * 0.55
        img = img + (1 - img) * flash
        img *= vignette
        img += rng.normal(0, 0.022, (h, w, 1)).astype(np.float32)
        fade = min(1.0, (f - 1) / 6) * min(1.0, max(0.0, (end - f) / 18))
        img *= fade
        yield (np.clip(img, 0, 1) * 255).astype(np.uint8).tobytes(), (w, h)


def encode(info):
    wav = OUT / "soundtrack.wav"
    write_wav(wav, soundtrack(info))
    frames = post_frames(info)
    first, (w, h) = next(frames)
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(info["fps"]), "-i", "-",
           "-i", str(wav), "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", str(VIDEO)]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    enc.stdin.write(first)
    for data, _ in frames:
        enc.stdin.write(data)
    enc.stdin.close()
    if enc.wait():
        sys.exit("ffmpeg failed")
    print(f"Wrote {VIDEO}")


if __name__ == "__main__":
    if "--post" not in sys.argv:
        render()
    encode(json.loads((OUT / "impacts.json").read_text()))
