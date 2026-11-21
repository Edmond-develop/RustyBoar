extends Node3D
## Шаг 119: стена к вершине (548 → 700 м) в конце ночной дороги — на ледорубах (ЛКМ/ПКМ по очереди).
##   6 участков по ~25 м, между ними — полки: там отдыхают (силы восстанавливаются). На стене силы только тают:
##   висишь — понемногу, каждый удар — ещё. Кончились — руки разжались, падаешь на полку ниже.
##   A/D — вбок, Пробел — отпустить. Друг лезет над тобой — E: схватить его за ногу и ехать на нём
##   (у него силы тают вдвое; он стряхнёт — E). Посылку поднимают лебёдкой (кулуар слева).
## (Ниже — описание прежней стены, шаг 73; связка/страховка/подтягивание в шаге 119 убраны.)
## Шаг 73: стена к вершине (520 → 650 м) — только скалолазанием. 5 участков («верёвок») с полками.
##
## Как лезть: подошёл к стене, держи E — вцепился. W — вверх, S — вниз, A/D — вбок, Пробел — отпустить.
##   Двигаешься — тратишь силы; держишь E — вбил ледоруб, отдыхаешь (силы растут) и порыв не сорвёт.
##   Порыв (сначала гул) — если в этот миг лезешь, срываешься. Силы кончились — срываешься.
## Связка: у мотка верёвки на Плече вдвоём держите E — вы в одной верёвке (до 30 м друг от друга).
##   Сорвался — друг удержит, если сам вцепился: на полке держит E у страховочного крюка
##   или на стене держит E. Не держит — повиснешь хуже (съедешь ниже) или оба сорвётесь.
##   Без связки срыв — падение на полку ниже (поломка).
## Гладкий лёд у верха 2-го и 5-го участков: не зацепиться. Сбоку — трещина (лезть можно, но силы тают втрое).
##   Кто уже наверху — ложится у края (держи E у метки) и подтягивает друга за руку.
## Посылку на стену не взять: её кладут в корзину лебёдки в кулуаре слева. Наверху один крутит ворот (держи E),
##   внизу второй держит оттяжку (E у столбика) — иначе корзина цепляется за карнизы и встаёт.
## Боты: связываются, страхуют, держат оттяжку/крутят ворот, лезут за хозяином, подтягивают.

const M := preload("res://scenes/world/mountain_layout.gd")
const SFX := preload("res://scripts/sfx.gd")
const GATE := preload("res://scenes/world/mountain_gate.gd")
const CLIMB_UP := 1.15
const CLIMB_DOWN := 1.4
const CLIMB_SIDE := 0.9
const DRAIN := 4.5                 ## силы/с, когда лезу (участок ~25 с — одна передышка)
const DRAIN_CRACK := 13.0          ## в трещине
const DRAIN_HANG := 1.5
const DRAIN_GUST := 6.0
const REST := 5.0                  ## держу E — силы растут
const ROPE_LEN := 30.0
const TIE_T := 1.0
const PULL_T := 1.1
const MANTLE_T := 0.6
const WALL_OFF := 0.45             ## от стены до дрона
const HOIST_SPEED := 3.2
const BASKET_DOWN := 6.0
const TAG_PULL := 3.0
const PULL_X := [-1.5, 1.5]        ## где подтягивают на участках с гладким льдом (по BANDS)
## шаг 119: ледорубы
const AX_STEP := 0.55              ## перехват выше
const AX_SWING_T := 0.32
const AX_HIT_AT := 0.18
const AX_HANG := 0.7               ## силы/с, вишу на двух (шаг 126: на участок хватает с небольшим запасом)
const AX_COST := 0.55              ## за удар
const AX_SIDE := 0.9               ## вбок, м/с
const AX_SIDE_COST := 3.0          ## силы/с, пока шагаю вбок
const AX_MANTLE := 1.2
const LEG_DRAIN := 2.0             ## на мне висит друг — силы тают вдвое

var mtn: Node
var is_open := false
var ties := {}                     ## дрон → дрон в связке (у всех)
var _hoist_last := Vector3.INF
var _hoist_tag := false
var basket_y := M.FOOT_Y + 0.35      ## высота корзины (хост ведёт, всем рассылает)
var basket_load := false           ## в корзине посылка
var basket_stuck := false
var basket_tag := false            ## оттяжку держат
var _tie_t := 0.0
var _sync_t := 0.0
var _rope_segs := {}               ## пара → [меши]
var _rest := {}                    ## бот → отдыхает (до 70% сил)
var _basket: Node3D
var _hoist_im: ImmediateMesh
var _ice_mat: StandardMaterial3D
var _snow_mat: StandardMaterial3D
var tie_pos := Vector3.ZERO
var tag_pos := Vector3.ZERO
var winch_pos := Vector3.ZERO
var drum_pos := Vector3.ZERO
var basket_low := Vector3.ZERO
var _pull_pts: Array = []          ## [участок, точка у края полки, id]
var _bel_pts: Array = []           ## [уровень (−1 — Плечо, k — полка k), точка, id]


# ---------------------------------------------------------------------------
#  Постройка
# ---------------------------------------------------------------------------

func build() -> void:
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color(0.42, 0.6, 0.74, 0.62)
	_ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ice_mat.roughness = 0.12
	_ice_mat.metallic_specular = 1.0
	_ice_mat.rim_enabled = true
	_ice_mat.rim = 0.25
	var inz := FastNoiseLite.new()
	inz.frequency = 0.035
	inz.fractal_octaves = 4
	var itex := NoiseTexture2D.new()
	itex.noise = inz
	itex.width = 256
	itex.height = 256
	itex.seamless = true
	var ialb := NoiseTexture2D.new()
	ialb.noise = inz
	ialb.width = 256
	ialb.height = 256
	ialb.seamless = true
	var igr := Gradient.new()
	igr.set_color(0, Color(0.7, 0.82, 0.9))
	igr.set_color(1, Color(1.0, 1.0, 1.0))
	ialb.color_ramp = igr
	_ice_mat.albedo_texture = ialb
	itex.as_normal_map = true
	itex.bump_strength = 6.0
	_ice_mat.normal_enabled = true
	_ice_mat.normal_texture = itex
	_ice_mat.normal_scale = 0.8
	_ice_mat.uv1_triplanar = true
	_ice_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.albedo_color = Color(0.93, 0.95, 1.0)
	_snow_mat.roughness = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 73650
	for k in M.PITCHES.size():
		_build_pitch(k, rng)
	# связка, страховочные крюки
	tie_pos = Vector3(M.BX - 2.6, M.FOOT_Y, M.FOOT_ZN + 2.6)
	if false:
		mtn.add_hold("TIE", tie_pos, 1.7)
	var coil := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.25
	tm.outer_radius = 0.45
	tm.material = mtn.rope_mat()
	coil.mesh = tm
	coil.position = tie_pos + Vector3.UP * 0.12
	for lv in range(-1, -1):
		var y := M.FOOT_Y if lv < 0 else M.pitch_top(lv)
		var z := M.FOOT_ZN + 1.2 if lv < 0 else M.face_z(lv + 1) + 1.0
		var p := Vector3(M.BX + 5.4, y, z)
		var id := "BEL%d" % (lv + 1)
		mtn.add_hold(id, p, 1.3)
		mtn.post(p, Color(0.95, 0.75, 0.15), self)
		_bel_pts.append([lv, p, id])
	# подтянуть за руку: метки у края полки над гладким льдом
	for bi in M.BANDS.size():
		var band: Array = M.BANDS[bi]
		var k: int = band[0]
		var xp: float = PULL_X[bi]
		var top := M.pitch_top(k)
		var zp := M.face_z(k) - 0.7
		var p2 := Vector3(M.BX + xp, top, zp)
		var id2 := "PULL%d" % k
		mtn.add_hold(id2, p2, 1.0)
		_pull_pts.append([k, p2, id2, xp])
		var mark := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.45
		mm.bottom_radius = 0.45
		mm.height = 0.04
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = Color(1.0, 0.75, 0.15)
		mmat.emission_enabled = true
		mmat.emission = Color(1.0, 0.6, 0.1)
		mmat.emission_energy_multiplier = 0.6
		mm.material = mmat
		mark.mesh = mm
		mark.position = p2 + Vector3.UP * 0.05
		add_child(mark)
	_build_winch()
	_build_foot()
	mtn.sign_at(Vector3(M.BX + 3.0, M.FOOT_Y, M.FOOT_ZN + 4.0), "СТЕНА — 152 м до вершины\nЛКМ / ПКМ по очереди — бить ледорубами и лезть.\nA/D — вбок, Пробел — отпустить.\nЛЁД держит плохо — ледоруб едет, перебивай быстро.\nЛедоруб поехал — жми его кнопку!\nВ порыв ветра — не бей, держись на двух.\nСосульки над головой: ударишь — рухнут вниз.\nR — сбить лёд на тех, кто ниже :)\nДруг над тобой — E: схватить за ногу.", Color(0.95, 0.8, 0.3))
	mtn.sign_at(Vector3(M.SLOT_X1 + 1.0, M.FOOT_Y, M.FOOT_ZN + 3.0), "ЛЕБЁДКА\nПосылку — в корзину (в кулуаре).\nНаверху крутят ворот (E),\nвнизу держат оттяжку (E у столбика)", Color(0.6, 0.9, 1.0))
	GATE.make(self, Vector3(M.BX, M.FOOT_Y, M.FOOT_ZN + 4.0))
	GATE.make(self, Vector3(M.BX, M.PEAK, M.BZ + 6.0))
	_hoist_im = ImmediateMesh.new()
	var him := MeshInstance3D.new()
	him.mesh = _hoist_im
	him.material_override = mtn.rope_mat()
	him.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(him)


## Шаг 123: рельеф плиты — одна формула и для меша, и для тела на стене (чтобы не входить в скалу)
var _bn: Array = []
func _bump(k: int, xx: float, yy: float) -> float:
	var nz: FastNoiseLite = _bn[k]
	var y0 := M.pitch_base(k)
	var y1 := M.pitch_top(k)
	var v := clampf((yy - y0) / (y1 - y0), 0.0, 1.0)
	var ax := absf(xx)
	# шаг 127: крупная форма — как настоящая скала: контрфорс выпуклый посередине, плавные «пузыри» и впадины
	# метрового масштаба, вертикальные рёбра; у основания — ровнее (чтобы на полке ниже было где стоять)
	var big := 0.5 * (1.0 - pow(minf(ax / (M.FACE_SIDE + 1.0), 1.0), 2.0))
	big += nz.get_noise_2d(xx * 0.2 + 30.0, yy * 0.11) * 0.75
	big += 0.3 * sin(PI * v)
	big *= smoothstep(0.0, 0.3, v)
	var rib := absf(nz.get_noise_2d(xx * 0.9 + 80.0, yy * 0.07)) * 0.35
	var b := big + rib + nz.get_noise_2d(xx * 1.4, yy * 1.4) * 0.22
	# края — круто заворачивают назад, в склон; сама кромка гуляет по высоте (силуэт не прямоугольный)
	var edge := M.FACE_SIDE + 0.9 * nz.get_noise_2d(yy * 0.09, 300.0 + float(k) * 7.0) + 0.6 * nz.get_noise_2d(yy * 0.25, 410.0)
	b -= smoothstep(edge - 1.8, edge, ax) * 1.6 + smoothstep(edge, edge + 1.2, ax) * 2.5
	# у верхнего края скала скруглённо заваливается назад — без «бортика»
	b -= smoothstep(y1 - 1.2, y1 + 0.05, yy) * (0.4 + 0.5 * maxf(big, 0.0))
	return b


## Поверхность стены перед телом: самая выступающая точка от ног до ледорубов (±0.35 м вбок)
func _surf(k: int, xx: float, y: float) -> float:
	var m := -INF
	for dx in [-0.35, 0.0, 0.35]:
		for dy in [0.1, 0.7, 1.3, 1.9, 2.4]:
			m = maxf(m, _bump(k, xx + dx, y + dy))
	return M.face_z(k) + m


# ===========================================================================
#  Шаг 123: препятствия стены
#   * гладкий лёд (SLABS): ледоруб не держится — «дзынь», искры; обходить A/D;
#   * сосульки над участками: ударил ледорубом рядом — обрушил на тех, кто ниже (прикол!);
#     сами тоже срываются — сначала трещат и качаются (1.2 с), можно увернуться;
#   * камнепад: сверху сыплется крошка (предупреждение), потом летит камень;
#   * R на стене — отбить кусок льда вниз (на друзей);
#   * порывы ветра: «ветер усиливается…» → 3 с порыв: кто держится на двух ледорубах — терпит,
#     кто в замахе / на одном — силы тают быстро, ледорубы чаще соскальзывают;
#   * ледоруб соскальзывает: его кнопка мигает — успей нажать (0.85 с), иначе вылетит.
# ===========================================================================

