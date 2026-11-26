class_name SlimeTrail
extends MultiMeshInstance3D
## The slime swurms leave behind them, for looks only. Each slide lays a flat smear on the floor, from where the head
## started to where it stopped, in the swurm's colour; it dries up from its ragged edges and is gone after LIFE
## seconds (slime.gdshader). One per section draws all of that section's slime in one batch, from a ring of smears
## that reuses the oldest first. It ages on the game clock (set_now), so it waits while the game is paused.

const LIFE := 2.5                 # seconds a smear lasts
const WIDTH := 0.7                # tiles across
const LIFT := 0.01                # tiles above the floor, so it doesn't flicker into it

var _tile := 1.0
var _births := PackedFloat32Array()
var _next := 0
var _material: ShaderMaterial


func _init(tile: float, capacity: int) -> void:
	_tile = tile
	top_level = true # smears are placed in world space
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = plane
	multimesh.instance_count = capacity
	_births.resize(capacity)
	for i in capacity:
		_births[i] = -1000.0 # long gone: nothing shows until it's laid
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		multimesh.set_instance_custom_data(i, Color(-1000.0, 0, 0, 0))
	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/slime.gdshader")
	_material.set_shader_parameter("life", LIFE)
	_material.render_priority = -1 # under the lanes and other see-through things
	material_override = _material


## A smear on the floor from `from` to `to` (floor points, world space) in `color`, laid at game time `now`.
func lay(from: Vector3, to: Vector3, color: Color, now: float) -> void:
	var run := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := run.length()
	if length < 0.01 * _tile:
		return
	var width := WIDTH * _tile
	var along := run / length
	var basis := Basis(Vector3.UP.cross(along) * width, Vector3.UP, along * (length + width))
	var centre := (from + to) * 0.5 + Vector3.UP * LIFT * _tile
	multimesh.set_instance_transform(_next, Transform3D(basis, centre))
	multimesh.set_instance_color(_next, color)
	multimesh.set_instance_custom_data(_next, Color(now, length / width, randf() * 100.0, 0.0))
	_births[_next] = now
	_next = (_next + 1) % _births.size()


## The game clock, which the smears age by.
func set_now(now: float) -> void:
	_material.set_shader_parameter("now", now)


## How many smears are still showing at game time `now`.
func live_count(now: float) -> int:
	var n := 0
	for b in _births:
		if b <= now and now - b < LIFE:
			n += 1
	return n
