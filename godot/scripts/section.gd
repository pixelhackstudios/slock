class_name Section
extends Node3D
## One section of the course, drawn by hand: '#' wall, '.' floor with a pellet, 'O' floor with a power pellet,
## '_' bare floor, 'S' swurm pen floor (where they start), ' ' nothing. The first line is the far end; the bottom
## lines are the climb ramp up from the previous section (flat on the first section, which also has a back
## wall), then the maze. Sections are laid end to end along -Z, each RISE higher than the last, and each with
## blocks a little smaller (see tile_of): the same maze, at a finer and finer grid.
##
## Grid (col, row) counts rows up from the bottom line. Floor top is floor_y in the maze; walls are one block
## tall. Collision is two static bodies: the floor (normal friction) and the walls (no friction, so sliding along
## a wall never brakes). Each is built from boxes merged into long runs, so a straight wall or floor is one flat
## face with no seams to snag on (the Unity version needed contact modification for that).

const BASE_BLOCK := 60            # "resolution": blocks are BLOCK/60 tiles across, 2 smaller each section...
const BLOCK_STEP := 2
const MIN_BLOCK := 20             # ... down to a third
const RISE := 1.0                 # each section's floor is this much higher than the last
const DEPTH := 1.0                # how far blocks reach below the lowest floor of a section

const LAYOUT: Array[String] = [
	"#########_#########",
	"#O......#.....#...#",
	"#.#####.#.###.#.#.#",
	"#.#...#...#...#.#.#",
	"#.#.#.#####.###.#.#",
	"#...#.......#.....#",
	"###.#.........#####",
	"#...#..##_###.....#",
	"#.###..#SSSS#.###.#",
	"#......#SSSS#.....#",
	"#.####.######.###.#",
	"#.................#",
	"#####.#.#.#.#.###.#",
	"#.....#...#...#...#",
	"#.#####.#######.#.#",
	"#.#.....#.....#.#.#",
	"#.#.###.#.###.#.#.#",
	"#...#O.....O#.....#",
	"#########.#########",
	"        #_#        ",
	"        #_#        ",
	"        #_#        ",
	"        #_#        ",
	"        #_#        ",
	"        #_#        ",
	"        ###        ",
]

enum { VOID, FLOOR, WALL }
enum Eaten { NOTHING, PELLET, POWER }
enum { SURF_FLOOR, SURF_WALL_SIDE, SURF_WALL_TOP }

var index := 0
var tile := 1.0                   # block size in this section
var floor_y := 0.0                # maze floor height
var near_edge := 0.0              # world z of the start of the ramp (row 1's near edge)
var width: int
var length: int
var centre: int
var tiles: Array = []             # tiles[col][row]
var maze_start := 0               # first row of the maze proper (below it: the ramp)
var swurm_homes: Array[Vector2i] = []
var swurms: Array[Swurm] = []
var pellets := {}                 # Vector2i(col, row) -> the pellet or power pellet floating over that tile
var _power := {}                  # the tiles in `pellets` that hold power pellets
var _prev_floor := 0.0            # where the ramp starts from: the previous section's floor
var _built: Array[Node] = []      # the mesh and collision bodies, rebuilt when the exit is sealed
var _exit_sealed := false


## Block size of section `i` (1 at the start).
static func tile_of(i: int) -> float:
	return block_of(i) / float(BASE_BLOCK)


## Block size of section `i` in "resolution units" (60 at the start), shown on the HUD.
static func block_of(i: int) -> int:
	return maxi(MIN_BLOCK, BASE_BLOCK - BLOCK_STEP * maxi(0, i))


## World z where section `i` starts (its ramp's near edge): straight after the previous section's exit.
static func near_edge_of(i: int) -> float:
	var z := -0.5
	for k in i:
		z -= (LAYOUT.size() - 1) * tile_of(k)
	return z


func _init(section_index: int) -> void:
	index = section_index
	tile = tile_of(index)
	floor_y = index * RISE
	_prev_floor = maxf(0.0, floor_y - RISE)
	near_edge = near_edge_of(index)
	_parse()


func _ready() -> void:
	_build()
	_spawn_pellets()
	close_gate()
	if index > 0:
		_add_chevrons()


func _process(_delta: float) -> void:
	_float_pellets()


## Where Slock starts a run: the first tile of the start corridor, resting on the floor.
func start_position(height: float) -> Vector3:
	return tile_centre(Vector2i(centre, 1)) + Vector3.UP * (height * 0.5 + 0.02)