## [участок, x от, x до, высота от, высота до (от основания участка)]
const SLABS := [[0, 0.9, 4.6, 5.0, 14.0], [0, -4.6, -2.6, 15.0, 22.0], [1, -4.6, -0.6, 4.0, 12.0], [1, 1.6, 4.6, 14.0, 21.0],
	[2, -1.4, 2.4, 8.0, 16.0], [3, 0.4, 4.6, 3.0, 11.0], [3, -4.6, -1.2, 13.0, 21.0], [4, -3.2, 0.6, 5.0, 14.0],
	[5, -4.6, -1.8, 3.0, 10.0], [5, 1.0, 4.6, 11.0, 19.0]]
const SLIP_T := 0.85               ## сколько едет соскальзывающий ледоруб — успей нажать
const SLIP_EVERY := Vector2(7.0, 14.0)
const HIT_STAM := 18.0             ## прилетело сверху — силы долой (шаг 126: не приговор, но больно)
const GUST_CYCLE := 32.0
const GUST_WARN := 5.0             ## шаг 125: предвестник — лёгкий ветер (успеть вбить оба ледоруба)
const GUST_LEN := 3.5              ## сам порыв (первые 0.8 с — нарастает)
const KICK_CD := 5.0

var _ice: Array = []               ## сосульки: {"k", "x", "y", "z", "n", "st" (0 висит, 1 трещит, 2 нет), "t"}
var _falls: Array = []             ## падают: {"n", "p", "v", "k", "by", "hit" {}, "kind"}
var _rock_t := 8.0
var _kick_cd := 0.0
var _gust_prev := 0
var _slab_mat: ShaderMaterial
var _rock_m: StandardMaterial3D


func _in_slab(k: int, xx: float, yy: float) -> bool:
	for sl in SLABS:
		if int(sl[0]) == k and _slab_r(sl, xx, yy) < 1.0:
			return true
	return false


## Шаг 128: попытка зацепиться при падении. Шанс высокий сразу после срыва, падает со временем,
## на льду — меньше, вторая попытка — хуже. true — зацепился (снова на стене)
func _try_arrest(d: Node3D) -> bool:
	var A: Dictionary = d.get_meta("arrest")
	var el := Time.get_ticks_msec() / 1000.0 - float(A["t"])
	var p := d.global_position
	var k := int(A["k"])
	if el > 1.6 or p.y < M.pitch_base(k) + 1.0 or int(d.snow.climb) != 0:
		d.remove_meta("arrest")
		return false
	var bot := bool(d.get("is_bot"))
	var press: bool = d._just("use_item") or d._just("use_alt") or (bot and el > 0.35 and int(A["tries"]) == 0)
	if not press or int(A["tries"]) >= 2:
		return false
	A["tries"] = int(A["tries"]) + 1
	var x := clampf(p.x - M.BX, -M.FACE_W, M.FACE_W)
	var y := p.y
	var gap := p.z - _surf(k, x, y)
	var ch := 0.8 - el * 0.3 - (0.35 if _in_slab(k, x, y + 1.8) else 0.0) - (0.25 if int(A["tries"]) == 2 else 0.0)
	var hp := Vector3(M.BX + x, y + 1.9, M.face_z(k) + _bump(k, x, y + 1.9))
	var me := d == Network.local_player
	if gap < 2.8 and randf() < ch:
		d.remove_meta("arrest")
		d.velocity = Vector3.ZERO
		d.stamina = maxf(float(d.stamina), 15.0)          # адреналин
		d.snow.start_scripted(3, self, {"k": k, "x": x, "y": y, "slip_cd": randf_range(SLIP_EVERY.x, SLIP_EVERY.y), "ax": [y + 1.95, y + 1.7],
			"sw": -1, "swt": 0.0, "tgt": 0.0, "last": 1, "bot_t": 0.0})
		d.visual.rotation.y = 0.0
		_axes_all(int(d.peer_id), true)
		_sparks(hp)
		_chips(hp)
		SFX.play(self, hp, "clank", 0.0, 1.1, 40.0)
		if me:
			d.add_shake(0.45)
			mtn.say("ЗАЦЕПИЛСЯ! Повезло… Держись!")
		return true
	_sparks(hp)
	SFX.play(self, hp, "ding", -4.0, 1.9, 30.0)
	if me:
		d.add_shake(0.15)
		mtn.say("Ледоруб скользнул по скале! " + ("Ещё раз!" if int(A["tries"]) < 2 else "Не зацепился…"))
	return false


## Шаг 127: форма натёка — неровный овал, вытянутый вниз, снизу — языки-подтёки. < 1 — внутри
func _slab_geom(sl: Array) -> Array:
	var yb := M.pitch_base(int(sl[0]))
	var cx := (float(sl[1]) + float(sl[2])) * 0.5
	var cy := yb + (float(sl[3]) + float(sl[4])) * 0.5 + (float(sl[4]) - float(sl[3])) * 0.08
	var rx := (float(sl[2]) - float(sl[1])) * 0.5
	var ry := (float(sl[4]) - float(sl[3])) * 0.42
	var sd := float(int(sl[0]) * 7 + int(float(sl[1]) * 3.0)) * 1.7
	return [cx, cy, rx, ry, sd]


func _slab_lim(sd: float, th: float) -> float:
	var lim := 1.0 + 0.16 * sin(3.0 * th + sd) + 0.09 * sin(7.0 * th + sd * 2.0) + 0.05 * sin(13.0 * th + sd * 3.0)
	if sin(th) < 0.0:
		lim += 0.45 * pow(maxf(sin(5.0 * th + sd), 0.0), 3.0) * -sin(th)      # подтёки вниз
	return lim


func _slab_r(sl: Array, xx: float, yy: float) -> float:
	var g := _slab_geom(sl)
	var dx := (xx - float(g[0])) / float(g[2])
	var dy := (yy - float(g[1])) / float(g[3])
	if dy < 0.0:
		dy /= 1.35
	var th := atan2(dy, dx)
	return sqrt(dx * dx + dy * dy) / _slab_lim(float(g[4]), th)


## Лёд на плите: неровный лист поверх скалы, по низу — сосульки-натёки (не падают)
func _build_slab(k: int, sl: Array, rng: RandomNumberGenerator) -> void:
	if _slab_mat == null:
		_slab_mat = ShaderMaterial.new()
		_slab_mat.shader = load("res://shaders/peak_ice_wall.gdshader")
		var t := "res://assets/peak/tex/"
		if ResourceLoader.exists(t + "ice_color.jpg"):
			_slab_mat.set_shader_parameter("tex_color", load(t + "ice_color.jpg"))
			_slab_mat.set_shader_parameter("tex_normal", load(t + "ice_normal.png"))
			_slab_mat.set_shader_parameter("tex_rough", load(t + "ice_rough.jpg"))
		_slab_mat.set_shader_parameter("uv_scale", 0.35)
	# шаг 127: натёк — кольца от середины к рваному краю; толщина к краю сходит на нет, край прозрачный
	var g := _slab_geom(sl)
	var cx: float = g[0]
	var cy: float = g[1]
	var rx: float = g[2]
	var ry: float = g[3]
	var sd: float = g[4]
	var z := M.face_z(k)
	var en := FastNoiseLite.new()
	en.seed = 4100 + k * 13 + int(cx * 10.0)
	en.frequency = 0.6
	var RN := 9
	var AN := 56
	var rings: Array = []
	for ri in RN + 1:
		var t := float(ri) / RN
		var row: Array = []
		for ai in AN:
			var th := TAU * ai / AN
			var r := t * _slab_lim(sd, th) * 0.985
			var dx := cos(th) * r
			var dy := sin(th) * r
			if dy < 0.0:
				dy *= 1.35
			var xx := cx + dx * rx
			var yy := cy + dy * ry
			var thick := (0.13 + 0.05 * en.get_noise_2d(xx * 1.5, yy * 0.6)) * (1.0 - t * t)
			row.append([Vector3(M.BX + xx, yy, z + _bump(k, xx, yy) + 0.025 + thick), 1.0 - smoothstep(0.55, 1.0, t)])
		rings.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in RN:
		for ai in AN:
			var a: Array = rings[ri][ai]
			var b: Array = rings[ri][(ai + 1) % AN]
			var c: Array = rings[ri + 1][ai]
			var d: Array = rings[ri + 1][(ai + 1) % AN]
			for q in [a, b, c, b, d, c]:
				var p: Vector3 = q[0]
				st.set_color(Color(1, 1, 1, float(q[1])))
				st.set_uv(Vector2(p.x, p.y) * 0.35)
				st.add_vertex(p)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _slab_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# сосульки-натёки по нижнему краю (на кончиках подтёков — длиннее)
	for ai2 in AN:
		var th2 := TAU * ai2 / AN
		if sin(th2) > -0.45 or rng.randf() < 0.45:
			continue
		var r2 := _slab_lim(sd, th2)
		var px := cx + cos(th2) * r2 * rx
		var py := cy + sin(th2) * r2 * 1.35 * ry
		var ln := rng.randf_range(0.2, 0.6) + (r2 - 1.0) * 1.2
		_cone(self, Vector3(M.BX + px, py - ln * 0.45, z + _bump(k, px, py) + 0.07), rng.randf_range(0.04, 0.08), ln, _ice_mat)


func _cone(parent: Node3D, pos: Vector3, r: float, ln: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = 0.0
	cm.height = ln
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	return mi


## Сосульки по кромке полки над участком k (4 гроздья)
func _build_icicles(k: int, rng: RandomNumberGenerator) -> void:
	var y1 := M.pitch_top(k)
	var xs: Array = []
	var tries := 0
	while xs.size() < 4 and tries < 40:
		tries += 1
		var x := rng.randf_range(-M.FACE_W + 0.4, M.FACE_W - 0.4)
		var ok := true
		for o in xs:
			if absf(float(o) - x) < 1.8:
				ok = false
		if ok:
			xs.append(x)
	for x in xs:
		var zt := M.face_z(k) + _bump(k, x, y1 - 0.25) + 0.1
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(M.BX + x, y1 - 0.1, zt)
		for c in rng.randi_range(5, 8):
			var ln := rng.randf_range(0.35, 1.3)
			var cn := _cone(n, Vector3.ZERO, rng.randf_range(0.05, 0.11), ln, _ice_mat)
			cn.position = Vector3(rng.randf_range(-0.35, 0.35), -ln * 0.5, rng.randf_range(-0.06, 0.06))
		_ice.append({"k": k, "x": float(x), "y": y1 - 0.1, "z": zt, "n": n, "st": 0, "t": 0.0})


## Сосулька i: 1 — трещит (качается), 2 — рухнула; по сети — всем
func _ice_all(i: int, st: int, by: int) -> void:
	if mtn._online():
		_ice_set.rpc(i, st, by)
	else:
		_ice_set(i, st, by)


@rpc("any_peer", "call_local", "reliable")
func _ice_set(i: int, st: int, by: int) -> void:
	if i < 0 or i >= _ice.size():
		return
	var I: Dictionary = _ice[i]
	if st == int(I["st"]):
		return
	I["st"] = st
	I["t"] = 0.0
	var n: Node3D = I["n"]
	if st == 1:
		SFX.play(self, n.global_position, "creak", -2.0, 1.7, 40.0)
	elif st == 2:
		n.visible = false
		SFX.play(self, n.global_position, "snowslide", 0.0, 1.8, 50.0)
		var shared := {}                 # шаг 126: гроздь бьёт одного дрона один раз (а не каждой сосулькой)
		for c in 4:
			_spawn_fall(int(I["k"]), n.global_position + Vector3(randf_range(-0.3, 0.3), -0.3 - c * 0.15, 0.05), "ice", by, Vector3(randf_range(-0.4, 0.4), -1.0 - c * 0.4, 0.3), shared)
	elif st == 0:
		n.visible = true
		n.scale = Vector3.ONE * 0.05
		create_tween().tween_property(n, "scale", Vector3.ONE, 3.0)


## Камнепад: сверху сыплется крошка (k, x), через delay — камень
func _rock_all(k: int, x: float, delay: float) -> void:
	if mtn._online():
		_rock.rpc(k, x, delay)
	else:
		_rock(k, x, delay)


@rpc("authority", "call_local", "reliable")
func _rock(k: int, x: float, delay: float) -> void:
	var top := Vector3(M.BX + x, M.pitch_top(k) + 0.3, M.face_z(k) + _bump(k, x, M.pitch_top(k) - 1.0) + 0.5)
	var sp := FX.particles(Color(0.45, 0.42, 0.4), 30, 1.2, 0.035, 0.5, 2.0, Vector3(0, -9, 0), 25.0, false, true)
	add_child(sp)
	sp.global_position = top
	sp.emitting = true
	get_tree().create_timer(delay + 0.4).timeout.connect(sp.queue_free)
	SFX.play(self, top, "crunch", 0.0, 0.7, 60.0)
	var me = Network.local_player
	if me and int(me.snow.climb) == 3 and int(me.snow._cl_data.get("k", -1)) == k:
		mtn.say("СВЕРХУ КАМЕНЬ! В сторону — A/D!")
		me.add_shake(0.1)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_spawn_fall(k, top, "rock", -1, Vector3(randf_range(-0.3, 0.3), -2.0, 0.4)))


