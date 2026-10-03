extends Node3D
## Builds the test scene in code: lighting, one map section, Slock and the tilt camera.
## Mouse (or left stick) tilts the board. R restarts, Esc frees the mouse, click to grab it again.

var section: Section
var slock: Slock
var rig: TiltRig


func _ready() -> void:
	_setup_lighting()

	section = Section.new()
	add_child(section)

	slock = Slock.new()
	add_child(slock)
	slock.reset_to(section.start_position(slock.HEIGHT))

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
