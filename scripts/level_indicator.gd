class_name LevelIndicator
extends Control
## An artificial horizon for the board: the dot is where your hand is (trackball or stick), the outer ring is full
## tilt, and the small centre ring is level. Inside it the board is within half a degree of flat, so Slock
## stops; the dot turns green there.

const RADIUS := 56.0
const LEVEL_TILT := Slock.LEVEL # tilt (fraction of full) that counts as level: half a degree

var rig: TiltRig


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * RADIUS * 2.0
	size = custom_minimum_size
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var faint := Color(1, 1, 1, 0.25)
	draw_circle(c, RADIUS, Color(0, 0, 0, 0.35))
	draw_arc(c, RADIUS, 0, TAU, 64, faint, 1.5, true)
	draw_line(c - Vector2(RADIUS, 0), c + Vector2(RADIUS, 0), faint, 1.0)
	draw_line(c - Vector2(0, RADIUS), c + Vector2(0, RADIUS), faint, 1.0)
	# The level zone, sized through the same response curve the tilt uses.
	var level_r := RADIUS * pow(LEVEL_TILT, 1.0 / 2.2)
	draw_arc(c, level_r, 0, TAU, 32, Color(1, 1, 1, 0.6), 1.5, true)

	if rig == null:
		return
	var level := rig.tilt.length() < LEVEL_TILT
	var dot := c + Vector2(rig.stick.x, -rig.stick.y) * RADIUS
	draw_circle(dot, 5.0, Color(0.35, 0.95, 0.55) if level else Color.WHITE, true, -1.0, true)
