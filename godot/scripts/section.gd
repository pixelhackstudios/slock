class_name Section
extends Node3D
## One section of the course, drawn by hand. The first line is the far end. Sections are laid end to end along -Z,
## each RISE higher than the last, and each with blocks a little smaller (see tile_of): the same layout, at a finer
## and finer grid.
##
## The maze (main level):           '#' wall  '.' floor with a pellet  'O' power pellet  '_' bare floor
##                                  'S' swurm pen floor (where they start)
## The side room (SIDE_DROP lower): '=' wall  ',' floor with a gold pellet  'o' power pellet  '-' bare floor
##                                  'C' clock  'K' key
## The side ramp between them:      '>' ramp floor  '^' ramp wall (it slopes from the room up to the maze)
## Anything else (a space) is nothing: a pit inside, or an open edge to slide off.
## The bottom lines are the climb ramp up from the previous section (flat on the first section, which also has a
## back wall); the maze proper starts where its outer walls do.
##
## Grid (col, row) counts rows up from the bottom line; the maze's exit column is x = 0. Walls are one block tall.
## Collision is two static bodies: the floor (normal friction) and the walls (no friction, so sliding along a wall
## never brakes). Each is built from slabs merged into long runs, so a straight wall or floor is one flat face with
## no seams to snag on (the Unity version needed contact modification for that).

const BASE_BLOCK := 60            # "resolution": blocks are BLOCK/60 tiles across, 2 smaller each section...
const BLOCK_STEP := 2
const MIN_BLOCK := 20             # ... down to a third
const RISE := 1.0                 # each section's floor is this much higher than the last
const SIDE_DROP := 3.0            # how far below the maze a side room sits
const DEPTH := 1.0                # how far blocks reach below the lowest floor of a section

const LAYOUT: Array[String] = [
	"             #########_#########",
	"             #O......#.....#...#",
	"             #.#####.#.###.#.#.#",
	"             #.#...#...#...#.#.#",
	"             #.#.#.#####.###.#.#",
	"=========    #...#.......#.....#",
	"=,,,,,,,=    ###.#.........#####",
	"=,=,= =,=    #...#..##_###.....#",
	"=,,,o,,,=^^^^#.###..#SSSS#.###.#",
	",,=,=,=,->>>>.......#SSSS#.....#",
	"=,,,,,=,=^^^^#.####.######.###.#",
	" ,=,=C,,=    #.................#",
	"=,,,,,,,=    #####.#.#.#.#.###.#",
	"=========    #.....#...#...#...#",
	"             #.#####.#######.#.#",
	"             #.#.....#.....#.#.#",
	"             #.#.###.#.###.#.#.#",
	"             #...#O.....O#.....#",
	"             #########.#########",
	"                     #_#        ",
	"                     #_#        ",
	"                     #_#        ",
	"                     #_#        ",
	"                     #_#        ",
	"                     #_#        ",
	"                     ###        ",
]

enum { VOID, FLOOR, WALL }
enum Level { MAIN, LOW, CLIMB, SIDE } # the maze, the side room, the climb ramp, the side ramp
enum Eaten { NOTHING, PELLET, GOLD, POWER, CLOCK, KEY }
enum { SURF_FLOOR, SURF_WALL_SIDE, SURF_WALL_TOP }

var index := 0
var tile := 1.0                   # block size in this section
var floor_y := 0.0                # maze floor height
var near_edge := 0.0              # world z of the start of the climb ramp (row 1's near edge)
var width: int
var length: int
var centre: int                   # the exit's column: x = 0
var maze_left: int                # the maze's outer wall columns
var maze_right: int
var maze_start := 0               # first row of the maze proper (below it: the climb ramp)
var tiles: Array = []             # tiles[col][row]: VOID, FLOOR or WALL
var levels: Array = []            # levels[col][row]: Level
var swurm_homes: Array[Vector2i] = []
var swurms: Array[Swurm] = []
var pellets := {}                 # Vector2i(col, row) -> the pellet, power pellet, clock or key floating there
var _kinds := {}                  # ... and what it is (Eaten)
var _prev_floor := 0.0            # where the climb ramp starts from: the previous section's floor
var _side := Vector3i(-1, -1, -1) # the side ramp: first col, last col, row (-1: none)
var _built: Array[Node] = []      # the mesh and collision bodies, rebuilt when the exit is sealed
var _exit_sealed := false


