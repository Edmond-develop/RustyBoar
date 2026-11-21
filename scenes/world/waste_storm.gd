extends "res://scenes/world/blizzard.gd"
## Метель Снежной пустоши (шаг 50). У каждого игрока своя (туман, снег, ветер — для своего дрона),
## но сила метели (по месту) и порывы (по общему времени игры) — одинаковые у всех.
##
##  * Сила — WasteLayout.storm(z): у каньона лёгкий снег, к середине белая мгла (видно 2–3 вешки),
##    у Лавинного склона стихает.
##  * Постоянный ветер в лицо и вбок; раз в ~24 с — порыв: за 2.4 с гул и позёмка (без надписей),
##    потом ~5 с ураган (18 м/с — быстрее бега) — уносит назад и вбок на 130–150 м.
##  * Порыв швырнул на скалу, вешку, монолит — удар бьёт по корпусу (10–20%, по разу на препятствие).
##  * В порыв сыплет град (только картинка и стук — без урона). Сам ветер урона не наносит,
##    но если порыв бросит на скалу или вешку — удар бьёт по корпусу, как обычно.
##  * Мороз: в метели корпус медленно обмерзает (player.air_cold); отогреться — у огня
##    (лагерь, метеобудка, костры у скал). Дошло до предела — вмёрз в глыбу.
##  * Снег: тонкие косые штрихи по ветру (шейдер вытягивает их по скорости) и кружащиеся хлопья.
##  * Защита: присесть (Ctrl), держаться за вешку или леер, укрыться за скалой/стеной/вездеходом,
##    быть рядом с другом или в связке верёвкой. Всё складывается.
##  * Звук ветра — шум, который сам генерируется (воет сильнее в порыв).

const W := preload("res://scenes/world/waste_layout.gd")
const CYCLE := 24.0
const WARN := 2.4
const GUST := 5.2
const FADE := 2.0
const GUST_SPEED := 18.0           ## м/с в самый сильный порыв (бег — 11.5: против не пробежать)
const ROCK_ROOM := 2                ## сколько дронов прячется за одной скалой
const COLD := 0.045                ## обмерзание в белой мгле, ед./с (предел 12, черта 70% — ~3 мин)
const STORM_FOG := 0.085           ## туман в белой мгле (без порыва)
const GUST_FOG := 0.06             ## добавка в порыв

var waste: Node3D                  ## snow_waste.gd (вешки, леер)
var calm := false                  ## для проверок: без порывов
var no_cold := false               ## для проверок: без мороза
var protection := 1.0              ## последний множитель ветра (1 — ничем не защищён)
var protect_why := ""
var wind_now := Vector3.ZERO       ## какой ветер сейчас прикладываем (м/с)
var gust_phase := 0                ## 0 — тихо, 1 — гул (предупреждение), 2 — порыв, 3 — стихает
var gust_dir := Vector2.ZERO

var sheltered := false             ## за укрытием (от ветра, града и отчасти мороза)
var hail_hits := 0
var slam_hits := 0
var _slammed := {}                 ## в этот порыв уже ударился об это (id → номер цикла)
var _hail_t := 0.0
var _streaks: GPUParticles3D
var _hail: GPUParticles3D
var _hail_pm: ParticleProcessMaterial
var _local_t := 0.0
var _last_cycle := -1
var _audio: AudioStreamPlayer
var _gen: AudioStreamGeneratorPlayback
var _lp1 := 0.0
var _lp2 := 0.0
var _vol := 0.0
var _howl := 0.0
var _sun: DirectionalLight3D
var _base_sun := 1.0
var _base_sky_affect := 0.6


func _ready() -> void:
	process_priority = 20          # после каньона: туман пишем последними
	var we := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment if get_tree().current_scene else null
	if we and we.environment:
		_env = we.environment
		_base_fog = _env.fog_density
		_base_fog_color = _env.fog_light_color
		_base_sky_affect = _env.fog_sky_affect
	if get_tree().current_scene:
		_sun = get_tree().current_scene.get_node_or_null("Sun") as DirectionalLight3D
		if _sun:
			_base_sun = _sun.light_energy
	_veil()
	# звук ветра
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_audio = AudioStreamPlayer.new()
	_audio.stream = gen
	_audio.volume_db = -60.0
	add_child(_audio)


