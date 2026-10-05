"""
Slock's 3D models, built from scratch in Blender: the maze kit the sections are assembled from, and the pickups.

    flatpak run org.blender.Blender -b --python art-work/models.py -- [options]
    python3 art-work/models.py [options]          (with Blender's Python module: pip install bpy)

Options:
    --only kit|textures|pickups     build just that part (default: everything)
    --quick                         low sample counts, for a fast look
    --preview DIR                   also render a preview of each model into DIR

It writes:
    models/maze_kit.glb             the maze pieces, which section.gd assembles tile by tile:
                                        wall_cap    a wall block's top, rounded over its edges
                                        wall_side   one side face, between the rounded corners
                                        wall_edge   one rounded vertical corner
                                        wall_plug   fills the dimple where four wall blocks meet
                                        floor       one floor tile
    textures/maze/<set>_*.png       their textures, baked from detailed models of each surface: _albedo (colour),
                                    _normal (OpenGL, +Y up) and _orm (ambient occlusion, roughness, metallic), plus
                                    _emission for the pen. Sets: floor, ramp, pen, wall, cap, cliff
    models/<pickup>.glb             the powerups and pickups, with their materials: clear_dots, steel, slug_pack,
                                    extra_slug, close_traps, clock, key, slug, gate, chevron

Units: one block (tile) is 1.0. Blender is Z-up; the glTF files come out Y-up, which is what Godot uses. Shapes are
written here in Godot's axes through gd(x, y, z): x right, y up, z towards the camera (the near side of a tile).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODELS = os.path.join(ROOT, "models")
TEXTURES = os.path.join(ROOT, "textures", "maze")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
ONLY = ARGS[ARGS.index("--only") + 1] if "--only" in ARGS else None
QUICK = "--quick" in ARGS
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else None

TEX_SIZE = 1024
RIM = 0.06                       # wall blocks: radius of the rounding on their top and vertical edges


# ------------------------------------------------------------------------------------------------- helpers

def gd(x, y, z):
    """A point in Godot's axes (y up, z towards the camera) as a Blender vector (z up)."""
    return Vector((x, -z, y))


def srgb(r, g, b):
    """An sRGB colour (0..1, as picked on screen) in Blender's linear space."""
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    world = bpy.data.worlds.new("World")
    sc.world = world
    return sc


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mesh_object(name, verts, faces, uvs=None, normals=None, material=None, smooth=False):
    """A mesh from vertex positions (Blender axes) and faces (vertex index tuples). `uvs` and `normals`, if given,
    are per face corner, in the same order as the faces' indices."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    if uvs is not None:
        layer = me.uv_layers.new(name="UVMap")
        for i, uv in enumerate(uvs):
            layer.data[i].uv = uv
    for p in me.polygons:
        p.use_smooth = smooth or normals is not None
    if normals is not None:
        me.normals_split_custom_set([tuple(n) for n in normals])
    if material is not None:
        me.materials.append(material)
    me.validate()
    return link(bpy.data.objects.new(name, me))


def apply_modifiers(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def bevel(ob, width, segments=2, angle=30.0):
    """Round off the object's edges sharper than `angle` degrees (a bevel modifier, applied later)."""
    m = ob.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.profile = 0.5
    return m


def prism(name, outline, z0, z1, material=None, edge=0.0, segments=2):
    """A vertical prism over a 2D outline (counter-clockwise points in the Blender XY plane), from z0 to z1, its
    edges rounded by `edge`."""
    n = len(outline)
    verts = [(x, y, z0) for x, y in outline] + [(x, y, z1) for x, y in outline]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    ob = mesh_object(name, verts, faces, material=material)
    if edge > 0:
        bevel(ob, edge, segments)
        apply_modifiers(ob)
    return ob


def ring_prism(name, outer, inner, z0, z1, material=None, edge=0.0, segments=2):
    """A flat ring (an outline with a hole, both counter-clockwise with the same number of points) from z0 to z1."""
    n = len(outer)
    v = [(x, y, z0) for x, y in outer] + [(x, y, z1) for x, y in outer]
    v += [(x, y, z0) for x, y in inner] + [(x, y, z1) for x, y in inner]
    o0, o1, i0, i1 = 0, n, 2 * n, 3 * n
    faces = []
    for a in range(n):
        b = (a + 1) % n
        faces.append((o1 + a, o1 + b, i1 + b, i1 + a))      # top
        faces.append((o0 + b, o0 + a, i0 + a, i0 + b))      # bottom
        faces.append((o0 + a, o0 + b, o1 + b, o1 + a))      # outer wall
        faces.append((i0 + b, i0 + a, i1 + a, i1 + b))      # inner wall
    ob = mesh_object(name, v, faces, material=material)
    if edge > 0:
        bevel(ob, edge, segments)
        apply_modifiers(ob)
    return ob


def chamfered_square(half_w, half_h, chamfer, cx=0.0, cy=0.0):
    """An octagon: a rectangle with its corners cut at 45 degrees, counter-clockwise."""
    c = chamfer
    pts = [(half_w, -half_h + c), (half_w, half_h - c), (half_w - c, half_h), (-half_w + c, half_h),
           (-half_w, half_h - c), (-half_w, -half_h + c), (-half_w + c, -half_h), (half_w - c, -half_h)]
    return [(cx + x, cy + y) for x, y in pts]


def octagon(radius, cx=0.0, cy=0.0):
    """A regular octagon, flat sides facing the axes, `radius` from the centre to a flat side."""
    r = radius / math.cos(math.pi / 8)
    return [(cx + r * math.cos(math.pi / 8 + k * math.pi / 4), cy + r * math.sin(math.pi / 8 + k * math.pi / 4))
            for k in range(8)]


def rounded_box(name, size, radius, segments=3, material=None, location=(0, 0, 0)):
    """A box (Blender axes) with all its edges rounded."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if radius > 0:
        bevel(ob, radius, segments, angle=60.0)
        apply_modifiers(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    if material is not None:
        ob.data.materials.append(material)
    ob.location = location
    return ob


def cylinder(name, radius, depth, vertices=24, material=None, location=(0, 0, 0), rotation=(0, 0, 0), edge=0.0,
             segments=2):
    """A cylinder along Z (Blender axes), its ends' edges rounded by `edge`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=vertices, radius1=radius, radius2=radius, depth=depth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if edge > 0:
        bevel(ob, edge, segments, angle=60.0)
        apply_modifiers(ob)
    for p in ob.data.polygons:
        p.use_smooth = len(p.vertices) == 4   # smooth round sides, flat caps
    if material is not None:
        ob.data.materials.append(material)
    ob.location = location
    ob.rotation_euler = rotation
    return ob


