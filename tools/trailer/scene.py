"""Slock teaser: builds the whole scene in Blender and renders PNG frames.

Run through make_trailer.py, or directly:
    flatpak run org.blender.Blender -b --python tools/trailer/scene.py -- [--preview] [--frames A-B]

Everything is procedural and baked per frame: the maze (real tile textures), Slock, the Slorms,
the voxel-jelly SLOCK letters, the kinetic type and every camera move. The timeline sits on a
120 BPM grid (a beat every 15 frames at 30 fps) so the hits line up with the soundtrack, which
make_trailer.py synthesizes from the impacts.json this script writes.
"""
import bpy, bmesh, json, math, random, sys
from pathlib import Path
from mathutils import Vector, Quaternion, Euler

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Builds" / "Trailer"
TEX = ROOT / "textures"
FONT_PATHS = ["/run/host/usr/share/fonts/truetype/noto/NotoSansDisplay-CondensedBlack.ttf",
              "/usr/share/fonts/truetype/noto/NotoSansDisplay-CondensedBlack.ttf"]

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = "--preview" in args
FRAME_RANGE = (1, 525)
for a in args:
    if "-" in a and a[0].isdigit():
        lo, hi = a.split("-")
        FRAME_RANGE = (int(lo), int(hi))
FPS = 30
END = 525
rng = random.Random(7)

# ---------------------------------------------------------------------------------------------
# small math helpers
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def lerp(a, b, t): return a + (b - a) * t
def vlerp(a, b, t): return Vector(a).lerp(Vector(b), t)
def seg(f, f0, f1): return clamp((f - f0) / (f1 - f0)) if f1 != f0 else float(f >= f1)
def smooth(t): return t * t * (3 - 2 * t)
def out_expo(t): return 1.0 if t >= 1 else 1 - 2 ** (-10 * t)
def in_quad(t): return t * t
def out_back(t, s=2.2):
    t -= 1
    return t * t * ((s + 1) * t + s) + 1
def wobble(k, decay=3.0, freq=1.1):
    """Damped jelly spring, 1 at the moment of impact, settling to 0."""
    return math.exp(-k / decay) * math.cos(k * freq) if k >= 0 else 0.0

# ---------------------------------------------------------------------------------------------
# timeline (beat k lands on frame 1 + 15k)
IMPACTS = []        # (frame, strength 0..1, kind) -> camera shake, flashes, sound
def hit(f, amp, kind): IMPACTS.append((f, amp, kind))

LAND = 16                          # Slock drops in
GO = 30                            # Slock takes off down the corridor
WORD_HITS = [46, 61, 76]           # TILT / THE / WORLD, camera flies through each
CRANE = 106                        # whip up to the aerial view
LETTER_LAND = [151, 166, 181, 196, 211]  # S L O C K
E_IN, E_DEV0 = 256, 262            # IN, then DEVELOPMENT letters every 2 frames
E_OUT = 331
F_COMING = 346
F_SOON = [361, 368, 376, 383]
FINAL = 421
SLOCK_TOP = 436                    # Slock lands on top of the O
CAPTION = 443

hit(LAND, 0.8, "boom")
hit(41, 0.6, "hit")
for f in WORD_HITS: hit(f, 0.55, "hit")
hit(96, 0.35, "whoosh")
hit(CRANE + 6, 0.4, "whoosh")
for f in LETTER_LAND: hit(f, 0.85, "boom")
hit(E_IN, 1.0, "boom")
for k in range(11): hit(E_DEV0 + 2 * k, 0.18, "tick")
hit(E_DEV0 + 20, 0.5, "hit")
hit(287, 0.3, "whoosh")
for f in (301, 316): hit(f, 0.45, "hit")
hit(E_OUT + 4, 0.5, "whoosh")
hit(F_COMING, 0.9, "boom")
for f in F_SOON: hit(f, 0.75, "hit")
hit(391, 0.0, "riser")
hit(412, 0.4, "whoosh")
hit(FINAL, 1.0, "boom")
hit(SLOCK_TOP, 0.7, "boom")
hit(CAPTION, 0.3, "whoosh")

def impact_env(f):
    e = 0.0
    for fi, amp, kind in IMPACTS:
        if kind in ("whoosh", "riser", "tick"):
            continue
        if f >= fi:
            e += amp * math.exp(-(f - fi) / 4.5)
    return min(e, 1.4)

# ---------------------------------------------------------------------------------------------
# scene reset + render settings
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = FRAME_RANGE
sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "OPTIX"
prefs.get_devices()
for d in prefs.devices:
    d.use = d.type == "OPTIX"
sc.cycles.device = "GPU"
sc.cycles.samples = 16 if PREVIEW else 96
sc.cycles.use_adaptive_sampling = True
sc.cycles.adaptive_threshold = 0.02
sc.cycles.use_denoising = True
sc.cycles.denoiser = "OPENIMAGEDENOISE"   # the flatpak cannot reach the OptiX denoiser weights
sc.cycles.denoising_use_gpu = True
sc.cycles.max_bounces = 8
sc.cycles.transmission_bounces = 8
sc.cycles.transparent_max_bounces = 8
sc.cycles.caustics_reflective = sc.cycles.caustics_refractive = False
sc.cycles.blur_glossy = 1.0
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.render.resolution_percentage = 50 if PREVIEW else 100
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = 0.5
sc.render.use_persistent_data = True
sc.render.image_settings.file_format = "PNG"
sc.render.filepath = str(OUT / ("preview" if PREVIEW else "frames") / "f_")
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure = 0.0