## World z of this section's far end (the next section's near edge).
func far_edge() -> float:
	return near_edge - (length - 1) * tile


## The z of a tile-centre row, for lining Slock up with this section's grid.
func row_z(row: int) -> float:
	return near_edge - (row - 0.5) * tile


func tile_at(col: int, row: int) -> int:
	if col < 0 or col >= width or row < 0 or row >= length:
		return VOID
	return tiles[col][row]


func _parse() -> void:
	length = LAYOUT.size()
	width = LAYOUT[0].length()
	centre = width / 2
	tiles.resize(width)
	maze_start = length - 1
	while maze_start > 0 and not LAYOUT[length - maze_start].contains(" "):
		maze_start -= 1
	for col in width:
		tiles[col] = []
		tiles[col].resize(length)
		for row in length:
			var ch := LAYOUT[length - 1 - row][col]
			if ch == "S":
				swurm_homes.append(Vector2i(col, row))
			tiles[col][row] = WALL if ch == "#" else (FLOOR if ch in "._OS" else VOID)
			if row == 0 and index > 0:
				tiles[col][row] = VOID # the back wall is only on the first section; later ones join the last


## Floor centre of a tile, in world space.
func tile_centre(t: Vector2i) -> Vector3:
	var f := _row_floor(t.y)
	return Vector3((t.x - centre) * tile, (f.x + f.y) * 0.5, row_z(t.y))


## Floor height at a row's near (x) and far (y) edges: the ramp climbs evenly from the previous floor.
func _row_floor(row: int) -> Vector2:
	if row >= maze_start:
		return Vector2(floor_y, floor_y)
	if row <= 0:
		return Vector2(_prev_floor, _prev_floor)
	var n := float(maze_start - 1)
	return Vector2(lerpf(_prev_floor, floor_y, (row - 1) / n), lerpf(_prev_floor, floor_y, row / n))


## Tiles swurms may crawl on: maze floor, away from its outer edge and the entry and exit.
func is_crawlable(t: Vector2i) -> bool:
	return tile_at(t.x, t.y) == FLOOR and t.x > 0 and t.x < width - 1 and t.y > maze_start and t.y < length - 1


## The exit: the gap in the far wall, where the gate sits.
func exit_tile() -> Vector2i:
	return Vector2i(LAYOUT[0].find("_"), length - 1)


## Where a climb-ramp launch lands: the 4th tile into the maze.
func landing_tile() -> Vector2i:
	return Vector2i(centre, maze_start + 3)


## The tile under a world position.
func tile_under(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / tile) + centre, roundi((near_edge - world.z) / tile + 0.5))


## True on the climb ramp's corridor (or half a tile past either end of it).
func on_ramp(world: Vector3) -> bool:
	return absf(world.x) < tile * 0.45 and world.z <= near_edge + tile * 0.5 \
		and world.z >= near_edge - (maze_start - 0.5) * tile


## The ramp's top edge (world z).
func ramp_top_z() -> float:
	return near_edge - (maze_start - 1) * tile


# ------------------------------------------------------------------ building

func _build() -> void:
	for n in _built:
		n.queue_free()
	_built.clear()
	_build_mesh()
	_build_collision()


## Top of a tile at a row's near (x) and far (y) edges.
func _top(col: int, row: int) -> Vector2:
	var kind := tile_at(col, row)
	return _row_floor(row) + Vector2.ONE * (tile if kind == WALL else 0.0)


func _bottom() -> float:
	return minf(_prev_floor, floor_y) - DEPTH