def array_copies(objects, offsets):
    """Copies of `objects` moved by each offset (Blender axes): the neighbours of a tiling texture."""
    out = []
    for off in offsets:
        for ob in objects:
            c = ob.copy()
            c.data = ob.data
            c.location = ob.location + Vector(off)
            link(c)
            out.append(c)
    return out


# ------------------------------------------------------------------------------------------------- materials

def material(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0, alpha=1.0, coat=0.0, vary=0.0, grime=1.0):
    """A Principled BSDF material. For the texture bakes: `vary` gives each object its own slight shade of `color`,
    and `grime` is how much of the stains and wear it takes (see bake_set). The values are also kept on the
    material for the bake passes (see bake_pass)."""
    m = bpy.data.materials.new(name)
    if m.node_tree is None or "Principled BSDF" not in m.node_tree.nodes:
        m.use_nodes = True  # Blender 4 (5 always uses nodes)
    m.use_backface_culling = True
    nodes = m.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None and strength > 0:
        bsdf.inputs["Emission Color"].default_value = emit
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    if coat > 0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    m["color"] = color
    m["rough"] = rough
    m["metal"] = metal
    m["emit"] = [c * strength for c in emit[:3]] if emit is not None else [0.0, 0.0, 0.0]
    m["vary"] = vary
    m["grime"] = grime
    return m


# ------------------------------------------------------------------------------------------------- texture bakes
#
# Each texture set is a detailed model of one block face laid flat in the Blender XY plane over [-0.5, 0.5]^2
# (detail standing up along +Z), surrounded by copies of itself when the texture tiles, so shadows and occlusion
# carry across its edges. An orthographic camera looks straight down at the middle copy, and each map is a render
# of one quantity as plain emission: colour, roughness, metallic, glow, the surface normal (which, for a face
# looking straight up the camera, is its tangent-space normal: +X right, +Y up the image) and ambient occlusion.

def bake_camera(sc):
    cam = bpy.data.cameras.new("bake")
    cam.type = "ORTHO"
    cam.ortho_scale = 1.0
    cam.clip_start = 0.01
    cam.clip_end = 20.0
    ob = link(bpy.data.objects.new("bake", cam))
    ob.location = (0, 0, 5)
    sc.camera = ob
    sc.render.resolution_x = sc.render.resolution_y = TEX_SIZE if not QUICK else TEX_SIZE // 2
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.cycles.filter_width = 1.0
    sc.cycles.max_bounces = 0
    sc.cycles.use_adaptive_sampling = False
    sc.world.color = (0, 0, 0)
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "16"


def _emission_tree(m, source):
    """Replace a material's nodes with: source -> emission -> output. `source(nodes, links)` returns a colour socket
    to plug in, or a constant colour."""
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    sock = source(nt.nodes, nt.links)
    if isinstance(sock, tuple):
        em.inputs["Color"].default_value = sock
    else:
        nt.links.new(sock, em.inputs["Color"])


def bake_pass(sc, which, ao_distance=0.1):
    """Set every material up to render `which`: albedo, rough, metal, grime, emit, normal or ao."""
    for m in bpy.data.materials:
        if which == "albedo":
            def src(nodes, links, m=m):
                c = tuple(m["color"])
                if m["vary"] <= 0:
                    return c
                info = nodes.new("ShaderNodeObjectInfo")
                rng = nodes.new("ShaderNodeMapRange")
                rng.inputs["To Min"].default_value = 1.0 - m["vary"]
                rng.inputs["To Max"].default_value = 1.0 + m["vary"]
                links.new(info.outputs["Random"], rng.inputs["Value"])
                mul = nodes.new("ShaderNodeMix")
                mul.data_type = "RGBA"
                mul.blend_type = "MULTIPLY"
                mul.inputs["Factor"].default_value = 1.0
                mul.inputs["A"].default_value = c
                links.new(rng.outputs["Result"], mul.inputs["B"])
                return mul.outputs["Result"]
        elif which in ("rough", "metal", "grime"):
            def src(nodes, links, m=m):
                v = float(m[which])
                return (v, v, v, 1.0)
        elif which == "emit":
            def src(nodes, links, m=m):
                return tuple(m["emit"]) + (1.0,)
        elif which == "normal":
            def src(nodes, links):
                geo = nodes.new("ShaderNodeNewGeometry")
                ma = nodes.new("ShaderNodeVectorMath")
                ma.operation = "MULTIPLY_ADD"
                ma.inputs[1].default_value = (0.5, 0.5, 0.5)
                ma.inputs[2].default_value = (0.5, 0.5, 0.5)
                links.new(geo.outputs["Normal"], ma.inputs[0])
                return ma.outputs["Vector"]
        else:  # ao
            def src(nodes, links):
                ao = nodes.new("ShaderNodeAmbientOcclusion")
                ao.samples = 16
                ao.inputs["Distance"].default_value = ao_distance
                return ao.outputs["AO"]
        _emission_tree(m, src)
    colour = which in ("albedo", "emit")
    sc.view_settings.view_transform = "Standard" if colour else "Raw"
    if which == "ao":
        sc.cycles.samples = 16 if QUICK else 48
    else:
        sc.cycles.samples = 4 if QUICK else 16
    sc.cycles.use_denoising = False


def tile_noise(size, cells, seed, sharp=2.0):
    """Cloudy noise in 0..1 that tiles (it's built from whole waves across the texture): features about
    1/`cells` of the texture across."""
    import numpy as np
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((size, size)))
    k = np.hypot(*np.meshgrid(np.fft.fftfreq(size) * size, np.fft.fftfreq(size) * size))
    f *= 1.0 / (1.0 + (k / cells) ** (2.0 * sharp))
    n = np.real(np.fft.ifft2(f))
    n = (n - n.mean()) / (n.std() + 1e-9)
    return 0.5 + 0.5 * np.tanh(n * 0.6)