# world: black to the camera (the void), soft grey fill for everything else
world = bpy.data.worlds.new("Void")
sc.world = world
world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links
wn.clear()
lp = wn.new("ShaderNodeLightPath")
bg_fill = wn.new("ShaderNodeBackground"); bg_fill.inputs[0].default_value = (0.55, 0.58, 0.66, 1); bg_fill.inputs[1].default_value = 0.45
bg_void = wn.new("ShaderNodeBackground"); bg_void.inputs[0].default_value = (0, 0, 0, 1)
mix = wn.new("ShaderNodeMixShader")
wout = wn.new("ShaderNodeOutputWorld")
wl.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
wl.new(bg_fill.outputs[0], mix.inputs[1])
wl.new(bg_void.outputs[0], mix.inputs[2])
wl.new(mix.outputs[0], wout.inputs[0])

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 3.2
sun_data.angle = math.radians(1.5)
sun = bpy.data.objects.new("Sun", sun_data)
sc.collection.objects.link(sun)
sun.rotation_euler = Euler((math.radians(38), math.radians(-18), math.radians(-28)))

# bloom on the bright stuff
comp = bpy.data.node_groups.new("Comp", "CompositorNodeTree")
comp.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
rl = comp.nodes.new("CompositorNodeRLayers")
glare = comp.nodes.new("CompositorNodeGlare")
glare.inputs["Type"].default_value = "Bloom"
glare.inputs["Threshold"].default_value = 1.0
glare.inputs["Strength"].default_value = 0.6
glare.inputs["Size"].default_value = 0.6
gout = comp.nodes.new("NodeGroupOutput")
comp.links.new(rl.outputs["Image"], glare.inputs["Image"])
comp.links.new(glare.outputs["Image"], gout.inputs[0])
sc.compositing_node_group = comp
sc.render.use_compositing = True

# ---------------------------------------------------------------------------------------------
# materials
def principled(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree.nodes["Principled BSDF"], m.node_tree

def tile_material(name, stem):
    m, p, nt = principled(name)
    base = nt.nodes.new("ShaderNodeTexImage"); base.image = bpy.data.images.load(str(TEX / f"{stem}_base.png"))
    ao = nt.nodes.new("ShaderNodeTexImage"); ao.image = bpy.data.images.load(str(TEX / f"{stem}_ao.png"))
    ao.image.colorspace_settings.name = "Non-Color"
    nrm = nt.nodes.new("ShaderNodeTexImage"); nrm.image = bpy.data.images.load(str(TEX / f"{stem}_normal.png"))
    nrm.image.colorspace_settings.name = "Non-Color"
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nmap = nt.nodes.new("ShaderNodeNormalMap"); nmap.inputs["Strength"].default_value = 0.8
    nt.links.new(base.outputs["Color"], mul.inputs[6])
    nt.links.new(ao.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], p.inputs["Base Color"])
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = 0.55
    return m

def jelly(name, color, emit, transmission=0.8):
    m, p, _ = principled(name)
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = 0.06
    p.inputs["IOR"].default_value = 1.33
    p.inputs["Transmission Weight"].default_value = transmission
    p.inputs["Coat Weight"].default_value = 0.6
    p.inputs["Coat Roughness"].default_value = 0.03
    p.inputs["Emission Color"].default_value = (*color, 1)
    p.inputs["Emission Strength"].default_value = emit
    return m

