extends Node3D
## Метель в зоне. Два режима:
##  * обычная метель (плато): туман гуще, валит снег, постоянный ветер сносит дрона,
##    иногда налетают сильные порывы;
##  * только порывы (calm_between_gusts, Ледяной лабиринт): между порывами — полный штиль,
##    ничего не видно и не дует. Порыв приходит волной: сначала по полу начинает
##    тянуть позёмку и летят первые снежинки (это предупреждение, ~1 с), потом
##    налетает метель: тысячи снежинок разного размера несутся и кружатся по ветру,
##    крупные хлопья пролетают у самой камеры, по полу текут ленты позёмки,
##    с гребней стен срывает снежные «флаги», видимость падает. Дрона толкает
##    (в первый миг — рывком), он кренится навстречу ветру и дрожит.
## Метель у каждого игрока своя (туман, снег и ветер — только для своего дрона).

@export var zone_z_max := -46.0
@export var zone_z_min := -104.0
@export var zone_half_width := 70.0
@export var environment_path: NodePath   ## WorldEnvironment
@export var max_fog := 0.06              ## Плотность тумана в самой метели (в порыв)
@export var calm_between_gusts := false  ## true — между порывами штиль, всё видно только в порыв
@export var base_wind := 1.2             ## Постоянный ветер (м/с сноса) — если не штиль
@export var gust_wind := 6.5             ## Порыв (м/с сноса)
@export var gust_interval_min := 4.5
@export var gust_interval_max := 8.0
@export var gust_warning := 1.0          ## Сколько длится «предупреждение» перед порывом
@export var gust_duration := 1.8
@export var gust_fade := 0.8             ## За сколько порыв стихает
@export var gust_kick := 0.0             ## Рывок в начале порыва (м/с)

var intensity := 0.0                     ## 1 — дрон внутри зоны
var gust := 0.0                          ## 0..1 — сила порыва прямо сейчас
var _fog_active := false

var _env: Environment
var _base_fog := 0.0
var _base_fog_color := Color.WHITE
var _snow: GPUParticles3D
var _fx: Array = []                      ## [частицы, материал, смещение от дрона по ветру, высота, наклон вниз]
var _flakes: GPUParticles3D              ## основная метель — снежинки
var _gust_kicked := false
var _haze: ColorRect
var _haze_mat: ShaderMaterial
var _haze_offset := 0.0
var _player: Node3D
var _gust_timer := 5.0
var _gust_state := 0      # 0 — тихо, 1 — предупреждение, 2 — порыв, 3 — стихает
var _gust_dir := 1.0
var _wind_dir := 1.0


const HAZE_SHADER := """
shader_type canvas_item;
// Снежная взвесь поверх экрана: рваные клубы несутся вбок, по краям гуще
uniform float amount = 0.0;
uniform float offset = 0.0;     // сдвиг по ветру (растёт со временем)
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { v += a * n(p); p *= 2.1; a *= 0.5; } return v; }
void fragment() {
	vec2 uv = UV * vec2(3.0, 1.7);
	float f = fbm(uv + vec2(offset, sin(offset * 0.3) * 0.2));
	float f2 = fbm(uv * 2.3 + vec2(offset * 1.7, 0.0));
	float cloud = smoothstep(0.42, 0.85, f * 0.65 + f2 * 0.35);
	float edge = smoothstep(0.15, 0.75, length(UV - 0.5) * 1.4);
	float a = amount * (cloud * 0.55 + edge * 0.35);
	COLOR = vec4(0.93, 0.96, 1.0, clamp(a, 0.0, 0.8));
}
"""


func _ready() -> void:
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we:
		_env = we.environment
		_base_fog = _env.fog_density
		_base_fog_color = _env.fog_light_color
	_snow = FX.particles(Color(1, 1, 1, 0.85), 2000, 1.4, 0.035, 8.0, 14.0,
		Vector3(0, -3, 0), 12.0, false)
	FX.set_box(_snow, Vector3(18.0, 8.0, 18.0))
	add_child(_snow)
	_make_veil()
	_gust_timer = randf_range(gust_interval_min, gust_interval_max)


## Текстуры частиц рисуем прямо в коде
## Снежинка: плотная середина, чёткий край (не «облачко»)
static func _flake_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.95))
	g.add_point(0.72, Color(1, 1, 1, 0.25))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


