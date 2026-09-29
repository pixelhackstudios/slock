"""
Turn the TextureMap.app PBR sets in this folder into Unity-ready tile textures.

    python3 art-work/process_tiles.py        (run from the project folder)

For each set (floor, tops, walls) it crops every map to the panel's frame lines, so the pattern tiles with
its lines on block edges, resizes to 1024x1024 and writes to Assets/Textures/Tiles/:
    <set>_base.png         greyscale albedo (the AO map; there is no colour map yet), tinted in the material
    <set>_normal.png       normal map (OpenGL +Y, which is what Unity expects)
    <set>_metalsmooth.png  URP Lit "metallic" map: R = metallic, A = smoothness (1 - roughness)
    <set>_ao.png           ambient occlusion
Then in Unity: menu Slock > Create Tile Materials (also run automatically by Slock > Build Linux).

If you re-draw a set with a different layout, adjust its crop box below: (left, top, right, bottom) in pixels,
at the centre of the panel's outer frame lines.
"""
import glob
import os

import numpy as np
from PIL import Image

CROPS = {"floor": (155, 144, 1097, 1085), "tops": (97, 100, 1155, 1132), "walls": (161, 118, 1090, 1128)}
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Assets", "Textures", "Tiles")

os.makedirs(OUT, exist_ok=True)
for kind, box in CROPS.items():
    sets = glob.glob(os.path.join(HERE, f"slock-{kind}-pbr*/"))
    if not sets:
        print(f"{kind}: no set found, skipped")
        continue
    d = sets[0]

    def load(name):
        return Image.open(glob.glob(d + f"*{name}*.png")[0]).crop(box).resize((1024, 1024), Image.LANCZOS)

    ao = load("ambient-occlusion").convert("L")
    ao.convert("RGB").save(os.path.join(OUT, f"{kind}_base.png"))
    ao.save(os.path.join(OUT, f"{kind}_ao.png"))
    load("normal-map").convert("RGB").save(os.path.join(OUT, f"{kind}_normal.png"))
    metal = load("metallic").convert("L")
    smooth = Image.fromarray(255 - np.asarray(load("roughness").convert("L")))
    Image.merge("RGBA", (metal, metal, metal, smooth)).save(os.path.join(OUT, f"{kind}_metalsmooth.png"))
    print(f"{kind}: done")
