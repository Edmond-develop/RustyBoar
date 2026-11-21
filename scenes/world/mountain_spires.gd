extends Node3D
## Шаг 77: «Пропасть с выступами» (u 0.18, 60 м) — вместо весов-замка.
## Тропа обрывается в пропасть (70 м, туман). В ней — 12 каменных столбов-выступов: широкие, узкие, острые
## (на остриё не встать — только висеть), обледенелые (ледоруб может соскользнуть); одни ниже, другие выше,
## расстояния разные — куда-то допрыгнешь, куда-то нет.
## У начала — стойка с ледорубами (по 2 на игрока). Взял (E) — в руках два ледоруба:
##   ЛКМ — удар левым, ПКМ — правым. В прыжке/падении удар рядом со скалой — ледоруб вонзается, повис на нём.
##   Висишь: ЛКМ/ПКМ по очереди — перехват выше (лезешь), A/D — вбок вокруг столба, Пробел — оттолкнуться и
##   прыгнуть (куда смотришь). Дотянулся до верха — вылез. Силы на весу тратятся; на одном ледорубе — быстрее;
##   на льду ледоруб может соскользнуть, а один ледоруб на льду долго не держит.
##   Сорвался в пропасть — снова у начала. На той стороне — стойка: ледорубы оставляют там (E или сами).
## Решает каждый за себя (у себя); всем — «у кого ледорубы» и поза (mpose 17 — вишу/лезу, 18 — замах в воздухе).

const M := preload("res://scenes/world/mountain_layout.gd")
const SFX := preload("res://scripts/sfx.gd")
const SPIRE_SHADER := preload("res://shaders/spire_rock.gdshader")
const PART := preload("res://scenes/world/peak_part.gd")
const SWING_T := 0.34              ## замах и удар
const HIT_AT := 0.2                ## когда ледоруб входит в камень
const REACH := 0.8                 ## насколько далеко от скалы ещё достаю
const STEP_UP := 0.55              ## перехват выше
const DRAIN2 := 2.2                ## силы на двух ледорубах, в секунду
const DRAIN1 := 6.5                ## на одном
const SWING_COST := 2.5
const ICY_SLIP := 0.3              ## шанс соскользнуть на льду
const ICY_HOLD := 2.2              ## на одном ледорубе на льду держит столько
const MANTLE_T := 1.35
const FALL_DY := 15.0              ## ниже края на столько — сорвался в пропасть (шаг 80: разбился)
## [вдоль тропы (м от начала), вбок (+ наружу), верх (м от линии тропы), радиус, вид]
## шаг 79: раскладка генерируется (одинаково у всех): два «хода» через всю пропасть + россыпь вокруг, ~40 выступов
## виды: mesa (широкий стол), tower (высокая башня), needle (остриё), slab (наклонная плита),
## ledge (с полкой сбоку), ice_tower / ice_needle (целиком изо льда)
var SPIRES: Array = []
const N_SPIRES := 100
const FAR_LOD := 60.0              ## шаг 82: дальше — простые модели выступов
const TYPES := [["mesa", 3.0], ["slab", 2.0], ["tower", 3.0], ["ledge", 2.0], ["needle", 2.0], ["ice_tower", 0.7], ["ice_needle", 0.35]]

var mtn: Node
var is_open := true                ## ботам тут делать нечего
var axes := {}                     ## у кого ледорубы (дрон → true), у всех
var surfs: Array = []              ## поверхности: {kind:"cyl"/"wall", c, r, top, bot, icy, sharp, n, t, lat0, lat1}
var _u0 := 0.0
var _u1 := 0.0
var _h0 := 0.0
var _h1 := 0.0
var _start := Vector3.ZERO
var _rack_a := Vector3.ZERO
var _rack_b := Vector3.ZERO
var _rack_axes: Array[Node3D] = []
var _in_hand := {}                 ## дрон → [ледоруб левый, правый] (модели в руках)
var _sw := {}                      ## мой дрон → [время замаха левой, правой] (−1 — нет)
var _chips: GPUParticles3D
var _axe_mesh: Array = []          ## готовая модель: [меш, материал] по частям
var _hint_t := 0.0
var _rng := RandomNumberGenerator.new()
var _nz := FastNoiseLite.new()
## шаг 82: грузовая люлька на тросе (вдоль задней стены пропасти) — для посылки
const CAB_SPEED := 6.0             ## м/с
const CAB_HANG := 2.6              ## от каретки до верха люльки
var _cab_sl: Array = []            ## точки троса: [s, вбок, высота над линией]
var _cab_pts: Array = []           ## …в мире
var _cab_cum: Array = []           ## длина троса до точки
var _cab_total := 0.0
var cab_g := 0.0                   ## где люлька на тросе (м от станции A)
var cab_dir := 0                   ## 0 стоит, +1 едет к B, −1 к A
var cab_load := false              ## посылка в люльке
var _cab_vis_g := 0.0
var _cab_node: Node3D
var _cab_lever: Array = []         ## [рычаг A, рычаг B] (узлы ручек)
var _cab_prev := [false, false]
var _cab_sync_t := 0.0
var _near_mi: Array = []           ## шаг 84: подробные модели выступов
var _far_mi: Array = []            ## …простые (вдали)
var _ice_mi: Array = []            ## …ледяные
var _rock_m: Material
var _ice_low: StandardMaterial3D
var _gfx := 2
var piles: Array = []              ## шаг 85: брошенные ледорубы (пары) — где лежат
var _pile_nodes: Array = []
var _lod := 0                      ## шаг 82: 0 — близко (подробно), 1 — вдали (просто)
var _hull_acc: Array = []          ## шаг 81: оболочки для коллизии, пока строю столб
var _bv := {}                      ## шаг 80: скорость тела на ледорубах (пружина)
var _cp_set := {}                  ## шаг 80: кому уже поставил точку возрождения у пропасти
var _leap := {}                    ## мой дрон → [сколько ещё, скорость по горизонтали] — оттолкнулся от скалы


func build() -> void:
	add_to_group("part_sockets")
	_rng.randomize()
	_u0 = M.SP_U0
	_u1 = M.sp_u1()
	_h0 = M.height(_u0)
	_h1 = M.height(_u1)
	var b: Node3D = mtn.builder
	_make_axe_model()
	# столбы
	_nz.seed = 7979
	_nz.frequency = 0.45
	_cab_sl = _cable_sl()
	_gen_layout()
	for e in SPIRES:
		var s: float = e[0]
		var u := _u0 + s / M.len_per_u(_u0)
		var c := M.point(u) + M.outward(u) * float(e[1])
		var top := lerpf(_h0, _h1, s / M.SP_LEN) + float(e[2])
		c.y = top
		var ty := String(e[4])
		var sf := {"kind": "cyl", "c": c, "r": float(e[3]), "top": top, "bot": top - 62.0, "icy": ty.begins_with("ice"),
			"sharp": ty.ends_with("needle"), "type": ty}
		surfs.append(sf)
		_build_spire(b, sf)
	# стены пропасти (у начала и у конца) — по ним тоже можно лезть ледорубами; вылезти — только на тропу
	for side in [0, 1]:
		var uu := _u0 if side == 0 else _u1
		var ou := M.outward(uu)
		var perp := Vector3(-ou.z, 0.0, ou.x)          # поперёк луча (стена пропасти идёт по лучу от центра горы)
		var wn := perp if side == 0 else -perp         # нормаль — в пропасть
		var wp := M.point(uu)
		var ed := M.sp_edges(0.0 if side == 0 else M.SP_LEN)
		surfs.append({"kind": "wall", "c": wp, "n": wn, "t": ou, "lat0": ed.x + 1.0,
			"lat1": M.half_out(uu) - 0.3, "top": M.height(uu), "bot": M.height(uu) - 60.0, "icy": false, "sharp": false, "type": "wall",
			"exit0": -M.half_in(uu) + 0.3})
	# стойки с ледорубами у начала и у конца
	_start = M.point(_u0 - 5.0 / M.len_per_u(_u0)) + Vector3.UP * 0.6
	_rack_a = _rack(b, _u0 - 3.0 / M.len_per_u(_u0), true)
	_rack_b = _rack(b, _u1 + 3.0 / M.len_per_u(_u0), false)
	mtn.add_hold("SP_RACK_A", _rack_a, 1.4)
	mtn.add_hold("SP_RACK_B", _rack_b, 1.4)
	for k in 8:
		var ax := Node3D.new()
		_axe_into(ax)
		add_child(ax)
		_rack_axes.append(ax)
	_place_rack_axes()
	mtn.sign_at(_rack_a + M.outward(_u0) * 2.2 - M.tangent(_u0) * 0.8, "ПРОПАСТЬ — 200 м по выступам\nВозьми ледорубы (E у стойки).\nЛКМ — левый, ПКМ — правый.\nНе допрыгнул — бей ледорубом в скалу!\nДЕРЖИ кнопку — ледоруб держит.\nОтпустил обе — падаешь!\nВверх: держи одну, бей другой и держи,\nпотом отпусти первую. A/D — вбок, Пробел — прыжок", Color(1.0, 0.85, 0.5))
	mtn.sign_at(_rack_b + M.outward(_u1) * 2.2 + M.tangent(_u1) * 0.8, "Ледорубы оставь здесь (E)", Color(1.0, 0.85, 0.5))
	_build_cable(b)
	add_to_group("gfx_listeners")
	var gx = get_tree().current_scene.get_node_or_null("Graphics") if get_tree().current_scene else null
	if gx and gx.get("level") != null:
		set_gfx_level.call_deferred(int(gx.get("level")))
	_chips = FX.particles(Color(0.85, 0.9, 1.0), 16, 0.5, 0.05, 1.5, 3.5, Vector3(0, -8.0, 0), 60.0, true)
	add_child(_chips)


func _build_spire(b: Node3D, sf: Dictionary) -> void:
	var c: Vector3 = sf["c"]
	var r: float = sf["r"]
	var top: float = sf["top"]
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = Vector3(c.x, top, c.z)
	body.set_meta("surf_i", surfs.find(sf))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 62.0 if not sf["sharp"] else 61.0
	cs.shape = cyl
	cs.position = Vector3(0, -cyl.height * 0.5 - (0.0 if not sf["sharp"] else 1.0), 0)
	body.add_child(cs)
	if sf["sharp"]:
		# остриё — конус: на нём не устоять
		var cv := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for k in 8:
			var a := TAU * k / 8.0
			pts.append(Vector3(cos(a) * r, -1.0, sin(a) * r))
		pts.append(Vector3(0, 0.35, 0))
		cv.points = pts
		var cs2 := CollisionShape3D.new()
		cs2.shape = cv
		body.add_child(cs2)
	var ty: String = sf["type"]
	if ty == "ledge":
		# полка сбоку (на неё можно спрыгнуть, оттуда — залезть наверх)
		var sd := Vector3(cos(float(c.x) * 0.3), 0, sin(float(c.x) * 0.3)).normalized()
		var lb := CollisionShape3D.new()
		var lbs := BoxShape3D.new()
		lbs.size = Vector3(1.4, 0.5, 1.4)
		lb.shape = lbs
		lb.position = sd * (r + 0.45) + Vector3.DOWN * 1.65
		body.add_child(lb)
		sf["shelf"] = sd
	sf["body"] = body
	_spire_look(b, sf)
	sf.erase("body")


# ---------------------------------------------------------------------------
#  Шаг 79: раскладка выступов
# ---------------------------------------------------------------------------

