// See-through glowing jelly orbs (pellets), drawn in batches. Each bobs up and down at its own pace, from its
// batch's custom data: (phase, speed in rad/s, height).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

uniform vec4 albedo : source_color = vec4(0.25, 0.55, 1.0, 0.72);
uniform vec3 emission : source_color = vec3(0.1, 0.35, 1.2);
uniform float roughness = 0.05;

void vertex() {
	VERTEX.y += sin((TIME + INSTANCE_CUSTOM.x) * INSTANCE_CUSTOM.y) * INSTANCE_CUSTOM.z;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	EMISSION = emission;
	ROUGHNESS = roughness;
}
