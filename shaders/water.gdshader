shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
// Тёмная ледяная вода с лёгкой рябью.
// Снизу (если смотреть из-под воды) поверхность — светлая полупрозрачная плёнка:
// в полынье сквозь неё видно небо, подо льдом — тёмный лёд.

uniform vec3 water_color : source_color = vec3(0.03, 0.12, 0.2);
uniform vec3 shallow_tint : source_color = vec3(0.08, 0.28, 0.38);

varying vec3 wpos;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * 0.6;
	float t = TIME * 0.6;
	float h1 = vnoise(p + vec2(t, t * 0.7));
	float h2 = vnoise(p * 1.7 - vec2(t * 0.8, t));
	float dx = vnoise(p + vec2(t + 0.1, t * 0.7)) - h1;
	float dz = vnoise(p + vec2(t, t * 0.7 + 0.1)) - h1;
	vec3 n = normalize(vec3(-dx * 3.0, 1.0, -dz * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(water_color, shallow_tint, h2 * 0.4);
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
	ALPHA = 0.92;
	if (!FRONT_FACING) {
		ALBEDO = mix(vec3(0.2, 0.45, 0.5), vec3(0.45, 0.7, 0.72), h2);
		EMISSION = vec3(0.04, 0.12, 0.14);
		ALPHA = 0.45;
	}
}