func _pick_type(rng: RandomNumberGenerator, route: bool) -> String:
	var tot := 0.0
	for e in TYPES:
		if route and String(e[0]).ends_with("needle"):
			continue
		tot += float(e[1])
	var x := rng.randf() * tot
	for e in TYPES:
		if route and String(e[0]).ends_with("needle"):
			continue
		x -= float(e[1])
		if x <= 0.0:
			return String(e[0])
	return "mesa"


func _type_r(ty: String, rng: RandomNumberGenerator) -> float:
	match ty:
		"mesa":
			return rng.randf_range(2.0, 3.3)
		"slab":
			return rng.randf_range(1.6, 2.5)
		"tower":
			return rng.randf_range(1.0, 1.45)
		"ledge":
			return rng.randf_range(1.3, 1.9)
		"needle":
			return rng.randf_range(0.65, 0.95)
		"ice_tower":
			return rng.randf_range(1.1, 1.7)
		_:
			return rng.randf_range(0.7, 1.0)


## Насколько верх выше линии тропы (по виду) — для россыпи
func _type_top(ty: String, rng: RandomNumberGenerator) -> float:
	match ty:
		"mesa":
			return rng.randf_range(-7.0, 0.0)
		"slab":
			return rng.randf_range(-5.0, 1.0)
		"tower":
			return rng.randf_range(0.5, 5.0)
		"ledge":
			return rng.randf_range(-3.0, 2.5)
		"needle":
			return rng.randf_range(0.5, 4.5)
		"ice_tower":
			return rng.randf_range(-2.0, 3.0)
		_:
			return rng.randf_range(0.0, 3.5)


func _fits(lst: Array, s: float, lat: float, r: float, gap: float) -> bool:
	var ed := M.sp_edges(s)
	if s - r < 2.6 or s + r > M.SP_LEN - 2.6 or lat - r < ed.x + 2.5 or lat + r > ed.y - 2.5:
		return false
	# шаг 82: под тросом люльки выступов нет
	if _cab_sl_d(s, lat) < r + 2.6:
		return false
	for e in lst:
		if Vector2(s - float(e[0]), lat - float(e[1])).length() - r - float(e[3]) < gap:
			return false
	return true


## Шаг 80: два хода через 90 м. Шаги: «прыжок» (3–4.2 м, не выше), «далеко/выше» (5–7 м или на 2–4 м выше —
## только ледорубами), «вниз» (низкий выступ на 4–7 м ниже тропы), после него — «вверх» (обязательно лезть)
func _gen_layout() -> void:
	SPIRES.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 800080
	for route in 2:
		var s := 0.0
		var lat := 1.0 if route == 0 else 4.0
		var pr := 0.0
		var ptop := 0.0
		var aim := 3.0 if route == 0 else 9.0
		var prev_kind := "start"
		var n := 0
		while n < 70:
			n += 1
			if n % 3 == 0:
				aim = rng.randf_range(-14.0, -1.0) if route == 0 else rng.randf_range(2.0, 12.0)
			var kind := "jump"
			if prev_kind == "start":
				kind = "jump"
			elif prev_kind == "low":
				kind = "up"
			else:
				var x := rng.randf()
				kind = "jump" if x < 0.36 else ("far" if x < 0.64 else "low")
			var ty := _pick_type(rng, true)
			var r := _type_r(ty, rng)
			var ok := false
			for tr in 30:
				var gap := rng.randf_range(2.5, 3.4) if kind == "jump" else rng.randf_range(5.0, 7.0) if kind == "far" else rng.randf_range(3.0, 5.0)
				var dt := ptop
				match kind:
					"jump":
						dt = ptop - rng.randf_range(0.0, 1.2)
						if prev_kind == "start":
							dt = rng.randf_range(-0.8, -0.2)
					"far":
						# не ниже: с разбега на уровень дальше ~4.4 м не прыгнуть — только ледорубами
						dt = clampf(ptop + rng.randf_range(-0.1, 1.6), ptop - 0.1, 3.5) if rng.randf() < 0.6 else ptop + rng.randf_range(2.0, 4.0)
						if dt > ptop + 1.5:
							gap = rng.randf_range(3.2, 5.0)       # выше — можно и ближе: всё равно не допрыгнуть
					"low":
						dt = -rng.randf_range(4.0, 7.0)
					"up":
						dt = rng.randf_range(-1.0, 1.5)
				dt = clampf(dt, -7.0, 4.5)
				var ang := atan2(aim - lat, 14.0) + rng.randf_range(-0.55, 0.55)
				var dist := pr + gap + r
				var ns := s + cos(ang) * dist
				var nl := lat + sin(ang) * dist
				if ns + r > M.SP_LEN - 2.6:
					break
				if _fits(SPIRES, ns, nl, r, 2.6):
					SPIRES.append([ns, nl, dt, r, ty])
					s = ns
					lat = nl
					pr = r
					ptop = dt
					prev_kind = kind
					ok = true
					break
				r = maxf(r * 0.88, 1.0)
			if not ok:
				break
		# до той стены далеко — ещё один у конца
		if M.SP_LEN - (s + pr) > 4.5:
			for tr2 in 40:
				var r2 := rng.randf_range(1.3, 2.0)
				var ns2 := M.SP_LEN - rng.randf_range(3.2, 4.0) - r2
				var nl2 := clampf(lat + rng.randf_range(-3.0, 3.0), -4.0, 4.0)
				if _fits(SPIRES, ns2, nl2, r2, 2.6):
					SPIRES.append([ns2, nl2, rng.randf_range(-0.8, 0.3), r2, "mesa" if tr2 % 2 == 0 else "ledge"])
					break
	# россыпь вокруг: разные, где повыше, где пониже, подальше друг от друга
	var tries := 0
	while SPIRES.size() < N_SPIRES and tries < 12000:
		tries += 1
		var ty3 := _pick_type(rng, false)
		var n_ice := 0
		for e3 in SPIRES:
			if String(e3[4]).begins_with("ice"):
				n_ice += 1
		if n_ice < 4:
			ty3 = "ice_tower" if n_ice % 2 == 0 or n_ice > 3 else "ice_needle"
		var r3 := _type_r(ty3, rng)
		var s3 := rng.randf_range(3.0, M.SP_LEN - 3.0)
		var ed := M.sp_edges(s3)
		var l3 := rng.randf_range(ed.x + 2.5, ed.y - 2.5)
		if _fits(SPIRES, s3, l3, r3, 3.2):
			var dt3 := _type_top(ty3, rng)
			if (ty3 == "mesa" or ty3 == "slab" or ty3 == "ledge") and rng.randf() < 0.35:
				dt3 = -rng.randf_range(4.0, 7.0)
			SPIRES.append([s3, l3, dt3, r3, ty3])


# ---------------------------------------------------------------------------
#  Шаг 79: модели выступов — гранёные ярусы (пласты), трещины, козырьки и поджимы; лёд — друзы кристаллов
# ---------------------------------------------------------------------------

