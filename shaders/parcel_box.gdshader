shader_type spatial;
render_mode specular_schlick_ggx;
// Посылка курьерской службы: картон, лента крест-накрест, оранжевая наклейка
// с полосками-штрихкодом. Всё рисуется по координатам коробки (размер — box_size).

uniform vec3 box_size = vec3(1.0, 1.0, 1.0);
uniform vec3 cardboard : source_color = vec3(0.62, 0.45, 0.28);
uniform vec3 tape : source_color = vec3(0.75, 0.62, 0.42);
uniform vec3 label : source_color = vec3(0.95, 0.55, 0.15);
uniform float dirt = 0.4;

varying vec3 lp;
varying vec3 ln;

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
	lp = VERTEX / box_size;     // от -0.5 до 0.5 по каждой оси
	ln = NORMAL;
}

void fragment() {
	vec3 an = abs(ln);
	vec2 uv = an.x > an.y && an.x > an.z ? lp.zy : (an.y > an.z ? lp.xz : lp.xy);
	float n = vnoise(uv * 9.0 + lp.xz * 3.0);
	vec3 col = cardboard * (0.85 + 0.25 * n);
	// гофра картона — тонкие полоски
	col *= 0.95 + 0.05 * sin(uv.x * 240.0);
	// лента: поперёк верха и сверху вниз по бокам
	float t1 = 1.0 - step(0.07, abs(lp.x));
	float t2 = (an.y > 0.5) ? 1.0 - step(0.07, abs(lp.z)) : 0.0;
	col = mix(col, tape * (0.9 + 0.2 * n), clamp(t1 + t2, 0.0, 1.0) * 0.85);
	// наклейка на боках (по Z)
	if (an.z > 0.5) {
		vec2 q = uv - vec2(0.2, 0.08);
		float in_label = step(abs(q.x), 0.16) * step(abs(q.y), 0.12);
		vec3 lab = label;
		float bars = step(0.5, fract(q.x * 60.0 + hash(vec2(floor(q.x * 60.0), 3.0)) * 0.5)) * step(q.y, -0.02) * step(-0.1, q.y);
		lab = mix(lab, vec3(0.05), bars);
		lab = mix(lab, vec3(1.0), step(0.05, q.y) * step(q.y, 0.09) * step(abs(q.x), 0.13) * 0.85);
		col = mix(col, lab, in_label);
	}
	// грязь снизу и пятнами
	col = mix(col, vec3(0.1, 0.07, 0.06), clamp((0.0 - lp.y) * 1.6 * dirt + smoothstep(0.65, 0.85, vnoise(uv * 4.0 + 9.0)) * dirt, 0.0, 0.8));
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
