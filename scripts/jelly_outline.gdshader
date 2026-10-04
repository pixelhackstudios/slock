// A jelly block's outline: the block's back faces pushed out a fixed number of screen pixels. A pixel of that
// shell is only kept where it's outside the block's own edge: its line of sight is traced through the block
// (a rounded cube, bent by the same wobble) and skipped if it hits. So every block shows its full outline, even
// seen through another see-through block, and never darkens its own inside.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

#include "res://scripts/jelly_wobble.gdshaderinc"

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width_px = 1.0;

const float ROUNDING = 0.12;   // the model's corner radius (a 1-block cube)
const float INSET = 0.006;     // trace a hair inside the model: its rounded edges are flat facets, and a
                               // perfectly round shape would poke past them and eat into the outline

varying mat4 view_to_model;

void vertex() {
	view_to_model = inverse(MODELVIEW_MATRIX);
	wobble(VERTEX, NORMAL);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 out_dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (dot(out_dir, out_dir) > 1e-12) {
		clip.xy += normalize(out_dir) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

// Distance to the block's surface from a point in (bent) model space: undo the wobble (exactly: the sway never
// moves a point up or down, and the squish is a plain stretch), then measure to the rounded cube.
float block_distance(vec3 p) {
	float h = clamp(p.y + 0.5, 0.0, 1.0);
	p.xz -= sway * h * h;
	vec3 n = squish_axis;
	float along = dot(p, n);
	p = n * (along / (1.0 - squish)) + (p - n * along) / (1.0 + squish * 0.5);
	vec3 q = abs(p) - vec3(0.5 - ROUNDING);
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - (ROUNDING - INSET);
}

void fragment() {
	// This pixel's line of sight, from the camera, in model space.
	vec4 far_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
	vec3 origin = (view_to_model * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize((view_to_model * vec4(far_point.xyz / far_point.w, 0.0)).xyz);

	// Only march where the ray passes through a box around the block (with room for the wobble).
	vec3 lo = (vec3(-0.9) - origin) / dir;
	vec3 hi = (vec3(0.9) - origin) / dir;
	float t = max(max(min(lo.x, hi.x), min(lo.y, hi.y)), min(lo.z, hi.z));
	float t_end = min(min(max(lo.x, hi.x), max(lo.y, hi.y)), max(lo.z, hi.z));
	t = max(t, 0.0);
	// Outline pixels are all within a pixel of the edge, so "hit" has to mean far closer than a pixel.
	for (int i = 0; i < 96 && t < t_end; i++) {
		float d = block_distance(origin + dir * t);
		if (d < 0.00002) {
			discard; // the block itself is here: not part of the outline
		}
		t += d * 0.7; // the wobble bends space a little, so step short of the distance
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
