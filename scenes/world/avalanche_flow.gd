extends Node3D
## Одна лавина Лавинной долины (шаг 56). Её создаёт avalanche.gd — у всех одинаково (по времени старта).
##
##   SIDE  — срыв со склона сбоку: трещина отрыва по склону, пласт ломается на глыбы,
##           поток катится вниз, через всё дно до другого склона (быстро: 8 → 24 м/с).
##   CHASE — большая лавина с перевала: со склонов у перевала срываются пласты (трещины отрыва),
##           дальше поток гонится вниз по долине. Скоростью управляет хост (avalanche.gd): фронт держится
##           в ~12 м за последним бегущим — бежишь без остановки, успеваешь впритык. Выдыхается у гребня.
##
## Из чего сделана:
##   * плотное тело — «вал» снега у фронта (меш перестраивается каждый кадр, шейдер крутит снег);
##   * пылевое облако — сотни клубов-billboard'ов, вылетают у фронта, растут и отстают;
##   * глыбы — настоящие физические тела, кувыркаются и скачут по склону;
##   * брызги у фронта; позади насыпает толстый слой снега (snow_layer.gd) — он остаётся лежать.
##   * (шаг 62) снежная волна-облако: огромные клубы пыли вылетают вперёд головы и обгоняют её —
##     впереди потока идёт стена пыли с ударным ветром (avalanche.gd толкает дронов, белеет экран);
##     глыбы, улёгшиеся на слой снега, остаются лежать; со склонов вокруг игрока сыплются струйки снега.
##   * Шейдеры, меши глыб и материалы — общие (static) и «прогреваются» при загрузке уровня (prewarm),
##     иначе первая лавина подвисала на компиляции шейдеров.

const W := preload("res://scenes/world/avalanche_layout.gd")

enum K { SIDE, CHASE }

const N := 44                      ## точек по фронту (шаг 64: подробнее — чёткий вал)
const PUFFS := 420                 ## шаг 137: было 1000 — клубы крупнее, из фото-облаков (флипбук), на процессоре втрое легче
const CHUNKS := 30

var kind := K.SIDE
var far := false                   ## шаг 137: срыв высоко на дальнем склоне — видно издалека, до дна ~13 с
const ATLAS := "res://assets/avalanche/cloud_atlas.png"
const DEBRIS_TEX := "res://assets/avalanche/snow_debris_color.jpg"
const DEBRIS_NRM := "res://assets/avalanche/snow_debris_normal.jpg"
var t := -1.0                      ## время от срыва (до 0 — предупреждение)
var warn := 1.0
var stopped := false
var done := false                  ## всё улеглось — можно удалять
var speed := 0.0                   ## скорость фронта сейчас
var flow_dir := Vector3.FORWARD    ## куда течёт (в середине фронта)

# SIDE
var zc := 0.0
var side := 1.0                    ## +1 — срыв с восточного склона (течёт на запад)
var width := 140.0
var _x0 := 0.0
var _x1 := 0.0
var _dist := 0.0
# CHASE
var s_front := 0.0
var s_start := 215.0
var s_end := W.SAFE_S - 6.0
var ext_speed := -1.0              ## скорость, которую задаёт хост (−1 — своя)
var net_s := -1.0                  ## у остальных: где фронт у хоста

var front := PackedVector3Array()  ## точки фронта (на земле)
var dirs := PackedVector3Array()   ## направление потока у каждой точки

var _ter: Node
var _rng := RandomNumberGenerator.new()
var _body_mesh: ArrayMesh
var _body: MeshInstance3D
var _body_mat: ShaderMaterial
var _ga := PackedFloat32Array()     ## шаг 137: высоты рельефа под валом (кэш)
var _ga_frame := 0
var _stamp_n := 0
var _lod_n := 0
var _puff_mm: MultiMesh
var _puff_pos := PackedVector3Array()
var _puff_vel := PackedVector3Array()
var _puff_age := PackedFloat32Array()
var _puff_life := PackedFloat32Array()
var _puff_size := PackedFloat32Array()
var _puff_rot := PackedFloat32Array()
var _puff_drag := PackedFloat32Array()     ## куда тормозит клуб: доля скорости фронта (облако-волна — обгоняет)
var _puff_g := PackedFloat32Array()        ## высота земли под клубом (обновляется не каждый кадр)
var _puff_buf := PackedFloat32Array()      ## буфер мультимеша: 12 чисел матрицы + 4 своих на клуб
var _puff_frame := 0
var _cloud_acc := 0.0
var _puff_next := 0
var _emit_acc := 0.0
var _chunks: Array = []            ## [тело, возраст]
var _chunk_acc := 0.0
var _chunk_mat: StandardMaterial3D
var _chunk_meshes: Array[Mesh] = []
var _spray: GPUParticles3D
var _layer: Node                    ## snow_layer.gd
var _snout_done := false
var _slab_done := false
var _slough_t := 0.0
var _fractures: Array = []           ## линии отрыва (большая лавина): [[точки], склон]
var _crack: MeshInstance3D
var _age_after := 0.0
var _height := 0.0                 ## высота вала сейчас
var _lobe := FastNoiseLite.new()   ## «языки» вала: по фронту выше/ниже, меняются со временем


func setup_side(z_center: float, from_side: float, seed: int, is_far := false) -> void:
	kind = K.SIDE
	zc = z_center
	side = from_side
	far = is_far
	warn = 3.0 if far else 1.3
	t = -warn
	_rng.seed = seed
	var s := W.s_of(zc)
	var cx := W.center_x(s)
	var hw := W.half_w(s)
	_x0 = cx + side * (hw + 42.0)
	_x1 = cx - side * (hw + 6.0)
	if far:
		# шаг 137: отрыв — высоко в горах (рельеф там до ~250 м), но не за краем мира (|x| ≤ 252)
		width = 270.0
		var up := clampf(252.0 - absf(cx + side * hw), 60.0, 165.0)
		_x0 = cx + side * (hw + up)


func setup_chase(seed: int, from_s := 215.0) -> void:
	kind = K.CHASE
	warn = 2.6
	t = -warn
	_rng.seed = seed
	s_start = from_s
	s_front = s_start


