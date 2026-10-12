shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Металл обломков корабля (всё рисуется по координатам самой детали, без текстур):
//  * краска с полосами панелей и рядами заклёпок;
//  * краска стёрта до блестящего металла пятнами и по рваным краям;
//  * сажа и подпалины, ржавые потёки вниз;
//  * по желанию — жёлто-чёрная «аварийная» полоса;
//  * heat > 0 — металл раскалён (сопло двигателя), светится от тёмно-красного до оранжевого.
// Цвет вершин умножает краску (можно красить части меша по-разному).

uniform vec3 paint : source_color = vec3(0.78, 0.8, 0.84);
uniform vec3 bare : source_color = vec3(0.55, 0.56, 0.58);
uniform float wear = 0.35;          // сколько краски стёрто
uniform float soot = 0.45;          // сколько сажи
uniform float rust = 0.25;
uniform float panel = 0.9;          // размер панели, м
uniform float hazard = 0.0;         // 1 — аварийная полоса
uniform float hazard_y = 0.0;       // где полоса (по высоте детали)
uniform float heat = 0.0;

varying vec3 lp;
varying vec3 ln;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	return noise3(p) * 0.5 + noise3(p * 2.1 + 3.1) * 0.3 + noise3(p * 4.3 + 7.7) * 0.2;
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	// Плоскость, на которую «наклеены» панели — по главной оси нормали
	vec3 an = abs(ln);
	vec2 uv = an.x > an.y && an.x > an.z ? lp.zy : (an.y > an.z ? lp.xz : lp.xy);
	vec2 cell = uv / panel;
	vec2 f = fract(cell);
	float seam = 1.0 - smoothstep(0.0, 0.025, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	// заклёпки вдоль швов
	vec2 rv = fract(uv / (panel / 8.0)) - 0.5;
	float near_seam = 1.0 - smoothstep(0.04, 0.09, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	float rivet = (1.0 - smoothstep(0.12, 0.22, length(rv))) * near_seam;
	float pid = hash(floor(vec3(cell, 0.0)) + 0.5);

	float n1 = fbm3(lp * 1.3);
	float n2 = fbm3(lp * 6.0 + 11.0);
	vec3 col = paint * COLOR.rgb * (0.88 + 0.2 * pid);
	// аварийная полоса
	float stripe_band = 1.0 - smoothstep(0.35, 0.4, abs(lp.y - hazard_y));
	float stripes = step(0.5, fract((lp.x + lp.z + lp.y) * 1.4));
	col = mix(col, mix(vec3(0.9, 0.62, 0.05), vec3(0.04), stripes), stripe_band * hazard);
	// стёртая краска
	float worn = smoothstep(1.0 - wear, 1.05 - wear, n2 * 0.6 + n1 * 0.4);
	col = mix(col, bare * (0.8 + 0.4 * n2), worn);
	// ржавые потёки — вытянуты вниз
	float streak = fbm3(vec3(lp.x * 3.0, lp.y * 0.4, lp.z * 3.0));
	col = mix(col, vec3(0.32, 0.15, 0.07) * (0.7 + 0.5 * n2), smoothstep(0.6, 0.8, streak) * rust);
	// сажа и подпалины
	float s = smoothstep(0.45, 0.75, n1 + (n2 - 0.5) * 0.3) * soot;
	col = mix(col, vec3(0.03, 0.028, 0.026), s);
	// швы и заклёпки
	col *= 1.0 - seam * 0.55;
	col = mix(col, bare * 1.2, rivet * 0.6);

	ALBEDO = col;
	METALLIC = mix(0.12, 0.85, worn);
	ROUGHNESS = clamp(mix(0.58, 0.32, worn) + s * 0.4 + seam * 0.2, 0.05, 1.0);
	// раскалённый металл
	float hot = heat * (0.75 + 0.25 * sin(TIME * 2.0 + n1 * 6.0));
	EMISSION = mix(vec3(0.6, 0.05, 0.0), vec3(1.0, 0.5, 0.1), heat) * hot * 2.5;
}
