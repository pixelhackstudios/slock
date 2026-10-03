// Slock's see-through red jelly, bent by the wobble (see jelly.gd): the top sways behind the bottom, and the
// whole block squishes along an impact axis and bulges out the other ways. Vertices are in the model's
// unit cube (-0.5..0.5).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(0.85, 0.0, 0.06, 0.72);
uniform vec3 emission : source_color = vec3(0.45, 0.0, 0.03);
uniform float roughness = 0.05;
uniform vec2 sway;                       // top shear, x and z
uniform float squish;                    // + squashes along squish_axis, - stretches
uniform vec3 squish_axis = vec3(0.0, 1.0, 0.0);

void vertex() {
	vec3 n = squish_axis;
	// Squish: shorter along the hit axis, bulging out the other ways (roughly keeps volume). It's a linear
	// stretch, so normals take its inverse.
	float along = dot(VERTEX, n);
	vec3 p = n * (along * (1.0 - squish)) + (VERTEX - n * along) * (1.0 + squish * 0.5);
	float nAlong = dot(NORMAL, n);
	vec3 nrm = n * (nAlong / (1.0 - squish)) + (NORMAL - n * nAlong) / (1.0 + squish * 0.5);
	// Sway: shear grows with height, curved so the base stays planted.
	float h = clamp(p.y + 0.5, 0.0, 1.0);
	p.xz += sway * h * h;
	nrm.y -= dot(sway * 2.0 * h, nrm.xz);
	VERTEX = p;
	NORMAL = normalize(nrm);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	EMISSION = emission;
	ROUGHNESS = roughness;
}