const STREAK_SHADER := """
shader_type spatial;
// Снежинка-штрих: квадрат вытягивается вдоль скорости частицы (ось Y частицы — по скорости, align_y)
// и поворачивается к камере. Мягкий край, лёгкая прозрачность — как размытый в движении снег.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;
uniform float width = 0.012;
uniform float stretch = 0.12;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fog_fade = 0.035;
varying float vdist;
void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 vd = normalize(MODEL_MATRIX[1].xyz);
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 tc = normalize(cam - c);
	// смотрим вдоль полёта — штрих укорачивается до точки (а не пропадает)
	vec3 cr = cross(vd, tc);
	float l = length(cr);
	vec3 rt = l > 0.04 ? cr / l : INV_VIEW_MATRIX[0].xyz;
	vec3 up = normalize(cross(tc, rt));
	float along = max(stretch * l, width * 1.2);
	vec3 w = c + rt * VERTEX.x * width * sc * 2.0 + up * VERTEX.y * along * sc * 2.0;
	vdist = length(w - cam);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = (1.0 - smoothstep(0.2, 1.0, abs(q.x))) * (1.0 - smoothstep(0.35, 1.0, abs(q.y)));
	a *= exp(-vdist * fog_fade);           // дальние тонут в метели
	ALBEDO = tint.rgb;
	ALPHA = a * tint.a * COLOR.a;
}
"""


## Снег, хлопья, позёмка, град
func _veil() -> void:
	var sh := Shader.new()
	sh.code = STREAK_SHADER
	# 1. мелкий снег — тысячи косых штрихов вокруг камеры
	_streaks = _streak_emitter(sh, 22000, 1.0, Vector3(13.0, 6.0, 13.0), 0.0095, 0.08, Color(0.97, 0.98, 1.0, 0.72), Vector3(0, -3.0, 0))
	_snow = _streaks
	# 2. хлопья у самой камеры: неровные, кружатся (мелкие — не «шарики»)
	_emitter(1600, 1.2, _billboard_quad(_flake_tex(), 0.045), Vector3(8.0, 3.5, 9.0), 5.0, 2.4,
		6.0, 12.0, 0.5, 1.4, 0.45, _ramp(0.1, 0.9, 0.8), 260.0, -2.0)
	# 3. позёмка лентами по полу
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
	_emitter(240, 1.3, dq, Vector3(12.0, 0.08, 16.0), 8.0, 0.22, 10.0, 17.0, 0.7, 1.5, 0.0,
		_ramp(0.15, 0.95, 0.7), 0.0, 0.0)
	# снежная пыль над позёмкой — тоже штрихи, низко
	var dust := _streak_emitter(sh, 900, 0.9, Vector3(10.0, 0.35, 12.0), 0.008, 0.07, Color(1, 1, 1, 0.55), Vector3(0, 0.3, 0))
	_fx.append([dust, dust.process_material, 7.0, 0.45])
	# 4. «флаги» снега, сорванные ветром
	_emitter(80, 1.8, _billboard_quad(_puff_texture(), 1.0), Vector3(12.0, 1.2, 18.0), 5.0, 7.6,
		12.0, 18.0, 1.2, 2.8, 0.25, _ramp(0.12, 0.3, 0.6), 60.0, -1.2)
	# 5. град — короткие яркие штрихи, падают круто и быстро
	_hail = _streak_emitter(sh, 1800, 0.55, Vector3(10.0, 2.0, 10.0), 0.03, 0.07, Color(0.62, 0.72, 0.84, 0.95), Vector3(0, -22.0, 0))
	_hail_pm = _hail.process_material
	_hail_pm.initial_velocity_min = 22.0
	_hail_pm.initial_velocity_max = 30.0
	_hail.emitting = false
	# белёсая взвесь на экране
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_haze = ColorRect.new()
	_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := Shader.new()
	hs.code = HAZE_SHADER
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = hs
	_haze.material = _haze_mat
	_haze.visible = false
	layer.add_child(_haze)


func _streak_emitter(sh: Shader, amount: int, life: float, ext: Vector3, w: float, st: float, col: Color, grav: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3(0, -1, 1)
	pm.spread = 6.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 14.0
	pm.gravity = grav
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.particle_flag_align_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.12
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 0.9))
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	p.process_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("width", w)
	mat.set_shader_parameter("stretch", st)
	mat.set_shader_parameter("tint", col)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p


