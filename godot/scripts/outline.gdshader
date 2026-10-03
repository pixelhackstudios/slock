// A black outline around a sphere, a fixed number of screen pixels wide at any distance. Drawn on a flat quad
// that always faces the camera, centred on the sphere: everything outside the sphere's edge plus width_px is
// cut away, so nothing dark sits behind a see-through sphere.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform float radius = 0.115;      // the sphere's radius (world units)
uniform float half_size = 0.18;    // half the quad's width (world units)
uniform float width_px = 2.0;
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	// Face the camera, ignoring the node's own spin.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0 * half_size; // world distance from the centre
	float px = fwidth(d);                          // world size of one pixel here
	// Hard inner edge tucked half a pixel under the sphere; soft (antialiased) outer edge.
	float inner = step(radius - 0.5 * px, d);
	float outer = 1.0 - smoothstep(radius + (width_px - 0.5) * px, radius + (width_px + 0.5) * px, d);
	float a = inner * outer * color.a;
	if (a <= 0.0) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = a;
}