def emissive(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (*color, 1)
    e.inputs[1].default_value = strength
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m

def hazard(name):
    """Yellow/black construction stripes, self-lit so they read anywhere."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 2.2
    frac = nt.nodes.new("ShaderNodeMath"); frac.operation = "FRACT"
    gt = nt.nodes.new("ShaderNodeMath"); gt.operation = "GREATER_THAN"; gt.inputs[1].default_value = 0.5
    mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"
    mx.inputs[6].default_value = (1.0, 0.72, 0.02, 1)
    mx.inputs[7].default_value = (0.01, 0.01, 0.01, 1)
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs[1].default_value = 1.6
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    L = nt.links.new
    L(tc.outputs["Object"], sep.inputs[0])
    L(sep.outputs[0], add.inputs[0]); L(sep.outputs[1], add.inputs[1])
    L(add.outputs[0], mul.inputs[0]); L(mul.outputs[0], frac.inputs[0])
    L(frac.outputs[0], gt.inputs[0]); L(gt.outputs[0], mx.inputs["Factor"])
    L(mx.outputs[2], em.inputs[0]); L(em.outputs[0], o.inputs[0])
    return m

M_FLOOR = tile_material("Floor", "floor")
M_TOPS = tile_material("Tops", "tops")
M_WALLS = tile_material("Walls", "walls")
M_SLOCK = jelly("SlockJelly", (0.85, 0.0, 0.06), 0.35)
M_CORE = jelly("SlockCore", (0.45, 0.0, 0.04), 0.6, transmission=0.0)
M_WORM = jelly("SlormJelly", (0.2, 0.75, 0.12), 0.25, transmission=0.55)
M_WORM_CORE = jelly("SlormCore", (0.04, 0.3, 0.02), 0.4, transmission=0.0)
M_PELLET = jelly("Pellet", (0.25, 0.55, 1.0), 1.2)
M_GOLD = jelly("Gold", (1.0, 0.75, 0.1), 1.4)
M_TXT_WHITE = emissive("TypeWhite", (1, 1, 1), 2.2)
M_TXT_RED = emissive("TypeRed", (1.0, 0.03, 0.08), 3.5)
M_TXT_BLACK = principled("TypeBlack")[0]
M_TXT_BLACK.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.01, 0.01, 0.012, 1)
M_TXT_BLACK.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.25
M_HAZARD = hazard("Hazard")
M_BAR = emissive("Bar", (0.0, 0.0, 0.0), 1.0)

# ---------------------------------------------------------------------------------------------
# objects
def link(obj, parent=None):
    sc.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj

def empty(name, parent=None):
    return link(bpy.data.objects.new(name, None), parent)

def rounded_cube_mesh(name, size, bevel, segments=3):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=size)
    bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, offset_type="OFFSET",
                    segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    return me

JELLY_MESH = rounded_cube_mesh("JellyCube", 1.0, 0.16)
CORE_MESH = rounded_cube_mesh("CoreCube", 0.55, 0.1)
PELLET_MESH = rounded_cube_mesh("PelletCube", 0.2, 0.03, 2)
for me in (JELLY_MESH, CORE_MESH, PELLET_MESH):
    me.materials.append(None)          # one slot; each object fills it with its own material

def mesh_object(name, mesh, mat, parent=None):
    o = link(bpy.data.objects.new(name, mesh), parent)
    o.material_slots[0].link = "OBJECT"
    o.material_slots[0].material = mat
    return o

def jelly_block(name, size, mat, core_mat=None, parent=None):
    o = mesh_object(name, JELLY_MESH, mat, parent)
    o["size"] = size
    o.scale = (size,) * 3
    if core_mat:
        mesh_object(name + "Core", CORE_MESH, core_mat, o)
    return o

WORLD = empty("World")      # the whole level hangs off this so it can tilt

# ---------------------------------------------------------------------------------------------
# maze
N = 41
H = 1.0          # wall height
SLAB = 2.0       # floating slab thickness under the floor
def X(i): return i - N // 2
def I(x): return int(round(x)) + N // 2

wall = [[True] * N for _ in range(N)]
stack = [(1, 1)]
wall[1][1] = False
while stack:
    i, j = stack[-1]
    nbrs = [(i + di, j + dj, di, dj) for di, dj in ((2, 0), (-2, 0), (0, 2), (0, -2))
            if 0 < i + di < N - 1 and 0 < j + dj < N - 1 and wall[i + di][j + dj]]
    if not nbrs:
        stack.pop()
        continue
    ni, nj, di, dj = rng.choice(nbrs)
    wall[i + di // 2][j + dj // 2] = False
    wall[ni][nj] = False
    stack.append((ni, nj))
# braid: knock out extra walls so it plays like the game's loopy layout
for i in range(1, N - 1):
    for j in range(1, N - 1):
        if wall[i][j] and (i + j) % 2 == 1 and rng.random() < 0.22:
            wall[i][j] = False

CORRIDOR_J = I(-15)
CROSS_X = 9
for i in range(1, N - 1):
    wall[i][CORRIDOR_J] = False                      # the long chase corridor
for j in range(1, I(-11) + 1):
    wall[I(CROSS_X)][j] = False                      # the Slorm's crossing
for i in range(I(-17), I(17) + 1):
    for j in range(I(-5), I(2) + 1):
        wall[i][j] = False                           # plaza the SLOCK letters stand in

def is_wall(i, j):
    return i < 0 or j < 0 or i >= N or j >= N or wall[i][j]

def build_maze():
    me = bpy.data.meshes.new("Maze")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    UVS = ((0, 0), (1, 0), (1, 1), (0, 1))

    def quad(pts, mat):
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        f.material_index = mat
        for loop, t in zip(f.loops, UVS):
            loop[uv].uv = t

    def side(cx, cy, n, z0, z1, mat):
        t = Vector((0, 0, 1)).cross(Vector((n[0], n[1], 0)))
        c = Vector((cx + n[0] * 0.5, cy + n[1] * 0.5, 0))
        a, b = c - t * 0.5, c + t * 0.5
        quad([(a.x, a.y, z0), (b.x, b.y, z0), (b.x, b.y, z1), (a.x, a.y, z1)], mat)

    for i in range(N):
        for j in range(N):
            x, y = X(i), X(j)
            if wall[i][j]:
                quad([(x - .5, y - .5, H), (x + .5, y - .5, H), (x + .5, y + .5, H), (x - .5, y + .5, H)], 1)
                for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ni, nj = i + di, j + dj
                    if ni < 0 or nj < 0 or ni >= N or nj >= N:
                        for z in range(-int(SLAB), int(H)):
                            side(x, y, (di, dj), z, z + 1, 2)
                    elif not wall[ni][nj]:
                        side(x, y, (di, dj), 0, H, 2)
            else:
                quad([(x - .5, y - .5, 0), (x + .5, y - .5, 0), (x + .5, y + .5, 0), (x - .5, y + .5, 0)], 0)
    h = N / 2
    quad([(-h, h, -SLAB), (h, h, -SLAB), (h, -h, -SLAB), (-h, -h, -SLAB)], 2)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(me)
    bm.free()
    for m in (M_FLOOR, M_TOPS, M_WALLS):
        me.materials.append(m)
    return link(bpy.data.objects.new("Maze", me), WORLD)

build_maze()

# ---------------------------------------------------------------------------------------------
# animation baking: every animated thing is a function of the frame, keyed once per frame
ANIMS = []
def animate(obj, f0, f1, fn):
    ANIMS.append((obj, max(int(f0), 0), min(int(math.ceil(f1)), END + 1), fn))

def bake():
    for obj, f0, f1, fn in ANIMS:
        for f in range(f0, f1 + 1):
            d = fn(f)
            for key in ("location", "rotation_euler", "rotation_quaternion", "scale"):
                if key in d:
                    setattr(obj, key, d[key])
                    obj.keyframe_insert(key, frame=f)
            if "lens" in d:
                obj.data.lens = d["lens"]
                obj.data.keyframe_insert("lens", frame=f)

HIDDEN = Vector((0, 0, -60))

# ---------------------------------------------------------------------------------------------
# Slock
VMAX, ACC = 0.4, 0.06
X0 = -18.0
def slock_x(f):
    if f <= GO:
        return X0
    t = f - GO
    tv = VMAX / ACC
    d = 0.5 * ACC * t * t if t < tv else 0.5 * ACC * tv * tv + VMAX * (t - tv)
    return min(X0 + d, 19.0)

slock = jelly_block("Slock", 0.8, M_SLOCK, M_CORE, WORLD)
def slock_anim(f):
    s = 0.8
    if f <= 135:
        x, y = slock_x(f), -15.0
        if f < 4:
            z = 30.0
        elif f < LAND:
            z = 0.4 + 10 * (1 - seg(f, 4, LAND)) ** 2
        else:
            z = 0.4
        w = wobble(f - LAND) - 0.5 * wobble(f - GO, 2.5, 1.3)
        stretch = 0.25 * math.exp(-max(0, f - GO) / 6) if f > GO else 0
        sz = 1 - 0.38 * w
        return {"location": Vector((x, y, z - 0.4 * (1 - sz))),
                "scale": Vector((s * (1 + 0.2 * w + stretch), s * (1 + 0.2 * w), s * sz))}
    if f < SLOCK_TOP - 10:
        return {"location": HIDDEN, "scale": Vector((0, 0, 0))}
    top = 6.97 + 0.4
    z = top + 14 * (1 - seg(f, SLOCK_TOP - 10, SLOCK_TOP)) ** 2
    w = wobble(f - SLOCK_TOP)
    sz = 1 - 0.4 * w
    return {"location": Vector((0, 0, z - 0.4 * (1 - sz))),
            "scale": Vector((s * (1 + 0.22 * w), s * (1 + 0.22 * w), s * sz))}
animate(slock, 1, END, slock_anim)

# ---------------------------------------------------------------------------------------------
# pellets (the ones in the chase corridor get eaten as Slock passes)
LETTER_ROW = I(0)
pellet_cells = []
for i in range(1, N - 1):
    for j in range(1, N - 1):
        if not wall[i][j] and not (I(-17) <= i <= I(17) and I(-1) <= j <= I(1)):
            if j == CORRIDOR_J and X(i) > -16 or rng.random() < 0.55:
                pellet_cells.append((i, j))
for i, j in pellet_cells:
    gold = rng.random() < 0.06
    p = mesh_object("Pellet", PELLET_MESH, M_GOLD if gold else M_PELLET, WORLD)
    if gold:
        p.scale = (1.6,) * 3
    p.location = (X(i), X(j), 0.35)
    p.rotation_euler = (rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0, 6.3))
    if j == CORRIDOR_J and X(i) > -16:
        x = X(i)
        eat = next(f for f in range(GO, 200) if slock_x(f) >= x - 0.5)
        def pellet_anim(f, eat=eat, base=Vector(p.location)):
            k = f - eat
            s = 1.0 if k < 0 else (1.5 if k == 0 else 0.0)
            return {"scale": Vector((s, s, s)), "location": base + Vector((0, 0, 0.3 if k == 0 else 0))}
        animate(p, eat - 1, eat + 1, pellet_anim)

# ---------------------------------------------------------------------------------------------
# Slorms: a head and five segments, inch-worming along maze paths
SEG_SIZES = [0.8, 0.64, 0.512, 0.41, 0.328, 0.262]
BLOCKED = {(i, CORRIDOR_J) for i in range(N)} | {(i, LETTER_ROW) for i in range(I(-15), I(15) + 1)}

def random_walk(start, steps):
    path = [start]
    prev = None
    cur = start
    for _ in range(steps):
        i, j = cur
        opts = [(i + di, j + dj) for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if not is_wall(i + di, j + dj) and (i + di, j + dj) not in BLOCKED]
        fwd = [o for o in opts if prev and (o[0] - i, o[1] - j) == (i - prev[0], j - prev[1])]
        back = [o for o in opts if o == prev]
        choices = [o for o in opts if o != prev] or back or [cur]
        nxt = fwd[0] if fwd and rng.random() < 0.6 else rng.choice(choices)
        prev, cur = cur, nxt
        path.append(cur)
    return [Vector((X(i), X(j))) for i, j in path]

def sample(path, s):
    s = clamp(s, 0, len(path) - 1)
    k = min(int(s), len(path) - 2)
    return path[k].lerp(path[k + 1], s - k)

def inch(u):
    """Steppy progress: pauses at every whole tile, like the game's inch-worm crawl."""
    n = math.floor(u)
    return n + smooth(smooth(u - n))

def make_slorm(name, path, progress):
    offsets, acc = [], 0.0
    for k, s in enumerate(SEG_SIZES):
        if k:
            acc += (SEG_SIZES[k - 1] + s) / 2 + 0.08
        offsets.append(acc)
    for k, s in enumerate(SEG_SIZES):
        o = jelly_block(f"{name}_{k}", s, M_WORM, M_WORM_CORE if k == 0 else None, WORLD)
        def fn(f, k=k, s=s):
            u = progress(f - 2.2 * k) - offsets[k]
            p = sample(path, u)
            bob = 0.04 * math.sin((f - 2.2 * k) * 0.5)
            return {"location": Vector((p.x, p.y, s / 2 + abs(bob)))}
        animate(o, 1, END, fn)

# Slorm 0 cuts across the chase corridor right in front of Slock
cross = [Vector((CROSS_X, y)) for y in range(-19, -10)]
cont = random_walk((I(CROSS_X), I(-11)), 60)
path0 = cross + cont[1:]
def prog0(f):
    if f < 74:
        return 0.0
    if f < 98:
        return (f - 74) / 3.0
    return 8 + inch((f - 98) / 8.0)
make_slorm("Slorm0", path0, prog0)

open_cells = [(i, j) for i in range(1, N - 1) for j in range(1, N - 1)
              if not wall[i][j] and (i, j) not in BLOCKED]
starts = [(I(-12), I(-3)), (I(10), I(-4)), (I(-6), I(8)), (I(14), I(9)), (I(0), I(-9))]
for n, st in enumerate(starts, 1):
    if st not in open_cells:
        st = min(open_cells, key=lambda c: (c[0] - st[0]) ** 2 + (c[1] - st[1]) ** 2)
    path = random_walk(st, 90)
    speed = 7.0 + n
    make_slorm(f"Slorm{n}", path, lambda f, speed=speed: 6 + inch(max(f, 0) / speed))

# ---------------------------------------------------------------------------------------------
# SLOCK in voxel jelly, raining down one letter per beat
GLYPHS = {
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
}
LETTER_CENTERS = []
for li, ch in enumerate("SLOCK"):
    x0 = -14 + li * 6
    LETTER_CENTERS.append(Vector((x0 + 2, 0, 3.5)))
    L = LETTER_LAND[li]
    for r, row in enumerate(GLYPHS[ch]):
        for c, px in enumerate(row):
            if px != "#":
                continue
            v = jelly_block(f"Vox{ch}{r}{c}", 0.94, M_SLOCK, M_CORE, WORLD)
            final = Vector((x0 + c, 0, 0.5 + (6 - r)))
            land = L - 4 + (6 - r) * 0.8 + rng.uniform(-1, 1)
            dur = 10.0
            spin = Vector((rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2)))
            scatter = Vector((rng.uniform(-3, 3), rng.uniform(-3, 3), 0))
            def fn(f, final=final, land=land, dur=dur, spin=spin, scatter=scatter):
                t = (f - (land - dur)) / dur
                if t < 0:
                    return {"location": final + Vector((0, 0, 40)), "scale": Vector((0, 0, 0)),
                            "rotation_euler": Euler((0, 0, 0))}
                s = 0.94
                if t < 1:
                    q = (1 - t) ** 2
                    return {"location": final + scatter * q + Vector((0, 0, 16 * q)),
                            "rotation_euler": Euler(spin * q), "scale": Vector((s, s, s))}
                w = wobble(f - land)
                sz = 1 - 0.3 * w
                return {"location": final - Vector((0, 0, 0.47 * (1 - sz))), "rotation_euler": Euler((0, 0, 0)),
                        "scale": Vector((s * (1 + 0.15 * w), s * (1 + 0.15 * w), s * sz))}
            animate(v, int(land - dur) - 2, int(land) + 22, fn)

