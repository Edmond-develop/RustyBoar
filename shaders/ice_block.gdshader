shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Глыба льда, в которую вмёрз дрон. Похожа на настоящий лёд:
//  * сквозь неё видно скафандр — с преломлением (картинка позади чуть искажена гранями);
//  * толща голубеет, края и рёбра светлее;
//  * белёсые пятна инея и наледи, у основания лёд мутнее;
//  * внутри — пузырьки воздуха и плоскости трещин, блики на гранях;
//  * cracks 0..1 — трещины от ударов (растут, пока раскалываешь);
//  * crush 0..1 — глыба на дне: лёд мутнеет и трескается от давления.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float cracks : hint_range(0.0, 1.0) = 0.0;
uniform float crush : hint_range(0.0, 1.0) = 0.0;
uniform vec3 deep : source_color = vec3(0.22, 0.52, 0.70);
uniform vec3 shallow : source_color = vec3(0.80, 0.94, 1.0);
uniform float refract_amount = 0.05;

varying vec3 lp;

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int k = 0; k < 4; k++) {
		s += noise3(p) * a;
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// x — расстояние до ребра ячейки (трещина), y — до центра ячейки (пузырёк), z — id
vec3 cells(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = hash33(ip + g);
				vec3 r = g + h - fp;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = h.x;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec3(sqrt(f2) - sqrt(f1), sqrt(f1), id);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	float thick = ndv;                       // в центре глыбы лёд толще

	// иней и наледь: пятнами, у основания — сплошь
	float rime_n = fbm(lp * 2.6);
	float rime = smoothstep(0.46, 0.74, rime_n) * 0.9;
	rime = max(rime, smoothstep(-0.25, -0.75, lp.y) * (0.55 + 0.45 * rime_n));
	float fine = noise3(lp * 38.0);
	rime *= 0.75 + 0.25 * fine;

	// внутренние плоскости трещин (видны «в глубине» — смещаем по взгляду)
	vec3 vdir = normalize((inverse(MODEL_MATRIX) * vec4((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz, 0.0)).xyz);
	vec3 inner = lp - vdir * 0.22;
	vec3 c_big = cells(inner * 1.5);
	float veil = (1.0 - smoothstep(0.0, 0.03, c_big.x)) * step(0.5, c_big.z) * 0.4;
	veil *= smoothstep(0.42, 0.62, fbm(inner * 1.7 + 5.0));     // трещины-вуали — обрывками, не сеткой
	// пузырьки воздуха — мелкие белые точки, гуще внизу
	vec3 c_bub = cells(inner * 7.0 + 11.0);
	float bub_mask = step(0.72 - smoothstep(0.3, -0.6, lp.y) * 0.2, c_bub.z);
	float bubbles = (1.0 - smoothstep(0.035, 0.075, c_bub.y)) * bub_mask;
	// трещины от ударов: «включаются» всё новые рёбра ячеек
	vec3 c_hit = cells(lp * 2.8);
	float active = step(c_hit.z, cracks * 1.1);
	float hit = (1.0 - smoothstep(0.0, 0.025 + cracks * 0.04, c_hit.x)) * active * smoothstep(0.02, 0.15, cracks);
	// давление на дне: сеть мелких трещин
	vec3 c_cr = cells(lp * 6.0);
	float crushl = (1.0 - smoothstep(0.0, 0.03, c_cr.x)) * step(c_cr.z, crush) * smoothstep(0.05, 0.3, crush);
	float crackw = clamp(hit + crushl * 0.8 + veil, 0.0, 1.0);

	// преломление: картинка позади сдвинута гранями
	vec2 off = n.xy * refract_amount * (0.5 + thick);
	vec3 bg = textureLod(screen_tex, SCREEN_UV - off, 1.2).rgb;
	vec3 tint = mix(shallow, deep, clamp(thick * 0.85 + crush * 0.2, 0.0, 1.0));
	vec3 through = bg * tint * 1.25;

	float cover = clamp(rime + crackw * 0.9 + bubbles * 0.8 + fres * 0.35, 0.0, 1.0);
	vec3 white = vec3(0.9, 0.96, 1.0);
	ALBEDO = white * cover;
	EMISSION = through * (1.0 - cover * 0.85) + vec3(hit * 0.25);
	ROUGHNESS = mix(0.03, 0.6, clamp(rime + crackw * 0.3, 0.0, 1.0));
	SPECULAR = 0.95;
	METALLIC = 0.0;
	RIM = 0.4;
	RIM_TINT = 0.6;
	ALPHA = 1.0;
}
