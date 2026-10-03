// See-through jelly (Slock, swurms), bent by the wobble (see jelly_wobble.gdshaderinc). Its outline is
// jelly_outline.gdshader.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

#include "res://scripts/jelly_wobble.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.85, 0.0, 0.06, 0.72);
uniform vec3 emission : source_color = vec3(0.45, 0.0, 0.03);
uniform float roughness = 0.05;

void vertex() {
	wobble(VERTEX, NORMAL);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	EMISSION = emission;
	ROUGHNESS = roughness;
}
