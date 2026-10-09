shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Плоскость трещины внутри прозрачного льда.
// UV.x — вдоль трещины (0..1), UV.y — вглубь (0 у поверхности, 1 на дне скола).
//  * поверхность скола серебристая, по ней идут косые «перья» (следы роста трещины);
//  * если смотреть вдоль трещины — она вспыхивает яркой линией (как в настоящем льду),
//    если сверху — видна как полупрозрачная молочная пелена;
//  * вглубь трещина тускнеет и голубеет — её «видно сквозь толщу льда».
// Цвет экземпляра: .a — насколько трещина заметна (растёт с уровнем), .r — случайный узор.

uniform vec3 silver : source_color = vec3(0.88, 0.95, 1.0);
uniform vec3 deep_tint : source_color = vec3(0.3, 0.55, 0.8);

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

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float seed = COLOR.r * 37.0;
	// к концам трещина сходит на нет
	float ends = smoothstep(0.0, 0.07, u) * smoothstep(1.0, 0.93, u);
	// перья: косые штрихи по плоскости скола
	float feather = vnoise(vec2(u * 46.0 - v * 7.0 + seed, v * 2.5));
	feather = smoothstep(0.42, 0.9, feather);
	float fine = vnoise(vec2(u * 140.0 + v * 9.0, v * 5.0 + seed));
	// вглубь — тусклее
	float depth_fade = pow(1.0 - clamp(v, 0.0, 1.0), 0.9);
	// блик: вдоль трещины ярко, сверху — пелена
	float facing = abs(dot(NORMAL, VIEW));
	float glint = pow(1.0 - facing, 3.0);
	float a = (0.28 + 0.55 * feather + 0.15 * fine) * depth_fade + glint * 0.8 * (1.0 - v * 0.6);
	a *= ends * COLOR.a;
	ALBEDO = mix(deep_tint, silver, clamp(1.0 - v * 0.85 + feather * 0.25 + glint * 0.3, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.95);
}
