class_name Section
extends Node3D
## One map section, drawn by hand: '#' wall, '.' floor with a pellet, 'O' floor with a power pellet, '_' bare
## floor, 'S' swurm pen floor (where they start), ' ' nothing. The first line is the far end;
## the bottom lines are the start corridor (the Unity version's flat entry ramp) and its back wall.
## Grid (col, row) sits at world x = (col - centre) * TILE, z = -row * TILE, counting rows up from the
## bottom line, so the course runs away from the camera along -Z. Floor top is y = 0; walls are one block tall.
##
## Collision is two static bodies: the floor (normal friction) and the walls (no friction, so sliding along a
## wall never brakes). Each is built from boxes merged into long runs, so a straight wall or floor is one flat
## face with no seams to snag on (the Unity version needed contact modification for that).

const TILE := 1.0
const DEPTH := 1.0 # how far blocks reach below the floor

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

var width: int
var length: int
var centre: int
var tiles: Array = [] # tiles[col][row]
var maze_start := 0  # first row of the maze proper (below it: the start corridor)
var swurm_homes: Array[Vector2i] = []
var pellets := {}     # Vector2i(col, row) -> the pellet or power pellet floating over that tile
var _power := {}      # the tiles in `pellets` that hold power pellets


func _ready() -> void:
	_parse()
	_build_mesh()
	_build_collision()
	_spawn_pellets()
	close_gate()


func _process(_delta: float) -> void:
	_float_pellets()


## Where Slock starts: the first tile of the start corridor, resting on the floor.
func start_position(height: float) -> Vector3:
	return Vector3(0, height * 0.5 + 0.02, -TILE)


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


## Floor centre of a tile, in world space.
func tile_centre(tile: Vector2i) -> Vector3:
	return _centre_of(tile.x, tile.y)


## Tiles swurms may crawl on: maze floor, away from its outer edge and the entry and exit.
func is_crawlable(tile: Vector2i) -> bool:
	return tile_at(tile.x, tile.y) == FLOOR and tile.x > 0 and tile.x < width - 1 \
		and tile.y > maze_start and tile.y < length - 1


## The exit: the gap in the far wall, where the gate sits.
func exit_tile() -> Vector2i:
	return Vector2i(LAYOUT[0].find("_"), length - 1)


## The tile under a world position.
func tile_under(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / TILE) + centre, roundi(-world.z / TILE))


func _centre_of(col: int, row: int) -> Vector3:
	return Vector3((col - centre) * TILE, 0, -row * TILE)


func _top_of(kind: int) -> float:
	return TILE if kind == WALL else 0.0


# ------------------------------------------------------------------ mesh

func _build_mesh() -> void:
	var tools := []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)

	var h := TILE * 0.5
	for col in width:
		for row in length:
			var kind: int = tiles[col][row]
			if kind == VOID:
				continue
			var c := _centre_of(col, row)
			var top := _top_of(kind)
			var x0 := c.x - h
			var x1 := c.x + h
			var z0 := c.z - h
			var z1 := c.z + h
			var bot := -DEPTH
			var side: SurfaceTool = tools[SURF_WALL_SIDE]
			_quad(tools[SURF_WALL_TOP if kind == WALL else SURF_FLOOR],
				Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x0, top, z1), Vector3.UP)
			if not _hides(col + 1, row, top):
				_quad(side, Vector3(x1, bot, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x1, bot, z1), Vector3.RIGHT)
			if not _hides(col - 1, row, top):
				_quad(side, Vector3(x0, bot, z0), Vector3(x0, top, z0), Vector3(x0, top, z1), Vector3(x0, bot, z1), Vector3.LEFT)
			if not _hides(col, row + 1, top): # row + 1 is further along -Z
				_quad(side, Vector3(x0, bot, z0), Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, bot, z0), Vector3.FORWARD)
			if not _hides(col, row - 1, top):
				_quad(side, Vector3(x0, bot, z1), Vector3(x0, top, z1), Vector3(x1, top, z1), Vector3(x1, bot, z1), Vector3.BACK)

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


