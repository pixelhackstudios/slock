// The jelly wobble's bend (set from jelly.gd), shared by the jelly and its outline so they move together:
// the top sways behind the bottom, and the whole block squishes along an impact axis and bulges out the
// other ways. Vertices are in the model's unit cube (-0.5..0.5).
uniform vec2 sway;                       // top shear, x and z
uniform float squish;                    // + squashes along squish_axis, - stretches
uniform vec3 squish_axis = vec3(0.0, 1.0, 0.0);

void wobble(inout vec3 vertex, inout vec3 normal) {
	vec3 n = squish_axis;
	// Squish: shorter along the hit axis, bulging out the other ways (roughly keeps volume). It's a linear
	// stretch, so normals take its inverse.
	float along = dot(vertex, n);
	vec3 p = n * (along * (1.0 - squish)) + (vertex - n * along) * (1.0 + squish * 0.5);
	float n_along = dot(normal, n);
	vec3 nrm = n * (n_along / (1.0 - squish)) + (normal - n * n_along) / (1.0 + squish * 0.5);
	// Sway: shear grows with height, curved so the base stays planted.
	float h = clamp(p.y + 0.5, 0.0, 1.0);
	p.xz += sway * h * h;
	nrm.y -= dot(sway * 2.0 * h, nrm.xz);
	vertex = p;
	normal = normalize(nrm);
}
