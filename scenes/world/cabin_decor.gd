extends RefCounted
## Материалы и картинки для избы «Борея-4» (шаг 55): брёвна с волокнами и годичными кольцами на торцах,
## дощатый пол, каменная кладка камина, гобелен с узором, картины в рамах.
## Всё рисуется кодом — внешних текстур не нужно.

const LOG_SHADER := """
shader_type spatial;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec3 wood_light = vec3(0.56, 0.37, 0.2);
uniform vec3 wood_dark = vec3(0.3, 0.18, 0.09);
uniform vec3 end_light = vec3(0.82, 0.64, 0.4);
uniform vec3 end_dark = vec3(0.5, 0.33, 0.17);
uniform vec3 bark = vec3(0.22, 0.14, 0.08);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 col;
	if (UV.y > 0.5) {
		// торец: годичные кольца вокруг сердцевины
		vec2 c = vec2(UV.x < 0.5 ? 0.25 : 0.75, 0.75);
		float d = length(UV - c) * 4.0;
		float n = texture(noise, UV * 2.0 + wp.xz * 0.37).r;
		float ring = fract(d * 6.0 + n * 0.7);
		col = mix(end_light, end_dark, smoothstep(0.62, 0.95, ring) * 0.8);
		col = mix(col, end_dark * 0.7, smoothstep(0.05, 0.0, d));
		col = mix(col, bark, smoothstep(0.84, 0.92, d));
		// трещинка-усушка
		float ang = atan(UV.y - c.y, UV.x - c.x);
		col *= 1.0 - 0.6 * smoothstep(0.035, 0.0, abs(ang - 1.1 - n * 0.3)) * step(d, 0.8);
		ROUGHNESS = 0.92;
	} else {
		// бок бревна: продольные волокна, сучки
		float along = wp.y * 0.6 + (wp.x + wp.z) * 0.35;
		float n = texture(noise, vec2(UV.x * 1.3, along * 0.25)).r;
		float n2 = texture(noise, vec2(UV.x * 3.1 + 0.37, along * 1.7)).r;
		float g = fract(UV.x * 11.0 + n * 2.2);
		col = mix(wood_light, wood_dark, smoothstep(0.55, 1.0, g) * 0.55 + (n2 - 0.5) * 0.35);
		float knot = smoothstep(0.78, 0.86, texture(noise, vec2(UV.x * 0.9, along * 0.45) + 0.5).r);
		col = mix(col, wood_dark * 0.6, knot * 0.8);
		// свет на «спине» бревна чуть светлее, в стыках — тень
		col *= 0.75 + 0.35 * clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) * 0.5 + 0.6, 0.0, 1.0);
		ROUGHNESS = 0.85;
	}
	ALBEDO = col;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec3 along = vec3(1.0, 0.0, 0.0);
uniform float board = 0.22;
uniform vec3 c1 = vec3(0.62, 0.43, 0.25);
uniform vec3 c2 = vec3(0.47, 0.31, 0.17);
varying vec3 wp;
float h(float x) { return fract(sin(x * 91.7) * 4375.85); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 side = normalize(cross(along, vec3(0.0, 1.0, 0.0)));
	float a = dot(wp, along);
	float b = dot(wp, side) + wp.y * 0.0;
	float row = floor(b / board);
	float fb = fract(b / board);
	float len = 2.4;
	float aa = a + h(row) * len;
	float fa = fract(aa / len);
	float id = row * 7.0 + floor(aa / len);
	vec3 col = mix(c1, c2, h(id) * 0.7);
	float n = texture(noise, vec2(a * 0.15, b * 2.2 + row * 0.31)).r;
	col *= 0.85 + 0.3 * fract(n * 3.0 + b * 9.0) * 0.6;
	float gap = max(smoothstep(0.06, 0.0, fb), smoothstep(0.94, 1.0, fb));
	gap = max(gap, smoothstep(0.01, 0.0, fa) + smoothstep(0.99, 1.0, fa));
	col = mix(col, c2 * 0.35, clamp(gap, 0.0, 1.0));
	// гвоздики
	float nail = step(length(vec2((fa - 0.02) * len, (fb - 0.5) * board)), 0.012);
	col = mix(col, vec3(0.1), nail);
	ALBEDO = col;
	ROUGHNESS = 0.75;
}
"""

