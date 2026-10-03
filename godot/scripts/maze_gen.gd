class_name MazeGen
## Generates each section's layout, in the text format section.gd reads (see there for the characters). Ported
## from the Unity MazeChunk generator: a maze carved from the entry with a few loops knocked through, open rooms
## with pits (some missing an outer wall, so you can slide off), a clear corridor just inside the outer wall, the
## swurm pen in the middle, power pellets in dead ends, powerups, and usually a side room down a ramp off the left wall,
## holding gold pellets and a clock or a key. Sections keep roughly the same footprint as their blocks shrink, so
## each one has more, smaller tiles than the last. The same run seed and section index always give the same layout.

const BASE_WIDTH := 18.0          # a section's maze footprint, in world units
const BASE_LENGTH := 18.0
const RAMP_LENGTH := 6.0          # the climb ramp's length, in world units
const LAUNCH_TILES := 4           # the climb ramp launches Slock onto this tile of the maze

const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)] # +y: towards the exit

enum { WALL, FLOOR, PIT }


## How nasty section `i` is: everything ramps up and then plateaus.
static func loop_chance(i: int) -> float:
	return maxf(0.005, 0.3 - i * 0.3)  # extra openings in the maze (more ways to recover from a bad slide)


static func pit_chance(i: int) -> float:
	return minf(0.5, 0.2 + i * 0.05)


static func open_edge_chance(i: int) -> float:
	return minf(0.95, 0.4 + i * 0.06)


static func power_pellets(i: int) -> int:
	return 3 + mini(3, i / 3)


static func swurm_count(i: int) -> int:
	return 4 + i                       # Pac-Man: 4 to start, one more per section


static func swurm_speed(i: int) -> float:
	return minf(20.6, 15.0 + i * 0.3) # tiles/s


const POWERUPS := 3                # powerups out at once in a section


static func side_room_chance(i: int) -> float:
	return 1.0 if i == 0 else 0.7      # the first section always shows one off


static func _odd(v: float) -> int:
	var n := roundi(v)
	return n + 1 if n % 2 == 0 else n


## Maze width of section `i`, in tiles. Odd, with the centre column itself odd, so the centre is a maze cell and
## the cells line up with the side-room doorways.
static func maze_width(i: int) -> int:
	var w := _odd(BASE_WIDTH / Section.tile_of(i))
	return w if (w / 2) % 2 == 1 else w + 2


static func maze_length(i: int) -> int:
	return _odd(BASE_LENGTH / Section.tile_of(i))


static func ramp_tiles(i: int) -> int:
	return maxi(4, roundi(RAMP_LENGTH / Section.tile_of(i)))


## Rows in section `i`'s layout: the back wall row, the climb ramp, the maze.
static func rows_of(i: int) -> int:
	return 1 + ramp_tiles(i) + maze_length(i)