func _build_mesh() -> void:
	var tools := []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)

	var h := tile * 0.5
	var bot := _bottom()
	var side: SurfaceTool = tools[SURF_WALL_SIDE]
	for col in width:
		for row in length:
			var kind: int = tiles[col][row]
			if kind == VOID:
				continue
			var c := tile_centre(Vector2i(col, row))
			var top := _top(col, row) # x: near edge (z1), y: far edge (z0)
			var x0 := c.x - h
			var x1 := c.x + h
			var z0 := c.z - h
			var z1 := c.z + h
			_quad(tools[SURF_WALL_TOP if kind == WALL else SURF_FLOOR],
				Vector3(x0, top.y, z0), Vector3(x1, top.y, z0), Vector3(x1, top.x, z1), Vector3(x0, top.x, z1),
				Vector3(0, (z1 - z0), top.y - top.x).normalized())
			# A side face shows unless the neighbour is solid and at least as tall along the shared edge.
			var e := _top(col + 1, row)
			if tile_at(col + 1, row) == VOID or e.x < top.x or e.y < top.y:
				_quad(side, Vector3(x1, bot, z0), Vector3(x1, top.y, z0), Vector3(x1, top.x, z1), Vector3(x1, bot, z1), Vector3.RIGHT)
			var w := _top(col - 1, row)
			if tile_at(col - 1, row) == VOID or w.x < top.x or w.y < top.y:
				_quad(side, Vector3(x0, bot, z0), Vector3(x0, top.y, z0), Vector3(x0, top.x, z1), Vector3(x0, bot, z1), Vector3.LEFT)
			if tile_at(col, row + 1) == VOID or _top(col, row + 1).x < top.y: # row + 1 is further along -Z
				_quad(side, Vector3(x0, bot, z0), Vector3(x0, top.y, z0), Vector3(x1, top.y, z0), Vector3(x1, bot, z0), Vector3.FORWARD)
			if tile_at(col, row - 1) == VOID or _top(col, row - 1).y < top.x:
				_quad(side, Vector3(x0, bot, z1), Vector3(x0, top.x, z1), Vector3(x1, top.x, z1), Vector3(x1, bot, z1), Vector3.BACK)

	var mesh := ArrayMesh.new()
	var materials := [_material("floor"), _material("walls"), _material("tops")]
	for i in 3:
		var st: SurfaceTool = tools[i]
		st.generate_tangents() # needed by the tile normal maps
		st.commit(mesh)
		mesh.surface_set_material(i, materials[i])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	_built.append(mi)


## One flat quad facing `normal`. UVs put one whole texture on each block face.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	# Godot draws clockwise triangles (seen from the front) as front faces.
	if (b - a).cross(c - a).dot(normal) > 0:
		var t := b
		b = d
		d = t
	for p in [a, b, c, a, c, d]:
		st.set_normal(normal)
		st.set_uv(_uv(p, normal))
		st.add_vertex(p)


func _uv(p: Vector3, normal: Vector3) -> Vector2:
	if absf(normal.y) > 0.5:
		return Vector2(p.x / tile + 0.5, p.z / tile + 0.5)
	if absf(normal.x) > 0.5:
		return Vector2(p.z / tile + 0.5, -p.y / tile)
	return Vector2(p.x / tile + 0.5, -p.y / tile)


