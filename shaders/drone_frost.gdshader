shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Ледяная корка на дроне (рисуется поверх всех его деталей).
// amount 0..1: корка нарастает пятнами, потом сплошняком, становится толще и бугристее.

uniform float amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 lp;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
	// корка нарастает наружу — бугристо
	float lump = noise3(VERTEX * 14.0);
	VERTEX += NORMAL * amount * (0.012 + 0.025 * lump);
}

void fragment() {
	if (amount <= 0.001) {
		discard;
	}
	float n = noise3(lp * 7.0) * 0.6 + noise3(lp * 19.0) * 0.4;
	float t = 1.0 - amount * 1.15;
	float cover = smoothstep(t - 0.06, t + 0.06, n);
	if (cover < 0.02) {
		discard;
	}
	float fine = noise3(lp * 45.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(vec3(0.7, 0.85, 0.97), vec3(0.96, 0.98, 1.0), clamp(fine * 0.6 + fres * 0.5, 0.0, 1.0));
	ROUGHNESS = mix(0.1, 0.55, fine);
	SPECULAR = 0.75;
	EMISSION = vec3(step(0.94, fine) * 0.5 * amount);   // искорки инея
	ALPHA = cover * (0.72 + 0.22 * fine);
}
