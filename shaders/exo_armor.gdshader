shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Броня экзоскафандра: краска цвета игрока или голый металл/резина.
//  * износ (wear): чем меньше здоровья, тем больше сколов краски и ржавчины;
//  * следы (spots, до 8 на деталь), в координатах самой детали:
//      0 — ожог лучом: обугленная середина, вокруг цвета побежалости, свежий — светится;
//      1 — вмятина: ямка, содранная до металла краска, царапины;
//      2 — пробоина: дырка с рваными краями, внутри искрит;
//      3 — ошпарило паром: жёлто-бурые разводы;
//      4 — царапины (столкновения): борозды до блестящего металла;
//      5 — следы мороза (после глыбы): краска потрескалась сеткой и отслоилась;
//      6 — смято давлением: складки-морщины;
//  * снег налипает сверху, мокрый корпус темнее и блестит.

uniform vec3 base_color : source_color = vec3(0.86, 0.45, 0.17);
uniform float metal = 0.5;
uniform float rough = 0.4;
uniform float paint = 1.0;          // 1 — окрашенная деталь, 0 — металл/резина без краски
uniform float wear = 0.0;
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float pattern = 6.0;        // мелкость узоров (на метр детали)
uniform float detail = 1.0;         // шаг 92: панели, швы, вставки, потёртости (экспедиционный костюм)
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
	// шаг 92: панели и швы по сетке детали, тёмно-серые вставки на краске, фаска у шва
	vec3 cf = vec3(4.0, 6.0, 4.0);
	vec3 cell = lp * cf;
	vec3 gd = (0.5 - abs(fract(cell) - 0.5)) / cf;
	float dl = min(gd.x, gd.y);
	float seam = (1.0 - smoothstep(0.0012, 0.0035, dl)) * detail;
	float bevel = smoothstep(0.0035, 0.005, dl) * (1.0 - smoothstep(0.005, 0.008, dl)) * detail;
	if (paint > 0.5) {
		float ins = step(0.74, hash3(floor(cell) + vec3(3.1, 7.7, 1.3))) * detail;
		col = mix(col, vec3(0.14, 0.14, 0.15) * (0.9 + 0.2 * n1), ins);
		m = mix(m, 0.35, ins);
		r = mix(r, 0.62, ins);
		// мелкие метки-трафареты: тонкая белая полоска в углу некоторых панелей
		vec3 fc = fract(cell);
		float tag = step(0.86, hash3(floor(cell) + vec3(9.3, 1.1, 4.4))) * step(0.12, fc.x) * step(fc.x, 0.42) * step(0.14, fc.y) * step(fc.y, 0.2) * detail;
		col = mix(col, vec3(0.86, 0.86, 0.82), tag * (1.0 - ins));
	} else if (rough > 0.7) {
		// резина/ткань: мелкое плетение
		col *= 0.9 + 0.1 * sin(lp.x * 700.0) * sin(lp.y * 700.0 + lp.z * 300.0);
	}
	col *= 1.0 - 0.6 * seam;
	col *= 1.0 + 0.16 * bevel;
	r = mix(r, 0.85, seam);
	// шаг 124: рельеф вблизи (особенно от 1-го лица): шов — канавка, фаска — валик, по углам панелей — заклёпки,
	// сталь — шлифованная (тонкие риски), краска — лёгкая «шагрень» под лаком. Вдали рельеф гаснет (не рябит).
	float near_k = 1.0 - smoothstep(1.5, 5.0, length(VERTEX));
	float h0 = (-seam * 0.0016 + bevel * 0.0006) * near_k;
	vec2 mc = (fract(cell.xy) - 0.5) / cf.xy;                       // метры от центра панели
	vec2 half_sz = 0.5 / cf.xy - 0.016;
	float rd = length(abs(mc) - half_sz);
	float riv = (1.0 - smoothstep(0.0035, 0.0058, rd)) * step(0.35, hash3(floor(cell) + vec3(2.7, 5.1, 8.3))) * detail * step(0.5, paint + step(rough, 0.6));
	h0 += riv * 0.0018 * near_k;
	col = mix(col, steel * (0.85 + 0.25 * n1), riv * 0.9);
	col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0058, 0.0085, rd)) * (1.0 - riv) * step(0.35, hash3(floor(cell) + vec3(2.7, 5.1, 8.3))) * detail * step(0.5, paint + step(rough, 0.6));
	m = mix(m, 0.9, riv);
	r = mix(r, 0.3, riv);
	if (paint < 0.5 && rough < 0.7) {
		float brush = noise3(vec3(lp.x * 600.0, lp.y * 30.0, lp.z * 600.0));
		h0 += (brush - 0.5) * 0.00012 * near_k;
		r = clamp(r + (brush - 0.5) * 0.12 * near_k, 0.05, 1.0);
	} else if (paint > 0.5) {
		h0 += (noise3(lp * 260.0) - 0.5) * 0.00006 * near_k;
	}

	if (paint > 0.5) {
		// сколы краски — сквозь них голая сталь (чем хуже корпус, тем их больше)
		float chip = fbm(p * 3.4 + 3.1);
		float chip_t = 0.79 - wear * 0.3;
		float c = smoothstep(chip_t, chip_t + 0.02, chip);
		col = mix(col, steel * (0.75 + 0.35 * noise3(p * 7.0)), c);
		col = mix(col, col * 0.45, smoothstep(chip_t - 0.025, chip_t, chip) * (1.0 - c) * wear);   // тёмный край скола
		m = mix(m, 0.9, c);
		r = mix(r, 0.32, c);
		// ржавые подтёки
		float rust = smoothstep(0.62 - wear * 0.2, 0.82, fbm(p * 1.1 + vec3(7.7, 2.0, 1.0))) * (0.25 + wear * 0.6);
		col = mix(col, vec3(0.4, 0.19, 0.07) * (0.7 + 0.5 * noise3(p * 5.0)), rust * 0.6);
		r = mix(r, 0.85, rust * 0.55);
	}
	// потрёпанность: копоть и грязь пятнами, сетка мелких царапин по всему корпусу
	float wr = max(wear, 0.22 * detail);
	if (wr > 0.05) {
		float soot = smoothstep(0.58 - wr * 0.25, 0.9, fbm(p * 0.8 + vec3(5.0, 1.3, 8.1))) * wr;
		col *= 1.0 - soot * 0.6;
		r = mix(r, 0.9, soot * 0.6);
		float field = smoothstep(0.5, 0.72, fbm(lp * 2.3 + vec3(9.0, 4.0, 2.0))) * clamp(wr * 1.7, 0.0, 1.0);
		vec3 ax1 = normalize(vec3(0.8, 0.35, 0.45));
		vec3 ax2 = normalize(vec3(-0.3, 0.9, 0.3));
		float l1 = noise3(vec3(dot(lp, cross(ax1, vec3(0.0, 0.0, 1.0))) * 70.0, dot(lp, ax1) * 3.0, 1.7));
		float l2 = noise3(vec3(dot(lp, cross(ax2, vec3(1.0, 0.0, 0.0))) * 60.0, dot(lp, ax2) * 3.0, 4.2));
		float scr = max(smoothstep(0.66, 0.7, l1), smoothstep(0.67, 0.71, l2)) * field;
		col = mix(col, steel * 1.15, scr * (paint > 0.5 ? 0.85 : 0.45));
		m = mix(m, 0.95, scr * 0.8);
		r = mix(r, 0.25, scr * 0.8);
	}

	float h = h0;                  // рельеф (м) — швы, заклёпки, риски; дальше — вмятины и рваные края
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
			float ring = 1.0 - smoothstep(0.5, 1.5, d);
			float t = clamp((d - 0.3) / 1.0, 0.0, 1.0);
			vec3 temper = mix(vec3(0.16, 0.22, 0.55), vec3(0.42, 0.2, 0.5), smoothstep(0.0, 0.35, t));
			temper = mix(temper, vec3(0.8, 0.6, 0.25), smoothstep(0.35, 0.8, t));
			col = mix(col, temper, ring * 0.9 * str);
			col *= 1.0 - (1.0 - smoothstep(0.3, 1.6, d)) * 0.35 * str;     // копоть вокруг
			m = mix(m, 0.85, ring * str * 0.6);
			r = mix(r, 0.3, ring * str * 0.5);
			float crackle = smoothstep(0.45, 0.6, fbm(lp * (3.0 / rad) + si.w));
			col = mix(col, vec3(0.03, 0.025, 0.02) + crackle * 0.05, core * str);
			r = mix(r, 0.95, core * str);
			m = mix(m, 0.1, core * str);
			emis += vec3(1.0, 0.32, 0.05) * core * si.y * (1.5 + 3.0 * crackle);
		} else if (kind == 1) {
			// вмятина: глубокая ямка с тёмным дном, вокруг — вспученный край (светлый ободок),
			// по краю краска треснула и осыпалась
			float dent = 1.0 - smoothstep(0.0, 1.0, d);
			float lip1 = smoothstep(0.75, 1.0, d) * (1.0 - smoothstep(1.0, 1.35, d));
			h -= dent * dent * str * 0.075 * rad * 6.0;
			h += lip1 * str * 0.012 * rad * 6.0;
			float bare = (1.0 - smoothstep(0.35, 0.7, d)) * str;
			float flk = smoothstep(0.55, 0.62, noise3(lp * (22.0 / rad) * 0.12 + si.w)) * lip1 * str;
			col = mix(col, steel * 0.7, flk);
			vec3 axis = normalize(vec3(si.w, 1.0, 0.3 + fract(si.w * 3.7)));
			float lines = noise3(vec3(dot(q, axis) * (60.0 / rad) * 0.1, length(cross(q, axis)) * 2.0, si.w));
			float scr = smoothstep(0.7, 0.78, lines) * (1.0 - smoothstep(0.5, 1.6, d)) * str;
			float b = max(bare * 0.85, scr);
			col = mix(col, steel * 0.95, b);
			m = mix(m, 0.95, b);
			r = mix(r, 0.28, b);
			col *= 1.0 - dent * dent * 0.55 * str;
			col += vec3(0.18) * lip1 * str * (1.0 - flk);
		} else if (kind == 2) {
			float hole = 1.0 - smoothstep(0.2, 0.3, d);
			float lip = clamp((1.0 - smoothstep(0.28, 0.65, d)) - hole, 0.0, 1.0);
			col = mix(col, steel, lip * str);
			m = mix(m, 0.95, lip * str);
			h += (lip * 0.4 - hole) * str * 0.012;
			col = mix(col, vec3(0.01), hole * str);
			r = mix(r, 1.0, hole * str);
			emis += vec3(1.0, 0.55, 0.15) * hole * str * (0.3 + si.y * 2.0);
		} else if (kind == 3) {
			float sc = (1.0 - smoothstep(0.3, 1.2, d)) * str;
			float blot = smoothstep(0.4, 0.7, noise3(lp * (14.0 / rad) * 0.1 + si.w));
			col = mix(col, mix(vec3(0.78, 0.64, 0.36), vec3(0.46, 0.38, 0.3), blot), sc * 0.65);
			r = mix(r, 0.75, sc * 0.5);
			m = mix(m, 0.3, sc * 0.5);
		} else if (kind == 4) {
			// царапины: пучок параллельных борозд вдоль удара, краска содрана до блестящего металла
			vec3 axis = normalize(vec3(cos(si.w), sin(si.w * 1.7) * 0.5, sin(si.w)));
			float along = dot(q, axis);
			vec3 side = normalize(cross(axis, vec3(0.2, 1.0, 0.3)));
			float across = dot(q, side);
			float ell = length(vec2(along / (rad * 2.0), across / (rad * 0.65)));
			float mask = (1.0 - smoothstep(0.6, 1.05, ell + jitter * 0.4)) * str;
			float lines = noise3(vec3(across * (55.0 / rad) * 0.1, along * 0.4, si.w));
			float groove = smoothstep(0.56, 0.64, lines) * mask;
			float edge = smoothstep(0.5, 0.56, lines) * (1.0 - smoothstep(0.64, 0.72, lines)) * mask;
			col = mix(col, steel * 1.3, groove);
			col = mix(col, col * 0.35, edge * 0.8);
			m = mix(m, 0.95, groove);
			r = mix(r, 0.22, groove);
			h -= groove * 0.0015;
		} else if (kind == 5) {
			// следы мороза: краска потрескалась сеткой, побелела и местами отслоилась
			float fm = (1.0 - smoothstep(0.35, 1.25, d)) * str;
			float cr = 1.0 - smoothstep(0.0, 0.05, abs(noise3(lp * (16.0 / rad) * 0.12 + si.w) - 0.5));
			float cr2 = 1.0 - smoothstep(0.0, 0.04, abs(noise3(lp * (34.0 / rad) * 0.12 + si.w * 2.0) - 0.5));
			float flake = smoothstep(0.62, 0.7, noise3(lp * (10.0 / rad) * 0.15 + si.w * 3.0));
			col = mix(col, vec3(0.8, 0.88, 0.95), fm * 0.38);
			col = mix(col, steel * 0.9, flake * fm * 0.8);
			col = mix(col, vec3(0.22, 0.27, 0.33), max(cr, cr2 * 0.7) * fm * 0.75);
			r = mix(r, 0.7, fm * 0.5);
			emis += vec3(0.25, 0.4, 0.55) * step(0.97, noise3(lp * 90.0)) * fm * 0.4;   // искорки инея в трещинах
		} else {
			// смято давлением: складки-морщины, на гребнях краска стёрта
			vec3 axis2 = normalize(vec3(sin(si.w), 0.4, cos(si.w)));
			float wr = sin(dot(q, axis2) * (22.0 / rad) + noise3(lp * (7.0 / rad) * 0.2 + si.w) * 5.0);
			float cm = (1.0 - smoothstep(0.1, 1.25, d)) * str;
			h += wr * cm * 0.006 - cm * 0.01;
			col *= 1.0 - cm * 0.18 * (0.5 - wr * 0.5);
			float ridge = smoothstep(0.75, 1.0, wr) * cm;
			col = mix(col, steel, ridge * 0.7);
			m = mix(m, 0.9, ridge * 0.7);
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

	// шаг 124: краска — под лаком (второй, гладкий блик), по краям силуэта — мягкая подсветка (объём читается лучше)
	CLEARCOAT = 0.45 * paint * (1.0 - s) * (1.0 - clamp(wear * 1.5, 0.0, 1.0)) * step(rough, 0.6);
	CLEARCOAT_ROUGHNESS = 0.18;
	RIM = 0.12 * (1.0 - s);
	RIM_TINT = 0.6;
	ALBEDO = col;
	METALLIC = m;
	ROUGHNESS = r;
	SPECULAR = 0.5;
	EMISSION = emis;
}