# ---------------------------------------------------------------------------------------------
# kinetic type
font = None
for fp in FONT_PATHS:
    if Path(fp).exists():
        font = bpy.data.fonts.load(fp)
        break

def word(text, height, mat, parent, extrude=0.06):
    """One object per letter so each can fly on its own. Returns [(obj, x_offset)], width."""
    objs = []
    for ch in text:
        if ch == " ":
            objs.append((None, height * 0.28))
            continue
        cu = bpy.data.curves.new(f"T_{ch}", "FONT")
        cu.body = ch
        if font:
            cu.font = font
        cu.size = height / 0.72
        cu.extrude = extrude * height
        cu.bevel_depth = 0.012 * height
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.materials.append(mat)
        o = link(bpy.data.objects.new(f"T_{ch}", cu), parent)
        objs.append((o, None))
    bpy.context.view_layer.update()
    track = 0.05 * height
    widths = [w if o is None else o.dimensions.x for o, w in objs]
    total = sum(widths) + track * (len(widths) - 1)
    x = -total / 2
    out = []
    for (o, _), w in zip(objs, widths):
        if o is not None:
            out.append((o, x + w / 2))
        x += w + track
    return out, total

FACE_NEG_Y = Euler((math.pi / 2, 0, 0))            # text standing up, facing -Y
FACE_NEG_X = Euler((math.pi / 2, 0, -math.pi / 2))  # text standing up, facing -X