func _spire_look(_b: Node3D, sf: Dictionary) -> void:
	var c: Vector3 = sf["c"]
	var r: float = sf["r"]
	var ty: String = sf["type"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(c.x) * 13.0 + absf(c.z) * 7.0) + 11
	var depth := float(sf["top"]) - (lerpf(_h0, _h1, 0.5) - M.SP_DEPTH - 6.0)
	var mesh := ArrayMesh.new()
	_hull_acc.clear()
	if ty.begins_with("ice"):
		var st_a := SurfaceTool.new()
		var st_b := SurfaceTool.new()
		st_a.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_b.begin(Mesh.PRIMITIVE_TRIANGLES)
		_ice_cluster(st_a, st_b, r, depth, bool(sf["sharp"]), rng)
		for st: SurfaceTool in [st_a, st_b]:
			st.generate_normals()
			st.index()
			st.commit(mesh)
		mesh.surface_set_material(0, mtn.builder.mat("ice_dark"))
		mesh.surface_set_material(1, mtn.builder.mat("ice"))
	else:
		var seed0 := rng.seed
		for lod in [1, 0]:
			_lod = lod
			rng.seed = seed0
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var horns: Array = []
			_crag(st, r, depth, ty, rng, Vector2(c.x, c.z), horns, sf)
			st.generate_normals()
			st.index()
			var mm := ArrayMesh.new() if lod == 1 else mesh
			st.commit(mm)
			mm.surface_set_material(0, _rock_mat())
			if lod == 1:
				# вдали — простая модель, без теней
				var mf := MeshInstance3D.new()
				mf.mesh = mm
				mf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mf.visibility_range_begin = FAR_LOD
				mf.visibility_range_begin_margin = 8.0
				mf.visibility_range_end = 1000.0
				mf.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				add_child(mf)
				mf.global_position = c
				_far_mi.append(mf)
		_lod = 0
	# шаг 81: всё, что видно у верха (блоки, зубья, рога, кристаллы), — твёрдое: в текстуру не провалиться
	var body: StaticBody3D = sf.get("body")
	if body:
		for pts: PackedVector3Array in _hull_acc:
			var cv := ConvexPolygonShape3D.new()
			cv.points = pts
			var cs := CollisionShape3D.new()
			cs.shape = cv
			body.add_child(cs)
	_hull_acc.clear()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# шаг 82: тени и подробная модель — только вблизи (иначе на всю пропасть — тормоза)
	if ty.begins_with("ice"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 900.0
	else:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # шаг 83: тени выступов — главный тормоз
		mi.visibility_range_end = FAR_LOD
		mi.visibility_range_end_margin = 8.0
	add_child(mi)
	mi.global_position = c
	if ty.begins_with("ice"):
		_ice_mi.append(mi)
	else:
		_near_mi.append(mi)


## Шаг 84: лёгкий материал скалы для выступов (те же текстуры, что у горы)
func _rock_mat() -> Material:
	if _rock_m:
		return _rock_m
	var m := ShaderMaterial.new()
	m.shader = SPIRE_SHADER
	var tm = mtn.builder.mat("rock")
	if tm is ShaderMaterial:
		for k in ["rock_tex", "rock_nrm", "snow_tex", "rock_scale", "snow_tint", "normal_strength"]:
			var v = (tm as ShaderMaterial).get_shader_parameter(k)
			if v != null:
				m.set_shader_parameter(k, v)
	_rock_m = m
	return m


## Шаг 84: настройки графики (F2): на низкой — подробные выступы только совсем рядом, дальние — до 350 м,
## лёд — простым материалом
func set_gfx_level(l: int) -> void:
	_gfx = clampi(l, 0, 2)
	var near_d: float = [35.0, 50.0, FAR_LOD][_gfx]
	var far_d: float = [350.0, 700.0, 1000.0][_gfx]
	for mi in _near_mi:
		if is_instance_valid(mi):
			mi.visibility_range_end = near_d
	for mf in _far_mi:
		if is_instance_valid(mf):
			mf.visibility_range_begin = near_d
			mf.visibility_range_end = far_d
	if _ice_low == null:
		_ice_low = StandardMaterial3D.new()
		_ice_low.albedo_color = Color(0.32, 0.6, 0.85)
		_ice_low.roughness = 0.2
		_ice_low.emission_enabled = true
		_ice_low.emission = Color(0.05, 0.14, 0.24)
	for im in _ice_mi:
		if is_instance_valid(im):
			im.visibility_range_end = far_d
			for si in im.mesh.get_surface_count():
				im.set_surface_override_material(si, _ice_low if _gfx == 0 else null)


## Профиль по глубине от верха (во сколько раз шире/уже радиуса)
func _prof(ty: String, d: float, depth: float) -> float:
	var dk := clampf(d / maxf(depth, 1.0), 0.0, 1.0)
	match ty:
		"mesa":
			if d < 1.2:
				return 1.03
			if d < 3.0:
				return lerpf(1.03, 0.92, smoothstep(1.2, 3.0, d))
			return 0.92 + 0.55 * dk
		"needle", "fang":
			if d < 1.2:
				return pow(clampf((d + 0.35) / 1.55, 0.0, 1.0), 0.7)
			return 1.0 + 0.6 * dk
		"corbel":
			return lerpf(1.0, 0.1, pow(dk, 0.7))
		_:
			return 1.0 + 0.5 * dk


## Многоугольник сечения (грани скалы): углы и радиусы вершин; вытянут вдоль el (слэб — плита)
func _poly(rng: RandomNumberGenerator, el := 1.0, ea := 0.0) -> Array:
	var k := rng.randi_range(5, 7)
	var angs: Array = []
	var rads: Array = []
	for i in k:
		var a := TAU * i / k + rng.randf_range(-0.32, 0.32) * TAU / k
		angs.append(a)
		var ex := absf(cos(a - ea))
		rads.append(rng.randf_range(0.86, 1.14) * lerpf(1.0 / el, el, ex))
	return [angs, rads, (1.0 + cos(PI / k)) * 0.5]


func _poly_r(poly: Array, th: float) -> float:
	var angs: Array = poly[0]
	var rads: Array = poly[1]
	var k := angs.size()
	var t := fposmod(th - float(angs[0]), TAU) + float(angs[0])
	var i := k - 1
	for q in k:
		var a0 := float(angs[q])
		var a1 := float(angs[(q + 1) % k]) + (TAU if q == k - 1 else 0.0)
		if t >= a0 and t < a1:
			i = q
			break
	var pa := Vector2(cos(float(angs[i])), sin(float(angs[i]))) * float(rads[i])
	var pb := Vector2(cos(float(angs[(i + 1) % k])), sin(float(angs[(i + 1) % k]))) * float(rads[(i + 1) % k])
	var dv := Vector2(cos(th), sin(th))
	var e := pb - pa
	var den := dv.cross(e)
	if absf(den) < 0.0001:
		return 1.0
	return (pa.cross(e) / den) / float(poly[2])


## Квад между двумя кольцами (верх j, j+1; низ j, j+1) — лицом наружу
func _quad(st: SurfaceTool, u0: Vector3, u1: Vector3, l0: Vector3, l1: Vector3) -> void:
	st.add_vertex(u1)
	st.add_vertex(u0)
	st.add_vertex(l0)
	st.add_vertex(u1)
	st.add_vertex(l0)
	st.add_vertex(l1)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Шаг 80: скала-зуб. Главный столб (на нём стоять и висеть) + вокруг 2–5 «зубьев»-контрфорсов разной высоты
## (острые, наклонные, с расщелинами между ними); у башен и острий иногда «рог» выше верха (твёрдый).
## Грани плоские (резкие), стыки блоков — трещины, козырьки и полочки (на них снег)
func _crag(st: SurfaceTool, r: float, depth: float, ty: String, rng: RandomNumberGenerator, wo: Vector2, horns: Array, sf: Dictionary) -> void:
	var lean := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.01, 0.035)
	var el := rng.randf_range(1.0, 1.18)
	if ty == "slab":
		el = rng.randf_range(1.3, 1.5)
	var ea := rng.randf() * TAU
	var main_ty := "fang" if ty == "needle" else ty
	_pillar(st, Vector2.ZERO, 0.0, r, depth, main_ty, rng, wo, lean, el, ea, true)
	# зубья вокруг
	var nb := rng.randi_range(2, 5) if r > 1.2 else rng.randi_range(1, 3)
	var a0 := rng.randf() * TAU
	for k in nb:
		var a := a0 + TAU * k / nb + rng.randf_range(-0.4, 0.4)
		var br := r * rng.randf_range(0.32, 0.55)
		var bc := Vector2.from_angle(a) * r * rng.randf_range(0.62, 0.85)
		var horn := (ty == "tower" or ty == "needle") and k == 0 and rng.randf() < 0.7
		var btop := rng.randf_range(0.6, 2.2) if horn else -rng.randf_range(1.8, 9.0)
		if ty == "mesa" or ty == "slab" or String(sf.get("type", "")) == "ledge":
			btop = -rng.randf_range(2.2, 10.0)
		var bdep := minf(depth, btop + 28.0 + rng.randf_range(0.0, 10.0))
		var pts := _pillar(st, bc, btop, br, bdep, "fang", rng, wo + bc * 7.0, lean * rng.randf_range(0.5, 1.6) + Vector2.from_angle(a) * 0.015, rng.randf_range(1.0, 1.3), rng.randf() * TAU, false)
		if horn:
			horns.append(pts)
	if ty == "ledge":
		var sd: Vector3 = sf.get("shelf", Vector3.RIGHT)
		_pillar(st, Vector2(sd.x, sd.z) * (r + 0.35), -1.38, 0.82, 3.6, "corbel", rng, wo + Vector2(5, 5), Vector2.ZERO, 1.1, rng.randf() * TAU, true)


## Один столб: блоки с гранёным сечением (у каждого своё), стыки — трещина + козырёк/полочка; верх — плоский
## (с зубчиками по краю) или остриё (смещено вбок). Возвращает точки верхних 3 м (для коллизии рога)
func _pillar(st: SurfaceTool, cxz: Vector2, top: float, r: float, depth: float, ty: String, rng: RandomNumberGenerator, wo: Vector2, lean: Vector2, el: float, ea: float, flat_top: bool) -> PackedVector3Array:
	var pr := RandomNumberGenerator.new()
	pr.seed = rng.randi()
	# шаг 82: меньше треугольников; вдали — простая модель (_lod 1)
	var N := (10 if r < 0.9 else (14 if r < 1.6 else 17)) if _lod == 0 else (5 if r < 0.9 else 7)
	var sharp := ty == "fang" or ty == "needle"
	var cracks: Array = []
	for k in pr.randi_range(1, 3):
		cracks.append([pr.randf() * TAU, pr.randf_range(0.04, 0.09), pr.randf_range(0.1, 0.2), pr.randf_range(0.0, 6.0)])
	var tilt := Vector2.ZERO
	if ty == "slab":
		tilt = Vector2.from_angle(pr.randf() * TAU) * pr.randf_range(0.09, 0.13)
	var tip_off := Vector2.from_angle(pr.randf() * TAU) * r * pr.randf_range(0.1, 0.35)
	var y := top + (0.35 if sharp and flat_top else (r * pr.randf_range(0.9, 1.8) if sharp else 0.0))
	var y_tip := y
	var taper := 1.55 if flat_top else r * pr.randf_range(1.8, 3.2)
	var band := 0
	var twist := pr.randf() * TAU
	var prev := PackedVector3Array()
	var cap_ring := PackedVector3Array()
	var hp := PackedVector3Array()
	var near := 14.0 if ty != "corbel" else 99.0
	var hacc := PackedVector3Array()
	st.set_smooth_group(-1)
	while y > top - depth + 0.01:
		var d0 := top - y
		var bh := pr.randf_range(1.8, 4.5) if d0 < near else pr.randf_range(5.0, 9.0)
		if _lod == 1:
			bh = pr.randf_range(4.0, 7.0) if d0 < near else pr.randf_range(12.0, 18.0)
		if band == 0 and ty == "mesa":
			bh = pr.randf_range(1.1, 1.5)
		if band == 0 and sharp:
			bh = maxf(bh, taper + 0.6)
		if ty == "corbel":
			bh = depth
		var y1 := maxf(y - bh, top - depth)
		var poly := _poly(rng, el, ea + pr.randf_range(-0.2, 0.2))
		twist += pr.randf_range(-0.35, 0.35)
		var jk := pr.randf()
		var k_top := pr.randf_range(1.04, 1.09) if jk < 0.3 else (pr.randf_range(0.9, 0.95) if jk < 0.5 else pr.randf_range(0.98, 1.02))
		var k_bot := pr.randf_range(0.94, 1.03)
		var step := (1.25 if d0 < near else 7.0) if _lod == 0 else 99.0
		if sharp and band == 0:
			step = 0.35 if _lod == 0 else 0.8
		var nr := maxi(2 if _lod == 0 else 1, ceili((y - y1) / step))
		var rings: Array = []
		for i in nr + 1:
			var f := float(i) / nr
			var yy := lerpf(y, y1, f)
			var dd := top - yy
			var ring := PackedVector3Array()
			var bk := lerpf(k_top, k_bot, f)
			# трещина у стыка блоков (узкая полоска потоньше)
			if i == nr and y1 > top - depth + 0.5:
				bk *= 0.9
			var ctr := cxz + lean * maxf(dd, 0.0)
			var tt := clampf((y_tip - yy) / taper, 0.0, 1.0)
			var pk := pow(tt, 0.7) * (1.0 + 0.6 * clampf(dd / maxf(depth, 1.0), 0.0, 1.0)) if sharp else _prof(ty, dd, depth)
			if sharp:
				ctr += tip_off * (1.0 - tt)
			for j in N + 1:
				var th := TAU * float(j % N) / N
				var rr := r * pk * _poly_r(poly, th - twist) * bk
				# вертикальные борозды и бугры
				rr *= 1.0 + 0.05 * _nz.get_noise_3d(wo.x * 3.0 + cos(th) * 6.0, yy * 0.22, wo.y * 3.0 + sin(th) * 6.0) \
					+ 0.04 * _nz.get_noise_3d(wo.x + cos(th) * 2.0, yy * 0.9, wo.y + sin(th) * 2.0)
				if dd > 12.0:
					rr *= 1.0 + 0.2 * _nz.get_noise_3d(wo.x * 0.3 + cos(th), yy * 0.1, wo.y * 0.3 + sin(th))
				for cr in cracks:
					if dd > float(cr[3]):
						rr *= 1.0 - float(cr[2]) * exp(-pow(angle_difference(th, float(cr[0])) / float(cr[1]), 2.0))
				var yv := yy
				if band == 0 and i == 0 and tilt != Vector2.ZERO:
					yv += (cos(th) * tilt.x + sin(th) * tilt.y) * rr
				# сколы: каждая вершина чуть своя (грани — неровные, как у колотого камня)
				if j < N and not (sharp and tt < 0.05):
					rr *= 1.0 + pr.randf_range(-0.045, 0.045)
				elif j == N:
					rr = Vector2(ring[0].x - ctr.x, ring[0].z - ctr.y).length()
				var v := Vector3(ctr.x + cos(th) * rr, yv, ctr.y + sin(th) * rr)
				ring.append(v)
				if yy > top - 3.0 and j % 2 == 0:
					hp.append(v)
			rings.append(ring)
		# шаг 81: коллизия блока (оболочка верхнего и нижнего кольца) — для всего, что выше 16 м от верха
		# шаг 84: одна оболочка на столб — верхние ~6 м (меньше форм — физика и камера легче)
		if _lod == 0 and y_tip - y < 6.0:
			var ra0: PackedVector3Array = rings[0]
			var rb0: PackedVector3Array = rings[mini(nr, maxi(1, ceili((6.0 - (y_tip - y)) / maxf(step, 0.01))))]
			for jh in range(0, N, 2):
				var v0: Vector3 = ra0[jh]
				if flat_top and band == 0 and not sharp:
					v0.y = minf(v0.y, top + 0.05)
				hacc.append(v0)
				hacc.append(rb0[jh])
		# зубчики по краю плоского верха
		if band == 0 and not sharp and flat_top:
			var r0: PackedVector3Array = rings[0]
			for q in pr.randi_range(2, 4):
				var jj := pr.randi_range(0, N - 1)
				var up := pr.randf_range(0.12, 0.35)
				r0[jj] = r0[jj] + Vector3.UP * up
				if jj == 0:
					r0[N] = r0[0]
			rings[0] = r0
		if not prev.is_empty():
			var top_ring: PackedVector3Array = rings[0]
			for j2 in N:
				_quad(st, prev[j2], prev[j2 + 1], top_ring[j2], top_ring[j2 + 1])
		else:
			cap_ring = rings[0]
		for i2 in nr:
			var ra: PackedVector3Array = rings[i2]
			var rb: PackedVector3Array = rings[i2 + 1]
			for j3 in N:
				_quad(st, ra[j3], ra[j3 + 1], rb[j3], rb[j3 + 1])
		prev = rings[nr]
		y = y1
		band += 1
	if hacc.size() >= 4:
		_hull_acc.append(hacc)
	# шапка: плоская, чуть неровная (снег ляжет сам)
	if not sharp and not cap_ring.is_empty():
		var cc := Vector3(cxz.x, top + 0.04, cxz.y)
		var inner := PackedVector3Array()
		for j4 in N + 1:
			var v4: Vector3 = cap_ring[j4]
			var w := Vector3(cxz.x, 0, cxz.y).lerp(Vector3(v4.x, 0, v4.z), 0.8)
			w.y = top + 0.05 + 0.05 * _nz.get_noise_2d(wo.x + w.x * 3.0, wo.y + w.z * 3.0)
			inner.append(w)
		inner[N] = inner[0]
		for j5 in N:
			_quad(st, inner[j5], inner[j5 + 1], cap_ring[j5], cap_ring[j5 + 1])
			_tri(st, cc, inner[j5], inner[j5 + 1])
	return hp


