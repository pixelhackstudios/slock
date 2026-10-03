class_name Jelly
extends Node3D
## A rounded jelly block that wobbles like jelly. Visual only; the physics never changes. The top sways behind
## the bottom when the block speeds up, stops or turns, and the whole block squishes and springs back when it
## smacks into a wall. jelly_wobble.gdshaderinc does the bending. Every jelly is see-through with a thin outline.
##   SLOCK: red with a darker core inside; moves with `body` (a physics body).
##   SWURM: no core, recoloured with set_colors(); moves however its node is moved.

enum Look { SLOCK, SWURM }

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

const OUTLINE_COLOR := Color(0, 0, 0, 1.0)
const OUTLINE_PX := 1.0

var body: RigidBody3D
var wobbles := true
var _material: ShaderMaterial
var _outline: ShaderMaterial
var _core: MeshInstance3D
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_vel := Vector2.ZERO
var _squish := 0.0
var _squish_vel := 0.0
var _squish_axis := Vector3.UP


static var _mesh: Mesh

## The rounded block model (a 1-block cube), loaded once.
static func mesh() -> Mesh:
	if _mesh == null:
		var model: Node = load("res://models/SlockJelly.fbx").instantiate()
		_mesh = (model.get_child(0) as MeshInstance3D).mesh
		model.free()
	return _mesh


func _init(size: Vector3, look := Look.SLOCK) -> void:
	scale = size
	_material = ShaderMaterial.new()
	var jelly := MeshInstance3D.new()
	jelly.mesh = mesh()
	jelly.material_override = _material
	add_child(jelly)
	_material.shader = load("res://scripts/jelly.gdshader")
	_outline = ShaderMaterial.new()
	_outline.shader = load("res://scripts/jelly_outline.gdshader")
	_outline.set_shader_parameter("color", OUTLINE_COLOR)
	_outline.set_shader_parameter("width_px", OUTLINE_PX)
	_material.next_pass = _outline
	if look == Look.SWURM:
		return

	# A darker core you can see through the jelly, for depth.
	_core = MeshInstance3D.new()
	_core.mesh = mesh()
	_core.scale = Vector3.ONE * 0.5
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.45, 0.0, 0.04)
	core_mat.roughness = 0.4
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.5, 0.0, 0.05)
	_core.material_override = core_mat
	add_child(_core)


## The colour (alpha: how see-through) and glow.
func set_colors(albedo: Color, glow: Color) -> void:
	_material.set_shader_parameter("albedo", albedo)
	_material.set_shader_parameter("emission", glow)


## Squish along `normal` (world space) for an impact of `speed`.
func hit(normal: Vector3, speed: float) -> void:
	if speed < 0.6:
		return
	var local := global_basis.inverse() * normal
	_squish_axis = local.normalized() if local.length_squared() > 1e-4 else Vector3.UP
	_squish_vel += minf(speed * SQUISH_GAIN * 60.0, 12.0)


func _ready() -> void:
	_last_pos = global_position


func _physics_process(dt: float) -> void:
	if body != null and wobbles:
		_step(body.linear_velocity, dt)


func _process(dt: float) -> void:
	if body != null or not wobbles or dt <= 0.0:
		return
	var p := global_position
	_step((p - _last_pos) / dt, dt)
	_last_pos = p


func _step(v: Vector3, dt: float) -> void:
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

	for m in [_material, _outline]:
		if m != null:
			m.set_shader_parameter("sway", _sway)
			m.set_shader_parameter("squish", _squish)
			m.set_shader_parameter("squish_axis", _squish_axis)
	if _core != null:
		_core.position = Vector3(_sway.x, 0, _sway.y) * 0.3 # the core rides along, about a third as much
