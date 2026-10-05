class_name Section
extends Node3D
## One section of the course. Its layout comes from maze_gen.gd as lines of text, the first line the far end.
## Sections are laid end to end along -Z, each RISE higher than the last, and each with blocks a little smaller
## (see tile_of).
##
## The maze (main level):           '#' wall  '.' floor with a pellet  'O' power pellet  '_' bare floor
##                                  'S' swurm pen floor (where they start)  '*' a powerup
## The side room (SIDE_DROP lower): '=' wall  ',' floor with a gold pellet  'o' power pellet  '-' bare floor
##                                  'C' clock  'K' key
## The side ramp between them:      '>' ramp floor  '^' ramp wall (it slopes from the room up to the maze)
## Anything else (a space) is nothing: a pit inside, or an open edge to slide off.
## The bottom lines are the climb ramp up from the previous section (flat on the first section, which also has a
## back wall); the maze proper starts where its outer walls do.
##
## Grid (col, row) counts rows up from the bottom line; the maze's exit column is x = 0. Walls are one block tall.
## Collision is two static bodies, neither with seams to snag on: the floor, one continuous surface of triangles
## (normal friction), and the walls, slabs merged into long runs so each straight wall is one flat face (no friction,
## so sliding along a wall never brakes).

const BASE_BLOCK := 60            # "resolution": blocks are BLOCK/60 tiles across, 2 smaller each section...
const BLOCK_STEP := 2
const MIN_BLOCK := 20             # ... down to a third
const RISE := 1.0                 # each section's floor is this much higher than the last
const SIDE_DROP := 3.0            # how far below the maze a side room sits
const DEPTH := 1.0                # how far blocks reach below the lowest floor of a section

enum { VOID, FLOOR, WALL }
enum Level { MAIN, LOW, CLIMB, SIDE } # the maze, the side room, the climb ramp, the side ramp
enum Eaten { NOTHING, PELLET, GOLD, POWER, CLOCK, KEY, STEEL, CLEAR_DOTS, CLOSE_TRAPS, SLUG_PACK, EXTRA_SLUG }

var index := 0
var layout: Array[String]         # see the characters above
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
var pellets := {}                 # Vector2i(col, row) -> what floats there (Eaten): pellet, power pellet, clock, key
var _prev_floor := 0.0            # where the climb ramp starts from: the previous section's floor
var _side := Vector3i(-1, -1, -1) # the side ramp: first col, last col, row (-1: none)
var _exit_sealed := false
var sliced := false               # build a little each frame (sections streamed in ahead), not all at once
var built := false                # finished building: safe to play on
var _seed := 0
var _slice_from := 0

const SLICE_USEC := 3000          # building a sliced section takes at most this much of a frame

signal _frame


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
		z -= (MazeGen.rows_of(k) - 1) * tile_of(k)
	return z


## Section `i` of the run with this seed. It generates and builds itself once it's in the scene.
func _init(section_index: int, seed: int) -> void:
	index = section_index
	_seed = seed
	tile = tile_of(index)
	floor_y = index * RISE
	_prev_floor = maxf(0.0, floor_y - RISE)
	near_edge = near_edge_of(index)


func _ready() -> void:
	_slice_from = Time.get_ticks_usec()
	if sliced: # generate on another thread while the game runs on
		var task := WorkerThreadPool.add_task(func(): layout = MazeGen.layout(index, _seed))
		while not WorkerThreadPool.is_task_completed(task):
			await _frame
		WorkerThreadPool.wait_for_task_completion(task)
		_slice_from = Time.get_ticks_usec()
	else:
		layout = MazeGen.layout(index, _seed)
	_parse()
	await _build_mesh()
	await _build_collision()
	await reset()
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
	_add_swurms()
	built = true


## While building sliced: carry on next frame once this frame's share is used up. (The frame check matters: a
## section that pauses while _frame is going out would otherwise be woken by that same emission.)
func _pause() -> void:
	if sliced and Time.get_ticks_usec() - _slice_from > SLICE_USEC:
		var frame := Engine.get_process_frames()
		while Engine.get_process_frames() == frame:
			await _frame
		_slice_from = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	_frame.emit()
	_float_pickups()


## The section's swurms, at home in its pen (or, with no room for a pen, anywhere well clear of the entry).
func _add_swurms() -> void:
	var homes := swurm_homes.duplicate()
	if homes.is_empty():
		for col in width:
			for row in range(maze_start + 5, length - 2):
				if is_crawlable(Vector2i(col, row)):
					homes.append(Vector2i(col, row))
	homes.shuffle()
	for k in MazeGen.swurm_count(index):
		var swurm := Swurm.new(self, homes[k % homes.size()])
		swurm.tiles_per_second = MazeGen.swurm_speed(index)
		add_child(swurm)
		swurms.append(swurm)


## Put every pellet and pickup back and close the gate (a new run).
func reset() -> void:
	for n in _orb_batches + _pickups.values():
		n.queue_free()
	_orb_batches.clear()
	_pickups.clear()
	_floats.clear()
	_slots.clear()
	pellets.clear()
	_once.clear()
	_powerups_due.clear()
	_pellets_left = 0
	await _spawn_pellets()
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
	var line := layout[length - 1 - row]
	return line[col] if col < line.length() else " "