## Block size of section `i` (1 at the start).
static func tile_of(i: int) -> float:
	return block_of(i) / float(BASE_BLOCK)


## Block size of section `i` in "resolution units" (60 at the start), shown on the HUD.
static func block_of(i: int) -> int:
	return maxi(MIN_BLOCK, BASE_BLOCK - BLOCK_STEP * maxi(0, i))


## World z where section `i` starts (its climb ramp's near edge): straight after the previous section's exit.
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
	reset()
	if index > 0:
		_add_chevrons(Vector3(0, _prev_floor, near_edge), Vector3(0, floor_y, ramp_top_z()))
	if has_side_ramp():
		var a := tile_centre(Vector2i(_side.x, _side.z))
		var b := tile_centre(Vector2i(_side.y, _side.z))
		var left := Vector3(a.x - tile * 0.5, _side_floor(_side.x, false), a.z)
		var right := Vector3(b.x + tile * 0.5, _side_floor(_side.y, true), b.z)
		if right.y > left.y:
			_add_chevrons(left, right)
		else:
			_add_chevrons(right, left)


func _process(_delta: float) -> void:
	_float_pellets()


## Put every pellet and pickup back and close the gate (a new run).
func reset() -> void:
	for pellet in pellets.values():
		pellet.queue_free()
	pellets.clear()
	_kinds.clear()
	_floats.clear()
	_spawn_pellets()
	close_gate()


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


func _char(col: int, row: int) -> String:
	var line := LAYOUT[length - 1 - row]
	return line[col] if col < line.length() else " "


func _parse() -> void:
	length = LAYOUT.size()
	width = 0
	for line in LAYOUT:
		width = maxi(width, line.length())
	centre = LAYOUT[0].find("_")
	maze_left = LAYOUT[0].find("#")
	maze_right = LAYOUT[0].rfind("#")
	# The maze proper starts where its outer walls do; below that is the climb ramp.
	maze_start = length - 1
	while maze_start > 0 and _char(maze_left, maze_start - 1) != " ":
		maze_start -= 1
	tiles.resize(width)
	levels.resize(width)
	for col in width:
		tiles[col] = []
		tiles[col].resize(length)
		levels[col] = []
		levels[col].resize(length)
		for row in length:
			var ch := _char(col, row)
			var kind := VOID
			var level := Level.MAIN
			if ch == "#":
				kind = WALL
			elif ch in "._OS":
				kind = FLOOR
			elif ch == "=":
				kind = WALL
				level = Level.LOW
			elif ch in ",-oCK":
				kind = FLOOR
				level = Level.LOW
			elif ch == "^":
				kind = WALL
				level = Level.SIDE
			elif ch == ">":
				kind = FLOOR
				level = Level.SIDE
				_side = Vector3i(col if _side.x < 0 else _side.x, col, row)
			if level == Level.MAIN and row < maze_start:
				level = Level.CLIMB
			if row == 0 and index > 0:
				kind = VOID # the back wall is only on the first section; later ones join the last
			if ch == "S":
				swurm_homes.append(Vector2i(col, row))
			tiles[col][row] = kind
			levels[col][row] = level


## Floor centre of a tile, in world space.
func tile_centre(t: Vector2i) -> Vector3:
	var f := _floor_corners(t.x, t.y)
	return Vector3((t.x - centre) * tile, (f[0] + f[1] + f[2] + f[3]) * 0.25, row_z(t.y))


## Floor height at a tile's corners: near-left, near-right, far-right, far-left (near = towards the camera).
func _floor_corners(col: int, row: int) -> PackedFloat32Array:
	var lvl: int = levels[clampi(col, 0, width - 1)][clampi(row, 0, length - 1)]
	match lvl:
		Level.LOW:
			var y := floor_y - SIDE_DROP
			return PackedFloat32Array([y, y, y, y])
		Level.CLIMB:
			var f := _climb_floor(row)
			return PackedFloat32Array([f.x, f.x, f.y, f.y])
		Level.SIDE:
			var l := _side_floor(col, false)
			var r := _side_floor(col, true)
			return PackedFloat32Array([l, r, r, l])
	return PackedFloat32Array([floor_y, floor_y, floor_y, floor_y])