def bake_set(name, build, tiles_x=True, tiles_y=True, ao_distance=0.1, emission=False, dirt=0.25, stains=0.035,
             mottle=0.02, seed=1):
    """Model a surface with `build()`, then render its texture set into textures/maze/<name>_*.png.
    The colour gets a little of the wear real panels have, scaled by each material's `grime`: `dirt` darkens it in
    creases (by the occlusion), `stains` adds soft blotches and `mottle` fine variation; roughness varies with them."""
    import numpy as np
    sc = reset()
    objects = build()
    offsets = [(dx, dy, 0) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
               if (dx, dy) != (0, 0) and (tiles_x or dx == 0) and (tiles_y or dy == 0)]
    array_copies(objects, offsets)
    bake_camera(sc)
    os.makedirs(TEXTURES, exist_ok=True)
    tmp = os.path.join(TEXTURES, "_pass.png")
    maps = {}
    for which in ["albedo", "rough", "metal", "grime", "normal", "ao"] + (["emit"] if emission else []):
        bake_pass(sc, which, ao_distance)
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        img.colorspace_settings.name = "Non-Color"  # the values as stored, no conversion
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]  # top row first
        bpy.data.images.remove(img)
        maps[which] = px
    os.remove(tmp)

    def save(arr, path):
        from_float = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
        img = bpy.data.images.new("out", from_float.shape[1], from_float.shape[0], alpha=False)
        img.colorspace_settings.name = "Non-Color"
        rgba = np.concatenate([from_float[::-1].astype(np.float32) / 255.0,
                               np.ones(from_float.shape[:2] + (1,), np.float32)], axis=2)
        img.pixels.foreach_set(rgba.ravel())
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)

    size = maps["ao"].shape[0]
    ao = maps["ao"][..., :1]
    grime = maps["grime"][..., :1]
    blotch = np.clip((tile_noise(size, 3.0, seed) - 0.5) * 3.0, 0.0, 1.0)[..., None]   # soft patches
    fine = tile_noise(size, 40.0, seed + 1, sharp=1.0)[..., None] - 0.5
    # Grime settles in the creases (where the occlusion is), and in patches; the stains are a warm grey.
    shade = (1.0 - dirt + dirt * ao) ** 0.8
    stain = grime * (stains * blotch + mottle * 2.0 * fine)
    albedo = maps["albedo"] * shade * (1.0 - stain * np.array([0.9, 1.0, 1.15]))
    rough = maps["rough"][..., :1] + grime * (0.08 * blotch + 0.04 * fine)
    n = maps["normal"] * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
    save(albedo, os.path.join(TEXTURES, f"{name}_albedo.png"))
    save(n * 0.5 + 0.5, os.path.join(TEXTURES, f"{name}_normal.png"))
    save(np.concatenate([ao, np.clip(rough, 0.0, 1.0), maps["metal"][..., :1]], axis=2),
         os.path.join(TEXTURES, f"{name}_orm.png"))
    if emission:
        save(maps["emit"], os.path.join(TEXTURES, f"{name}_emission.png"))
    print(f"texture set {name}: done")


# ---- the surfaces