# TILT / THE / WORLD hang over the chase corridor; the camera flies straight through them
CAM_BACK, CAM_Z = 3.2, 1.55
for wi, (txt, mat) in enumerate((("TILT", M_TXT_BLACK), ("THE", M_TXT_RED), ("WORLD", M_TXT_BLACK))):
    fh = WORD_HITS[wi]
    anchor = empty(f"Word{txt}", WORLD)
    anchor.location = (slock_x(fh) - CAM_BACK + 0.15, -15, CAM_Z)
    anchor.rotation_euler = FACE_NEG_X
    letters, _ = word(txt, 1.1, mat, anchor, extrude=0.15)
    for k, (o, lx) in enumerate(letters):
        pop = fh - 11 + k
        def fn(f, lx=lx, pop=pop, k=k, fh=fh):
            t = seg(f, pop, pop + 5)
            s = out_back(t) if t > 0 and f < fh + 3 else 0.0
            return {"location": Vector((lx, 0, 0)), "scale": Vector((s, s, s)),
                    "rotation_euler": Euler((0, 0, (1 - smooth(t)) * (0.8 if k % 2 else -0.8)))}
        animate(o, pop - 1, fh + 3, fn)

# IN DEVELOPMENT and COMING SOON hang off the near edge of the level, over the void
TYPE_AT = Vector((0, -30, 10.0))
e_anchor = empty("TypeE")
e_anchor.location = TYPE_AT
e_anchor.rotation_euler = FACE_NEG_Y
ex_rng = random.Random(3)