## Неровная снежинка: шесть мягких лучей и плотная середина
static func _flake_tex() -> Texture2D:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			var r := v.length()
			var ang := atan2(v.y, v.x)
			var arms := pow(absf(cos(ang * 3.0)), 6.0)
			var a := (1.0 - smoothstep(0.0, 0.35, r)) + arms * (1.0 - smoothstep(0.2, 0.95, r)) * 0.8
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Порыв в момент t: [фаза, сила 0…1, направление (x, z), номер цикла]
static func gust_at(t: float, z: float) -> Array:
	var cyc := int(floor(t / CYCLE))
	var h1 := fposmod(sin(cyc * 12.9898 + 4.1) * 43758.5453, 1.0)
	var h2 := fposmod(sin(cyc * 78.233 + 1.7) * 24634.6345, 1.0)
	var start := 5.0 + h1 * (CYCLE - WARN - GUST - FADE - 6.0)
	var tau := t - cyc * CYCLE - start
	var base := W.wind_dir(z)
	var ang := (h2 - 0.5) * 1.6
	var dir := base.rotated(ang)
	var power := 0.85 + 0.3 * h1
	if tau < 0.0:
		return [0, 0.0, dir, cyc]
	if tau < WARN:
		return [1, 0.12 * (tau / WARN), dir, cyc]
	tau -= WARN
	if tau < GUST:
		var u := tau / GUST
		return [2, power * smoothstep(0.0, 0.08, u) * (0.88 + 0.12 * sin(tau * 9.0)), dir, cyc]
	tau -= GUST
	if tau < FADE:
		return [3, power * (1.0 - smoothstep(0.0, 1.0, tau / FADE)), dir, cyc]
	return [0, 0.0, dir, cyc]


## Чем защищён дрон от ветра (множитель 0…1 и почему)
func shelter_factor(me: Node3D, wind_dir3: Vector3) -> Array:
	var f := 1.0
	var why: Array[String] = []
	var p := me.global_position
	# двор лагеря (частокол) и изба: ветра нет совсем
	var cab = waste.get("cabin") if waste else null
	if cab and cab.in_yard(p):
		sheltered = true
		me.set("_wind_hold", Vector3.ZERO)
		return [0.0, "в лагере"]
	if me.get("sitting"):
		f *= 0.35
		why.append("присел")
	var held := false
	if waste:
		for q: Vector3 in waste.poles:
			if absf(q.z - p.z) < 2.0 and Vector2(q.x - p.x, q.z - p.z).length() < 1.7:
				held = true
				break
		if not held:
			for r in waste.ropes:
				var a: Vector3 = r[0]
				var b: Vector3 = r[1]
				if absf((a.z + b.z) * 0.5 - p.z) > 12.0:
					continue
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var ap := Vector2(p.x - a.x, p.z - a.z)
				var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
				if (ap - ab * t).length() < 1.3:
					held = true
					break
	if held:
		# держится — не сносит совсем (и прежний снос гасится)
		f = 0.0
		me.set("_wind_hold", Vector3.ZERO)
		why.append("держишься")
	# укрытие: что-то твёрдое и высокое с наветренной стороны
	if wind_dir3.length() > 0.01:
		var space := me.get_world_3d().direct_space_state
		var up_dir := -wind_dir3.normalized()
		var hidden := false
		for ang in [0.0, 0.35, -0.35]:
			var rd := up_dir.rotated(Vector3.UP, ang)
			for hgt in [0.8, 1.6]:
				var from := p + Vector3(0, hgt, 0)
				var q2 := PhysicsRayQueryParameters3D.create(from, from + rd * 8.0)
				q2.exclude = [me.get_rid()]
				var hit := space.intersect_ray(q2)
				if hit and (hit["collider"] as Node).is_in_group("wind_shelter"):
					hidden = true
					break
			if hidden:
				break
		# за скалой помещаются только двое (ближайшие к ней с подветренной стороны)
		if hidden and not _room_behind_rock(me, wind_dir3):
			hidden = false
			why.append("за скалой нет места")
		sheltered = hidden
		if hidden:
			f *= 0.05
			me.set("_wind_hold", Vector3.ZERO)
			why.append("за укрытием")
	# вместе: рядом друг (или бот) — ветер берёт слабее; в связке верёвкой — ещё слабее
	var tied := false
	var rope = me.get("rope")
	if rope and int(rope.get("state")) == 3 and rope.get("target") is CharacterBody3D:
		tied = true
	elif rope and rope.has_method("ropes_on") and not rope.ropes_on(me).is_empty():
		tied = true
	var near := false
	for o in get_tree().get_nodes_in_group("player"):
		if o != me and not o.get("is_dead") and (o as Node3D).global_position.distance_to(p) < 2.8:
			near = true
			break
	if tied:
		f *= 0.4
		why.append("в связке")
	elif near:
		f *= 0.5
		why.append("вместе")
	return [f, ", ".join(why)]