## A neighbour hides the face between us when it's solid and at least as tall.
func _hides(col: int, row: int, top: float) -> bool:
	var kind := tile_at(col, row)
	return kind != VOID and _top_of(kind) >= top


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
		return Vector2(p.x / TILE + 0.5, p.z / TILE + 0.5)
	if absf(normal.x) > 0.5:
		return Vector2(p.z / TILE + 0.5, -p.y / TILE)
	return Vector2(p.x / TILE + 0.5, -p.y / TILE)


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

	# Floor: every solid tile has floor under it (walls stand on it). Runs along each row, then stacked
	# with identical runs in the next rows into rectangles (here: one for the corridor, one for the maze).
	var open := {} # Vector2i(first col, last col) -> first row it started on
	for row in length + 1:
		var runs := []
		if row < length:
			for run in _runs_along_row(row, func(k): return k != VOID):
				runs.append(Vector2i(run[0], run[1]))
		for run in open.keys():
			if not runs.has(run):
				_box(floor_body, run.x, run.y, open[run], row - 1, -DEPTH, 0.0)
				open.erase(run)
		for run in runs:
			if not open.has(run):
				open[run] = row

	# Walls: long runs both ways, overlapping where they cross, so every straight wall face is a single box face.
	# A lone block that's in no run gets its own box.
	var covered := {}
	for row in length:
		for run in _runs_along_row(row, func(k): return k == WALL):
			if run[1] > run[0]:
				_box(wall_body, run[0], run[1], row, row, 0.0, TILE)
				for col in range(run[0], run[1] + 1):
					covered[Vector2i(col, row)] = true
	for col in width:
		for run in _runs_along_col(col, func(k): return k == WALL):
			if run[1] > run[0]:
				_box(wall_body, col, col, run[0], run[1], 0.0, TILE)
				for row in range(run[0], run[1] + 1):
					covered[Vector2i(col, row)] = true
	for col in width:
		for row in length:
			if tiles[col][row] == WALL and not covered.has(Vector2i(col, row)):
				_box(wall_body, col, col, row, row, 0.0, TILE)


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


func _runs_along_col(col: int, solid: Callable) -> Array:
	var runs := []
	var start := -1
	for row in length + 1:
		var on: bool = row < length and solid.call(tiles[col][row])
		if on and start < 0:
			start = row
		elif not on and start >= 0:
			runs.append([start, row - 1])
			start = -1
	return runs


## A box covering tiles col0..col1, row0..row1 (inclusive), from y0 to y1.
func _box(body: StaticBody3D, col0: int, col1: int, row0: int, row1: int, y0: float, y1: float) -> void:
	var a := _centre_of(col0, row0)
	var b := _centre_of(col1, row1)
	var shape := BoxShape3D.new()
	shape.size = Vector3(absf(b.x - a.x) + TILE, y1 - y0, absf(b.z - a.z) + TILE)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3((a.x + b.x) * 0.5, (y0 + y1) * 0.5, (a.z + b.z) * 0.5)
	body.add_child(cs)


# ------------------------------------------------------------------ pellets

const PELLET_RADIUS := 0.115      # world units (0.23 blocks across)
const PELLET_HEIGHT := 0.3        # centre above the floor
const PELLET_BOB := 0.06          # bob height
const POWER_RADIUS := 0.23        # power pellets: big glowing orbs (0.46 blocks across)
const POWER_HEIGHT := 0.6
const POWER_BOB := 0.12
const OUTLINE_PX := 0.5           # black outline width, in screen pixels

var _floats := {} # Vector2i(col, row) -> [home, phase, spin (deg/s), bob speed (rad/s), bob height]


func _spawn_pellets() -> void:
	var pellet_look := _orb(PELLET_RADIUS, Color(0.25, 0.55, 1.0, 0.72), Color(0.1, 0.35, 1.2))
	var power_look := _orb(POWER_RADIUS, Color(1.0, 0.85, 0.15, 0.72), Color(1.2, 0.85, 0.1))
	for row in length:
		for col in width:
			var ch := LAYOUT[length - 1 - row][col]
			var key := Vector2i(col, row)
			if ch == ".":
				_floats[key] = [_centre_of(col, row) + Vector3.UP * PELLET_HEIGHT, randf() * 100.0,
					randf_range(40.0, 140.0) * (1 if randf() < 0.5 else -1), randf_range(1.2, 2.4), PELLET_BOB]
				pellets[key] = _add_orb(pellet_look)
			elif ch == "O":
				_floats[key] = [_centre_of(col, row) + Vector3.UP * POWER_HEIGHT, randf() * 10.0, 120.0, 3.0, POWER_BOB]
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


## Put every pellet back and close the gate (a restart).
func reset() -> void:
	for pellet in pellets.values():
		pellet.queue_free()
	pellets.clear()
	_power.clear()
	_floats.clear()
	_spawn_pellets()
	close_gate()


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
	if pellet == null or absf(pellet.global_position.y - world.y) > TILE * 1.5:
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
	shape.shape.size = Vector3(TILE, TILE * 1.2, TILE)
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
	_gate.position = tile_centre(exit_tile()) + Vector3.UP * TILE * 0.6
	add_child(_gate)


func open_gate() -> void:
	if _gate != null:
		_gate.queue_free()
		_gate = null


func gate_open() -> bool:
	return _gate == null
