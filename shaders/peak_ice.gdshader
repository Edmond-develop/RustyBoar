shader_type spatial;
// Шаг 122: лёд на ночной дороге — фототекстура льда (TextureCan Ice 0002), блеск, радужный перелив под углом, искорки
render_mode cull_disabled;

uniform sampler2D tex_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.22;
uniform vec4 tint : source_color = vec4(0.62, 0.85, 1.0, 1.0);
uniform float glow = 0.22;          // светится сам — видно в темноте
uniform float sparkle = 2.6;
uniform bool wall_uv = false;      // шаг 123: лёд на отвесной стене — текстура по x/y

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = (wall_uv ? wpos.xy : wpos.xz) * uv_scale;
	vec3 c = texture(tex_color, uv).rgb;
	vec3 c2 = texture(tex_color, uv * 0.31 + vec2(0.37, 0.11)).rgb;
	c = mix(c, c2, 0.35);
	NORMAL_MAP = texture(tex_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.9;
	float r = texture(tex_rough, uv).r;
	ROUGHNESS = mix(0.03, 0.22, r);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
	ALBEDO = c * tint.rgb * 0.8;
	// под углом — радужный перелив (как на тонком льду), медленно «течёт»
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float ph = fres * 3.0 + TIME * 0.25 + dot(wall_uv ? wpos.xy : wpos.xz, vec2(0.045, 0.07)) + c.b * 1.5;
	vec3 irid = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + ph));
	// искорки: мелкие кристаллы вспыхивают, когда смотришь под нужным углом
	vec2 g = floor((wall_uv ? wpos.xy : wpos.xz) * 14.0);
	float h = hash(g);
	float tw = step(0.975, h) * pow(max(0.0, sin(TIME * 2.5 + h * 50.0 + dot(VIEW, vec3(9.0, 6.0, 4.0)))), 10.0);
	// перелив — лёгкий, с голубым уклоном (не «бензиновая лужа»)
	vec3 sheen = mix(vec3(0.55, 0.85, 1.0), irid, 0.35);
	EMISSION = tint.rgb * glow * (0.35 + 0.65 * c.b) + sheen * fres * 0.18 + vec3(0.8, 0.95, 1.0) * tw * sparkle;
}