## R на стене — отбил кусок льда вниз (прикол над теми, кто ниже)
func _kick_all(k: int, p: Vector3, by: int) -> void:
	if mtn._online():
		_kick.rpc(k, p, by)
	else:
		_kick(k, p, by)


@rpc("any_peer", "call_local", "reliable")
func _kick(k: int, p: Vector3, by: int) -> void:
	_chips(p)
	_spawn_fall(k, p + Vector3(0, -0.4, 0.1), "ice", by, Vector3(randf_range(-0.2, 0.2), -1.5, 0.3))


func _spawn_fall(k: int, p: Vector3, kind: String, by: int, v: Vector3, hitd: Dictionary = {}) -> void:
	var n: MeshInstance3D
	if kind == "rock":
		if _rock_m == null:
			_rock_m = StandardMaterial3D.new()
			_rock_m.albedo_color = Color(0.32, 0.3, 0.29)
			_rock_m.roughness = 0.95
		n = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.5
		sm.radial_segments = 7
		sm.rings = 4
		n.mesh = sm
		n.material_override = _rock_m
		add_child(n)
		n.global_position = p
	else:
		n = _cone(self, p, randf_range(0.07, 0.12), randf_range(0.5, 1.0), _ice_mat)
	n.rotation = Vector3(randf() * 0.4, randf() * TAU, randf() * 0.4)
	_falls.append({"n": n, "p": p, "v": v, "k": k, "by": by, "hit": hitd, "kind": kind, "spin": Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))})


## Падение: летит вдоль стены, бьёт тех, кто ниже на этом участке (кто бросил — не задевает), разбивается о полку
func _update_falls(delta: float) -> void:
	for i in range(_falls.size() - 1, -1, -1):
		var F: Dictionary = _falls[i]
		var v: Vector3 = F["v"]
		v.y -= 14.0 * delta
		F["v"] = v
		var p: Vector3 = F["p"] + v * delta
		F["p"] = p
		var n: Node3D = F["n"]
		n.global_position = p
		n.rotation += (F["spin"] as Vector3) * delta
		var k := int(F["k"])
		var gy := M.pitch_base(k) + 0.1
		for d in get_tree().get_nodes_in_group("player"):
			if not d.is_local or bool(d.get("is_dead")) or (F["hit"] as Dictionary).has(int(d.peer_id)) or int(d.peer_id) == int(F["by"]):
				continue
			var c: Vector3 = d.global_position + Vector3.UP * 1.3
			if absf(p.x - c.x) < 0.75 and absf(p.y - c.y) < 1.2 and absf(p.z - c.z) < 1.4:
				(F["hit"] as Dictionary)[int(d.peer_id)] = true
				_got_hit(d, F["kind"] == "rock", int(F["by"]))
		if p.y < gy:
			var sp := FX.particles(Color(0.85, 0.93, 1.0) if F["kind"] != "rock" else Color(0.45, 0.42, 0.4), 16, 0.5, 0.04, 1.5, 4.0, Vector3(0, -9, 0), 120.0, true, true)
			add_child(sp)
			sp.global_position = p
			sp.emitting = true
			get_tree().create_timer(1.0).timeout.connect(sp.queue_free)
			SFX.play(self, p, "ding" if F["kind"] != "rock" else "thunk", -6.0, randf_range(1.2, 1.6), 40.0)
			n.queue_free()
			_falls.remove_at(i)


## Прилетело сверху
func _got_hit(d: Node3D, rock: bool, by: int) -> void:
	var dmg := HIT_STAM * (1.3 if rock else 1.0)
	d.stamina = maxf(float(d.stamina) - dmg, 0.0)
	var me: bool = d == Network.local_player
	if me:
		d.add_shake(0.5 if rock else 0.35)
	if int(d.snow.climb) == 3:
		var data: Dictionary = d.snow._cl_data
		_start_slip(d, data, randi() % 2)
		if me:
			var who: Node3D = mtn.drone_by_id(by) if by >= 0 else null
			mtn.say(("Камнем по шлему! " if rock else "Сосулькой сверху! ") + ("(это %s)" % who.get("display_name") if who and who.get("display_name") else "") + " Силы −%d, ледоруб поехал!" % int(dmg))
	else:
		d.wind_shove(Vector3(0, 0, 1), 1.2)
		if me:
			mtn.say("Сверху прилетело! Силы −%d" % int(dmg))


## Ветер: детерминированно по времени (у всех одинаково, без сети): 0 — тихо, 1 — усиливается, 2 — порыв
func gust_state() -> Vector2:
	var t: float = mtn.now()
	var c := floori(t / GUST_CYCLE)
	var h := fposmod(sin(float(c) * 12.9898) * 43758.5453, 1.0)
	var off := 6.0 + h * 14.0
	var lt := t - c * GUST_CYCLE
	var dir := 1.0 if fposmod(h * 7.0, 1.0) > 0.5 else -1.0
	_gust_in = lt - off
	if lt > off and lt < off + GUST_WARN:
		return Vector2(1, dir)
	_gust_in = lt - off - GUST_WARN
	if lt >= off + GUST_WARN and lt < off + GUST_WARN + GUST_LEN:
		return Vector2(2, dir)
	return Vector2(0, dir)


var _gust_in := 0.0                ## сколько секунд идёт текущая фаза ветра (заполняет gust_state)


## Ледоруб h начал соскальзывать
func _start_slip(d: Node3D, data: Dictionary, h: int) -> void:
	var ax: Array = data["ax"]
	# шаг 125: соскальзывает только когда держусь на двух (на одном — уже и так висишь на волоске)
	if int(data.get("slip", -1)) >= 0 or int(data["sw"]) >= 0 or is_nan(float(ax[0])) or is_nan(float(ax[1])):
		return
	data["slip"] = h
	data["slip_t"] = 0.0
	data["slip_cd"] = randf_range(SLIP_EVERY.x, SLIP_EVERY.y)
	SFX.play(self, d.global_position + Vector3.UP * 2.0, "grind", -4.0, 1.7, 30.0)
	if d == Network.local_player:
		d.add_shake(0.12)


## Свой дрон на стене: соскальзывание, порыв, R — сбить лёд. Возвращает true, если сорвался
func _hazards(d: Node3D, data: Dictionary, press: Array, delta: float, bot: bool) -> bool:
	var ax: Array = data["ax"]
	var k := int(data["k"])
	var x := float(data["x"])
	var me: bool = d == Network.local_player
	var g := gust_state()
	var planted := 0
	for v in ax:
		if not is_nan(float(v)):
			planted += 1
	# порыв ветра
	var gin := _gust_in
	var hold := planted == 2 and int(data["sw"]) < 0 and int(data.get("slip", -1)) < 0
	data["hold"] = hold
	if int(g.x) == 1:
		# шаг 125: предвестник — лёгкий ветер, ничего не отнимает: только качает и предупреждает (5 с)
		var wk := clampf(gin / GUST_WARN, 0.0, 1.0)
		if me:
			d.add_shake(0.004 + 0.012 * wk)
		if not hold:
			data["x"] = clampf(x + g.y * 0.08 * wk * delta, -M.FACE_W, M.FACE_W)
	elif int(g.x) == 2:
		var gk := smoothstep(0.0, 0.8, gin)          # порыв нарастает, а не бьёт сразу
		d.stamina = maxf(float(d.stamina) - (1.5 if hold else 13.0) * gk * delta, 0.0)
		if not hold:
			data["x"] = clampf(x + g.y * 0.5 * gk * delta, -M.FACE_W, M.FACE_W)
		if me:
			d.add_shake((0.02 if hold else 0.07) * gk)
		if not hold and int(data.get("slip", -1)) < 0 and randf() < delta * 0.5 * gk:
			_start_slip(d, data, randi() % 2)
	if int(g.x) != _gust_prev and me:
		if int(g.x) == 1:
			SFX.play(self, d.global_position + Vector3.UP * 2.0, "whistle", -8.0, 0.55, 30.0)
			get_tree().call_group("level", "show_banner", "Ветер поднимается!", "Через 5 секунд порыв — вбей ОБА ледоруба и не бей")
		elif int(g.x) == 2:
			SFX.play(self, d.global_position + Vector3.UP * 2.0, "gust", 2.0, 1.0, 30.0)
		elif _gust_prev == 2:
			mtn.say("Порыв стих — можно лезть дальше")
	if me:
		_gust_prev = int(g.x)
	# соскальзывание: само по себе (чаще в порыв), жми кнопку этого ледоруба
	data["slip_cd"] = float(data.get("slip_cd", randf_range(SLIP_EVERY.x, SLIP_EVERY.y))) - delta * (2.0 if int(g.x) == 2 else 1.0)
	if int(data.get("slip", -1)) < 0 and float(data["slip_cd"]) <= 0.0 and planted == 2 and int(data["sw"]) < 0 and not leg_by.has(int(d.peer_id)):
		_start_slip(d, data, randi() % 2)
	# шаг 127: ледоруб во льду — скоро поедет сам
	var on_ice := false
	for hi in 2:
		var it := float(data.get("icy%d" % hi, 0.0))
		if it > 0.0 and not is_nan(float(ax[hi])):
			on_ice = true
			it -= delta
			if it <= 0.0:
				if int(data.get("slip", -1)) < 0 and planted == 2 and int(data["sw"]) < 0:
					_start_slip(d, data, hi)
					it = 0.0
				else:
					it = 0.1
			data["icy%d" % hi] = it
	if on_ice:
		d.stamina = maxf(float(d.stamina) - 0.2 * delta, 0.0)
	var sh := int(data.get("slip", -1))
	if sh >= 0:
		data["slip_t"] = float(data["slip_t"]) + delta
		ax[sh] = float(ax[sh]) - (0.55 if int(g.x) != 2 else 0.9) * delta
		var saved: bool = press[sh] or (bot and float(data["slip_t"]) > 0.35)
		if saved:
			press[sh] = false
			data["slip"] = -1
			_chips(Vector3(M.BX + x + (-0.2 if sh == 0 else 0.2), float(ax[sh]), _surf(k, x, float(data["y"]))))
			if me:
				d.add_shake(0.08)
				mtn.say("Удержал!")
			# всё ещё во льду — поедет снова
			if _in_slab(k, x + (-0.2 if sh == 0 else 0.2), float(ax[sh])):
				data["icy%d" % sh] = randf_range(1.0, 2.0)
		elif float(data["slip_t"]) > SLIP_T:
			data["slip"] = -1
			ax[sh] = NAN
			d.stamina = maxf(float(d.stamina) - 10.0, 0.0)
			SFX.play(self, d.global_position + Vector3.UP * 2.0, "clank", -2.0, 1.2, 30.0)
			if me:
				d.add_shake(0.3)
				mtn.say("Ледоруб вырвало! Висишь на одном — вбей снова (%s)!" % ("ЛКМ" if sh == 0 else "ПКМ"))
	# ни одного ледоруба в стене и не бью — держаться не за что: срыв
	if planted == 0 and int(data["sw"]) < 0:
		return true
	# на одном ледорубе силы тают втрое
	if planted == 1 and int(data["sw"]) < 0:
		d.stamina = maxf(float(d.stamina) - AX_HANG * 2.0 * delta, 0.0)
	# R — отбить лёд вниз на тех, кто ниже
	_kick_cd = maxf(_kick_cd - delta, 0.0)
	if me and d._just("shake_ice") and _kick_cd <= 0.0 and int(data["sw"]) < 0:
		_kick_cd = KICK_CD
		d.stamina = maxf(float(d.stamina) - 4.0, 0.0)
		_kick_all(k, Vector3(M.BX + x, float(data["y"]) - 0.2, _surf(k, x, float(data["y"])) + 0.3), int(d.peer_id))
		mtn.say("Отбил лёд вниз! Берегитесь, кто ниже :)")
	return false


## Хост: сосульки трещат и падают сами, камнепады — над теми, кто лезет
func _server_hazards(delta: float) -> void:
	for i in _ice.size():
		var I: Dictionary = _ice[i]
		I["t"] = float(I["t"]) + delta
		if int(I["st"]) == 1 and float(I["t"]) > 1.2:
			_ice_all(i, 2, -1)
		elif int(I["st"]) == 2 and float(I["t"]) > 35.0:
			_ice_all(i, 0, -1)
	_rock_t -= delta
	if _rock_t > 0.0:
		return
	_rock_t = randf_range(18.0, 30.0)          # шаг 126: реже — силы рассчитаны на 1 попадание за участок
	var climbers: Array = []
	for d in get_tree().get_nodes_in_group("player"):
		if int(d.snow.climb) == 3 and not bool(d.get("is_dead")):
			climbers.append(d)
	if climbers.is_empty():
		return
	var c: Node3D = climbers[randi() % climbers.size()]
	var cd: Dictionary = c.snow._cl_data
	var k := int(cd.get("k", 0))
	var x := clampf(float(cd.get("x", 0.0)) + randf_range(-2.0, 2.0), -M.FACE_W, M.FACE_W)
	# сосулька рядом — трещит; иначе — камень
	for i in _ice.size():
		var I: Dictionary = _ice[i]
		if int(I["k"]) == k and int(I["st"]) == 0 and absf(float(I["x"]) - x) < 1.5 and randf() < 0.6:
			_ice_all(i, 1, -1)
			return
	_rock_all(k, x, 1.3)