func _parse() -> void:
	length = layout.size()
	width = 0
	for line in layout:
		width = maxi(width, line.length())
	centre = layout[0].find("_")
	maze_left = layout[0].find("#")
	maze_right = layout[0].rfind("#")
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
			elif ch in "._OS*":
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
#
# The blocks are built from the maze kit (models/maze_kit.glb, made by art-work/models.py): a wall block is a cap
# rounded over its top edges, a side piece on each face that shows and a rounded edge on each corner that shows (or a
# plug where four wall blocks meet); a floor tile is one flat piece. Each tile's pieces are stretched onto its floor,
# so they follow the ramps. Below the floors, the section's sheer sides (cliffs) are plain quads. The pieces' textures
# are in textures/maze/.

## A tile's top at its corners (see _floor_corners): its floor, or a block higher for walls.
func _top(col: int, row: int) -> PackedFloat32Array:
	var f := _floor_corners(col, row)
	if tile_at(col, row) == WALL:
		for i in 4:
			f[i] += tile
	return f


## A tile's top (see _top): from the strip being built, if it's there.
func _top_of(col: int, row: int) -> PackedFloat32Array:
	var k := col - _tops_from
	if k >= 0 and k < _tops.size():
		return _tops[k][row]
	return _top(col, row)


## The bottom of the section's blocks: DEPTH below its lowest floor.
func _bottom() -> float:
	return minf(_prev_floor, floor_y) - (SIDE_DROP if has_side_ramp() else 0.0) - DEPTH


const STRIP := 8                  # the visible mesh is built in strips this many columns wide, so a change to
                                  # one tile (a wall blasted, the exit sealed) only rebuilds its strip

const KIT_SURFACES := {           # a strip's surfaces: [kit piece, texture set]
	"cap": ["wall_cap", "cap"], "plug": ["wall_plug", "cap"], "side": ["wall_side", "wall"],
	"edge": ["wall_edge", "wall"], "floor": ["floor", "floor"], "ramp": ["floor", "ramp"], "pen": ["floor", "pen"],
}
const FACES := [                  # the side piece's quarter turns: [neighbour, its corners and ours on the shared edge]
	[Vector2i(0, -1), 3, 2, 0, 1],  # near (+z)
	[Vector2i(1, 0), 0, 3, 1, 2],   # right (+x)
	[Vector2i(0, 1), 1, 0, 2, 3],   # far (-z)
	[Vector2i(-1, 0), 2, 1, 3, 0],  # left (-x)
]
const FACE_NORMALS: Array[Vector3] = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
const CORNERS := [                # the edge piece's quarter turns: [x side, row side (-1 near), our corner]
	[1, -1, 1],  # near-right
	[1, 1, 2],   # far-right
	[-1, 1, 3],  # far-left
	[-1, -1, 0], # near-left
]

static var _kit := {}             # kit piece -> its four quarter turns about y: [positions, normals, tangents, uvs]
static var _kit_triangles := {}   # kit piece -> its triangles, repeated for as many copies as a strip has needed
static var _looks := {}           # texture set -> material

var _strips: Array[MeshInstance3D] = []
var _cliff_quads := 0             # quads in the cliff surface of the strip being built
var _tops: Array = []             # ... and its tiles' tops (see _top), from column _tops_from: _tops[col][row]
var _tops_from := 0


func _build_mesh() -> void:
	_load_kit()
	_strips.resize(ceili(width / float(STRIP)))
	for i in _strips.size():
		await _pause()
		_build_strip(i)


## (Re)build the visible mesh of strip `i`.
func _build_strip(i: int) -> void:
	var kit := {} # KIT_SURFACES key -> KitSurface
	for key in KIT_SURFACES:
		kit[key] = KitSurface.new()
	var cliff := SurfaceTool.new()
	cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cliff_quads = 0
	var h := tile * 0.5
	var bot := _bottom()
	var c0 := i * STRIP
	var c1 := mini(width, (i + 1) * STRIP)
	# Every tile's top, for the strip and the columns either side (a tile's pieces depend on its neighbours).
	_tops_from = maxi(0, c0 - 1)
	_tops.clear()
	for col in range(_tops_from, mini(width, c1 + 1)):
		var column := []
		column.resize(length)
		for row in length:
			column[row] = _top(col, row)
		_tops.append(column)
	for col in range(c0, c1):
		for row in length:
			var kind: int = tiles[col][row]
			if kind == VOID:
				continue
			var t: PackedFloat32Array = _tops[col - _tops_from][row]
			var f := _floor_corners(col, row) if kind == WALL else t # near-left, near-right, far-right, far-left
			var place := _placement(col, row, f)
			var sloped := not (is_equal_approx(f[0], f[1]) and is_equal_approx(f[1], f[2]) and is_equal_approx(f[2], f[3]))
			if kind == WALL:
				kit.cap.add(_kit.wall_cap[0], place, sloped)
				for k in 4:
					var c: Array = CORNERS[k]
					if _corner_enclosed(col, row, c[0], c[1], t[c[2]]):
						kit.plug.add(_kit.wall_plug[k], place, sloped)
					else:
						kit.edge.add(_kit.wall_edge[k], place, sloped)
			else:
				kit[_floor_surface(col, row)].add(_kit.floor[0], place, sloped)
			# Sides: a wall's side piece shows unless the neighbour is solid and at least as tall along the shared
			# edge; below it (or below a floor), a cliff runs down to the bottom where the neighbour is lower.
			var x := (col - centre) * tile
			var z := row_z(row)
			var xz: Array[Vector2] = [Vector2(x - h, z + h), Vector2(x + h, z + h), Vector2(x + h, z - h),
				Vector2(x - h, z - h)]
			var ref := floor_y - (SIDE_DROP if levels[col][row] == Level.LOW else 0.0)
			for k in 4:
				var face: Array = FACES[k]
				var n: Vector2i = Vector2i(col, row) + face[0]
				if kind == WALL and _shows(n.x, n.y, face[1], face[2], t[face[3]], t[face[4]]):
					kit.side.add(_kit.wall_side[k], place, sloped)
				if _shows(n.x, n.y, face[1], face[2], f[face[3]], f[face[4]]):
					var a: Vector2 = xz[face[3]]
					var b: Vector2 = xz[face[4]]
					_quad(cliff, Vector3(a.x, bot, a.y), Vector3(a.x, f[face[3]], a.y), Vector3(b.x, f[face[4]], b.y),
						Vector3(b.x, bot, b.y), FACE_NORMALS[k], ref)
	_tops.clear()

	var mesh := ArrayMesh.new()
	for key in kit:
		var s: KitSurface = kit[key]
		if s.copies == 0:
			continue # an empty surface can't be committed
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.positions
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TANGENT] = s.tangents
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_INDEX] = _triangles(KIT_SURFACES[key][0], s.copies)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _look(KIT_SURFACES[key][1]))
	if _cliff_quads > 0:
		cliff.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _look("cliff"))
	if _strips[i] != null:
		_strips[i].queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	_strips[i] = mi