BURST = [Vector((ex_rng.uniform(-1, 1), ex_rng.uniform(-1, 2), 12)) for _ in range(16)]
def explode(f, lx, ly, k):
    """Shared exit: letters burst toward the camera and spin away."""
    t = seg(f, E_OUT + k * 0.4, E_OUT + 10 + k * 0.4)
    d = (Vector((lx * 0.6, ly, 0)) + BURST[k]) * in_quad(t)
    return d, t

in_letters, _ = word("IN", 2.3, M_TXT_RED, e_anchor, extrude=0.12)
for k, (o, lx) in enumerate(in_letters):
    def fn(f, lx=lx, k=k):
        if f >= E_OUT:
            d, t = explode(f, lx, 1.6, k)
            s = 1 - t
            return {"location": Vector((lx, 1.7, 0)) + d, "scale": Vector((s, s, s)),
                    "rotation_euler": Euler((t * 3, t * 2 * (k - .5), 0))}
        t = seg(f, E_IN - 6, E_IN)
        s = lerp(7.0, 1.0, in_quad(t)) if t < 1 else 1 + 0.12 * wobble(f - E_IN, 2.5)
        z = lerp(9.0, 0.0, in_quad(t))
        return {"location": Vector((lx, 1.7, z)), "scale": Vector((s, s, s)) if t > 0 else Vector((0, 0, 0)),
                "rotation_euler": Euler((0, 0, 0))}
    animate(o, E_IN - 8, E_OUT + 20, fn)

dev_letters, dev_w = word("DEVELOPMENT", 1.55, M_TXT_WHITE, e_anchor, extrude=0.1)
for k, (o, lx) in enumerate(dev_letters):
    land = E_DEV0 + 2 * k
    side = 1 if k % 2 else -1
    def fn(f, lx=lx, land=land, side=side, k=k):
        if f >= E_OUT:
            d, t = explode(f, lx, -0.5, k + 2)
            s = 1 - t
            return {"location": Vector((lx, -0.5, 0)) + d, "scale": Vector((s, s, s)),
                    "rotation_euler": Euler((t * 4 * side, 0, t * 2))}
        t = seg(f, land - 6, land)
        e = out_expo(t)
        s = 0.0 if t <= 0 else 1 + 0.25 * wobble(f - land, 2, 1.4)
        return {"location": Vector((lx, -0.5 + side * 5 * (1 - e), 3 * (1 - e))), "scale": Vector((s, s, s)),
                "rotation_euler": Euler((0, 0, side * 1.6 * (1 - e)))}
    animate(o, land - 8, E_OUT + 20, fn)

def hazard_strip(name, width, height, parent):
    me = bpy.data.meshes.new(name)
    w, h = width / 2, height / 2
    me.from_pydata([(-w, -h, 0), (w, -h, 0), (w, h, 0), (-w, h, 0)], [], [(0, 1, 2, 3)])
    me.materials.append(M_HAZARD)
    return link(bpy.data.objects.new(name, me), parent)

for n, (y, side) in enumerate(((-1.75, -1), (3.25, 1))):
    strip = hazard_strip(f"Tape{n}", dev_w + 4, 0.42, e_anchor)
    def fn(f, y=y, side=side):
        if f >= E_OUT:
            t = seg(f, E_OUT, E_OUT + 8)
            s = 1.0 if t < 1 else 0.0
            return {"location": Vector((side * 30 * in_quad(t), y, -0.2)), "scale": Vector((s, s, s))}
        t = out_expo(seg(f, 285, 293))
        s = 1.0 if f >= 285 else 0.0
        return {"location": Vector((-side * 30 * (1 - t), y, -0.2)), "scale": Vector((s, s, s))}
    strip.rotation_euler = Euler((0, 0, side * 0.04))
    animate(strip, 283, E_OUT + 9, fn)

f_anchor = empty("TypeF")
f_anchor.location = TYPE_AT
f_anchor.rotation_euler = FACE_NEG_Y
coming, _ = word("COMING", 2.0, M_TXT_WHITE, f_anchor, extrude=0.1)
mid = (len(coming) - 1) / 2
for k, (o, lx) in enumerate(coming):
    order = abs(k - mid)
    t0 = F_COMING - 6 + order * 0.8
    def fn(f, lx=lx, t0=t0):
        if f >= FINAL:
            return {"scale": Vector((0, 0, 0)), "location": Vector((lx, 1.5, 0))}
        t = seg(f, t0, t0 + 6)
        s = 0.0 if t <= 0 else (lerp(6.0, 1.0, in_quad(t)) if t < 1 else 1 + 0.1 * wobble(f - t0 - 6, 2.5))
        return {"location": Vector((lx * s if t < 1 else lx, 1.5, 10 * (1 - in_quad(t)))), "scale": Vector((s, s, s))}
    animate(o, int(t0) - 2, FINAL, fn)

soon, _ = word("SOON", 3.2, M_TXT_RED, f_anchor, extrude=0.18)
for k, (o, lx) in enumerate(soon):
    land = F_SOON[k]
    def fn(f, lx=lx, land=land):
        if f >= FINAL:
            return {"scale": Vector((0, 0, 0)), "location": Vector((lx, -1.4, 0))}
        t = seg(f, land - 7, land)
        if t <= 0:
            return {"scale": Vector((0, 0, 0)), "location": Vector((lx, 12, 0))}
        w = wobble(f - land)
        sy = 1 - 0.3 * w
        return {"location": Vector((lx, -1.4 + 13 * (1 - in_quad(t)) - 1.6 * (1 - sy), 0)),
                "scale": Vector((1 + 0.2 * w, sy, 1))}
    animate(o, land - 9, FINAL, fn)

# ---------------------------------------------------------------------------------------------
# world tilt while the type is up ("tilt the world")
TILTS = [(250, (0, 0)), (E_IN, (9, -11)), (286, (-7, 13)), (316, (11, 6)), (F_COMING, (-10, -9)),
         (F_SOON[0], (6, 12)), (F_SOON[2], (-8, -6)), (406, (0, 0))]
