class_name Slock
extends RigidBody3D
## The sliding block. It stays on tile-centre rails and turns Pac-Man style at centres. On a flat floor the board's
## tilt sets how fast it goes (see TOP_SPEED); level the board and it stops on a tile. On ramps tilted gravity pushes
## it, with floor friction the only drag (walls have none), and a ramp booster can push it uphill and launch it in a
## hop. It's always one block across, shrinking smoothly when it passes into a section with smaller blocks. Its look
## and wobble are in jelly.gd.

const HEIGHT_RATIO := 1.1         # a hair taller than the walls (which are one block tall)
const SHRINK := 0.1               # hull undersize vs a tile: stops wedging, stays grid-true
const SHRINK_SPEED := 3.0         # block sizes per second, shrinking through a gate
const MAX_SPEED := 60.0           # safety limit only, well above what gravity reaches

# On a flat floor the tilt sets the speed and Slock eases to it: a gentle tilt is a steady creep, full tilt full speed,
# the same every time. (A tilt that set an acceleration left no middle speed: a crawl, or faster and faster.)
const TOP_SPEED := 15.0           # blocks/s at full tilt (more in later sections: it ramps up with gravity)
const ACCEL := 40.0               # blocks/s^2 at most, speeding up ...
const ACCEL_EASE := 5.0           # ... easing into the speed the tilt asks for (per second)
const BRAKE := 175.0              # blocks/s^2 at most, slowing to a lower speed ...
const BRAKE_EASE := 10.0          # ... easing into it
const COAST := 4.0                # blocks/s^2: slowing while you lean to the side for a turn
# Level the board and it stops on a tile centre: the first one ahead it can stop on braking no harder than
# STOP_BRAKE, or the last one before a hole or a wall if that comes first. From near rest it settles onto the nearest.
const LEVEL := 0.02               # tilt (fraction of full) under which the board counts as level
const STOP_BRAKE := 175.0         # blocks/s^2
const SETTLE_SPEED := 3.0         # blocks/s
# Turning: a lean to the side is remembered for a moment, and Slock takes the next opening that way (or one it has
# only just passed), keeping most of its speed round the corner.
const TURN_MEMORY := 0.3          # seconds
const TURN_LATE := 0.5            # blocks past an opening it can still turn back into it
const CORNER_CARRY := 0.9         # how much of its speed it keeps round a corner

# On ramps, and for a moment after a swurm knocks it away, plain physics moves it instead: tilted gravity, floor
# friction, and these.
const FRICTION := 0.058           # floor friction coefficient (0 = ice)
const KNOCK_TIME := 0.45          # seconds a swurm's knock runs on plain physics
# Creep: a soft, jelly-like resistance at low speed (strongest near rest, gone by CREEP_FADE_SPEED).
const CREEP_DAMPING := 6.0        # per second, at rest
const CREEP_FADE_SPEED := 6.0     # tiles/s
# Level means stop: grip that fades as the board tilts. Level, it's LEVEL_GRIP per second of speed (stops from
# 8 blocks/s in about a block); it eases off with the square of the tilt and is gone at full tilt.
const LEVEL_GRIP := 8.0           # per second

const HOLE_SNAP := 14.0           # how fast it lines up with a hole it's dropping into
const TURN_SNAP := 14.0           # how fast it slides to a tile centre to take a turn
const TURN_BIAS := 1.15           # tilt must favour the other axis by this much to turn (no jitter on diagonals)

const LAUNCH_DURATION := 0.55     # seconds in the air on a ramp launch
const GUIDE_BRAKE := 20.0         # blocks/s^2: how hard a ramp guide settles it toward its stop point

