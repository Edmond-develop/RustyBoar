shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Броня экзоскафандра: краска цвета игрока или голый металл/резина.
//  * износ (wear): чем меньше здоровья, тем больше сколов краски и ржавчины;
//  * следы (spots, до 8 на деталь), в координатах самой детали:
//      0 — ожог лучом: обугленная середина, вокруг цвета побежалости, свежий — светится;
//      1 — вмятина: ямка, содранная до металла краска, царапины;
//      2 — пробоина: дырка с рваными краями, внутри искрит;
//      3 — ошпарило паром: жёлто-бурые разводы;
//  * снег налипает сверху, мокрый корпус темнее и блестит.

uniform vec3 base_color : source_color = vec3(0.86, 0.45, 0.17);
uniform float metal = 0.5;
uniform float rough = 0.4;
uniform float paint = 1.0;          // 1 — окрашенная деталь, 0 — металл/резина без краски
uniform float wear = 0.0;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float pattern = 6.0;        // мелкость узоров (на метр детали)
uniform int spot_count = 0;
uniform vec4 spot_pos[8];           // xyz — центр, w — радиус
uniform vec4 spot_info[8];          // x — тип, y — накал (0..1), z — сила, w — зерно

varying vec3 lp;
varying vec3 wn;

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

float fbm(vec3 p) {
	return noise3(p) * 0.5 + noise3(p * 2.03 + 1.7) * 0.3 + noise3(p * 4.1 + 3.1) * 0.2;
}

void vertex() {
	lp = VERTEX;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 p = lp * pattern;
	float n1 = fbm(p);
	vec3 col = base_color * (0.9 + 0.2 * n1);
	float m = metal;
	float r = clamp(rough + (n1 - 0.5) * 0.12, 0.05, 1.0);
	vec3 steel = vec3(0.58, 0.59, 0.61);

	if (paint > 0.5) {
		// сколы краски — сквозь них голая сталь
		float chip = fbm(p * 3.4 + 3.1);
		float chip_t = 0.79 - wear * 0.16;
		float c = smoothstep(chip_t, chip_t + 0.02, chip);
		col = mix(col, steel * (0.75 + 0.35 * noise3(p * 7.0)), c);
		m = mix(m, 0.9, c);
		r = mix(r, 0.32, c);
		// ржавые подтёки
		float rust = smoothstep(0.62 - wear * 0.12, 0.82, fbm(p * 1.1 + vec3(7.7, 2.0, 1.0))) * (0.25 + wear * 0.35);
		col = mix(col, vec3(0.4, 0.19, 0.07) * (0.7 + 0.5 * noise3(p * 5.0)), rust * 0.55);
		r = mix(r, 0.85, rust * 0.55);
	}

	float h = 0.0;                 // рельеф (м) — для вмятин и рваных краёв
	vec3 emis = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= spot_count) {
			break;
		}
		vec4 sp = spot_pos[i];
		vec4 si = spot_info[i];
		vec3 q = lp - sp.xyz;
		float rad = max(sp.w, 0.001);
		float jitter = (noise3(lp * (9.0 / rad) + si.w) - 0.5) * 0.5;
		float d = length(q) / rad + jitter;
		if (d > 1.7) {
			continue;
		}
		int kind = int(si.x + 0.5);
		float str = si.z;
		if (kind == 0) {
			float core = 1.0 - smoothstep(0.22, 0.55, d);
			float ring = 1.0 - smoothstep(0.5, 1.3, d);
			float t = clamp((d - 0.3) / 1.0, 0.0, 1.0);
			vec3 temper = mix(vec3(0.16, 0.22, 0.55), vec3(0.42, 0.2, 0.5), smoothstep(0.0, 0.35, t));
			temper = mix(temper, vec3(0.8, 0.6, 0.25), smoothstep(0.35, 0.8, t));
			col = mix(col, temper, ring * 0.8 * str);
			m = mix(m, 0.85, ring * str * 0.6);
			r = mix(r, 0.3, ring * str * 0.5);
			float crackle = smoothstep(0.45, 0.6, fbm(lp * (3.0 / rad) + si.w));
			col = mix(col, vec3(0.03, 0.025, 0.02) + crackle * 0.05, core * str);
			r = mix(r, 0.95, core * str);
			m = mix(m, 0.1, core * str);
			emis += vec3(1.0, 0.32, 0.05) * core * si.y * (1.5 + 3.0 * crackle);
		} else if (kind == 1) {
			float dent = 1.0 - smoothstep(0.0, 1.0, d);
			h -= dent * dent * str * 0.03 * rad * 6.0;
			float bare = (1.0 - smoothstep(0.35, 0.7, d)) * str;
			vec3 axis = normalize(vec3(si.w, 1.0, 0.3 + fract(si.w * 3.7)));
			float lines = noise3(vec3(dot(q, axis) * (60.0 / rad) * 0.1, length(cross(q, axis)) * 2.0, si.w));
			float scr = smoothstep(0.7, 0.78, lines) * (1.0 - smoothstep(0.5, 1.6, d)) * str;
			float b = max(bare * 0.85, scr);
			col = mix(col, steel * 0.95, b);
			m = mix(m, 0.95, b);
			r = mix(r, 0.28, b);
			col *= 1.0 - dent * 0.3 * str;
		} else if (kind == 2) {
			float hole = 1.0 - smoothstep(0.2, 0.3, d);
			float lip = clamp((1.0 - smoothstep(0.28, 0.65, d)) - hole, 0.0, 1.0);
			col = mix(col, steel, lip * str);
			m = mix(m, 0.95, lip * str);
			h += (lip * 0.4 - hole) * str * 0.012;
			col = mix(col, vec3(0.01), hole * str);
			r = mix(r, 1.0, hole * str);
			emis += vec3(1.0, 0.55, 0.15) * hole * str * (0.3 + si.y * 2.0);
		} else {
			float sc = (1.0 - smoothstep(0.3, 1.2, d)) * str;
			float blot = smoothstep(0.4, 0.7, noise3(lp * (14.0 / rad) * 0.1 + si.w));
			col = mix(col, mix(vec3(0.78, 0.64, 0.36), vec3(0.46, 0.38, 0.3), blot), sc * 0.65);
			r = mix(r, 0.75, sc * 0.5);
			m = mix(m, 0.3, sc * 0.5);
		}
	}

	if (h != 0.0) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhx = dFdx(h);
		float dhy = dFdy(h);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	}

	// снег налипает на то, что смотрит вверх
	float up = normalize(wn).y;
	float s = snow * smoothstep(0.25, 0.75, up + (noise3(lp * 30.0) - 0.5) * 0.5);
	col = mix(col, vec3(0.92, 0.95, 1.0), s);
	r = mix(r, 0.9, s);
	m = mix(m, 0.0, s);

	// мокрый — темнее и блестит
	col *= 1.0 - 0.25 * wet * (1.0 - s);
	r = mix(r, 0.08, wet * 0.8 * (1.0 - s));

	ALBEDO = col;
	METALLIC = m;
	ROUGHNESS = r;
	SPECULAR = 0.5;
	EMISSION = emis;
}