## Визуал: трещащие сосульки качаются; ветер — снег вбок у своего на стене
var _gust_fx: GPUParticles3D
var _gust_dir := 0.0
func _visual_hazards(delta: float) -> void:
	_update_falls(delta)
	var me = Network.local_player
	var g := gust_state()
	var on: bool = me != null and int(me.snow.climb) == 3 and int(g.x) >= 1
	if on and (_gust_fx == null or _gust_dir != g.y):
		if _gust_fx:
			_gust_fx.queue_free()
		_gust_dir = g.y
		_gust_fx = FX.particles(Color(0.9, 0.95, 1.0), 140, 0.9, 0.025, 10.0, 16.0, Vector3(g.y * 25.0, -2.0, 0.0), 25.0, false, true)
		add_child(_gust_fx)
	if _gust_fx:
		_gust_fx.emitting = on
		if on:
			# шаг 125: предвестник — редкие снежинки вбок, всё гуще; порыв — сплошная метель
			_gust_fx.amount_ratio = lerpf(0.08, 0.4, clampf(_gust_in / GUST_WARN, 0.0, 1.0)) if int(g.x) == 1 else 1.0
			_gust_fx.global_position = me.global_position + Vector3(-g.y * 5.0, 1.6, 1.4)
	for I in _ice:
		if int(I["st"]) == 1:
			var n: Node3D = I["n"]
			n.rotation.z = sin(float(I["t"]) * 40.0) * 0.06
			I["t"] = float(I["t"]) + (delta if not multiplayer.is_server() else 0.0)


func _build_pitch(k: int, rng: RandomNumberGenerator) -> void:
	var y0 := M.pitch_base(k)
	var y1 := M.pitch_top(k)
	var z := M.face_z(k)
	var hw := M.FACE_SIDE
	var nz := FastNoiseLite.new()
	nz.seed = 911 + k
	nz.frequency = 0.35
	nz.fractal_octaves = 3
	_bn.append(nz)
	# --- скальная плита ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 40
	var ny := int((y1 - y0) / 0.45) + 2
	var hwm := hw + 1.4                 # шаг 127: плита шире полки — края загибаются в склон
	var grid: Array = []
	for j in ny + 1:
		var row: Array = []
		var yy := lerpf(y0 - 0.3, y1 + 0.05, float(j) / ny)
		for i in nx + 1:
			var xx := lerpf(-hwm, hwm, float(i) / nx)
			row.append(Vector3(M.BX + xx, yy, z + _bump(k, xx, yy)))
		grid.append(row)
	for j in ny:
		for i in nx:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i]
			var d: Vector3 = grid[j + 1][i + 1]
			for v in [a, c, b, b, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var wall := MeshInstance3D.new()
	wall.mesh = st.commit()
	wall.material_override = _wall_m()
	wall.name = "FaceWall%d" % k
	add_child(wall)
	# коллизия — точно по поверхности (раньше коробка за плитой: выпуклости были «сквозными»)
	var body := StaticBody3D.new()
	body.add_to_group("safe_ground")
	add_child(body)
	var wcs := CollisionShape3D.new()
	wcs.shape = wall.mesh.create_trimesh_shape()
	body.add_child(wcs)
	_col_box(body, Vector3(hw * 2.0 - 2.0, y1 - y0 - 0.6, 0.8), Vector3(M.BX, (y0 + y1) * 0.5 - 0.3, z - 2.6))
	# --- полка: узкая неровная скальная, спереди — скруглённый край плиты, сзади — осыпь к следующей стене ---
	var last := k == M.PITCHES.size() - 1
	var ld := M.LEDGE_D if not last else 6.0
	var sn := FastNoiseLite.new()
	sn.seed = 377 + k
	sn.frequency = 0.6
	var ss := SurfaceTool.new()
	ss.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := 30
	var sz := 6
	var sg: Array = []
	for j in sz + 1:
		var row2: Array = []
		var t := float(j) / sz
		for i in sx + 1:
			var xx := lerpf(-hw, hw, float(i) / sx)
			var zf := z + _bump(k, xx, y1 + 0.05)
			var zz := lerpf(zf, z - ld - 0.15, t)
			var hy := y1 + 0.05
			if j > 0:
				hy = y1 + 0.06 + (sn.get_noise_2d(xx, zz) * 0.5 + 0.5) * 0.12
				if not last:
					hy += smoothstep(0.55, 1.0, t) * (0.25 + 0.2 * sn.get_noise_2d(xx * 0.5, 9.0))   # осыпь у стены
				# края полки уходят вниз в склон
				hy -= smoothstep(hw - 1.2, hw, absf(xx)) * 0.35
			row2.append(Vector3(M.BX + xx, hy, zz))
		sg.append(row2)
	for j in sz:
		for i in sx:
			var a2: Vector3 = sg[j][i]
			var b2: Vector3 = sg[j][i + 1]
			var c2: Vector3 = sg[j + 1][i]
			var d2: Vector3 = sg[j + 1][i + 1]
			for v in [a2, c2, b2, b2, c2, d2]:
				ss.add_vertex(v)
	ss.generate_normals()
	var shelf := MeshInstance3D.new()
	shelf.mesh = ss.commit()
	shelf.material_override = _wall_m()         # шаг 127: полка — скала (снег — сугробами), без белой «линейки»
	shelf.name = "Shelf%d" % k
	add_child(shelf)
	var scs := CollisionShape3D.new()
	scs.shape = shelf.mesh.create_trimesh_shape()
	body.add_child(scs)
	# снег: сугробы в углу у следующей стены и пятна по полке
	for n2 in (4 if not last else 2):
		var dr := MeshInstance3D.new()
		var dm := SphereMesh.new()
		dm.radius = 1.0
		dm.height = 2.0
		dm.radial_segments = 10
		dm.rings = 5
		dr.mesh = dm
		dr.material_override = _snow_mat
		dr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dr)
		var xs := rng.randf_range(-hw + 1.0, hw - 1.0)
		dr.scale = Vector3(rng.randf_range(0.7, 1.5), rng.randf_range(0.18, 0.3), rng.randf_range(0.35, 0.55))
		dr.position = Vector3(M.BX + xs, y1 + 0.12, z - ld + 0.25 if not last else z - rng.randf_range(1.5, 4.5))
	# камни на полке и по кромке (разного размера, кучками — без ровного ряда)
	for n3 in 6:
		var xs3 := rng.randf_range(-hw + 0.4, hw - 0.4)
		var front := rng.randf() < 0.55
		var zr := z + _bump(k, xs3, y1) - (rng.randf_range(0.15, 0.45) if front else rng.randf_range(0.9, ld - 0.2))
		var sz3 := rng.randf_range(0.18, 0.42) * (0.7 if front else 1.2)
		mtn.builder.rock_vis(Vector3(M.BX + xs3, y1 + sz3 * 0.3, zr), Vector3(sz3, sz3 * 0.85, sz3), rng.randf_range(0.0, TAU), "rock", 1)
	# шаг 127: по бокам кромки — крупные округлые глыбы: верх уступа не «линейкой», а горбами
	for sx4 in [-1.0, 1.0]:
		for n4 in 3:
			var xs4: float = float(sx4) * rng.randf_range(hw - 1.6, hw + 0.4)
			var sz4 := rng.randf_range(0.7, 1.5)
			var zr4 := z + _bump(k, xs4, y1 - 0.3) - rng.randf_range(0.2, 0.9)
			mtn.builder.rock_vis(Vector3(M.BX + xs4, y1 + sz4 * 0.15, zr4), Vector3(sz4, sz4 * rng.randf_range(0.6, 0.9), sz4 * 0.9), rng.randf_range(0.0, TAU), "rock", 1)
	# зацепки — мелкие камни по плите
	for n in 46:
		var xx2 := rng.randf_range(-M.FACE_W, M.FACE_W)
		var yy2 := rng.randf_range(y0 + 0.4, y1 - 0.5)
		if _in_slab(k, xx2, yy2):
			continue
		mtn.builder.rock_vis(Vector3(M.BX + xx2, yy2, z + _bump(k, xx2, yy2) + 0.08), Vector3(rng.randf_range(0.12, 0.25), rng.randf_range(0.08, 0.16), 0.12), 0.0, "rock", 1)
	# гладкий лёд (не держит ледоруб) и сосульки над участком
	for sl in SLABS:
		if int(sl[0]) == k:
			_build_slab(k, sl, rng)
	if not last:
		_build_icicles(k, rng)


## Шаг 122: стена — обледенелая скала (TextureCan Ground 0031), видно издалека, что это «та самая» стена
var _wall_mat: StandardMaterial3D
func _wall_m() -> Material:
	if _wall_mat:
		return _wall_mat
	# шаг 123: тёмная скала (Poly Haven Cliff Side) с холодным отливом и ледяной глазурью;
	# ледяные места — отдельными пластинами (гладкий лёд), сосульки — у кромок
	var t := "res://assets/ropeway/rocks/textures/"
	if not ResourceLoader.exists(t + "cliff_side_diff_1k.jpg"):
		return mtn.rock_mat()
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_texture = load(t + "cliff_side_diff_1k.jpg")
	_wall_mat.albedo_color = Color(0.4, 0.43, 0.5)
	_wall_mat.normal_enabled = true
	_wall_mat.normal_texture = load(t + "cliff_side_nor_gl_1k.jpg")
	_wall_mat.normal_scale = 1.3
	_wall_mat.roughness = 0.82
	_wall_mat.clearcoat_enabled = true
	_wall_mat.clearcoat = 0.35
	_wall_mat.clearcoat_roughness = 0.25
	_wall_mat.uv1_triplanar = true
	_wall_mat.uv1_world_triplanar = true
	_wall_mat.uv1_triplanar_sharpness = 4.0
	_wall_mat.uv1_scale = Vector3(0.22, 0.22, 0.22)
	return _wall_mat


## Полка сверху: та же скала, но со снегом (верхняя грань — снежная)
var _shelf_mat: StandardMaterial3D
func _shelf_m() -> Material:
	if _shelf_mat:
		return _shelf_mat
	var t := "res://assets/peak/tex/"
	_shelf_mat = (_wall_m() as StandardMaterial3D).duplicate() if _wall_m() is StandardMaterial3D else StandardMaterial3D.new()
	if ResourceLoader.exists(t + "snow_color.jpg"):
		_shelf_mat.albedo_texture = load(t + "snow_color.jpg")
		_shelf_mat.normal_texture = load(t + "snow_normal.png")
		_shelf_mat.albedo_color = Color(0.92, 0.95, 1.0)
		_shelf_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
		_shelf_mat.clearcoat_enabled = false
		_shelf_mat.roughness = 0.9
	return _shelf_mat


## Шаг 122: у подножия — стойка с ледорубами (E — взять), прожекторы светят на стену, щит «СТЕНА»
var rack_pos := Vector3.ZERO
func _build_foot() -> void:
	add_to_group("part_sockets")
	rack_pos = Vector3(M.BX + 7.5, M.FOOT_Y, M.FOOT_ZS - 3.2)
	rack_pos.y = mtn._gy(rack_pos.x, rack_pos.z)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.27, 0.15)
	wood.roughness = 0.8
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.32, 0.36)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var yel := StandardMaterial3D.new()
	yel.albedo_color = Color(0.95, 0.72, 0.1)
	# стойка: две ножки, перекладина, козырёк; ледорубы висят клювом вверх
	var rb := rack_pos
	for sx in [-1.0, 1.0]:
		_mbeam(rb + Vector3(sx * 0.9, 0.0, 0.25), rb + Vector3(sx * 0.9, 1.9, 0.0), 0.05, wood)
		_mbeam(rb + Vector3(sx * 0.9, 0.0, -0.3), rb + Vector3(sx * 0.9, 1.9, 0.0), 0.05, wood)
	_mbeam(rb + Vector3(-1.0, 1.55, 0.0), rb + Vector3(1.0, 1.55, 0.0), 0.04, metal)
	_mbox(Vector3(2.3, 0.08, 0.7), rb + Vector3(0, 2.0, 0.05), yel, false)
	var sp: Node = mtn.get("spires")
	if sp and sp.has_method("_axe_into"):
		for i in 4:
			var h := Node3D.new()
			add_child(h)
			h.global_transform = Transform3D((Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.FORWARD, 0.15 * (i - 1.5))).scaled(Vector3.ONE * 1.7), rb + Vector3(-0.66 + i * 0.44, 1.52, 0.06))
			sp.call("_axe_into", h)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.4)
	lamp.light_energy = 2.2
	lamp.omni_range = 6.0
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 70.0
	add_child(lamp)
	lamp.global_position = rb + Vector3(0, 1.85, 0.6)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.8, 0.45) * 3.0
	_mbox(Vector3(0.5, 0.06, 0.14), rb + Vector3(0, 1.94, 0.3), glow, false)
	mtn.sign_at(rb + Vector3(1.9, 0.0, 0.6), "ЛЕДОРУБЫ\nE — взять пару\n(без них на стену не залезть)", Color(1.0, 0.8, 0.3))
	# прожекторы на стену: два столба у края площадки, лучи вверх по стене
	for sx2 in [-1.0, 1.0]:
		var bp := Vector3(M.BX + sx2 * 9.5, M.FOOT_Y, M.FOOT_ZS - 1.0)
		bp.y = mtn._gy(bp.x, bp.z)
		_mbeam(bp, bp + Vector3.UP * 3.2, 0.07, metal)
		_mbox(Vector3(0.55, 0.4, 0.45), bp + Vector3(0, 3.35, 0), metal, false)
		_mbox(Vector3(0.46, 0.32, 0.04), bp + Vector3(0, 3.35, -0.24), glow, false)
		var sl := SpotLight3D.new()
		sl.light_color = Color(0.85, 0.92, 1.0)
		sl.light_energy = 40.0
		sl.spot_range = 80.0
		sl.spot_angle = 32.0
		sl.spot_attenuation = 0.6
		sl.shadow_enabled = false
		sl.distance_fade_enabled = true
		sl.distance_fade_begin = 180.0
		add_child(sl)
		var from := bp + Vector3(0, 3.35, -0.3)
		var to := Vector3(M.BX - sx2 * 1.5, M.FOOT_Y + 22.0, M.face_z(0))
		sl.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)