## Which floor a tile gets: the booster ramps' tread plate, the swurm pen's grate, or plain floor.
func _floor_surface(col: int, row: int) -> String:
	if levels[col][row] == Level.SIDE or (levels[col][row] == Level.CLIMB and index > 0):
		return "ramp"
	return "pen" if _char(col, row) == "S" else "floor"


## Where kit pieces go on tile (col, row), whose floor is at `f` (see _floor_corners): from a piece's own unit block
## (x and z -0.5..0.5, standing on y = 0) to the world, stretched onto the tile's floor, which may slope.
func _placement(col: int, row: int, f: PackedFloat32Array) -> Transform3D:
	var rise_x := (f[1] + f[2] - f[0] - f[3]) * 0.5   # left to right
	var rise_z := (f[0] + f[1] - f[2] - f[3]) * 0.5   # far to near
	var at := Vector3((col - centre) * tile, (f[0] + f[1] + f[2] + f[3]) * 0.25, row_z(row))
	return Transform3D(Basis(Vector3(tile, rise_x, 0), Vector3(0, tile, 0), Vector3(0, rise_z, tile)), at)


## Whether a wall's corner is closed in: the two blocks beside it and the one across it are all walls at least as tall
## there (`height`), so its rounded edge would be hidden (a plug closes the dimple the four rounded corners leave).
## `sx`: +1 the right corner; `sr`: -1 the near corner.
func _corner_enclosed(col: int, row: int, sx: int, sr: int, height: float) -> bool:
	for n in [[col + sx, row, -sx, sr], [col, row + sr, sx, -sr], [col + sx, row + sr, -sx, -sr]]:
		if tile_at(n[0], n[1]) != WALL or _top_of(n[0], n[1])[_corner_index(n[2], n[3])] < height - 1e-4:
			return false
	return true


static func _corner_index(sx: int, sr: int) -> int:
	if sr < 0:
		return 0 if sx < 0 else 1
	return 3 if sx < 0 else 2


## Whether the side face towards neighbour (col, row) shows: unless the neighbour is solid and its top, at the
## two corners on the shared edge (`ca`, `cb`), is at least as high as ours there (`ya`, `yb`).
func _shows(col: int, row: int, ca: int, cb: int, ya: float, yb: float) -> bool:
	if tile_at(col, row) == VOID:
		return true
	var n := _top_of(col, row)
	return n[ca] < ya - 1e-4 or n[cb] < yb - 1e-4


## One flat cliff quad facing `normal`. UVs put one whole texture on each block's worth of it, lined up with the
## floor at height `ref`. Tangents (for the normal map) are set here, the way Godot's generate_tangents() would, but
## without its cost on the whole mesh.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, ref: float) -> void:
	_cliff_quads += 1
	# Godot draws clockwise triangles (seen from the front) as front faces.
	if (b - a).cross(c - a).dot(normal) > 0:
		var t := b
		b = d
		d = t
	# The texture's u runs along x (along z on faces looking along x), its v down the sides.
	var u := Vector3.BACK if absf(normal.x) > 0.5 else Vector3.RIGHT
	var tangent := Plane(u, 1.0 if u.cross(normal).dot(Vector3.DOWN) >= 0.0 else -1.0)
	for p in [a, b, c, a, c, d]:
		st.set_normal(normal)
		st.set_tangent(tangent)
		st.set_uv(Vector2((p.z if absf(normal.x) > 0.5 else p.x) / tile + 0.5, (ref - p.y) / tile))
		st.add_vertex(p)