var size := 1.0                   # one grid block across
var height := HEIGHT_RATIO
var grid := 1.0                   # block size of the grid it's locked to
var grid_z := 0.0                 # the z of one of that grid's tile-centre rows
var travel_z := true              # rail it's on: true = runs along Z (X locked), false = runs along X (Z locked)
var grounded := false
var governed := false             # on a flat floor, going at the speed the tilt asks for (see TOP_SPEED)
var boost := Vector3.ZERO         # set by the ramp booster each physics frame: extra acceleration uphill
var boost_limit := 0.0            # ... until it's going this fast uphill
var launching := false
var _guiding := false
var _guide_dir := Vector3.ZERO
var _guide_stop := Vector3.ZERO
var _guide_since := 0
var _target_size := 1.0
var _hull: CollisionShape3D
var _jelly: Jelly
var _launch_from := Vector3.ZERO
var _launch_to := Vector3.ZERO
var _launch_t := 0.0
var _launch_peak := 0.0
var _saved_layers := Vector2i.ZERO
var _clock := 0.0                 # physics time, seconds
var _turn := Vector3.ZERO         # a lean to the side, remembered: the way to turn at the next opening ...
var _turn_until := 0.0            # ... until then (see TURN_MEMORY)
var _knocked_until := 0.0


func _init() -> void:
	mass = 1.0
	lock_rotation = true
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0 # no hidden drag: floor friction is the only resistance
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0 # floor friction is applied in _integrate_forces (it's off when governed)
	physics_material_override.bounce = 0.0

	_hull = CollisionShape3D.new()
	add_child(_hull)
	_jelly = Jelly.new(Vector3.ONE)
	_jelly.body = self
	add_child(_jelly)
	set_size_immediate(1.0)


## Slock of Steel's look (see jelly.gd).
func set_steel(on: bool) -> void:
	_jelly.set_steel(on)


## Snap to a block size (a new run).
func set_size_immediate(s: float) -> void:
	_target_size = s
	_apply_size(s)


## Shrink smoothly to a new block size (passing into a section with smaller blocks).
func shrink_to(s: float) -> void:
	_target_size = s


## Lock to a section's grid: its block size and the z of one of its tile-centre rows.
func set_grid(block: float, row_z: float) -> void:
	grid = block
	grid_z = row_z


func _apply_size(s: float) -> void:
	size = s
	height = s * HEIGHT_RATIO
	_hull.shape = _rounded_box(s * (1.0 - SHRINK), height, 0.08 * s)
	_jelly.scale = Vector3(s, height, s)


func _physics_process(delta: float) -> void:
	if not is_equal_approx(size, _target_size):
		_apply_size(move_toward(size, _target_size, SHRINK_SPEED * delta))


## Sliding down a side ramp along `dir`: braked so it comes to rest no further than `stop`, then it's the
## player's again.
func guide(dir: Vector3, stop: Vector3) -> void:
	if _guiding and _guide_stop == stop:
		return
	_guiding = true
	_guide_dir = dir.normalized()
	_guide_stop = stop
	_guide_since = Time.get_ticks_msec()


## Hop from here onto the floor tile centred at `landing`, high enough to clear `clear` (a wall). No collisions
## in the air; on landing it's stopped and back on its rails.
func launch(landing: Vector3, clear: float) -> void:
	if launching:
		return
	launching = true
	_guiding = false
	_launch_from = global_position
	_launch_to = landing + Vector3.UP * (height * 0.5 + 0.02)
	_launch_peak = (clear + 0.15 * grid) / 0.6 # clears it over the middle of the hop (4t(1-t) >= 0.6)
	_launch_t = 0.0
	_saved_layers = Vector2i(collision_layer, collision_mask)
	collision_layer = 0
	collision_mask = 0
	_set_rail_lock(false, false)
	custom_integrator = true


## A box with chamfered corners, so wall corners deflect it instead of snagging like a sharp box would.
static func _rounded_box(w: float, h: float, bevel: float) -> ConvexPolygonShape3D:
	var hx := w * 0.5
	var hy := h * 0.5
	var points := PackedVector3Array()
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				points.append(Vector3(sx * hx, sy * (hy - bevel), sz * (hx - bevel)))
				points.append(Vector3(sx * (hx - bevel), sy * hy, sz * (hx - bevel)))
				points.append(Vector3(sx * (hx - bevel), sy * (hy - bevel), sz * hx))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func reset_to(pos: Vector3) -> void:
	if launching:
		_end_launch()
	_guiding = false
	_turn = Vector3.ZERO
	travel_z = true
	_set_rail_lock(false, false)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos))
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	global_position = pos
	reset_physics_interpolation()