func _physics_process(delta: float) -> void:
	_player = Network.local_player
	if _player == null or not is_instance_valid(_player):
		return
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var p := _player.global_position
	var inside := p.z < W.S_Z - 3.0 and p.z > W.N_Z - 30.0 and absf(p.x) < W.HALF + 60.0
	var st := W.storm(p.z) if inside else 0.0
	intensity = move_toward(intensity, st, 0.35 * delta)
	var g: Array = gust_at(t, p.z)
	gust_phase = int(g[0]) if intensity > 0.3 and not calm else 0
	var gs: float = float(g[1]) if intensity > 0.3 and not calm else 0.0
	gust_dir = g[2]
	gust = move_toward(gust, gs, delta * 3.0)
	var base_dir := W.wind_dir(p.z)
	var wb := Vector3(base_dir.x, 0, base_dir.y) * (0.5 + 2.1 * intensity)
	var wg := Vector3(gust_dir.x, 0, gust_dir.y) * GUST_SPEED * gust * intensity
	var wind := wb.lerp(Vector3.ZERO, gust * 0.5) + wg
	var prot: Array = [1.0, ""]
	if intensity > 0.02 and not _player.is_dead:
		prot = shelter_factor(_player, wind)
		protection = prot[0]
		protect_why = prot[1]
		wind_now = wind * protection
		if wind_now.length() > 0.02:
			_player.apply_wind(wind_now)
		# первый удар порыва — рывок
		if gust_phase == 2 and int(g[3]) != _last_cycle:
			_last_cycle = int(g[3])
			if protection > 0.2:
				_player.wind_shove(Vector3(gust_dir.x, 0, gust_dir.y), 5.0 * protection * intensity)
		if gust_phase == 2:
			_player.add_shake(0.06 * protection + 0.02)
	else:
		wind_now = Vector3.ZERO
		protection = 1.0
		protect_why = ""
		sheltered = false
	_slam(int(g[3]))
	_cold_and_hail(delta)
	_update_look(delta, p, wind)


## Есть ли мне место за ближайшей скалой-укрытием (не больше ROCK_ROOM дронов)
func _room_behind_rock(me: Node3D, wind3: Vector3) -> bool:
	var p := me.global_position
	var best: Array = []
	var bd := 1e9
	for sh in W.shelters():
		var c: Vector2 = sh[0]
		var d := Vector2(p.x, p.z).distance_to(c)
		if d < bd:
			bd = d
			best = sh
	if best.is_empty() or bd > float(best[1]) + 6.0:
		return true                  # укрылся не за скалой (стена, монолит, вездеход) — места хватит
	var c2: Vector2 = best[0]
	var reach := float(best[1]) + 6.0
	var wd := Vector2(wind3.x, wind3.z).normalized()
	var list: Array = []
	for o in get_tree().get_nodes_in_group("player"):
		if o.get("is_dead"):
			continue
		var q: Vector3 = (o as Node3D).global_position
		var dq := Vector2(q.x, q.z) - c2
		if dq.length() < reach and dq.dot(wd) > -0.5:
			list.append([dq.length(), o])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(list.size(), ROCK_ROOM):
		if list[i][1] == me:
			return true
	return false


## Порыв несёт на препятствие — удар (по разу о каждое препятствие за порыв)
func _slam(cyc: int) -> void:
	if _player.is_dead or _player.is_frozen or wind_now.length() < 4.0 or not (gust_phase in [2, 3]):
		return
	for i in _player.get_slide_collision_count():
		var col: KinematicCollision3D = _player.get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue
		var into := -wind_now.dot(n)
		if into < 3.0:
			continue
		var obj := col.get_collider()
		var id := obj.get_instance_id() if obj else 0
		if _slammed.get(id, -1) == cyc:
			continue
		_slammed[id] = cyc
		var dmg := clampf(10.0 + (into - 3.0) * 0.8, 10.0, 20.0)
		_player.take_damage(dmg, "hit", col.get_position())
		_player.add_shake(0.35)
		slam_hits += 1
		break


## Мороз и град (только своему дрону)
func _cold_and_hail(delta: float) -> void:
	if _player.is_dead or intensity < 0.05 or no_cold:
		_player.air_cold = 0.0
		return
	var c := COLD * pow(intensity, 1.3)
	var cab = waste.get("cabin") if waste else null
	if cab and cab.in_cabin(_player.global_position):
		c = 0.0
	elif cab and cab.in_yard(_player.global_position):
		c *= 0.3
	elif sheltered:
		c *= 0.5
	if gust_phase == 2:
		c *= 1.5
	_player.air_cold = c
	# град: в порыв, если не за укрытием (присел — реже попадает)
	if gust_phase == 2 and gust > 0.4 and intensity > 0.5 and not sheltered and not _player.is_frozen:
		_hail_t -= delta
		if _hail_t <= 0.0:
			_hail_t = randf_range(0.45, 0.9) * (2.0 if _player.sitting else 1.0)
			_player.add_shake(0.04)          # град только стучит — без урона
			hail_hits += 1
	else:
		_hail_t = 0.3