## The climb ramp's floor at a row's near (x) and far (y) edges: it climbs evenly from the previous floor.
func _climb_floor(row: int) -> Vector2:
	if row <= 0:
		return Vector2(_prev_floor, _prev_floor)
	var n := float(maze_start - 1)
	return Vector2(lerpf(_prev_floor, floor_y, (row - 1) / n), lerpf(_prev_floor, floor_y, row / n))


## The side ramp's floor at a column's left or right edge: it climbs evenly from the side room to the maze.
func _side_floor(col: int, right_edge: bool) -> float:
	var low := floor_y - SIDE_DROP
	var n := float(_side.y - _side.x + 1)
	var f := (col - _side.x + (1 if right_edge else 0)) / n # 0 at the ramp's left end, 1 at its right
	if _side_rises_right():
		return lerpf(low, floor_y, f)
	return lerpf(floor_y, low, f)


func _side_rises_right() -> bool:
	return levels[maxi(0, _side.x - 1)][_side.z] == Level.LOW


## Tiles swurms may crawl on: maze floor, away from its outer edge and the entry and exit.
func is_crawlable(t: Vector2i) -> bool:
	return tile_at(t.x, t.y) == FLOOR and levels[t.x][t.y] == Level.MAIN and t.x > maze_left and t.x < maze_right \
		and t.y > maze_start and t.y < length - 1


## The exit: the gap in the far wall, where the gate sits.
func exit_tile() -> Vector2i:
	return Vector2i(centre, length - 1)


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


## The climb ramp's top edge (world z).
func ramp_top_z() -> float:
	return near_edge - (maze_start - 1) * tile


func has_side_ramp() -> bool:
	return _side.z >= 0


## True on the side ramp (or half a tile past either end of it).
func on_side_ramp(world: Vector3) -> bool:
	if not has_side_ramp() or absf(world.z - row_z(_side.z)) > tile * 0.45:
		return false
	var a := tile_centre(Vector2i(_side.x, _side.z)).x
	var b := tile_centre(Vector2i(_side.y, _side.z)).x
	return world.x >= minf(a, b) - tile and world.x <= maxf(a, b) + tile


## The side ramp's uphill direction (towards the maze).
func side_uphill() -> Vector3:
	return Vector3.RIGHT if _side_rises_right() else Vector3.LEFT


## The side ramp's top edge (world x).
func side_top_x() -> float:
	var top_col := _side.y if _side_rises_right() else _side.x
	return tile_centre(Vector2i(top_col, _side.z)).x + side_uphill().x * tile * 0.5


## Where a side-ramp launch lands: the 4th tile into the maze from its doorway.
func side_landing() -> Vector3:
	var doorway := _side.y + 1 if _side_rises_right() else _side.x - 1
	return tile_centre(Vector2i(doorway + 3 * int(side_uphill().x), _side.z))


## Where sliding down the side ramp is braked to a stop: the room's second tile in.
func side_stop() -> Vector3:
	var room_door := _side.x - 1 if _side_rises_right() else _side.y + 1
	return tile_centre(Vector2i(room_door - int(side_uphill().x), _side.z))


# ------------------------------------------------------------------ building

func _build() -> void:
	for n in _built:
		n.queue_free()
	_built.clear()
	_build_mesh()
	_build_collision()


## A tile's top at its corners (see _floor_corners): its floor, or a block higher for walls.
func _top(col: int, row: int) -> PackedFloat32Array:
	var f := _floor_corners(col, row)
	if tile_at(col, row) == WALL:
		for i in 4:
			f[i] += tile
	return f


