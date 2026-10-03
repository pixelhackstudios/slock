class_name Swurm
extends Node3D
## A swurm: a green block worm that inches through the maze like a telescope. The head, one tile cube, slides two
## tiles while the body stays put; then it stops and the five segments (each 20% smaller than the one ahead)
## follow in a short train until they are all tucked inside the head, and it slides again. Nothing rotates: the
## blocks stay square to the grid. Touching the head knocks Slock and the swurm about 3 tiles apart, unless a
## power pellet is active (see main.gd), in which case it gets eaten. It starts at home in the pen and waits there
## until released.

const SEGMENT_SCALE: Array[float] = [0.8, 0.64, 0.512, 0.41, 0.328] # each 20% smaller than the one ahead
const SLIDE_TILES := 2            # the head slides two tiles per move (one where two won't fit)
const SEGMENT_GAP := 0.08         # edge-to-edge gap between segments in the train, in tiles
const KNOCK_SPEED := 2.5          # a knock-back slide runs this many times faster than crawling
const SCARED_SPEED := 0.55        # frightened swurms (power pellet active) are slow

const GREEN := [Color(0.2, 0.75, 0.12, 0.72), Color(0.02, 0.18, 0.0)]  # [colour (alpha: see-through), glow]
const SCARED := [Color(0.15, 0.3, 1.0, 0.72), Color(0.02, 0.08, 0.5)]
const FLASH := [Color(1, 1, 1, 0.72), Color(0.6, 0.6, 0.6)]             # scared, power about to run out

enum Mood { NORMAL, SCARED, FLASH }

var section: Section
var tiles_per_second := 15.0
var mood := Mood.NORMAL           # set by main.gd each frame
var eaten := false

var _home: Vector2i
var _from: Vector2i
var _to: Vector2i
var _t := 0.0
var _size := 1.0
var _sliding := false             # head moving; otherwise the body is catching up
var _knocked := false             # this slide is a knock-back from hitting Slock
var _slide_start := Vector3.ZERO  # where the head's current slide began (mid-tile after a knock)
var _gather_time := 0.0
var _gather_from: Array[Vector3] = []
var _head: Jelly
var _body: Array[Jelly] = []
var _shown_mood := -1
var _release_at := INF            # waits at home in the pen until then
var _respawn_at := 0.0


func _init(home_section: Section, home: Vector2i) -> void:
	section = home_section
	_size = Section.TILE
	_home = home
	_head = Jelly.new(Vector3.ONE * _size, Jelly.Look.SWURM)
	_head.wobbles = false # stays an exact one-tile cube
	add_child(_head)
	for s in SEGMENT_SCALE:
		var seg := Jelly.new(Vector3.ONE * _size * s, Jelly.Look.SWURM)
		add_child(seg)
		_body.append(seg)
	reset()


## Back home in the pen, waiting to be released.
func reset() -> void:
	eaten = false
	visible = true
	_release_at = INF
	_from = _home
	_to = _home
	_head.position = _pos(_home)
	for i in _body.size():
		_body[i].position = _floor_point(_head.position, SEGMENT_SCALE[i])
	_shown_mood = -1
	_pick_next()


func head_position() -> Vector3:
	return _head.position


## Leave the pen at `time` (seconds, game clock).
func release_at(time: float) -> void:
	_release_at = time


## Eaten while a power pellet is active: vanish, then crawl back out from home after `delay` seconds.
func get_eaten(now: float, delay: float) -> void:
	eaten = true
	visible = false
	_respawn_at = now + delay


## Hit Slock: get knocked up to `tiles` blocks straight away from `slock_pos` (as far as open floor allows;
## sideways if straight back is blocked), quickly, then carry on crawling (not back toward it).
func knock_back(slock_pos: Vector3, now: float, tiles := 3) -> void:
	if eaten:
		return
	var away := _head.position - slock_pos
	var dir := Vector2i(1 if away.x >= 0.0 else -1, 0) if absf(away.x) >= absf(away.z) \
		else Vector2i(0, -1 if away.z >= 0.0 else 1) # rows run along -Z
	var at := _to if not _sliding or _t >= 0.5 else _from # the block the head is mostly over right now
	var n := _room(at, dir, tiles)
	if n == 0: # e.g. just round a corner: sideways, whichever side is longer
		var side := Vector2i(dir.y, dir.x)
		var a := _room(at, side, tiles)
		var b := _room(at, -side, tiles)
		if a > 0 or b > 0:
			dir = side if a >= b else -side
			n = maxi(a, b)
	_slide_start = _head.position
	_from = at
	_to = at + dir * n
	_t = 0.0
	_sliding = true
	_knocked = true
	_release_at = minf(_release_at, now) # knocked out of the pen early: it's loose now