## Лента позёмки: рваные волокна, вытянутые вдоль ветра
static func _drift_texture(seed_value: int) -> Texture2D:
	var w := 256
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.0
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var fib := n.get_noise_2d(u * 3.0, v * 14.0) * 0.5 + 0.5     # волокна вдоль x
			var tear := n.get_noise_2d(u * 9.0 + 40.0, v * 4.0) * 0.5 + 0.5
			var a := smoothstep(0.45, 0.85, fib) * smoothstep(0.25, 0.6, tear)
			a *= sin(v * PI) * smoothstep(0.0, 0.25, u) * smoothstep(1.0, 0.6, u)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * 1.3, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Клочья снега, которые срывает с гребней
static func _puff_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Одна система частиц ветра. along — где центр относительно дрона против ветра (м),
## height — высота центра, ext — размер области появления (вдоль ветра, вверх, поперёк).
func _emitter(amount: int, life: float, mesh: Mesh, ext: Vector3, along: float, height: float,
		v_min: float, v_max: float, scale_min: float, scale_max: float, turb: float,
		alpha_ramp: Gradient, spin: float = 0.0, fall: float = -1.5) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-70, -12, -50), Vector3(140, 30, 100))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.gravity = Vector3(0, fall, 0)
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	if spin > 0.0:
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -spin
		pm.angular_velocity_max = spin
	if turb > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 2.5
		pm.turbulence_noise_scale = 4.0
		pm.turbulence_noise_speed = Vector3(1.5, 0.3, 0.3)
		pm.turbulence_influence_min = turb * 0.5
		pm.turbulence_influence_max = turb
	var ramp := GradientTexture1D.new()
	ramp.gradient = alpha_ramp
	pm.color_ramp = ramp
	p.process_material = pm
	p.draw_pass_1 = mesh
	add_child(p)
	_fx.append([p, pm, along, height])
	return p


func _ramp(a_in: float, a_mid: float, tail: float = 0.75) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(a_in, Color(0.97, 0.98, 1.0, a_mid))
	g.add_point(tail, Color(0.95, 0.97, 1.0, a_mid * 0.85))
	return g


func _make_veil() -> void:
	var flake := _flake_texture()
	# 1. метель: много мелких снежинок разного размера, кружатся по ветру
	_flakes = _emitter(2200, 1.6, _billboard_quad(flake, 0.1), Vector3(14.0, 4.0, 18.0), 9.0, 3.5,
		14.0, 24.0, 0.5, 1.8, 0.35, _ramp(0.08, 0.95, 0.85), 220.0, -2.5)
	# 2. крупные хлопья у самой камеры — пролетают мимо, дают глубину
	_emitter(160, 0.9, _billboard_quad(flake, 0.18), Vector3(6.0, 2.2, 7.0), 4.0, 2.4,
		18.0, 26.0, 0.8, 1.6, 0.2, _ramp(0.1, 0.9, 0.8), 160.0, -2.0)
	# 3. позёмка: ленты снега текут по самому полу
	var drift := StandardMaterial3D.new()
	drift.albedo_texture = _drift_texture(13)
	drift.vertex_color_use_as_albedo = true
	drift.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drift.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drift.cull_mode = BaseMaterial3D.CULL_DISABLED
	drift.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var dq := QuadMesh.new()
	dq.orientation = PlaneMesh.FACE_Y
	dq.size = Vector2(5.5, 1.3)
	dq.material = drift
	_emitter(220, 1.3, dq, Vector3(12.0, 0.08, 16.0), 8.0, 0.22, 10.0, 17.0, 0.7, 1.5, 0.0,
		_ramp(0.15, 0.95, 0.7), 0.0, 0.0)
	# второй слой позёмки чуть выше — завихряется
	_emitter(110, 1.1, _billboard_quad(flake, 0.05), Vector3(12.0, 0.3, 16.0), 8.0, 0.45,
		12.0, 20.0, 0.5, 1.2, 0.6, _ramp(0.1, 0.8, 0.8), 0.0, 0.6)
	# 4. «флаги»: снег срывает с гребней стен (на высоте 6–9 м)
	_emitter(90, 1.8, _billboard_quad(_puff_texture(), 1.0), Vector3(12.0, 1.2, 18.0), 5.0, 7.6,
		12.0, 18.0, 1.2, 2.8, 0.25, _ramp(0.12, 0.38, 0.6), 60.0, -1.2)
	_flakes.amount_ratio = 1.0
	# белёсая взвесь на экране — несётся по ветру
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_haze = ColorRect.new()
	_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = HAZE_SHADER
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = sh
	_haze.material = _haze_mat
	_haze.visible = false
	layer.add_child(_haze)