## Ледяная друза: главный шестигранный кристалл до самого дна, вокруг — кристаллы поменьше (наклонены наружу)
func _ice_cluster(st_a: SurfaceTool, st_b: SurfaceTool, r: float, depth: float, sharp: bool, rng: RandomNumberGenerator) -> void:
	var rot := rng.randf() * TAU
	if sharp:
		_prism(st_a, Vector3(0, -depth, 0), Vector3.UP, r * 1.5, r * 1.05, depth - 1.0, 1.35, rot, rng)
	else:
		_prism(st_a, Vector3(0, -depth, 0), Vector3.UP, r * 1.5, r * 1.06, depth, 0.1, rot, rng)
	# крупные сбоку (наполовину в главном): торчат пониже края
	for k in rng.randi_range(3, 5):
		var a := rot + TAU * k / 4.6 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var ln := rng.randf_range(5.0, 12.0)
		var tip_y := -rng.randf_range(1.0, 3.5)
		var ax := (Vector3.UP + out * rng.randf_range(0.06, 0.2)).normalized()
		var base := Vector3(0, tip_y - ln, 0) + out * r * 0.7 - ax * 0.0
		_prism(st_b if k % 2 == 0 else st_a, base, ax, r * rng.randf_range(0.42, 0.6), r * rng.randf_range(0.35, 0.5), ln, rng.randf_range(0.4, 0.9), rng.randf() * TAU, rng)
	# мелкие у края: веером наружу-вверх
	for k2 in rng.randi_range(4, 7):
		var a2 := rot + TAU * k2 / 6.0 + rng.randf_range(-0.35, 0.35)
		var out2 := Vector3(cos(a2), 0, sin(a2))
		var ax2 := (Vector3.UP + out2 * rng.randf_range(0.45, 0.95)).normalized()
		var l2 := rng.randf_range(0.7, 1.7)
		var b2 := out2 * r * rng.randf_range(0.8, 0.95) + Vector3.DOWN * rng.randf_range(0.7, 1.3)
		_prism(st_b, b2, ax2, rng.randf_range(0.1, 0.2) * maxf(r, 1.0), rng.randf_range(0.08, 0.16) * maxf(r, 1.0), l2, rng.randf_range(0.15, 0.35), rng.randf() * TAU, rng)
	# сосульки под краем
	for k3 in rng.randi_range(5, 9):
		var a3 := rng.randf() * TAU
		var p3 := Vector3(cos(a3), 0, sin(a3)) * r * 1.02 + Vector3.DOWN * rng.randf_range(0.3, 1.2)
		_prism(st_b, p3, Vector3.DOWN, rng.randf_range(0.05, 0.1), 0.02, rng.randf_range(0.5, 1.4), 0.0, rng.randf() * TAU, rng)


## Шестигранная призма вдоль оси (основание → верх), с пирамидкой-остриём; грани плоские
func _prism(st: SurfaceTool, base: Vector3, axis: Vector3, r0: float, r1: float, length: float, tip: float, rot: float, rng: RandomNumberGenerator) -> void:
	var a := axis.normalized()
	var refv := Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.FORWARD
	var uu := a.cross(refv).normalized()
	var vv := uu.cross(a)
	var jit: Array = []
	for k in 6:
		jit.append(rng.randf_range(0.86, 1.12))
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for k2 in 7:
		var th := rot + TAU * float(k2 % 6) / 6.0
		var dir := uu * cos(th) + vv * sin(th)
		lo.append(base + dir * r0 * float(jit[k2 % 6]))
		hi.append(base + a * length + dir * r1 * float(jit[k2 % 6]))
	var apex := base + a * (length + tip)
	if r0 > 0.12 and (base + a * length).y > -6.0 and _hull_acc.size() < 7:
		var hp2 := PackedVector3Array()
		for k4 in 6:
			hp2.append(lo[k4])
			hp2.append(hi[k4])
		hp2.append(apex)
		_hull_acc.append(hp2)
	st.set_smooth_group(-1)
	for k3 in 6:
		_quad(st, hi[k3], hi[k3 + 1], lo[k3], lo[k3 + 1])
		_tri(st, apex, hi[k3], hi[k3 + 1])


## Стойка: деревянная рама, на ней ледорубы. Возвращает, где стоять
func _rack(b: Node3D, u: float, start: bool) -> Vector3:
	var p := M.point(u) - M.outward(u) * (M.half_in(u) - 1.0)
	p.y = M.height(u)
	var bas := Basis(M.outward(u), Vector3.UP, -M.tangent(u))
	b.box(Vector3(1.8, 0.08, 0.3), p + Vector3.UP * 1.25, bas, "wood_dark")
	b.box(Vector3(1.8, 0.08, 0.3), p + Vector3.UP * 0.35, bas, "wood_dark")
	for sx in [-0.85, 0.85]:
		b.beam(p + bas * Vector3(sx, 0, 0), p + bas * Vector3(sx, 1.4, 0), 0.05, "wood_dark", 6)
	b.box(Vector3(2.0, 0.12, 0.5), p + Vector3.UP * 1.45, bas, "snowblock")
	var stand := p + M.outward(u) * 1.3
	return stand


## Ледорубы на стойках: у начала — по 2 на каждого, кто ещё без них; у конца — те, что оставили
func _place_rack_axes() -> void:
	var humans := 0
	for d in get_tree().get_nodes_in_group("player"):
		if not bool(d.get("is_bot")):
			humans += 1
	humans = clampi(humans, 1, 4)
	var on_a := maxi(humans * 2 - axes.size() * 2 - piles.size() * 2, 0)
	var on_b := mini(int(get_meta("left_b", 0)), 8)
	var i := 0
	for k in _rack_axes.size():
		var ax := _rack_axes[k]
		var at_a := k < on_a
		var at_b := not at_a and k - on_a < on_b
		ax.visible = at_a or at_b
		if not ax.visible:
			continue
		var u := _u0 - 3.0 / M.len_per_u(_u0) if at_a else _u1 + 3.0 / M.len_per_u(_u0)
		var slot := k if at_a else k - on_a
		var p := M.point(u) - M.outward(u) * (M.half_in(u) - 1.0)
		p.y = M.height(u)
		var side := M.outward(u)
		ax.global_transform = Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)) * Basis(Vector3.RIGHT, PI * 0.5 - 0.15), p + side * (-0.75 + slot * 0.21) + Vector3.UP * 0.95 - M.tangent(u) * 0.12)
		i += 1


# ---------------------------------------------------------------------------
#  Модель ледоруба
# ---------------------------------------------------------------------------

func _make_axe_model() -> void:
	var mb = PART.ModelBuilder.new()
	# рукоять вдоль −Z (к голове), по +Z — штычок; верх рукояти изогнут
	mb.beam(Vector3(0, 0, 0.13), Vector3(0, 0.0, -0.2), 0.024, "dark", 8)
	mb.beam(Vector3(0, 0, -0.2), Vector3(0, 0.05, -0.5), 0.022, "paint_b", 8)
	mb.cyl(0.028, 0.03, 0.17, Vector3(0, 0, 0.03), Basis(Vector3.RIGHT, PI * 0.5), "rubber", 8)
	mb.cyl(0.005, 0.02, 0.07, Vector3(0, 0, 0.165), Basis(Vector3.RIGHT, -PI * 0.5), "steel", 6)
	# голова: клюв (длинный, загнут, с зубьями) — по +Y, лопатка — по −Y
	var head := Vector3(0, 0.05, -0.52)
	mb.box(Vector3(0.034, 0.1, 0.07), head, Basis.IDENTITY, "steel")
	mb.box(Vector3(0.04, 0.05, 0.075), head + Vector3(0, 0.0, 0.0), Basis.IDENTITY, "paint_r")
	for k in 5:
		var y := 0.07 + k * 0.05
		mb.box(Vector3(0.016, 0.056, 0.036 - k * 0.005), head + Vector3(0, y, 0.012 + k * k * 0.006), Basis(Vector3.RIGHT, 0.2 + k * 0.12), "steel")
	for k2 in 4:
		mb.box(Vector3(0.018, 0.014, 0.014), head + Vector3(0, 0.08 + k2 * 0.05, -0.02 + k2 * k2 * 0.004), Basis.IDENTITY, "dark")
	mb.box(Vector3(0.07, 0.11, 0.01), head + Vector3(0, -0.1, 0.0), Basis(Vector3.RIGHT, -0.25), "steel")
	var tm := TorusMesh.new()
	tm.inner_radius = 0.04
	tm.outer_radius = 0.052
	tm.rings = 12
	tm.ring_segments = 4
	mb.add(tm, Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(0, -0.06, 0.08)), "paint_r")
	var tmp := Node3D.new()
	mb.commit(tmp, Callable(PART, "mat"))
	for c in tmp.get_children():
		_axe_mesh.append([(c as MeshInstance3D).mesh, (c as MeshInstance3D).material_override])
	tmp.free()


