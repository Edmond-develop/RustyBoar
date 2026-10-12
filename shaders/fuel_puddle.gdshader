shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Лужа вытекшего топлива: светится ядовито-бирюзовым, по ней бегут медленные круги,
// по краям — радужная плёнка. Неровный край рисуется прозрачностью.

uniform vec3 glow_color : source_color = vec3(0.2, 1.0, 0.75);
uniform vec3 deep_color : source_color = vec3(0.02, 0.18, 0.14);

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 p = lp.xz;
	float r = length(p);
	float edge = 1.0 - smoothstep(0.75, 0.98, r + (vnoise(p * 3.0) - 0.5) * 0.35 + (vnoise(p * 9.0) - 0.5) * 0.1);
	if (edge < 0.01) {
		discard;
	}
	float ripple = sin(r * 40.0 - TIME * 2.0) * 0.5 + 0.5;
	float swirl = vnoise(p * 4.0 + vec2(TIME * 0.15, -TIME * 0.1));
	vec3 col = mix(deep_color, glow_color, swirl * 0.6 + ripple * 0.15);
	// радужная плёнка у края
	float rim = smoothstep(0.55, 0.9, r);
	vec3 rainbow = 0.5 + 0.5 * cos(6.28 * (r * 3.0 + swirl + vec3(0.0, 0.33, 0.67)));
	col = mix(col, rainbow * 0.6, rim * 0.5);
	ALBEDO = col * 0.4;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	EMISSION = col * (0.9 + 0.4 * ripple) * (1.0 - rim * 0.6);
	ALPHA = edge * 0.92;
}
