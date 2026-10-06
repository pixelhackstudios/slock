class_name Slock
extends RigidBody3D
## The sliding block: plain physics. The board's tilted gravity pushes it, floor friction is the only drag (walls have
## none), and walls stop it. A ramp booster can push it uphill and launch it in a hop. It's always one block across,
## shrinking smoothly when it passes into a section with smaller blocks. Its look and wobble are in jelly.gd.

const HEIGHT_RATIO := 1.1         # a hair taller than the walls (which are one block tall)
const SHRINK := 0.1               # hull undersize vs a tile: stops wedging, stays grid-true
const SHRINK_SPEED := 3.0         # block sizes per second, shrinking through a gate
const MAX_SPEED := 60.0           # safety limit only, well above what gravity reaches

const FRICTION := 0.058           # floor friction coefficient (0 = ice)
const HOLE_SNAP := 14.0           # how fast it lines up with a hole it's dropping into

const LAUNCH_DURATION := 0.55     # seconds in the air on a ramp launch
const GUIDE_BRAKE := 20.0         # blocks/s^2: how hard a ramp guide settles it toward its stop point

var size := 1.0                   # one grid block across
var height := HEIGHT_RATIO
var grid := 1.0                   # block size of the grid it's locked to
var grid_z := 0.0                 # the z of one of that grid's tile-centre rows
var grounded := false
var on_flat := false              # on a flat floor (not a ramp)
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
	physics_material_override.friction = 0.0 # floor friction is applied in _integrate_forces
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
## in the air; on landing it's stopped.
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
	var boosting := boost != Vector3.ZERO
	if boosting and Vector3(v.x, 0, v.z).dot(boost.normalized()) < boost_limit:
		v += boost * dt
	boost = Vector3.ZERO

	var below := _floor_below(space, p, height * 0.5 + 0.35 * size)
	grounded = not below.is_empty()
	if not grounded and _ray(space, p, Vector3.DOWN, height * 0.5 + 1.5 * size):
		# Only briefly airborne (a bump): floor is right below, so this isn't a hole. Keep its speed.
		state.linear_velocity = v
		return
	if not grounded:
		# Centre is over a hole (or past an edge): line up with that grid square and drop straight through it.
		var target := Vector3(_snap(p.x), p.y, _snap_z(p.z))
		var pull := (target - p) * HOLE_SNAP
		state.linear_velocity = Vector3(pull.x, v.y, pull.z)
		return

	var normal: Vector3 = below.normal
	on_flat = normal.y > 0.9999 and not boosting

	# Floor friction, against gravity's press on the floor; the tilted gravity itself is added by the physics step.
	var flat := Vector3(v.x, 0, v.z).move_toward(Vector3.ZERO, FRICTION * absf(g.dot(normal)) * dt)
	# Safety limit only (keeps fast falls from tunnelling); not part of the feel.
	if flat.length() > MAX_SPEED:
		flat = flat.normalized() * MAX_SPEED
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
		_end_launch.call_deferred()


func _end_launch() -> void:
	launching = false
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	custom_integrator = false
	linear_velocity = Vector3.ZERO


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
