class_name LevelIndicator
extends Control
## An artificial horizon for the board: the dot is where your hand is (trackball or stick), the centre is level and
## the ring is full tilt. It sits at the bottom middle of the screen, near where you're looking, just above the
## controls line.

const RADIUS := 40.0
const ABOVE_BOTTOM := 44.0        # px from the bottom of the screen to its lowest point (clear of the controls line)

var rig: TiltRig


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * RADIUS * 2.0
	size = custom_minimum_size
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -RADIUS
	offset_right = RADIUS
	offset_bottom = -ABOVE_BOTTOM
	offset_top = -ABOVE_BOTTOM - RADIUS * 2.0
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
	if rig == null:
		return
	var dot := c + Vector2(rig.hand.x, -rig.hand.y) * RADIUS
	draw_circle(dot, 4.0, Color.WHITE, true, -1.0, true)
