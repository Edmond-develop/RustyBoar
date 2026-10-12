shader_type spatial;
render_mode specular_schlick_ggx;
// Вздыбленный лёд торосов: глыбы и плиты, выдавленные сжатием.
//  * внизу и внутри — густой цвет толщи, к рёбрам светлеет до кромки;
//  * слои замёрзшей воды полосами, тонкие светлые трещины внутри;
//  * по краю — светлый ободок (как свет сквозь кромку льда);
//  * на всём, что смотрит вверх, лежит снег (snow_amount > 1 — снега больше);
//  * milk — мутный «молочный» лёд с белыми облачками пузырьков внутри;
//  * polish = 1 — гладкий отполированный лёд (горки): без снега, блестит.
// Разные виды льда (синий, бирюзовый, снежный, тёмный старый, молочный, ледниковый)
// — это один шейдер с разными настройками (см. hummock_builder.gd, PALETTES).
// Цвет экземпляра (MultiMesh) слегка меняет оттенок каждой глыбы.

uniform vec3 deep : source_color = vec3(0.05, 0.22, 0.4);
uniform vec3 mid : source_color = vec3(0.24, 0.56, 0.76);
uniform vec3 edge : source_color = vec3(0.8, 0.94, 1.0);
uniform vec3 snow : source_color = vec3(0.93, 0.95, 1.0);
uniform float polish = 0.0;
uniform float snow_amount = 1.0;
uniform float base_rough = 0.18;
uniform float milk = 0.0;
uniform float crack_amount = 0.45;
uniform float band_amount = 0.35;
uniform float glow = 0.06;
uniform float band_scale = 9.0;   // частота слоёв (по высоте модели)

varying vec3 wp;
varying vec3 wn;
varying vec3 lp;

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

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lp = VERTEX;
}

void fragment() {
	float n = noise3(wp * 0.6) * 0.6 + noise3(wp * 1.9) * 0.4;
	float n2 = noise3(wp * 5.0);
	// слои замёрзшей воды
	float bands = sin(lp.y * band_scale + n * 5.0) * 0.5 + 0.5;
	vec3 col = mix(deep, mid, smoothstep(0.15, 0.85, n * (1.0 - band_amount) + bands * band_amount + clamp(lp.y, 0.0, 4.0) * 0.12));
	// трещины внутри — тонкие светлые жилки
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(noise3(wp * 1.3 + 7.0) - 0.5));
	col = mix(col, edge, crack * crack_amount);
	// мутный лёд: облачка пузырьков
	float cloud = smoothstep(0.45, 0.8, noise3(wp * 2.6 + 3.0) * 0.7 + n2 * 0.3);
	col = mix(col, edge * 0.95, cloud * milk);
	// светлый ободок по краю
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col = mix(col, edge, fres * 0.55);
	// снег сверху (чем больше snow_amount, тем ниже по склонам он лежит)
	float thr = mix(0.5, 0.18, clamp(snow_amount - 1.0, 0.0, 1.0));
	float up = smoothstep(thr, thr + 0.32, wn.y + (n2 - 0.5) * 0.35) * min(snow_amount, 1.0) * (1.0 - polish);
	col = mix(col, snow * (0.92 + 0.1 * n2), up);
	col *= COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = mix(mix(base_rough + cloud * milk * 0.25, 0.04, polish), 0.85, up);
	SPECULAR = mix(0.55, 0.8, polish);
	// слабое свечение толщи льда (как просвет)
	EMISSION = mid * (glow + 0.05 * polish) * (1.0 - up);
}