static func layout(i: int, seed: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + i * 104729
	var w := maze_width(i)
	var l := maze_length(i)
	var ramp := ramp_tiles(i)
	var centre := w / 2

	# --- the maze: t[x][z], z = 0 the entry row, l - 1 the exit row
	var t := _carve(w, l, Vector2i(centre, 1), loop_chance(i), rng)
	t[centre][0] = FLOOR
	t[centre][l - 1] = FLOOR

	# Open rooms, optionally with pits and a missing outer wall.
	var pits: Array[Vector2i] = []
	var area := w * l / (BASE_WIDTH * BASE_LENGTH)
	for r in roundi(rng.randi_range(2, 4) * area):
		var rw := rng.randi_range(3, 5)
		var rl := rng.randi_range(3, 5)
		var rx := rng.randi_range(1, w - rw - 1)
		if rng.randf() < 0.45:
			rx = 1 if rng.randi_range(0, 1) == 0 else w - 1 - rw # hug an edge
		var rz := rng.randi_range(2, l - 2 - rl)
		for x in range(rx, rx + rw):
			for z in range(rz, rz + rl):
				var inside := x > rx and x < rx + rw - 1 and z > rz and z < rz + rl - 1
				if inside and rng.randf() < pit_chance(i):
					t[x][z] = PIT
					pits.append(Vector2i(x, z))
				else:
					t[x][z] = FLOOR
		if rng.randf() < open_edge_chance(i):
			for z in range(rz, rz + rl):
				if rx == 1:
					t[0][z] = FLOOR
				if rx + rw == w - 1:
					t[w - 1][z] = FLOOR

	# A clear corridor runs all the way round just inside the outer wall.
	for x in range(1, w - 1):
		t[x][1] = FLOOR
		t[x][l - 2] = FLOOR
	for z in range(1, l - 1):
		t[1][z] = FLOOR
		t[w - 2][z] = FLOOR

	# The swurm pen in the middle (Pac-Man style): a wall ring with one opening towards the exit.
	var pen := _carve_pen(t, w, l)

	# The exit must be reachable: if pits cut the way, fill them in; if the pen did, flatten it.
	if _distances(t, Vector2i(centre, 0))[centre][l - 1] < 0:
		for p in pits:
			t[p.x][p.y] = FLOOR
	if _distances(t, Vector2i(centre, 0))[centre][l - 1] < 0:
		for p in pen.keys():
			t[p.x][p.y] = FLOOR
		pen.clear()
	t[centre][LAUNCH_TILES - 1] = FLOOR # where the climb ramp's launch lands

	# --- the side room, down a ramp off the maze's left wall
	var room: Array = []
	var room_w := 0
	var room_l := 0
	var room_z := 0                   # maze row of the room's first row
	var entrance := 0                 # room row of its doorway (and the ramp)
	var side_len := 0
	if rng.randf() < side_room_chance(i):
		side_len = maxi(3, roundi(4.0 / Section.tile_of(i)))
		room_w = _odd(rng.randi_range(7, 9) / Section.tile_of(i))
		room_l = _odd(rng.randi_range(7, 9) / Section.tile_of(i))
		room_z = 2 * rng.randi_range(0, (l - room_l) / 2) # keep row parity in step with the maze's cells
		entrance = 1 + 2 * rng.randi_range(0, (room_l - 1) / 2 - 1)
		var door_z := room_z + entrance
		t[0][door_z] = FLOOR                  # the doorway in the maze's left wall ...
		t[LAUNCH_TILES - 1][door_z] = FLOOR   # ... and where the side ramp's launch lands
		room = _make_room(room_w, room_l, entrance, rng, i)

	# --- what floats where
	var marks := {} # Vector2i(x, z) in the maze -> character
	var reach := _distances(t, Vector2i(centre, 0))
	var spots: Array[Vector2i] = []   # power pellets: dead ends first, then anywhere
	var others: Array[Vector2i] = []
	for x in range(1, w - 1):
		for z in range(2, l - 2):
			if t[x][z] != FLOOR or pen.has(Vector2i(x, z)) or reach[x][z] < 0:
				continue
			var ways := 0
			for d in DIRS:
				ways += int(t[x + d.x][z + d.y] == FLOOR)
			(spots if ways == 1 else others).append(Vector2i(x, z))
	_shuffle(spots, rng)
	_shuffle(others, rng)
	spots.append_array(others)
	for k in mini(power_pellets(i), spots.size()):
		marks[spots[k]] = "O"
	var rest := spots.slice(power_pellets(i))
	_shuffle(rest, rng)
	for k in mini(POWERUPS, rest.size()):
		marks[rest[k]] = "*"
	for p in pen.keys():
		marks[p] = pen[p]

	var room_marks := {}
	if not room.is_empty():
		var dist := _distances(room, Vector2i(0, entrance))
		var by_distance: Array[Vector2i] = []
		for x in room_w:
			for z in room_l:
				if dist[x][z] > 1:
					by_distance.append(Vector2i(x, z))
		by_distance.sort_custom(func(a, b): return dist[a.x][a.y] > dist[b.x][b.y])
		if by_distance.size() >= 2:
			room_marks[by_distance[0]] = "K" if rng.randf() < 0.35 else "C"
			room_marks[by_distance[mini(by_distance.size() - 1, by_distance.size() / 3)]] = "o"
		for x in room_w:
			for z in room_l:
				if room[x][z] == FLOOR and not room_marks.has(Vector2i(x, z)):
					room_marks[Vector2i(x, z)] = "," if dist[x][z] >= 0 else "-"

	# --- write it out: the room and side ramp to the left, then the maze; first line is the far end
	var left := room_w + side_len if not room.is_empty() else 0
	var rows := 1 + ramp + l
	var grid: Array = []
	for row in rows:
		var line: Array[String] = []
		line.resize(left + w)
		line.fill(" ")
		grid.append(line)
	var maze_row := func(z: int) -> int: return 1 + ramp + z
	# Back wall and climb ramp corridor.
	for col in [centre - 1, centre, centre + 1]:
		grid[0][left + col] = "#"
	for row in range(1, 1 + ramp):
		grid[row][left + centre - 1] = "#"
		grid[row][left + centre] = "_"
		grid[row][left + centre + 1] = "#"
	# The maze.
	for x in w:
		for z in l:
			var ch: String = "#" if t[x][z] == WALL else (" " if t[x][z] == PIT else ".")
			if t[x][z] == FLOOR:
				if marks.has(Vector2i(x, z)):
					ch = marks[Vector2i(x, z)]
				elif reach[x][z] < 0 or z == l - 1:
					ch = "_" # cut off by pits, or the exit (where the gate sits): no pellet
			grid[maze_row.call(z)][left + x] = ch
	# The side room (mirrored: its doorway is on its right, next to the ramp) and the ramp.
	if not room.is_empty():
		for x in room_w:
			for z in room_l:
				var ch: String = "=" if room[x][z] == WALL else (" " if room[x][z] == PIT else room_marks.get(Vector2i(x, z), "-"))
				grid[maze_row.call(room_z + z)][room_w - 1 - x] = ch
		var door_row: int = maze_row.call(room_z + entrance)
		for col in range(room_w, room_w + side_len):
			grid[door_row][col] = ">"
			grid[door_row - 1][col] = "^"
			grid[door_row + 1][col] = "^"

	var out: Array[String] = []
	for row in range(rows - 1, -1, -1):
		out.append("".join(grid[row]))
	return out


## A perfect maze (recursive backtracker on odd cells) from `start`, plus some loops. t[x][z].
static func _carve(w: int, l: int, start: Vector2i, loops: float, rng: RandomNumberGenerator) -> Array:
	var t := []
	for x in w:
		var col := []
		col.resize(l)
		col.fill(WALL)
		t.append(col)
	var stack: Array[Vector2i] = [start]
	t[start.x][start.y] = FLOOR
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d in DIRS:
			var n := cur + d * 2
			if n.x >= 1 and n.x <= w - 2 and n.y >= 1 and n.y <= l - 2 and t[n.x][n.y] == WALL:
				options.append(d)
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		t[cur.x + pick.x][cur.y + pick.y] = FLOOR
		t[cur.x + pick.x * 2][cur.y + pick.y * 2] = FLOOR
		stack.append(cur + pick * 2)

	# Knock out a few walls between corridors so there are loops.
	for x in range(1, w - 1):
		for z in range(1, l - 1):
			if t[x][z] != WALL or rng.randf() > loops:
				continue
			var across: bool = x % 2 == 0 and z % 2 == 1 and t[x - 1][z] == FLOOR and t[x + 1][z] == FLOOR
			var along: bool = x % 2 == 1 and z % 2 == 0 and t[x][z - 1] == FLOOR and t[x][z + 1] == FLOOR
			if across or along:
				t[x][z] = FLOOR
	return t


## The swurm pen: a 6x4 wall ring with one opening towards the exit and a 4x2 floor inside, standing clear in a
## one-tile corridor all the way round (so any corridor it cuts still connects). Returns its tiles: "S" where the
## swurms start, "_" for the opening. Empty if the maze is too small for it.
static func _carve_pen(t: Array, w: int, l: int) -> Dictionary:
	var cx := w / 2
	var cz := l / 2
	if cz % 2 == 0:
		cz += 1 # sit on a maze-cell row
	var x0 := cx - 2
	var x1 := cx + 3
	var z0 := cz - 1
	var z1 := cz + 2
	var pen := {}
	if x0 - 1 < 1 or x1 + 1 > w - 2 or z0 - 1 < 2 or z1 + 1 > l - 2:
		return pen
	for x in range(x0 - 1, x1 + 2):
		for z in range(z0 - 1, z1 + 2):
			var ring := x == x0 - 1 or x == x1 + 1 or z == z0 - 1 or z == z1 + 1
			var edge := x == x0 or x == x1 or z == z0 or z == z1
			var opening := x == cx and z == z1
			t[x][z] = FLOOR if ring or not edge or opening else WALL
			if not ring and not edge:
				pen[Vector2i(x, z)] = "S"
	pen[Vector2i(cx, z1)] = "_"
	return pen


## A side room: a loopy mini-maze entered at (0, entrance), with holes (never ones that cut part of it off)
## and its far wall missing here and there.
static func _make_room(w: int, l: int, entrance: int, rng: RandomNumberGenerator, i: int) -> Array:
	var t := _carve(w, l, Vector2i(1, entrance), 0.35, rng)
	t[0][entrance] = FLOOR
	var reachable := _count(_distances(t, Vector2i(0, entrance)))
	for tries in w * l / 6:
		var x := rng.randi_range(2, w - 2)
		var z := rng.randi_range(1, l - 2)
		if t[x][z] != FLOOR or rng.randf() > pit_chance(i):
			continue
		t[x][z] = PIT
		var now := _count(_distances(t, Vector2i(0, entrance)))
		if now < reachable - 1:
			t[x][z] = FLOOR
		else:
			reachable = now
	for z in range(1, l - 1):
		if t[w - 2][z] == FLOOR and rng.randf() < open_edge_chance(i) * 0.5:
			t[w - 1][z] = FLOOR
	return t


## Walking distance (in tiles) from `from` over floor; -1 where unreachable.
static func _distances(t: Array, from: Vector2i) -> Array:
	var w := t.size()
	var l: int = t[0].size()
	var dist := []
	for x in w:
		var col := []
		col.resize(l)
		col.fill(-1)
		dist.append(col)
	dist[from.x][from.y] = 0
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in DIRS:
			var n := c + d
			if n.x < 0 or n.x >= w or n.y < 0 or n.y >= l or dist[n.x][n.y] >= 0 or t[n.x][n.y] != FLOOR:
				continue
			dist[n.x][n.y] = dist[c.x][c.y] + 1
			queue.append(n)
	return dist


static func _count(dist: Array) -> int:
	var n := 0
	for col in dist:
		for v in col:
			n += int(v >= 0)
	return n


static func _shuffle(list: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for k in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp := list[k]
		list[k] = list[j]
		list[j] = tmp