## The material for one of the kit's texture sets (textures/maze/<set>_*.png).
static func _look(set_name: String) -> ORMMaterial3D:
	if _looks.has(set_name):
		return _looks[set_name]
	var m := ORMMaterial3D.new()
	var path := "res://textures/maze/%s_%s.png"
	m.albedo_texture = load(path % [set_name, "albedo"])
	m.normal_enabled = true
	m.normal_texture = load(path % [set_name, "normal"])
	m.orm_texture = load(path % [set_name, "orm"])
	m.ao_enabled = true
	if ResourceLoader.exists(path % [set_name, "emission"]):
		m.emission_enabled = true
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY # the texture is the glow
		m.emission = Color.WHITE
		m.emission_texture = load(path % [set_name, "emission"])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_looks[set_name] = m
	return m


## Load the maze kit's pieces (once), each in its four quarter turns about y: as modelled (facing +z, or at the near
## right corner), then turned a quarter at a time (so the next faces +x, then -z, then -x).
static func _load_kit() -> void:
	if not _kit.is_empty():
		return
	var scene: Node = load("res://models/maze_kit.glb").instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var arrays := mi.mesh.surface_get_arrays(0)
		var turns := []
		for k in 4:
			var turn := Transform3D(Basis(Vector3.UP, k * PI * 0.5), Vector3.ZERO)
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT].duplicate()
			for v in range(0, tangents.size(), 4):
				var tn := turn.basis * Vector3(tangents[v], tangents[v + 1], tangents[v + 2])
				tangents[v] = tn.x
				tangents[v + 1] = tn.y
				tangents[v + 2] = tn.z
			turns.append([turn * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array),
				turn * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array), tangents, arrays[Mesh.ARRAY_TEX_UV]])
		_kit[String(mi.name)] = turns
		_kit_triangles[String(mi.name)] = [arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_INDEX].duplicate()]
	scene.free()


## The triangles of `copies` copies of a kit piece, each copy's vertices straight after the last's.
static func _triangles(piece: String, copies: int) -> PackedInt32Array:
	var tri: Array = _kit_triangles[piece] # [one copy's, as many copies' as needed so far]
	var one: PackedInt32Array = tri[0]
	var many: PackedInt32Array = tri[1]
	var have := many.size() / one.size()
	if have < copies:
		var verts: int = (_kit[piece][0][0] as PackedVector3Array).size()
		var more := PackedInt32Array()
		more.resize((maxi(copies, have * 2) - have) * one.size())
		var k := 0
		for c in range(have, have + more.size() / one.size()):
			for i in one:
				more[k] = i + c * verts
				k += 1
		many.append_array(more)
		tri[1] = many
	return many.slice(0, copies * one.size())


## One of a strip's kit surfaces while it's built: the pieces added so far, placed in the world.
class KitSurface:
	var copies := 0
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()

	## Add a piece (one of its turns, see _load_kit) placed by `place` (see _placement).
	func add(turn: Array, place: Transform3D, sloped: bool) -> void:
		copies += 1
		positions.append_array(place * (turn[0] as PackedVector3Array))
		uvs.append_array(turn[3])
		if not sloped:
			normals.append_array(turn[1])
			tangents.append_array(turn[2])
			return
		# Stretched up a slope: normals tilt by the inverse transpose, tangents follow the surface.
		var nb := place.basis.inverse().transposed()
		var tn: PackedFloat32Array = turn[2]
		for n: Vector3 in turn[1]:
			normals.append((nb * n).normalized())
		for k in range(0, tn.size(), 4):
			var t := (place.basis * Vector3(tn[k], tn[k + 1], tn[k + 2])).normalized()
			tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, tn[k + 3]]))


# ------------------------------------------------------------------ collision

func _build_collision() -> void:
	# The bodies join the scene once they have all their shapes: a body already in the physics world
	# rebuilds its whole shape for every one added.
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var wall_body := StaticBody3D.new()
	wall_body.name = "Walls"
	wall_body.physics_material_override = PhysicsMaterial.new()
	wall_body.physics_material_override.friction = 0.0
	_floor_body = floor_body
	_wall_body = wall_body

	# Floor: one continuous surface of triangles over every solid tile (walls stand on it, so a blasted wall
	# has floor ready underneath). Jolt treats the edges between level neighbouring triangles as inside the
	# surface, so there are no seams to snag on, however ragged the maze (separate boxes for floor strips
	# snagged where rows of different shapes met).
	_floor_faces = PackedVector3Array()
	for col in width:
		await _pause()
		for row in length:
			if tiles[col][row] != VOID:
				_add_floor_faces(col, row)
	_floor_shape = CollisionShape3D.new()
	_floor_shape.shape = ConcavePolygonShape3D.new()
	_floor_shape.shape.backface_collision = true
	_floor_shape.shape.set_faces(_floor_faces)
	floor_body.add_child(_floor_shape)

	# Walls: each level (maze, side room, climb ramp, side ramp) is built separately, so every slab is one flat
	# or evenly sloped piece.
	for lvl in Level.values():
		var wall := func(c: int, r: int) -> bool: return tiles[c][r] == WALL and levels[c][r] == lvl

		# Walls: long runs both ways, overlapping where they cross, so every straight wall face is a single
		# slab face. A lone block that's in no run gets its own.
		var covered := {}
		for row in length:
			await _pause()
			for run in _runs_along_row(row, wall):
				if run[1] > run[0]:
					_wall_slab(run[0], run[1], row, row)
					for col in range(run[0], run[1] + 1):
						covered[Vector2i(col, row)] = true
		for col in width:
			await _pause()
			for run in _runs_along_col(col, wall):
				if run[1] > run[0]:
					_wall_slab(col, col, run[0], run[1])
					for row in range(run[0], run[1] + 1):
						covered[Vector2i(col, row)] = true
		for col in width:
			for row in length:
				if wall.call(col, row) and not covered.has(Vector2i(col, row)):
					_wall_slab(col, col, row, row)
	add_child(floor_body)
	add_child(wall_body)


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


