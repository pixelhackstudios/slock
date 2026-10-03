extends Node3D
## A run of Slock: an endless climb through sections (section.gd), each a little higher, with smaller blocks
## and faster than the last. Built in code: lighting, the sections, Slock, the swurms, the tilt camera and the
## HUD. You start with 35 seconds: pellets add time and score, swurms leave their pen one at a time and steal a
## third of your time when they hit you, unless a power pellet is active: then they're scared and slow, and
## eating one gives time back. Eat every pellet (the gold ones down in the side room too) to open the gate, or find
## the side room's key; go through for a time bonus, and the climb ramp boosts you up into the next section. The
## run ends when time runs out, or you fall down a pit or off an edge.
## Slugs: click to aim (the game freezes; tilt picks a direction), click again to fire: it kills the first swurm or
## breaks the first inner wall in its way. Powerups float in each section and come back 10 s after being taken.
## Mouse (or left stick) tilts the board. Esc pauses, R restarts.

enum State { PLAYING, PAUSED, OVER }

const START_TIME := 35.0
const PELLET_TIME := 1.0          # seconds each pellet adds
const GOLD_TIME := 2.0            # ... each gold pellet (side rooms)
const CLOCK_TIME := 20.0          # ... the side room's clock
const POWER_TIME := 5.0           # ... each power pellet
const SWURM_TIME := 10.0          # ... each scared swurm eaten (plus any time it stole, back)
const PELLET_POINTS := 10
const GOLD_POINTS := 30
const CLOCK_POINTS := 250
const KEY_POINTS := 500
const POWER_POINTS := 100         # plus 10 per floor climbed
const SWURM_POINTS := 200         # doubles for each more eaten on the same power pellet, up to 1600
const FLOOR_POINTS := 250         # through a gate: this times the floor number
const PROGRESS_POINTS := 10       # per unit of your furthest progress up the course
const FALL_DISTANCE := 5.0        # this far below the maze floor counts as falling off (side rooms are 3 below)

const SECTIONS_AHEAD := 2         # sections built beyond the one Slock is in ...
const SECTIONS_BEHIND := 1        # ... and kept behind it

const SWURM_RELEASE_GAP := 4.0    # seconds between swurms leaving the pen
const SWURM_RESPAWN := 8.0        # seconds after being eaten until it crawls out again
const POWER_DURATION := 10.0      # seconds a power pellet lasts
const POWER_FLASH := 2.0          # scared swurms flash white for the last this many seconds
const HIT_REACH := 0.9            # Slock and a swurm head touch when this close on both axes (blocks)
const HIT_COOLDOWN := 1.0         # a swurm that just hit Slock only knocks it again for that long (no new ouch)

const START_SLUGS := 3            # and one more each gate after that
const STEEL_DURATION := 10.0      # Slock of Steel: break inner walls and swurms by pushing into them
const STEEL_WALL_POINTS := 20
const CLEAR_DOTS_FRACTION := 0.25 # clear-the-dots removes this much of what's left

const BOOST_ACCEL := 80.0         # the climb ramp's booster pushes this hard uphill ...
const BOOST_SPEED := 15.0         # ... up to this speed, then launches Slock off the top

var sections := {}                # index -> Section
var seed := 0                     # this run's layouts
var slock: Slock
var rig: TiltRig
var sounds: Sounds
var hud: Hud
var state := State.PLAYING
var now := 0.0                    # game clock, seconds
var power_until := 0.0
var time_left := START_TIME
var current := 0                  # the section Slock is in
var height := 0                   # floors climbed (gates passed)
var _hit_until := {}              # swurm -> game time its hit cooldown ends
var _bonus := 0                   # score from pellets, swurms and gates
var _progress := 0.0              # furthest Slock has got up the course
var _chain := 0                   # swurms eaten on the current power pellet
var _pellets_eaten := 0
var _swurms_eaten := 0
var _run_seconds := 0.0
var _released := {}               # sections whose swurms have been let out
var _sealed_up_to := -1           # sections whose exit has been walled up behind Slock
var slugs := START_SLUGS
var _slug_allowance := START_SLUGS # refilled to at each gate, one more each time
var _flying: Array[Slug] = []
var aiming := false               # slug aim mode: the game is frozen, tilt picks the direction, click fires
var _aim := Vector2i(0, 1)        # the direction picked (on the grid: +y is up the course)
var _aim_mark: MeshInstance3D     # translucent red block over what the slug would hit
var _steel_until := 0.0
var _run_started := 0             # msec, so the click that starts a run doesn't fire a slug