func _ready() -> void:
	_ter = get_tree().get_first_node_in_group("terrain")
	_lobe.seed = _rng.randi()
	_lobe.frequency = 0.35
	front.resize(N)
	dirs.resize(N)
	_make_body()
	_make_puffs()
	_make_chunks()
	_layer = get_tree().get_first_node_in_group("snow_layer")
	_spray = make_spray()
	add_child(_spray)
	_update_front(0.0)
	if kind == K.SIDE:
		if not far:
			_make_crack()                   # шаг 137: у дальнего срыва трещину отрыва не видно — только облако
	else:
		_make_fractures()



func _h(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else 0.0


# ---------------------------------------------------------------------------
#  Фронт
# ---------------------------------------------------------------------------

func _update_front(delta: float) -> void:
	if kind == K.SIDE:
		if t >= 0.0 and not stopped:
			speed = minf(10.0 + t * 14.0, 26.0) if not far else minf(8.0 + t * 9.0, 25.0)
			var left := absf(_x1 - _x0) - _dist
			if left < 18.0:
				speed *= clampf(left / 18.0, 0.15, 1.0)
			_dist += speed * delta
			if _dist >= absf(_x1 - _x0) - 0.5:
				stopped = true
				speed = 0.0
		var xf := _x0 - side * _dist
		flow_dir = Vector3(-side, 0.0, 0.0)
		for j in N:
			var u := float(j) / (N - 1) * 2.0 - 1.0
			var z := zc + u * width * 0.5
			# середина впереди, края отстают; по краям вал тоньше
			var x := xf - side * (1.0 - u * u) * 9.0 + side * absf(u) * 4.0
			var p := Vector3(x, 0.0, z)
			p.y = _h(p.x, p.z)
			front[j] = p
			var down := Vector3(-side, 0.0, u * 0.25).normalized()
			dirs[j] = down
	else:
		if t >= 0.0 and not stopped:
			if ext_speed >= 0.0:
				speed = move_toward(speed, ext_speed, 6.0 * delta)
			else:
				speed = minf(5.0 + t * 1.5, 10.0)
			s_front += speed * delta
			if net_s >= 0.0:
				s_front = lerpf(s_front, net_s, clampf(delta * 3.0, 0.0, 1.0))
			if s_front >= s_end - 0.5:
				stopped = true
				speed = 0.0
		flow_dir = W.path_dir(s_front)
		var side_v := Vector3(flow_dir.z, 0.0, -flow_dir.x)
		var hw := W.half_w(s_front) + 30.0
		for j in N:
			var u2 := float(j) / (N - 1) * 2.0 - 1.0
			var s2 := s_front + (1.0 - u2 * u2) * 10.0 - absf(u2) * 6.0
			var pc := W.path_point(s2)
			var p2 := Vector3(W.center_x(s2) + u2 * hw, 0.0, pc.z)
			p2.y = _h(p2.x, p2.z)
			front[j] = p2
			# у склонов снег стекает к середине
			dirs[j] = (flow_dir + side_v * (-u2) * 0.35).normalized()


## Лавина у точки p: [накрыло?, скорость потока там]
func hit_test(p: Vector3) -> Array:
	if t < 0.0 or (stopped and _age_after > 0.6):
		return [false, Vector3.ZERO]
	if kind == K.SIDE:
		if absf(p.z - zc) > width * 0.5:
			return [false, Vector3.ZERO]
		var j := clampi(roundi((p.z - zc) / width * (N - 1) + (N - 1) * 0.5), 0, N - 1)
		var fx: float = front[j].x
		# фронт прошёл мимо меня (я между ним и склоном, откуда он идёт), тело — до 45 м
		var behind := (p.x - fx) * side
		if behind > -1.2 and behind < 45.0:
			return [true, dirs[j] * maxf(speed, 9.0) + Vector3(0, 0, _rng.randf_range(-2.0, 2.0))]
		return [false, Vector3.ZERO]
	var s := W.s_of(p.z)
	if s > W.SAFE_S - 2.0:
		return [false, Vector3.ZERO]          # на гребне лавина не достаёт
	var cx := W.center_x(s)
	if absf(p.x - cx) > W.half_w(s) + 32.0:
		return [false, Vector3.ZERO]
	var u := clampf((p.x - cx) / (W.half_w(s) + 30.0), -1.0, 1.0)
	var sf := s_front + (1.0 - u * u) * 10.0 - absf(u) * 6.0
	if s < sf + 1.2 and s > sf - 60.0:
		return [true, (flow_dir + Vector3(flow_dir.z, 0, -flow_dir.x) * (-u) * 0.3).normalized() * maxf(speed * 1.05, 7.0)]
	return [false, Vector3.ZERO]


## Насколько точка позади фронта (в теле потока), м; отрицательное — впереди
func behind_front(p: Vector3) -> float:
	if kind == K.SIDE:
		# между соседними точками фронта — плавно (иначе едущий на валу подпрыгивает на стыках)
		var fj := clampf((p.z - zc) / width * (N - 1) + (N - 1) * 0.5, 0.0, N - 1.001)
		var j := int(fj)
		var fx := lerpf(front[j].x, front[mini(j + 1, N - 1)].x, fj - j)
		return (p.x - fx) * side
	var s := W.s_of(p.z)
	var cx := W.center_x(s)
	var u := clampf((p.x - cx) / (W.half_w(s) + 30.0), -1.0, 1.0)
	return s_front + (1.0 - u * u) * 10.0 - absf(u) * 6.0 - s


## Верх снежного вала над точкой (мировой y) — по нему «едет» тот, кого несёт
func surface_at(p: Vector3) -> float:
	var g := _h(p.x, p.z)
	var b := behind_front(p) / (1.0 if kind == K.CHASE else 0.7)
	if b < 0.0 or b > SURF[SURF.size() - 1].x or _height < 0.05:
		return g
	var fr := 0.0
	for i in SURF.size() - 1:
		var a: Vector2 = SURF[i]
		var c: Vector2 = SURF[i + 1]
		if b <= c.x:
			fr = lerpf(a.y, c.y, (b - a.x) / maxf(c.x - a.x, 0.001))
			break
	var u := 0.0
	if kind == K.SIDE:
		u = clampf((p.z - zc) / (width * 0.5), -1.0, 1.0)
	else:
		var s := W.s_of(p.z)
		u = clampf((p.x - W.center_x(s)) / (W.half_w(s) + 30.0), -1.0, 1.0)
	return g + fr * _height * (0.35 + 0.65 * (1.0 - pow(absf(u), 3.0))) - 0.15


## Шаг 137: насколько точка у края потока (0 — посередине, 1 — у самого края): у края заваливает неглубоко
func edge_k(p: Vector3) -> float:
	if kind == K.SIDE:
		return clampf(absf(p.z - zc) / (width * 0.5), 0.0, 1.0)
	var s := W.s_of(p.z)
	return clampf(absf(p.x - W.center_x(s)) / (W.half_w(s) + 30.0), 0.0, 1.0)


## Середина фронта (для звука, тряски)
func front_center() -> Vector3:
	return front[N / 2]


func _process(delta: float) -> void:
	t += delta
	if stopped:
		_age_after += delta
	_update_front(delta)
	var active := t >= 0.0 and not stopped
	var grow := clampf(t / 1.2, 0.0, 1.0) if t >= 0.0 else 0.0
	var fade := 1.0 - clampf(_age_after / 2.5, 0.0, 1.0)
	_height = (9.0 if kind == K.CHASE or far else 6.5) * grow * fade
	# шаг 137: далеко от камеры вал перестраиваю через кадр (на 150+ м разницы не видно)
	_lod_n += 1
	var camv := get_viewport().get_camera_3d()
	var far_cam := camv != null and camv.global_position.distance_to(front_center()) > 150.0
	if not far_cam or _lod_n % 2 == 0:
		_update_body()
	_update_puffs(delta, active)
	_update_chunks(delta, active)
	if active:
		_stamp()
	if stopped and not _snout_done:
		_snout_done = true
		_stamp_snout()
	var fc := front_center()
	_spray.global_position = fc + Vector3.UP * 1.5
	_spray.emitting = active
	(_spray.process_material as ParticleProcessMaterial).direction = (flow_dir + Vector3.UP * 0.9).normalized()
	if _crack:
		_crack.visible = t < 4.0
	if kind == K.CHASE:
		if t < 0.0:
			_emit_warn_dust(delta)
			if not _slab_done and t > -1.5:
				_slab_done = true
				_release_slabs()
		elif active:
			_sloughs(delta)
	elif active:
		_sloughs(delta)
	if stopped and _age_after > 25.0:
		done = true


# ---------------------------------------------------------------------------
#  Тело: вал снега у фронта
# ---------------------------------------------------------------------------

const BODY_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Вал лавины (шаг 64): плотный и чёткий — непрозрачный, с нависающей кромкой гребня;
// по нему бегут струи вдоль потока и катятся валики-складки, гребень яркий с искрами,
// у земли и в складках — синеватая тень. Вблизи камеры рассыпается точками (не стена перед глазами).
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D debris : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D debris_n : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float span = 140.0;
uniform float churn = 1.0;
uniform float tspeed = 1.0;
varying float crest;
varying vec2 fl;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	crest = UV.y;
	fl = vec2(UV.x, UV2.x);
	float tt = TIME * tspeed;
	// крупные клубы на лице волны — катятся вперёд вместе с ней
	float n = texture(noise, vec2(fl.x * 4.0, fl.y * 0.05 - tt * 0.22)).r;
	float n2 = texture(noise, wpos.xz * 0.11 + vec2(-tt * 0.5, tt * 0.4)).r;
	VERTEX += NORMAL * ((n - 0.5) * 1.9 + (n2 - 0.5) * 0.8) * smoothstep(0.0, 0.25, crest) * churn;
}
void fragment() {
	float tt = TIME * tspeed;
	// струи вдоль потока: вытянутый шум бежит назад от гребня
	float st = texture(noise, vec2(fl.x * 24.0, fl.y * 0.08 + tt * 0.9)).r;
	float st2 = texture(noise, vec2(fl.x * 61.0 + 0.3, fl.y * 0.21 + tt * 1.5)).r;
	// валики поперёк — накатывают
	float fold = sin(fl.y * 1.7 - tt * 7.0 + st * 5.0) * 0.5 + 0.5;
	float n = texture(noise, wpos.xz * 0.2 + vec2(tt * 0.5, tt * 0.3)).r;
	float light = 0.5 + crest * 0.38 + (st - 0.5) * 0.5 + (st2 - 0.5) * 0.2 + (fold - 0.5) * 0.26 + (n - 0.5) * 0.25;
	vec3 c = mix(vec3(0.34, 0.43, 0.6), vec3(0.97, 0.98, 1.0), clamp(light, 0.0, 1.0));
	c *= mix(0.7, 1.0, smoothstep(0.0, 0.3, crest));          // плотный снег у земли темнее
	float rim = smoothstep(0.84, 0.98, crest);
	c = mix(c, vec3(1.02, 1.03, 1.06), rim * 0.55);           // кромка гребня — светлая
	float sp = step(0.986, hash(floor(FRAGCOORD.xy / 2.0) + floor(tt * 8.0)));
	// шаг 137: фото-текстура рыхлого снега (комья, складки) — бежит назад от гребня, как перекатывающийся снег
	vec2 duv = vec2(fl.x * span * 0.22, fl.y * 0.22 + tt * 1.1);
	vec3 dt = texture(debris, duv).rgb;
	c *= mix(0.78, 1.12, clamp(dot(dt, vec3(0.33)) * 1.15, 0.0, 1.0));
	NORMAL_MAP = texture(debris_n, duv).rgb;
	NORMAL_MAP_DEPTH = 1.6;
	ALBEDO = c + vec3(0.3) * sp * (rim + 0.25);
	ROUGHNESS = 0.9;
	RIM = 0.45;
	RIM_TINT = 0.7;
	BACKLIGHT = vec3(0.3, 0.38, 0.52);
	float dcam = length(VERTEX);
	if (dcam < 4.0 && hash(FRAGCOORD.xy) > smoothstep(1.0, 4.0, dcam)) {
		discard;
	}
}
"""

## Верх вала (по нему едут): сколько позади фронта → доля высоты (монотонно по «позади»)
const SURF := [Vector2(0.0, 0.45), Vector2(1.0, 0.9), Vector2(3.0, 1.0), Vector2(5.0, 0.9), Vector2(8.0, 0.74),
	Vector2(11.5, 0.56), Vector2(15.0, 0.4), Vector2(19.0, 0.23), Vector2(23.5, 0.1), Vector2(28.0, 0.0)]

## Профиль вала: (сколько позади фронта, доля высоты)
## Отрицательное «позади» — впереди фронта: нависающая кромка гребня (масштаб — по высоте вала)
const PROFILE := [Vector2(-0.3, 0.0), Vector2(-0.9, 0.16), Vector2(-1.5, 0.36), Vector2(-1.8, 0.56), Vector2(-1.5, 0.74),
	Vector2(-0.7, 0.88), Vector2(0.4, 0.97), Vector2(2.0, 1.0), Vector2(4.0, 0.95), Vector2(6.5, 0.86), Vector2(9.5, 0.72),
	Vector2(13.0, 0.55), Vector2(17.0, 0.37), Vector2(21.0, 0.22), Vector2(25.0, 0.1), Vector2(29.0, 0.02)]


func _make_body() -> void:
	_body_mesh = ArrayMesh.new()
	_body = MeshInstance3D.new()
	_body.mesh = _body_mesh
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_mat = body_material()
	_body_mat.set_shader_parameter("span", width if kind == K.SIDE else 220.0)
	_body.material_override = _body_mat
	_body.extra_cull_margin = 200.0
	add_child(_body)


func _update_body() -> void:
	_body_mesh.clear_surfaces()
	if _height < 0.05:
		return
	var rows := PROFILE.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	verts.resize(N * rows)
	uvs.resize(N * rows)
	uv2.resize(N * rows)
	var len_k := 1.0 if kind == K.CHASE else 0.7
	var lip := clampf(_height / 7.0, 0.3, 1.3)
	# земля под валом: по 4 точкам вдоль потока, между ними — прямая (дно ровное; в разы меньше запросов к рельефу)
	var anchors := [-2.5 * len_k, 5.0 * len_k, 14.0 * len_k, 29.0 * len_k]
	_ga_frame += 1
	if _ga.size() != N * 4:
		_ga.resize(N * 4)
		_ga_frame = 0
	for j in N:
		var fp: Vector3 = front[j]
		var d: Vector3 = dirs[j]
		# шаг 137: рельеф под валом — у каждой колонки раз в 3 кадра (по очереди), а не каждый кадр
		if _ga_frame < 2 or far or (j + _ga_frame) % 3 == 0:     # на крутом склоне — каждый кадр (иначе вал «зубьями»)
			for ai in 4:
				var qa: Vector3 = fp - d * float(anchors[ai])
				_ga[j * 4 + ai] = _h(qa.x, qa.z)
		var ga: Array[float] = [_ga[j * 4], _ga[j * 4 + 1], _ga[j * 4 + 2], _ga[j * 4 + 3]]
		var edge := 1.0 - pow(absf(float(j) / (N - 1) * 2.0 - 1.0), 3.0)
		edge *= 0.55 + 0.9 * clampf(_lobe.get_noise_2d(float(j) * 28.0 / N, t * 1.3) * 0.5 + 0.5, 0.0, 1.0)
		var hk := 0.35 + 0.65 * edge
		for k in rows:
			var pr: Vector2 = PROFILE[k]
			var bx: float = pr.x * len_k * (1.0 if pr.x >= 0.0 else lip * hk)
			var q := fp - d * bx
			var g: float
			if bx <= anchors[1]:
				g = lerpf(ga[0], ga[1], (bx - anchors[0]) / (anchors[1] - anchors[0]))
			elif bx <= anchors[2]:
				g = lerpf(ga[1], ga[2], (bx - anchors[1]) / (anchors[2] - anchors[1]))
			else:
				g = lerpf(ga[2], ga[3], (bx - anchors[2]) / (anchors[3] - anchors[2]))
			verts[j * rows + k] = Vector3(q.x, g + pr.y * _height * hk - 0.15, q.z)
			uvs[j * rows + k] = Vector2(float(j) / (N - 1), pr.y * edge)
			uv2[j * rows + k] = Vector2(pr.x, 0.0)
	# нормали — по соседям сетки (быстрее, чем SurfaceTool)
	var norms := PackedVector3Array()
	norms.resize(N * rows)
	for j in N:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, N - 1)
		for k in rows:
			var k0 := maxi(k - 1, 0)
			var k1 := mini(k + 1, rows - 1)
			var across := verts[j1 * rows + k] - verts[j0 * rows + k]
			var along := verts[j * rows + k1] - verts[j * rows + k0]
			var nn := along.cross(across)
			norms[j * rows + k] = nn.normalized() if nn.length() > 0.0001 else Vector3.UP
	# сторона: на гребне нормаль должна смотреть вверх
	var mid := (N / 2) * rows + 7
	if norms[mid].y < 0.0:
		for i in norms.size():
			norms[i] = -norms[i]
	var idx := PackedInt32Array()
	idx.resize((N - 1) * (rows - 1) * 6)
	var w := 0
	for j in N - 1:
		for k in rows - 1:
			var a := j * rows + k
			var b := (j + 1) * rows + k
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = a + 1
			idx[w + 3] = a + 1
			idx[w + 4] = b
			idx[w + 5] = b + 1
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	_body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


# ---------------------------------------------------------------------------
#  Пылевое облако: клубы-billboard'ы
# ---------------------------------------------------------------------------

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
// Шаг 137: клуб снежной пыли — фото-облако из флипбука (Unity Labs, CC0): 4 облака по 8×8 кадров;
// кадр — по возрасту клуба (облако растёт и клубится), между кадрами — плавно.
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying float alpha;
float lin_depth(sampler2D dt, vec2 suv, mat4 inv_proj) {
	float d = texture(dt, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

varying float variant;
varying float age;
varying float shade;
void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	alpha = INSTANCE_CUSTOM.x;
	variant = floor(INSTANCE_CUSTOM.y * 0.5);
	age = INSTANCE_CUSTOM.y - variant * 2.0;
	shade = INSTANCE_CUSTOM.w;
	float a = INSTANCE_CUSTOM.z * 6.2832;
	VERTEX.xy = vec2(VERTEX.x * cos(a) - VERTEX.y * sin(a), VERTEX.x * sin(a) + VERTEX.y * cos(a)) * sc;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
vec4 frame(float f, vec2 uv) {
	float fi = clamp(floor(f), 0.0, 63.0);
	vec2 cellp = vec2(mod(fi, 8.0), floor(fi / 8.0));
	vec2 q = vec2(mod(variant, 2.0), floor(variant / 2.0));
	return texture(atlas, (q * 8.0 + cellp + uv) / 16.0);
}
void fragment() {
	vec2 uv = UV - 0.5;
	float f = age * 62.0;
	vec4 c = mix(frame(f, UV), frame(f + 1.0, UV), fract(f));
	float dens = clamp(c.r * 1.9, 0.0, 1.0);
	// сверху светлее, снизу и внутри — голубоватая тень; плотные места облака — темнее
	float light = clamp(0.35 + (-uv.y) * 0.9 + dens * 0.55, 0.0, 1.0) * shade;
	ALBEDO = mix(vec3(0.42, 0.5, 0.66), vec3(0.98, 0.99, 1.02), light);
	// мягкие клубы: растворяются у земли/склонов и перед самой камерой
	float scene = lin_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float me = -VERTEX.z;
	float soft = clamp((scene - me) / 4.0, 0.0, 1.0) * smoothstep(0.6, 6.0, me);
	ALPHA = clamp(pow(c.a, 1.35) * 1.25, 0.0, 1.0) * alpha * soft;
}
"""