func _axe_into(parent: Node3D) -> void:
	for e in _axe_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = e[0]
		mi.material_override = e[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


# ---------------------------------------------------------------------------
#  Взять / оставить (E у стойки) — зовёт игрок
# ---------------------------------------------------------------------------

func try_socket(d: Node3D) -> bool:
	if d.get("held_parcel") != null:
		return false
	var p := d.global_position
	var pid := int(d.peer_id)
	if not axes.has(pid) and _pile_near(p) >= 0:
		take_axes(d)
		return true
	if p.distance_to(_rack_a) < 1.6 and not axes.has(pid):
		_ask(pid, true)
		return true
	if p.distance_to(_rack_b) < 1.6 and axes.has(pid):
		_ask(pid, false)
		return true
	return false


func _ask(pid: int, on: bool) -> void:
	if multiplayer.is_server():
		_req(pid, on)
	else:
		_req.rpc_id(1, pid, on)


@rpc("any_peer", "call_remote", "reliable")
func _req(pid: int, on: bool) -> void:
	if not multiplayer.is_server():
		return
	if mtn._online():
		_set_axes.rpc(pid, on)
	else:
		_set_axes(pid, on)


@rpc("authority", "call_local", "reliable")
func _set_axes(pid: int, on: bool) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	if on:
		axes[pid] = true
	else:
		if axes.has(pid):
			set_meta("left_b", int(get_meta("left_b", 0)) + 2)
		axes.erase(pid)
	if d:
		d.set("ice_axes", on)
		if on:
			SFX.play(self, d.global_position + Vector3.UP, "clank", -6.0, 1.5)
	_hand_models(pid, on)
	_place_rack_axes()


## Модели ледорубов в руках (у всех)
func _hand_models(pid: int, on: bool) -> void:
	if _in_hand.has(pid):
		for n in _in_hand[pid]:
			if is_instance_valid(n):
				(n as Node3D).queue_free()
		_in_hand.erase(pid)
	if not on:
		return
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null:
		return
	var suit = d.get("suit")
	if suit == null or not suit.has_method("attach_to_hand"):
		return
	var arr := []
	for i in 2:
		var holder := Node3D.new()
		holder.name = "IceAxe%d" % i
		_axe_into(holder)
		suit.attach_to_hand(i, holder)
		arr.append(holder)
	_in_hand[pid] = arr


# ---------------------------------------------------------------------------
#  Каждый кадр: мой дрон
# ---------------------------------------------------------------------------

func in_field(p: Vector3) -> bool:
	return absf(p.y - lerpf(_h0, _h1, 0.5)) < 80.0 and not is_nan(M.sp_carve(p.x, p.z, 0.5))


## Сюда не вылезти (остриё; стена пропасти — кроме того места, где тропа)
func _no_top(sf: Dictionary, a: float) -> bool:
	if bool(sf["sharp"]):
		return true
	return String(sf["kind"]) == "wall" and a < float(sf.get("exit0", -99.0))


func local(d: Node3D, _hp: String, _holding: bool, delta: float) -> void:
	var pid := int(d.peer_id)
	var p := d.global_position
	# сорвался в пропасть — к началу
	var u := M.u_at(p)
	var sq := M.sp_local(p.x, p.z)
	var line := lerpf(_h0, _h1, clampf(sq.x / M.SP_LEN, 0.0, 1.0)) if not is_nan(sq.x) else _h0
	var fell := p.y < line - FALL_DY and not is_nan(M.sp_carve(p.x, p.z, 1.0))
	# шаг 79: в пропасти удары о скалу мягкие — царапины, но руки-ноги целы (чтобы успеть зацепиться)
	d.set("impact_soft", fell or in_field(p) or d.snow.climb == 8 or d.snow.climb == 9)
	if fell:
		_respawn(d)
		return
	# шаг 80: у пропасти — точка возрождения (у стойки)
	if in_field(p) and not _cp_set.has(pid) and d.has_method("set_checkpoint"):
		_cp_set[pid] = true
		d.set_checkpoint(_start)
	# прыжок от скалы: в полёте держу набранную скорость (иначе гасится без бега)
	var lp: Array = _leap.get(pid, [])
	if not lp.is_empty():
		lp[0] = float(lp[0]) - delta
		var hv: Vector3 = lp[1]
		if float(lp[0]) <= 0.0 or (d.is_on_floor() and float(lp[0]) < 0.75):
			_leap.erase(pid)
		else:
			d.velocity.x = hv.x
			d.velocity.z = hv.z
	if not axes.has(pid):
		if d.snow.mpose == 18:
			d.snow.set_mpose(0)
		return
	# далеко ушёл с ледорубами за ту сторону — оставил на стойке сам
	if u > _u1 + 30.0 / M.len_per_u(_u0) and d.is_local and multiplayer.is_server():
		_req(pid, false)
		return
	var sw: Array = _sw.get(pid, [-1.0, -1.0])
	_sw[pid] = sw
	# удары в свободном состоянии (в воздухе — может зацепиться)
	for h in 2:
		if float(sw[h]) >= 0.0:
			var t0 := float(sw[h])
			sw[h] = t0 + delta
			if t0 < HIT_AT and float(sw[h]) >= HIT_AT:
				_free_hit(d, h)
				if d.snow.climb == 8:
					return
			if float(sw[h]) >= SWING_T:
				sw[h] = -1.0
	var press := [_pressed(d, 0), _pressed(d, 1)]
	for h2 in 2:
		if press[h2] and (float(sw[h2]) < 0.0 or float(sw[h2]) > HIT_AT + 0.05):
			sw[h2] = 0.0
			SFX.play(self, d.global_position + Vector3.UP * 1.6, "puff", -12.0, 1.6)
	var swing_h := 0 if float(sw[0]) >= 0.0 else (1 if float(sw[1]) >= 0.0 else -1)
	if swing_h >= 0:
		d.snow.set_mpose(18, float(swing_h) + clampf(float(sw[swing_h]) / SWING_T, 0.0, 0.99), d.global_position, -d.visual.global_basis.z)
	elif d.snow.mpose == 18:
		d.snow.set_mpose(0)


## Шаг 81: держит ли кнопку этой руки (ЛКМ — левая, ПКМ — правая)
func _holding(d: Node3D, h: int) -> bool:
	if bool(d.get("is_bot")):
		return true
	return d._held("use_item" if h == 0 else "use_alt")


## Шаг 81: где на самом деле скала столба si под углом a на высоте y (расстояние от оси; лучом — по коллизии)
func _surf_rad(d: Node3D, si: int, a: float, y: float) -> float:
	var sf: Dictionary = surfs[si]
	var c: Vector3 = sf["c"]
	var r := float(sf["r"])
	var n := Vector3(cos(a), 0.0, sin(a))
	var from := Vector3(c.x, y, c.z) + n * (r * 1.6 + 2.0)
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(c.x, y, c.z))
	q.exclude = [d.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit["collider"] is Node or int((hit["collider"] as Node).get_meta("surf_i", -1)) != si:
		return r
	var hp: Vector3 = hit["position"]
	return clampf(Vector2(hp.x - c.x, hp.z - c.z).length(), r * 0.8, r * 1.6 + 1.5)


func _pressed(d: Node3D, h: int) -> bool:
	if bool(d.get("is_bot")):
		return false
	return d._just("use_item" if h == 0 else "use_alt")


## Удар ледорубом не на весу: рядом скала (а я в воздухе или у стены) — вонзился, повис
func _free_hit(d: Node3D, h: int) -> void:
	var fwd: Vector3 = -d.visual.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var reach := d.global_position + Vector3.UP * 1.75 + fwd * 0.45
	var best := -1
	var bd := REACH
	var hit_y := 0.0
	var hit_a := 0.0
	# шаг 81: сначала лучом — в настоящую скалу (зубья, выступы, кристаллы)
	var q0 := PhysicsRayQueryParameters3D.create(d.global_position + Vector3.UP * 1.6, d.global_position + Vector3.UP * 1.75 + fwd * 1.35)
	q0.exclude = [d.get_rid()]
	var h0 := get_world_3d().direct_space_state.intersect_ray(q0)
	if not h0.is_empty() and h0["collider"] is Node:
		var si0 := int((h0["collider"] as Node).get_meta("surf_i", -1))
		if si0 >= 0:
			var c0: Vector3 = surfs[si0]["c"]
			var hp0: Vector3 = h0["position"]
			best = si0
			bd = 0.0
			hit_a = atan2(hp0.z - c0.z, hp0.x - c0.x)
			hit_y = minf(reach.y, float(surfs[si0]["top"]) + 0.4)
	for i in surfs.size():
		if best >= 0 and bd == 0.0:
			break
		var sf: Dictionary = surfs[i]
		var q := _project(sf, reach)
		if q.is_empty():
			continue
		if float(q[0]) < bd:
			bd = float(q[0])
			best = i
			hit_a = float(q[1])
			hit_y = float(q[2])
	if best < 0:
		SFX.play(self, reach, "puff", -10.0, 1.3)
		return
	var sf2: Dictionary = surfs[best]
	var on_floor: bool = d.is_on_floor()
	if on_floor and hit_y > float(sf2["top"]) - 0.4:
		return                                      # стою наверху — бить некуда
	var hp := _surf_pt(sf2, hit_a, minf(hit_y, float(sf2["top"]) - 0.05))
	if bool(sf2["icy"]) and _rng.randf() < ICY_SLIP:
		_ice_fx(hp, true)
		if d == Network.local_player:
			d.add_shake(0.06)
			mtn.say("Лёд! Ледоруб соскользнул — бей ещё!")
		return
	_ice_fx(hp, false)
	if not _holding(d, h):
		return                                      # ударил, но кнопку не держу — не зацепился
	if hit_y > float(sf2["top"]) - 0.12 and not _no_top(sf2, hit_a):
		# зацепился за самый край — сразу вылезаю
		_start_mantle(d, best, hit_a)
		return
	_sw[int(d.peer_id)] = [-1.0, -1.0]
	var data := {"s": best, "a": hit_a, "ax": [NAN, NAN], "sw": -1, "swt": 0.0, "tgt": 0.0, "one_t": 0.0, "jolt": 0.25,
		"from": d.global_position}
	data["ax"][h] = minf(hit_y, float(sf2["top"]) - 0.25)
	d.snow.start_scripted(8, self, data)
	if d == Network.local_player:
		d.add_shake(0.14)


## Расстояние от точки до поверхности (если она рядом и по высоте подходит): [дист, угол/вбок, высота]
func _project(sf: Dictionary, p: Vector3) -> Array:
	if p.y > float(sf["top"]) + 0.5 or p.y < float(sf["bot"]):
		return []
	if String(sf["kind"]) == "cyl":
		var c: Vector3 = sf["c"]
		var dv := Vector2(p.x - c.x, p.z - c.z)
		var dist := dv.length() - float(sf["r"])
		if dist < -0.4:
			return []
		return [maxf(dist, 0.0), atan2(dv.y, dv.x), p.y]
	var c2: Vector3 = sf["c"]
	var n: Vector3 = sf["n"]
	var dn := (p - c2).dot(n)
	var lat := (p - c2).dot(sf["t"] as Vector3)
	if dn < -0.4 or lat < float(sf["lat0"]) or lat > float(sf["lat1"]):
		return []
	return [maxf(dn, 0.0), lat, p.y]


## Точка на поверхности (угол — у столба, «вбок» — у стены)
func _surf_pt(sf: Dictionary, a: float, y: float) -> Vector3:
	if String(sf["kind"]) == "cyl":
		var c: Vector3 = sf["c"]
		return Vector3(c.x + cos(a) * float(sf["r"]), y, c.z + sin(a) * float(sf["r"]))
	var c2: Vector3 = sf["c"]
	var q := c2 + (sf["t"] as Vector3) * a
	q.y = y
	return q


func _surf_n(sf: Dictionary, a: float) -> Vector3:
	if String(sf["kind"]) == "cyl":
		return Vector3(cos(a), 0.0, sin(a))
	return sf["n"]


func _ice_fx(at: Vector3, slip: bool) -> void:
	_chips.global_position = at
	_chips.restart()
	_chips.emitting = true
	if slip:
		SFX.play(self, at, "slide", -2.0, 1.6)
		SFX.play(self, at, "spark", -4.0)
	else:
		SFX.play(self, at, "thunk", -3.0, 1.5)
		SFX.play(self, at, "clank", -9.0, 1.8)


## Шаг 80: сорвался в пропасть — разбился (возрождение у стойки перед пропастью)
func _respawn(d: Node3D) -> void:
	if d.snow.busy():
		d.snow.end_scripted()
	d.snow.set_mpose(0)
	_leap.erase(int(d.peer_id))
	if d.has_method("set_checkpoint"):
		d.set_checkpoint(_start)
	if d.has_method("kill"):
		d.kill("Сорвался в пропасть!\nНе допрыгиваешь — бей ледорубом в скалу (ЛКМ/ПКМ)")
	else:
		d.teleport_to(_start)


# ---------------------------------------------------------------------------
#  На весу (snow_state зовёт drive, пока climb 8 / 9)
# ---------------------------------------------------------------------------

func drive(d: Node3D, kind: int, t: float, data: Dictionary, delta: float) -> void:
	if kind == 9:
		_drive_mantle(d, t, data)
		return
	var sf: Dictionary = surfs[int(data["s"])]
	var ax: Array = data["ax"]
	var pid := int(d.peer_id)
	var a := float(data["a"])
	var n := _surf_n(sf, a)
	var top := float(sf["top"])
	# A/D — вбок (вокруг столба / вдоль стены)
	var mv := 0.0
	if d._held("move_left"):
		mv -= 1.0
	if d._held("move_right"):
		mv += 1.0
	if mv != 0.0 and int(data["sw"]) < 0:
		var right := (-n).cross(Vector3.UP)          # лицом к скале: «вправо»
		if String(sf["kind"]) == "cyl":
			var sg := signf(right.dot(Vector3(-sin(a), 0.0, cos(a))) + 0.0001)
			a += mv * 0.9 / float(sf["r"]) * delta * sg
		else:
			var sg2 := signf(right.dot(sf["t"] as Vector3) + 0.0001)
			a = clampf(a + mv * 1.0 * delta * sg2, float(sf["lat0"]), float(sf["lat1"]))
		data["a"] = a
		n = _surf_n(sf, a)
	# шаг 81: держу кнопку — ледоруб держит; отпустил — выдернул (отпустил оба — падаю)
	for hr in 2:
		if not is_nan(float(ax[hr])) and not _holding(d, hr):
			ax[hr] = NAN
			SFX.play(self, d.global_position + Vector3.UP * 1.9, "clank", -14.0, 1.7)
	# удары: ЛКМ/ПКМ — перехват свободной рукой (выше другого ледоруба)
	for h in 2:
		if int(data["sw"]) < 0 and _pressed(d, h) and is_nan(float(ax[h])):
			var other := 1 - h
			var oy := float(ax[other])
			if is_nan(oy):
				continue
			var tgt := oy + STEP_UP
			data["sw"] = h
			data["swt"] = 0.0
			data["tgt"] = tgt
			ax[h] = NAN
			d.stamina = maxf(float(d.stamina) - SWING_COST, 0.0)
			SFX.play(self, d.global_position + Vector3.UP * 1.8, "puff", -12.0, 1.6)
	if int(data["sw"]) >= 0:
		var h2 := int(data["sw"])
		var t0 := float(data["swt"])
		data["swt"] = t0 + delta
		if t0 < HIT_AT and float(data["swt"]) >= HIT_AT:
			var tgt2 := float(data["tgt"])
			var hp := _surf_pt(sf, a, minf(tgt2, top - 0.05))
			if tgt2 > top - 0.15:
				if _no_top(sf, a):
					# остриё — выше не за что
					tgt2 = top - 0.3
					if d == Network.local_player:
						mtn.say("Остриё — не встать. Оттолкнись (Пробел) к следующему выступу" if bool(sf["sharp"]) else "Тут не вылезти — A/D вбок, к тропе")
				else:
					_ice_fx(hp, false)
					_start_mantle(d, int(data["s"]), a)
					return
			if bool(sf["icy"]) and _rng.randf() < ICY_SLIP:
				_ice_fx(hp, true)
				if d == Network.local_player:
					mtn.say("Соскользнул по льду — ещё раз!")
			elif _holding(d, h2):
				ax[h2] = tgt2
				_ice_fx(hp, false)
				if d == Network.local_player:
					d.add_shake(0.07)
			else:
				_ice_fx(hp, false)                  # ударил, но кнопку отпустил — не удержал
		if float(data["swt"]) >= SWING_T:
			data["sw"] = -1
	# ни одного ледоруба в скале — падаю
	var planted: Array = []
	for v in ax:
		if not is_nan(float(v)):
			planted.append(float(v))
	if planted.is_empty():
		_drop(d, n, "Ни один ледоруб не держит — сорвался!")
		return
	# силы; один ледоруб на льду долго не держит
	var one := planted.size() == 1
	d.stamina = maxf(float(d.stamina) - (DRAIN1 if one else DRAIN2) * delta, 0.0)
	if one and bool(sf["icy"]) and int(data["sw"]) < 0:
		data["one_t"] = float(data["one_t"]) + delta
		if float(data["one_t"]) > ICY_HOLD:
			_ice_fx(_surf_pt(sf, a, planted[0]), true)
			_drop(d, n, "Ледоруб выскользнул изо льда!")
			return
	else:
		data["one_t"] = 0.0
	if float(d.stamina) <= 0.0:
		_drop(d, n, "Нет сил — руки разжались!")
		return
	# Пробел — оттолкнуться и прыгнуть туда, куда смотрю
	if d._just("jump"):
		var cam := d.get_viewport().get_camera_3d()
		var look := -cam.global_basis.z if cam else -n
		look.y = 0.0
		look = look.normalized()
		if look.dot(n) < -0.3:
			look = (look + n).normalized()
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.velocity = look * 5.6 + n * 1.2 + Vector3.UP * 6.4
		_leap[pid] = [0.9, look * 5.6 + n * 1.2]
		d.visual.rotation.y = atan2(-look.x, -look.z)
		SFX.play(self, d.global_position + Vector3.UP, "puff", -8.0, 0.9)
		return
	# где тело: висит под ледорубами, на 0.45 м от скалы; сначала — рывок (повис после удара)
	var hy := (float(planted.max()) - 2.05) if one else ((float(ax[0]) + float(ax[1])) * 0.5 - 1.92)
	var want := _surf_pt(sf, a, hy) + n * 0.45
	# шаг 81: вишу у настоящей скалы (выступы, зубья), а не у «цилиндра» — не залезаю в камень
	if String(sf["kind"]) == "cyl":
		var c8: Vector3 = sf["c"]
		var rad := _surf_rad(d, int(data["s"]), a, hy + 1.2)
		want = Vector3(c8.x, hy, c8.z) + n * (rad + 0.45)
	# шаг 80: на одном ледорубе тело уходит под него (вбок)
	if one:
		var lat8 := (-n).cross(Vector3.UP).normalized()
		want += lat8 * (-0.11 if not is_nan(float(ax[0])) else 0.11)
	var jolt := float(data["jolt"])
	if jolt > 0.0:
		data["jolt"] = maxf(jolt - delta, 0.0)
		var from: Vector3 = data["from"]
		var kk := 1.0 - jolt / 0.25
		want = from.lerp(want, smoothstep(0.0, 1.0, kk)) + Vector3.DOWN * 0.12 * sin(kk * PI)
	# шаг 80: тело тянется за ледорубами «с весом» (пружина с лёгким перелётом), а не скользит ровно
	var bv: Vector3 = _bv.get(pid, Vector3.ZERO)
	if jolt <= 0.0:
		bv += ((want - d.global_position) * 48.0 - bv * 10.0) * delta
		d.global_position += bv * delta
	else:
		d.global_position = want
		bv = Vector3.ZERO
	_bv[pid] = bv
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = atan2(n.x, n.z)
	data["from"] = d.global_position
	# поза: точка — скала на высоте тела, направление — в скалу; кодирую ледорубы и замах
	var ref := d.global_position - n * 0.45
	var qL := 99 if is_nan(float(ax[0])) else clampi(int((float(ax[0]) - ref.y) * 20.0), 0, 98)
	var qR := 99 if is_nan(float(ax[1])) else clampi(int((float(ax[1]) - ref.y) * 20.0), 0, 98)
	var swc := int(data["sw"]) + 1
	var ph := clampi(int(float(data["swt"]) / SWING_T * 99.0), 0, 99) if swc > 0 else 0
	var tq := clampi(int((float(data["tgt"]) - ref.y) * 20.0), 0, 98)
	d.snow.set_mpose(17, float(qL + qR * 100 + swc * 10000 + ph * 100000) + float(tq) / 100.0, ref, -n)
	if d == Network.local_player:
		_hint_t -= delta
		if _hint_t <= 0.0:
			_hint_t = 0.4
			mtn.say("%s  ЛКМ/ПКМ — выше, A/D — вбок, Пробел — прыжок" % ("Один ледоруб — бей вторым!" if one else "Висишь на ледорубах."))


func _drop(d: Node3D, n: Vector3, msg: String) -> void:
	d.snow.end_scripted()
	d.snow.set_mpose(0)
	d.velocity = n * 1.0 + Vector3.DOWN * 1.0
	if d == Network.local_player:
		mtn.say(msg)
		d.add_shake(0.15)
	SFX.play(self, d.global_position + Vector3.UP, "slide", -3.0, 0.8)


func _start_mantle(d: Node3D, si: int, a: float) -> void:
	var sf: Dictionary = surfs[si]
	_sw[int(d.peer_id)] = [-1.0, -1.0]
	if d.snow.busy():
		d.snow.end_scripted()
	var n := _surf_n(sf, a)
	var top := float(sf["top"])
	var dest: Vector3
	if String(sf["kind"]) == "cyl":
		var c: Vector3 = sf["c"]
		dest = Vector3(c.x, top + 0.05, c.z) + n * maxf(float(sf["r"]) - 0.55, 0.0)
	else:
		dest = _surf_pt(sf, a, top + 0.05) - n * 0.9
	var rad := _surf_rad(d, si, a, top - 0.7) if String(sf["kind"]) == "cyl" else 0.0
	d.snow.start_scripted(9, self, {"s": si, "a": a, "from": d.global_position, "dest": dest, "n": n, "rad": rad})
	if d == Network.local_player:
		d.add_shake(0.08)


## Шаг 80: вылезти наверх по-настоящему: подтянулся на ледорубах (клювы за краем) → локти на край →
## колено на край → встал. Поза 19
func _drive_mantle(d: Node3D, t: float, data: Dictionary) -> void:
	var sf: Dictionary = surfs[int(data["s"])]
	var n: Vector3 = data["n"]
	var from: Vector3 = data["from"]
	var dest: Vector3 = data["dest"]
	var top := float(sf["top"])
	var aa := float(data["a"])
	var k := clampf(t / MANTLE_T, 0.0, 1.0)
	var hang := _surf_pt(sf, aa, top - 1.85) + n * 0.42
	var chest := _surf_pt(sf, aa, top - 1.05) + n * 0.34
	var knee := _surf_pt(sf, aa, top - 0.55) + n * 0.1
	# шаг 81: у настоящего края скалы (если он торчит дальше «цилиндра»)
	var rad := float(data.get("rad", 0.0))
	if rad > 0.0:
		var push := n * maxf(rad - float(sf["r"]), 0.0)
		hang += push
		chest += push
		knee += push
	var pos := Vector3.ZERO
	if k < 0.18:
		pos = from.lerp(hang, smoothstep(0.0, 1.0, k / 0.18))
	elif k < 0.5:
		var a2 := smoothstep(0.0, 1.0, (k - 0.18) / 0.32)
		pos = hang.lerp(chest, a2) + n * sin(a2 * PI) * 0.06
	elif k < 0.78:
		var b2 := smoothstep(0.0, 1.0, (k - 0.5) / 0.28)
		pos = chest.lerp(knee, b2)
	else:
		var c2 := smoothstep(0.0, 1.0, (k - 0.78) / 0.22)
		pos = knee.lerp(dest, c2) + Vector3.UP * sin(c2 * PI) * 0.12
	d.global_position = pos
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = atan2(n.x, n.z)
	d.snow.set_mpose(19, k, _surf_pt(sf, aa, top) - n * 0.05, -n)
	if k >= 1.0:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.global_position = dest
		d.velocity = Vector3.ZERO


func visual(delta: float) -> void:
	# модели в руках у тех, у кого ледорубы (вдруг дрон появился позже)
	for pid in axes:
		if not _in_hand.has(pid):
			_hand_models(int(pid), true)
	_cab_visual(delta)


func hint(me: Node3D) -> String:
	var p := me.global_position
	var ch := _cab_hint(me)
	if ch != "":
		return ch
	if p.distance_to(_rack_a) < 2.2:
		return "У меня ледорубы: ЛКМ — левый, ПКМ — правый" if axes.has(int(me.peer_id)) else "E — взять ледорубы"
	if p.distance_to(_rack_b) < 2.2 and axes.has(int(me.peer_id)):
		return "E — оставить ледорубы на стойке"
	if in_field(p) and not axes.has(int(me.peer_id)) and me.snow.climb == 0:
		return "Без ледорубов здесь не пройти — стойка у начала пропасти"
	return ""


func server(delta: float) -> void:
	_cab_server(delta)
	pass


# ---------------------------------------------------------------------------
#  Шаг 82: грузовая люлька. Станция A — у начала пропасти, B — за ней. Посылку отпускаешь у люльки —
#  она в люльке; E у рычага — люлька едет по тросу на ту сторону (или зовёшь её к себе). Посылка ждёт там.
# ---------------------------------------------------------------------------

## Трос в координатах пропасти: станция A → кронштейн на ближней стене → вдоль задней стены → дальняя стена → B
func _cable_sl() -> Array:
	var L := M.SP_LEN
	var out: Array = [[-9.0, -3.0, 3.9], [1.4, -3.6, 6.2]]
	var s := 14.0
	while s < L - 13.0:
		out.append([s, -21.0, 12.0])
		s += 22.0
	out.append([L - 14.0, -21.0, 12.0])
	out.append([L - 1.4, -3.6, 6.2])
	out.append([L + 9.0, -3.0, 3.9])
	return out


func _cab_sl_d(s: float, lat: float) -> float:
	var best := INF
	for i in _cab_sl.size() - 1:
		var a := Vector2(float(_cab_sl[i][0]), float(_cab_sl[i][1]))
		var b := Vector2(float(_cab_sl[i + 1][0]), float(_cab_sl[i + 1][1]))
		var p := Vector2(s, lat)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, (a + ab * t).distance_to(p))
	return best