# tilt toward each new target on its beat
def world_anim(f):
    rot = (0.0, 0.0)
    for k in range(1, len(TILTS)):
        fa = TILTS[k][0]
        if f >= fa:
            prev = TILTS[k - 1][1]
            t = out_expo(seg(f, fa, fa + 9))
            rot = (lerp(prev[0], TILTS[k][1][0], t), lerp(prev[1], TILTS[k][1][1], t))
    if f >= TILTS[-1][0] + 9:
        rot = (0, 0)
    return {"rotation_euler": Euler((math.radians(rot[0]), math.radians(rot[1]), 0))}
WORLD.location = (0, 0, 0)
animate(WORLD, 248, 418, world_anim)

# ---------------------------------------------------------------------------------------------
# cameras: one per shot, switched by timeline markers (hard cuts)
def noise(f, seed):
    return (math.sin(f * 0.83 + seed) * 0.5 + math.sin(f * 1.91 + seed * 2.3) * 0.3
            + math.sin(f * 3.7 + seed * 5.1) * 0.2)

def make_shot(name, f0, f1, fn, rumble=0.12):
    data = bpy.data.cameras.new(name)
    data.clip_start, data.clip_end = 0.05, 400
    data.sensor_width = 36
    cam = link(bpy.data.objects.new(name, data))
    cam.rotation_mode = "QUATERNION"
    m = sc.timeline_markers.new(name, frame=f0)
    m.camera = cam
    prev = [None]

    def cam_anim(f):
        pos, target, roll, lens = fn(f)
        pos, target = Vector(pos), Vector(target)
        e = impact_env(f)
        amp = e + (rumble(f) if callable(rumble) else rumble)
        q = (target - pos).to_track_quat("-Z", "Y")
        q = q @ Quaternion((0, 0, 1), math.radians(roll))
        shake = Euler((math.radians(1.6 * amp * noise(f, 1.0)), math.radians(1.6 * amp * noise(f, 7.0)),
                       math.radians(3.0 * amp * noise(f, 13.0))))
        q = q @ shake.to_quaternion()
        if prev[0] is not None and prev[0].dot(q) < 0:
            q.negate()
        prev[0] = q.copy()
        jitter = Vector((noise(f, 3.0), noise(f, 5.0), noise(f, 9.0))) * 0.035 * amp
        return {"location": pos + jitter, "rotation_quaternion": q, "lens": lens * (1 + 0.14 * e)}
    animate(cam, f0 - 1, f1 + 1, cam_anim)
    return cam

# A: cold open, low in the corridor; Slock drops, then charges straight through the lens
def shot_a(f):
    t = smooth(seg(f, 1, GO))
    pos = Vector((lerp(-14.6, -15.4, t), -15.25, lerp(0.75, 0.5, t)))
    tgt = Vector((-18, -15, 0.45))
    if f > GO:
        tgt = Vector((slock_x(f), -15, 0.45 + 0.1 * seg(f, GO, 40)))
    return pos, tgt, lerp(-6, 4, t), 26
make_shot("A_Drop", 1, 40, shot_a)

# B: the chase, flying through the words; the horizon snaps on every word
ROLLS = [(41, 0), (WORD_HITS[0], 14), (WORD_HITS[1], -14), (WORD_HITS[2], 20), (91, -8)]
def roll_at(f, keys):
    r = keys[0][1]
    for k in range(1, len(keys)):
        if f >= keys[k][0]:
            r = lerp(keys[k - 1][1], keys[k][1], out_expo(seg(f, keys[k][0], keys[k][0] + 7)))
    return r

def chase_pose(f):
    x = slock_x(f)
    return Vector((x - CAM_BACK, -15, CAM_Z)), Vector((x + 4.5, -15, 0.4))

def shot_b(f):
    pos, tgt = chase_pose(f)
    return pos, tgt, roll_at(f, ROLLS), 20
make_shot("B_Chase", 41, CRANE - 1, shot_b, rumble=0.35)

# C: whip up and out to the aerial, letters start raining in
def shot_c(f):
    p0, t0 = chase_pose(CRANE)
    t = out_expo(seg(f, CRANE, CRANE + 22))
    pos = p0.lerp(Vector((-4, -36, 30)), t) + Vector((0, 0, 1.5)) * seg(f, CRANE + 22, 146)
    tgt = t0.lerp(Vector((-2, -2, 0)), t)
    return pos, tgt, lerp(-8, 6, t), lerp(20, 30, t)
make_shot("C_Crane", CRANE, LETTER_LAND[0] - 6, shot_c)

# D: one hard cut per letter, each from a different angle
D_OFFSETS = [((-6, -9, -2.5), -9, 24), ((7, -8, 6), 11, 24), ((0, -6.5, 0.5), 0, 18),
             ((-5, -7, 8), -13, 24), ((5, -9, -2.3), 9, 22)]
for li, (off, roll, lens) in enumerate(D_OFFSETS):
    f0 = LETTER_LAND[li] - 5
    c = LETTER_CENTERS[li]
    def shot_d(f, c=c, off=Vector(off), roll=roll, lens=lens, f0=f0):
        t = seg(f, f0, f0 + 15)
        pos = c + off * lerp(1.0, 0.82, smooth(t))
        return pos, c + Vector((0, 0, -0.5)), roll * lerp(1, 0.6, t), lens
    make_shot(f"D_{'SLOCK'[li]}", f0, f0 + 14, shot_d)