var _floor_body: StaticBody3D
var _floor_shape: CollisionShape3D
var _floor_faces: PackedVector3Array
var _wall_body: StaticBody3D
var _wall_slabs := {}             # Vector2i(col, row) -> the wall slabs covering that tile


## The floor under tile (col, row), as two triangles for the floor's collision surface.
func _add_floor_faces(col: int, row: int) -> void:
	var c := Vector3((col - centre) * tile, 0, row_z(row))
	var h := tile * 0.5
	var f := _floor_corners(col, row) # near-left, near-right, far-right, far-left
	var nl := Vector3(c.x - h, f[0], c.z + h)
	var nr := Vector3(c.x + h, f[1], c.z + h)
	var fr := Vector3(c.x + h, f[2], c.z - h)
	var fl := Vector3(c.x - h, f[3], c.z - h)
	_floor_faces.append_array([fl, fr, nr, fl, nr, nl])


## A wall slab over tiles col0..col1, row0..row1, remembered against each tile it covers (to break it up again).
func _wall_slab(col0: int, col1: int, row0: int, row1: int) -> void:
	var cs := _slab(_wall_body, col0, col1, row0, row1)
	cs.set_meta("extent", Rect2i(col0, row0, col1 - col0 + 1, row1 - row0 + 1))
	for col in range(col0, col1 + 1):
		for row in range(row0, row1 + 1):
			if not _wall_slabs.has(Vector2i(col, row)):
				_wall_slabs[Vector2i(col, row)] = []
			_wall_slabs[Vector2i(col, row)].append(cs)


## A wall slab over tiles col0..col1, row0..row1 (inclusive, all on one level): from the floor up one block.
## Follows any slope.
func _slab(body: StaticBody3D, col0: int, col1: int, row0: int, row1: int) -> CollisionShape3D:
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
		var y0 := f
		var y1 := f + tile
		cs.shape = BoxShape3D.new()
		cs.shape.size = Vector3(x1 - x0, y1 - y0, z_near - z_far)
		cs.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z_near + z_far) * 0.5)
	else:
		var points := PackedVector3Array()
		for c in corners:
			points.append(Vector3(c[0], c[2], c[1]))
			points.append(Vector3(c[0], c[2] + tile, c[1]))
		cs.shape = ConvexPolygonShape3D.new()
		cs.shape.points = points
	body.add_child(cs)
	return cs


## A booster's markings: glowing chevrons (models/chevron.glb) pointing uphill from `bottom` to `top` (points on the
## ramp's centre line).
func _add_chevrons(bottom: Vector3, top: Vector3) -> void:
	var run := Vector3(top.x - bottom.x, 0, top.z - bottom.z)
	var uphill := run.normalized()
	var heading := atan2(-uphill.x, -uphill.z) # turns the chevron (modelled pointing -Z, like the climb ramp) uphill
	var slope := atan2(top.y - bottom.y, run.length())
	var count := maxi(2, roundi(run.length() / (tile * 1.5)))
	for i in count:
		var chevron := Section.model("chevron", false)
		chevron.basis = Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, slope) * Basis.from_scale(Vector3.ONE * tile)
		chevron.position = bottom.lerp(top, (i + 0.5) / count) + Vector3.UP * 0.004 * tile
		add_child(chevron)


## Wall up the exit behind Slock, once it's through: no going back.
func seal_exit() -> void:
	if _exit_sealed:
		return
	_exit_sealed = true
	open_gate()
	var e := exit_tile()
	tiles[e.x][e.y] = WALL
	_wall_slab(e.x, e.x, e.y, e.y)
	_rebuild_strips_near([e])


## Rebuild the strips holding these tiles (and the strip next door, for a tile on a strip's edge, whose side
## faces may change too).
func _rebuild_strips_near(changed: Array) -> void:
	var redo := {}
	for t: Vector2i in changed:
		for col in [t.x - 1, t.x, t.x + 1]:
			if col >= 0 and col < width:
				redo[col / STRIP] = true
	for i in redo:
		_build_strip(i)


## The maze's inner walls: what slugs and Slock of Steel can break (not its outer walls).
func is_inner_wall(t: Vector2i) -> bool:
	return tile_at(t.x, t.y) == WALL and levels[t.x][t.y] == Level.MAIN and t.x > maze_left and t.x < maze_right \
		and t.y > maze_start and t.y < length - 1


## Blast an inner wall block into open floor. False if it isn't one.
func blast_wall(t: Vector2i) -> bool:
	if not is_inner_wall(t):
		return false
	tiles[t.x][t.y] = FLOOR
	# Its wall slabs go; what's left of each either side of the gap goes back as new slabs.
	for cs: CollisionShape3D in _wall_slabs.get(t, []).duplicate():
		var r: Rect2i = cs.get_meta("extent")
		for col in range(r.position.x, r.end.x):
			for row in range(r.position.y, r.end.y):
				_wall_slabs[Vector2i(col, row)].erase(cs)
		cs.queue_free()
		if r.size.x > 1:
			if t.x > r.position.x:
				_wall_slab(r.position.x, t.x - 1, t.y, t.y)
			if t.x < r.end.x - 1:
				_wall_slab(t.x + 1, r.end.x - 1, t.y, t.y)
		elif r.size.y > 1:
			if t.y > r.position.y:
				_wall_slab(t.x, t.x, r.position.y, t.y - 1)
			if t.y < r.end.y - 1:
				_wall_slab(t.x, t.x, t.y + 1, r.end.y - 1)
	_wall_slabs.erase(t)
	_rebuild_strips_near([t])
	return true