func _make_puffs() -> void:
	_puff_mm = MultiMesh.new()
	_puff_mm.transform_format = MultiMesh.TRANSFORM_3D
	_puff_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_puff_mm.mesh = q
	_puff_mm.instance_count = PUFFS
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _puff_mm
	mmi.material_override = puff_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 400.0
	add_child(mmi)
	_puff_pos.resize(PUFFS)
	_puff_vel.resize(PUFFS)
	_puff_age.resize(PUFFS)
	_puff_life.resize(PUFFS)
	_puff_size.resize(PUFFS)
	_puff_rot.resize(PUFFS)
	_puff_drag.resize(PUFFS)
	_puff_g.resize(PUFFS)
	_puff_buf.resize(PUFFS * 16)
	_puff_buf.fill(0.0)
	for i in PUFFS:
		_puff_life[i] = 0.0
		_puff_age[i] = 1.0
		_puff_buf[i * 16 + 7] = -9999.0
	_puff_mm.buffer = _puff_buf


func _spawn_puff(at: Vector3, vel: Vector3, size: float, life: float, drag := 0.35) -> void:
	var i := _puff_next
	_puff_next = (_puff_next + 1) % PUFFS
	_puff_pos[i] = at
	_puff_vel[i] = vel
	_puff_age[i] = 0.0
	_puff_life[i] = life
	_puff_size[i] = size
	_puff_rot[i] = _rng.randf()
	_puff_drag[i] = drag
	_puff_g[i] = _h(at.x, at.z)