func _sl_world(s: float, lat: float, dy: float) -> Vector3:
	var u := _u0 + s / M.len_per_u(_u0)
	var p := M.point(u) + M.outward(u) * lat
	p.y = lerpf(_h0, _h1, clampf(s / M.SP_LEN, 0.0, 1.0)) + dy
	if s < 0.0 or s > M.SP_LEN:
		p.y = M.height(u) + dy
	return p


func _build_cable(b: Node3D) -> void:
	_cab_pts.clear()
	_cab_cum.clear()
	_cab_total = 0.0
	for e in _cab_sl:
		var p := _sl_world(float(e[0]), float(e[1]), float(e[2]))
		if not _cab_pts.is_empty():
			_cab_total += (_cab_pts[_cab_pts.size() - 1] as Vector3).distance_to(p)
		_cab_pts.append(p)
		_cab_cum.append(_cab_total)
	# трос (два: несущий и тяговый)
	for i in _cab_pts.size() - 1:
		var a: Vector3 = _cab_pts[i]
		var c: Vector3 = _cab_pts[i + 1]
		b.beam(a, c, 0.035, "cable", 6)
		b.beam(a + Vector3.DOWN * 0.32, c + Vector3.DOWN * 0.32, 0.018, "cable", 5)
	# опоры: кронштейны в скале со шкивами
	for i2 in range(1, _cab_pts.size() - 1):
		var p2: Vector3 = _cab_pts[i2]
		var e2: Array = _cab_sl[i2]
		var s2 := float(e2[0])
		var u2 := _u0 + s2 / M.len_per_u(_u0)
		var into := -M.outward(u2)                  # к задней стене (в гору)
		var reach := 5.5
		if i2 == 1 or i2 == _cab_pts.size() - 2:
			# у ближней/дальней стены — вбит в стену пропасти
			var ou := M.outward(u2)
			into = Vector3(-ou.z, 0.0, ou.x) * (-1.0 if i2 == 1 else 1.0)
			reach = 2.2
		var wall := p2 + into * reach
		b.beam(p2 + Vector3.UP * 0.25, wall + Vector3.UP * 0.5, 0.11, "steel", 6)
		b.beam(p2 + Vector3.DOWN * 0.4, wall + Vector3.DOWN * 2.6, 0.08, "steel", 6)
		b.beam(p2 + Vector3.UP * 0.25, p2 + Vector3.DOWN * 0.45, 0.06, "steel", 6)
		b.box(Vector3(0.9, 1.3, 0.25), wall + Vector3.DOWN * 1.0 + into * 0.1, Basis(Vector3.UP, atan2(into.x, into.z)), "concrete")
		var tdir := ((_cab_pts[i2 + 1] as Vector3) - (_cab_pts[i2 - 1] as Vector3))
		tdir.y = 0.0
		tdir = tdir.normalized()
		var sd2 := tdir.cross(Vector3.UP).normalized()
		b.cyl(0.32, 0.32, 0.1, p2 + Vector3.UP * 0.05, Basis(tdir, sd2, tdir.cross(sd2)), "paint_red", 12)
	# станции
	for st in 2:
		var p3: Vector3 = _cab_pts[0] if st == 0 else _cab_pts[_cab_pts.size() - 1]
		var nxt: Vector3 = _cab_pts[1] if st == 0 else _cab_pts[_cab_pts.size() - 2]
		var td := nxt - p3
		td.y = 0.0
		td = td.normalized()
		var side := td.cross(Vector3.UP).normalized()
		var ust := _u0 if st == 0 else _u1
		if side.dot(M.outward(ust)) < 0.0:
			side = -side                       # рычаг — к тропе (не в скалу)
		var g := p3 + Vector3.DOWN * 3.9
		for sx in [-0.9, 0.9]:
			b.beam(g + side * sx - td * 0.6, p3 + side * sx * 0.35 + Vector3.UP * 0.4, 0.1, "steel", 6)
			b.beam(g + side * sx + td * 0.6, p3 + side * sx * 0.35 + Vector3.UP * 0.4, 0.08, "steel", 6)
		b.beam(p3 + side * 0.4 + Vector3.UP * 0.4, p3 - side * 0.4 + Vector3.UP * 0.4, 0.09, "steel", 6)
		b.cyl(0.42, 0.42, 0.12, p3 + Vector3.UP * 0.1, Basis(td, side, td.cross(side)), "paint_red", 14)
		b.box(Vector3(1.8, 0.3, 1.6), g + Vector3.UP * 0.15, Basis(side, Vector3.UP, side.cross(Vector3.UP)), "concrete")
		# рычаг на тумбе
		var lv := g + side * 3.3 - td * 0.2         # подальше от люльки: E у рычага не хватает посылку
		b.box(Vector3(0.45, 1.0, 0.45), lv + Vector3.UP * 0.5, Basis(side, Vector3.UP, side.cross(Vector3.UP)), "yellow")
		var handle := Node3D.new()
		add_child(handle)
		handle.global_position = lv + Vector3.UP * 1.0
		handle.global_basis = Basis(side, Vector3.UP, side.cross(Vector3.UP))
		var hm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 0.7
		hm.mesh = cm
		hm.position = Vector3(0, 0.35, 0)
		hm.material_override = mtn.builder.mat("steel")
		handle.add_child(hm)
		var knob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		knob.mesh = sm
		knob.position = Vector3(0, 0.72, 0)
		knob.material_override = mtn.builder.mat("paint_red")
		handle.add_child(knob)
		handle.rotation.x = -0.5
		_cab_lever.append(handle)
		mtn.add_hold("SP_CAB_A" if st == 0 else "SP_CAB_B", lv + side * 0.6, 1.3)
		mtn.sign_at(lv + side * 0.9 + Vector3.UP * 0.4, ("ГРУЗОВАЯ ЛЮЛЬКА\nОтпусти посылку у люльки,\nE у рычага — едет на ту сторону" if st == 0 else "ГРУЗОВАЯ ЛЮЛЬКА\nЗабери посылку из люльки.\nE у рычага — позвать / отправить"), Color(1.0, 0.85, 0.5))
	# люлька: каретка с роликами, тяга, открытый ящик
	_cab_node = Node3D.new()
	add_child(_cab_node)
	var parts := [[Vector3(0.7, 0.28, 0.3), Vector3(0, -0.1, 0), "steel"], [Vector3(0.06, CAB_HANG, 0.06), Vector3(0, -CAB_HANG * 0.5 - 0.2, 0), "steel"],
		[Vector3(1.3, 0.08, 1.1), Vector3(0, -CAB_HANG - 1.15, 0), "planks"], [Vector3(1.3, 0.55, 0.06), Vector3(0, -CAB_HANG - 0.85, 0.52), "planks"],
		[Vector3(1.3, 0.55, 0.06), Vector3(0, -CAB_HANG - 0.85, -0.52), "planks"], [Vector3(0.06, 0.55, 1.1), Vector3(0.62, -CAB_HANG - 0.85, 0), "planks"],
		[Vector3(0.06, 0.55, 1.1), Vector3(-0.62, -CAB_HANG - 0.85, 0), "planks"], [Vector3(1.4, 0.06, 0.06), Vector3(0, -CAB_HANG - 0.2, 0), "steel"]]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[0]
		mi.mesh = bm
		mi.position = pt[1]
		mi.material_override = mtn.builder.mat(String(pt[2]))
		_cab_node.add_child(mi)
	for sx2 in [-0.25, 0.25]:
		var wh := MeshInstance3D.new()
		var wc := CylinderMesh.new()
		wc.top_radius = 0.11
		wc.bottom_radius = 0.11
		wc.height = 0.08
		wh.mesh = wc
		wh.rotation.x = PI * 0.5
		wh.position = Vector3(sx2, 0.05, 0)
		wh.material_override = mtn.builder.mat("dark")
		_cab_node.add_child(wh)
	# стропы от поперечины к углам ящика
	for cx in [-0.6, 0.6]:
		for cz in [-0.5, 0.5]:
			var sl := MeshInstance3D.new()
			var sb := BoxMesh.new()
			var a0 := Vector3(cx * 1.15, -CAB_HANG - 0.2, 0)
			var a1 := Vector3(cx, -CAB_HANG - 0.6, cz)
			sb.size = Vector3(0.025, 0.025, a0.distance_to(a1))
			sl.mesh = sb
			sl.material_override = mtn.builder.mat("cable")
			_cab_node.add_child(sl)
			sl.position = (a0 + a1) * 0.5
			sl.basis = Basis.looking_at(a1 - a0, Vector3.UP)
	_cab_place(0.0)