# D wide: pull back off the K and reveal the whole word on the maze
def shot_d_wide(f):
    t = out_expo(seg(f, LETTER_LAND[-1] + 10, LETTER_LAND[-1] + 30))
    pos = Vector((9, -9, 3)).lerp(Vector((-2, -27, 8.5)), t) + Vector((0.04 * (f - 221), 0, 0))
    tgt = Vector((10, 0, 3.5)).lerp(Vector((0, 0, 3.0)), t)
    return pos, tgt, lerp(10, -2, t), lerp(20, 30, t)
make_shot("D_Wide", LETTER_LAND[-1] + 10, E_IN - 9, shot_d_wide)

# E: IN DEVELOPMENT. Orbit snaps on the beats while the level tilts below
E_ORBIT = [(E_IN - 8, -38), (E_IN, -22), (286, 14), (301, -8), (316, 24)]
E_ROLL = [(E_IN - 8, -10), (E_IN, 6), (286, -9), (301, 11), (316, -4)]
def shot_e(f):
    ang = math.radians(roll_at(f, E_ORBIT))
    dist = lerp(9.0, 14.0, out_expo(seg(f, E_IN, E_IN + 25))) - 1.5 * smooth(seg(f, 290, E_OUT))
    dist -= 8 * in_quad(seg(f, E_OUT, F_COMING - 1))
    pos = TYPE_AT + Vector((math.sin(ang) * dist, -math.cos(ang) * dist, -3.5))
    return pos, TYPE_AT + Vector((0, 0, 0.3)), roll_at(f, E_ROLL), 22
make_shot("E_InDev", E_IN - 8, F_COMING - 7, shot_e)

# F: COMING SOON. Dolly back off COMING, jolt on every SOON letter, then whip pan away
F_ROLL = [(F_COMING - 6, 0), (F_SOON[0], -7), (F_SOON[1], 8), (F_SOON[2], -10), (F_SOON[3], 4)]
def shot_f(f):
    t = out_expo(seg(f, F_COMING, F_COMING + 14))
    dist = lerp(5.0, 15.0, t) + 1.2 * seg(f, F_SOON[3], 406)
    yaw = 70 * in_quad(seg(f, 406, FINAL))
    pos = TYPE_AT + Vector((0, -dist, -3.5))
    look = Vector((0, 1, 0.2))
    look.rotate(Euler((0, 0, math.radians(-yaw))))
    return pos, pos + look * 10, roll_at(f, F_ROLL) - yaw * 0.3, 24
make_shot("F_ComingSoon", F_COMING - 6, FINAL - 1, shot_f)

# G: the final lockup over the lettering
def shot_g(f):
    t = seg(f, FINAL, END)
    pos = Vector((-3.0, -29, 8.0)).lerp(Vector((0.5, -25.5, 6.8)), smooth(t))
    return pos, Vector((0, 0, 2.6)), lerp(-3, 0, smooth(t)), 24
cam_g = make_shot("G_Final", FINAL, END, shot_g, rumble=0.06)

# the caption rides the final camera like a title card
cap = empty("Caption", cam_g)
cap.location = (0, 0, -5 * 24 / 28)   # sized as if 5 units out on a 28 mm lens; the camera is 24 mm
CAP_W = 2 * 5 * 18 / 28          # frame width at the caption plane
tape = hazard_strip("CapTape", CAP_W * 1.2, 0.16, cap)
bar_me = bpy.data.meshes.new("CapBar")
bar_me.from_pydata([(-CAP_W * 0.6, -0.24, 0), (CAP_W * 0.6, -0.24, 0), (CAP_W * 0.6, 0.24, 0), (-CAP_W * 0.6, 0.24, 0)], [], [(0, 1, 2, 3)])
bar_me.materials.append(M_BAR)
bar = link(bpy.data.objects.new("CapBar", bar_me), cap)
for obj, y, f0, side in ((tape, -0.82, CAPTION - 2, -1), (bar, -1.14, CAPTION, 1)):
    def fn(f, y=y, f0=f0, side=side):
        t = out_expo(seg(f, f0, f0 + 8))
        s = 1.0 if f >= f0 else 0.0
        return {"location": Vector((side * CAP_W * 1.3 * (1 - t), y, -0.01)), "scale": Vector((s, s, s))}
    animate(obj, f0 - 1, f0 + 9, fn)

def type_on(letters, y, f0, step, x=0.0):
    for k, (o, lx) in enumerate(letters):
        pop = f0 + k * step
        def fn(f, lx=lx + x, pop=pop):
            t = seg(f, pop, pop + 4)
            s = out_back(t, 3.0) if t > 0 else 0.0
            return {"location": Vector((lx, y + 0.12 * (1 - smooth(t)), 0)), "scale": Vector((s, s, s))}
        animate(o, pop - 1, pop + 5, fn)

# IN DEVELOPMENT and COMING SOON share the bar, centred as one line with a gap between
dev_line, w1 = word("IN DEVELOPMENT", 0.22, M_TXT_WHITE, cap, extrude=0.02)
soon_line, w2 = word("COMING SOON", 0.22, M_TXT_RED, cap, extrude=0.02)
span = w1 + 0.4 + w2
type_on(dev_line, -1.14, CAPTION + 5, 0.9, x=-span / 2 + w1 / 2)
type_on(soon_line, -1.14, CAPTION + 22, 1.2, x=span / 2 - w2 / 2)
credit, _ = word("A PIXELHACK STUDIOS PRODUCTION", 0.12, M_TXT_WHITE, cap, extrude=0.02)
type_on(credit, 1.38, 466, 0.5)

bake()

# ---------------------------------------------------------------------------------------------
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "impacts.json").write_text(json.dumps({"fps": FPS, "end": END, "impacts": IMPACTS}, indent=1))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "slock_teaser.blend"))
if "--no-render" not in args:
    bpy.ops.render.render(animation=True)
