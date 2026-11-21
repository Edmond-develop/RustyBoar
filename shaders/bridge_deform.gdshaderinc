// Шаг 102: форма старого моста — та же формула, что в mountain_chasm.gd (_frame): провис, раскачка, крен.
// Меш хранит точки «в координатах моста» (поперёк, вверх, t вдоль 0…1) — видеокарта сама гнёт его каждый кадр.
uniform vec3 br_a;
uniform vec3 br_b;
uniform vec3 br_side;
uniform float br_sag;
uniform float br_sway;
uniform float br_roll;
uniform float br_len = 70.0;
uniform float br_wave = 0.0;
uniform float br_phase = 0.0;
uniform float br_e = 0.0;          // концы на пятах — прямые (шаг 105)

void br_frame(float t, out vec3 o, out vec3 sd, out vec3 up, out vec3 tg) {
	float u = clamp((t - br_e) / (1.0 - 2.0 * br_e), 0.0, 1.0);
	float ins = (t > br_e && t < 1.0 - br_e) ? 1.0 / (1.0 - 2.0 * br_e) : 0.0;
	float sw = sin(PI * u);
	o = mix(br_a, br_b, t) - vec3(0.0, 1.0, 0.0) * br_sag * 4.0 * u * (1.0 - u) + br_side * br_sway * sw
		+ vec3(0.0, 1.0, 0.0) * 0.4 * br_wave * sin(br_phase * 1.3 - t * 9.0) * sw;
	tg = normalize((br_b - br_a) + (-vec3(0.0, 1.0, 0.0) * br_sag * 4.0 * (1.0 - 2.0 * u) + br_side * br_sway * PI * cos(PI * u)) * ins);
	sd = normalize(br_side - tg * dot(br_side, tg));
	up = cross(tg, sd);
	if (up.y < 0.0) {
		sd = -sd;
		up = -up;
	}
	float r = (br_roll + radians(15.0) * br_wave * sin(br_phase * 1.9 - t * 7.0)) * sw;
	vec3 sd2 = sd * cos(r) + up * sin(r);
	vec3 up2 = up * cos(r) - sd * sin(r);
	sd = sd2;
	up = up2;
}