func _bottom() -> float:
	var lowest := minf(_prev_floor, floor_y)
	for col in width:
		for row in length:
			if tiles[col][row] != VOID and levels[col][row] == Level.LOW:
				lowest = minf(lowest, floor_y - SIDE_DROP)
	return lowest - DEPTH


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
			var t := _top(col, row) # near-left, near-right, far-right, far-left
			var x0 := c.x - h
			var x1 := c.x + h
			var z0 := c.z - h # far
			var z1 := c.z + h # near
			var nl := Vector3(x0, t[0], z1)
			var nr := Vector3(x1, t[1], z1)
			var fr := Vector3(x1, t[2], z0)
			var fl := Vector3(x0, t[3], z0)
			var up := (nr - fl).cross(nl - fr).normalized()
			_quad(tools[SURF_WALL_TOP if kind == WALL else SURF_FLOOR], fl, fr, nr, nl, up if up.y > 0 else -up)
			# A side face shows unless the neighbour is solid and at least as tall along the shared edge.
			if _shows(col + 1, row, 3, 0, t[2], t[1]):
				_quad(side, Vector3(x1, bot, z0), fr, nr, Vector3(x1, bot, z1), Vector3.RIGHT)
			if _shows(col - 1, row, 2, 1, t[3], t[0]):
				_quad(side, Vector3(x0, bot, z0), fl, nl, Vector3(x0, bot, z1), Vector3.LEFT)
			if _shows(col, row + 1, 0, 1, t[3], t[2]): # row + 1 is further along -Z
				_quad(side, Vector3(x0, bot, z0), fl, fr, Vector3(x1, bot, z0), Vector3.FORWARD)
			if _shows(col, row - 1, 3, 2, t[0], t[1]):
				_quad(side, Vector3(x0, bot, z1), nl, nr, Vector3(x1, bot, z1), Vector3.BACK)

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


## Whether the side face towards neighbour (col, row) shows: unless the neighbour is solid and its top, at the
## two corners on the shared edge (`ca`, `cb`), is at least as high as ours there (`ya`, `yb`).
func _shows(col: int, row: int, ca: int, cb: int, ya: float, yb: float) -> bool:
	if tile_at(col, row) == VOID:
		return true
	var n := _top(col, row)
	return n[ca] < ya - 1e-4 or n[cb] < yb - 1e-4


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

	# Each level (maze, side room, climb ramp, side ramp) is built separately, so every slab is one flat or
	# evenly sloped piece.
	for lvl in Level.values():
		var solid := func(c: int, r: int) -> bool: return tiles[c][r] != VOID and levels[c][r] == lvl
		var wall := func(c: int, r: int) -> bool: return tiles[c][r] == WALL and levels[c][r] == lvl

		# Floor: every solid tile has floor under it (walls stand on it). Runs along each row, stacked with
		# identical runs in the next rows into rectangles.
		var open := {} # Vector2i(first col, last col) -> first row it started on
		for row in length + 1:
			var runs := []
			if row < length:
				for run in _runs_along_row(row, solid):
					runs.append(Vector2i(run[0], run[1]))
			for run in open.keys():
				if not runs.has(run):
					_slab(floor_body, run.x, run.y, open[run], row - 1, true)
					open.erase(run)
			for run in runs:
				if not open.has(run):
					open[run] = row

		# Walls: long runs both ways, overlapping where they cross, so every straight wall face is a single
		# slab face. A lone block that's in no run gets its own.
		var covered := {}
		for row in length:
			for run in _runs_along_row(row, wall):
				if run[1] > run[0]:
					_slab(wall_body, run[0], run[1], row, row, false)
					for col in range(run[0], run[1] + 1):
						covered[Vector2i(col, row)] = true
		for col in width:
			for run in _runs_along_col(col, wall):
				if run[1] > run[0]:
					_slab(wall_body, col, col, run[0], run[1], false)
					for row in range(run[0], run[1] + 1):
						covered[Vector2i(col, row)] = true
		for col in width:
			for row in length:
				if wall.call(col, row) and not covered.has(Vector2i(col, row)):
					_slab(wall_body, col, col, row, row, false)


func _runs_along_row(row: int, solid: Callable) -> Array:
	var runs := []
	var start := -1
	for col in width + 1:
		var on: bool = col < width and solid.call(col, row)
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
		var on: bool = row < length and solid.call(col, row)
		if on and start < 0:
			start = row
		elif not on and start >= 0:
			runs.append([start, row - 1])
			start = -1
	return runs


