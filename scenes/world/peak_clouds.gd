extends Node3D
## Шаг 147: облака над тропой Пика.
##  * Три облачных слоя (пелена) на 262 / 284 / 306 м: плотная облачность с просветами, медленно плывёт.
##    Снизу (от моста, из пропасти с выступами) — серо-белый «потолок» с тенями в плотных местах;
##    закрывает всё, что выше (канатку, её скалы). Сверху (с плато) — море облаков внизу.
##  * Клубы (фото-облака из атласа лавины, CC0) — объём по краям и в толще слоя.
##  * Внутри слоя (≈250–330 м) — густой туман: mountain_weather (полоса «want»).
## Облака не мешают игре: без столкновений.

const ATLAS := "res://assets/avalanche/cloud_atlas.png"
const CENTER := Vector3(0.0, 0.0, -3060.0)
const LAYERS := [[228.0, 0.97, 0.0], [242.0, 0.9, 37.0], [262.0, 0.82, 71.0], [290.0, 0.72, 113.0]]   ## высота, плотность, зерно
## шаг 148: нижний слой почти сплошной и непрозрачный — сквозь него сверху ничего не видно
const PUFFS := 320

var _rng := RandomNumberGenerator.new()

const DECK_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float coverage = 0.7;
uniform float scale = 0.0021;
uniform float seed = 0.0;
uniform vec2 wind = vec2(0.0035, 0.0012);
uniform float max_alpha = 1.0;
uniform vec3 light_col : source_color = vec3(0.96, 0.97, 1.0);
uniform vec3 shade_col : source_color = vec3(0.5, 0.55, 0.65);
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.42;
	}
	s /= 0.8;
	return s;
}
float lin_depth(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wp.xz * scale + wind * TIME + vec2(seed);
	float d = fbm(p) * 0.75 + vn(p * 0.23 + vec2(3.1, 7.7)) * 0.45 - 0.12;
	float th = 1.0 - coverage;
	float a = smoothstep(th - 0.08, th + 0.12, d);
	float k = clamp((d - th) * 2.4, 0.0, 1.0);
	bool below = CAMERA_POSITION_WORLD.y < wp.y;
	// снизу плотные места — темнее (тень облака), сверху — светлее
	// снизу: края облаков светятся, середина плотных — серо-синяя тень
	vec3 col = below ? mix(light_col * 0.97, shade_col * 0.82, smoothstep(0.05, 0.9, k)) : mix(shade_col * 1.15, light_col, 0.55 + k * 0.45);
	ALBEDO = col;
	float scene = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float me = -VERTEX.z;
	float soft = clamp((scene - me) / 6.0, 0.0, 1.0);
	// (шаг 148: раньше гасил облако ближе 80 м — прямо над головой оно было полупрозрачным)
	ALPHA = clamp(a * max_alpha * soft * smoothstep(1.0, 8.0, me), 0.0, 1.0);
}
"""

const PUFF_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying float variant;
varying float fr;
varying float shade;
float lin_depth(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}
void vertex() {
	variant = INSTANCE_CUSTOM.x;
	fr = INSTANCE_CUSTOM.y;
	shade = INSTANCE_CUSTOM.z;
	float sc = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	VERTEX.xy = vec2(VERTEX.x * sc, VERTEX.y * sy);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float fi = fr;
	vec2 cellp = vec2(mod(fi, 8.0), floor(fi / 8.0));
	vec2 q = vec2(mod(variant, 2.0), floor(variant / 2.0));
	vec4 c = texture(atlas, (q * 8.0 + cellp + UV) / 16.0);
	float dens = clamp(c.r * 1.9, 0.0, 1.0);
	float light = clamp(0.45 + (0.5 - UV.y) * 0.8 + dens * 0.35, 0.0, 1.0) * shade;
	ALBEDO = mix(vec3(0.55, 0.6, 0.7), vec3(0.97, 0.98, 1.0), light);
	float scene = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float me = -VERTEX.z;
	float soft = clamp((scene - me) / 10.0, 0.0, 1.0) * smoothstep(4.0, 25.0, me);
	ALPHA = clamp(pow(c.a, 1.2) * 1.2, 0.0, 1.0) * 0.9 * soft;
}
"""


func _ready() -> void:
	_rng.seed = 147147
	var dsh := Shader.new()
	dsh.code = DECK_SHADER
	for L in LAYERS:
		var m := ShaderMaterial.new()
		m.shader = dsh
		m.set_shader_parameter("coverage", float(L[1]))
		m.set_shader_parameter("seed", float(L[2]))
		m.set_shader_parameter("wind", Vector2(0.0035, 0.0012) * (1.0 + float(L[2]) * 0.004))
		m.render_priority = -1
		var pm := PlaneMesh.new()
		pm.size = Vector2(3000.0, 3000.0)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "CloudDeck"
		add_child(mi)
		mi.global_position = Vector3(CENTER.x, float(L[0]), CENTER.z)
	_puffs()


## Клубы: в толще слоя, гуще — над тропой и у горы
func _puffs() -> void:
	if not ResourceLoader.exists(ATLAS):
		return
	var sh := Shader.new()
	sh.code = PUFF_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("atlas", load(ATLAS))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = PUFFS
	for i in PUFFS:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 1100.0
		var p := CENTER + Vector3(cos(a) * r, _rng.randf_range(222.0, 300.0), sin(a) * r)
		var w := _rng.randf_range(70.0, 150.0)
		var b := Basis.from_scale(Vector3(w, w * _rng.randf_range(0.45, 0.7), 1.0))
		mm.set_instance_transform(i, Transform3D(b, p))
		# поздние кадры атласа — облако разросшееся, пышное
		mm.set_instance_custom_data(i, Color(float(_rng.randi() % 4), float(_rng.randi_range(40, 60)), _rng.randf_range(0.85, 1.05), 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "CloudPuffs"
	add_child(mi)