## The side room's bounds (all its own tiles), or an empty rect without one.
func _room_rect() -> Rect2i:
	var r := Rect2i()
	for col in width:
		for row in length:
			if levels[col][row] == Level.LOW and tiles[col][row] != VOID:
				r = Rect2i(col, row, 1, 1) if r.size == Vector2i.ZERO else r.expand(Vector2i(col, row)).expand(Vector2i(col + 1, row + 1))
	return r


## Powerup: fill every pit in the maze and side room with floor, and wall up every gap in their outer walls (not
## the entry, exit or side-room doorways, nor the tile at `standing`, nor anything holding a pickup). Pellets on
## walled-up tiles go too. Returns how many traps were closed.
func close_traps(standing: Vector2i) -> int:
	var changed: Array[Vector2i] = []
	var maze := Rect2i(maze_left, maze_start, maze_right - maze_left + 1, length - maze_start)
	var room := _room_rect()
	var doorways: Array[Vector2i] = [Vector2i(centre, maze_start), exit_tile(), standing]
	if has_side_ramp():
		doorways.append(Vector2i(_side.y + 1 if _side_rises_right() else _side.x - 1, _side.z))
		doorways.append(Vector2i(_side.x - 1 if _side_rises_right() else _side.y + 1, _side.z))
	for area in [[maze, Level.MAIN], [room, Level.LOW]]:
		var r: Rect2i = area[0]
		for col in range(r.position.x, r.end.x):
			for row in range(r.position.y, r.end.y):
				var t := Vector2i(col, row)
				if tiles[col][row] == VOID:
					tiles[col][row] = FLOOR
					levels[col][row] = area[1]
					_add_floor_faces(col, row)
					changed.append(t)
					continue
				var edge := col == r.position.x or col == r.end.x - 1 or row == r.position.y or row == r.end.y - 1
				if not edge or tiles[col][row] != FLOOR or levels[col][row] != area[1] or t in doorways \
						or (pellets.has(t) and pellets[t] not in [Eaten.PELLET, Eaten.GOLD]):
					continue
				tiles[col][row] = WALL
				_wall_slab(col, col, row, row)
				_remove_pellet(t)
				changed.append(t)
	_floor_shape.shape.set_faces(_floor_faces)
	_rebuild_strips_near(changed)
	return changed.size()


# ------------------------------------------------------------------ pellets and pickups

const PELLET_RADIUS := 0.115      # blocks (0.23 across)
const GOLD_RADIUS := 0.14         # side-room pellets are a bit bigger (0.28 across)
const PELLET_HEIGHT := 0.3        # centre above the floor, blocks
const PELLET_BOB := 0.06          # bob height, blocks
const POWER_RADIUS := 0.23        # power pellets: big glowing orbs (0.46 blocks across)
const PICKUP_HEIGHT := 0.6        # power pellets, clocks and keys float higher ...
const PICKUP_BOB := 0.12          # ... and bob more
const OUTLINE_PX := 0.5           # black outline width round the orbs, in screen pixels
const PICKUP_OUTLINE_PX := 0.75   # ... and round the models: the clocks, keys and powerups, and the gate

var _pellets_left := 0            # blue pellets still uneaten: the gate opens at none (gold and power pellets
                                  # only add time)
var _heights := {}                # Vector2i(col, row) -> world height of what floats there
var _slots := {}                  # orbs: Vector2i(col, row) -> [sphere batch, ring batch, instance index]
var _orb_batches: Array[Node] = []
var _pickups := {}                # clocks, keys and powerups: Vector2i(col, row) -> their model ...
var _floats := {}                 # ... and how it floats: [home, phase]