def floor_surface():
    """A floor block: four square tiles with cut corners, grey grout, orange octagonal studs where they meet."""
    tile = material("tile", srgb(0.89, 0.88, 0.85), rough=0.5, vary=0.025)
    grout = material("grout", srgb(0.36, 0.36, 0.37), rough=0.85, grime=0.5)
    stud = material("stud", srgb(0.98, 0.56, 0.12), rough=0.3, grime=0.3)
    stud_rim = material("stud_rim", srgb(0.42, 0.24, 0.08), rough=0.5, grime=0.3)
    obs = [prism("bed", [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.05, 0.0, grout)]
    for cx in (-0.25, 0.25):
        for cy in (-0.25, 0.25):
            obs.append(prism("tile", chamfered_square(0.232, 0.232, 0.05, cx, cy), 0.0, 0.016, tile,
                             edge=0.007, segments=3))
    for cx in (-0.5, 0.0, 0.5):
        for cy in (-0.5, 0.0, 0.5):
            obs.append(prism("stud_rim", octagon(0.046, cx, cy), 0.0, 0.013, stud_rim, edge=0.004))
            obs.append(prism("stud", octagon(0.036, cx, cy), 0.0, 0.019, stud, edge=0.005, segments=3))
    return obs


def wall_surface():
    """One side of a wall block, standing up the image (its foot at the bottom, the floor in front of it): a pale
    panel crossed by dark conduits, with blue square bolts where they meet, and a darker kick plate along the foot.
    The face runs from the floor up to the wall's rounded top edge (RIM below the top of the image); its left and
    right edges wrap round the block's rounded corners."""
    panel = material("panel", srgb(0.8, 0.8, 0.79), rough=0.55, vary=0.0)
    conduit = material("conduit", srgb(0.2, 0.21, 0.23), rough=0.4, metal=0.6, grime=0.4)
    bolt = material("bolt", srgb(0.3, 0.56, 0.78), rough=0.32, grime=0.3)
    bolt_rim = material("bolt_rim", srgb(0.12, 0.22, 0.33), rough=0.45, grime=0.3)
    kick = material("kick", srgb(0.6, 0.6, 0.6), rough=0.6)
    floor = material("floor", srgb(0.85, 0.85, 0.83), rough=0.5)
    foot = -0.5                                  # the floor line (image bottom)
    top = 0.5 - RIM                              # where the rounded top edge begins
    mid = (foot + top) * 0.5
    obs = [prism("panel", [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.05, 0.0, panel)]
    # The floor the wall stands on: seen edge-on by the camera, it only shades the foot of the wall.
    floor_ob = mesh_object("floor", [(-0.5, foot, 0), (0.5, foot, 0), (0.5, foot, 0.6), (-0.5, foot, 0.6)],
                           [(0, 1, 2, 3)], material=floor)
    obs.append(floor_ob)
    obs.append(prism("kick", [(-0.5, foot), (0.5, foot), (0.5, foot + 0.07), (-0.5, foot + 0.07)], 0.0, 0.006,
                     kick, edge=0.003))
    cols = (-0.34, 0.0, 0.34)
    rows = (mid - 0.31, mid, mid + 0.31)
    for x in cols:   # conduits: rounded bars lying on the panel
        obs.append(cylinder("conduit", 0.009, rows[2] - rows[0], 12, conduit, location=(x, mid, 0.004)))
        obs[-1].rotation_euler = (math.radians(90), 0, 0)
    for y in rows:
        obs.append(cylinder("conduit", 0.009, cols[2] - cols[0], 12, conduit, location=(0, y, 0.004),
                            rotation=(0, math.radians(90), 0)))
    for x in cols:
        for y in rows:
            obs.append(rounded_box("bolt_rim", (0.066, 0.066, 0.016), 0.01, 2, bolt_rim, location=(x, y, 0.004)))
            obs.append(rounded_box("bolt", (0.05, 0.05, 0.026), 0.009, 3, bolt, location=(x, y, 0.006)))
    return obs


def cap_surface():
    """The top of a wall block: a raised panel with cut corners inside a channel, bridged at the middle of each
    side, in a flat frame. The outer RIM of it lies on the block's rounded top edge (its shape comes from the model,
    so the frame stays flat here)."""
    frame = material("frame", srgb(0.88, 0.87, 0.85), rough=0.5)
    panel = material("panel", srgb(0.9, 0.89, 0.87), rough=0.45, vary=0.0)
    channel = material("channel", srgb(0.55, 0.55, 0.57), rough=0.7, grime=0.6)
    screw = material("screw", srgb(0.62, 0.64, 0.68), rough=0.3, metal=0.9, grime=0.3)
    inner = 0.5 - RIM - 0.055                    # the frame's inner edge
    obs = [prism("channel", [(-0.6, -0.6), (0.6, -0.6), (0.6, 0.6), (-0.6, 0.6)], -0.05, -0.012, channel)]
    obs.append(ring_prism("frame", chamfered_square(0.6, 0.6, 0.1), chamfered_square(inner, inner, 0.085),
                          -0.012, 0.0, frame, edge=0.004))
    obs.append(prism("panel", chamfered_square(inner - 0.03, inner - 0.03, 0.07), -0.012, 0.002, panel,
                     edge=0.006, segments=3))
    for k in range(4):   # bridges across the channel
        a = k * math.pi / 2
        c, s_ = math.cos(a), math.sin(a)
        r = inner - 0.015
        ob = rounded_box("bridge", (0.035, 0.06, 0.012), 0.004, 2, frame, location=(c * r, s_ * r, -0.006))
        ob.rotation_euler = (0, 0, a)
        obs.append(ob)
    for sx in (-1, 1):   # screws in the frame's cut corners
        for sy in (-1, 1):
            d = inner + 0.008
            obs.append(cylinder("screw", 0.011, 0.006, 16, screw, location=(sx * (d - 0.035), sy * (d - 0.035), 0.0),
                                edge=0.003))
    return obs


def cliff_surface():
    """The sheer sides of a section, below its floor: big plain panels with ribs and corner bolts, a shade darker
    than the walls so the maze stands out from its foundations."""
    seam = material("seam", srgb(0.22, 0.22, 0.24), rough=0.8, grime=0.5)
    panel = material("panel", srgb(0.6, 0.61, 0.63), rough=0.6, vary=0.03)
    rib = material("rib", srgb(0.56, 0.57, 0.6), rough=0.55)
    bolt = material("bolt", srgb(0.3, 0.56, 0.78), rough=0.35, grime=0.3)
    obs = [prism("seam", [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.05, 0.0, seam)]
    obs.append(prism("panel", chamfered_square(0.478, 0.478, 0.05), 0.0, 0.02, panel, edge=0.007, segments=3))
    for y in (-0.16, 0.16):
        obs.append(prism("rib", chamfered_square(0.33, 0.022, 0.018, 0.0, y), 0.02, 0.03, rib, edge=0.004))
    for sx in (-1, 1):
        for sy in (-1, 1):
            obs.append(prism("bolt", octagon(0.018, sx * 0.4, sy * 0.4), 0.02, 0.03, bolt, edge=0.004))
    return obs


def ramp_surface():
    """The booster ramps: dark steel tread plate, its raised lugs in a herringbone."""
    plate = material("plate", srgb(0.36, 0.37, 0.4), rough=0.42, metal=0.85, vary=0.02)
    seam = material("seam", srgb(0.12, 0.12, 0.13), rough=0.8, metal=0.5, grime=0.5)
    obs = [prism("seam", [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.05, -0.01, seam)]
    obs.append(prism("plate", chamfered_square(0.493, 0.493, 0.02), -0.01, 0.0, plate, edge=0.004))
    n = 8
    step = 1.0 / n
    lug = [(0.04, 0), (0, 0.011), (-0.04, 0), (0, -0.011)]   # a long thin diamond
    for i in range(n):
        for j in range(n):
            cx, cy = -0.5 + (i + 0.5) * step, -0.5 + (j + 0.5) * step
            a = math.radians(45 if (i + j) % 2 == 0 else -45)
            pts = [(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in lug]
            obs.append(prism("lug", pts, 0.0, 0.007, plate, edge=0.003))
    return obs


def pen_surface():
    """The swurm pen's floor: a steel grate over a green glow."""
    glow = material("glow", srgb(0.12, 0.45, 0.14), rough=0.6, emit=srgb(0.3, 1.0, 0.35), strength=1.0, grime=0.0)
    bar = material("bar", srgb(0.26, 0.27, 0.29), rough=0.45, metal=0.8, grime=0.6)
    frame = material("frame", srgb(0.34, 0.35, 0.37), rough=0.45, metal=0.8, grime=0.6)
    obs = [prism("glow", [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)], -0.08, -0.06, glow)]
    obs.append(ring_prism("frame", chamfered_square(0.5, 0.5, 0.0001), chamfered_square(0.44, 0.44, 0.0001),
                          -0.06, 0.0, frame, edge=0.004))
    holes = 5
    pitch = 0.88 / holes
    for k in range(1, holes):
        p = -0.44 + k * pitch
        obs.append(prism("bar", [(p - 0.012, -0.45), (p + 0.012, -0.45), (p + 0.012, 0.45), (p - 0.012, 0.45)],
                         -0.06, -0.008, bar, edge=0.004))
        obs.append(prism("bar", [(-0.45, p - 0.012), (0.45, p - 0.012), (0.45, p + 0.012), (-0.45, p + 0.012)],
                         -0.06, -0.012, bar, edge=0.004))
    return obs


TEXTURE_SETS = {   # name -> (model, bake options)
    "floor": (floor_surface, dict(ao_distance=0.08, stains=0.03)),
    "wall": (wall_surface, dict(tiles_y=False, ao_distance=0.12, seed=2, stains=0.025)),
    "cap": (cap_surface, dict(tiles_x=False, tiles_y=False, ao_distance=0.08, seed=3, stains=0.02, mottle=0.015)),
    "cliff": (cliff_surface, dict(ao_distance=0.1, seed=4, stains=0.05)),
    "ramp": (ramp_surface, dict(ao_distance=0.05, seed=5, dirt=0.4, stains=0.05)),
    "pen": (pen_surface, dict(ao_distance=0.1, emission=True, seed=6)),
}


# ------------------------------------------------------------------------------------------------- the maze kit
#
# The pieces section.gd builds every maze block from, written out exactly (in Godot's axes) so their rounded edges
# have true normals and every piece meets its neighbours edge for edge. They're lean (a cap is 42 triangles: the
# deepest sections have a couple of thousand wall blocks), and the smooth normals do the rounding. A wall block is one
# wall_cap, a wall_side for each face that isn't against another wall block as tall, a wall_edge on each corner unless
# the three blocks round that corner are all walls (then a wall_plug closes the little dimple their rounded corners
# leave). The block is
# 1 x 1 x 1 standing on the floor (y = 0): the cap is its top RIM, rounded over, the sides and edges go from the
# floor up to it. Pieces for one face or corner are made for the near face (+z) and the near-right corner (+x +z);
# the game turns them for the others. UVs: the cap, plug and floor are mapped from above (u along x, v along z), the
# sides from the front (u along x, v down), and the edges carry the side's u on round the corner, past 1 (the wall
# texture tiles across).

def _oriented(verts, faces, normals):
    """Faces wound so they face the way their vertex normals point (counter-clockwise seen from outside)."""
    out = []
    for f in faces:
        a, b, c = (Vector(verts[i]) for i in f[:3])
        n = sum((Vector(normals[i]) for i in f), Vector())
        out.append(tuple(f) if (b - a).cross(c - a).dot(n) >= 0 else tuple(reversed(f)))
    return out


def kit_piece(name, verts, faces, normals, uvs):
    """A kit piece from vertices in Godot's axes, with a normal and (Godot) UV per vertex."""
    faces = _oriented(verts, faces, normals)
    bverts = [gd(*v) for v in verts]
    loop_normals = [gd(*normals[i]) for f in faces for i in f]
    loop_uvs = [(uvs[i][0], 1.0 - uvs[i][1]) for f in faces for i in f]   # Blender's v runs up the image
    return mesh_object(name, bverts, faces, uvs=loop_uvs, normals=loop_normals)


def kit_cap(rings=2, arc=2):
    h = 0.5 - RIM
    corners = [(h, h, 0.0), (-h, h, 90.0), (-h, -h, 180.0), (h, -h, 270.0)]   # (x, z, start angle): round from +x
    verts, normals = [], []
    ring_ids = []
    for k in range(rings):
        phi = math.pi / 2 * k / rings
        r, y = RIM * math.cos(phi), 1.0 - RIM + RIM * math.sin(phi)
        ids = []
        for cx, cz, a0 in corners:
            for j in range(arc + 1):
                a = math.radians(a0 + 90.0 * j / arc)
                verts.append((cx + r * math.cos(a), y, cz + r * math.sin(a)))
                normals.append((math.cos(phi) * math.cos(a), math.sin(phi), math.cos(phi) * math.sin(a)))
                ids.append(len(verts) - 1)
        ring_ids.append(ids)
    top = []
    for cx, cz, a0 in corners:
        verts.append((cx, 1.0, cz))
        normals.append((0.0, 1.0, 0.0))
        top.append(len(verts) - 1)
    faces = []
    for k in range(rings - 1):
        a, b = ring_ids[k], ring_ids[k + 1]
        for p in range(len(a)):
            q = (p + 1) % len(a)
            faces.append((a[p], a[q], b[q], b[p]))
    last = ring_ids[-1]
    for i in range(4):
        base = i * (arc + 1)
        for j in range(arc):                       # round corner: a fan to the top corner
            faces.append((last[base + j], last[base + j + 1], top[i]))
        nxt = ((i + 1) % 4) * (arc + 1)            # straight side
        faces.append((last[base + arc], last[nxt], top[(i + 1) % 4], top[i]))
    faces.append(tuple(top))
    uvs = [(x + 0.5, z + 0.5) for x, y, z in verts]
    return kit_piece("wall_cap", verts, faces, normals, uvs)


def kit_side():
    h = 0.5 - RIM
    verts = [(-h, 0.0, 0.5), (h, 0.0, 0.5), (h, 1.0 - RIM, 0.5), (-h, 1.0 - RIM, 0.5)]
    normals = [(0.0, 0.0, 1.0)] * 4
    uvs = [(x + 0.5, 1.0 - y) for x, y, z in verts]
    return kit_piece("wall_side", verts, [(0, 1, 2, 3)], normals, uvs)


def kit_edge(arc=2):
    h = 0.5 - RIM
    verts, normals, uvs = [], [], []
    for j in range(arc + 1):
        a = math.radians(90.0 * j / arc)                     # 0: facing +x ... 90: facing +z
        u = 1.0 - RIM + 2.0 * RIM * (1.0 - j / arc)          # carries on from the near face's u, round to the right
        for y in (0.0, 1.0 - RIM):
            verts.append((h + RIM * math.cos(a), y, h + RIM * math.sin(a)))
            normals.append((math.cos(a), 0.0, math.sin(a)))
            uvs.append((u, 1.0 - y))
    faces = [(2 * j, 2 * j + 2, 2 * j + 3, 2 * j + 1) for j in range(arc)]
    return kit_piece("wall_edge", verts, faces, normals, uvs)


def kit_plug():
    h = 0.5 - RIM
    y = 1.0 - RIM
    verts = [(h, y, h), (0.5, y, h), (0.5, y, 0.5), (h, y, 0.5)]
    normals = [(0.0, 1.0, 0.0)] * 4
    uvs = [(x + 0.5, z + 0.5) for x, _, z in verts]
    return kit_piece("wall_plug", verts, [(0, 1, 2, 3)], normals, uvs)


def kit_floor():
    verts = [(-0.5, 0.0, -0.5), (0.5, 0.0, -0.5), (0.5, 0.0, 0.5), (-0.5, 0.0, 0.5)]
    normals = [(0.0, 1.0, 0.0)] * 4
    uvs = [(x + 0.5, z + 0.5) for x, _, z in verts]
    return kit_piece("floor", verts, [(0, 1, 2, 3)], normals, uvs)


def export_glb(path, objects, materials=True):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_normals=True, export_tangents=True,
                              export_materials="EXPORT" if materials else "NONE",
                              export_animations=False, export_extras=False)
    print("wrote", os.path.relpath(path, ROOT))


def build_kit():
    reset()
    pieces = [kit_cap(), kit_side(), kit_edge(), kit_plug(), kit_floor()]
    export_glb(os.path.join(MODELS, "maze_kit.glb"), pieces, materials=False)


# ------------------------------------------------------------------------------------------------- the pickups
#
# Each is one model (one node; the slug and the gate have two), centred on the point it floats and spins about,
# sized in blocks. They read at a glance from the game's camera, high above: each has its own shape and colour, glossy
# glowing parts against white ceramic and chrome, like the maze. The game gives them their black outlines.

def smooth_by_angle(ob, angle=35.0):
    """Smooth shading, with sharp edges where faces meet at more than `angle` degrees."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for e in bm.edges:
        if e.is_manifold and len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) < math.radians(angle)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def lathe(name, profile, segments=48, material=None, location=(0, 0, 0), angle=35.0):
    """A surface of revolution about Z from (radius, z) points, bottom to top. A radius of 0 closes that end."""
    verts, faces, rings = [], [], []
    for r, z in profile:
        if r <= 1e-6:
            verts.append((0.0, 0.0, z))
            rings.append([len(verts) - 1])
            continue
        ring = []
        for k in range(segments):
            a = 2.0 * math.pi * k / segments
            verts.append((r * math.cos(a), r * math.sin(a), z))
            ring.append(len(verts) - 1)
        rings.append(ring)
    for lo, hi in zip(rings, rings[1:]):
        for k in range(segments):
            k1 = (k + 1) % segments
            if len(lo) == 1:
                faces.append((lo[0], hi[k1], hi[k]))
            elif len(hi) == 1:
                faces.append((lo[k], lo[k1], hi[0]))
            else:
                faces.append((lo[k], lo[k1], hi[k1], hi[k]))
    ob = mesh_object(name, verts, faces, material=material)
    ob.location = location
    return smooth_by_angle(ob, angle)


def uv_sphere(name, radius, material=None, location=(0, 0, 0), segments=32, rings=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    for p in ob.data.polygons:
        p.use_smooth = True
    if material is not None:
        ob.data.materials.append(material)
    ob.location = location
    return ob


def torus(name, major, minor, material=None, location=(0, 0, 0), rotation=(0, 0, 0), segments=48, sides=16):
    verts, faces = [], []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        for j in range(sides):
            b = 2.0 * math.pi * j / sides
            r = major + minor * math.cos(b)
            verts.append((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))
    for i in range(segments):
        for j in range(sides):
            i1, j1 = (i + 1) % segments, (j + 1) % sides
            faces.append((i * sides + j, i1 * sides + j, i1 * sides + j1, i * sides + j1))
    ob = mesh_object(name, verts, faces, material=material, smooth=True)
    ob.location = location
    ob.rotation_euler = rotation
    return ob


def join(name, objects):
    """Join objects into one mesh object (transforms applied), named `name`."""
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def place(objects, offset=(0, 0, 0), scale=1.0, rotation=(0, 0, 0)):
    """Move, scale and turn objects together about the origin (Blender axes)."""
    m = Matrix.Translation(offset) @ Matrix.Rotation(rotation[2], 4, "Z") @ Matrix.Rotation(rotation[1], 4, "Y") \
        @ Matrix.Rotation(rotation[0], 4, "X") @ Matrix.Scale(scale, 4)
    for ob in objects:
        ob.matrix_world = m @ ob.matrix_world
    return objects


def copy_objects(objects):
    out = []
    for ob in objects:
        c = ob.copy()
        c.data = ob.data.copy()
        link(c)
        out.append(c)
    return out


def pickup_looks():
    """The pickups' shared materials."""
    return {
        "ceramic": material("ceramic", srgb(0.92, 0.91, 0.89), rough=0.28, coat=0.4),
        # Metals that read in the game's plain light: part diffuse, or they'd only mirror the dark around them.
        "chrome": material("chrome", srgb(0.93, 0.94, 0.96), rough=0.14, metal=0.85),
        "steel": material("steel", srgb(0.88, 0.89, 0.92), rough=0.26, metal=0.7),
        "gunmetal": material("gunmetal", srgb(0.2, 0.21, 0.24), rough=0.35, metal=0.9),
        "brass": material("brass", srgb(0.94, 0.72, 0.36), rough=0.22, metal=1.0),
        "orange": material("glow_orange", srgb(1.0, 0.52, 0.08), rough=0.22, emit=srgb(1.0, 0.45, 0.05),
                           strength=2.5, coat=0.6),
        "blue_jelly": material("blue_jelly", srgb(0.3, 0.6, 1.0), rough=0.04, emit=srgb(0.15, 0.4, 1.0),
                               strength=0.6, alpha=0.62, coat=1.0),
        "blue_core": material("blue_core", srgb(0.55, 0.82, 1.0), rough=0.3, emit=srgb(0.35, 0.7, 1.0), strength=3.0),
        "green": material("glow_green", srgb(0.3, 1.0, 0.38), rough=0.15, emit=srgb(0.25, 1.0, 0.32), strength=1.6,
                          alpha=0.85, coat=1.0),
        "mint": material("mint", srgb(0.85, 1.0, 0.88), rough=0.25, emit=srgb(0.6, 1.0, 0.65), strength=1.2),
        "glass": material("glass_cyan", srgb(0.6, 0.95, 1.0), rough=0.03, alpha=0.38, coat=1.0),
        "cyan": material("glow_cyan", srgb(0.35, 0.95, 1.0), rough=0.4, emit=srgb(0.3, 0.9, 1.0), strength=3.0),
        "ink": material("ink", srgb(0.06, 0.13, 0.16), rough=0.4),
        "magenta": material("magenta", srgb(1.0, 0.28, 0.82), rough=0.18, emit=srgb(1.0, 0.18, 0.75), strength=0.7,
                            coat=0.8),
        "teal": material("glow_teal", srgb(0.3, 1.0, 0.92), rough=0.3, emit=srgb(0.2, 1.0, 0.9), strength=2.5),
        "barrier": material("barrier", srgb(0.1, 0.8, 0.8), rough=0.1, emit=srgb(0.05, 0.7, 0.7), strength=1.0,
                            alpha=0.5),
    }


def slug_round(L, scale=1.0):
    """A slug: the glowing orange block the gun fires, seated in a square brass casing. Height 0.2, its middle at
    the origin; returns [head, casing pieces...]."""
    head = rounded_box("head", (0.1, 0.1, 0.11), 0.03, 4, L["orange"], location=(0, 0, 0.045))
    body = rounded_box("casing", (0.112, 0.112, 0.076), 0.016, 3, L["brass"], location=(0, 0, -0.03))
    groove = rounded_box("groove", (0.1, 0.1, 0.02), 0.006, 2, L["gunmetal"], location=(0, 0, -0.075))
    rim = rounded_box("rim", (0.126, 0.126, 0.022), 0.008, 3, L["brass"], location=(0, 0, -0.089))
    collar = rounded_box("collar", (0.118, 0.118, 0.014), 0.005, 2, L["gunmetal"], location=(0, 0, 0.006))
    parts = [head, body, groove, rim, collar]
    place(parts, scale=scale)
    return parts


def build_slug(L):
    parts = slug_round(L)
    head = join("head", [parts[0]])
    casing = join("casing", parts[1:])
    return [head, casing]


def build_slug_pack(L):
    rounds = []
    for x in (-0.15, 0.0, 0.15):
        rounds += place(slug_round(L), offset=(x, 0, 0.02))
    clip = rounded_box("clip", (0.47, 0.15, 0.024), 0.01, 3, L["steel"], location=(0, 0, -0.088))
    band = rounded_box("band", (0.46, 0.136, 0.03), 0.008, 2, L["gunmetal"], location=(0, 0, -0.03))
    parts = place(rounds + [clip, band], scale=1.1)
    return [join("slug_pack", parts)]


def build_extra_slug(L):
    parts = slug_round(L, scale=1.9)
    halo = torus("halo", 0.15, 0.012, L["chrome"], location=(0, 0, -0.06))
    return [join("extra_slug", parts + [halo])]


def build_steel(L):
    """Slock of Steel: Slock's own rounded block, in polished steel, armoured with riveted plates."""
    size, plate = 0.36, 0.22
    parts = [rounded_box("block", (size,) * 3, 0.06, 5, L["steel"])]
    for axis in range(3):
        for sign in (-1, 1):
            n = Vector([0, 0, 0])
            n[axis] = sign
            dims = [plate, plate, plate]
            dims[axis] = 0.03
            centre = n * (size * 0.5 - 0.008)
            parts.append(rounded_box("plate", dims, 0.012, 3, L["chrome"], location=centre))
            # rivets at the plate's corners
            u, v = [i for i in range(3) if i != axis]
            for su in (-1, 1):
                for sv in (-1, 1):
                    p = Vector(centre) + n * 0.017
                    p[u] += su * (plate * 0.5 - 0.03)
                    p[v] += sv * (plate * 0.5 - 0.03)
                    parts.append(uv_sphere("rivet", 0.013, L["gunmetal"], location=p, segments=12, rings=6))
    return [join("steel", parts)]


def build_clear_dots(L):
    """Clear the dots: three blue jelly pellets on chrome spokes round a ceramic hub, like a spinner."""
    parts = [rounded_box("hub", (0.13, 0.13, 0.06), 0.025, 4, L["ceramic"])]
    parts.append(torus("hub_ring", 0.066, 0.011, L["chrome"], segments=32, sides=12))
    for k in range(3):
        a = math.radians(90 + 120 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        parts.append(cylinder("spoke", 0.013, 0.13, 12, L["chrome"], location=d * 0.12,
                              rotation=(0, math.radians(90), a)))
        at = d * 0.21
        parts.append(uv_sphere("pellet", 0.088, L["blue_jelly"], location=at))
        parts.append(uv_sphere("core", 0.05, L["blue_core"], location=at, segments=20, rings=10))
        parts.append(torus("collar", 0.09, 0.011, L["chrome"], location=at, segments=32, sides=12))
    return [join("clear_dots", parts)]


def build_close_traps(L):
    """Close the traps: a floor patch, a ceramic plate with a glowing green inset and a plus, bolted at its corners."""
    outer = chamfered_square(0.23, 0.23, 0.07)
    inner = chamfered_square(0.165, 0.165, 0.045)
    parts = [ring_prism("frame", outer, inner, -0.025, 0.025, L["ceramic"], edge=0.008, segments=3)]
    parts.append(prism("inset", chamfered_square(0.168, 0.168, 0.047), -0.02, 0.012, L["green"], edge=0.004))
    for w, h in ((0.2, 0.055), (0.055, 0.2)):
        parts.append(rounded_box("plus", (w, h, 0.03), 0.012, 3, L["mint"], location=(0, 0, 0.016)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(cylinder("bolt", 0.016, 0.014, 6, L["chrome"], location=(sx * 0.17, sy * 0.17, 0.028),
                                  edge=0.004))
    parts.append(prism("base", outer, -0.035, -0.024, L["gunmetal"], edge=0.006))
    return [join("close_traps", parts)]


def build_clock(L):
    """The clock: an hourglass of cyan glass in a ceramic and chrome frame, running with glowing sand."""
    h = 0.25                                     # half the glass's height
    glass = [(0.0, -h), (0.055, -h), (0.085, -h + 0.03), (0.104, -0.13), (0.09, -0.07), (0.045, -0.025),
             (0.017, 0.0), (0.045, 0.025), (0.09, 0.07), (0.104, 0.13), (0.085, h - 0.03), (0.055, h), (0.0, h)]
    parts = [lathe("glass", glass, 48, L["glass"], angle=80.0)]
    parts.append(lathe("sand_low", [(0.0, -h + 0.008), (0.083, -h + 0.03), (0.09, -0.16), (0.05, -0.135),
                                   (0.0, -0.118)], 40, L["cyan"], angle=80.0))
    parts.append(lathe("sand_high", [(0.0, 0.028), (0.03, 0.04), (0.075, 0.08), (0.0, 0.09)], 40, L["cyan"],
                       angle=80.0))
    parts.append(cylinder("stream", 0.005, 0.15, 8, L["cyan"], location=(0, 0, -0.045)))
    for z in (-h - 0.016, h + 0.016):
        parts.append(cylinder("cap", 0.15, 0.034, 48, L["ceramic"], location=(0, 0, z), edge=0.01, segments=3))
        parts.append(torus("cap_ring", 0.148, 0.011, L["cyan"], location=(0, 0, z), segments=48, sides=12))
    # On top, what the game's camera sees most of: a glowing clock face.
    top = h + 0.033
    parts.append(cylinder("dial", 0.118, 0.008, 48, L["cyan"], location=(0, 0, top), edge=0.002))
    for k in range(4):
        a = math.radians(90 * k)
        tick = rounded_box("tick", (0.03, 0.012, 0.006), 0.003, 1, L["ink"],
                           location=(0.09 * math.cos(a), 0.09 * math.sin(a), top + 0.004))
        tick.rotation_euler = (0, 0, a)
        parts.append(tick)
    for length, width, angle in ((0.085, 0.012, 90.0), (0.058, 0.017, 20.0)):
        a = math.radians(angle)
        hand = rounded_box("hand", (length, width, 0.006), 0.003, 1, L["ink"],
                           location=(0.5 * length * math.cos(a), 0.5 * length * math.sin(a), top + 0.006))
        hand.rotation_euler = (0, 0, a)
        parts.append(hand)
    parts.append(cylinder("pin", 0.014, 0.01, 16, L["chrome"], location=(0, 0, top + 0.008), edge=0.003))
    for k in range(3):
        a = math.radians(90 + 120 * k)
        parts.append(cylinder("pillar", 0.012, 2 * h, 12, L["chrome"],
                              location=(0.127 * math.cos(a), 0.127 * math.sin(a), 0)))
    return [join("clock", parts)]


def build_key(L):
    """The key: chunky and magenta, lying flat, its bow a rounded square ring round a chrome eye."""
    t = 0.032                                    # half its thickness
    parts = [ring_prism("bow", chamfered_square(0.105, 0.105, 0.035, -0.17, 0),
                        chamfered_square(0.052, 0.052, 0.016, -0.17, 0), -t, t, L["magenta"], edge=0.014, segments=3)]
    parts.append(ring_prism("eye", chamfered_square(0.055, 0.055, 0.018, -0.17, 0),
                            chamfered_square(0.04, 0.04, 0.012, -0.17, 0), -t * 0.8, t * 0.8, L["chrome"],
                            edge=0.004))
    parts.append(rounded_box("collar", (0.045, 0.1, 2 * t + 0.01), 0.012, 3, L["chrome"], location=(-0.05, 0, 0)))
    parts.append(rounded_box("shaft", (0.27, 0.055, 2 * t - 0.006), 0.018, 3, L["magenta"], location=(0.085, 0, 0)))
    parts.append(rounded_box("tooth", (0.045, 0.085, 2 * t - 0.006), 0.012, 3, L["magenta"],
                             location=(0.195, -0.05, 0)))
    parts.append(rounded_box("tooth", (0.04, 0.06, 2 * t - 0.006), 0.012, 3, L["magenta"], location=(0.12, -0.04, 0)))
    parts.append(rounded_box("tip", (0.03, 0.065, 2 * t), 0.012, 3, L["chrome"], location=(0.225, 0, 0)))
    return [join("key", place(parts, scale=1.15))]


def build_gate(L):
    """The gate, for the exit tile (centred on it, standing on the floor): a ceramic frame whose posts stand in the
    walls either side and rise above them, joined by a lintel, with teal light strips; and the barrier that fills the
    opening until the gate opens."""
    frame = []
    for sx in (-1, 1):
        post = gd(sx * 0.5625, 0.66, 0)
        frame.append(rounded_box("post", (0.155, 1.12, 1.32), 0.02, 3, L["ceramic"], location=post))
        frame.append(rounded_box("post_cap", (0.18, 0.2, 0.05), 0.014, 3, L["chrome"],
                                 location=gd(sx * 0.5625, 1.345, 0)))
        for sz in (-1, 1):   # light strips down the front and back of each post
            frame.append(rounded_box("strip", (0.03, 0.02, 1.05), 0.008, 2, L["teal"],
                                     location=gd(sx * 0.5625, 0.6, sz * 0.56)))
        frame.append(rounded_box("strip", (0.012, 0.04, 1.02), 0.005, 2, L["teal"],
                                 location=gd(sx * 0.483, 0.56, 0)))
    frame.append(rounded_box("lintel", (1.3, 0.34, 0.15), 0.025, 3, L["ceramic"], location=gd(0, 1.25, 0)))
    for sz in (-1, 1):
        frame.append(rounded_box("lintel_strip", (0.9, 0.02, 0.035), 0.008, 2, L["teal"],
                                 location=gd(0, 1.25, sz * 0.17)))
    barrier = rounded_box("barrier", (0.96, 0.9, 1.15), 0.02, 2, L["barrier"], location=gd(0, 0.575, 0))
    return [join("frame", frame), join("barrier", [barrier])]


def build_chevron(L):
    """A booster chevron, flat on the ramp, pointing uphill (-z in the game): a glowing orange insert in a dark
    housing."""
    def vee(tip, back, half_w, arm):
        return [(-half_w, back), (0.0, tip), (half_w, back), (half_w, back - arm), (0.0, tip - arm),
                (-half_w, back - arm)][::-1]
    glow = material("glow_chevron", srgb(1.0, 0.55, 0.1), rough=0.3, emit=srgb(1.0, 0.5, 0.06), strength=3.5)
    parts = [prism("housing", vee(0.22, -0.05, 0.34, 0.18), 0.0, 0.012, L["gunmetal"], edge=0.004)]
    parts.append(prism("light", vee(0.185, -0.06, 0.285, 0.11), 0.0, 0.022, glow, edge=0.005))
    return [join("chevron", parts)]


PICKUPS = {
    "slug": build_slug,
    "slug_pack": build_slug_pack,
    "extra_slug": build_extra_slug,
    "steel": build_steel,
    "clear_dots": build_clear_dots,
    "close_traps": build_close_traps,
    "clock": build_clock,
    "key": build_key,
    "gate": build_gate,
    "chevron": build_chevron,
}


def build_pickups():
    for name, build in PICKUPS.items():
        reset()
        objects = build(pickup_looks())
        export_glb(os.path.join(MODELS, f"{name}.glb"), objects)
        if PREVIEW:
            preview(name, objects)


def preview(name, objects):
    """A studio render of a model, from about the game camera's angle, into the --preview folder."""
    sc = bpy.context.scene
    os.makedirs(PREVIEW, exist_ok=True)
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for ob in objects:
        for c in ob.bound_box:
            p = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    centre, radius = (lo + hi) * 0.5, (hi - lo).length * 0.5
    cam = bpy.data.cameras.new("cam")
    cam.lens = 85
    ob = link(bpy.data.objects.new("cam", cam))
    direction = Vector((0.55, -1.0, 1.05)).normalized()
    ob.location = centre + direction * radius * 4.3
    ob.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    sc.camera = ob
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.5
    sun.angle = math.radians(4)
    s = link(bpy.data.objects.new("sun", sun))
    s.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    # The game's light: a sun from the same side, and a plain grey sky, lighter overhead, for the reflections.
    world = sc.world
    if world.node_tree is None:
        world.use_nodes = True  # Blender 4
    nt = world.node_tree
    nt.nodes.clear()
    coords = nt.nodes.new("ShaderNodeTexCoord")
    split = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (0.1, 0.1, 0.1, 1)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (0.6, 0.6, 0.6, 1)
    to01 = nt.nodes.new("ShaderNodeMapRange")
    to01.inputs["From Min"].default_value = -1.0
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(coords.outputs["Generated"], split.inputs["Vector"])
    nt.links.new(split.outputs["Z"], to01.inputs["Value"])
    nt.links.new(to01.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 640
    sc.cycles.samples = 32 if QUICK else 128
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 8
    sc.cycles.transparent_max_bounces = 16
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.filepath = os.path.join(PREVIEW, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("preview", sc.render.filepath)


def main():
    if ONLY in (None, "kit"):
        build_kit()
    if ONLY in (None, "textures"):
        for name, (build, options) in TEXTURE_SETS.items():
            bake_set(name, build, **options)
    if ONLY in (None, "pickups"):
        build_pickups()


main()
if not bpy.app.binary_path:
    # Run as Blender's Python module rather than in Blender: skip the interpreter's shutdown, which crashes after a
    # glTF export in some versions (4.2). Everything is written by now.
    sys.stdout.flush()
    os._exit(0)
