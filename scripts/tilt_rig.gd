class_name TiltRig
extends Camera3D
## "Tilting the world": mouse input picks a tilt. A single tilted gravity vector drives the physics and the
## camera presents that exact same rotation, so apparent downhill and simulated downhill cannot diverge.
## Whichever was used last tilts the board (using_pad): moving the mouse hands it to the mouse, pushing the left stick
## past STICK_TAKEOVER hands it to the stick.
##   Mouse: movement moves the board's tilt and it stays where you leave it (TRACKBALL_PIXELS from level to full).
##   Stick: it sets where the board is heading and the board eases there (STICK_RESPONSE), as Super Monkey Ball does,
##     so a stick let go doesn't snap the board level in the time it takes to spring back.
## Brake: the right trigger, analog, is Slock's brake (see slock.gd): a light squeeze slows it, a full pull holds it.
##   W is a full pull while it's held.
## Peek: the right stick slides the camera's view across the maze, up to PEEK_REACH blocks, and it eases back to Slock
## when let go. Holding Space does the same with the mouse: it slides the view (TRACKBALL_PIXELS for the full reach)
## and leaves the board tilted where it was until Space is let go. Camera only: the tilt and gravity don't change,
## and the game keeps running.

const MAX_TILT := 25.0            # degrees of world/camera tilt at full input
const FALL_GRAVITY := 75.0        # strength of the tilted gravity
const TRACKBALL_PIXELS := 320.0   # mouse travel (px) from level to full tilt
const STICK_TAKEOVER := 0.24      # of the stick's travel (Xbox's standard dead zone): a push past this hands the
                                  # tilt to the stick; a thumb resting on it doesn't
const STICK_RESPONSE := 0.075     # s: the board's time constant easing to where the stick puts it (Super Monkey
                                  # Ball's stage moves 20% of the way each 60 fps frame, which is 75 ms)
const PEEK_REACH := 8.0           # blocks the camera's view slides at full push of the right stick
const BRAKE_DEAD := 0.05          # of the right trigger's travel ignored
const PEEK_DEAD := 0.2            # of the right stick's travel ignored, so a resting thumb doesn't drift the view

var target: Slock
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
var _mouse_peek := Vector2.ZERO   # where the mouse has slid the view while Space is held, -1..1
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
		if Input.is_key_pressed(KEY_SPACE):
			_mouse_peek = (_mouse_peek + Vector2(d.x, -d.y) / TRACKBALL_PIXELS).limit_length(1.0)
			return # looking, not tilting
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
	var trigger := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var squeeze := clampf((trigger - BRAKE_DEAD) / (1.0 - BRAKE_DEAD), 0.0, 1.0)
	target.brake = (1.0 if Input.is_key_pressed(KEY_W) else squeeze) if input_enabled else 0.0
	if not input_enabled or not Input.is_key_pressed(KEY_SPACE):
		_mouse_peek = Vector2.ZERO # let go: the view eases back to Slock
	var goal := target.get_global_transform_interpolated().origin + Vector3(0, 0, -look_ahead) + _peek()
	_pivot = _follow(goal, delta)
	var world_tilt := Quaternion(Vector3.DOWN, gravity_dir())
	var rot := Basis(world_tilt) * _base_rot()
	_zoom_now = lerpf(_zoom_now, zoom, 1.0 - exp(-2.0 * delta))
	global_transform = Transform3D(rot, _pivot + rot * Vector3(0, 0, distance * _zoom_now))


## Where the right stick (or the mouse, with Space held) has the camera looking, away from Slock (world space): along
## the screen's right and up, as far as the push, past the stick's dead zone; whichever pushes further. Nothing while
## input is off (paused, round over).
func _peek() -> Vector3:
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var push := clampf((stick.length() - PEEK_DEAD) / (1.0 - PEEK_DEAD), 0.0, 1.0)
	var look := stick.normalized() * push if push > 0.0 else Vector2.ZERO
	if _mouse_peek.length() > look.length():
		look = _mouse_peek
	if not input_enabled or look == Vector2.ZERO:
		return Vector3.ZERO
	var rot := _base_rot()
	return (_flat(rot.x) * look.x + _flat(-rot.z) * look.y) * PEEK_REACH * target.size


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
