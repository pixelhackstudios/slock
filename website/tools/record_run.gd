extends SceneTree
## Records a run of the real game for the website's film, played by an autopilot: it eats its way round the first
## section, fetches the key from the side room, goes through the gate and up the ramp into the next section. Same
## course as the site's (seed 20261005). Godot's movie maker writes the video, sound and all:
##   godot --path . --write-movie run.avi --fixed-fps 30 --script website/tools/record_run.gd
## then encode it for the web (see website/README.md).

const SEED := 20261005
const LENGTH := 40.0              # seconds of play recorded
const HUNT := 8.0                 # seconds of eating before it goes for the key

var main: Node


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_start.call_deferred()


func _start() -> void:
	for i in 3:
		await process_frame
	# The site's course instead of a random one.
	for s in main.sections.values():
		s.free()
	main.sections.clear()
	main.seed = SEED
	seed(SEED)
	main._stream_sections(true)
	var first: Section = main.sections[0]
	main.slock.set_size_immediate(first.tile)
	main.slock.set_grid(first.tile, first.row_z(0))
	main.slock.reset_to(first.start_position(main.slock.height))
	main.rig.snap_to_target()
	main._begin()
	var pilot := Pilot.new()
	pilot.main = main
	pilot.process_priority = -100 # before the tilt rig reads its input
	root.add_child(pilot)


class Pilot extends Node:
	var main: Node
	var path: Array[Vector2i] = []
	var replan_at := 0.0
	var rest_until := 0.0
	var next_rest := 7.0
	var _said := -1                 # the last second it reported progress

	func _process(_delta: float) -> void:
		var now: float = main.now
		if now > LENGTH or main.state != 1:
			get_tree().quit()
			return
		var rig: TiltRig = main.rig
		rig._trackball = _stick(now)
		if int(now) != _said and int(now) % 4 == 0:
			_said = int(now)
			print("%2ds  section %d  lives %d  score %d" % [_said, main.current, main.lives, main.score()])

	func _stick(now: float) -> Vector2:
		var slock: Slock = main.slock
		if slock.launching:
			return Vector2.ZERO
		var here: Section = main.sections[main.current]
		var at := here.tile_under(slock.global_position)
		var goal := _goal(here, now)
		if goal == "exit" and at == here.exit_tile():
			return _toward(Vector2i(0, 1)) # through, and on up the ramp into the next section
		# A short rest now and then while it's just eating, as a player does.
		if goal == "food" and now > next_rest:
			rest_until = now + 1.2
			next_rest = now + 6.0 + randf() * 4.0
		if now < rest_until:
			return Vector2.ZERO
		if path.is_empty() or now > replan_at or not path.has(at):
			path = _plan(here, at, goal)
			replan_at = now + 0.4
		var i := path.find(at)
		if i < 0 or i + 1 >= path.size():
			return Vector2.ZERO
		var d := path[i + 1] - path[i]
		var run := 1
		while run < 6 and _walkable(here, at + d * (run + 1), goal):
			run += 1
		return _toward(d) * lerpf(0.74, 1.0, minf(1.0, (run - 1) / 4.0))

	## What it's after: food, the key (in the side room), or the way out once the gate's open.
	func _goal(here: Section, now: float) -> String:
		if here.index == 0 and here.gate_open():
			return "exit"
		if here.index == 0 and now > HUNT and Section.Eaten.KEY in here.pellets.values():
			return "key"
		return "food"

	func _walkable(s: Section, t: Vector2i, goal: String) -> bool:
		if s.tile_at(t.x, t.y) != Section.FLOOR:
			return false
		var level: int = s.levels[t.x][t.y]
		if level in [Section.Level.LOW, Section.Level.SIDE]:
			return goal != "food"
		if t == s.exit_tile():
			return s.gate_open()
		return true

	func _wanted(s: Section, t: Vector2i, goal: String) -> bool:
		match goal:
			"key":
				return s.pellets.get(t) == Section.Eaten.KEY
			"exit":
				return t == s.exit_tile()
		return s.pellets.has(t)

	func _plan(s: Section, from: Vector2i, goal: String) -> Array[Vector2i]:
		var came := {from: from}
		var queue: Array[Vector2i] = [from]
		while not queue.is_empty():
			var t: Vector2i = queue.pop_front()
			if t != from and _wanted(s, t, goal):
				var out: Array[Vector2i] = [t]
				while out[0] != from:
					out.push_front(came[out[0]])
				return out
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = t + d
				if not came.has(n) and _walkable(s, n, goal):
					came[n] = t
					queue.push_back(n)
		return []

	## A grid step (columns right, rows up the course) as a hand on the board: the inverse of TiltRig.gravity_dir.
	func _toward(d: Vector2i) -> Vector2:
		var rig: TiltRig = main.rig
		return rig.on_screen(Vector3(d.x, 0, -d.y)).normalized()