## E у стойки — взять (или вернуть) ледорубы
func try_socket(d: Node3D) -> bool:
	if rack_pos == Vector3.ZERO or d.global_position.distance_to(rack_pos) > 2.2:
		return false
	var sp: Node = mtn.get("spires")
	if sp == null or d.get("held_parcel") != null or d.get("held_friend") != null:
		return false
	var pid := int(d.peer_id)
	sp.call("_ask", pid, not bool(d.get("ice_axes")))
	return true


func _col_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


## Лебёдка: ворот на вершине, трос над кулуаром, корзина, оттяжка, карнизы на пути
func _build_winch() -> void:
	var hx := M.HOIST.x
	var hz := M.HOIST.y
	basket_low = Vector3(hx, M.FOOT_Y + 0.35, hz)
	drum_pos = Vector3(hx, M.PEAK, hz - 6.0)
	drum_pos.y = mtn._gy(drum_pos.x, drum_pos.z)
	winch_pos = drum_pos + Vector3(1.4, 0.0, -0.8)
	tag_pos = Vector3(hx + 0.8, M.FOOT_Y, hz + 11.0)
	tag_pos.y = mtn._gy(tag_pos.x, tag_pos.z)
	mtn.add_hold("WINCH", winch_pos, 1.2)
	mtn.add_hold("TAG", tag_pos, 1.2)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.35, 0.36, 0.4)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.45, 0.8)
	paint.roughness = 0.5
	# барабан с воротом и стрела над кулуаром
	_mbox(Vector3(1.6, 1.0, 1.0), drum_pos + Vector3.UP * 0.5, paint, true)
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.38
	dm.bottom_radius = 0.38
	dm.height = 1.2
	dm.material = metal
	drum.mesh = dm
	drum.rotation.z = PI * 0.5
	drum.position = drum_pos + Vector3.UP * 1.3
	drum.name = "Drum"
	add_child(drum)
	for s in [-1.0, 1.0]:
		_mbeam(drum_pos + Vector3(s * 0.7, 0.0, 0.3), Vector3(hx + s * 0.4, M.PEAK + 4.2, hz), 0.07, metal)
	_mbeam(Vector3(hx - 0.5, M.PEAK + 4.2, hz), Vector3(hx + 0.5, M.PEAK + 4.2, hz), 0.08, metal)
	_mbeam(drum_pos + Vector3(0.8, 1.3, 0), winch_pos + Vector3(0, 1.0, 0), 0.04, metal)
	# корзина
	_basket = Node3D.new()
	_basket.name = "Basket"
	add_child(_basket)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	for s2 in [-1.0, 1.0]:
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			var side := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.06, 0.45, 1.0) if axis == Vector3.RIGHT else Vector3(1.0, 0.45, 0.06)
			side.mesh = sb
			side.material_override = wood
			side.position = axis * s2 * 0.5 + Vector3.UP * 0.22
			_basket.add_child(side)
	var bottom := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.0, 0.06, 1.0)
	bottom.mesh = bb
	bottom.material_override = wood
	_basket.add_child(bottom)
	_basket.position = basket_low
	# столбик оттяжки
	mtn.post(tag_pos, Color(0.3, 0.75, 1.0), self)
	# карнизы над тросом
	for sy in M.SNAGS:
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(3.8, 1.3, M.SNAG_OUT)
		roof.mesh = rm
		roof.material_override = mtn.rock_mat()
		roof.position = Vector3(hx, float(sy) + 0.9, M.SLOT_ZN + M.SNAG_OUT * 0.5 - 0.2)
		add_child(roof)
		mtn.builder.rock_vis(roof.position + Vector3(0, -0.6, M.SNAG_OUT * 0.5 - 0.2), Vector3(1.4, 0.6, 0.6), 0.3, "rock")


