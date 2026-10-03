extends Node3D
## One round of Slock on the hand-drawn section. Built in code: lighting, the section, Slock, the swurms, the tilt
## camera and the HUD. You start with 35 seconds: pellets add time and score, swurms leave their pen one at a
## time and steal a third of your time when they hit you, unless a power pellet is active: then they're scared
## and slow, and eating one gives time back. Eat every pellet to open the gate, then reach the exit.
## Mouse (or left stick) tilts the board. Esc pauses, R restarts.

enum State { PLAYING, PAUSED, OVER }

const START_TIME := 35.0
const PELLET_TIME := 1.0          # seconds each pellet adds
const POWER_TIME := 5.0           # ... each power pellet
const SWURM_TIME := 10.0          # ... each scared swurm eaten (plus any time it stole, back)
const PELLET_POINTS := 10
const POWER_POINTS := 100
const SWURM_POINTS := 200         # doubles for each more eaten on the same power pellet, up to 1600
const CLEAR_POINTS := 250         # reaching the exit
const PROGRESS_POINTS := 10       # per block of your furthest progress up the course

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
var hud: Hud
var swurms: Array[Swurm] = []
var state := State.PLAYING
var now := 0.0                    # game clock, seconds
var power_until := 0.0
var time_left := START_TIME
var _hit_until := {}              # swurm -> game time its hit cooldown ends
var _bonus := 0                   # score from pellets, swurms and the exit
var _progress := 0.0              # furthest Slock has got up the course (blocks)
var _chain := 0                   # swurms eaten on the current power pellet
var _pellets_eaten := 0
var _swurms_eaten := 0
var _run_seconds := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # handles pause; the game itself stops while paused
	_setup_lighting()
	sounds = _game(Sounds.new())
	section = _game(Section.new())
	slock = _game(Slock.new())

	var homes := section.swurm_homes.duplicate()
	homes.shuffle()
	for i in SWURM_COUNT:
		var swurm := Swurm.new(section, homes[i % homes.size()])
		swurm.tiles_per_second = SWURM_SPEED
		swurms.append(_game(swurm))

	rig = TiltRig.new()
	rig.target = slock
	_game(rig)

	var level := LevelIndicator.new()
	level.rig = rig
	add_child(level)
	hud = Hud.new()
	add_child(hud)

	_start_round()


## Adds a node that stops while the game is paused.
func _game(node: Node) -> Node:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)
	return node


func _start_round() -> void:
	section.reset()
	slock.reset_to(section.start_position(slock.HEIGHT))
	for swurm in swurms:
		swurm.reset()
	_release_swurms()
	rig.reset_trackball()
	rig.snap_to_target()
	rig.input_enabled = true
	time_left = START_TIME
	power_until = 0.0
	_hit_until.clear()
	_bonus = 0
	_progress = 0.0
	_chain = 0
	_pellets_eaten = 0
	_swurms_eaten = 0
	_run_seconds = 0.0
	state = State.PLAYING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_overlay("")
	hud.clear_popups()
	hud.popup("GO!", Color.WHITE, 1.0)


func _end_round(title: String, title_color: Color) -> void:
	state = State.OVER
	rig.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay(title, title_color,
		"score %s   ·   %d pellets   ·   %d swurms eaten   ·   %ds" % [Hud._thousands(score()), _pellets_eaten,
		_swurms_eaten, roundi(_run_seconds)],
		"R or Enter to play again")


func _set_paused(paused: bool) -> void:
	state = State.PAUSED if paused else State.PLAYING
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	hud.show_overlay("PAUSED" if paused else "", Color.WHITE, "", "Esc to resume    R to restart")


func score() -> int:
	return int(_progress * PROGRESS_POINTS) + _bonus


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_R or (state == State.OVER and key.keycode in [KEY_ENTER, KEY_KP_ENTER]):
			_start_round()
		elif key.keycode == KEY_ESCAPE and state != State.OVER:
			_set_paused(state == State.PLAYING)
	elif event is InputEventMouseButton and event.pressed and state == State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # e.g. back after switching windows


