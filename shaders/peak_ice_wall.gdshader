shader_type spatial;
// Шаг 127: натёчный лёд на скале — полупрозрачный (к краю тает в камень), глянец, перелив под углом,
// по льду медленно «текут» светлые блики, искорки. COLOR.a — 1 в середине натёка, 0 на краю.
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D tex_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.35;
uniform vec4 tint : source_color = vec4(0.6, 0.86, 1.0, 1.0);
uniform float glow = 0.05;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = wpos.xy * uv_scale;
	vec3 c = texture(tex_color, uv).rgb;
	vec3 c2 = texture(tex_color, uv * 0.37 + vec2(0.21, 0.6)).rgb;
	c = mix(c, c2, 0.4);
	NORMAL_MAP = texture(tex_normal, uv * vec2(1.0, 0.45)).rgb;     // вытянуто вниз — лёд натекал
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.02, 0.16, texture(tex_rough, uv).r);
	SPECULAR = 0.95;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
	float core = COLOR.a;
	ALBEDO = mix(vec3(0.16, 0.24, 0.3), c * tint.rgb * 0.62, 0.45 + 0.4 * core);
	// перелив: цвет плывёт по углу взгляда и по времени
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float ph = fres * 2.2 + TIME * 0.18 + dot(wpos.xy, vec2(0.07, 0.11)) + c.b;
	vec3 irid = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + ph));
	vec3 sheen = mix(vec3(0.6, 0.88, 1.0), irid, 0.5);
	// блики-«ручьи»: светлые полосы медленно сползают вниз
	float flow = pow(max(0.0, sin(wpos.y * 2.2 + TIME * 0.9 + sin(wpos.x * 1.7) * 1.4)), 14.0) * 0.5 * core;
	vec2 g = floor(wpos.xy * 15.0);
	float h = hash(g);
	float tw = step(0.975, h) * pow(max(0.0, sin(TIME * 2.5 + h * 50.0 + dot(VIEW, vec3(9.0, 6.0, 4.0)))), 10.0);
	EMISSION = tint.rgb * glow * (0.3 + 0.7 * c.b) * core + sheen * fres * 0.22 + vec3(0.75, 0.92, 1.0) * (flow * 0.45 + tw * 2.0);
	ALPHA = clamp(0.12 + 0.6 * smoothstep(0.0, 0.8, core) + fres * 0.25, 0.0, 0.9);     // скала просвечивает
}
