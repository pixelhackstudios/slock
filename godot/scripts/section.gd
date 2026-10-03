class_name Section
extends Node3D
## One map section, drawn by hand: '#' wall, '.' floor, ' ' nothing. The first line is the far end;
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
	"#########.#########",
	"#.......#.....#...#",
	"#.#####.#.###.#.#.#",
	"#.#...#...#...#.#.#",
	"#.#.#.#####.###.#.#",
	"#...#.......#.....#",
	"###.#.#####.#.#####",
	"#...#.#.....#.....#",
	"#.###.#.###.#####.#",
	"#.....#...#.......#",
	"#.#######.#.#####.#",
	"#.......#.#.#.....#",
	"#####.#.#.#.#.###.#",
	"#.....#...#...#...#",
	"#.#####.#######.#.#",
	"#.#.....#.....#.#.#",
	"#.#.###.#.###.#.#.#",
	"#...#.......#.....#",
	"#########.#########",
	"        #.#        ",
	"        #.#        ",
	"        #.#        ",
	"        #.#        ",
	"        #.#        ",
	"        #.#        ",
	"        ###        ",
]

enum { VOID, FLOOR, WALL }
enum { SURF_FLOOR, SURF_WALL_SIDE, SURF_WALL_TOP }

var width: int
var length: int
var centre: int
var tiles: Array = [] # tiles[col][row]


func _ready() -> void:
	_parse()
	_build_mesh()
	_build_collision()


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
	for col in width:
		tiles[col] = []
		tiles[col].resize(length)
		for row in length:
			var ch := LAYOUT[length - 1 - row][col]
			tiles[col][row] = WALL if ch == "#" else (FLOOR if ch == "." else VOID)


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