func _mbox(size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		add_child(body)
		_col_box(body, size, pos)


func _mbeam(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	cm.material = mat
	mi.mesh = cm
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5)
	add_child(mi)


# ---------------------------------------------------------------------------
#  Правила стены
# ---------------------------------------------------------------------------

func _band_of(k: int) -> Array:
	for b in M.BANDS:
		if int(b[0]) == k:
			return b
	return []


func _in_band(k: int, x: float, y: float) -> bool:
	var b := _band_of(k)
	if b.is_empty():
		return false
	return y > M.pitch_top(k) - float(b[1]) - 0.05 and x > float(b[2]) and x < float(b[3])


func _in_crack(k: int, x: float, y: float) -> bool:
	var b := _band_of(k)
	if b.is_empty():
		return false
	return y > M.pitch_top(k) - float(b[1]) - 2.5 and not (x > float(b[2]) and x < float(b[3]))


## Где на стене можно вцепиться: стою у стены участка k на его подножии
func _start_cell(p: Vector3) -> int:
	for k in M.PITCHES.size():
		var z := M.face_z(k)
		if absf(p.y - M.pitch_base(k)) < 1.0 and p.z - z < 2.4 and p.z - z > -0.3 and absf(p.x - M.BX) < M.FACE_W:
			return k
	return -1


func partner(pid: int) -> int:
	return int(ties.get(pid, -1))


## Друг в связке держит (на полке — у крюка, на стене — вцепился)
func secure(pid: int) -> bool:
	var other := partner(pid)
	if other < 0:
		return false
	for id in mtn.active:
		if String(id).begins_with("BEL") and int(mtn.active[id]) == other:
			return true
	var d: Node3D = mtn.drone_by_id(other)
	return d != null and not d.is_dead and d.snow.mpose == 12


func night_block() -> bool:
	return false                       # шаг 119: ночью как раз и лезут


# ---------------------------------------------------------------------------
#  Свои дроны
# ---------------------------------------------------------------------------

func local(d: Node3D, hp: String, holding: bool, _delta: float) -> void:
	var pid := int(d.peer_id)
	# позы у точек
	if hp == "WINCH":
		d.snow.set_mpose(9, fposmod(mtn.now() * 0.7, 1.0), drum_pos + Vector3(0.9, 1.3, 0), Vector3.LEFT)
		d.visual.rotation.y = atan2(1.0, 0.0)
		return
	if hp == "TAG":
		d.snow.set_mpose(10, 0.0, _basket.global_position, (_basket.global_position - d.global_position).normalized())
		return
	if hp.begins_with("BEL"):
		var other: Node3D = mtn.drone_by_id(partner(pid))
		d.snow.set_mpose(11, 0.0, other.global_position if other else d.global_position + Vector3.UP, Vector3.FORWARD)
		return
	if hp.begins_with("PULL"):
		var k := int(hp.substr(4))
		d.snow.set_mpose(7, 0.0, Vector3(d.global_position.x, M.pitch_top(k) - 1.6, M.face_z(k) + 0.3), Vector3.BACK)
		d.visual.rotation.y = atan2(0.0, -1.0)          # лицом к краю (на юг)
		return
	if d.snow.mpose in [7, 9, 10, 11] and hp == "":
		d.snow.set_mpose(0)
	# шаг 128: падаю после срыва — бью ледорубом в стену, чтобы зацепиться
	if d.has_meta("arrest") and _try_arrest(d):
		return
	# шаг 128: застрял на выступе посреди стены (упал на «пузо» скалы) — ЛКМ/ПКМ: вбить ледоруб и лезть дальше
	if d.is_on_floor() and int(d.snow.climb) == 0 and bool(d.get("ice_axes")) and d.held_parcel == null and (d._just("use_item") or d._just("use_alt")):
		var pp := d.global_position
		for k5 in M.PITCHES.size():
			var x5 := pp.x - M.BX
			if pp.y > M.pitch_base(k5) + 1.0 and pp.y < M.pitch_top(k5) - 1.5 and absf(x5) < M.FACE_W and pp.z - _surf(k5, x5, pp.y) < 2.4 and pp.z > M.face_z(k5) - 2.0:
				d.snow.start_scripted(3, self, {"k": k5, "x": x5, "y": pp.y, "slip_cd": randf_range(SLIP_EVERY.x, SLIP_EVERY.y), "ax": [pp.y + 1.95, pp.y + 1.7],
					"sw": -1, "swt": 0.0, "tgt": 0.0, "last": 1, "bot_t": 0.0})
				d.visual.rotation.y = 0.0
				_axes_all(int(d.peer_id), true)
				SFX.play(self, pp + Vector3.UP * 1.9, "clank", -6.0, 1.3)
				return
	# вцепиться в стену: ЛКМ/ПКМ (или E) у стены — вбил ледоруб
	var hit_btn: bool = d._just("use_item") or d._just("use_alt")
	if (holding or hit_btn) and hp == "" and d.is_on_floor() and d.held_friend == null and int(d.snow.climb) == 0:
		var k2 := _start_cell(d.global_position)
		var has_ax: bool = bool(d.get("ice_axes")) or bool(d.get("is_bot"))
		if k2 >= 0 and d.held_parcel == null and not has_ax and d == Network.local_player and hit_btn:
			mtn.say("Без ледорубов не залезть — возьми их на стойке у подножия (E)")
		if k2 >= 0 and d.held_parcel == null and has_ax:
			var x := clampf(d.global_position.x - M.BX, -M.FACE_W, M.FACE_W)
			var y0 := M.pitch_base(k2) + 0.2
			d.snow.start_scripted(3, self, {"k": k2, "x": x, "y": y0, "slip_cd": 0.0, "ax": [y0 + 2.0, y0 + 1.75],
				"sw": -1, "swt": 0.0, "tgt": 0.0, "last": 1, "bot_t": 0.0})
			d.visual.rotation.y = 0.0
			_axes_all(int(d.peer_id), true)
			SFX.play(self, d.global_position + Vector3.UP * 1.9, "clank", -6.0, 1.3)


## Шаг 119: друг лезет надо мной — E: схватить его за ногу (я сам на стене)
func _try_leg(d: Node3D, data: Dictionary) -> bool:
	for o in get_tree().get_nodes_in_group("player"):
		if o == d or bool(o.get("is_dead")) or int(o.snow.climb) != 3 or leg_by.has(int(o.peer_id)):
			continue
		var od: Dictionary = o.snow._cl_data
		if int(od["k"]) == int(data["k"]) and absf(float(od["x"]) - float(data["x"])) < 1.1 \
				and float(od["y"]) - float(data["y"]) > 0.8 and float(od["y"]) - float(data["y"]) < 3.2:
			data["ride"] = int(o.peer_id)
			_leg_all(int(o.peer_id), int(d.peer_id))
			SFX.play(self, d.global_position + Vector3.UP * 2.0, "creak", -4.0, 1.4)
			if d == Network.local_player:
				mtn.say("Вцепился другу в ногу — едешь на нём! (E — отпустить)")
			return true
	return false


## Движение по стене (3), подтягивают (6), вылезаю на полку (7)
func drive(d: Node3D, kind: int, t: float, data: Dictionary, delta: float) -> void:
	var pid := int(d.peer_id)
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = 0.0
	if kind == 6 or kind == 7:
		var from: Vector3 = data["from"]
		var to: Vector3 = data["to"]
		var dur := PULL_T if kind == 6 else MANTLE_T
		var kk := clampf(t / dur, 0.0, 1.0)
		var pos := Vector3.ZERO
		if kk < 0.6:
			var a := smoothstep(0.0, 1.0, kk / 0.6)
			pos = from.lerp(Vector3(from.x, to.y - 0.35, from.z), a)
		else:
			var b := smoothstep(0.0, 1.0, (kk - 0.6) / 0.4)
			pos = Vector3(from.x, to.y - 0.35, from.z).lerp(to, b) + Vector3.UP * sin(b * PI) * 0.2
		d.global_position = pos
		d.snow.set_mpose(8 if kind == 6 else 6, kk, Vector3(from.x, to.y, M.face_z(int(data["k"])) + 0.05), Vector3.FORWARD)
		if kk >= 1.0:
			d.snow.end_scripted()
			d.snow.set_mpose(0)
			d.global_position = to
		return
	if kind == 9:
		_drive_mantle(d, t, data)
		return
	# --- лезу на ледорубах (шаг 119) ---
	var k: int = data["k"]
	var x: float = data["x"]
	var ax: Array = data["ax"]
	var top := M.pitch_top(k)
	var bot: bool = bool(d.get("is_bot"))
	if d._just("jump"):
		_fall(d, k, x, float(data["y"]), false)
		return
	# еду на друге (держусь за ногу): тело под ним, силы не трачу
	var ride := int(data.get("ride", -1))
	if ride >= 0:
		var rd: Node3D = mtn.drone_by_id(ride)
		if rd == null or bool(rd.get("is_dead")) or int(rd.snow.climb) != 3 or int(leg_by.get(ride, -1)) != pid:
			data["ride"] = -1
			_fall(d, k, x, float(data["y"]), true)
			if d == Network.local_player:
				mtn.say("Стряхнули с ноги — падаю!")
			return
		if d._just("interact") and t > 0.3:
			data["ride"] = -1
			_leg_all(ride, -1)
			data["leg_cd"] = 0.4
		else:
			var rdd: Dictionary = rd.snow._cl_data
			if int(rdd["k"]) != k:
				data["ride"] = -1
				_leg_all(ride, -1)
			else:
				x = float(rdd["x"])
				var hy2 := float(rdd["y"]) - 1.55
				data["x"] = x
				data["y"] = hy2
				ax[0] = hy2 + 1.9
				ax[1] = hy2 + 1.9
				# шаг 122: вишу под другом, держусь за его ботинок обеими руками, раскачиваюсь
				var sw2 := sin(t * 1.7) * 0.07
				d.global_position = Vector3(M.BX + x + sw2, hy2, _surf(k, x, hy2) + WALL_OFF + 0.12)
				var boot := rd.global_position + Vector3(0.1, 0.08, 0.06)
				d.snow.set_mpose(32, 0.0, boot, Vector3.FORWARD)
				return
	data["leg_cd"] = maxf(float(data.get("leg_cd", 0.0)) - delta, 0.0)
	if not bot and not leg_by.has(pid) and d._just("interact") and float(data["leg_cd"]) <= 0.0 and _try_leg(d, data):
		return
	# A/D — вбок
	var mvx := 0.0
	if not bot:
		if d._held("move_left"):
			mvx -= 1.0
		if d._held("move_right"):
			mvx += 1.0
	if mvx != 0.0 and int(data["sw"]) < 0:
		var nx := clampf(x + mvx * AX_SIDE * delta, -M.FACE_W, M.FACE_W)
		if absf(nx - x) > 0.0001:
			d.stamina = maxf(float(d.stamina) - AX_SIDE_COST * delta, 0.0)
		x = nx
		data["x"] = x
	# удары: ЛКМ — левый, ПКМ — правый (бот бьёт сам, по очереди)
	var press := [false, false]
	if bot:
		data["bot_t"] = float(data["bot_t"]) - delta
		if float(data["bot_t"]) <= 0.0 and int(data["sw"]) < 0:
			data["bot_t"] = 0.42
			press[1 - int(data["last"])] = true
	else:
		press = [d._just("use_item"), d._just("use_alt")]
	# шаг 123: бот — не лезет в гладкий лёд (обходит), в порыв держится и ждёт
	if bot:
		var gb := gust_state()
		if int(gb.x) >= 1 and int(data["sw"]) < 0:
			press = [false, false]
		# выше гладкий лёд — отхожу вбок к ближнему краю (непрерывно), пока над головой не будет чисто
		var yy := float(data["y"])
		var blocked := false
		for dyb in [2.2, 2.8, 3.4]:
			for dxb in [-0.45, 0.0, 0.45]:
				if _in_slab(k, x + dxb, yy + dyb):
					blocked = true
		if blocked:
			if float(data.get("bot_dx", 0.0)) == 0.0:
				var best := 0.0
				var bestd := INF
				for dirc in [-1.0, 1.0]:
					var xc := x
					while absf(xc) <= M.FACE_W:
						var free := true
						for dyb2 in [2.2, 2.8, 3.4]:
							for dxb2 in [-0.45, 0.0, 0.45]:
								if _in_slab(k, xc + dxb2, yy + dyb2):
									free = false
						if free:
							break
						xc += dirc * 0.2
					if absf(xc) <= M.FACE_W and absf(xc - x) < bestd:
						bestd = absf(xc - x)
						best = dirc
				data["bot_dx"] = best if best != 0.0 else (1.0 if x < 0.0 else -1.0)
			press = [false, false]
			data["x"] = clampf(x + float(data["bot_dx"]) * AX_SIDE * delta, -M.FACE_W, M.FACE_W)
			x = float(data["x"])
		else:
			data["bot_dx"] = 0.0
	# шаг 123: соскальзывание, порыв ветра, R — сбить лёд
	if _hazards(d, data, press, delta, bot):
		_fall(d, k, x, float(data["y"]), true)
		return
	x = float(data["x"])
	for h in 2:
		if press[h] and int(data["sw"]) < 0:
			if is_nan(float(ax[1 - h])):
				continue                       # шаг 127: висишь на одном — его не выдернуть (бей вылетевшим)
			var tgt := float(ax[1 - h]) + AX_STEP
			if tgt <= float(ax[h]) + 0.05:
				continue                       # этим и так выше — бей другим!
			data["sw"] = h
			data["swt"] = 0.0
			data["tgt"] = tgt
			data["last"] = h
			data["prev"] = float(ax[h])
			ax[h] = NAN
			d.stamina = maxf(float(d.stamina) - AX_COST, 0.0)
			SFX.play(self, d.global_position + Vector3.UP * 1.8, "puff", -12.0, 1.6)
	if int(data["sw"]) >= 0:
		var h2 := int(data["sw"])
		var t0 := float(data["swt"])
		data["swt"] = t0 + delta
		if t0 < AX_HIT_AT and float(data["swt"]) >= AX_HIT_AT:
			var tg2 := float(data["tgt"])
			var hx2 := x + (-0.2 if h2 == 0 else 0.2)
			var hp2 := Vector3(M.BX + hx2, minf(tg2, top - 0.05), M.face_z(k) + _bump(k, hx2, minf(tg2, top - 0.05)))
			# шаг 127: лёд держит плохо — ледоруб вбит, но скоро поедет (0.5–1.5 с): перебивай быстро
			if tg2 <= top - 0.2 and _in_slab(k, hx2, tg2):
				_sparks(hp2)
				data["icy%d" % h2] = randf_range(1.0, 2.0)
				if d == Network.local_player and not bool(data.get("ice_told", false)):
					data["ice_told"] = true
					mtn.say("Лёд! Ледоруб держится плохо — будет соскальзывать, перебивай быстро")
			else:
				data["icy%d" % h2] = 0.0
			_chips(hp2)
			# сосульки над ударом — обрушил (на тех, кто ниже; меня не задевает)
			for ii in _ice.size():
				var I: Dictionary = _ice[ii]
				if int(I["k"]) == k and int(I["st"]) == 0 and absf(float(I["x"]) - hx2) < 0.75 and float(I["y"]) - tg2 < 1.7 and float(I["y"]) - tg2 > -0.4:
					_ice_all(ii, 2, pid)
					if d == Network.local_player:
						mtn.say("Обрушил сосульки — вниз полетели!")
			if tg2 > top - 0.2:
				# достал до края полки — вылезаю
				_start_mantle(d, k, x)
				return
			ax[h2] = tg2
			if d == Network.local_player:
				d.add_shake(0.06)
		if float(data["swt"]) >= AX_SWING_T:
			data["sw"] = -1
			if is_nan(float(ax[h2])):
				ax[h2] = float(data["tgt"])
	# силы: вишу (на мне друг — вдвое)
	var leg := leg_by.has(pid)
	d.stamina = maxf(float(d.stamina) - AX_HANG * (LEG_DRAIN if leg else 1.0) * delta, 0.0)
	if leg and not bot and d._just("interact"):
		_leg_all(pid, -1)                    # стряхнул друга
		if d == Network.local_player:
			mtn.say("Стряхнул друга с ноги!")
	if float(d.stamina) <= 0.0:
		if d == Network.local_player:
			mtn.say("Нет сил — руки разжались!")
		_fall(d, k, x, float(data["y"]), true)
		return
	_finish_pose(d, data, k, x, top)


## Тело — под ледорубами, перед самой выступающей точкой скалы (шаг 123: не входить в текстуру)
func _finish_pose(d: Node3D, data: Dictionary, k: int, x: float, _top: float) -> void:
	var ax: Array = data["ax"]
	var lo := INF
	var hi := -INF
	for v in ax:
		if not is_nan(float(v)):
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	var hy := (lo + hi) * 0.5 - 1.92 if hi > -INF else float(data["y"])
	hy = maxf(hy, M.pitch_base(k) + 0.1)
	var y := lerpf(float(data["y"]), hy, clampf(get_physics_process_delta_time() * 10.0, 0.0, 1.0))
	data["y"] = y
	var sz := _surf(k, x, y)
	var bz := lerpf(float(data.get("bz", sz)), sz, clampf(get_physics_process_delta_time() * 8.0, 0.0, 1.0))
	bz = maxf(bz, sz - 0.05)
	data["bz"] = bz
	d.global_position = Vector3(M.BX + x, y, bz + WALL_OFF)
	var ref := Vector3(M.BX + x, y, bz)
	var qL := 99 if is_nan(float(ax[0])) else clampi(int((float(ax[0]) - y) * 20.0), 0, 98)
	var qR := 99 if is_nan(float(ax[1])) else clampi(int((float(ax[1]) - y) * 20.0), 0, 98)
	var swc := int(data["sw"]) + 1
	var ph := clampi(int(float(data["swt"]) / AX_SWING_T * 99.0), 0, 99) if swc > 0 else 0
	var tq := clampi(int((float(data["tgt"]) - y) * 20.0), 0, 98)
	d.snow.set_mpose(17, float(qL + qR * 100 + swc * 10000 + ph * 100000) + float(tq) / 100.0, ref, Vector3.FORWARD)


## Шаг 123: ледоруб по гладкому льду — искры и звон
func _sparks(p: Vector3) -> void:
	var sp := FX.particles(Color(1.0, 0.85, 0.5), 14, 0.3, 0.02, 2.5, 5.0, Vector3(0, -9, 0), 60.0, true, true)
	add_child(sp)
	sp.global_position = p + Vector3.BACK * 0.12
	sp.emitting = true
	get_tree().create_timer(0.8).timeout.connect(sp.queue_free)
	SFX.play(self, p, "ding", -6.0, randf_range(1.7, 2.0), 30.0)


## Шаг 119: крошка льда от удара
func _chips(p: Vector3) -> void:
	var sp := FX.particles(Color(0.85, 0.92, 1.0), 10, 0.45, 0.03, 1.2, 3.0, Vector3(0, -9, 0), 70.0, true, true)
	add_child(sp)
	sp.global_position = p + Vector3.BACK * 0.1
	sp.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sp.queue_free)
	SFX.play(self, p, "thunk", -8.0, randf_range(1.3, 1.6), 30.0)


## Шаг 119: вылезти на полку: подтянулся на ледорубах → локти на край → колено → встал (поза 19)
func _start_mantle(d: Node3D, k: int, x: float) -> void:
	var pid := int(d.peer_id)
	if leg_by.has(pid):
		_leg_all(pid, -1)
	d.snow.end_scripted()
	var top := M.pitch_top(k)
	var dest := Vector3(M.BX + x, top + 0.05, M.face_z(k) - 1.0)
	d.snow.start_scripted(9, self, {"k": k, "x": x, "from": d.global_position, "dest": dest})


func _drive_mantle(d: Node3D, t: float, data: Dictionary) -> void:
	var k: int = data["k"]
	var x: float = data["x"]
	var n := Vector3.BACK
	var top := M.pitch_top(k)
	var fz := maxf(M.face_z(k), _surf(k, x, top - 2.3))     # шаг 123: перед выступами, не в скале
	var from: Vector3 = data["from"]
	var dest: Vector3 = data["dest"]
	var kk := clampf(t / AX_MANTLE, 0.0, 1.0)
	var base := Vector3(M.BX + x, 0.0, fz)
	var hang := base + Vector3(0, top - 1.85, 0) + n * 0.42
	var chest := base + Vector3(0, top - 1.05, 0) + n * 0.34
	var knee := base + Vector3(0, top - 0.55, 0) + n * 0.1
	var pos := Vector3.ZERO
	if kk < 0.18:
		pos = from.lerp(hang, smoothstep(0.0, 1.0, kk / 0.18))
	elif kk < 0.5:
		var a2 := smoothstep(0.0, 1.0, (kk - 0.18) / 0.32)
		pos = hang.lerp(chest, a2) + n * sin(a2 * PI) * 0.06
	elif kk < 0.78:
		pos = chest.lerp(knee, smoothstep(0.0, 1.0, (kk - 0.5) / 0.28))
	else:
		var c2 := smoothstep(0.0, 1.0, (kk - 0.78) / 0.22)
		pos = knee.lerp(dest, c2) + Vector3.UP * sin(c2 * PI) * 0.12
	d.global_position = pos
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = 0.0
	d.snow.set_mpose(19, kk, base + Vector3(0, top, 0) - n * 0.05, -n)
	if kk >= 1.0:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.global_position = dest
		d.velocity = Vector3.ZERO
		if k == M.PITCHES.size() - 1:
			_axes_all(int(d.peer_id), false)        # вершина — ледорубы за пояс
			if d == Network.local_player:
				get_tree().call_group("level", "show_banner", "ВЕРШИНА!", "Посылку поднимают лебёдкой — крутите ворот (E)")
		elif d == Network.local_player:
			mtn.say("Полка! Отдохни — силы восстанавливаются. Дальше — ЛКМ/ПКМ у стены")


