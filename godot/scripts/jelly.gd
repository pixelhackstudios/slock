class_name Jelly
extends Node3D
## Slock's look: the rounded jelly block with a darker core inside, wobbling like jelly. Visual only; the
## physics never changes. The top sways behind the bottom when the block speeds up, stops or turns, and the
## whole block squishes and springs back when it smacks into a wall. jelly.gdshader does the bending.

# Sway (top lags behind the bottom)
const SWAY_GAIN := 0.012          # sway per unit of acceleration
const SWAY_MAX := 0.32
const SWAY_STIFFNESS := 260.0     # spring stiffness: higher = faster wobble
const SWAY_DAMPING := 5.0         # lower = wobbles longer
# Squish (on impacts)
const SQUISH_GAIN := 0.05         # squish per unit of impact speed
const SQUISH_MAX := 0.32
const SQUISH_STIFFNESS := 380.0
const SQUISH_DAMPING := 7.0
const IMPACT_THRESHOLD := 1.5     # sudden speed change (per physics step) that counts as a smack

var body: RigidBody3D
var _material: ShaderMaterial
var _core: MeshInstance3D
var _last_vel := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_vel := Vector2.ZERO
var _squish := 0.0
var _squish_vel := 0.0
var _squish_axis := Vector3.UP


func _init(size: Vector3) -> void:
	scale = size
	var model: Node = load("res://models/SlockJelly.fbx").instantiate()
	var mesh: Mesh = (model.get_child(0) as MeshInstance3D).mesh
	model.free()

	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/jelly.gdshader")
	var jelly := MeshInstance3D.new()
	jelly.mesh = mesh
	jelly.material_override = _material
	jelly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(jelly)

	# A darker core you can see through the jelly, for depth.
	_core = MeshInstance3D.new()
	_core.mesh = mesh
	_core.scale = Vector3.ONE * 0.5
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.45, 0.0, 0.04)
	core_mat.roughness = 0.4
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.5, 0.0, 0.05)
	_core.material_override = core_mat
	add_child(_core)


## Squish along `normal` (world space) for an impact of `speed`.
func hit(normal: Vector3, speed: float) -> void:
	if speed < 0.6:
		return
	var local := global_basis.inverse() * normal
	_squish_axis = local.normalized() if local.length_squared() > 1e-4 else Vector3.UP
	_squish_vel += minf(speed * SQUISH_GAIN * 60.0, 12.0)


func _physics_process(dt: float) -> void:
	if body == null:
		return
	var v := body.linear_velocity
	var dv := v - _last_vel
	var accel := dv / dt
	_last_vel = v

	# A wall hit shows up as a sudden change in velocity: squish along it.
	if dv.length() > IMPACT_THRESHOLD:
		hit(dv, dv.length())

	# Sway: the top wants to lean against the acceleration (inertia), on a bouncy spring.
	var local_a := global_basis.inverse() * accel
	var target := (Vector2(-local_a.x, -local_a.z) * SWAY_GAIN).limit_length(SWAY_MAX)
	_sway_vel += (SWAY_STIFFNESS * (target - _sway) - SWAY_DAMPING * _sway_vel) * dt
	_sway = (_sway + _sway_vel * dt).limit_length(SWAY_MAX)

	_squish_vel += (-SQUISH_STIFFNESS * _squish - SQUISH_DAMPING * _squish_vel) * dt
	_squish = clampf(_squish + _squish_vel * dt, -SQUISH_MAX, SQUISH_MAX)

	_material.set_shader_parameter("sway", _sway)
	_material.set_shader_parameter("squish", _squish)
	_material.set_shader_parameter("squish_axis", _squish_axis)
	_core.position = Vector3(_sway.x, 0, _sway.y) * 0.3 # the core rides along, about a third as much