## A slab over tiles col0..col1, row0..row1 (inclusive, all on one level): the floor under them (from the
## section's bottom up to the floor) or walls on them (from the floor up one block). Follows any slope.
func _slab(body: StaticBody3D, col0: int, col1: int, row0: int, row1: int, is_floor: bool) -> void:
	var x0 := (col0 - centre - 0.5) * tile
	var x1 := (col1 - centre + 0.5) * tile
	var z_near := near_edge - (row0 - 1) * tile
	var z_far := near_edge - row1 * tile
	var corners := [ # [x, z, floor height] at near-left, near-right, far-right, far-left
		[x0, z_near, _floor_corners(col0, row0)[0]], [x1, z_near, _floor_corners(col1, row0)[1]],
		[x1, z_far, _floor_corners(col1, row1)[2]], [x0, z_far, _floor_corners(col0, row1)[3]]]
	var cs := CollisionShape3D.new()
	var flat := true
	for c in corners:
		flat = flat and is_equal_approx(c[2], corners[0][2])
	if flat:
		var f: float = corners[0][2]
		var y0 := _bottom() if is_floor else f
		var y1 := f if is_floor else f + tile
		cs.shape = BoxShape3D.new()
		cs.shape.size = Vector3(x1 - x0, y1 - y0, z_near - z_far)
		cs.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z_near + z_far) * 0.5)
	else:
		var points := PackedVector3Array()
		for c in corners:
			points.append(Vector3(c[0], _bottom() if is_floor else c[2], c[1]))
			points.append(Vector3(c[0], c[2] if is_floor else c[2] + tile, c[1]))
		cs.shape = ConvexPolygonShape3D.new()
		cs.shape.points = points
	body.add_child(cs)


## A booster's markings: orange chevrons pointing uphill from `bottom` to `top` (points on the ramp's centre line).
func _add_chevrons(bottom: Vector3, top: Vector3) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.6, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(2.0, 0.9, 0.1)
	glow.roughness = 0.5
	var bar := BoxMesh.new()
	bar.size = Vector3(0.45, 0.04, 0.12) * tile # long across the ramp; the chevron's arms
	bar.material = glow
	var run := Vector3(top.x - bottom.x, 0, top.z - bottom.z)
	var uphill := run.normalized()
	var across := Vector3(-uphill.z, 0, uphill.x)
	var heading := atan2(-uphill.x, -uphill.z) # turns the bar's frame so its "uphill" is -Z, like the climb ramp
	var slope := atan2(top.y - bottom.y, run.length())
	var count := maxi(2, roundi(run.length() / (tile * 1.5)))
	for i in count:
		var f := (i + 0.5) / count
		var at := bottom.lerp(top, f) + Vector3.UP * 0.06 * tile
		for side in [-1, 1]:
			var piece := MeshInstance3D.new()
			piece.mesh = bar
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			piece.basis = Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, slope) * Basis(Vector3.UP, deg_to_rad(-35.0 * side))
			piece.position = at + across * side * tile * 0.17
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


# ------------------------------------------------------------------ pellets and pickups

const PELLET_RADIUS := 0.115      # blocks (0.23 across)
const GOLD_RADIUS := 0.14         # side-room pellets are a bit bigger (0.28 across)
const PELLET_HEIGHT := 0.3        # centre above the floor, blocks
const PELLET_BOB := 0.06          # bob height, blocks
const POWER_RADIUS := 0.23        # power pellets: big glowing orbs (0.46 blocks across)
const PICKUP_HEIGHT := 0.6        # power pellets, clocks and keys float higher ...
const PICKUP_BOB := 0.12          # ... and bob more
const OUTLINE_PX := 0.5           # black outline width round the orbs, in screen pixels

var _floats := {} # Vector2i(col, row) -> [home, phase, spin (deg/s), bob speed (rad/s), bob height]


func _spawn_pellets() -> void:
	var pellet_look := _orb(PELLET_RADIUS * tile, Color(0.25, 0.55, 1.0, 0.72), Color(0.1, 0.35, 1.2))
	var gold_look := _orb(GOLD_RADIUS * tile, Color(1.0, 0.75, 0.1, 0.72), Color(1.3, 0.8, 0.1))
	var power_look := _orb(POWER_RADIUS * tile, Color(1.0, 0.85, 0.15, 0.72), Color(1.2, 0.85, 0.1))
	for row in length:
		for col in width:
			var key := Vector2i(col, row)
			var at := tile_centre(key)
			match _char(col, row):
				".", ",":
					var gold := _char(col, row) == ","
					_place(key, _add_orb(gold_look if gold else pellet_look), Eaten.GOLD if gold else Eaten.PELLET,
						[at + Vector3.UP * PELLET_HEIGHT * tile, randf() * 100.0,
						randf_range(40.0, 140.0) * (1 if randf() < 0.5 else -1), randf_range(1.2, 2.4), PELLET_BOB * tile])
				"O", "o":
					_place(key, _add_orb(power_look), Eaten.POWER, _pickup_float(at))
				"C":
					_place(key, _clock(), Eaten.CLOCK, _pickup_float(at))
				"K":
					_place(key, _key(), Eaten.KEY, _pickup_float(at))