func _material(set_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/%s_base.png" % set_name)
	m.normal_enabled = true
	m.normal_texture = load("res://textures/%s_normal.png" % set_name)
	m.ao_enabled = true
	m.ao_texture = load("res://textures/%s_ao.png" % set_name)
	m.roughness = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ------------------------------------------------------------------ collision

func _build_collision() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	add_child(floor_body)
	var wall_body := StaticBody3D.new()
	wall_body.name = "Walls"
	wall_body.physics_material_override = PhysicsMaterial.new()
	wall_body.physics_material_override.friction = 0.0
	add_child(wall_body)
	_built.append_array([floor_body, wall_body])

	# The ramp (sloped) and the maze (flat) are built separately, so every piece is one straight slab.
	for rows in [range(0, maze_start), range(maze_start, length)]:
		# Floor: every solid tile has floor under it (walls stand on it). Runs along each row, stacked with
		# identical runs in the next rows into rectangles (here: one for the ramp, one for the maze).
		var open := {} # Vector2i(first col, last col) -> first row it started on
		for row in rows + [-1]:
			var runs := []
			if row >= 0:
				for run in _runs_along_row(row, func(k): return k != VOID):
					runs.append(Vector2i(run[0], run[1]))
			for run in open.keys():
				if not runs.has(run):
					_slab(floor_body, run.x, run.y, open[run], (row if row >= 0 else rows[-1] + 1) - 1, true)
					open.erase(run)
			for run in runs:
				if not open.has(run):
					open[run] = row

		# Walls: long runs both ways, overlapping where they cross, so every straight wall face is a single
		# box face. A lone block that's in no run gets its own box.
		var covered := {}
		for row in rows:
			for run in _runs_along_row(row, func(k): return k == WALL):
				if run[1] > run[0]:
					_slab(wall_body, run[0], run[1], row, row, false)
					for col in range(run[0], run[1] + 1):
						covered[Vector2i(col, row)] = true
		for col in width:
			for run in _runs_along_col(col, rows, func(k): return k == WALL):
				if run[1] > run[0]:
					_slab(wall_body, col, col, run[0], run[1], false)
					for row in range(run[0], run[1] + 1):
						covered[Vector2i(col, row)] = true
		for col in width:
			for row in rows:
				if tiles[col][row] == WALL and not covered.has(Vector2i(col, row)):
					_slab(wall_body, col, col, row, row, false)


func _runs_along_row(row: int, solid: Callable) -> Array:
	var runs := []
	var start := -1
	for col in width + 1:
		var on: bool = col < width and solid.call(tiles[col][row])
		if on and start < 0:
			start = col
		elif not on and start >= 0:
			runs.append([start, col - 1])
			start = -1
	return runs


func _runs_along_col(col: int, rows: Array, solid: Callable) -> Array:
	var runs := []
	var start := -1
	for row in rows + [-1]:
		var on: bool = row >= 0 and solid.call(tiles[col][row])
		if on and start < 0:
			start = row
		elif not on and start >= 0:
			runs.append([start, row - 1])
			start = -1
	return runs


## A slab over tiles col0..col1, row0..row1 (inclusive): the floor under them (from the section's bottom up to
## the floor) or walls on them (from the floor up one block). Follows the ramp's slope.
func _slab(body: StaticBody3D, col0: int, col1: int, row0: int, row1: int, is_floor: bool) -> void:
	var x0 := (col0 - centre - 0.5) * tile
	var x1 := (col1 - centre + 0.5) * tile
	var z_near := near_edge - (row0 - 1) * tile
	var z_far := near_edge - row1 * tile
	var floor_near := _row_floor(row0).x
	var floor_far := _row_floor(row1).y
	var cs := CollisionShape3D.new()
	if is_equal_approx(floor_near, floor_far):
		var y0 := _bottom() if is_floor else floor_near
		var y1 := floor_near if is_floor else floor_near + tile
		cs.shape = BoxShape3D.new()
		cs.shape.size = Vector3(x1 - x0, y1 - y0, z_near - z_far)
		cs.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z_near + z_far) * 0.5)
	else:
		var points := PackedVector3Array()
		for x in [x0, x1]:
			for end in [[z_near, floor_near], [z_far, floor_far]]:
				var lo: float = _bottom() if is_floor else end[1]
				var hi: float = end[1] if is_floor else end[1] + tile
				points.append(Vector3(x, lo, end[0]))
				points.append(Vector3(x, hi, end[0]))
		cs.shape = ConvexPolygonShape3D.new()
		cs.shape.points = points
	body.add_child(cs)


## The booster's markings: orange chevrons up the climb ramp, pointing uphill.
func _add_chevrons() -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.6, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(2.0, 0.9, 0.1)
	glow.roughness = 0.5
	var bar := BoxMesh.new()
	bar.size = Vector3(0.45, 0.04, 0.12) * tile
	bar.material = glow
	var z_bottom := near_edge
	var z_top := ramp_top_z()
	var slope := atan2(floor_y - _prev_floor, z_bottom - z_top)
	var count := maxi(2, roundi((z_bottom - z_top) / (tile * 1.5)))
	for i in count:
		var f := (i + 0.5) / count
		var at := Vector3(0, lerpf(_prev_floor, floor_y, f) + 0.06 * tile, lerpf(z_bottom, z_top, f))
		for side in [-1, 1]:
			var piece := MeshInstance3D.new()
			piece.mesh = bar
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			piece.basis = Basis(Vector3.RIGHT, slope) * Basis(Vector3.UP, deg_to_rad(-35.0 * side))
			piece.position = at + Vector3(side * tile * 0.17, 0, 0)
			add_child(piece)


## Wall up the exit behind Slock, once it's through: no going back.
func seal_exit() -> void:
	if _exit_sealed:
		return
	_exit_sealed = true
	var e := exit_tile()
	tiles[e.x][e.y] = WALL
	open_gate()
	_build()


# ------------------------------------------------------------------ pellets

const PELLET_RADIUS := 0.115      # blocks (0.23 across)
const PELLET_HEIGHT := 0.3        # centre above the floor, blocks
const PELLET_BOB := 0.06          # bob height, blocks
const POWER_RADIUS := 0.23        # power pellets: big glowing orbs (0.46 blocks across)
const POWER_HEIGHT := 0.6
const POWER_BOB := 0.12
const OUTLINE_PX := 0.5           # black outline width, in screen pixels