func _update_puffs(delta: float, active: bool) -> void:
	if active:
		var rate := (72.0 if kind == K.CHASE or far else 60.0) * clampf(speed / 8.0, 0.6, 1.3)
		_emit_acc += rate * delta
		while _emit_acc >= 1.0:
			_emit_acc -= 1.0
			# точка — в любом месте фронта (между опорными), чуть позади него
			var fj := _rng.randf() * (N - 1)
			var j := mini(int(fj), N - 2)
			var fp: Vector3 = front[j].lerp(front[j + 1], fj - j)
			var d: Vector3 = dirs[j]
			var at := fp + Vector3.UP * _rng.randf_range(0.3, 3.5) - d * _rng.randf_range(-0.5, 8.0)
			# у головы клубы вылетают вперёд-вверх и закручиваются назад — «перекатывающийся» вал пыли
			var v := d * speed * _rng.randf_range(0.9, 1.35) + Vector3.UP * _rng.randf_range(3.0, 11.0 if kind == K.CHASE else 8.0) \
				+ Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
			_spawn_puff(at, v, _rng.randf_range(5.5, 10.0) if kind == K.CHASE or far else _rng.randf_range(4.0, 7.5), _rng.randf_range(3.0, 5.5))
		# снежная волна-облако: огромные клубы вылетают из головы вперёд и обгоняют поток
		var crate := (14.0 if kind == K.CHASE or far else 10.0) * clampf(speed / 9.0, 0.5, 1.3)
		_cloud_acc += crate * delta
		while _cloud_acc >= 1.0:
			_cloud_acc -= 1.0
			var fj2 := _rng.randf_range(0.12, 0.88) * (N - 1)
			var j2 := mini(int(fj2), N - 2)
			var fp2: Vector3 = front[j2].lerp(front[j2 + 1], fj2 - j2)
			var d2: Vector3 = dirs[j2]
			var big := kind == K.CHASE or far
			_spawn_puff(fp2 + Vector3.UP * _rng.randf_range(1.5, 6.0) + d2 * _rng.randf_range(0.0, 3.0),
				d2 * speed * _rng.randf_range(1.5, 2.0) + Vector3.UP * _rng.randf_range(3.0, 12.0 if big else 8.0)
					+ Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)),
				_rng.randf_range(8.0, 14.0) if big else _rng.randf_range(5.5, 9.5), _rng.randf_range(3.5, 5.5), 1.12)
	var cam := get_viewport().get_camera_3d()
	var cam_p := cam.global_position if cam else Vector3.ZERO
	_puff_frame += 1
	var buf := _puff_buf
	var fv := flow_dir * speed
	for i in PUFFS:
		var o := i * 16
		if _puff_age[i] >= _puff_life[i]:
			if buf[o] != 0.0:
				buf[o] = 0.0
				buf[o + 5] = 0.0
				buf[o + 10] = 0.0
				buf[o + 7] = -9999.0
			continue
		_puff_age[i] += delta
		var a := _puff_age[i] / _puff_life[i]
		var v: Vector3 = _puff_vel[i]
		# воздух тормозит клубы, они поднимаются и медленно оседают; облако-волна тормозит лишь до
		# скорости чуть выше фронта — так и идёт стеной впереди
		var dk: float = _puff_drag[i]
		v = v.lerp(fv * dk + Vector3.UP * (1.4 if dk > 1.0 else 0.4), clampf(delta * 0.9, 0.0, 1.0))
		_puff_vel[i] = v
		var p: Vector3 = _puff_pos[i] + v * delta
		if (i + _puff_frame) % 4 == 0:
			_puff_g[i] = _h(p.x, p.z)
		var g: float = _puff_g[i] + 0.6
		if p.y < g:
			p.y = g
		_puff_pos[i] = p
		var sz: float = _puff_size[i] * (1.0 + a * 2.6)
		var al := smoothstep(0.0, 0.08, a) * (1.0 - smoothstep(0.55, 1.0, a)) * (0.42 if dk > 1.0 else 0.62)
		# вблизи камеры — прозрачнее (не стена белого)
		var dcp := p.distance_to(cam_p)
		al *= clampf((dcp - 1.0) / 6.0, 0.15, 1.0)
		if far:
			al *= 1.0 + 0.6 * smoothstep(60.0, 220.0, dcp)   # издалека облако плотнее — его надо заметить
		if a >= 1.0:
			al = 0.0
		var shade := clampf(0.75 + (p.y - g) * 0.03, 0.75, 1.05)
		buf[o] = sz
		buf[o + 1] = 0.0
		buf[o + 2] = 0.0
		buf[o + 3] = p.x
		buf[o + 4] = 0.0
		buf[o + 5] = sz
		buf[o + 6] = 0.0
		buf[o + 7] = p.y
		buf[o + 8] = 0.0
		buf[o + 9] = 0.0
		buf[o + 10] = sz
		buf[o + 11] = p.z
		buf[o + 12] = al
		buf[o + 13] = float(i % 4) * 2.0 + clampf(a, 0.0, 0.999)       # шаг 137: вариант облака ×2 + возраст
		buf[o + 14] = _puff_rot[i] + a * 0.15
		buf[o + 15] = shade
	_puff_buf = buf
	_puff_mm.buffer = buf