## Шаг 119: ледорубы в руках (у всех) — модели берём у пропасти с выступами
func _axes_all(pid: int, on: bool) -> void:
	if mtn._online():
		_axes.rpc(pid, on)
	else:
		_axes(pid, on)


@rpc("any_peer", "call_local", "reliable")
func _axes(pid: int, on: bool) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	var sp: Node = mtn.get("spires")
	if d:
		d.set("ice_axes", on)
	if sp:
		var axd: Dictionary = sp.get("axes")
		if on:
			axd[pid] = true
		else:
			axd.erase(pid)
		sp.call("_hand_models", pid, on)


## Шаг 119: кто за чью ногу держится (у всех): хозяин ноги → кто держится (−1 — отпустил)
var leg_by := {}


func _leg_all(owner_pid: int, rider: int) -> void:
	if mtn._online():
		_leg.rpc(owner_pid, rider)
	else:
		_leg(owner_pid, rider)


@rpc("any_peer", "call_local", "reliable")
func _leg(owner_pid: int, rider: int) -> void:
	if rider < 0:
		leg_by.erase(owner_pid)
	else:
		leg_by[owner_pid] = rider
	var me = Network.local_player
	if me != null and int(me.peer_id) == owner_pid and rider >= 0:
		get_tree().call_group("level", "show_banner", "Кто-то висит у тебя на ноге!", "Силы тают вдвое. E — стряхнуть")


## Сорвался: в связке и друг держит — повис; иначе — падение (и друга на стене, если не держится, тоже сдёрнет)
func _slip(d: Node3D, data: Dictionary) -> void:
	var pid := int(d.peer_id)
	var k: int = data["k"]
	var other := partner(pid)
	if d == Network.local_player:
		d.add_shake(0.4)
	if other >= 0 and secure(pid):
		data["y"] = maxf(float(data["y"]) - 1.5, M.pitch_base(k) + 0.2)
		d.stamina = maxf(d.stamina, 25.0)
		_jolt_all(other, 15.0)
		return
	if other >= 0:
		var od: Node3D = mtn.drone_by_id(other)
		if od != null and od.is_on_floor():
			# друг стоял, но не держал — рывок, повис ниже
			data["y"] = maxf(float(data["y"]) - 3.5, M.pitch_base(k) + 0.2)
			d.stamina = maxf(d.stamina, 20.0)
			_jolt_all(other, 0.0)
			return
		if od != null and int(od.snow.climb) == 3:
			_yank_all(other)
	_fall(d, k, float(data["x"]), float(data["y"]), true)


func _fall(d: Node3D, k: int, x: float, y: float, slipped: bool) -> void:
	var pid := int(d.peer_id)
	if leg_by.has(pid):
		_leg_all(pid, -1)
	d.snow.end_scripted()
	d.snow.set_mpose(0)
	d.global_position = Vector3(M.BX + x, y, _surf(k, x, y) + 0.8)        # шаг 123: от выступов, не в скалу
	d.velocity = Vector3(0, -1.0 if slipped else 0.0, 1.2)
	# шаг 128: сорвался — есть ~1.5 с, чтобы зацепиться ледорубом (ЛКМ/ПКМ), чаще всего получается
	if slipped and bool(d.get("ice_axes")) or slipped and bool(d.get("is_bot")):
		d.set_meta("arrest", {"t": Time.get_ticks_msec() / 1000.0, "k": k, "tries": 0})


func _jolt_all(pid: int, cost: float) -> void:
	if mtn._online():
		_jolt.rpc(pid, cost)
	else:
		_jolt(pid, cost)


@rpc("any_peer", "call_local", "reliable")
func _jolt(pid: int, cost: float) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or not d.is_local:
		return
	d.stamina = maxf(d.stamina - cost, 0.0)
	if d == Network.local_player:
		d.add_shake(0.3)
	if d.is_on_floor() and int(d.snow.climb) == 0:
		# рывок верёвки — к стене (туда, где друг)
		d.wind_shove(Vector3.FORWARD, 0.8)


func _yank_all(pid: int) -> void:
	if mtn._online():
		_yank.rpc(pid)
	else:
		_yank(pid)


## Сдёрнуло тем, кто сорвался в связке
@rpc("any_peer", "call_local", "reliable")
func _yank(pid: int) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or not d.is_local or int(d.snow.climb) != 3:
		return
	if d.snow.mpose == 12:
		return                       # вцепился — удержался
	var data: Dictionary = d.snow._cl_data
	_fall(d, int(data["k"]), float(data["x"]), float(data["y"]), true)


# ---------------------------------------------------------------------------
#  Хост: связка, подтягивание, лебёдка
# ---------------------------------------------------------------------------

func server(delta: float) -> void:
	_server_hazards(delta)
	# связка: двое у мотка
	var tiers: Array = mtn.holders("TIE")
	if tiers.size() >= 2 and not ties.has(tiers[0]) and not ties.has(tiers[1]):
		_tie_t += delta
		if _tie_t >= TIE_T:
			_tie_t = 0.0
			_set_tie_all(int(tiers[0]), int(tiers[1]), true)
	elif tiers.size() == 1 and ties.has(tiers[0]):
		# один держит E у мотка — развязаться
		_tie_t += delta
		if _tie_t >= TIE_T * 2.0:
			_tie_t = 0.0
			_set_tie_all(int(tiers[0]), partner(int(tiers[0])), false)
	else:
		_tie_t = 0.0
	for a in ties.keys():
		var da: Node3D = mtn.drone_by_id(int(a))
		var db: Node3D = mtn.drone_by_id(int(ties[a]))
		if da == null or db == null or da.is_dead or db.is_dead or da.global_position.distance_to(db.global_position) > 60.0:
			_set_tie_all(int(a), int(ties[a]), false)
			break
	_pull_server()
	_winch_server(delta)


func _set_tie_all(a: int, b: int, on: bool) -> void:
	if mtn._online():
		_set_tie.rpc(a, b, on)
	else:
		_set_tie(a, b, on)


@rpc("authority", "call_local", "reliable")
func _set_tie(a: int, b: int, on: bool) -> void:
	if on:
		ties[a] = b
		ties[b] = a
	else:
		ties.erase(a)
		ties.erase(b)
	var me = Network.local_player
	if me and (int(me.peer_id) == a or int(me.peer_id) == b):
		get_tree().call_group("level", "show_banner", "Вы в связке!" if on else "Связка развязана",
			"Сорвёшься — друг удержит, если держит E (у крюка или на стене)" if on else "")


## Подтянуть: наверху держат E у метки, снизу под гладким льдом — тот, кого тянут
func _pull_server() -> void:
	for pp in _pull_pts:
		var id: String = pp[2]
		if not mtn.is_active(id):
			continue
		var k: int = pp[0]
		var xp: float = pp[3]
		var band := _band_of(k)
		var y_need := M.pitch_top(k) - float(band[1]) - 1.5
		for d in get_tree().get_nodes_in_group("player"):
			if d.is_dead or int(d.snow.climb) != 3:
				continue
			if int(d.peer_id) == int(mtn.active[id]):
				continue
			var p: Vector3 = d.global_position
			if absf(p.z - (M.face_z(k) + WALL_OFF)) < 0.6 and absf(p.x - (M.BX + xp)) < 1.3 and p.y > y_need and p.y < M.pitch_top(k):
				if mtn._online():
					_pull_up.rpc(int(d.peer_id), k)
				else:
					_pull_up(int(d.peer_id), k)


@rpc("authority", "call_local", "reliable")
func _pull_up(pid: int, k: int) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or not d.is_local or int(d.snow.climb) != 3:
		return
	var xp := float(_pull_pts[0][3])
	for pp in _pull_pts:
		if int(pp[0]) == k:
			xp = float(pp[3])
	d.snow.end_scripted()
	d.snow.start_scripted(6, self, {"from": d.global_position, "to": Vector3(M.BX + xp, M.pitch_top(k) + 0.05, M.face_z(k) - 1.6), "k": k})
	if d == Network.local_player:
		get_tree().call_group("level", "show_banner", "Подтянули!", "")


func parcel_busy() -> bool:
	return basket_load


func _winch_server(delta: float) -> void:
	var parcel: Node = mtn.main_parcel
	var top_y := M.PEAK + 0.4
	# загрузка: посылку отпустили у корзины внизу
	if not basket_load and parcel != null and is_instance_valid(parcel) and not parcel.is_held and not parcel.is_delivered \
			and basket_y < M.FOOT_Y + 1.0:
		var pp: Vector3 = (parcel as Node3D).global_position
		if Vector2(pp.x - basket_low.x, pp.z - basket_low.z).length() < 1.5 and absf(pp.y - basket_low.y) < 1.5:
			basket_load = true
			(parcel as RigidBody3D).freeze = true
			_basket_sync_all(true)
	if basket_load and parcel != null and is_instance_valid(parcel) and parcel.is_held:
		basket_load = false              # схватили из корзины
		_basket_sync_all(true)
	basket_tag = mtn.is_active("TAG")
	if basket_load:
		var cranking: bool = mtn.is_active("WINCH")
		basket_stuck = false
		if cranking and basket_y < top_y:
			var ny := basket_y + HOIST_SPEED * delta
			for sy in M.SNAGS:
				if not basket_tag and basket_y <= float(sy) - 0.45 and ny > float(sy) - 0.45:
					ny = float(sy) - 0.45
					basket_stuck = true
			if not basket_tag:
				for sy2 in M.SNAGS:
					if absf(basket_y - (float(sy2) - 0.45)) < 0.01:
						basket_stuck = true
			basket_y = minf(ny, top_y)
		if basket_y >= top_y - 0.01:
			# наверху: посылку — на площадку у ворота
			basket_load = false
			var at := drum_pos + Vector3(1.8, 0.8, -1.6)
			var rb := parcel as RigidBody3D
			rb.global_position = at
			rb.linear_velocity = Vector3.ZERO
			rb.freeze = false
			mtn.set_parcel_last(at)
			_basket_sync_all(true)
			if mtn._online():
				_arrived.rpc()
			else:
				_arrived()
		elif parcel != null and is_instance_valid(parcel):
			(parcel as Node3D).global_position = _basket_world() + Vector3.UP * 0.35
	elif basket_y > M.FOOT_Y + 0.35:
		basket_y = maxf(basket_y - BASKET_DOWN * delta, M.FOOT_Y + 0.35)     # пустая — сама вниз
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.1
		_basket_sync_all(false)


func _basket_sync_all(reliable: bool) -> void:
	if not mtn._online():
		return
	if reliable:
		_basket_state_r.rpc(basket_y, basket_load, basket_stuck, basket_tag)
	else:
		_basket_state.rpc(basket_y, basket_load, basket_stuck, basket_tag)


@rpc("authority", "call_remote", "unreliable_ordered")
func _basket_state(y: float, load: bool, stuck: bool, tag: bool) -> void:
	basket_y = y
	basket_load = load
	basket_stuck = stuck
	basket_tag = tag


@rpc("authority", "call_remote", "reliable")
func _basket_state_r(y: float, load: bool, stuck: bool, tag: bool) -> void:
	_basket_state(y, load, stuck, tag)


@rpc("authority", "call_local", "reliable")
func _arrived() -> void:
	var me = Network.local_player
	if me and me.global_position.y > M.FOOT_Y - 10.0 and M.on_block(me.global_position):
		get_tree().call_group("level", "show_banner", "Посылка на вершине!", "Отнесите её в зелёный круг у станции")


func _basket_world() -> Vector3:
	var off := TAG_PULL if basket_tag and basket_y > M.FOOT_Y + 2.0 and basket_y < M.PEAK - 1.0 else 0.0
	return Vector3(M.HOIST.x, basket_y, M.HOIST.y + off)


# ---------------------------------------------------------------------------
#  Вид: корзина, тросы, верёвки связок
# ---------------------------------------------------------------------------

