class_name Slock
extends RigidBody3D
## The sliding block. Tilted gravity pushes; floor friction is the only drag (walls have none). It stays on
## tile-centre rails and turns Pac-Man style at centres. Ported from the Unity SlockController, minus ramps,
## launches and shrinking for now. Its look and wobble are in jelly.gd.

const SIZE := 1.0                 # one grid block
const HEIGHT := SIZE * 1.1        # a hair taller than the walls
const SHRINK := 0.1               # hull undersize vs a tile: stops wedging, stays grid-true
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

var grid := 1.0                   # block size of the grid it's locked to
var travel_z := true              # rail it's on: true = runs along Z (X locked), false = runs along X (Z locked)
var grounded := false


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

	var hull := CollisionShape3D.new()
	hull.shape = _rounded_box(SIZE * (1.0 - SHRINK), HEIGHT, 0.08)
	add_child(hull)

	var jelly := Jelly.new(Vector3(SIZE, HEIGHT, SIZE))
	jelly.body = self
	add_child(jelly)


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
	travel_z = true
	_set_rail_lock(false, false)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos))
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	global_position = pos
	reset_physics_interpolation()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var p := state.transform.origin
	var v := state.linear_velocity
	var g := state.total_gravity
	var dt := state.step
	var space := state.get_space_state()

	grounded = _ray(space, p, Vector3.DOWN, HEIGHT * 0.5 + 0.35 * SIZE)
	if not grounded and _ray(space, p, Vector3.DOWN, HEIGHT * 0.5 + 1.5 * SIZE):
		# Only briefly airborne (a bump): floor is right below, so this isn't a hole. Keep its speed and rail.
		_set_rail_lock(not travel_z, travel_z)
		return
	if not grounded:
		# Centre is over a hole (or past an edge): line up with that grid square and drop straight through it.
		_set_rail_lock(false, false)
		var target := Vector3(_snap(p.x), p.y, _snap(p.z))
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
	var along_centre := _snap(along)
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
		p.z = _snap(p.z)
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
