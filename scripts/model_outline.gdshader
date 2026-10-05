// A black outline round a model (any mesh: the pickups, the gate's frame), a fixed number of screen pixels wide: the
// model's back faces pushed out along their normals. The model's own materials mark every pixel they draw in the
// stencil buffer (see Section._dress), and the outline only draws where nothing is marked, so it never covers the
// model, even through its see-through glass. It draws after everything else (render priority), once every model has
// marked its pixels.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;
stencil_mode read, compare_not_equal, 1;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width_px = 1.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 out_dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (dot(out_dir, out_dir) > 1e-12) {
		clip.xy += normalize(out_dir) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