## Сколько метров впереди фронта идёт стена пыли (удар ветром — avalanche.gd)
func cloud_ahead() -> float:
	if t < 0.3 or stopped:
		return 0.0
	return clampf(speed * 1.3, 6.0, 18.0)


## Стена пыли впереди головы: 0 — нет, 1 — у самого фронта
func cloud_test(p: Vector3) -> float:
	var ca := cloud_ahead()
	if ca <= 0.0:
		return 0.0
	var ahead := 0.0
	if kind == K.SIDE:
		if absf(p.z - zc) > width * 0.5:
			return 0.0
		var j := clampi(roundi((p.z - zc) / width * (N - 1) + (N - 1) * 0.5), 0, N - 1)
		ahead = -(p.x - front[j].x) * side
	else:
		var s := W.s_of(p.z)
		if s > W.SAFE_S - 2.0:
			return 0.0
		var cx := W.center_x(s)
		if absf(p.x - cx) > W.half_w(s) + 32.0:
			return 0.0
		var u := clampf((p.x - cx) / (W.half_w(s) + 30.0), -1.0, 1.0)
		ahead = s - (s_front + (1.0 - u * u) * 10.0 - absf(u) * 6.0)
	if ahead < -1.2 or ahead > ca:
		return 0.0
	return 1.0 - clampf(ahead / ca, 0.0, 1.0)