## Let the swurms out of the pen one at a time, Pac-Man style.
func _release_swurms() -> void:
	for i in swurms.size():
		swurms[i].release_at(now + i * SWURM_RELEASE_GAP)


func _process(delta: float) -> void:
	if state == State.PAUSED:
		return
	now += delta
	var mood := Swurm.Mood.NORMAL
	if now < power_until:
		var flashing := power_until - now < POWER_FLASH and fmod(now, 0.3) < 0.15
		mood = Swurm.Mood.FLASH if flashing else Swurm.Mood.SCARED
	for swurm in swurms:
		swurm.mood = mood
		swurm.tick(delta, now)

	if state == State.PLAYING:
		time_left -= delta
		_run_seconds += delta
		if time_left <= 0.0:
			time_left = 0.0
			_end_round("OUT OF TIME", Hud.RED)
	hud.show_status(score(), time_left, section.pellets.size(), maxf(0.0, power_until - now))


func _physics_process(_delta: float) -> void:
	if state != State.PLAYING:
		return
	var p := slock.global_position
	_progress = maxf(_progress, -p.z / Section.TILE)

	match section.try_eat_pellet(p):
		Section.Eaten.PELLET:
			sounds.pellet()
			_pellets_eaten += 1
			_bonus += PELLET_POINTS
			time_left += PELLET_TIME
			_check_gate()
		Section.Eaten.POWER:
			sounds.pellet()
			_pellets_eaten += 1
			_bonus += POWER_POINTS
			time_left += POWER_TIME
			power_until = now + POWER_DURATION
			_chain = 0
			hud.popup("POWER!   +%ds" % POWER_TIME, Color(1.0, 0.85, 0.2), 1.2)
			_check_gate()

	for swurm in swurms:
		if swurm.eaten:
			continue
		var d := p - swurm.head_position()
		if absf(d.x) >= HIT_REACH or absf(d.z) >= HIT_REACH or absf(d.y) >= Slock.HEIGHT:
			continue
		if now < power_until:
			_eat_swurm(swurm)
		else:
			_swurm_hit(swurm, p)

	if section.gate_open() and section.tile_under(p) == section.exit_tile():
		_bonus += CLEAR_POINTS
		_end_round("SECTION CLEARED", Hud.CYAN)


func _check_gate() -> void:
	if section.pellets.is_empty() and not section.gate_open():
		section.open_gate()
		hud.popup("GATE OPEN!", Color(0.3, 1.0, 0.95), 1.5)


## Touched while scared: eaten. Points double with each one on the same power pellet, and it gives back any
## time it stole.
func _eat_swurm(swurm: Swurm) -> void:
	var points := SWURM_POINTS << mini(_chain, 3) # 200, 400, 800, 1600
	_chain += 1
	_swurms_eaten += 1
	_bonus += points
	var refund := swurm.stolen_time
	time_left += SWURM_TIME + refund
	swurm.get_eaten(now, SWURM_RESPAWN)
	var back := "   +%ds back" % roundi(refund) if refund > 0.05 else ""
	hud.popup("CHOMP! +%d   +%ds%s" % [points, SWURM_TIME, back], Color(0.4, 0.6, 1.0), 1.2)


## A hit: Slock and the swurm are knocked ~3 tiles apart, and it steals a third of your time. Still touching
## inside the cooldown just pushes them apart again.
func _swurm_hit(swurm: Swurm, p: Vector3) -> void:
	slock.bounce_back(swurm.head_position(), 3.0)
	swurm.knock_back(p, now, 3)
	if now < _hit_until.get(swurm, 0.0):
		return
	_hit_until[swurm] = now + HIT_COOLDOWN
	sounds.ouch()
	var stolen := time_left / 3.0
	time_left -= stolen
	swurm.stolen_time += stolen
	hud.flash()
	hud.popup("-%ds" % roundi(stolen), Color(0.5, 1.0, 0.2), 1.0)


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
