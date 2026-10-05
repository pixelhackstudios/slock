// The gate's barrier: a see-through teal field filling the exit, brightest where you see it edge-on, with bands of
// light rising through it and a faint grid. On the gate model's barrier (a rounded box over the exit tile, standing on
// its floor: model y 0..1.15).
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.12, 0.95, 0.9);
uniform float base_alpha = 0.22;
uniform float edge_alpha = 0.55;   // added where the field is seen edge-on
uniform float band_alpha = 0.18;   // the rising bands
uniform float bands = 7.0;         // across its height
uniform float speed = 0.35;        // bands a second

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	edge = edge * edge;
	float band = pow(0.5 + 0.5 * sin((model_pos.y * bands - TIME * speed) * TAU), 6.0);
	vec2 cell = abs(fract(vec2(model_pos.x + model_pos.z, model_pos.y) * 8.0) - 0.5);
	float grid = smoothstep(0.44, 0.5, max(cell.x, cell.y)) * 0.12;
	float fade = smoothstep(0.0, 0.08, model_pos.y);  // softer where it meets the floor
	ALBEDO = tint * (1.0 + band * 0.6 + edge * 0.8);
	ALPHA = clamp((base_alpha + edge * edge_alpha + band * band_alpha + grid) * mix(0.6, 1.0, fade), 0.0, 0.95);
}
