shader_type spatial;
// Плиты тонкого ледяного моста (непрозрачные — без мерцания).
// INSTANCE_CUSTOM.r — насколько плита треснула (0..1), .g — своё зерно узора трещин.

uniform vec3 deep : source_color = vec3(0.04, 0.2, 0.38);
uniform vec3 mid : source_color = vec3(0.3, 0.62, 0.84);
uniform vec3 rim : source_color = vec3(0.8, 0.94, 1.0);
uniform vec3 crack_col : source_color = vec3(0.92, 0.98, 1.0);

varying vec3 lpos;
varying float stress;
varying float seed;

void vertex() {
	lpos = VERTEX;
	stress = INSTANCE_CUSTOM.r;
	seed = INSTANCE_CUSTOM.g;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// расстояние до границы ячейки — линии трещин
float cracks(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(h21(n + g + seed), h21(n + g + 17.3 + seed));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void fragment() {
	vec2 p = lpos.xz;
	float n = vnoise(p * 2.3 + seed * 10.0);
	// толща льда: глубокий синий, к краям — светлее
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 col = mix(deep, mid, 0.35 + 0.45 * n);
	col = mix(col, rim, fres * 0.7);
	// пузырьки и белые прожилки
	float veins = smoothstep(0.82, 0.95, vnoise(p * vec2(0.8, 5.0) + seed * 3.0));
	col = mix(col, rim, veins * 0.5);
	// иней сверху
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float top = smoothstep(0.6, 0.95, wn.y);
	float frost = top * smoothstep(0.35, 0.7, vnoise(p * 3.1 + 7.0)) * 0.55;
	col = mix(col, vec3(0.9, 0.95, 1.0), frost);
	// трещины: с ростом напряжения — гуще и ярче, перед обрушением светятся
	float s = clamp(stress, 0.0, 1.0);
	float line_fine = 1.0 - smoothstep(0.0, 0.04 + 0.03 * s, cracks(p * (2.2 + s * 1.5)));
	float line_big = 1.0 - smoothstep(0.0, 0.05, cracks(p * 0.9 + 3.0));
	float cr = max(line_big * smoothstep(0.0, 0.25, s), line_fine * smoothstep(0.25, 0.8, s));
	col = mix(col, crack_col, cr);
	col *= 1.0 - 0.25 * s;
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.35, frost + cr * 0.5);
	METALLIC = 0.1;
	SPECULAR = 0.7;
	EMISSION = crack_col * cr * s * s * 1.6 + mid * 0.04;
}
