class_name BlockBurst
extends Node3D
## A wall block pulverised, for looks only (the wall is already gone from the maze): a fountain of small chips in the
## wall's white and grey, with dust and a few sparks off its glowing pipe. The chips shrink as they fly and vanish as
## they land (no sitting on the floor). One of seven variations at random, never the same twice running (like the pellet pops), each with a little
## random spin, size and speed of its own.
##   CLASSIC   a fountain straight up
##   GEYSER    a narrower, faster column that goes much higher
##   SPRAY     wider and lower, landing in a broad ring
##   UPRIGHT   a slightly tighter fountain straight up
##   TWIN      two fountains leaning apart in a V
##   PULSE     three quick spurts, PULSE_GAP apart
##   HEAVY     fewer, bigger chunks thrown lower, with more dust

enum Kind { CLASSIC, GEYSER, SPRAY, UPRIGHT, TWIN, PULSE, HEAVY }

const LIFE := 1.8                 # seconds until it's all gone and the node frees itself
const WHITE := Color(0.78, 0.78, 0.76) # the wall's cap, a shade darker so it reads against the walls
const GREY := Color(0.28, 0.29, 0.32)  # its band
const DUST := Color(0.48, 0.46, 0.44)
const GLOW := Color(1.0, 0.72, 0.15)   # its pipe
const GRAVITY := 26.0             # blocks/s² on the chips
const TWIN_LEAN := 22.0           # degrees: each of TWIN's fountains
const PULSE_GAP := 0.1            # seconds between PULSE's spurts

static var _last := -1
static var _puff: Texture2D       # a soft round dust puff, made once

var kind: Kind
var _s := 1.0                     # block size, with this burst's random size on top
var _speed := 1.0                 # this burst's random speed


## A burst for the wall block standing on the floor at `at` (its floor centre), `size` across.
static func spawn(parent: Node, at: Vector3, size: float) -> BlockBurst:
	var b := BlockBurst.new()
	b.kind = _pick(Kind.size())
	b.position = at
	b.rotation.y = randf() * TAU # also which way TWIN leans
	b._s = size * randf_range(0.85, 1.15)
	b._speed = randf_range(0.85, 1.2)
	parent.add_child(b)
	return b


## One of `n`, never the last one picked.
static func _pick(n: int) -> int:
	var k := randi() % n if _last < 0 else randi() % (n - 1)
	if _last >= 0 and k >= _last:
		k += 1
	_last = k
	return k


func _ready() -> void:
	get_tree().create_timer(LIFE, false).timeout.connect(queue_free) # waits while the game is paused
	_floor()
	match kind:
		Kind.CLASSIC:
			_fountain(Vector3.UP, 25.0, 6.0, 9.0)
		Kind.GEYSER:
			_fountain(Vector3.UP, 10.0, 9.0, 12.5, 70, 1.0, 10)
		Kind.SPRAY:
			_fountain(Vector3.UP, 45.0, 4.0, 6.5, 80)
		Kind.UPRIGHT:
			_fountain(Vector3.UP, 20.0, 6.0, 9.0)
		Kind.TWIN:
			_fountain(_tipped(TWIN_LEAN), 15.0, 6.0, 9.0, 40, 1.0, 7)
			_fountain(_tipped(-TWIN_LEAN), 15.0, 6.0, 9.0, 40, 1.0, 7)
		Kind.PULSE:
			for i in 3:
				if i > 0:
					await get_tree().create_timer(PULSE_GAP, false).timeout
				_fountain(Vector3.UP, 20.0, 6.0, 9.0, 28, 1.0, 5)
		Kind.HEAVY:
			_fountain(Vector3.UP, 30.0, 4.0, 6.5, 35, 1.8, 22)


## Straight up, tipped `degrees` over (which way depends on this burst's random turn).
func _tipped(degrees: float) -> Vector3:
	return Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(degrees))