## The orbs (pellets, gold pellets, power pellets) are drawn in batches, one per look: thousands of them in the
## later sections. They bob on the GPU (orb.gdshader). Clocks and keys are a few separate nodes.
func _spawn_pellets() -> void:
	var looks := { # Eaten -> [radius, float height, bob height, colour, glow]
		Eaten.PELLET: [PELLET_RADIUS, PELLET_HEIGHT, PELLET_BOB, Color(0.25, 0.55, 1.0, 0.72), Color(0.1, 0.35, 1.2)],
		Eaten.GOLD: [GOLD_RADIUS, PELLET_HEIGHT, PELLET_BOB, Color(1.0, 0.75, 0.1, 0.72), Color(1.3, 0.8, 0.1)],
		Eaten.POWER: [POWER_RADIUS, PICKUP_HEIGHT, PICKUP_BOB, Color(1.0, 0.85, 0.15, 0.72), Color(1.2, 0.85, 0.1)],
	}
	var kind_of := {".": Eaten.PELLET, ",": Eaten.GOLD, "O": Eaten.POWER, "o": Eaten.POWER, "C": Eaten.CLOCK, "K": Eaten.KEY,
		"*": Eaten.STEEL} # the kind of powerup is picked as it appears
	var spots := {} # Eaten -> [Vector2i]
	for row in length:
		await _pause()
		for col in width:
			var kind: Eaten = kind_of.get(_char(col, row), Eaten.NOTHING)
			if kind == Eaten.NOTHING:
				continue
			var key := Vector2i(col, row)
			pellets[key] = kind
			if kind in [Eaten.CLOCK, Eaten.KEY]:
				_add_pickup(key, kind, _add_model("clock" if kind == Eaten.CLOCK else "key"))
			elif kind == Eaten.STEEL:
				_add_powerup(key)
			else:
				if kind == Eaten.PELLET:
					_pellets_left += 1
				if not spots.has(kind):
					spots[kind] = []
				spots[kind].append(key)

	for kind in spots:
		var look: Array = looks[kind]
		var radius: float = look[0] * tile
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 24
		sphere.rings = 12
		var jelly := ShaderMaterial.new()
		jelly.shader = load("res://scripts/orb.gdshader")
		jelly.set_shader_parameter("albedo", look[3])
		jelly.set_shader_parameter("emission", look[4])
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

		var keys: Array = spots[kind]
		var batches := []
		for mesh in [sphere, ring]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = keys.size()
			var batch := MultiMeshInstance3D.new()
			batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # they never move (they bob on the GPU)
			batch.multimesh = mm
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(batch)
			_orb_batches.append(batch)
			batches.append(mm)
		var pellet: bool = kind != Eaten.POWER
		for n in keys.size():
			if n % 64 == 0:
				await _pause()
			var key: Vector2i = keys[n]
			var home: Vector3 = tile_centre(key) + Vector3.UP * look[1] * tile
			# Each bobs at its own pace, out of step with the rest: (phase, speed rad/s, height).
			var bob := Color(randf() * (100.0 if pellet else 10.0), randf_range(1.2, 2.4) if pellet else 3.0, look[2] * tile, 0)
			for mm: MultiMesh in batches:
				mm.set_instance_transform(n, Transform3D(Basis(), home))
				mm.set_instance_custom_data(n, bob)
			_slots[key] = [batches[0], batches[1], n]
			_heights[key] = home.y


func _add_pickup(key: Vector2i, kind: Eaten, node: Node3D) -> void:
	var home := tile_centre(key) + Vector3.UP * PICKUP_HEIGHT * tile
	pellets[key] = kind
	_pickups[key] = node
	_floats[key] = [home, randf() * 10.0]
	_heights[key] = home.y
	node.position = home


## A model (models/<name>.glb, made by art-work/models.py), sized for this section's blocks and added to it.
func _add_model(name: String, shadow := false) -> Node3D:
	var node := Section.model(name, true, shadow)
	node.scale = Vector3.ONE * tile
	add_child(node)
	return node


static var _models := {}          # name -> its scene, loaded once
static var _outline_pass: ShaderMaterial

## A new copy of a model (models/<name>.glb), at its own size (one block = 1): outlined (see _dress) unless `outline` is
## false, and casting no shadow unless `shadow`.
static func model(name: String, outline := true, shadow := false) -> Node3D:
	if not _models.has(name):
		_models[name] = load("res://models/%s.glb" % name)
	var node: Node3D = _models[name].instantiate()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if outline:
			_dress(mi.mesh)
	return node


## Give a model's materials their black outline: each marks the pixels it draws in the stencil buffer, and draws the
## outline (model_outline.gdshader) round them as its next pass. Its materials are shared by every copy, so this only
## does anything the first time.
static func _dress(mesh: Mesh) -> void:
	if _outline_pass == null:
		_outline_pass = ShaderMaterial.new()
		_outline_pass.shader = load("res://scripts/model_outline.gdshader")
		_outline_pass.set_shader_parameter("width_px", PICKUP_OUTLINE_PX)
		_outline_pass.render_priority = Material.RENDER_PRIORITY_MAX # after every model has marked its pixels
	for k in mesh.get_surface_count():
		var m := mesh.surface_get_material(k) as BaseMaterial3D
		if m == null or m.next_pass != null:
			continue
		m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		m.stencil_reference = 1 # see model_outline.gdshader
		m.next_pass = _outline_pass


## See-through, glowing material for the pickups and gate.
static func _glass(color: Color, glow: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.roughness = roughness
	m.emission_enabled = true
	m.emission = glow
	return m


## Clocks, keys and powerups spin and bob.
func _float_pickups() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for key in _pickups:
		var f: Array = _floats[key]
		var ph: float = f[1] + time
		_pickups[key].position = f[0] + Vector3.UP * sin(ph * 3.0) * PICKUP_BOB * tile
		_pickups[key].rotation_degrees = Vector3(0, ph * 150.0, 0)


## How many blue pellets are left: the gate opens at none.
func pellets_left() -> int:
	return _pellets_left


## Eat or take whatever floats on the tile under `world`, if it's level with it.
func try_eat_pellet(world: Vector3) -> Eaten:
	var key := tile_under(world)
	if not pellets.has(key) or absf(_heights[key] - world.y) > tile * 1.5:
		return Eaten.NOTHING
	var kind: Eaten = pellets[key]
	_remove_pellet(key)
	return kind


## Take away whatever floats on tile `key` (eaten, cleared, or walled up).
func _remove_pellet(key: Vector2i) -> void:
	if not pellets.has(key):
		return
	var kind: Eaten = pellets[key]
	pellets.erase(key)
	if _slots.has(key):
		var slot: Array = _slots[key]
		for mm: MultiMesh in [slot[0], slot[1]]:
			mm.set_instance_transform(slot[2], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)) # gone
		_slots.erase(key)
		if kind == Eaten.PELLET:
			_pellets_left -= 1
	else:
		_pickups[key].queue_free()
		_pickups.erase(key)
		_floats.erase(key)