var _indoor := 0.0                 ## 1 — в избе: метели не видно и не слышно

func _update_look(delta: float, p: Vector3, wind: Vector3) -> void:
	var cab = waste.get("cabin") if waste else null
	_indoor = move_toward(_indoor, 1.0 if (cab and cab.in_cabin(p)) else 0.0, delta * 2.5)
	var dir3 := wind.normalized() if wind.length() > 0.05 else Vector3(0, 0, 1)
	# снег: штрихи летят по ветру, в порыв — быстрее и почти горизонтально
	var sp := 7.0 + 9.0 * intensity + 14.0 * gust
	_streaks.global_position = p - dir3 * (sp * 0.55) + Vector3(0, 3.5, 0)
	_streaks.emitting = intensity > 0.02
	_streaks.amount_ratio = clampf(0.2 + intensity * 0.85, 0.0, 1.0) * (1.0 - _indoor)
	var spm := _streaks.process_material as ParticleProcessMaterial
	spm.direction = (dir3 + Vector3(0, -0.55 + 0.4 * gust, 0)).normalized()
	spm.initial_velocity_min = sp * 0.8
	spm.initial_velocity_max = sp * 1.2
	# град
	var hail_on := gust_phase == 2 and gust > 0.3 and intensity > 0.5 and _indoor < 0.5
	_hail.emitting = hail_on
	if hail_on:
		_hail.global_position = p - dir3 * 9.0 + Vector3(0, 7.0, 0)
		_hail_pm.direction = (dir3 * 0.8 + Vector3(0, -1.0, 0)).normalized()
	var vis := intensity * (0.55 + 0.45 * gust) * (1.0 - _indoor)
	for e in _fx:
		var part: GPUParticles3D = e[0]
		var ppm: ParticleProcessMaterial = e[1]
		part.emitting = vis > 0.04
		part.amount_ratio = clampf(vis, 0.0, 1.0)
		part.global_position = p - dir3 * float(e[2]) + Vector3(0, float(e[3]), 0)
		ppm.direction = dir3
		part.speed_scale = 0.7 + 0.5 * gust
	# муть на экране несётся по ветру (с точки зрения камеры)
	var cam := get_viewport().get_camera_3d()
	var side := 1.0
	if cam:
		side = signf(cam.global_basis.x.dot(dir3))
		if side == 0.0:
			side = 1.0
	_haze_offset -= side * delta * (0.5 + 1.8 * gust)
	_haze.visible = vis > 0.03
	_haze_mat.set_shader_parameter("amount", vis * 0.38)
	_haze_mat.set_shader_parameter("offset", _haze_offset)
	# звук
	_vol = move_toward(_vol, intensity * (0.35 + 0.65 * gust) * (1.0 - 0.75 * _indoor), delta * 0.8)
	_howl = gust


## Туман и свет — в _process (после всех, кто тоже трогает туман)
func _apply_air() -> void:
	var fog_k := intensity * (1.0 - 0.95 * _indoor)
	if _env and (fog_k > 0.001 or _fog_active):
		_env.fog_density = lerpf(_base_fog, STORM_FOG, fog_k) + GUST_FOG * gust * fog_k
		_env.fog_light_color = _base_fog_color.lerp(Color(0.66, 0.71, 0.78), clampf(fog_k * 1.3, 0.0, 1.0))
		_env.fog_sky_affect = lerpf(_base_sky_affect, 1.0, clampf(fog_k * 1.5, 0.0, 1.0))
		if _sun:
			_sun.light_energy = _base_sun * lerpf(1.0, 0.45, fog_k)
	_fog_active = fog_k > 0.001


func _process(_delta: float) -> void:
	_apply_air()
	if _audio == null:
		return
	if _vol < 0.01:
		if _audio.playing:
			_audio.stop()
			_gen = null
		return
	if not _audio.playing:
		_audio.play()
		_gen = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _gen == null:
		return
	_audio.volume_db = linear_to_db(clampf(_vol, 0.001, 1.0)) - 4.0
	var n := _gen.get_frames_available()
	var cut := 0.012 + 0.05 * _howl
	var gain := 9.0 + 6.0 * _howl
	for i in n:
		var w := randf() * 2.0 - 1.0
		_lp1 += (w - _lp1) * cut
		_lp2 += (_lp1 - _lp2) * cut * 1.6
		var v := clampf(_lp2 * gain, -1.0, 1.0)
		_gen.push_frame(Vector2(v, v * 0.92))