## How nasty section `i` is (see also MazeGen): everything ramps up and then plateaus.
static func time_bonus(i: int) -> float:
	return maxf(7.0, 18.0 - i * 0.5)


static func speed_of(i: int) -> float:
	return 1.0 + minf(0.6, i * 0.05) # Slock's gravity, in blocks: +5% a section, up to +60%


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # handles pause; the game itself stops while paused
	_setup_lighting()
	sounds = _game(Sounds.new())
	slock = _game(Slock.new())
	rig = TiltRig.new()
	rig.target = slock
	_game(rig)

	var level := LevelIndicator.new()
	level.rig = rig
	add_child(level)
	hud = Hud.new()
	add_child(hud)
	_aim_mark = MeshInstance3D.new()
	_aim_mark.mesh = BoxMesh.new()
	_aim_mark.mesh.material = Section._glass(Color(1.0, 0.08, 0.08, 0.45), Color(0.7, 0.0, 0.0), 0.2)
	_aim_mark.visible = false
	add_child(_aim_mark)

	_start_run()


## Adds a node that stops while the game is paused.
func _game(node: Node) -> Node:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)
	return node


func _start_run() -> void:
	for s in sections.values():
		s.queue_free()
	sections.clear()
	seed = randi_range(1, 1 << 28)
	_released.clear()
	_sealed_up_to = -1
	current = 0
	_stream_sections(true)
	var first: Section = sections[0]
	slock.set_size_immediate(first.tile)
	slock.set_grid(first.tile, first.row_z(0))
	slock.reset_to(first.start_position(slock.height))
	rig.zoom = 1.0
	rig.gravity_scale = slock.size * speed_of(0)
	rig.reset_trackball()
	rig.snap_to_target()
	rig.input_enabled = true
	time_left = START_TIME
	power_until = 0.0
	height = 0
	_hit_until.clear()
	_bonus = 0
	_progress = 0.0
	_chain = 0
	_pellets_eaten = 0
	_swurms_eaten = 0
	_run_seconds = 0.0
	slugs = START_SLUGS
	_slug_allowance = START_SLUGS
	for slug in _flying:
		slug.queue_free()
	_flying.clear()
	_set_aiming(false)
	_steel_until = 0.0
	slock.set_steel(false)
	_run_started = Time.get_ticks_msec()
	state = State.PLAYING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_overlay("")
	hud.clear_popups()
	hud.popup("GO!", Color.WHITE, 1.0)