func _room(at: Vector2i, d: Vector2i, tiles: int) -> int:
	var k := 0
	while k < tiles and section.is_crawlable(at + d * (k + 1)):
		k += 1
	return k


func tick(delta: float, now: float) -> void:
	if eaten:
		if now < _respawn_at:
			return
		reset()
		_release_at = now
	_update_look()
	if now < _release_at:
		return # still waiting in the pen

	var speed := tiles_per_second * (SCARED_SPEED if mood != Mood.NORMAL else 1.0)
	if _sliding:
		# Head: one eased slide; the body stays where it was.
		var end := _pos(_to)
		var tiles := maxf(1.0, _slide_start.distance_to(end) / _size)
		_t = minf(1.0, _t + delta * speed * (KNOCK_SPEED if _knocked else 1.0) / tiles)
		var m := 1.0 - (1.0 - _t) * (1.0 - _t) if _knocked else _t * _t * (3.0 - 2.0 * _t) # a knock starts fast, eases out
		_head.position = _slide_start.lerp(end, m)
		if _t < 1.0:
			return
		_sliding = false
		_gather_time = 0.0
		_gather_from.clear()
		for seg in _body:
			_gather_from.append(seg.position)
		return

	# Body: each segment sets off once the one ahead is a block-edge gap clear of it, so the train is evenly
	# spaced edge to edge (smaller blocks sit closer, centre to centre), and slides into the head.
	_gather_time += delta
	var gathered := true
	var lag := 0.0
	for i in _body.size():
		if i > 0:
			lag += _size * ((SEGMENT_SCALE[i - 1] + SEGMENT_SCALE[i]) * 0.5 + SEGMENT_GAP)
		var target := _floor_point(_head.position, SEGMENT_SCALE[i])
		var dist := _gather_from[i].distance_to(target)
		var travelled := maxf(0.0, _gather_time * speed * _size - lag)
		var f := 1.0 if dist < 1e-4 else clampf(travelled / dist, 0.0, 1.0)
		_body[i].position = _gather_from[i].lerp(target, f)
		if f < 1.0:
			gathered = false
	if gathered:
		_pick_next()


func _update_look() -> void:
	if mood == _shown_mood:
		return
	_shown_mood = mood
	var look: Array = [GREEN, SCARED, FLASH][mood]
	for block in [_head] + _body:
		block.set_colors(look[0], look[1])


## Start the next slide from `_to`: two tiles straight on if it can, else one, never straight back the way it
## came unless it's a dead end.
func _pick_next() -> void:
	var back := _from - _to
	back = Vector2i(signi(back.x), signi(back.y))
	_from = _to
	var next: Variant = _choose(SLIDE_TILES, back)
	if next == null:
		next = _choose(1, back)
	_to = next if next != null else _from + back
	_slide_start = _pos(_from)
	_t = 0.0
	_sliding = true
	_knocked = false


func _choose(tiles: int, back: Vector2i) -> Variant:
	var options: Array[Vector2i] = []
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if d == back:
			continue
		var clear := true
		for i in range(1, tiles + 1):
			clear = clear and section.is_crawlable(_from + d * i)
		if clear:
			options.append(_from + d * tiles)
	return options.pick_random() if not options.is_empty() else null


## Head centre on a tile (a one-tile cube resting on the floor).
func _pos(tile: Vector2i) -> Vector3:
	return section.tile_centre(tile) + Vector3.UP * _size * 0.5


## Centre of a block of relative `scale` resting on the floor under `p`.
func _floor_point(p: Vector3, scale_: float) -> Vector3:
	return Vector3(p.x, _size * scale_ * 0.5, p.z)