## Точка на тросе и направление
func _cab_at(g: float) -> Array:
	var gg := clampf(g, 0.0, _cab_total)
	for i in _cab_pts.size() - 1:
		var c0 := float(_cab_cum[i])
		var c1 := float(_cab_cum[i + 1])
		if gg <= c1 or i == _cab_pts.size() - 2:
			var t := clampf((gg - c0) / maxf(c1 - c0, 0.001), 0.0, 1.0)
			var a: Vector3 = _cab_pts[i]
			var b: Vector3 = _cab_pts[i + 1]
			return [a.lerp(b, t), (b - a).normalized()]
	return [_cab_pts[0], Vector3.FORWARD]


func _cab_place(g: float) -> void:
	if _cab_node == null:
		return
	var q := _cab_at(g)
	var dir: Vector3 = q[1]
	var hd := Vector3(dir.x, 0.0, dir.z)
	if hd.length() < 0.01:
		hd = Vector3.FORWARD
	hd = hd.normalized()
	_cab_node.global_position = (q[0] as Vector3) + Vector3.DOWN * 0.05
	_cab_node.global_basis = Basis(hd.cross(Vector3.UP).normalized(), Vector3.UP, -hd).orthonormalized()
	# по ходу люлька слегка раскачивается
	if cab_dir != 0:
		_cab_node.rotate_object_local(Vector3.FORWARD, sin(mtn.now() * 2.1) * 0.03)