func _end_run(title: String) -> void:
	state = State.OVER
	rig.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay(title, Hud.RED,
		"score %s   ·   floor %d   ·   %d pellets   ·   %d swurms eaten   ·   %ds" % [Hud._thousands(score()), height,
		_pellets_eaten, _swurms_eaten, roundi(_run_seconds)],
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
			_start_run()
		elif key.keycode == KEY_ESCAPE and state != State.OVER and not aiming:
			_set_paused(state == State.PLAYING)
	elif event is InputEventMouseButton and event.pressed and state == State.PLAYING:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # e.g. back after switching windows
		elif event.button_index == MOUSE_BUTTON_LEFT and Time.get_ticks_msec() - _run_started > 500:
			_on_fire_click()


# ------------------------------------------------------------------ sections

## Build the sections around the current one and drop the ones far behind. At the start of a run they're built
## straight away; after that, new ones (two ahead) build a little each frame so there's no hitch.
func _stream_sections(at_once := false) -> void:
	for i in range(maxi(0, current - SECTIONS_BEHIND), current + SECTIONS_AHEAD + 1):
		if not sections.has(i):
			var s := Section.new(i, seed)
			s.sliced = not at_once
			_game(s)
			sections[i] = s
	for i in sections.keys():
		if i < current - SECTIONS_BEHIND - 1:
			sections[i].queue_free()
			sections.erase(i)


## The section whose stretch of the course contains world `z`.
func _section_at(z: float) -> int:
	var i := 0
	while z < Section.near_edge_of(i + 1):
		i += 1
	return i


## Let a section's swurms out of the pen one at a time, Pac-Man style, the first time Slock arrives.
func _release_swurms(s: Section) -> void:
	if _released.has(s.index):
		return
	_released[s.index] = true
	for i in s.swurms.size():
		s.swurms[i].release_at(now + i * SWURM_RELEASE_GAP)


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if state == State.PAUSED:
		return
	if aiming:
		_update_aim()
		hud.show_slugs(slugs, true)
		return
	now += delta
	var mood := Swurm.Mood.NORMAL
	if now < power_until:
		var flashing := power_until - now < POWER_FLASH and fmod(now, 0.3) < 0.15
		mood = Swurm.Mood.FLASH if flashing else Swurm.Mood.SCARED
	for s in sections.values():
		for swurm in s.swurms:
			swurm.mood = mood
			swurm.tick(delta, now)

	var here: Section = sections[current]
	if state == State.PLAYING:
		time_left -= delta
		_run_seconds += delta
		if time_left <= 0.0:
			time_left = 0.0
			_end_run("OUT OF TIME")
	hud.show_status(score(), time_left, here.pellets_left(), maxf(0.0, power_until - now), height,
		Section.block_of(height))
	hud.show_slugs(slugs, false)
	hud.show_steel(maxf(0.0, _steel_until - now))


func _physics_process(delta: float) -> void:
	if state != State.PLAYING or aiming:
		return
	var p := slock.global_position
	_progress = maxf(_progress, -p.z)

	var now_in := _section_at(p.z)
	if now_in != current:
		current = now_in
		_stream_sections()
	var here: Section = sections[current]
	if not here.built:
		return # still building (only if Slock outran the streaming)
	slock.set_grid(here.tile, here.row_z(0))
	rig.gravity_scale = slock.size * speed_of(current) # gravity scales with the block, so speed only ramps
	_release_swurms(here)

	# Once Slock is fully out of the last section's exit, wall it up: no going back.
	if current > 0 and _sealed_up_to < current - 1 and p.z + slock.size * 0.5 < here.near_edge:
		_sealed_up_to = current - 1
		sections[current - 1].seal_exit()

	if p.y < here.floor_y - FALL_DISTANCE:
		_end_run("YOU SLID OFF THE EDGE")
		return
	_fly_slugs(delta)
	if slock.launching:
		return # nothing gets eaten mid-hop
	_climb_ramp(here, p)
	_side_ramp(here, p)
	_tick_steel(here, p)
	here.respawn_powerups(now, here.tile_under(p))

	var eaten := here.try_eat_pellet(p)
	match eaten:
		Section.Eaten.PELLET, Section.Eaten.GOLD:
			var gold := eaten == Section.Eaten.GOLD
			sounds.pellet()
			_pellets_eaten += 1
			_bonus += GOLD_POINTS if gold else PELLET_POINTS
			time_left += GOLD_TIME if gold else PELLET_TIME
			_check_gate(here)
		Section.Eaten.CLOCK:
			sounds.pellet()
			_bonus += CLOCK_POINTS
			time_left += CLOCK_TIME
			hud.popup("+%ds!" % CLOCK_TIME, Color(0.4, 0.9, 1.0), 1.4)
		Section.Eaten.KEY:
			sounds.pellet()
			_bonus += KEY_POINTS
			if not here.gate_open():
				here.open_gate()
			hud.popup("KEY!  GATE OPEN", Color(1.0, 0.4, 1.0), 1.6)
		Section.Eaten.STEEL, Section.Eaten.CLEAR_DOTS, Section.Eaten.CLOSE_TRAPS, Section.Eaten.REFILL_SLUGS, \
				Section.Eaten.EXTRA_SLUG:
			here.powerup_taken(now)
			_powerup(eaten, here, p)
		Section.Eaten.POWER:
			sounds.big_pop()
			_pellets_eaten += 1
			_bonus += POWER_POINTS + height * 10
			time_left += POWER_TIME
			power_until = now + POWER_DURATION
			_chain = 0
			hud.popup("POWER!   +%ds" % POWER_TIME, Color(1.0, 0.85, 0.2), 1.2)
			_check_gate(here)

	for swurm in here.swurms:
		if swurm.eaten:
			continue
		var d := p - swurm.head_position()
		var reach := HIT_REACH * here.tile
		if absf(d.x) >= reach or absf(d.y) >= slock.height or absf(d.z) >= reach:
			continue
		if now < _steel_until:
			_kill_swurm(swurm, "SMASHED!")
		elif now < power_until:
			_eat_swurm(swurm)
		else:
			_swurm_hit(swurm, p)

	if here.gate_open() and height <= here.index and here.tile_under(p) == here.exit_tile():
		_through_gate(here)


## The climb ramp's booster: heading uphill it speeds Slock up the ramp, and at the top launches it in a hop
## onto the 4th tile of the maze. (The first section's start corridor is flat: no booster.)
func _climb_ramp(here: Section, p: Vector3) -> void:
	if here.index == 0 or not here.on_ramp(p):
		return
	var uphill := slock.linear_velocity.dot(Vector3.FORWARD)
	if uphill <= 0.3:
		return
	if p.z <= here.ramp_top_z():
		slock.launch(here.tile_centre(here.landing_tile()), here.tile)
	else:
		slock.boost = Vector3.FORWARD * BOOST_ACCEL
		slock.boost_limit = BOOST_SPEED


## The side ramp: slide down and it brakes you to a stop just inside the side room; head back up and its
## booster speeds you up it and launches you onto the 4th tile into the maze.
func _side_ramp(here: Section, p: Vector3) -> void:
	if not here.on_side_ramp(p):
		return
	var up := here.side_uphill()
	var uphill := slock.linear_velocity.dot(up)
	if uphill > 0.3:
		if p.x * up.x >= here.side_top_x() * up.x:
			slock.launch(here.side_landing(), here.tile)
		else:
			slock.boost = up * BOOST_ACCEL
			slock.boost_limit = BOOST_SPEED
	elif uphill < -0.3:
		slock.guide(-up, here.side_stop())


func _check_gate(here: Section) -> void:
	if here.pellets_left() == 0 and not here.gate_open():
		here.open_gate()
		hud.popup("GATE OPEN!", Color(0.3, 1.0, 0.95), 1.5)


## Through a gate: a floor higher, a time bonus, and the blocks (and Slock) get smaller.
func _through_gate(here: Section) -> void:
	var i := here.index
	height = i + 1
	_bonus += FLOOR_POINTS * height
	time_left += time_bonus(i)
	_slug_allowance += 1 # your slugs back, plus one more
	slugs = _slug_allowance
	hud.popup("SLUGS x%d" % slugs, Color(1.0, 0.85, 0.3), 1.6)
	var next := Section.tile_of(i + 1)
	slock.shrink_to(minf(slock.size, next))
	rig.zoom = lerpf(1.0, next, 0.5)
	hud.popup("FLOOR %d   +%ds" % [height, time_bonus(i)], Color(0.3, 1.0, 0.95), 1.6)
	if Section.block_of(i + 1) < Section.block_of(i):
		hud.popup("BLOCK %d" % Section.block_of(i + 1), Color.WHITE, 1.6)


## Touched while scared: eaten.
func _eat_swurm(swurm: Swurm) -> void:
	_kill_swurm(swurm, "CHOMP!")


## A swurm eaten (or shot, or smashed): points double with each one in a row, up to 1600, and it gives back any
## time it stole.
func _kill_swurm(swurm: Swurm, shout: String) -> void:
	var points := SWURM_POINTS << mini(_chain, 3) # 200, 400, 800, 1600
	_chain += 1
	_swurms_eaten += 1
	_bonus += points
	var refund := swurm.stolen_time
	time_left += SWURM_TIME + refund
	swurm.get_eaten(now, SWURM_RESPAWN)
	var back := "   +%ds back" % roundi(refund) if refund > 0.05 else ""
	hud.popup("%s +%d   +%ds%s" % [shout, points, SWURM_TIME, back], Color(0.4, 0.6, 1.0), 1.2)


# ------------------------------------------------------------------ powerups and slugs

func _powerup(kind: Section.Eaten, here: Section, p: Vector3) -> void:
	match kind:
		Section.Eaten.STEEL:
			sounds.steel()
			_steel_until = now + STEEL_DURATION
			hud.popup("SLOCK OF STEEL!", Color(0.85, 0.88, 0.95), 1.4)
		Section.Eaten.CLEAR_DOTS:
			sounds.big_pop()
			hud.popup("-%d DOTS" % here.remove_pellets(CLEAR_DOTS_FRACTION), Color(0.4, 0.65, 1.0), 1.4)
			_check_gate(here)
		Section.Eaten.CLOSE_TRAPS:
			sounds.big_pop()
			var closed := here.close_traps(here.tile_under(p))
			hud.popup("TRAPS CLOSED" if closed > 0 else "NO TRAPS HERE", Color(0.4, 1.0, 0.45), 1.4)
			_check_gate(here)
		Section.Eaten.REFILL_SLUGS:
			sounds.slug_reload()
			slugs = maxi(slugs, _slug_allowance)
			hud.popup("SLUGS REFILLED  x%d" % slugs, Color(1.0, 0.85, 0.3), 1.4)
		Section.Eaten.EXTRA_SLUG:
			sounds.slug_click()
			slugs += 1
			hud.popup("+1 SLUG  x%d" % slugs, Color(1.0, 0.85, 0.3), 1.4)


## Slock of Steel: push (tilt) into an inner wall next to you and it breaks. The look blinks back to jelly through
## the last second so the end doesn't catch you out.
func _tick_steel(here: Section, p: Vector3) -> void:
	var left := _steel_until - now
	slock.set_steel(left > 0.0 and (left > 1.0 or fmod(left, 0.25) > 0.125))
	if left <= 0.0 or rig.tilt.length() < 0.25:
		return
	if here.blast_wall(here.tile_under(p) + _tilt_step()):
		_bonus += STEEL_WALL_POINTS


## The grid direction the board slopes down (N/E/S/W): the same gravity Slock feels.
func _tilt_step() -> Vector2i:
	var g := rig.gravity_dir()
	if absf(g.x) > absf(g.z):
		return Vector2i(1 if g.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if g.z < 0.0 else -1) # rows run up the course, along -Z


## First click: the game freezes in aim mode (no backing out: the slug is committed); tilting picks the direction
## and the one thing it would hit glows red. Second click fires.
func _on_fire_click() -> void:
	if aiming:
		_fire_slug()
	elif slugs <= 0:
		hud.popup("NO SLUG", Color.GRAY, 0.8)
	else:
		_set_aiming(true)
		_update_aim()


func _set_aiming(on: bool) -> void:
	aiming = on
	get_tree().paused = on
	rig.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_PAUSABLE # tilt still works
	_aim_mark.visible = false


func _update_aim() -> void:
	if rig.tilt.length() >= 0.25:
		_aim = _tilt_step()
	var target := _slug_target()
	_aim_mark.visible = not target.is_empty()
	if _aim_mark.visible:
		_aim_mark.position = target[0]
		_aim_mark.mesh.size = Vector3.ONE * target[1] * 1.08


## The first swurm or inner wall within the slug's range along the aim, walking the grid out from Slock's tile:
## [centre, size], or empty. Outer walls and a locked gate stop the search (they can't be shot).
func _slug_target() -> Array:
	var here: Section = sections[current]
	var from := here.tile_under(slock.global_position)
	for i in range(1, Slug.RANGE + 1):
		var t := from + _aim * i
		for swurm in here.swurms:
			if not swurm.eaten and here.tile_under(swurm.head_position()) == t:
				return [swurm.head_position(), here.tile]
		if here.tile_at(t.x, t.y) == Section.WALL:
			if here.is_inner_wall(t):
				return [here.tile_centre(t) + Vector3.UP * here.tile * 0.5, here.tile]
			return []
		if t == here.exit_tile() and not here.gate_open():
			return []
	return []


func _fire_slug() -> void:
	_set_aiming(false)
	slugs -= 1
	var dir := Vector3(_aim.x, 0, -_aim.y)
	var slug := Slug.fire(slock.global_position, dir, sections[current])
	_game(slug)
	_flying.append(slug)


func _fly_slugs(delta: float) -> void:
	for slug: Slug in _flying.duplicate():
		var hit: Slug.Hit = slug.step(delta)
		match hit:
			Slug.Hit.FLYING:
				continue
			Slug.Hit.SWURM:
				_kill_swurm(slug.swurm_hit, "ZAPPED!")
			Slug.Hit.WALL:
				hud.popup("BREACHED!", Color.WHITE, 1.2)
			Slug.Hit.MISS:
				hud.popup("MISS...", Color.GRAY, 0.8)
		_flying.erase(slug)
		slug.queue_free()


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
	# Reflections: a plain neutral grey all round (the background stays black), so polished things like Slock of
	# Steel have something to reflect without tinting the tiles.
	var grey := ProceduralSkyMaterial.new()
	for prop in ["sky_top_color", "sky_horizon_color", "ground_bottom_color", "ground_horizon_color"]:
		grey.set(prop, Color(0.3, 0.3, 0.3))
	grey.sun_angle_max = 0.0
	env.sky = Sky.new()
	env.sky.sky_material = grey
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.75
	add_child(sun)
