// A swurm's slime smear (see slime_trail.gd): a flat strip with rounded ends, glossy and see-through, that dries up
// from its ragged edges inward over `life` seconds of game time. Per smear: COLOR is the swurm's colour, and the
// custom data is (laid at, length in widths, noise seed).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform float now = 0.0;
uniform float life = 2.5;

varying vec4 tint;
varying vec3 smear; // laid at, length in widths, seed

void vertex() {
	tint = COLOR;
	smear = INSTANCE_CUSTOM.xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise, 0..1.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float age = (now - smear.x) / life;
	if (age < 0.0 || age >= 1.0) {
		discard;
	}
	// Where this pixel is, in widths: across the strip, and along it from its middle.
	float len = smear.y;
	vec2 p = vec2(UV.x - 0.5, (UV.y - 0.5) * (len + 1.0));
	float d = length(vec2(p.x, max(abs(p.y) - len * 0.5, 0.0))); // distance from the strip's spine
	float inside = 1.0 - d / 0.5; // 1 on the spine, 0 at the edge
	if (inside <= 0.0) {
		discard;
	}
	// Drying: the edge and the noise go first, so the smear breaks up as it shrinks.
	float grain = noise(p * 3.0 + smear.z) * 0.6 + noise(p * 7.0 - smear.z) * 0.4;
	float wet = inside * 0.65 + grain * 0.45;
	float dry = age * 1.1;
	if (wet <= dry) {
		discard;
	}
	ALBEDO = tint.rgb * 0.5;
	ALPHA = 0.72 * smoothstep(dry, dry + 0.08, wet) * smoothstep(0.0, 0.12, inside);
	EMISSION = tint.rgb * 0.15;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