func _place(key: Vector2i, node: Node3D, kind: Eaten, float_: Array) -> void:
	pellets[key] = node
	_kinds[key] = kind
	_floats[key] = float_


func _pickup_float(at: Vector3) -> Array:
	return [at + Vector3.UP * PICKUP_HEIGHT * tile, randf() * 10.0, 150.0, 3.0, PICKUP_BOB * tile]


## A see-through jelly sphere and its outline: a flat ring facing the camera around the sphere's edge
## (see outline.gdshader). Returns [sphere mesh, ring mesh], shared by every orb of that look.
func _orb(radius: float, color: Color, glow: Color) -> Array:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = _glass(color, glow, 0.05)

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


## The clock (side rooms): a tall glowing cyan crystal.
func _clock() -> Node3D:
	return _add_block(Vector3(0.28, 0.6, 0.28) * tile, _glass(Color(0.3, 0.9, 1.0, 0.75), Color(0.3, 1.3, 1.6), 0.1))


## The key (side rooms): a magenta cube with a bar through it.
func _key() -> Node3D:
	var look := _glass(Color(1.0, 0.3, 1.0, 0.75), Color(1.5, 0.2, 1.5), 0.1)
	var key := _add_block(Vector3.ONE * 0.32 * tile, look)
	var bar := MeshInstance3D.new()
	bar.mesh = BoxMesh.new()
	bar.mesh.size = Vector3(0.7, 0.1, 0.1) * tile
	bar.mesh.material = look
	key.add_child(bar)
	return key


func _add_block(size: Vector3, look: Material) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	block.mesh = BoxMesh.new()
	block.mesh.size = size
	block.mesh.material = look
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(block)
	return block


## See-through, glowing material for the orbs, pickups and gate.
static func _glass(color: Color, glow: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.roughness = roughness
	m.emission_enabled = true
	m.emission = glow
	return m


## Pellets spin at their own speed and direction, and bob up and down out of step.
func _float_pellets() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for key in pellets:
		var pellet: Node3D = pellets[key]
		var f: Array = _floats[key]
		var ph: float = f[1] + time
		pellet.position = f[0] + Vector3.UP * sin(ph * f[3]) * f[4]
		pellet.rotation_degrees = Vector3(sin(ph * 0.7) * 8.0, ph * f[2], cos(ph * 0.9) * 8.0)


## How many pellets (of any colour) are left: the gate opens at none.
func pellets_left() -> int:
	var n := 0
	for kind in _kinds.values():
		if kind in [Eaten.PELLET, Eaten.GOLD, Eaten.POWER]:
			n += 1
	return n


## Eat or take whatever floats on the tile under `world`, if it's level with it.
func try_eat_pellet(world: Vector3) -> Eaten:
	var key := tile_under(world)
	var pellet: Node3D = pellets.get(key)
	if pellet == null or absf(pellet.global_position.y - world.y) > tile * 1.5:
		return Eaten.NOTHING
	pellets.erase(key)
	pellet.queue_free()
	var kind: Eaten = _kinds[key]
	_kinds.erase(key)
	return kind


# ------------------------------------------------------------------ gate

var _gate: StaticBody3D


## A solid glowing block in the exit, until every pellet is eaten (or the key is found).
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
	block.mesh.material = _glass(Color(0.1, 0.8, 0.8, 0.6), Color(0.05, 0.7, 0.7), 0.1) # teal glass
	_gate.add_child(block)
	_gate.position = tile_centre(exit_tile()) + Vector3.UP * tile * 0.6
	add_child(_gate)


func open_gate() -> void:
	if _gate != null:
		_gate.queue_free()
		_gate = null


func gate_open() -> bool:
	return _gate == null