const STONE_SHADER := """
shader_type spatial;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
varying vec3 wp;
varying vec3 wn;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 p;
	vec3 an = abs(wn);
	if (an.y > an.x && an.y > an.z) p = wp.xz;
	else if (an.x > an.z) p = vec2(wp.z, wp.y);
	else p = vec2(wp.x, wp.y);
	float rh = 0.2;
	float row = floor(p.y / rh);
	float sw = 0.34 + h(vec2(row, 1.0)) * 0.12;
	float px = p.x + h(vec2(row, 7.0)) * sw;
	vec2 cell = vec2(floor(px / sw), row);
	vec2 f = vec2(fract(px / sw), fract(p.y / rh));
	float m = min(min(f.x, 1.0 - f.x) * sw, min(f.y, 1.0 - f.y) * rh);
	float n = texture(noise, p * 1.7).r;
	vec3 base = mix(vec3(0.46, 0.43, 0.4), vec3(0.62, 0.56, 0.5), h(cell));
	base = mix(base, vec3(0.38, 0.33, 0.3), h(cell + 3.1) * 0.5);
	base *= 0.82 + n * 0.35;
	vec3 mortar = vec3(0.22, 0.2, 0.19);
	vec3 col = mix(mortar, base, smoothstep(0.012, 0.028 + n * 0.01, m));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""

static var _noise: NoiseTexture2D


static func noise() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02
		fn.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = fn
	return _noise


static func shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise", noise())
	return m


static func logs_mat() -> ShaderMaterial:
	return shader_mat(LOG_SHADER)


static func floor_mat(along: Vector3) -> ShaderMaterial:
	var m := shader_mat(FLOOR_SHADER)
	m.set_shader_parameter("along", along)
	return m


static func stone_mat() -> ShaderMaterial:
	return shader_mat(STONE_SHADER)


static func tex_mat(img: Image, emit := 0.0) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.95
	if emit > 0.0:
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = emit
	return m


## Гобелен: тёмно-красное полотно, золотая кайма, ромбы-«обереги» рядами, бахрома внизу
static func tapestry() -> Image:
	var w := 96
	var h := 132
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var red := Color(0.5, 0.08, 0.07)
	var dred := Color(0.33, 0.05, 0.05)
	var gold := Color(0.88, 0.66, 0.22)
	var cream := Color(0.92, 0.86, 0.72)
	var blue := Color(0.16, 0.26, 0.5)
	var green := Color(0.2, 0.38, 0.22)
	for y in h:
		for x in w:
			var c := red
			var fy := y
			if fy >= h - 10:
				# бахрома
				c = gold.darkened(0.25) if x % 3 != 0 else Color(0.12, 0.08, 0.06)
				img.set_pixel(x, y, c)
				continue
			var bx := mini(x, w - 1 - x)
			var by := mini(fy, h - 11 - fy)
			var b := mini(bx, by)
			if b < 3:
				c = dred
			elif b < 6:
				c = gold
			elif b < 8:
				c = cream if ((x + fy) / 2) % 2 == 0 else blue
			elif b < 10:
				c = gold
			else:
				# поле: ромбы в шахматном порядке
				var cx := (x - 10) % 19 - 9
				var cyr := (fy - 10) % 22 - 11
				var row := (fy - 10) / 22
				var col := (x - 10) / 19
				var d := absi(cx) + absi(cyr)
				var alt := (row + col) % 2 == 0
				if d < 3:
					c = gold
				elif d < 5:
					c = cream
				elif d < 7:
					c = blue if alt else green
				elif d == 8:
					c = gold
				else:
					c = red if (x + fy) % 7 != 0 else dred
			img.set_pixel(x, y, c)
	return img


## Картина маслом: kind 0 — горы на закате с ёлками; 1 — северное сияние над избой
static func painting(kind: int) -> Image:
	var w := 112 if kind == 0 else 80
	var h := 80 if kind == 0 else 104
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var t := float(y) / h
		for x in w:
			var c: Color
			if kind == 0:
				c = Color(0.95, 0.55, 0.25).lerp(Color(0.35, 0.3, 0.55), 1.0 - t * 1.6)
				var sun := Vector2(x - w * 0.68, y - h * 0.42).length()
				if sun < 9.0:
					c = Color(1.0, 0.86, 0.55)
				var mtn := h * 0.5 - 12.0 * absf(sin(x * 0.045 + 0.6)) - 6.0 * sin(x * 0.17)
				if y > mtn:
					c = Color(0.3, 0.32, 0.45)
					if y < mtn + 5.0 + 2.0 * sin(x * 0.4):
						c = Color(0.92, 0.9, 0.95)
				if y > h * 0.72:
					c = Color(0.88, 0.88, 0.95).darkened(0.1 * sin(x * 0.2 + y * 0.3))
				for tr in [[14, 0.78, 14.0], [26, 0.8, 11.0], [86, 0.76, 16.0], [98, 0.82, 10.0]]:
					var tx: float = tr[0]
					var base: float = float(tr[1]) * h
					var th: float = tr[2]
					if y < base and y > base - th and absf(x - tx) < (y - (base - th)) * 0.38:
						c = Color(0.1, 0.22, 0.14)
			else:
				c = Color(0.03, 0.05, 0.14).lerp(Color(0.1, 0.12, 0.28), t)
				var band := absf(y - (h * 0.3 + 10.0 * sin(x * 0.09) + 5.0 * sin(x * 0.23)))
				if band < 9.0:
					c = c.lerp(Color(0.25, 0.95, 0.55), (1.0 - band / 9.0) * 0.8)
				var band2 := absf(y - (h * 0.18 + 8.0 * sin(x * 0.07 + 2.0)))
				if band2 < 5.0:
					c = c.lerp(Color(0.6, 0.35, 0.9), (1.0 - band2 / 5.0) * 0.6)
				if (x * 37 + y * 91) % 97 == 0 and y < h * 0.6:
					c = Color(1, 1, 0.9)
				if y > h * 0.74 - 3.0 * sin(x * 0.08):
					c = Color(0.75, 0.8, 0.92)
				# избушка с огоньком
				var hx := x - w * 0.5
				var hy := y - h * 0.68
				if absf(hx) < 9.0 and hy > -4.0 and hy < 8.0:
					c = Color(0.3, 0.18, 0.1)
					if absf(hx - 3.0) < 2.0 and absf(hy - 2.0) < 2.0:
						c = Color(1.0, 0.75, 0.3)
				if hy <= -4.0 and hy > -12.0 and absf(hx) < (hy + 12.0) * 1.3:
					c = Color(0.9, 0.92, 1.0)
			img.set_pixel(x, y, c)
	return img
