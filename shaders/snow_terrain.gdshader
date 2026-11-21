shader_type spatial;
render_mode cull_disabled;
// Земля всего мира (рельеф terrain.gd). Настоящие текстуры с объёмом (нормали):
//  * Борея: снег с ветровой рябью, на крутых склонах — слоистые скалы;
//    в глубине ущелий — голубой лёд; на снегу искрятся снежинки;
//  * база (юг): инопланетный мох подушками, голая влажная почва с камешками,
//    фиолетовый лишайник; снег на переходе держится пятнами;
//  * место крушения: выжженная земля, пепел и тлеющие угли вдоль борозды.
// Скалы натягиваются с трёх сторон (не растягиваются на отвесных стенах).
// Чтобы плитка текстуры не повторялась заметно, каждая текстура смешивается
// сама с собой в другом масштабе.

uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
// шаг 132: в горах (ледник, мост) — второй снег, фото-текстура ambientCG Snow013: наст, гребни от ветра
uniform sampler2D snow2_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow2_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float snow2_on = 0.0;

uniform float ground_scale = 0.3;     // плиток на метр: 0.3 — плитка ~3.3 м
uniform float rock_scale = 0.12;
uniform float normal_strength = 1.1;

uniform vec3 snow_tint : source_color = vec3(0.72, 0.75, 0.82);
uniform vec3 rock_tint : source_color = vec3(1.0, 1.02, 1.1);
uniform vec3 alien_rock_tint : source_color = vec3(0.62, 0.58, 0.68);
uniform vec3 moss_tint : source_color = vec3(1.25, 1.25, 1.25);
uniform vec3 soil_tint : source_color = vec3(1.6, 1.5, 1.5);
uniform vec3 violet_color : source_color = vec3(0.42, 0.2, 0.62);
uniform vec3 ice_color : source_color = vec3(0.42, 0.7, 0.92);
uniform float sparkle_amount = 1.6;
// Ледяной каньон: в этом прямоугольнике (x0, z0, x1, z1) скалы — это слоистый лёд
uniform vec4 ice_wall_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform float meadow_start_z = 545.0;
// Шаг 73: Пик — севернее этой z скалы альпийские: гранит со слоями, светлые потёки льда,
// снег цепляется за уступы пятнами, выше — больше снега
uniform float peak_z = -2620.0;
// шаг 143: пропасть у Снежной горы — та же «настоящая» скала, что на Пике (z от y до w)
uniform vec4 granite_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform float meadow_full_z = 615.0;

// Место крушения (задаёт terrain.gd): борозда от носа до хвоста + пятно вокруг корабля
uniform vec2 crash_nose = vec2(0.0, 1104.0);
uniform vec2 crash_tail = vec2(12.0, 1204.0);
uniform float scorch_width = 7.5;
uniform float scorch_ship = 17.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Текстура в двух масштабах — прячет повторы
vec3 tex2(sampler2D t, vec2 p) {
	vec3 a = texture(t, p).rgb;
	vec3 b = texture(t, p * 0.27 + vec2(0.37, 0.71)).rgb;
	return mix(a, b, 0.35) * (0.85 + 0.3 * vnoise(p * 0.11));
}

