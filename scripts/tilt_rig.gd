class_name TiltRig
extends Camera3D
## "Tilting the world": mouse input picks a tilt. A single tilted gravity vector drives the physics and the
## camera presents that exact same rotation, so apparent downhill and simulated downhill cannot diverge.
## Mouse movement accumulates into a persistent 2D trackball (it stays where you leave it), a precision
## response shapes its magnitude (magnitude^2.2: very fine near level, full tilt at full displacement), and
## that commands the tilt. The left stick, when pushed, replaces the trackball.

const MAX_TILT := 25.0            # degrees of world/camera tilt at full input
const FALL_GRAVITY := 75.0        # strength of the tilted gravity
# Jitter filter, like a surgical robot's tremor filter: it only smooths frame-to-frame mouse jitter, so the
# board follows the hand with no lag you can feel (time constant in seconds; about a 6 Hz cutoff).
const JITTER_FILTER := 0.025
const TRACKBALL_PIXELS := 320.0   # mouse travel (px) from level to full tilt

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
var stick := Vector2.ZERO         # where the hand is: trackball or stick, -1..1, before the response curve
var _trackball := Vector2.ZERO
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


func reset_trackball() -> void:
	_trackball = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = event.screen_relative
		_trackball += Vector2(d.x, -d.y) / TRACKBALL_PIXELS
		_trackball = _trackball.limit_length(1.0)


func _process(delta: float) -> void:
	var want := _read_input()
	tilt = tilt.lerp(want, 1.0 - exp(-delta / JITTER_FILTER))
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


func _read_input() -> Vector2:
	if not input_enabled:
		stick = Vector2.ZERO
		return stick
	stick = _trackball
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length_squared() > 0.0004:
		stick = pad.limit_length(1.0)
	var mag := stick.length()
	return stick.normalized() * pow(mag, 2.2) if mag > 0.0 else Vector2.ZERO


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
