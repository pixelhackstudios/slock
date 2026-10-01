"""
Turn the PBR texture sets in this folder into Unity-ready tile textures.

    python3 art-work/process_tiles.py        (run from the project folder)

Two tile themes, each written to its own folder under Assets/Textures/ (in game, press T to switch between them):
    Tiles  <- the TextureMap.app sets:   slock-floor-pbr*/, slock-tops-pbr*/, slock-walls-pbr*/
    SciFi  <- slock-sample-textures/:    see THEMES below for which folder feeds floor / tops / walls / ramps / gate

Works at any image size. Each image is one whole block face: floor = one floor block, tops = the top of a wall
block, walls = one side of a wall block, ramps = one block of ramp surface, gate = one face of the locked gate. It keeps the source resolution
(rounded up to a power of two, which Unity prefers) and writes, per surface:
    <kind>_base.png         colour (falls back to the grey AO map if a set has no colour image); alpha = opacity map, if any
    <kind>_normal.png       normal map (OpenGL +Y, which is what Unity expects)
    <kind>_metalsmooth.png  URP Lit "metallic" map: R = metallic, A = smoothness (1 - roughness)
    <kind>_ao.png           ambient occlusion
    <kind>_emission.png     glow map, only if the set has one
Then in Unity use the menu: Slock > Create Tile Materials (makes/updates the materials that point at these).

To use only part of an image, change its crop below: (left, top, right, bottom) as fractions of the image size.
"""
import glob
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TEXTURES = os.path.join(HERE, "..", "Assets", "Textures")

# Each image is one whole block face, so by default nothing is trimmed: (left, top, right, bottom) fractions.
CROPS = {
    "floor": (0.0, 0.0, 1.0, 1.0),   # one floor block
    "tops": (0.0, 0.0, 1.0, 1.0),    # the top of one wall block
    "walls": (0.0, 0.0, 1.0, 1.0),   # one side face of a wall block
    "ramps": (0.0, 0.0, 1.0, 1.0),   # one block of ramp surface
    "gate": (0.0, 0.0, 1.0, 1.0),    # one face of the locked gate (see-through where the opacity map is dark)
}

# theme -> {surface: source folder}. Folders missing on disk are skipped.
THEMES = {
    "Tiles": {kind: (glob.glob(os.path.join(HERE, f"slock-{kind}-pbr*/")) or [None])[0] for kind in ("floor", "tops", "walls")},
    "SciFi": {
        "floor": os.path.join(HERE, "slock-sample-textures", "sci-fi-floors"),
        "tops": os.path.join(HERE, "slock-sample-textures", "sci-fi-metal-tops"),
        "walls": os.path.join(HERE, "slock-sample-textures", "sci-f-metal-plate"),
        "ramps": os.path.join(HERE, "slock-sample-textures", "sci-fi-ramps"),
        "gate": os.path.join(HERE, "slock-sample-textures", "sci-fi-gates"),
    },
}

# Map name fragments, covering both TextureMap.app ("ambient-occlusion-map") and Substance-style ("_ambientOcclusion").
MAPS = {
    "base": ["basecolor"],
    "ao": ["ambient-occlusion", "ambientOcclusion"],
    "normal": ["normal"],
    "metallic": ["metallic"],
    "roughness": ["roughness"],
    "emission": ["emissive", "emission"],
    "opacity": ["opacity"],
}


def power_of_two(n):
    p = 64
    while p < n and p < 2048:
        p *= 2
    return p


def find(folder, map_name, kind):
    """The image in folder for this map, or None. Preview renders (Material_*.png) are ignored."""
    files = [f for f in glob.glob(os.path.join(folder, "*")) if f.lower().endswith((".png", ".jpg", ".jpeg"))
             and not os.path.basename(f).startswith("Material_")]
    if map_name == "base":
        exact = [f for f in files if os.path.basename(f) == f"slock-{kind}.png"]   # TextureMap.app keeps the photo as-is
        if exact:
            return exact[0]
    for f in files:
        if any(frag.lower() in os.path.basename(f).lower() for frag in MAPS[map_name]):
            return f
    return None


def process(theme, kind, folder):
    out = os.path.join(TEXTURES, theme)
    os.makedirs(out, exist_ok=True)
    ao_file = find(folder, "ao", kind)
    w, h = Image.open(ao_file).size
    frac = CROPS[kind]
    box = (round(frac[0] * w), round(frac[1] * h), round(frac[2] * w), round(frac[3] * h))
    size = power_of_two(max(box[2] - box[0], box[3] - box[1]))

    def load(path):
        return Image.open(path).crop(box).resize((size, size), Image.LANCZOS)

    ao = load(ao_file).convert("L")
    base = find(folder, "base", kind)
    colour = load(base).convert("RGB") if base else ao.convert("RGB")
    opacity = find(folder, "opacity", kind)
    if opacity:
        colour.putalpha(load(opacity).convert("L"))
    colour.save(os.path.join(out, f"{kind}_base.png"))
    ao.save(os.path.join(out, f"{kind}_ao.png"))
    load(find(folder, "normal", kind)).convert("RGB").save(os.path.join(out, f"{kind}_normal.png"))
    metal_file = find(folder, "metallic", kind)
    metal = load(metal_file).convert("L") if metal_file else Image.new("L", (size, size), 0)   # none: not metal
    smooth = Image.fromarray(255 - np.asarray(load(find(folder, "roughness", kind)).convert("L")))
    Image.merge("RGBA", (metal, metal, metal, smooth)).save(os.path.join(out, f"{kind}_metalsmooth.png"))
    glow = find(folder, "emission", kind)
    if glow:
        load(glow).convert("RGB").save(os.path.join(out, f"{kind}_emission.png"))
    print(f"{theme}/{kind}: {w}x{h} -> {size}x{size}, colour from {os.path.basename(base) if base else 'AO map'}"
          f"{', + glow' if glow else ''}{', + opacity' if opacity else ''}")


for theme, kinds in THEMES.items():
    for kind, folder in kinds.items():
        if not folder or not os.path.isdir(folder):
            print(f"{theme}/{kind}: no set found, skipped")
            continue
        process(theme, kind, folder)