func _billboard_quad(tex: Texture2D, size: float) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


func _physics_process(delta: float) -> void:
	_player = Network.local_player
	if _player == null:
		return
	var p := _player.global_position
	var inside := p.z < zone_z_max and p.z > zone_z_min and absf(p.x) < zone_half_width
	intensity = move_toward(intensity, 1.0 if inside else 0.0, 0.5 * delta)

	# --- порывы ---
	var target_gust := 0.0
	if intensity > 0.3 or _gust_state != 0:
		_gust_timer -= delta
		match _gust_state:
			0:
				if _gust_timer <= 0.0:
					_gust_state = 1
					_gust_kicked = false
					_gust_timer = gust_warning
					_gust_dir = 1.0 if randf() > 0.5 else -1.0
			1:   # предупреждение: по коридору ползёт редкая пыль
				target_gust = 0.3
				if _gust_timer <= 0.0:
					_gust_state = 2
					_gust_timer = gust_duration
			2:
				target_gust = 1.0
				_player.add_shake(0.05)
				# первый удар порыва — рывок вбок
				if not _gust_kicked and intensity > 0.5:
					_gust_kicked = true
					if gust_kick > 0.0:
						_player.wind_shove(Vector3(_gust_dir, 0.0, 0.0), gust_kick)
				if _gust_timer <= 0.0:
					_gust_state = 3
					_gust_timer = gust_fade
			3:
				target_gust = 0.0
				if _gust_timer <= 0.0:
					_gust_state = 0
					_gust_timer = randf_range(gust_interval_min, gust_interval_max)
					_wind_dir = _gust_dir
	gust = move_toward(gust, target_gust, delta * (2.5 if target_gust > gust else 1.0 / maxf(gust_fade, 0.1)))

	# --- сила ветра ---
	var wind: float
	if calm_between_gusts:
		wind = _gust_dir * gust_wind * gust * gust     # в предупреждение почти не дует
	else:
		wind = _wind_dir * base_wind
		if gust > 0.0:
			wind = lerpf(wind, _gust_dir * gust_wind, gust)
	if intensity > 0.01 and absf(wind) > 0.01:
		_player.apply_wind(Vector3(wind * intensity, 0.0, 0.0))

	# --- вид: туман, снегопад, пелена ---
	var look := gust if calm_between_gusts else maxf(gust, 0.35)
	var fog_k := intensity * (gust if calm_between_gusts else 0.6 + 0.4 * gust)
	if _env and (fog_k > 0.0 or _fog_active):
		_env.fog_density = lerpf(_base_fog, max_fog, fog_k)
		_env.fog_light_color = _base_fog_color.lerp(Color(0.9, 0.93, 0.97), fog_k)
	_fog_active = fog_k > 0.0
	_snow.global_position = p + Vector3(-_gust_dir * 8.0, 5.0, 0.0)
	_snow.emitting = intensity > 0.05 and not calm_between_gusts
	_snow.amount_ratio = intensity
	var dir := _gust_dir if gust > 0.02 else _wind_dir
	var vis := intensity * look
	for e in _fx:
		var part: GPUParticles3D = e[0]
		var ppm: ParticleProcessMaterial = e[1]
		part.emitting = vis > 0.03
		part.amount_ratio = clampf(vis, 0.0, 1.0)
		part.global_position = p + Vector3(-dir * float(e[2]), float(e[3]), 0.0)
		ppm.direction = Vector3(dir, 0.0, 0.0)
		part.speed_scale = 0.75 + 0.35 * gust
	# муть на экране — несётся в ту сторону, куда дует (с точки зрения камеры)
	var cam := get_viewport().get_camera_3d()
	var side := 1.0
	if cam:
		side = signf(cam.global_basis.x.dot(Vector3(dir, 0.0, 0.0)))
		if side == 0.0:
			side = 1.0
	_haze_offset -= side * delta * (0.4 + 1.6 * gust)
	_haze.visible = vis > 0.02
	_haze_mat.set_shader_parameter("amount", vis * (0.45 if calm_between_gusts else 0.3))
	_haze_mat.set_shader_parameter("offset", _haze_offset)
	var pm := _snow.process_material as ParticleProcessMaterial
	pm.direction = Vector3(dir, -0.35, 0.0)