## Bounce away from `from` hard enough to slide about `tiles` grid blocks, plus a small hop (a swurm hit).
func bounce_back(from: Vector3, tiles := 3.0) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 1e-6:
		away = Vector3(linear_velocity.x, 0, linear_velocity.z)
	if away.length_squared() < 1e-6:
		away = Vector3.BACK
	away = away.normalized()
	# v = sqrt(2 a d): friction is the only resistance, so this slides ~tiles blocks.
	var a := maxf(0.5, FRICTION * TiltRig.FALL_GRAVITY)
	var speed := clampf(sqrt(2.0 * a * tiles * size), 2.5, 12.0)
	linear_velocity = Vector3(away.x * speed, linear_velocity.y + 2.0, away.z * speed)
	_knocked_until = _clock + KNOCK_TIME # slides free for a moment, rather than at the tilt's speed


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var p := state.transform.origin
	var v := state.linear_velocity
	var g := state.total_gravity
	var dt := state.step
	var space := state.get_space_state()
	_clock += dt
	if launching:
		_fly(state)
		return

	_apply_guide(state, p, v)
	p = state.transform.origin
	v = state.linear_velocity

	# Ramp booster (see main.gd): speeds it uphill, up to a limit.
	var boosting := boost != Vector3.ZERO
	if boosting and Vector3(v.x, 0, v.z).dot(boost.normalized()) < boost_limit:
		v += boost * dt
	boost = Vector3.ZERO

	var below := _floor_below(space, p, height * 0.5 + 0.35 * size)
	grounded = not below.is_empty()
	if not grounded and _ray(space, p, Vector3.DOWN, height * 0.5 + 1.5 * size):
		# Only briefly airborne (a bump): floor is right below, so this isn't a hole. Keep its speed and rail.
		_set_rail_lock(not travel_z, travel_z)
		state.linear_velocity = v
		return
	if not grounded:
		# Centre is over a hole (or past an edge): line up with that grid square and drop straight through it.
		_set_rail_lock(false, false)
		var target := Vector3(_snap(p.x), p.y, _snap_z(p.z))
		var pull := (target - p) * HOLE_SNAP
		state.linear_velocity = Vector3(pull.x, v.y, pull.z)
		return

	# Speeds and pushes scale with gravity: with the block's size, and up through the course.
	var unit := g.length() / TiltRig.FALL_GRAVITY
	var full := g.length() * sin(deg_to_rad(TiltRig.MAX_TILT)) # the sideways pull at full tilt
	var tilt := clampf(Vector2(g.x, g.z).length() / maxf(1e-4, full), 0.0, 1.0)
	var normal: Vector3 = below.normal
	governed = normal.y > 0.9999 and not boosting and _clock >= _knocked_until

	# Rails: the centre is locked to the tile-centre line across the corridor. It turns Pac-Man style, at a tile
	# centre: when the tilt favours the other axis (or did a moment ago, see TURN_MEMORY) and that way is open.
	var want_z := travel_z
	if absf(g.z) > absf(g.x) * TURN_BIAS:
		want_z = true
	elif absf(g.x) > absf(g.z) * TURN_BIAS:
		want_z = false
	var leaning := want_z != travel_z
	if leaning:
		_turn = Vector3(0, 0, signf(g.z)) if want_z else Vector3(signf(g.x), 0, 0)
		_turn_until = _clock + TURN_MEMORY
	elif _clock > _turn_until:
		_turn = Vector3.ZERO

	var pulling := false
	if _turn != Vector3.ZERO:
		var along := p.z if travel_z else p.x
		var speed := v.z if travel_z else v.x
		var nearest := _snap_z(along) if travel_z else _snap(along)
		var at := NAN # where along the rail to turn
		if absf(speed) < SETTLE_SPEED * unit:
			# Slow: at the nearest tile centre, sliding to it first.
			if _opens(space, p, nearest, _turn):
				if absf(nearest - along) < 0.02 * grid:
					at = nearest
				else:
					var pull := (nearest - along) * TURN_SNAP
					v = Vector3(v.x, v.y, pull) if travel_z else Vector3(pull, v.y, v.z)
					pulling = true
		else:
			# Moving: at a tile centre it reaches this step, or one it has only just passed.
			var dir := signf(speed)
			var ahead := nearest if (nearest - along) * dir >= 0.0 else nearest + dir * grid
			var behind := ahead - dir * grid
			if (along - behind) * dir <= TURN_LATE * grid and _opens(space, p, behind, _turn):
				at = behind
			elif (ahead - along) * dir <= absf(speed) * dt and _opens(space, p, ahead, _turn):
				at = ahead
		if not is_nan(at):
			# Round the corner: on a flat floor it keeps most of its speed; on plain physics momentum stops there.
			var carry := absf(speed) * CORNER_CARRY if governed else 0.0
			p = Vector3(p.x, p.y, at) if travel_z else Vector3(at, p.y, p.z)
			travel_z = _turn.z != 0.0
			v = Vector3(0, v.y, _turn.z * carry) if travel_z else Vector3(_turn.x * carry, v.y, 0)
			_turn = Vector3.ZERO
			pulling = false

	# Hold the cross axis exactly on the tile-centre line.
	if travel_z:
		p.x = _snap(p.x)
		v.x = 0.0
	else:
		p.z = _snap_z(p.z)
		v.z = 0.0
	_set_rail_lock(travel_z, not travel_z)

	if governed and not pulling:
		var axis := Vector3.BACK if travel_z else Vector3.RIGHT
		var speed := _govern(space, p, v.dot(axis), g.dot(axis) / maxf(1e-4, full), tilt, leaning, unit, dt)
		if speed == 0.0:
			# At rest on a tile centre: exactly on it.
			var along := p.z if travel_z else p.x
			var nearest := _snap_z(along) if travel_z else _snap(along)
			if absf(nearest - along) < 0.002 * grid:
				p = Vector3(p.x, p.y, nearest) if travel_z else Vector3(nearest, p.y, p.z)
		# The physics step adds gravity's pull along the rail after this: take it off here, so the speed comes out
		# as set.
		speed -= g.dot(axis) * dt
		v = Vector3(v.x, v.y, speed) if travel_z else Vector3(speed, v.y, v.z)
		state.transform.origin = p
		state.linear_velocity = v
		return

	var flat := Vector3(v.x, 0, v.z)
	if not pulling:
		# Floor friction, against gravity's press on the floor.
		flat = flat.move_toward(Vector3.ZERO, FRICTION * absf(g.dot(normal)) * dt)

	var sp := flat.length()

	# Creep (see CREEP_DAMPING): soft resistance that fades out as it speeds up.
	var fade := CREEP_FADE_SPEED * grid
	if sp > 1e-4 and sp < fade:
		flat -= flat * minf(1.0, CREEP_DAMPING * (1.0 - sp / fade) * dt)

	# Level means stop (see LEVEL_GRIP). "Level" is the whole board, so tilting toward a turn doesn't brake.
	var slack := 1.0 - tilt
	flat -= flat * minf(1.0, LEVEL_GRIP * slack * slack * dt)

	# Safety limit only (keeps fast falls from tunnelling); not part of the feel.
	if flat.length() > MAX_SPEED:
		flat = flat.normalized() * MAX_SPEED

	state.transform.origin = p
	state.linear_velocity = Vector3(flat.x, v.y, flat.z)