var _floats := {} # Vector2i(col, row) -> [home, phase, spin (deg/s), bob speed (rad/s), bob height]


func _spawn_pellets() -> void:
	var pellet_look := _orb(PELLET_RADIUS * tile, Color(0.25, 0.55, 1.0, 0.72), Color(0.1, 0.35, 1.2))
	var power_look := _orb(POWER_RADIUS * tile, Color(1.0, 0.85, 0.15, 0.72), Color(1.2, 0.85, 0.1))
	for row in length:
		for col in width:
			var ch := LAYOUT[length - 1 - row][col]
			var key := Vector2i(col, row)
			if ch == ".":
				_floats[key] = [tile_centre(key) + Vector3.UP * PELLET_HEIGHT * tile, randf() * 100.0,
					randf_range(40.0, 140.0) * (1 if randf() < 0.5 else -1), randf_range(1.2, 2.4), PELLET_BOB * tile]
				pellets[key] = _add_orb(pellet_look)
			elif ch == "O":
				_floats[key] = [tile_centre(key) + Vector3.UP * POWER_HEIGHT * tile, randf() * 10.0, 120.0, 3.0,
					POWER_BOB * tile]
				pellets[key] = _add_orb(power_look)
				_power[key] = true


## A see-through jelly sphere and its outline: a flat ring facing the camera around the sphere's edge
## (see outline.gdshader). Returns [sphere mesh, ring mesh], shared by every orb of that look.
func _orb(radius: float, color: Color, glow: Color) -> Array:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var jelly := StandardMaterial3D.new()
	jelly.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jelly.albedo_color = color
	jelly.roughness = 0.05
	jelly.emission_enabled = true
	jelly.emission = glow
	sphere.material = jelly

	var ring := QuadMesh.new()
	var half := radius * 1.6 # room for the ring outside the sphere
	ring.size = Vector2.ONE * half * 2.0
	var outline := ShaderMaterial.new()
	outline.shader = load("res://scripts/outline.gdshader")
	outline.set_shader_parameter("radius", radius)
	outline.set_shader_parameter("half_size", half)
	outline.set_shader_parameter("width_px", OUTLINE_PX)
	ring.material = outline
	return [sphere, ring]


func _add_orb(look: Array) -> MeshInstance3D:
	var orb := MeshInstance3D.new()
	orb.mesh = look[0]
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var edge := MeshInstance3D.new()
	edge.mesh = look[1]
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(edge)
	add_child(orb)
	return orb


## Pellets spin at their own speed and direction, and bob up and down out of step.
func _float_pellets() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for key in pellets:
		var pellet: Node3D = pellets[key]
		var f: Array = _floats[key]
		var ph: float = f[1] + time
		pellet.position = f[0] + Vector3.UP * sin(ph * f[3]) * f[4]
		pellet.rotation_degrees = Vector3(sin(ph * 0.7) * 8.0, ph * f[2], cos(ph * 0.9) * 8.0)


## Eat the pellet or power pellet on the tile under `world`, if there is one level with it.
func try_eat_pellet(world: Vector3) -> Eaten:
	var key := tile_under(world)
	var pellet: Node3D = pellets.get(key)
	if pellet == null or absf(pellet.global_position.y - world.y) > tile * 1.5:
		return Eaten.NOTHING
	pellets.erase(key)
	pellet.queue_free()
	return Eaten.POWER if _power.erase(key) else Eaten.PELLET


# ------------------------------------------------------------------ gate

const GATE_COLOR := Color(0.1, 0.8, 0.8, 0.6) # see-through glowing teal glass

var _gate: StaticBody3D


## A solid glowing block in the exit, until every pellet is eaten.
func close_gate() -> void:
	if _gate != null:
		return
	_gate = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(tile, tile * 1.2, tile)
	_gate.add_child(shape)
	var block := MeshInstance3D.new()
	block.mesh = BoxMesh.new()
	block.mesh.size = shape.shape.size
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = GATE_COLOR
	glass.emission_enabled = true
	glass.emission = Color(0.05, 0.7, 0.7)
	glass.roughness = 0.1
	block.mesh.material = glass
	_gate.add_child(block)
	_gate.position = tile_centre(exit_tile()) + Vector3.UP * tile * 0.6
	add_child(_gate)


func open_gate() -> void:
	if _gate != null:
		_gate.queue_free()
		_gate = null


func gate_open() -> bool:
	return _gate == null