// Нормаль из карты: только наклон (x, y), «вверх» восстанавливаем
vec2 nrm2(sampler2D t, vec2 p) {
	vec2 a = texture(t, p).rg * 2.0 - 1.0;
	vec2 b = texture(t, p * 0.27 + vec2(0.37, 0.71)).rg * 2.0 - 1.0;
	return a + b * 0.5;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 N = normalize(world_normal);
	vec2 gp = world_pos.xz * ground_scale;
	float n = vnoise(world_pos.xz * 0.12) * 0.6 + vnoise(world_pos.xz * 0.7) * 0.4;
	float big = vnoise(world_pos.xz * 0.035);

	// --- Какая где поверхность ---
	float slope = 1.0 - N.y;
	float rock = smoothstep(0.30, 0.48, slope + (n - 0.5) * 0.12);
	float meadow = smoothstep(meadow_start_z, meadow_full_z, world_pos.z + (big - 0.5) * 40.0 + (n - 0.5) * 8.0);
	float deep = smoothstep(-2.0, -12.0, world_pos.y);

	// --- Снег ---
	vec3 snow = tex2(snow_tex, gp * 0.8) * snow_tint;
	vec2 snow_n = nrm2(snow_nrm, gp * 0.8);
	if (snow2_on > 0.5) {
		float hk = smoothstep(50.0, 100.0, world_pos.y);
		float w2 = hk * (0.55 + 0.4 * vnoise(world_pos.xz * 0.025 + 13.0));
		vec3 s2 = tex2(snow2_tex, gp * 0.5) * snow_tint * 1.08;
		snow = mix(snow, s2, w2);
		snow_n = mix(snow_n, nrm2(snow2_nrm, gp * 0.5) * 1.2, w2);
	}

	// --- Луг: мох, голая почва (пятнами), фиолетовый лишайник ---
	vec3 moss = tex2(moss_tex, gp) * moss_tint;
	vec2 moss_n = nrm2(moss_nrm, gp) * 0.7;
	vec3 soil = tex2(soil_tex, gp * 1.3) * soil_tint;
	vec2 soil_n = nrm2(soil_nrm, gp * 1.3);
	float patch = vnoise(world_pos.xz * 0.09 + 7.0);
	float bare = smoothstep(0.6, 0.78, vnoise(world_pos.xz * 0.06 + 3.0) * 0.7 + n * 0.3);
	float lichen = smoothstep(0.74, 0.86, patch);
	vec3 violet = dot(moss, vec3(0.3, 0.5, 0.2)) * violet_color * 3.2;
	vec3 meadow_col = mix(moss, violet, lichen * 0.5);
	meadow_col = mix(meadow_col, soil, bare);
	vec2 meadow_n = mix(moss_n, soil_n, bare);

	// На переходе снег лежит пятнами: в ложбинках мха дольше
	float snow_left = clamp((1.0 - meadow) * 1.6 - (moss.g * 2.0 - 0.3) * 0.4, 0.0, 1.0);
	snow_left = smoothstep(0.35, 0.65, snow_left);
	vec3 ground = mix(meadow_col, snow, snow_left);
	vec2 ground_n = mix(meadow_n, snow_n, snow_left);

	// --- Скалы (с трёх сторон) ---
	vec3 w = pow(abs(N), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 rp = world_pos * rock_scale;
	vec3 rock_col = texture(rock_tex, rp.zy).rgb * w.x + texture(rock_tex, rp.xz).rgb * w.y + texture(rock_tex, rp.xy).rgb * w.z;
	rock_col *= mix(rock_tint, alien_rock_tint, meadow);
	vec2 rnx = texture(rock_nrm, rp.zy).rg * 2.0 - 1.0;
	vec2 rny = texture(rock_nrm, rp.xz).rg * 2.0 - 1.0;
	vec2 rnz = texture(rock_nrm, rp.xy).rg * 2.0 - 1.0;
	vec3 rock_pert = vec3(0.0, rnx.y, rnx.x) * w.x + vec3(rny.x, 0.0, rny.y) * w.y + vec3(rnz.x, rnz.y, 0.0) * w.z;

	// стены ущелий каньона — синий слоистый лёд с трещинами
	float in_ice = step(ice_wall_rect.x, world_pos.x) * step(world_pos.x, ice_wall_rect.z)
		* step(ice_wall_rect.y, world_pos.z) * step(world_pos.z, ice_wall_rect.w);
	if (in_ice > 0.5) {
		float strata = sin(world_pos.y * 0.9 + vnoise(world_pos.xz * 0.05) * 6.0) * 0.5 + 0.5;
		float vein = 1.0 - smoothstep(0.0, 0.04, abs(vnoise(world_pos.xz * 0.21 + world_pos.y * 0.13) - 0.5));
		vec3 ice_wall = mix(vec3(0.07, 0.24, 0.42), vec3(0.36, 0.64, 0.84), strata * 0.65 + n * 0.35);
		ice_wall = mix(ice_wall, vec3(0.8, 0.93, 1.0), vein * 0.22);
		rock_col = mix(rock_col, ice_wall, 0.88);
	}
	// --- Пик: настоящие горные скалы ---
	float alp = smoothstep(peak_z + 30.0, peak_z - 30.0, world_pos.z);
	float in_gr = smoothstep(granite_rect.x - 20.0, granite_rect.x, world_pos.x) * smoothstep(granite_rect.z + 20.0, granite_rect.z, world_pos.x)
		* smoothstep(granite_rect.y - 4.0, granite_rect.y + 4.0, world_pos.z) * smoothstep(granite_rect.w + 4.0, granite_rect.w - 4.0, world_pos.z);
	alp = max(alp, in_gr);
	if (alp > 0.001) {
		float steep = smoothstep(0.35, 0.9, slope);
		// та же порода крупнее (без мелкой «древесной» ряби) + серо-бурый гранит
		vec3 rp2 = world_pos * 0.042;
		vec3 big_rock = texture(rock_tex, rp2.zy).rgb * w.x + texture(rock_tex, rp2.xz).rgb * w.y + texture(rock_tex, rp2.xy).rgb * w.z;
		vec3 base_r = mix(rock_col, big_rock, 0.6);
		float lum = dot(base_r, vec3(0.3, 0.5, 0.2));
		vec3 granite = mix(vec3(lum), base_r, 0.3) * vec3(0.96, 0.9, 0.85) * 0.8;
		// слои породы (наклонные) — мягко
		float sn = vnoise(world_pos.xz * 0.018) * 6.0 + vnoise(world_pos.xz * 0.07) * 1.5;
		float strata = sin(world_pos.y * 0.33 + world_pos.x * 0.04 + sn) * 0.5 + 0.5;
		granite *= mix(0.82, 1.1, strata);
		// большие пятна: тёмные (лишайник, мокрая скала) и ржавые
		float blot = vnoise(world_pos.xz * 0.03 + world_pos.y * 0.015);
		granite *= mix(0.78, 1.12, blot);
		float stain = smoothstep(0.6, 0.82, vnoise(world_pos.xz * 0.045 + world_pos.y * 0.03 + 11.0));
		granite = mix(granite, granite * vec3(0.85, 0.66, 0.5), stain * 0.5);
		// потёки льда по кулуарам — широкие, мягкие
		float streak = smoothstep(0.62, 0.85, vnoise(vec2(world_pos.x * 0.12 + world_pos.z * 0.12, world_pos.y * 0.012)));
		granite = mix(granite, vec3(0.8, 0.86, 0.94), streak * steep * 0.35);
		rock_col = mix(rock_col, granite, alp);
		// снег на уступах — крупными пятнами; чем выше — тем больше
		float hi = smoothstep(150.0, 600.0, world_pos.y);
		float cn = vnoise(world_pos.xz * 0.035 + world_pos.y * 0.02) * 0.7 + vnoise(world_pos.xz * 0.11) * 0.3;
		float cling = smoothstep(0.54, 0.7, N.y + (cn - 0.5) * 0.45 + hi * 0.1);
		rock *= 1.0 - cling * 0.92 * alp;
	}
	vec3 col = mix(ground, rock_col, rock);
	vec3 pert = mix(vec3(ground_n.x, 0.0, ground_n.y), rock_pert * 1.4, rock);

	// Глубина трещин и ущелий — голубой лёд
	col = mix(col, ice_color * (0.6 + 0.4 * n), deep * 0.85);
	// Пропасть каньона: чем глубже, тем темнее — видно, что дна не достать
	col *= mix(1.0, mix(0.16, 0.62, in_gr), smoothstep(-22.0, -58.0, world_pos.y));

	// --- Выжженная земля у места крушения ---
	vec2 ab = crash_tail - crash_nose;
	float t = clamp(dot(world_pos.xz - crash_nose, ab) / dot(ab, ab), 0.0, 1.0);
	float d_line = length(world_pos.xz - (crash_nose + ab * t));
	float d_ship = length(world_pos.xz - (crash_nose + normalize(ab) * 12.0));
	float edge_n = (vnoise(world_pos.xz * 0.45) - 0.5) * 4.0 + (vnoise(world_pos.xz * 1.7) - 0.5) * 1.5;
	float width = scorch_width * mix(1.0, 0.45, t);
	float scorch = max(1.0 - smoothstep(width * 0.55, width, d_line + edge_n),
		1.0 - smoothstep(scorch_ship * 0.6, scorch_ship, d_ship + edge_n * 1.5));
	scorch *= smoothstep(0.98, 0.9, t);
	vec3 ash = mix(vec3(0.025, 0.02, 0.02), vec3(0.2, 0.18, 0.17), smoothstep(0.55, 0.85, vnoise(world_pos.xz * 2.3)));
	vec3 burnt = mix(soil * 0.35, ash, 0.7);
	col = mix(col, burnt, scorch * 0.92 * (1.0 - rock * 0.5));
	pert = mix(pert, vec3(soil_n.x, 0.0, soil_n.y), scorch * 0.7);

	// --- Нормаль: наклон из текстур поверх формы рельефа ---
	float snowy = (1.0 - meadow) * (1.0 - rock) + snow_left * meadow;
	vec3 nw = normalize(N + pert * normal_strength * mix(1.0, 3.5, snowy));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	ALBEDO = col;
	float snowness = (1.0 - meadow) * (1.0 - rock) + snow_left * meadow;
	ROUGHNESS = mix(mix(0.85, 0.65, snowness), 0.95, rock);
	SPECULAR = mix(0.3, 0.5, snowness);

	// Искорки на снегу
	float g = hash(floor(world_pos.xz * 14.0) + floor(world_pos.y * 14.0));
	float sparkle = step(0.997, g) * (1.0 - rock) * (1.0 - deep) * snowness;
	// Тлеющие угли в выжженной земле: мерцают, гаснут и разгораются
	vec2 ec = floor(world_pos.xz * 3.0);
	float ember = step(0.93, hash(ec + 13.0)) * smoothstep(0.55, 0.9, scorch);
	float glow = 0.5 + 0.5 * sin(TIME * (1.5 + hash(ec) * 2.5) + hash(ec + 3.0) * 6.28);
	float spot = 1.0 - smoothstep(0.1, 0.38, length(fract(world_pos.xz * 3.0) - 0.5));
	EMISSION = vec3(sparkle * sparkle_amount) + vec3(1.0, 0.32, 0.05) * ember * glow * spot * 2.5;
}