func _emit_warn_dust(delta: float) -> void:
	# перед большой лавиной: на перевале срывается пыль, клубы поднимаются над тропой
	_emit_acc += 30.0 * delta
	while _emit_acc >= 1.0:
		_emit_acc -= 1.0
		var j := _rng.randi_range(0, N - 1)
		var fp: Vector3 = front[j]
		var at := fp + Vector3.UP * _rng.randf_range(0.5, 3.0)
		_spawn_puff(at, Vector3.UP * _rng.randf_range(1.0, 4.0) + flow_dir * 2.0, _rng.randf_range(3.5, 6.5), 4.0)


# ---------------------------------------------------------------------------
#  Глыбы (физика)
# ---------------------------------------------------------------------------

func _make_chunks() -> void:
	_chunk_mat = chunk_material()
	_chunk_meshes = chunk_meshes()


func _spawn_chunk(at: Vector3, vel: Vector3, big := 1.0) -> void:
	if _chunks.size() >= CHUNKS:
		var old: Array = _chunks.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 40.0
	var s := _rng.randf_range(0.5, 2.0) * big
	var cs := CollisionShape3D.new()
	var bs := SphereShape3D.new()
	bs.radius = 0.5 * s
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _chunk_meshes[_rng.randi_range(0, _chunk_meshes.size() - 1)]
	mi.material_override = _chunk_mat
	mi.scale = Vector3.ONE * s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.6
	rb.physics_material_override = pm
	add_child(rb)
	rb.global_position = at
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-3, 3), _rng.randf_range(-5, 5))
	_chunks.append([rb, 0.0, s])


func _update_chunks(delta: float, active: bool) -> void:
	if active:
		_chunk_acc += (12.0 if kind == K.CHASE else 14.0) * delta
		while _chunk_acc >= 1.0:
			_chunk_acc -= 1.0
			var j := _rng.randi_range(2, N - 3)
			var fp: Vector3 = front[j]
			var d: Vector3 = dirs[j]
			# глыбы вылетают из головы и скачут впереди потока
			_spawn_chunk(fp + Vector3.UP * _rng.randf_range(1.0, 3.5) + d * 0.5,
				d * speed * _rng.randf_range(1.0, 1.45) + Vector3.UP * _rng.randf_range(2.0, 7.0))
	var keep: Array = []
	for c in _chunks:
		var rb: RigidBody3D = c[0]
		if not is_instance_valid(rb):
			continue
		c[1] = float(c[1]) + delta
		var age: float = c[1]
		# глыбу подгоняет поток, пока фронт рядом
		if active and age < 4.0:
			rb.apply_central_force(flow_dir * rb.mass * 6.0)
		# поток накрыл глыбу и насыпал снег — она остаётся лежать в нём (наполовину в снегу)
		if age > 1.5 and _layer != null and (stopped or behind_front(rb.global_position) > 11.0) \
				and _layer.depth_at(rb.global_position.x, rb.global_position.z) > 0.3:
			_layer.add_block((rb.get_child(1) as MeshInstance3D).mesh, rb.global_transform.basis.orthonormalized(),
				rb.global_position, float(c[2]))
			rb.queue_free()
			continue
		if age > 10.0:
			var k := clampf(1.0 - (age - 10.0) / 1.5, 0.0, 1.0)
			(rb.get_child(1) as Node3D).scale = Vector3.ONE * float(c[2]) * k
			if k <= 0.0:
				rb.queue_free()
				continue
		keep.append(c)
	_chunks = keep