## The speed along the rail for the next step on a flat floor. `pull`: the tilt along the rail (-1..1 of full tilt);
## `tilt`: the whole board's (0..1); `leaning`: towards the other axis, for a turn.
func _govern(space: PhysicsDirectSpaceState3D, p: Vector3, speed: float, pull: float, tilt: float, leaning: bool,
		unit: float, dt: float) -> float:
	if tilt < LEVEL:
		return _stop_on_centre(space, p, speed, unit, dt)
	if leaning:
		return move_toward(speed, 0.0, COAST * unit * dt)
	var target := TOP_SPEED * unit * clampf(pull, -1.0, 1.0)
	var faster := absf(target) > absf(speed) and target * speed >= 0.0
	var most := (ACCEL if faster else BRAKE) * unit
	return speed + clampf((target - speed) * (ACCEL_EASE if faster else BRAKE_EASE), -most, most) * dt


## Levelled: the speed that brings it to a stop on a tile centre (see STOP_BRAKE).
func _stop_on_centre(space: PhysicsDirectSpaceState3D, p: Vector3, speed: float, unit: float, dt: float) -> float:
	var along := p.z if travel_z else p.x
	var nearest := _snap_z(along) if travel_z else _snap(along)
	if absf(speed) <= SETTLE_SPEED * unit:
		var off := nearest - along
		return signf(off) * minf(minf(SETTLE_SPEED * unit, sqrt(2.0 * STOP_BRAKE * unit * absf(off))), absf(off) / dt)
	var dir := signf(speed)
	var step := Vector3(0, 0, dir) if travel_z else Vector3(dir, 0, 0)
	var c := nearest if (nearest - along) * dir >= 0.0 else nearest + dir * grid
	var stop := NAN
	for k in 8:
		var at := Vector3(p.x, p.y, c) if travel_z else Vector3(c, p.y, p.z)
		if not _ray(space, at, Vector3.DOWN, height * 0.5 + 0.35 * size):
			break # a hole: stop before it
		stop = c
		var d := absf(c - along)
		if d > 1e-4 and speed * speed / (2.0 * d) <= STOP_BRAKE * unit:
			break
		if _ray(space, at, step, grid * 0.7):
			break # a wall straight after it
		c += dir * grid
	if is_nan(stop):
		return move_toward(speed, 0.0, 3.0 * STOP_BRAKE * unit * dt) # a hole right ahead: brake all out
	var d := absf(stop - along)
	if d < 1e-4:
		return 0.0
	return dir * maxf(0.0, absf(speed) - speed * speed / (2.0 * d) * dt)


