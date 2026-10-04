// A black outline round a pickup piece (a box or a sphere, centred on its node), a fixed number of screen pixels
// wide: the piece's back faces pushed out along their normals. A pixel of that shell is only kept where its line of
// sight misses the piece itself, so nothing dark shows through the see-through glass. Used as a material overlay.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width_px = 1.0;
uniform vec3 half_size = vec3(0.5); // the box's half extents (model space); for a sphere, x is its radius
uniform bool sphere = false;

varying mat4 view_to_model;

void vertex() {
	view_to_model = inverse(MODELVIEW_MATRIX);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 out_dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (dot(out_dir, out_dir) > 1e-12) {
		clip.xy += normalize(out_dir) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	// This pixel's line of sight, from the camera, in model space.
	vec4 far_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
	vec3 origin = (view_to_model * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize((view_to_model * vec4(far_point.xyz / far_point.w, 0.0)).xyz);
	bool hit;
	if (sphere) {
		float b = dot(origin, dir);
		float c = dot(origin, origin) - half_size.x * half_size.x;
		hit = b * b - c >= 0.0 && -b + sqrt(max(b * b - c, 0.0)) >= 0.0;
	} else {
		vec3 lo = (-half_size - origin) / dir;
		vec3 hi = (half_size - origin) / dir;
		float t_in = max(max(min(lo.x, hi.x), min(lo.y, hi.y)), min(lo.z, hi.z));
		float t_out = min(min(max(lo.x, hi.x), max(lo.y, hi.y)), max(lo.z, hi.z));
		hit = t_out >= max(t_in, 0.0);
	}
	if (hit) {
		discard; // the piece itself is here: not part of the outline
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
