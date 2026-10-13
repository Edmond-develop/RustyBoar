shader_type canvas_item;
// Стекло визора изнутри (только у своего игрока):
//  * frost 0..1 — с краёв нарастают морозные узоры («папоротники»), чем сильнее обледенение;
//  * wet 0..1 — после воды по стеклу ползут капли и стекают вниз;
//  * splash 0..1 — миг всплеска: стекло заливает водой.

uniform float frost : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float splash : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += noise(p) * a;
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

// капли: сетка ячеек, в каждой — своя капля, которая медленно сползает
vec2 drops(vec2 uv, float t, float scale) {
	vec2 g = uv * vec2(scale * aspect, scale);
	vec2 id = floor(g);
	float r = h21(id);
	g.y += t * (0.05 + r * 0.25);
	id = floor(g);
	vec2 f = fract(g) - 0.5;
	float rr = h21(id + 7.0);
	vec2 c = vec2(rr - 0.5, h21(id + 13.0) - 0.5) * 0.6;
	float d = length((f - c) * vec2(1.0, 0.8));
	float size = 0.08 + 0.18 * rr;
	float on = step(0.8, h21(id + 3.0));
	float drop = smoothstep(size, size * 0.6, d) * on;
	float rim = (smoothstep(size, size * 0.85, d) - smoothstep(size * 0.85, size * 0.6, d)) * on;
	return vec2(drop, rim);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float edge = length(c) / length(vec2(aspect, 1.0) * 0.5);       // 0 в центре, 1 в углу
	vec4 col = vec4(0.0);

	// иней с краёв
	if (frost > 0.01) {
		float n = fbm(uv * vec2(aspect, 1.0) * 5.0);
		float reach = mix(1.05, 0.45, frost);
		float m = smoothstep(reach, reach + 0.18, edge + (n - 0.5) * 0.35);
		float fern = 1.0 - abs(noise(uv * vec2(aspect, 1.0) * 38.0 + n * 4.0) * 2.0 - 1.0);
		fern = pow(fern, 5.0);
		float a = m * (0.35 + 0.55 * fern) * (0.6 + 0.4 * frost);
		col = mix(col, vec4(0.86, 0.94, 1.0, a), a);
	}
	// капли воды
	if (wet > 0.01) {
		vec2 d1 = drops(uv, TIME, 6.0);
		vec2 d2 = drops(uv + 0.37, TIME * 1.3, 11.0);
		float dr = max(d1.x, d2.x * 0.6);
		float rim = max(d1.y, d2.y * 0.6);
		float a = (dr * 0.12 + rim * 0.3) * wet;
		col = mix(col, vec4(0.85, 0.95, 1.0, a), a);
	}
	// всплеск
	if (splash > 0.01) {
		float w = fbm(uv * vec2(aspect, 1.0) * 3.0 + TIME * 2.0);
		float a = splash * (0.45 + 0.35 * w);
		col = mix(col, vec4(0.55, 0.75, 0.82, a), a);
	}
	COLOR = col;
}
