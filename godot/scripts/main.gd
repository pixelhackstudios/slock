extends Node3D
## Builds the test scene in code: lighting, one map section, Slock, the swurms and the tilt camera. Slock eats
## the pellets it slides over. Swurms leave their pen one at a time; touching one knocks Slock and it apart,
## unless a power pellet is active: then they're scared and slow, and touching one eats it.
## Mouse (or left stick) tilts the board. R restarts, Esc frees the mouse, click to grab it again.

const SWURM_COUNT := 4            # Pac-Man: 4 to start
const SWURM_SPEED := 15.0         # tiles/s
const SWURM_RELEASE_GAP := 4.0    # seconds between swurms leaving the pen
const SWURM_RESPAWN := 8.0        # seconds after being eaten until it crawls out again
const POWER_DURATION := 10.0      # seconds a power pellet lasts
const POWER_FLASH := 2.0          # scared swurms flash white for the last this many seconds
const HIT_REACH := 0.9            # Slock and a swurm head touch when this close on both axes
const HIT_COOLDOWN := 1.0         # a swurm that just hit Slock only knocks it again for that long (no new ouch)

var section: Section
var slock: Slock
var rig: TiltRig
var sounds: Sounds
var swurms: Array[Swurm] = []
var now := 0.0                    # game clock, seconds
var power_until := 0.0
var _hit_until := {}              # swurm -> game time its hit cooldown ends


func _ready() -> void:
	_setup_lighting()
	sounds = Sounds.new()
	add_child(sounds)

	section = Section.new()
	add_child(section)

	slock = Slock.new()
	add_child(slock)
	slock.reset_to(section.start_position(slock.HEIGHT))

	var homes := section.swurm_homes.duplicate()
	homes.shuffle()
	for i in SWURM_COUNT:
		var swurm := Swurm.new(section, homes[i % homes.size()])
		swurm.tiles_per_second = SWURM_SPEED
		add_child(swurm)
		swurms.append(swurm)
	_release_swurms()

	rig = TiltRig.new()
	rig.target = slock
	add_child(rig)
	rig.snap_to_target()

	var help := Label.new()
	help.text = "Mouse: tilt    R: restart    Esc: free mouse"
	help.position = Vector2(16, 12)
	add_child(help)

	var level := LevelIndicator.new()
	level.rig = rig
	add_child(level)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		slock.reset_to(section.start_position(slock.HEIGHT))
		rig.reset_trackball()
		section.reset_pellets()
		for swurm in swurms:
			swurm.reset()
		power_until = 0.0
		_hit_until.clear()
		_release_swurms()


## Let the swurms out of the pen one at a time, Pac-Man style.
func _release_swurms() -> void:
	for i in swurms.size():
		swurms[i].release_at(now + i * SWURM_RELEASE_GAP)


func _process(delta: float) -> void:
	now += delta
	var mood := Swurm.Mood.NORMAL
	if now < power_until:
		var flashing := power_until - now < POWER_FLASH and fmod(now, 0.3) < 0.15
		mood = Swurm.Mood.FLASH if flashing else Swurm.Mood.SCARED
	for swurm in swurms:
		swurm.mood = mood
		swurm.tick(delta, now)


func _physics_process(_delta: float) -> void:
	match section.try_eat_pellet(slock.global_position):
		Section.Eaten.PELLET:
			sounds.pellet()
		Section.Eaten.POWER:
			sounds.pellet()
			power_until = now + POWER_DURATION

	var p := slock.global_position
	for swurm in swurms:
		if swurm.eaten:
			continue
		var d := p - swurm.head_position()
		if absf(d.x) >= HIT_REACH or absf(d.z) >= HIT_REACH or absf(d.y) >= Slock.HEIGHT:
			continue
		if now < power_until:
			swurm.get_eaten(now, SWURM_RESPAWN)
		else:
			# A hit: Slock and the swurm are knocked ~3 tiles apart. Still touching inside the cooldown just
			# pushes them apart again.
			slock.bounce_back(swurm.head_position(), 3.0)
			swurm.knock_back(p, now, 3)
			if now >= _hit_until.get(swurm, 0.0):
				_hit_until[swurm] = now + HIT_COOLDOWN
				sounds.ouch()


func _setup_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.36, 0.36) # neutral grey fill
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.75
	add_child(sun)
