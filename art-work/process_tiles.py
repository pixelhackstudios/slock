"""
Turn the PBR texture sets in this folder into the game's tile textures, in textures/.

    python3 art-work/process_tiles.py        (run from the project folder)

The sets: slock-floor-pbr*/, slock-tops-pbr*/, slock-walls-pbr*/ (made with TextureMap.app).

Works at any image size. Each image is one whole block face: floor = one floor block, tops = the top of a wall
block, walls = one side of a wall block. It keeps the source resolution (rounded up to a power of two) and writes,
per surface:
    <kind>_base.png         colour (falls back to the grey AO map if a set has no colour image)
    <kind>_normal.png       normal map (OpenGL +Y, which is what Godot expects)
    <kind>_ao.png           ambient occlusion
Godot picks them up the next time the project opens (section.gd makes the materials).

To use only part of an image, change its crop below: (left, top, right, bottom) as fractions of the image size.
"""
import glob
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TEXTURES = os.path.join(HERE, "..", "textures")

# Each image is one whole block face, so by default nothing is trimmed: (left, top, right, bottom) fractions.
CROPS = {
    "floor": (0.0, 0.0, 1.0, 1.0),   # one floor block
    "tops": (0.0, 0.0, 1.0, 1.0),    # the top of one wall block
    "walls": (0.0, 0.0, 1.0, 1.0),   # one side face of a wall block
}

# surface -> source folder. Folders missing on disk are skipped.
SETS = {kind: (glob.glob(os.path.join(HERE, f"slock-{kind}-pbr*/")) or [None])[0] for kind in ("floor", "tops", "walls")}

# Map name fragments, covering both TextureMap.app ("ambient-occlusion-map") and Substance-style ("_ambientOcclusion").
MAPS = {
    "base": ["basecolor"],
    "ao": ["ambient-occlusion", "ambientOcclusion"],
    "normal": ["normal"],
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


def process(kind, folder):
    out = TEXTURES
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
    colour.save(os.path.join(out, f"{kind}_base.png"))
    ao.save(os.path.join(out, f"{kind}_ao.png"))
    load(find(folder, "normal", kind)).convert("RGB").save(os.path.join(out, f"{kind}_normal.png"))
    print(f"{kind}: {w}x{h} -> {size}x{size}, colour from {os.path.basename(base) if base else 'AO map'}")


for kind, folder in SETS.items():
    if not folder or not os.path.isdir(folder):
        print(f"{kind}: no set found, skipped")
        continue
    process(kind, folder)
