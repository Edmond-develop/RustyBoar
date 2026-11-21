shader_type spatial;
// Шаг 132: доска (щит в руках, штабель, брус) — фото-текстура досок, волокна вдоль длинной стороны бруска
uniform sampler2D wood_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float rough = 0.85;
varying vec3 lp;
varying vec3 ln;
varying vec3 sz;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 an = abs(ln);
	// длинная ось бруска — вдоль волокон (u), поперёк — полоса доски (v)
	vec2 uv;
	if (an.y > 0.5) {
		uv = vec2(lp.z + lp.x * 0.0, lp.x);
	} else if (an.x > 0.5) {
		uv = vec2(lp.z, lp.y);
	} else {
		uv = vec2(lp.x, lp.y);
	}
	uv = uv * vec2(0.45, 0.5) + vec2(0.13, 0.055);
	vec3 tx = texture(wood_tex, uv).rgb;
	ALBEDO = tx * tint;
	NORMAL_MAP = texture(wood_nrm, uv).rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