## Powerup: remove a random `fraction` of the pellets left (rounded up; not power pellets). Returns how many.
func remove_pellets(fraction: float) -> int:
	var keys := []
	for key in pellets:
		if pellets[key] in [Eaten.PELLET, Eaten.GOLD]:
			keys.append(key)
	keys.shuffle()
	var n := ceili(keys.size() * fraction)
	for k in n:
		_remove_pellet(keys[k])
	return n


# ------------------------------------------------------------------ powerups

const POWERUPS: Array[Eaten] = [Eaten.CLEAR_DOTS, Eaten.STEEL, Eaten.SLUG_PACK, Eaten.EXTRA_SLUG, Eaten.CLOSE_TRAPS]
const POWERUP_RESPAWN := 10.0     # seconds after one is taken until a new one appears, somewhere already cleared

var _once := {}                   # clear-the-dots and close-the-traps: at most one of each per section
var _powerups_due: Array[float] = []


func is_powerup(kind: Eaten) -> bool:
	return kind in POWERUPS


const POWERUP_MODELS := {         # each powerup's model (models/<name>.glb)
	Eaten.CLEAR_DOTS: "clear_dots",   # three blue pellets on a spinner
	Eaten.STEEL: "steel",             # a riveted steel block
	Eaten.SLUG_PACK: "slug_pack",     # a clip of three slugs
	Eaten.EXTRA_SLUG: "extra_slug",   # one big slug
	Eaten.CLOSE_TRAPS: "close_traps", # a green floor patch
}


## A random powerup on tile `key`: clear-the-dots and close-the-traps come at most once per section.
func _add_powerup(key: Vector2i) -> void:
	var kind: Eaten
	while true:
		kind = POWERUPS.pick_random()
		if not _once.has(kind):
			break
	if kind in [Eaten.CLEAR_DOTS, Eaten.CLOSE_TRAPS]:
		_once[kind] = true
	_add_pickup(key, kind, _add_model(POWERUP_MODELS[kind]))


## Polished steel: Slock of Steel's powerup (and Slock while it lasts, see jelly.gd).
static func steel_look() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.8, 0.85)
	m.metallic = 0.9
	m.roughness = 0.08
	m.emission_enabled = true
	m.emission = Color(0.12, 0.12, 0.14)
	return m


## A powerup was taken here: a new one appears POWERUP_RESPAWN seconds later.
func powerup_taken(now: float) -> void:
	_powerups_due.append(now + POWERUP_RESPAWN)


## Put out any powerups that are due, on a random tile of the maze that's already been cleared, at least 3 tiles
## from Slock (at `slock_tile`). Stops once Slock has left the section.
func respawn_powerups(now: float, slock_tile: Vector2i) -> void:
	if _exit_sealed or _powerups_due.is_empty() or _powerups_due.min() > now:
		return
	var spots := []
	for t: Vector2i in _reachable():
		if t.x > maze_left and t.x < maze_right and t.y > maze_start + 1 and t.y < length - 2 and not pellets.has(t) \
				and _char(t.x, t.y) != "S" and absi(t.x - slock_tile.x) + absi(t.y - slock_tile.y) >= 3:
			spots.append(t)
	for i in range(_powerups_due.size() - 1, -1, -1):
		if _powerups_due[i] > now or spots.is_empty():
			continue
		var t: Vector2i = spots.pick_random()
		spots.erase(t)
		_add_powerup(t)
		_powerups_due.remove_at(i)


## The maze floor you can walk to from its entry.
func _reachable() -> Dictionary:
	var start := Vector2i(centre, maze_start)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if tile_at(n.x, n.y) == FLOOR and levels[n.x][n.y] == Level.MAIN and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


# ------------------------------------------------------------------ gate

var _gate: StaticBody3D           # the barrier, while the gate is shut
var _gate_frame: Node3D           # stays: after the gate opens, and round the wall when the exit is sealed


## The gate (models/gate.glb): a frame round the exit, and a solid glowing barrier in it until every pellet is eaten
## (or the key is found).
func close_gate() -> void:
	if _gate != null:
		return
	var at := tile_centre(exit_tile())
	if _gate_frame == null:
		_gate_frame = _add_model("gate", true)
		_gate_frame.get_node("barrier").free()
		_gate_frame.position = at
	_gate = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(tile, tile * 1.2, tile)
	shape.position = Vector3.UP * tile * 0.6
	_gate.add_child(shape)
	var gate := Section.model("gate", false)
	var barrier: MeshInstance3D = gate.get_node("barrier")
	gate.remove_child(barrier)
	gate.free()
	var field := ShaderMaterial.new()
	field.shader = load("res://scripts/gate_barrier.gdshader")
	barrier.material_override = field
	barrier.scale = Vector3.ONE * tile
	_gate.add_child(barrier)
	_gate.position = at
	add_child(_gate)


func open_gate() -> void:
	if _gate != null:
		_gate.queue_free()
		_gate = null


func gate_open() -> bool:
	return _gate == null
