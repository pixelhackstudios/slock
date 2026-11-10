class_name TiltRig
extends Camera3D
## "Tilting the world": mouse input picks a tilt. A single tilted gravity vector drives the physics and the
## camera presents that exact same rotation, so apparent downhill and simulated downhill cannot diverge.
## Whichever was used last tilts the board (using_pad): moving the mouse hands it to the mouse, pushing the left stick
## past STICK_TAKEOVER hands it to the stick.
##   Mouse: movement moves the board's tilt and it stays where you leave it (TRACKBALL_PIXELS from level to full).
##   Stick: it sets where the board is heading and the board eases there (STICK_RESPONSE), as Super Monkey Ball does,
##     so a stick let go doesn't snap the board level in the time it takes to spring back.

const MAX_TILT := 25.0            # degrees of world/camera tilt at full input
const FALL_GRAVITY := 75.0        # strength of the tilted gravity
const TRACKBALL_PIXELS := 320.0   # mouse travel (px) from level to full tilt
const STICK_TAKEOVER := 0.24      # of the stick's travel (Xbox's standard dead zone): a push past this hands the
                                  # tilt to the stick; a thumb resting on it doesn't
const STICK_RESPONSE := 0.075     # s: the board's time constant easing to where the stick puts it (Super Monkey
                                  # Ball's stage moves 20% of the way each 60 fps frame, which is 75 ms)

var target: Node3D
var yaw := 28.0
var pitch := 48.0
var distance := 20.0
var follow_smoothing := 0.18
var look_ahead := 3.0
var zoom := 1.0                   # distance multiplier, eased in, so the camera closes in as blocks shrink
var _zoom_now := 1.0
var input_enabled := true        # off: the board eases back to level (paused, round over)
var gravity_scale := 1.0          # block size times the section's speed ramp (1 on the first section)

var tilt := Vector2.ZERO          # current tilt, each axis -1..1 (x = screen right, y = screen up)
var hand := Vector2.ZERO          # where the hand has the board, -1..1: the mouse's or the stick's (the dial shows)
var using_pad := false            # the stick was used last, not the mouse (it has the tilt, and the hints follow it)
var _mouse := Vector2.ZERO        # where the mouse has put the board (it stays there between moves)
var _pivot := Vector3.ZERO
var _pivot_vel := Vector3.ZERO


func _ready() -> void:
	fov = 40.0
	near = 0.3
	far = 250.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # moved every frame here, not in physics
	current = true


func snap_to_target() -> void:
	_pivot = target.global_position + Vector3(0, 0, -look_ahead)
	_pivot_vel = Vector3.ZERO
	tilt = Vector2.ZERO
	_zoom_now = zoom


func reset_mouse() -> void:
	_mouse = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = event.screen_relative
		if using_pad:
			using_pad = false # the mouse takes over, from level
			_mouse = Vector2.ZERO
		_mouse = (_mouse + Vector2(d.x, -d.y) / TRACKBALL_PIXELS).limit_length(1.0)


func _process(delta: float) -> void:
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length() > STICK_TAKEOVER:
		using_pad = true # pushing the stick hands it the board

	if not input_enabled:
		hand = Vector2.ZERO
		tilt = Vector2.ZERO
	elif using_pad:
		hand = pad.limit_length(1.0)
		tilt = tilt.lerp(hand, 1.0 - exp(-delta / STICK_RESPONSE)) # eases there, like Super Monkey Ball
	else:
		hand = _mouse
		tilt = hand
	# One world, one downhill direction: the force field and the visible tilt are the same rotation.
	var space := get_world_3d().space
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, gravity_dir())
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, FALL_GRAVITY * gravity_scale)

	if target == null:
		return
	var goal := target.get_global_transform_interpolated().origin + Vector3(0, 0, -look_ahead)
	_pivot = _follow(goal, delta)
	var world_tilt := Quaternion(Vector3.DOWN, gravity_dir())
	var rot := Basis(world_tilt) * _base_rot()
	_zoom_now = lerpf(_zoom_now, zoom, 1.0 - exp(-2.0 * delta))
	global_transform = Transform3D(rot, _pivot + rot * Vector3(0, 0, distance * _zoom_now))


## The camera's untilted orientation: looking down at `pitch`, turned by `yaw` (to the right).
func _base_rot() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(-yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch))


## World gravity direction for the current tilt. The push goes the way the input points on screen: the camera
## looks down at `pitch`, so the floor's depth axis is foreshortened by sin(pitch), and undoing that makes the
## on-screen corridors and diagonals line up with the mouse. Tilt amount is the same in every direction.
func gravity_dir() -> Vector3:
	var mag := minf(1.0, tilt.length())
	if mag < 1e-5:
		return Vector3.DOWN
	var rot := _base_rot()
	var right := _flat(rot.x)
	var fwd := _flat(-rot.z)
	var foreshorten := maxf(0.2, sin(deg_to_rad(pitch)))
	var dir := (right * tilt.x + fwd * (tilt.y / foreshorten)).normalized()
	return (Vector3.DOWN + dir * tan(mag * deg_to_rad(MAX_TILT))).normalized()


## Where a flat world direction points on screen, the way the tilt aims (x right, y up): the inverse of
## gravity_dir's mapping, so a tilt pointing straight down an on-screen corridor points along it here too.
func on_screen(w: Vector3) -> Vector2:
	var rot := _base_rot()
	var foreshorten := maxf(0.2, sin(deg_to_rad(pitch)))
	return Vector2(w.dot(_flat(rot.x)), w.dot(_flat(-rot.z)) * foreshorten)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z).normalized()


# A critically damped spring (like Unity's SmoothDamp), for the camera follow.
func _follow(goal: Vector3, dt: float) -> Vector3:
	var omega := 2.0 / follow_smoothing
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := _pivot - goal
	var temp := (_pivot_vel + omega * change) * dt
	_pivot_vel = (_pivot_vel - omega * temp) * e
	return goal + (change + temp) * e
