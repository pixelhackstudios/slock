class_name Slock
extends RigidBody3D
## The sliding block. Tilted gravity pushes; floor friction is the only drag (walls have none). It stays on
## tile-centre rails and turns Pac-Man style at centres. It's always one block across, shrinking smoothly
## when it passes into a section with smaller blocks. A ramp booster can push it uphill and launch it in a hop.
## Ported from the Unity SlockController. Its look and wobble are in jelly.gd.

const HEIGHT_RATIO := 1.1         # a hair taller than the walls (which are one block tall)
const SHRINK := 0.1               # hull undersize vs a tile: stops wedging, stays grid-true
const SHRINK_SPEED := 3.0         # block sizes per second, shrinking through a gate
const FRICTION := 0.058           # floor friction coefficient (0 = ice)
const MAX_SPEED := 60.0           # safety limit only, well above what gravity reaches
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


func _init() -> void:
	mass = 1.0
	lock_rotation = true
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0 # no hidden drag: floor friction is the only resistance
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = FRICTION # combines as the lower of the two surfaces
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


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var p := state.transform.origin
	var v := state.linear_velocity
	var g := state.total_gravity
	var dt := state.step
	var space := state.get_space_state()
	if launching:
		_fly(state)
		return

	_apply_guide(state, p, v)
	p = state.transform.origin
	v = state.linear_velocity

	# Ramp booster (see main.gd): speeds it uphill, up to a limit.
	if boost != Vector3.ZERO and Vector3(v.x, 0, v.z).dot(boost.normalized()) < boost_limit:
		v += boost * dt
	boost = Vector3.ZERO

	grounded = _ray(space, p, Vector3.DOWN, height * 0.5 + 0.35 * size)
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

	# Rails: the centre is locked to the tile-centre line across the corridor. It turns Pac-Man style: when
	# the tilt favours the other axis and that way is open from the nearest tile centre, it slides to that
	# centre and switches rails.
	var want_z := travel_z
	if absf(g.z) > absf(g.x) * TURN_BIAS:
		want_z = true
	elif absf(g.x) > absf(g.z) * TURN_BIAS:
		want_z = false

	var along := p.z if travel_z else p.x
	var along_centre := _snap_z(along) if travel_z else _snap(along)
	if want_z != travel_z:
		var centre_pos := Vector3(p.x, p.y, along_centre) if travel_z else Vector3(along_centre, p.y, p.z)
		var dir := Vector3(0, 0, signf(g.z)) if want_z else Vector3(signf(g.x), 0, 0)
		if not _ray(space, centre_pos, dir, grid * 0.7):
			if absf(along_centre - along) < 0.02 * grid:
				# At the centre: switch rails. Momentum along the old rail stops at the corner.
				travel_z = want_z
				p = centre_pos
				v = Vector3(0, v.y, v.z) if travel_z else Vector3(v.x, v.y, 0)
			else:
				var pull := (along_centre - along) * TURN_SNAP
				v = Vector3(v.x, v.y, pull) if travel_z else Vector3(pull, v.y, v.z)

	# Hold the cross axis exactly on the tile-centre line.
	if travel_z:
		p.x = _snap(p.x)
		v.x = 0.0
	else:
		p.z = _snap_z(p.z)
		v.z = 0.0
	_set_rail_lock(travel_z, not travel_z)

	var flat := Vector3(v.x, 0, v.z)
	var sp := flat.length()

	# Creep (see CREEP_DAMPING): soft resistance that fades out as it speeds up.
	var fade := CREEP_FADE_SPEED * grid
	if sp > 1e-4 and sp < fade:
		flat -= flat * minf(1.0, CREEP_DAMPING * (1.0 - sp / fade) * dt)

	# Level means stop (see LEVEL_GRIP). "Level" is the whole board, so tilting toward a turn doesn't brake.
	var max_tilt := deg_to_rad(TiltRig.MAX_TILT)
	var tilt := clampf(Vector2(g.x, g.z).length() / maxf(1e-4, g.length() * sin(max_tilt)), 0.0, 1.0)
	var slack := 1.0 - tilt
	flat -= flat * minf(1.0, LEVEL_GRIP * slack * slack * dt)

	# Safety limit only (keeps fast falls from tunnelling); not part of the feel.
	if flat.length() > MAX_SPEED:
		flat = flat.normalized() * MAX_SPEED

	state.transform.origin = p
	state.linear_velocity = Vector3(flat.x, v.y, flat.z)


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
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


func _snap(value: float) -> float:
	return roundf(value / grid) * grid


func _snap_z(z: float) -> float:
	return grid_z + roundf((z - grid_z) / grid) * grid