# ---------------------------------------------------------------------------
#  Отложения и трещина отрыва
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
#  Слой снега позади фронта (snow_layer.gd)
# ---------------------------------------------------------------------------

## Каждый кадр: по двум линиям позади фронта насыпаем снег — толще посередине потока
func _stamp() -> void:
	if _layer == null or t < 0.4:
		return
	_stamp_n += 1
	if _stamp_n % 2 == 1:
		return                              # шаг 137: через кадр (две линии насыпи и так перекрываются)
	var dmax := 1.7 if kind == K.CHASE else (2.0 if far else 1.3)   # шаг 137: после большой лавины — толстый слой
	for off in [9.0, 10.5]:
		for j in N - 1:
			var a: Vector3 = front[j] - dirs[j] * off
			var b: Vector3 = front[j + 1] - dirs[j + 1] * off
			var steps := maxi(int(a.distance_to(b) / 1.2), 1)
			for k in steps:
				var f := float(k) / steps
				var q := a.lerp(b, f)
				var u := (float(j) + f) / (N - 1) * 2.0 - 1.0
				var thick := dmax * sqrt(maxf(1.0 - u * u, 0.0))
				_layer.pile(q.x, q.z, thick, dirs[j])


## Поток встал: у фронта — толстый «язык» из снега
func _stamp_snout() -> void:
	if _layer == null:
		return
	var dmax := 2.4 if kind == K.CHASE else (2.6 if far else 1.8)
	for j in N - 1:
		for off in range(0, 12):
			var b := float(off) * 1.2
			var fp: Vector3 = front[j].lerp(front[j + 1], 0.5) - dirs[j] * b
			var u := (float(j) + 0.5) / (N - 1) * 2.0 - 1.0
			var prof := clampf(b / 3.0, 0.0, 1.0) * (1.0 - clampf((b - 6.0) / 10.0, 0.0, 0.5))
			_layer.pile(fp.x, fp.z, dmax * prof * sqrt(maxf(1.0 - u * u, 0.0)), dirs[j])


# ---------------------------------------------------------------------------
#  Большая лавина: срыв пластов у перевала, осыпи со склонов впереди
# ---------------------------------------------------------------------------

func _make_fractures() -> void:
	# линии отрыва вдоль обоих склонов у перевала — тёмные трещины в снегу
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.28, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for sd in [-1.0, 1.0]:
		var pts := []
		var s := s_start - 45.0
		while s <= s_start + 35.0:
			var x: float = W.center_x(s) + sd * (W.half_w(s) + 34.0 + 4.0 * sin(s * 0.21))
			var z := W.z_of(s)
			pts.append(Vector3(x, _h(x, z) + 0.05, z))
			s += 2.5
		_fractures.append([pts, sd])
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var o := Vector3(-sd * 0.8, 0.5, 0.0)
			for v in [a, b, b + o, a, b + o, a + o]:
				im.surface_add_vertex(v)
	im.surface_end()
	_crack = MeshInstance3D.new()
	_crack.mesh = im
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)


## Пласты ломаются по трещинам и съезжают в долину огромными глыбами
func _release_slabs() -> void:
	for fr in _fractures:
		var pts: Array = fr[0]
		var sd: float = fr[1]
		for k in 9:
			var p: Vector3 = pts[_rng.randi_range(0, pts.size() - 1)]
			_spawn_chunk(p + Vector3(-sd * 2.0, 1.5, 0.0), Vector3(-sd * _rng.randf_range(4.0, 9.0), 1.0, _rng.randf_range(-2.0, -5.0)), 1.8)
			for m in 3:
				_spawn_puff(p + Vector3(-sd * _rng.randf_range(0.0, 6.0), 1.0, _rng.randf_range(-4.0, 4.0)),
					Vector3(-sd * 3.0, _rng.randf_range(1.0, 4.0), 0.0), _rng.randf_range(3.0, 5.0), 4.5)


## Пока лавина гонится — впереди со склонов срываются струйки снега (только для вида)
func _sloughs(delta: float) -> void:
	_slough_t -= delta
	if _slough_t > 0.0:
		return
	_slough_t = _rng.randf_range(0.25, 0.6)
	# струйки сыплются со склонов вокруг того, кто смотрит (только для вида; у каждого свои)
	var me := get_viewport().get_camera_3d()
	if me == null:
		return
	var s := W.s_of(me.global_position.z) + _rng.randf_range(-40.0, 90.0)
	if s > W.SAFE_S or s < 0.0 or me.global_position.distance_to(front_center()) > 260.0:
		return
	var sd := 1.0 if _rng.randf() < 0.5 else -1.0
	var x := W.center_x(s) + sd * (W.half_w(s) + _rng.randf_range(15.0, 35.0))
	var z := W.z_of(s)
	var p := Vector3(x, _h(x, z) + 1.0, z)
	for m in 6:
		_spawn_puff(p + Vector3(0, m * 0.6, _rng.randf_range(-3.0, 3.0)), Vector3(-sd * _rng.randf_range(5.0, 9.0), -_rng.randf_range(2.0, 5.0), 0.0),
			_rng.randf_range(1.2, 2.4), 2.5)
	if _rng.randf() < 0.5:
		_spawn_chunk(p, Vector3(-sd * 6.0, -1.0, 0.0), 0.6)