## Whether the way `dir` is open from the tile centre at `along` on the current rail.
func _opens(space: PhysicsDirectSpaceState3D, p: Vector3, along: float, dir: Vector3) -> bool:
	var at := Vector3(p.x, p.y, along) if travel_z else Vector3(along, p.y, p.z)
	return not _ray(space, at, dir, grid * 0.7)


## The side-ramp guide (see guide()): cap the speed along it so it can still stop by the stop point, and at the
## stop point halt it there. Ends there, or once it has stopped or turned off on its own.
func _apply_guide(state: PhysicsDirectBodyState3D, p: Vector3, v: Vector3) -> void:
	if not _guiding:
		return
	var d := (_guide_stop - p).dot(_guide_dir)
	var along := Vector3(v.x, 0, v.z).dot(_guide_dir)
	if d <= 0.0:
		if along > 0.0:
			state.linear_velocity = v - _guide_dir * along
		state.transform.origin = p + _guide_dir * d # click back onto the stop point
		_guiding = false
	elif along <= 0.01 and Time.get_ticks_msec() - _guide_since > 200:
		_guiding = false
	else:
		var most := sqrt(2.0 * GUIDE_BRAKE * grid * d)
		if along > most:
			state.linear_velocity = v - _guide_dir * (along - most)


## One step of a launch: a fixed arc from where it took off to the landing tile.
func _fly(state: PhysicsDirectBodyState3D) -> void:
	_launch_t = minf(1.0, _launch_t + state.step / LAUNCH_DURATION)
	var p := _launch_from.lerp(_launch_to, _launch_t) + Vector3.UP * (_launch_peak * 4.0 * _launch_t * (1.0 - _launch_t))
	state.linear_velocity = (p - state.transform.origin) / state.step # so the jelly sways with the hop
	state.transform.origin = p
	if _launch_t >= 1.0:
		state.linear_velocity = Vector3.ZERO
		var dir := _launch_to - _launch_from
		travel_z = absf(dir.z) >= absf(dir.x)
		_end_launch.call_deferred()


func _end_launch() -> void:
	launching = false
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	custom_integrator = false
	linear_velocity = Vector3.ZERO


var _lock_x := false
var _lock_z := false

func _set_rail_lock(x: bool, z: bool) -> void:
	if x != _lock_x:
		_lock_x = x
		axis_lock_linear_x = x
	if z != _lock_z:
		_lock_z = z
		axis_lock_linear_z = z


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, dist: float) -> bool:
	return not _cast(space, from, dir, dist).is_empty()


## The floor within `dist` below `from` (its normal is the floor's slope), or empty over a hole.
func _floor_below(space: PhysicsDirectSpaceState3D, from: Vector3, dist: float) -> Dictionary:
	return _cast(space, from, Vector3.DOWN, dist)


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.exclude = [get_rid()]
	return space.intersect_ray(q)


func _snap(value: float) -> float:
	return roundf(value / grid) * grid


func _snap_z(z: float) -> float:
	return grid_z + roundf((z - grid_z) / grid) * grid
