"""
Turn the TextureMap.app PBR sets in this folder into Unity-ready tile textures.

    python3 art-work/process_tiles.py        (run from the project folder)

Works at any image size (e.g. 128x128 or 1254x1254). Each image is one whole block face: floor = one floor
block, tops = the top of a wall block, walls = one side of a wall block. It keeps the source resolution
(rounded up to a power of two, which Unity prefers) and writes to Assets/Textures/Tiles/:
    <set>_base.png         colour, from the set's own image (e.g. slock-floor.png); falls back to the grey AO map
    <set>_normal.png       normal map (OpenGL +Y, which is what Unity expects)
    <set>_metalsmooth.png  URP Lit "metallic" map: R = metallic, A = smoothness (1 - roughness)
    <set>_ao.png           ambient occlusion
Unity picks the new files up automatically when its window is focused (the materials already point at them).
If the materials are missing, use the Unity menu: Slock > Create Tile Materials.

To use only part of an image, change its crop below: (left, top, right, bottom) as fractions of the image size.
"""
import glob
import os

import numpy as np
from PIL import Image

# Each image is one whole block face, so by default nothing is trimmed: (left, top, right, bottom) fractions.
CROPS = {
    "floor": (0.0, 0.0, 1.0, 1.0),   # one floor block
    "tops": (0.0, 0.0, 1.0, 1.0),    # the top of one wall block
    "walls": (0.0, 0.0, 1.0, 1.0),   # one side face of a wall block
}
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Assets", "Textures", "Tiles")


def power_of_two(n):
    p = 64
    while p < n and p < 2048:
        p *= 2
    return p


os.makedirs(OUT, exist_ok=True)
for kind, frac in CROPS.items():
    sets = glob.glob(os.path.join(HERE, f"slock-{kind}-pbr*/"))
    if not sets:
        print(f"{kind}: no set found, skipped")
        continue
    d = sets[0]

    def source(name):
        return Image.open(glob.glob(d + f"*{name}*.png")[0])

    w, h = source("ambient-occlusion").size
    box = (round(frac[0] * w), round(frac[1] * h), round(frac[2] * w), round(frac[3] * h))
    size = power_of_two(max(box[2] - box[0], box[3] - box[1]))

    def load(name):
        return source(name).crop(box).resize((size, size), Image.LANCZOS)

    ao = load("ambient-occlusion").convert("L")
    colour_files = glob.glob(d + f"slock-{kind}.png")          # the original colour image, if present
    base = colour_files[0] if colour_files else None
    if base:
        Image.open(base).convert("RGB").crop(box).resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"{kind}_base.png"))
    else:
        ao.convert("RGB").save(os.path.join(OUT, f"{kind}_base.png"))
    ao.save(os.path.join(OUT, f"{kind}_ao.png"))
    load("normal-map").convert("RGB").save(os.path.join(OUT, f"{kind}_normal.png"))
    metal = load("metallic").convert("L")
    smooth = Image.fromarray(255 - np.asarray(load("roughness").convert("L")))
    Image.merge("RGBA", (metal, metal, metal, smooth)).save(os.path.join(OUT, f"{kind}_metalsmooth.png"))
    print(f"{kind}: {w}x{h} source -> {size}x{size} tile, colour from {os.path.basename(base) if base else 'AO map (no colour image found)'}")