func _make_crack() -> void:
	# тёмная линия отрыва поперёк склона, по ней пласт и уходит
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.3, 0.42)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var steps := 30
	for i in steps:
		var z0 := zc - width * 0.5 + width * i / steps
		var z1 := zc - width * 0.5 + width * (i + 1) / steps
		var x0 := _x0 + side * 3.0 * sin(z0 * 0.3)
		var x1 := _x0 + side * 3.0 * sin(z1 * 0.3)
		var a := Vector3(x0, _h(x0, z0) + 0.05, z0)
		var b := Vector3(x1, _h(x1, z1) + 0.05, z1)
		var off := Vector3(side * 0.6, 0.0, 0.0)
		for v in [a, b, b + off + Vector3.UP * 0.4, a, b + off + Vector3.UP * 0.4, a + off + Vector3.UP * 0.4]:
			im.surface_add_vertex(v)
	im.surface_end()
	_crack = MeshInstance3D.new()
	_crack.mesh = im
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	# первые глыбы — по линии отрыва
	for k in 14:
		var z := zc + _rng.randf_range(-0.45, 0.45) * width
		var x := _x0 - side * _rng.randf_range(1.0, 6.0)
		_spawn_chunk(Vector3(x, _h(x, z) + 1.4, z), Vector3(-side * 3.0, 0.5, 0.0), 1.6)


static var _ntex: NoiseTexture2D


static func _noise_tex() -> NoiseTexture2D:
	if _ntex == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		_ntex = NoiseTexture2D.new()
		_ntex.width = 256
		_ntex.height = 256
		_ntex.seamless = true
		_ntex.generate_mipmaps = true
		_ntex.noise = fn
	return _ntex


# ---------------------------------------------------------------------------
#  Общие ресурсы (один раз на игру) и прогрев шейдеров
# ---------------------------------------------------------------------------

static var _sh_body: Shader
static var _sh_puff: Shader
static var _s_chunk_mat: StandardMaterial3D
static var _s_chunk_meshes: Array[Mesh] = []
static var _s_spray_draw: Mesh
static var _s_spray_proc: ParticleProcessMaterial


static func body_material() -> ShaderMaterial:
	if _sh_body == null:
		_sh_body = Shader.new()
		_sh_body.code = BODY_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sh_body
	m.set_shader_parameter("noise", _noise_tex())
	if tex_cached(DEBRIS_TEX):
		m.set_shader_parameter("debris", tex_cached(DEBRIS_TEX))
		m.set_shader_parameter("debris_n", tex_cached(DEBRIS_NRM))
	return m


static func puff_material() -> ShaderMaterial:
	if _sh_puff == null:
		_sh_puff = Shader.new()
		_sh_puff.code = PUFF_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sh_puff
	if tex_cached(ATLAS):
		m.set_shader_parameter("atlas", tex_cached(ATLAS))
	return m


## Шаг 137: текстуры лавины держу в памяти всю игру (грузятся при загрузке уровня, а не в момент срыва —
## первая загрузка облака занимала ~75 мс: тот самый рывок при старте лавины)
static var _tex_cache := {}


static func tex_cached(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	_tex_cache[path] = t
	return t


static func chunk_material() -> StandardMaterial3D:
	if _s_chunk_mat == null:
		_s_chunk_mat = StandardMaterial3D.new()
		_s_chunk_mat.albedo_color = Color(0.86, 0.9, 0.98)
		_s_chunk_mat.roughness = 0.92
		_s_chunk_mat.rim_enabled = true
		_s_chunk_mat.rim = 0.35
	return _s_chunk_mat


## Комья: бугристые сферы (каждая вершина сдвинута шумом), чуть приплюснутые
static func chunk_meshes() -> Array[Mesh]:
	if _s_chunk_meshes.is_empty():
		var fn := FastNoiseLite.new()
		fn.frequency = 1.6
		for k in 5:
			fn.seed = 300 + k
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 12
			sm.rings = 7
			var arr := sm.get_mesh_arrays()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in vs.size():
				var v := vs[i]
				var r := 1.0 + fn.get_noise_3dv(v * 2.0) * 0.45
				vs[i] = Vector3(v.x * r, v.y * r * 0.78, v.z * r)
			arr[Mesh.ARRAY_VERTEX] = vs
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.generate_normals()
			_s_chunk_meshes.append(st.commit())
	return _s_chunk_meshes


## Брызги у фронта (материалы общие)
static func make_spray() -> GPUParticles3D:
	if _s_spray_draw == null:
		var tmp := FX.particles(Color(0.96, 0.98, 1.0, 0.85), 500, 1.2, 0.3, 5.0, 12.0, Vector3(0, -6, 0), 40.0, false)
		_s_spray_draw = tmp.draw_pass_1
		_s_spray_proc = tmp.process_material as ParticleProcessMaterial
		tmp.free()
	var p := GPUParticles3D.new()
	p.amount = 500
	p.lifetime = 1.2
	p.one_shot = false
	p.emitting = false
	p.process_material = _s_spray_proc.duplicate()
	p.draw_pass_1 = _s_spray_draw
	return p


## Прогрев: всё, чем рисуется лавина, один раз показать камере (при загрузке уровня).
## Возвращает узел — через пару кадров его удаляют.
static func prewarm_node() -> Node3D:
	var root := Node3D.new()
	root.name = "AvalanchePrewarm"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var b := MeshInstance3D.new()
	b.mesh = quad
	b.material_override = body_material()
	root.add_child(b)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.02), Vector3.ZERO))
	mm.set_instance_custom_data(0, Color(0.01, 0.5, 0.0, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = puff_material()
	root.add_child(mmi)
	var c := MeshInstance3D.new()
	c.mesh = chunk_meshes()[0]
	c.material_override = chunk_material()
	c.scale = Vector3.ONE * 0.02
	root.add_child(c)
	var sp := make_spray()
	sp.scale = Vector3.ONE * 0.01
	root.add_child(sp)
	sp.set_deferred("emitting", true)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.22, 0.3, 0.42)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cr := MeshInstance3D.new()
	cr.mesh = quad
	cr.material_override = cm
	root.add_child(cr)
	return root