## Где сама люлька (дно ящика) — для посылки
func cab_basket() -> Vector3:
	if _cab_node == null:
		return Vector3.ZERO
	return _cab_node.global_position + Vector3.DOWN * (CAB_HANG + 1.1)


func parcel_busy() -> bool:
	return cab_load


func _cab_at_station() -> int:
	if cab_dir != 0:
		return -1
	if cab_g < 0.05:
		return 0
	if cab_g > _cab_total - 0.05:
		return 1
	return -1


func _cab_server(delta: float) -> void:
	if _cab_pts.is_empty():
		return
	var parcel: Node = mtn.main_parcel
	var st := _cab_at_station()
	# загрузка: посылку отпустили у люльки (на станции)
	if not cab_load and st >= 0 and parcel != null and is_instance_valid(parcel) and not parcel.is_held and not parcel.is_delivered:
		var pp: Vector3 = (parcel as Node3D).global_position
		var bp := cab_basket()
		if Vector2(pp.x - bp.x, pp.z - bp.z).length() < 1.7 and absf(pp.y - bp.y) < 2.2:
			cab_load = true
			(parcel as RigidBody3D).freeze = true
			_cab_sync(true)
	if cab_load and parcel != null and is_instance_valid(parcel) and parcel.is_held:
		cab_load = false                     # забрали из люльки
		_cab_sync(true)
	# рычаги
	for k in 2:
		var on: bool = mtn.is_active("SP_CAB_A" if k == 0 else "SP_CAB_B")
		if on and not bool(_cab_prev[k]) and cab_dir == 0:
			if st == k:
				cab_dir = 1 if k == 0 else -1     # отсюда — на ту сторону
			elif st >= 0:
				cab_dir = -1 if k == 0 else 1     # позвать к себе
			_cab_sync(true)
			if mtn._online():
				_cab_lever_fx.rpc(k)
			else:
				_cab_lever_fx(k)
		_cab_prev[k] = on
	# едет (плавно трогается и тормозит у станций)
	if cab_dir != 0:
		var to_end := (_cab_total - cab_g) if cab_dir > 0 else cab_g
		var from_st := cab_g if cab_dir > 0 else (_cab_total - cab_g)
		var v := CAB_SPEED * clampf(minf(to_end, from_st) / 4.0 + 0.15, 0.15, 1.0)
		cab_g = clampf(cab_g + v * float(cab_dir) * delta, 0.0, _cab_total)
		if (cab_dir > 0 and cab_g >= _cab_total) or (cab_dir < 0 and cab_g <= 0.0):
			cab_dir = 0
			_cab_sync(true)
			if cab_load:
				mtn.set_parcel_last(cab_basket() + Vector3.UP * 0.6 + (Vector3.ZERO))
				if mtn._online():
					_cab_arrived.rpc(cab_g > 1.0)
				else:
					_cab_arrived(cab_g > 1.0)
	if cab_load and parcel != null and is_instance_valid(parcel):
		_cab_place(cab_g)
		var pr := parcel as RigidBody3D
		pr.global_position = cab_basket() + Vector3.UP * 0.4
		pr.linear_velocity = Vector3.ZERO
	_cab_sync_t -= delta
	if _cab_sync_t <= 0.0:
		_cab_sync_t = 0.1
		_cab_sync(false)


func _cab_sync(reliable: bool) -> void:
	if not mtn._online():
		return
	if reliable:
		_cab_state_r.rpc(cab_g, cab_dir, cab_load)
	else:
		_cab_state.rpc(cab_g, cab_dir, cab_load)


@rpc("authority", "call_remote", "unreliable_ordered")
func _cab_state(g: float, dir: int, load: bool) -> void:
	cab_g = g
	cab_dir = dir
	cab_load = load


@rpc("authority", "call_remote", "reliable")
func _cab_state_r(g: float, dir: int, load: bool) -> void:
	_cab_state(g, dir, load)


@rpc("authority", "call_local", "reliable")
func _cab_lever_fx(k: int) -> void:
	if k < _cab_lever.size():
		var h: Node3D = _cab_lever[k]
		var tw := create_tween()
		tw.tween_property(h, "rotation:x", 0.5, 0.15)
		tw.tween_interval(0.5)
		tw.tween_property(h, "rotation:x", -0.5, 0.4)
		SFX.play(self, h.global_position, "clank", -4.0, 0.9)
	if _cab_node:
		SFX.play(self, _cab_node.global_position, "clank", -8.0, 0.6)


@rpc("authority", "call_local", "reliable")
func _cab_arrived(at_b: bool) -> void:
	var me = Network.local_player
	if me and is_instance_valid(me) and me.global_position.distance_to(cab_basket()) < 90.0:
		get_tree().call_group("level", "show_banner", "Люлька с посылкой %s" % ("на той стороне" if at_b else "вернулась к началу"), "Посылка ждёт в люльке" if at_b else "")


func _cab_visual(delta: float) -> void:
	if _cab_node == null:
		return
	# у клиентов — плавно догоняю присланное положение
	if multiplayer.is_server():
		_cab_vis_g = cab_g
	else:
		_cab_vis_g = lerpf(_cab_vis_g, cab_g, clampf(delta * 6.0, 0.0, 1.0)) if absf(_cab_vis_g - cab_g) < 20.0 else cab_g
	_cab_place(_cab_vis_g)
	var parcel: Node = mtn.main_parcel
	if cab_load and parcel != null and is_instance_valid(parcel) and not multiplayer.is_server():
		(parcel as Node3D).global_position = cab_basket() + Vector3.UP * 0.4


func _cab_hint(me: Node3D) -> String:
	if _cab_pts.is_empty():
		return ""
	var p := me.global_position
	for k in 2:
		var hp: Array = mtn.holds.get("SP_CAB_A" if k == 0 else "SP_CAB_B", [])
		if hp.is_empty():
			continue
		var lv: Vector3 = hp[0]
		if Vector2(p.x - lv.x, p.z - lv.z).length() < 1.6 and absf(p.y - lv.y) < 2.0:
			if cab_dir != 0:
				return "Люлька в пути…"
			var st := _cab_at_station()
			if st == k:
				return "E — отправить люльку с посылкой на ту сторону" if cab_load else "E — отправить пустую люльку (посылку отпусти у люльки)"
			return "E — позвать люльку сюда"
	var bp := cab_basket()
	if me.get("held_parcel") != null and Vector2(p.x - bp.x, p.z - bp.z).length() < 3.0 and _cab_at_station() >= 0:
		return "Отпусти посылку у люльки — она ляжет в ящик"
	return ""


# ---------------------------------------------------------------------------
#  Шаг 85: ледорубы можно бросить под ноги (когда берёшь другой предмет) и поднять снова (E)
# ---------------------------------------------------------------------------

func _pile_near(p: Vector3, r := 1.8) -> int:
	var best := -1
	var bd := r
	for i in piles.size():
		var d := (piles[i] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Далеко ли до ледорубов, которые можно взять (стойка у начала или брошенные); INF — нет рядом
func axes_spot(d: Node3D) -> float:
	var p := d.global_position
	if axes.has(int(d.peer_id)):
		return INF
	var i := _pile_near(p)
	if i >= 0:
		return (piles[i] as Vector3).distance_to(p)
	if p.distance_to(_rack_a) < 1.6:
		return p.distance_to(_rack_a)
	return INF


func take_axes(d: Node3D) -> void:
	var pid := int(d.peer_id)
	var i := _pile_near(d.global_position)
	if i >= 0:
		_ask_pile(pid, true, piles[i])
	elif d.global_position.distance_to(_rack_a) < 1.6:
		_ask(pid, true)


func drop_axes(d: Node3D) -> void:
	var fw := -(d.visual as Node3D).global_basis.z
	fw.y = 0.0
	var pos := d.global_position + fw.normalized() * 0.55 + Vector3.UP * 0.04
	_ask_pile(int(d.peer_id), false, pos)


func _ask_pile(pid: int, take: bool, pos: Vector3) -> void:
	if multiplayer.is_server():
		_req_pile(pid, take, pos)
	else:
		_req_pile.rpc_id(1, pid, take, pos)


@rpc("any_peer", "call_remote", "reliable")
func _req_pile(pid: int, take: bool, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var np := piles.duplicate()
	if take:
		var i := _pile_near(pos, 0.5)
		if i < 0 or axes.has(pid):
			return
		np.remove_at(i)
	else:
		if not axes.has(pid):
			return
		np.append(pos)
	if mtn._online():
		_set_pile.rpc(pid, take, np)
	else:
		_set_pile(pid, take, np)


@rpc("authority", "call_local", "reliable")
func _set_pile(pid: int, take: bool, np: Array) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	if take:
		axes[pid] = true
	else:
		axes.erase(pid)
	if d:
		d.set("ice_axes", take)
		SFX.play(self, d.global_position + Vector3.UP * 0.5, "clank", -6.0, 1.3 if take else 0.8)
	piles = np
	_hand_models(pid, take)
	_build_piles()
	_place_rack_axes()


## Пара ледорубов на снегу (крест-накрест)
func _build_piles() -> void:
	for n in _pile_nodes:
		if is_instance_valid(n):
			(n as Node3D).queue_free()
	_pile_nodes.clear()
	for i in piles.size():
		var p: Vector3 = piles[i]
		for k in 2:
			var h := Node3D.new()
			add_child(h)
			_axe_into(h)
			h.global_transform = Transform3D(Basis(Vector3.UP, i * 1.3 + k * 0.6) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3.UP * (0.05 + k * 0.05))
			_pile_nodes.append(h)
