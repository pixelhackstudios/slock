class_name Hud
extends CanvasLayer
## The on-screen display: score and lives (top left), remaining time (top centre, blinking red under 10 s), height,
## pellets left and block size (top right), the power and steel countdowns, the slug count, pop-up messages and the
## green flash when a swurm steals time; and the welcome, title, pause and game-over screens, with the leaderboard. It
## keeps running while the game is paused.

signal name_submitted(name: String)
signal play_again

const RED := Color(1.0, 0.25, 0.33)
const CYAN := Color(0.35, 0.75, 1.0)
const POWER_BLUE := Color(0.45, 0.6, 1.0)
const PELLET_CREAM := Color(1.0, 0.92, 0.7)
const BOARD_WIDTH := 460.0
const ITEM_WIDTH := 330.0         # the welcome screen: one model and its words ...
const MODEL_PX := 76.0            # ... the model's little window ...
const ITEM_GAP := 18.0            # ... and the space between items

var _font: FontVariation           # bold
var _status: Control               # the in-game numbers (hidden on the title screen)
var _score: Label
var _time: Label
var _pellets: Label
var _height: Label
var _block: Label
var _slugs: Label
var _lives: Label
var _steel: Label
var _power: Label
var _popups: VBoxContainer
var _flash: ColorRect
var _screen: Control               # the pause, title or game-over screen, rebuilt each time it's shown
var _name_box: LineEdit


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.8

	_flash = ColorRect.new()
	_flash.color = Color(0.4, 1.0, 0.2, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_status = _full_rect(self)
	_label(_status, "SCORE", 18, RED, HORIZONTAL_ALIGNMENT_LEFT, 20)
	_score = _label(_status, "0", 52, RED, HORIZONTAL_ALIGNMENT_LEFT, 40)
	_lives = _label(_status, "", 18, RED, HORIZONTAL_ALIGNMENT_LEFT, 112)
	_label(_status, "REMAINING TIME", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 20)
	_time = _label(_status, "", 52, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40)
	_label(_status, "HEIGHT", 18, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 20)
	_height = _label(_status, "0", 52, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 40)
	_pellets = _label(_status, "", 18, PELLET_CREAM, HORIZONTAL_ALIGNMENT_RIGHT, 112)
	_block = _label(_status, "", 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 140)
	_power = _label(_status, "", 18, POWER_BLUE, HORIZONTAL_ALIGNMENT_CENTER, 112)
	_steel = _label(_status, "", 18, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 140)
	_slugs = _label(_status, "", 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 168)
	var help := _label(_status, "Mouse: tilt    Esc: pause    R: restart", 16, Color(1, 1, 1, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER, 0)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -36
	help.add_theme_color_override("font_shadow_color", Color.TRANSPARENT) # small faded text reads doubled with one

	_popups = VBoxContainer.new()
	_popups.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)

	_screen = _full_rect(self)


func _ready() -> void:
	_popups.offset_top = _h() * 0.3


func _h() -> float:
	return get_viewport().get_visible_rect().size.y


## Refresh the numbers (every frame).
func show_status(score: int, time_left: float, pellets_left: int, power_left: float, height: int, block: int) -> void:
	_height.text = str(height)
	_block.text = "BLOCK  %d" % block
	_score.text = _thousands(score)
	_time.text = str(ceili(maxf(0.0, time_left)))
	var blink := time_left < 10.0 and fmod(_real_time(), 0.5) < 0.25
	_time.add_theme_color_override("font_color", RED if blink else Color.WHITE)
	_pellets.text = "PELLETS LEFT  %d" % pellets_left if pellets_left > 0 else "GATE OPEN"
	_power.text = "POWER  %.1f" % power_left if power_left > 0.0 else ""


## The slug count, or the aiming hint.
func show_slugs(count: int, aiming: bool) -> void:
	if aiming:
		_slugs.text = "AIMING — TILT TO PICK, LEFT CLICK FIRES, RIGHT CLICK CANCELS"
	else:
		_slugs.text = "SLUGS x%d — CLICK TO AIM" % count if count > 0 else "NO SLUGS"


## Lives left (under the score).
func show_lives(count: int) -> void:
	_lives.text = "LIVES x%d" % count


## Slock of Steel's countdown.
func show_steel(left: float) -> void:
	_steel.text = "STEEL  %.1f" % left if left > 0.0 else ""


## A big message in the middle of the screen for `seconds`, fading out over its last second.
func popup(text: String, color: Color, seconds: float) -> void:
	var l := _label(_popups, text, 52, color, HORIZONTAL_ALIGNMENT_CENTER, 0)
	l.set_meta("until", _real_time() + seconds)


## The screen flashes green (a swurm stole time).
func flash() -> void:
	_flash.color.a = 0.25


func clear_popups() -> void:
	for l in _popups.get_children():
		l.queue_free()


# ------------------------------------------------------------------ screens

## Back to the game: no screen over it.
func hide_screen() -> void:
	_clear_screen()
	_status.visible = true


func show_pause() -> void:
	_clear_screen()
	_dim(0.5)
	var y := _h() * 0.4
	_label(_screen, "PAUSED", 52, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, y)
	_label(_screen, "Esc to resume    R to restart    Q to quit", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, y + 76, false)


## The title screen: the name, the credit, how to play, the leaderboard.
func show_title() -> void:
	_clear_screen()
	_status.visible = false
	_dim(0.45)
	var y := _h() * 0.14
	_label(_screen, "A PIXELHACK STUDIOS PRODUCTION  ·  IN ASSOCIATION WITH SCOTT O'NANSKI", 16,
		Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, y - 40, false)
	_label(_screen, "SLOCK", 96, RED, HORIZONTAL_ALIGNMENT_CENTER, y)
	_label(_screen, "tilt the world with the mouse  ·  climb forever", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER,
		y + 130, false)
	_board(_h() * 0.36, 0)
	var start := _label(_screen, "CLICK or SPACE to start   ·   H for how to play   ·   Q to quit", 18, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, 0)
	start.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	start.offset_top = -90


## The welcome screen: what Slock is and what everything in it does, each next to its model, turning. Shown the first
## time the game runs, and from the title screen with H.
func show_welcome() -> void:
	_clear_screen()
	_status.visible = false
	_dim(0.78)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 8)
	page.modulate.a = 0.0 # until it's been fitted to the screen (see _fit)
	_centre(page, 0, ITEM_WIDTH * 3 + ITEM_GAP * 2, 0)
	for line in [["WELCOME TO", 18, Color.WHITE], ["SLOCK", 72, RED]]:
		var l := _text(line[0], line[1], line[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page.add_child(l)
	for part in _welcome_parts():
		var heading := _text(part[0], 18, CYAN, true)
		var note := _text(part[1], 14, Color(1, 1, 1, 0.7), false)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 14)
		top.add_child(heading)
		top.add_child(note)
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		page.add_child(gap)
		page.add_child(top)
		var items: Array = part[2]
		var grid := GridContainer.new()
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.columns = 3 if items.size() > 1 else 1
		grid.add_theme_constant_override("h_separation", ITEM_GAP)
		grid.add_theme_constant_override("v_separation", 8)
		var width := ITEM_WIDTH if items.size() > 1 else ITEM_WIDTH * 3 + ITEM_GAP * 2
		for item in items:
			grid.add_child(_welcome_item(_welcome_model(item[0]), item[1], item[2], width))
		page.add_child(grid)
	var go := _text("CLICK or SPACE to play   ·   Esc for the title", 18, Color.WHITE, true)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	page.add_child(gap)
	page.add_child(go)
	_fit(page)


## The welcome screen's parts: [heading, note, [[model, name, what it does], ...]], with the game's own numbers.
static func _welcome_parts() -> Array:
	return [
		["THE GOAL", "climb forever", [
			["slock", "TILT THE BOARD", "Move the mouse to tilt the board, and Slock slides downhill."],
			["gate", "OPEN THE GATE", "Eat every blue pellet to open it. Go through to climb to the next floor."],
			["key", "OR FIND THE KEY", "It's in the side room, and opens the gate, pellets or not."]]],
		["TIME", "you start with %d seconds; when they run out, the run is over" % Main.START_TIME, [
			["pellet", "PELLETS", "+%d second each, and points." % Main.PELLET_TIME],
			["gold", "GOLD PELLETS", "+%d seconds each, in the side rooms." % Main.GOLD_TIME],
			["clock", "CLOCK", "+%d seconds, in the side room." % Main.CLOCK_TIME]]],
		["DANGER", "and how to fight back", [
			["swurm", "SWURMS", "They crawl out of the pen one by one. A touch takes a third of your time."],
			["power", "POWER PELLET", "+%d seconds. For %d seconds swurms turn blue: eat them for time back." % [
				Main.POWER_TIME, Main.POWER_DURATION]],
			["life", "LIVES", "A pit or an edge costs a life. You have %d; a little red Slock is one more." % \
				Main.START_LIVES]]],
		["POWERUPS", "they float in every section, and come back %d seconds after you take one" % \
				Section.POWERUP_RESPAWN, [
			["steel", "SLOCK OF STEEL", "For %d seconds, push into inner walls and swurms to smash them." % \
				Main.STEEL_DURATION],
			["clear_dots", "CLEAR THE DOTS", "A quarter of the blue pellets left vanish."],
			["close_traps", "CLOSE THE TRAPS", "Fills every pit and walls up the open edges."],
			["slug_pack", "SLUG PACK", "+%d slugs." % Main.SLUG_PACK],
			["extra_slug", "BIG SLUG", "+1 slug."]]],
		["SLUGS", "every gate gives you more", [
			["slug", "AIM AND FIRE", "Left click to aim (the game waits), tilt to pick a way, left click to fire, " +
				"right click to cancel. A slug kills the first swurm or breaks the first inner wall in its way."]]],
	]


## One welcome item: the model turning in its window, its name, and what it does.
func _welcome_item(model: Node3D, name: String, about: String, width: float) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.x = width
	row.add_child(_model_view(model))
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	words.add_child(_text(name, 16, Color.WHITE, true))
	var text := _text(about, 14, Color(1, 1, 1, 0.78), false)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = width - MODEL_PX - 12
	words.add_child(text)
	row.add_child(words)
	return row


## The welcome screen's models, as the game draws them: the model files, Slock's jelly, the orbs, and a swurm.
static func _welcome_model(name: String) -> Node3D:
	match name:
		"slock", "life":
			var jelly := Jelly.new(Vector3(1.0, Slock.HEIGHT_RATIO, 1.0))
			jelly.wobbles = false
			return jelly
		"pellet", "gold", "power":
			var look: Array = Section.ORB_LOOKS[{"pellet": Section.Eaten.PELLET, "gold": Section.Eaten.GOLD,
				"power": Section.Eaten.POWER}[name]]
			var orb := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = look[0]
			sphere.height = look[0] * 2.0
			sphere.material = Section._glass(look[3], look[4], 0.2)
			orb.mesh = sphere
			return orb
		"swurm":
			# The head and its five segments in a train behind it, each 20% smaller (see swurm.gd).
			var swurm := Node3D.new()
			var size := 1.0
			var at := 0.0
			for s in [1.0] + Swurm.SEGMENT_SCALE:
				var block := Jelly.new(Vector3.ONE * s, Jelly.Look.SWURM)
				block.wobbles = false
				block.set_colors(Swurm.GREEN[0], Swurm.GREEN[1])
				if s < 1.0:
					at += (size + s) * 0.5 + Swurm.SEGMENT_GAP
				block.position = Vector3(0, s * 0.5, at)
				size = s
				swurm.add_child(block)
			return swurm
	return Section.model(name)


## A little 3D window of its own with `model` turning in the middle, lit like the game and framed to fit.
func _model_view(model: Node3D) -> Control:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(MODEL_PX, MODEL_PX)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	box.add_child(view)
	var env := WorldEnvironment.new()
	env.environment = Main.environment()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR # see-through: the screen shows behind
	view.add_child(env)
	view.add_child(Main.sunlight())
	var bounds := _bounds(model)
	model.position -= bounds.get_center()
	var turntable := _Turntable.new()
	turntable.add_child(model)
	view.add_child(turntable)
	var camera := Camera3D.new()
	camera.fov = 30.0
	var radius := maxf(0.05, bounds.size.length() * 0.5) # the model's bounding sphere: it fits at every turn
	var from := Vector3(0, sin(deg_to_rad(25.0)), cos(deg_to_rad(25.0))) * radius / sin(deg_to_rad(camera.fov * 0.5))
	camera.transform = Transform3D(Basis.looking_at(-from), from)
	view.add_child(camera)
	return box


## Everything `root` draws, as a box in its parent's space (before it's in the scene).
static func _bounds(root: Node3D) -> AABB:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var box := AABB()
	for i in meshes.size():
		var mi: MeshInstance3D = meshes[i]
		var to_root := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			to_root = (n as Node3D).transform * to_root
			n = n.get_parent()
		var b := to_root * mi.get_aabb()
		box = b if i == 0 else box.merge(b)
	return root.transform * box


## Scale `page` down if it's taller than the screen and centre it, once its height is known (the frame after it's
## built: the wrapped words need their widths first).
func _fit(page: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(page):
		return
	var h := _h()
	var size := page.get_combined_minimum_size()
	var fit := minf(1.0, (h - 40.0) / size.y)
	page.pivot_offset = Vector2(size.x * 0.5, 0)
	page.scale = Vector2.ONE * fit
	page.offset_top = (h - size.y * fit) * 0.5
	page.offset_bottom = page.offset_top + size.y
	page.modulate.a = 1.0


## Turns what's on it, slowly (the welcome screen's models).
class _Turntable extends Node3D:
	func _process(delta: float) -> void:
		rotation.y += delta * 1.1


## The end of a run: why, the run's numbers, then either the name box (a new high score) or the board.
func show_game_over(reason: String, summary: String, ask_name: bool, rank: int) -> void:
	_clear_screen()
	_dim(0.6)
	var y := _h() * 0.1
	_label(_screen, reason, 52, RED, HORIZONTAL_ALIGNMENT_CENTER, y)
	_label(_screen, summary, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, y + 76)
	y += 130
	if ask_name:
		_label(_screen, "NEW HIGH SCORE — enter your name", 18, CYAN, HORIZONTAL_ALIGNMENT_CENTER, y)
		_name_box = LineEdit.new()
		_name_box.text = Leaderboard.last_name()
		_name_box.max_length = 12
		_name_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_box.add_theme_font_size_override("font_size", 26)
		_name_box.select_all_on_focus = true
		_name_box.text_submitted.connect(func(_t): _submit_name())
		_centre(_name_box, y + 36, 300, 48)
		var submit := _button("Submit", y + 96, 140)
		submit.pressed.connect(_submit_name)
		_name_box.grab_focus.call_deferred()
		return
	if rank > 0:
		_label(_screen, "You placed #%d!" % rank, 18, CYAN, HORIZONTAL_ALIGNMENT_CENTER, y)
	_board(y + 40, rank)
	var again := _button("Play again (Enter)", y + 40 + 36 + Leaderboard.MAX * 28 + 30, 200)
	again.pressed.connect(func(): play_again.emit())


func _submit_name() -> void:
	var name := _name_box.text.strip_edges().to_upper()
	name_submitted.emit(name if name != "" else "SLOCK")


## The top 10: rank, name, floor, score, with row `highlight` (1-based) in red.
func _board(top: float, highlight: int) -> void:
	var board := VBoxContainer.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_theme_constant_override("separation", 4)
	_centre(board, top, BOARD_WIDTH, 0)
	var heading := _text("LEADERBOARD", 18, CYAN, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(heading)
	var list := Leaderboard.entries()
	if list.is_empty():
		var none := _text("no scores yet — be the first", 16, Color.GRAY, false)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		board.add_child(none)
		return
	for i in list.size():
		var e: Dictionary = list[i]
		var colour := RED if i + 1 == highlight else Color.WHITE
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for cell in [["%d." % (i + 1), 40, HORIZONTAL_ALIGNMENT_LEFT], [str(e.name), 180, HORIZONTAL_ALIGNMENT_LEFT],
				["F%d" % int(e.height), 80, HORIZONTAL_ALIGNMENT_RIGHT], [_thousands(int(e.score)), 160, HORIZONTAL_ALIGNMENT_RIGHT]]:
			var l := _text(cell[0], 16, colour, false)
			l.custom_minimum_size.x = cell[1]
			l.horizontal_alignment = cell[2]
			row.add_child(l)
		board.add_child(row)


func _clear_screen() -> void:
	for n in _screen.get_children():
		n.queue_free()
	_name_box = null


func _dim(alpha: float) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, alpha)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(dim)


func _button(text: String, top: float, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 18)
	_centre(b, top, width, 44)
	return b


## Put `control` on the screen, centred across it, `top` pixels down.
func _centre(control: Control, top: float, width: float, height: float) -> void:
	control.set_anchors_preset(Control.PRESET_CENTER_TOP)
	control.offset_left = -width * 0.5
	control.offset_right = width * 0.5
	control.offset_top = top
	control.offset_bottom = top + height
	_screen.add_child(control)


func _process(delta: float) -> void:
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.5)
	var t := _real_time()
	for l: Label in _popups.get_children():
		var left: float = l.get_meta("until") - t
		if left <= 0.0:
			l.queue_free()
		else:
			l.modulate.a = clampf(left, 0.0, 1.0)


func _full_rect(parent: Node) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## A label across the screen, `top` pixels down (the pop-up list stacks its own).
func _label(parent: Node, text: String, size: int, color: Color, align: HorizontalAlignment, top: float,
		bold := true) -> Label:
	var l := _text(text, size, color, bold)
	l.horizontal_alignment = align
	if parent != _popups:
		l.set_anchors_preset(Control.PRESET_TOP_WIDE)
		l.offset_left = 40
		l.offset_right = -40
		l.offset_top = top
	parent.add_child(l)
	return l


func _text(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	if bold:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _real_time() -> float:
	return Time.get_ticks_msec() / 1000.0
