shader_type spatial;
// Покрытие дорог и площадок ледяного каньона — у каждой развилки своё.
// UV: x — поперёк дороги (м, 0 — середина), y — вдоль дороги (м). UV2.x — полуширина дороги
// (0 — площадка: там UV — просто мировые x, z).
//   1 доски настила      2 шпалы и рельсы     3 рифлёная решётка     4 кристаллическая порода
//   5 каменные плиты     6 минеральная корка  7 стальные листы      8 ржавый лом
//   9 булыжник           10 замёрзшая рябь водопада

uniform int style = 1;
uniform float snow = 0.25;          // сколько снега намело поверх
uniform vec3 tint_a : source_color = vec3(0.5);
uniform vec3 tint_b : source_color = vec3(0.6);
uniform vec3 glow : source_color = vec3(0.0);

varying vec3 wpos;
varying vec2 edge;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	edge = UV2;
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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// x — до центра ближайшей клетки, y — до границы, z — номер клетки
vec3 voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(h21(n + g), h21(n + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = h21(n + g + 3.1);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

void fragment() {
	vec2 p = UV;
	float hw = edge.x;
	float n = fbm(wpos.xz * 0.35);
	float fine = vnoise(wpos.xz * 6.0);
	vec3 col = tint_a;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float gaps = 0.0;            // щели, куда набивается снег

	if (style == 1 || style == 2) {
		// доски поперёк дороги
		float w = style == 1 ? 0.34 : 0.9;
		float row = floor(p.y / w);
		float f = fract(p.y / w);
		float boardw = style == 1 ? 1.0 : 0.42;
		float in_board = step(f, boardw);
		float seg = floor((p.x + h21(vec2(row, 1.0)) * 5.0) / 2.6);
		float sx = fract((p.x + h21(vec2(row, 1.0)) * 5.0) / 2.6);
		float hv = h21(vec2(row, seg));
		float grain = vnoise(vec2(p.x * 1.5, p.y * 22.0 + hv * 9.0));
		vec3 wood = mix(tint_a, tint_b, hv) * (0.78 + 0.35 * grain);
		float gap = smoothstep(0.0, 0.05, f) * smoothstep(boardw, boardw - 0.05, f);
		if (style == 1) {
			gap *= smoothstep(0.0, 0.015, sx) * smoothstep(1.0, 0.985, sx);
			// гвозди у концов
			float nail = step(length(vec2((sx - 0.03) * 2.6, (f - 0.5) * w)), 0.025) + step(length(vec2((sx - 0.97) * 2.6, (f - 0.5) * w)), 0.025);
			wood = mix(wood, vec3(0.15), clamp(nail, 0.0, 1.0));
			col = mix(vec3(0.08, 0.06, 0.05), wood, gap);
			gaps = 1.0 - gap;
		} else {
			// шпалы, между ними — щебень со снегом, сверху — две стальные рельсы
			vec3 gravel = mix(vec3(0.25, 0.24, 0.23), vec3(0.45, 0.43, 0.4), fine);
			col = mix(gravel, wood, gap * in_board);
			gaps = (1.0 - in_board) * 0.8;
			float rail = step(abs(abs(p.x) - 0.75), 0.06);
			float shine = 0.6 + 0.4 * vnoise(vec2(p.y * 0.8, p.x));
			col = mix(col, vec3(0.55, 0.55, 0.58) * shine, rail);
			metal = rail * 0.9;
			rough = mix(0.85, 0.35, rail);
			gaps *= 1.0 - rail;
		}
	} else if (style == 3) {
		// рифлёная решётка: стальные полосы и тёмные прорези
		vec2 g = fract(p * vec2(4.0, 4.0));
		float slot = step(0.18, g.x) * step(g.x, 0.82) * step(0.12, g.y) * step(g.y, 0.88);
		float frame = 1.0 - slot;
		vec3 steel = mix(tint_a, tint_b, n) * (0.85 + 0.2 * fine);
		col = mix(vec3(0.03, 0.035, 0.04), steel, frame);
		// ржавые потёки
		col = mix(col, vec3(0.42, 0.2, 0.08), smoothstep(0.62, 0.8, fbm(wpos.xz * 0.8 + 5.0)) * 0.7);
		metal = frame * 0.8;
		rough = mix(0.9, 0.42, frame);
		gaps = slot * 0.7;
	} else if (style == 4) {
		// тёмная порода с кристаллами: края клеток светятся
		vec3 v = voronoi(wpos.xz * 0.9);
		float vein = 1.0 - smoothstep(0.0, 0.08, v.y);
		vec3 stone = mix(tint_a, tint_a * 1.6, v.z) * (0.7 + 0.4 * n);
		col = mix(stone, mix(tint_b, glow, v.z), vein);
		float pulse = 0.65 + 0.35 * sin(TIME * 1.3 + v.z * 6.28);
		emit = glow * vein * pulse * 1.6;
		rough = mix(0.55, 0.15, vein);
		gaps = 0.0;
	} else if (style == 5) {
		// каменные плиты вразбежку
		float rw = 1.3;
		float row = floor(p.y / rw);
		float fx = (p.x + h21(vec2(row, 7.0)) * 3.0) / 1.7;
		float seg = floor(fx);
		vec2 l = vec2(fract(fx), fract(p.y / rw));
		float joint = smoothstep(0.0, 0.035, l.x) * smoothstep(1.0, 0.965, l.x) * smoothstep(0.0, 0.03, l.y) * smoothstep(1.0, 0.97, l.y);
		float hv = h21(vec2(row, seg));
		vec3 slab = mix(tint_a, tint_b, hv) * (0.75 + 0.35 * fbm(wpos.xz * 1.7 + hv * 10.0));
		col = mix(vec3(0.12, 0.12, 0.13), slab, joint);
		gaps = 1.0 - joint;
		rough = 0.92;
	} else if (style == 6) {
		// минеральная корка: охра, сливки, бирюза; в трещинах — тёплое свечение
		vec3 v = voronoi(wpos.xz * 0.7);
		vec3 c1 = mix(tint_a, tint_b, smoothstep(0.2, 0.8, v.z));
		c1 = mix(c1, vec3(0.2, 0.62, 0.6), step(0.93, v.z));
		col = c1 * (0.75 + 0.35 * fbm(wpos.xz * 2.0));
		float crack = 1.0 - smoothstep(0.0, 0.06, v.y);
		col = mix(col, vec3(0.1, 0.05, 0.02), crack);
		emit = glow * crack * (0.6 + 0.4 * sin(TIME * 0.8 + v.z * 9.0));
		rough = 0.9;
	} else if (style == 7 || style == 8) {
		// стальные листы со швами и заклёпками; у края — предупреждающие полосы
		vec2 pl = vec2(p.x / 2.0, p.y / 1.25);
		vec2 c = fract(pl);
		vec2 id = floor(pl);
		float seam = smoothstep(0.0, 0.02, c.x) * smoothstep(1.0, 0.98, c.x) * smoothstep(0.0, 0.03, c.y) * smoothstep(1.0, 0.97, c.y);
		float hv = h21(id);
		vec3 paint = mix(tint_a, tint_b, hv) * (0.85 + 0.25 * fine);
		vec2 rv = abs(c - 0.5);
		float riv = step(0.44, max(rv.x, rv.y)) * step(fract((style == 7 ? c.x + c.y : c.x) * 8.0), 0.18);
		paint = mix(paint, paint * 1.4, riv);
		float rust = smoothstep(style == 8 ? 0.35 : 0.68, style == 8 ? 0.6 : 0.85, fbm(wpos.xz * 0.9 + 3.0));
		paint = mix(paint, vec3(0.38, 0.17, 0.07) * (0.7 + 0.5 * fine), rust);
		col = mix(vec3(0.05), paint, seam);
		if (hw > 0.0 && style == 7) {
			float band = step(hw - 0.5, abs(p.x));
			float stripe = step(0.5, fract((p.y + p.x) * 0.9));
			col = mix(col, mix(vec3(0.05), vec3(0.95, 0.68, 0.05), stripe), band * seam);
		}
		metal = (1.0 - rust) * 0.75;
		rough = mix(0.45, 0.95, rust);
		gaps = (1.0 - seam) * 0.5;
	} else if (style == 9) {
		// булыжник
		vec3 v = voronoi(wpos.xz * 1.6);
		float stone = smoothstep(0.02, 0.12, v.y);
		col = mix(vec3(0.1, 0.11, 0.13), mix(tint_a, tint_b, v.z) * (0.8 + 0.3 * fine), stone);
		gaps = 1.0 - stone;
		rough = 0.9;
	} else if (style == 10) {
		// застывшая рябь: плотный снег с голубыми волнами льда (не скользко)
		float wave = sin(p.y * 2.6 + n * 6.0 + sin(p.x * 0.7) * 1.5);
		float band = smoothstep(0.55, 0.95, wave);
		col = mix(tint_a, tint_b, band) * (0.88 + 0.18 * fine);
		rough = mix(0.8, 0.45, band);
		gaps = 0.2 * (1.0 - band);
	}

	// снег: в щелях и пятнами
	float drift = smoothstep(0.55, 0.75, n + fine * 0.15) * snow * 2.0 + gaps * snow * 1.6;
	drift = clamp(drift, 0.0, 0.92);
	col = mix(col, vec3(0.9, 0.94, 0.98), drift);
	rough = mix(rough, 0.75, drift);
	metal *= 1.0 - drift;
	emit *= 1.0 - drift * 0.8;

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
