class_name Hud
extends CanvasLayer
## The on-screen display: score (top left), remaining time (top centre, blinking red under 10 s), height, pellets
## left and block size (top right), the power countdown, pop-up messages, the green flash when a swurm steals time, and the pause
## and round-over screens. It keeps running while the game is paused.

const RED := Color(1.0, 0.25, 0.33)
const CYAN := Color(0.35, 0.75, 1.0)
const POWER_BLUE := Color(0.45, 0.6, 1.0)
const PELLET_CREAM := Color(1.0, 0.92, 0.7)

var _font: FontVariation
var _score: Label
var _time: Label
var _pellets: Label
var _height: Label
var _block: Label
var _slugs: Label
var _steel: Label
var _power: Label
var _popups: VBoxContainer
var _flash: ColorRect
var _overlay: Control
var _overlay_title: Label
var _overlay_line: Label
var _overlay_hint: Label


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

	_label("SCORE", 18, RED, HORIZONTAL_ALIGNMENT_LEFT, 20)
	_score = _label("0", 52, RED, HORIZONTAL_ALIGNMENT_LEFT, 40)
	_label("REMAINING TIME", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 20)
	_time = _label("", 52, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40)
	_label("HEIGHT", 18, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 20)
	_height = _label("0", 52, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 40)
	_pellets = _label("", 18, PELLET_CREAM, HORIZONTAL_ALIGNMENT_RIGHT, 112)
	_block = _label("", 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 140)
	_power = _label("", 18, POWER_BLUE, HORIZONTAL_ALIGNMENT_CENTER, 112)
	_steel = _label("", 18, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 140)
	_slugs = _label("", 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 168)

	_popups = VBoxContainer.new()
	_popups.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)

	var help := _label("Mouse: tilt    Esc: pause    R: restart", 16, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 0)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -36
	help.add_theme_color_override("font_shadow_color", Color.TRANSPARENT) # small faded text reads doubled with one

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	_overlay_title = _label("", 52, RED, HORIZONTAL_ALIGNMENT_CENTER, 0, _overlay)
	_overlay_line = _label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0, _overlay)
	_overlay_hint = _label("", 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 0, _overlay)


func _ready() -> void:
	var h := get_viewport().get_visible_rect().size.y
	_popups.offset_top = h * 0.3
	_overlay_title.offset_top = h * 0.3
	_overlay_line.offset_top = h * 0.3 + 76
	_overlay_hint.offset_top = h * 0.3 + 116


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
		_slugs.text = "AIMING — TILT TO PICK, CLICK TO FIRE"
	else:
		_slugs.text = "SLUGS x%d — CLICK TO AIM" % count if count > 0 else "NO SLUGS"


## Slock of Steel's countdown.
func show_steel(left: float) -> void:
	_steel.text = "STEEL  %.1f" % left if left > 0.0 else ""


## A big message in the middle of the screen for `seconds`, fading out over its last second.
func popup(text: String, color: Color, seconds: float) -> void:
	var l := _label(text, 52, color, HORIZONTAL_ALIGNMENT_CENTER, 0, _popups)
	l.set_meta("until", _real_time() + seconds)


## The screen flashes green (a swurm stole time).
func flash() -> void:
	_flash.color.a = 0.25


## The pause / round-over screen; an empty title hides it.
func show_overlay(title: String, title_color := RED, line := "", hint := "") -> void:
	_overlay.visible = title != ""
	if _overlay.visible:
		clear_popups()
	_overlay_title.text = title
	_overlay_title.add_theme_color_override("font_color", title_color)
	_overlay_line.text = line
	_overlay_hint.text = hint


func clear_popups() -> void:
	for l in _popups.get_children():
		l.queue_free()


func _process(delta: float) -> void:
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.5)
	var t := _real_time()
	for l: Label in _popups.get_children():
		var left: float = l.get_meta("until") - t
		if left <= 0.0:
			l.queue_free()
		else:
			l.modulate.a = clampf(left, 0.0, 1.0)


func _label(text: String, size: int, color: Color, align: HorizontalAlignment, top: float, parent: Node = null) -> Label:
	if parent == null:
		parent = self
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != _popups:
		l.set_anchors_preset(Control.PRESET_TOP_WIDE)
		l.offset_left = 40
		l.offset_right = -40
		l.offset_top = top
	parent.add_child(l)
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