func visual(delta: float) -> void:
	_visual_hazards(delta)
	if _basket == null:
		return
	var target := _basket_world()
	_basket.position = _basket.position.lerp(target, clampf(delta * 8.0, 0.0, 1.0))
	if basket_stuck:
		_basket.position += Vector3(sin(mtn.now() * 23.0), 0.0, 0.0) * 0.03
	var parcel: Node = mtn.main_parcel
	if basket_load and parcel != null and is_instance_valid(parcel) and not multiplayer.is_server():
		(parcel as Node3D).global_position = _basket.position + Vector3.UP * 0.35
	# шаг 120: трос перерисовываю, только если корзина сдвинулась или оттяжку взяли/отпустили
	if _basket.position.distance_squared_to(_hoist_last) < 0.000001 and basket_tag == _hoist_tag:
		return
	_hoist_last = _basket.position
	_hoist_tag = basket_tag
	_hoist_im.clear_surfaces()
	_hoist_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var top := Vector3(M.HOIST.x, M.PEAK + 4.2, M.HOIST.y)
	for s in [-0.03, 0.0, 0.03]:
		_hoist_im.surface_add_vertex(top + Vector3(s, 0, 0))
		_hoist_im.surface_add_vertex(_basket.position + Vector3(s, 0.9, 0))
	for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
		_hoist_im.surface_add_vertex(_basket.position + Vector3(0, 0.9, 0))
		_hoist_im.surface_add_vertex(_basket.position + c + Vector3.UP * 0.45)
	# оттяжка: натянута, когда держат
	var tp := tag_pos + Vector3.UP * 1.0
	var bp := _basket.position + Vector3.UP * 0.2
	var prev := tp
	for i in range(1, 11):
		var tt := i / 10.0
		var sag := 0.0 if basket_tag else 2.5 * sin(PI * tt) * clampf((bp.y - tp.y) / 10.0, 0.2, 1.0)
		var q := tp.lerp(bp, tt) + Vector3.DOWN * sag
		_hoist_im.surface_add_vertex(prev)
		_hoist_im.surface_add_vertex(q)
		prev = q
	# верёвки связок
	var done := {}
	for a in ties:
		var b: int = ties[a]
		var key := "%d_%d" % [mini(int(a), b), maxi(int(a), b)]
		if done.has(key):
			continue
		done[key] = true
		var da: Node3D = mtn.drone_by_id(int(a))
		var db: Node3D = mtn.drone_by_id(b)
		if da == null or db == null:
			continue
		var pa := da.global_position + Vector3.UP * 0.9
		var pb := db.global_position + Vector3.UP * 0.9
		var slack := clampf(1.0 - pa.distance_to(pb) / ROPE_LEN, 0.0, 1.0) * 3.0
		var pr := pa
		for i2 in range(1, 13):
			var t2 := i2 / 12.0
			var q2 := pa.lerp(pb, t2) + Vector3.DOWN * slack * sin(PI * t2)
			_hoist_im.surface_add_vertex(pr)
			_hoist_im.surface_add_vertex(q2)
			pr = q2
	_hoist_im.surface_end()


# ---------------------------------------------------------------------------
#  Подсказки
# ---------------------------------------------------------------------------

func hint(me: Node3D) -> String:
	var p := me.global_position
	if me.has_meta("arrest") and int(me.snow.climb) == 0:
		var A0: Dictionary = me.get_meta("arrest")
		if Time.get_ticks_msec() / 1000.0 - float(A0["t"]) < 1.6 and int(A0["tries"]) < 2:
			return "ПАДАЕШЬ! ЛКМ / ПКМ — вбить ледоруб и зацепиться!"
	if not M.on_block(p) or p.y < M.FOOT_Y - 3.0:
		return ""
	var pid := int(me.peer_id)
	var climb := int(me.snow.climb)
	if climb == 3:
		var data: Dictionary = me.snow._cl_data
		var k: int = data["k"]
		var y: float = data["y"]
		var left := M.pitch_top(k) - (y + 1.9)
		if int(data.get("ride", -1)) >= 0:
			return "Едешь на ноге у друга (E — отпустить) · силы %d%%" % int(me.stamina)
		# шаг 123: срочное — сверху вниз по важности
		var sh := int(data.get("slip", -1))
		if sh >= 0:
			var blink := "▶▶ " if fmod(Time.get_ticks_msec() / 120.0, 2.0) < 1.0 else "      "
			return "%s%s ЛЕДОРУБ СКОЛЬЗИТ — ЖМИ %s! %s" % [blink, "ЛЕВЫЙ" if sh == 0 else "ПРАВЫЙ", "ЛКМ" if sh == 0 else "ПКМ", blink.strip_edges()]
		var g := gust_state()
		var hd: bool = bool(data.get("hold", false))
		if int(g.x) == 1:
			var left2 := ceili(GUST_WARN - _gust_in)
			if hd:
				return "Ветер поднимается — порыв через %d…  Держишься на двух ледорубах ✔ — не бей!" % left2
			return "Ветер поднимается — порыв через %d…  ВБЕЙ ОБА ЛЕДОРУБА (ЛКМ/ПКМ) и не бей!" % left2
		if int(g.x) == 2:
			return ("ПОРЫВ! Держишься ✔ — не отпускай" if hd else "ПОРЫВ! Ты не держишься — силы сдувает! Вбей оба ледоруба!")
		var axd: Array = data["ax"]
		if is_nan(float(axd[0])) != is_nan(float(axd[1])) and int(data["sw"]) < 0:
			return "Висишь на одном ледорубе — силы тают! Вбей второй (%s)" % ("ЛКМ" if is_nan(float(axd[0])) else "ПКМ")
		var ahead := ""
		if _in_slab(k, float(data["x"]), y + 2.6) or _in_slab(k, float(data["x"]), y + 3.4):
			ahead = "   ВЫШЕ ЛЁД — ледоруб будет ехать (или обойди A/D)"
		var lg := "   НА НОГЕ ВИСИТ ДРУГ — E: стряхнуть!" if leg_by.has(pid) else ""
		return "ЛКМ/ПКМ — выше · A/D — вбок · R — сбить лёд вниз · силы %d%% · до полки %d м · %d/%d%s%s" % [int(me.stamina), int(maxf(left, 0.0)), k + 1, M.PITCHES.size(), ahead, lg]
	if climb == 9:
		return ""
	if climb in [6, 7]:
		return ""
	var hp: String = mtn._hold_point_of(me)
	var holding: bool = me._held("interact")
	if hp == "TIE":
		if ties.has(pid):
			return "Вы в связке. Держи E подольше — развязаться"
		return "Связываетесь… нужен второй у мотка" if holding else "Держите E вдвоём у мотка — связаться верёвкой"
	if hp.begins_with("BEL"):
		if not ties.has(pid):
			return "Страховочный крюк: сначала свяжитесь у мотка верёвки на Плече"
		return "Страхуешь друга — держи, пока он лезет" if holding else "Держи E — страховать друга в связке"
	if hp.begins_with("PULL"):
		return "Лёг у края, тянешь руку — друг снизу подлезет к метке" if holding else "Держи E — лечь у края и подтянуть друга за руку"
	if hp == "WINCH":
		if not basket_load:
			return "Ворот лебёдки. Корзина пуста — посылку кладут в неё внизу, в кулуаре"
		if basket_stuck:
			return "Корзина зацепилась за карниз! Внизу кто-то должен держать оттяжку (E у столбика)"
		return "Крутишь ворот — посылка поднимается (%d м)" % int(M.PEAK - basket_y) if holding else "Держи E — крутить ворот"
	if hp == "TAG":
		return "Держишь оттяжку — корзина идёт мимо карнизов" if holding else "Держи E — оттянуть корзину от скалы (иначе зацепится за карнизы)"
	if night_block() and _start_cell(p) >= 0:
		return "В буран на стену нельзя — переждите в приюте"
	if me.held_parcel == mtn.main_parcel and mtn.main_parcel != null and M.on_foot(p):
		return "С посылкой на стену не залезть — положи её в корзину лебёдки (кулуар слева)"
	if rack_pos != Vector3.ZERO and p.distance_to(rack_pos) < 2.2:
		return "E — вернуть ледорубы на стойку" if bool(me.get("ice_axes")) else "E — взять ледорубы"
	if _start_cell(p) >= 0 and not bool(me.get("ice_axes")):
		return "Нужны ледорубы — стойка у подножия справа (E)"
	if M.on_foot(p) and not bool(me.get("ice_axes")) and me.held_parcel == null:
		return "Стена! Возьми ледорубы на стойке (справа, под фонарём) — и лезь вверх"
	if _start_cell(p) >= 0:
		return "ЛКМ/ПКМ у стены — вбить ледоруб и лезть. Силы: %d%% — отдохни перед участком" % int(me.stamina)
	if basket_load and absf(p.y - M.FOOT_Y) < 3.0 and basket_y < M.PEAK - 1.0:
		return "Посылка в корзине. Наверху крутят ворот, внизу — держи оттяжку (E у голубого столбика)"
	return ""


# ---------------------------------------------------------------------------
#  Боты
# ---------------------------------------------------------------------------

## Ввод бота на стене: [движение, держать E]
func bot_climb(bot: Node3D, owner_node: Node3D) -> Array:
	return [Vector2.ZERO, false]          # шаг 119: на ледорубах бот бьёт сам (в drive)
	var data: Dictionary = bot.snow._cl_data
	if int(bot.snow.climb) != 3 or data.is_empty():
		return [Vector2.ZERO, false]
	var pid := int(bot.peer_id)
	var k: int = data["k"]
	var x: float = data["x"]
	var y: float = data["y"]
	if mtn.weather and (mtn.weather.gust_warn() or mtn.gust_hard()):
		return [Vector2.ZERO, true]
	if bot.stamina < 18.0:
		_rest[pid] = true
	if bool(_rest.get(pid, false)):
		if bot.stamina > 70.0:
			_rest.erase(pid)
		else:
			return [Vector2.ZERO, true]
	# связан с хозяином, он внизу и далеко — жду
	if partner(pid) == int(owner_node.peer_id) and owner_node.global_position.y < y - 22.0:
		return [Vector2.ZERO, true]
	var tx := x
	var band := _band_of(k)
	if not band.is_empty():
		var bi := M.BANDS.find(band)
		tx = float(PULL_X[bi])
		if y > M.pitch_top(k) - float(band[1]) - 0.7 and absf(x - tx) < 0.5:
			return [Vector2.ZERO, true]            # под льдом у метки — жду, пока подтянут
	var mx := clampf((tx - x) * 2.0, -1.0, 1.0) if absf(tx - x) > 0.15 else 0.0
	return [Vector2(mx, -1.0), false]


func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	var b := bot.global_position
	var o := owner_node.global_position
	if not M.on_block(b) or b.y < M.FOOT_Y - 3.0:
		return Vector3.INF
	var bpid := int(bot.peer_id)
	var opid := int(owner_node.peer_id)
	if int(bot.snow.climb) != 0:
		return Vector3.INF
	# оттяжка: посылка в корзине, я внизу
	if basket_load and absf(b.y - M.FOOT_Y) < 3.0 and basket_y < M.PEAK - 1.0 and o.y > b.y + 5.0:
		return tag_pos
	# ворот: посылка в корзине, я наверху
	if basket_load and b.y > M.PEAK - 3.0:
		return winch_pos
	# подтянуть хозяина: он на стене под гладким льдом, я на полке над ним
	if int(owner_node.snow.climb) == 3:
		var od: Dictionary = owner_node.snow._cl_data
		for pp in _pull_pts:
			var k: int = pp[0]
			if int(od.get("k", -1)) == k and absf(b.y - M.pitch_top(k)) < 1.5 and b.z < M.face_z(k):
				return pp[1]
		# хозяин лезет — лезу следом (если я у стены)
		var k3 := _level_of(b)
		if k3 >= 0 and k3 < M.PITCHES.size() and owner_node.global_position.y > b.y + 2.0:
			return Vector3(M.BX + clampf(o.x - M.BX + 1.4, -M.FACE_W, M.FACE_W), M.pitch_base(k3), M.face_z(k3) + 0.4)
		return Vector3.INF
	# хозяин выше — лезу за ним (сначала отдохнув на полке)
	if o.y > b.y + 3.0 and float(bot.stamina) < 90.0:
		return Vector3.INF
	if o.y > b.y + 3.0 and not night_block():
		var k2 := _level_of(b)
		if k2 >= 0 and k2 < M.PITCHES.size():
			var tx := 0.0
			var band := _band_of(k2)
			if not band.is_empty():
				tx = float(PULL_X[M.BANDS.find(band)])
			return Vector3(M.BX + tx, M.pitch_base(k2), M.face_z(k2) + 0.4)
	return Vector3.INF


## На каком уровне стоит (0 — Плечо: следующий участок 0; k+1 — полка над участком k)
func _level_of(p: Vector3) -> int:
	if M.on_foot(p):
		return 0
	for k in M.PITCHES.size():
		if absf(p.y - M.pitch_top(k)) < 1.2 and p.z <= M.face_z(k) + 0.2:
			return k + 1
	return -1


func _nearest_bel(p: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for bp in _bel_pts:
		var q: Vector3 = bp[1]
		var dd := q.distance_to(p)
		if dd < bd and absf(q.y - p.y) < 2.0:
			bd = dd
			best = q
	return best


func bot_crank(bot: Node3D, owner_node: Node3D) -> bool:
	var t := bot_target(bot, owner_node)
	if t == Vector3.INF:
		return false
	var b := bot.global_position
	return Vector2(t.x - b.x, t.z - b.z).length() < 0.9 and absf(t.y - b.y) < 1.6