## One fountain heading `dir` give or take `spread`°, at `slow`..`fast` blocks/s: `chips` chips (`big` scales them),
## `dust` puffs, and sparks.
func _fountain(dir: Vector3, spread: float, slow: float, fast: float, chips := 70, big := 1.0, dust := 12) -> void:
	_chips(chips, dir, spread, slow, fast, big)
	_dust(dust, dir, spread * 2.4)
	_sparks(chips / 7, dir, spread * 1.2)


## Something for the chips to land on: the floor, under the burst.
func _floor() -> void:
	var floor_box := GPUParticlesCollisionBox3D.new()
	floor_box.size = Vector3(8.0, 1.0, 8.0) * _s
	floor_box.position = Vector3(0, -0.5, 0) * _s
	add_child(floor_box)


## Small chips of wall, mostly grey, some white, from the block heading `dir` give or take `spread`° at `slow`..`fast`
## blocks/s. They shrink as they fly and vanish the moment they land.
func _chips(amount: int, dir: Vector3, spread: float, slow: float, fast: float, big: float) -> void:
	var m := _motion(Vector3(0.35, 0.3, 0.35), dir, spread, slow, fast, Vector3.DOWN * GRAVITY)
	m.scale_min = 0.5 * big
	m.scale_max = 1.6 * big
	m.scale_curve = _curve([Vector2(0, 1), Vector2(0.3, 1), Vector2(0.75, 0.25), Vector2(1, 0)]) # small by landing
	m.color_initial_ramp = _ramp(GREY, WHITE)
	m.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.8
	var chip := BoxMesh.new()
	chip.size = Vector3.ONE * 0.09 * _s
	chip.material = look
	var p := _emitter(amount, 1.2, Vector3(0, 0.6, 0), m, chip)
	p.collision_base_size = 0.09 * big * _s


## A cloud of soft dust puffs that swell and fade.
func _dust(amount: int, dir: Vector3, spread: float) -> void:
	var m := _motion(Vector3(0.4, 0.4, 0.4), dir, spread, 1.0, 2.0, Vector3.UP * 0.6)
	m.damping_min = 2.0 * _s
	m.damping_max = 3.5 * _s
	m.scale_min = 0.7
	m.scale_max = 1.3
	m.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.8)])
	var fade := Gradient.new()
	fade.set_color(0, Color(DUST, 0.7))
	fade.set_color(1, Color(DUST, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = _puff_texture()
	look.roughness = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.55 * _s
	quad.material = look
	_emitter(amount, 1.4, Vector3(0, 0.5, 0), m, quad)


## A few glowing sparks off the pipe, round the band's height.
func _sparks(amount: int, dir: Vector3, spread: float) -> void:
	var m := _motion(Vector3(0.45, 0.05, 0.45), dir, spread, 4.0, 7.0, Vector3.DOWN * GRAVITY * 0.6)
	m.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = GLOW
	var spark := BoxMesh.new()
	spark.size = Vector3.ONE * 0.05 * _s
	spark.material = look
	_emitter(amount, 0.6, Vector3(0, 0.45, 0), m, spark)


## How a layer's particles start and move: from a box with `half` extents (blocks), heading `dir` give or take
## `spread`°, at `slow`..`fast` blocks/s, pulled by `gravity` (blocks/s²), all scaled to this burst.
func _motion(half: Vector3, dir: Vector3, spread: float, slow: float, fast: float, gravity: Vector3) \
		-> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = half * _s
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = slow * _s * _speed
	m.initial_velocity_max = fast * _s * _speed
	m.gravity = gravity * _s
	return m


## A one-shot layer of `amount` particles living `life` s, from `centre` (blocks, above the floor centre).
func _emitter(amount: int, life: float, centre: Vector3, motion: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.process_material = motion
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = centre * _s
	p.visibility_aabb = AABB(Vector3(-4, -1, -4) * _s, Vector3(8, 9, 8) * _s)
	add_child(p)
	p.emitting = true
	return p


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for pt: Vector2 in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


## From `a` to `b`, mostly `a` (chips come out mostly the first colour, a few the second).
static func _ramp(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	g.add_point(0.6, a)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _puff_texture() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_puff = t
	return _puff
