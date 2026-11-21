extends Node3D
## Шаг 103: пропасть 66 м поперёк тропы (скальные стены с полками и наледью; не обойти) и СТАРЫЙ ПОДВЕСНОЙ МОСТ ~70 м.
## В настиле 7 дыр по 3 м. Переходят командой, у каждого своя роль:
##   * ЛЕБЁДКА у края (держи E) — натягивает мост. Отпустил — храповик проскальзывает, мост провисает (до 5.5 м),
##     по нему идут волны: крен, раскачка, подбрасывает. Пройти можно — перебежками между качками, приседая; ошибся — срыв;
##   * ПОРЫВЫ ВЕТРА: гул заранее, потом мост бросает вбок — присядь (Ctrl);
##   * СТРАХОВКА ОДНА: верёвка от КРЮКА у начала моста (E — пристегнуться; ЛКМ — забить крюк, до 5 ударов).
##     Кто на страховке — НОСИЛЬЩИК: только он берёт доски (E у штабеля — стопка на спину, 6 шт.) и только он
##     перелезает дыры по канатам (E у края дыры; ЛКМ/ПКМ по очереди — перехват; на порыве и крене — замри, иначе сорвёшься).
##     За дырой он кидает доски НАЗАД (Q) по одной тем, кто чинит;
##   * РЕМОНТНИКИ ловят доску (пустые руки, стоять у края дыры) и прибивают (ЛКМ): одна доска — полтора метра настила,
##     на дыру — две. Никто не поймал, порыв — доска в пропасть;
##   * двоим ближе 2 м друг к другу на мосту нельзя: доски трещат и ломаются под ногами;
##   * СОРВАЛСЯ на страховке — маятником назад, удар о стену (можно лишиться руки/ноги), висишь и раскачиваешься.
##     Руки слабеют: 15 с, если перехватываться (ЛКМ/ПКМ), иначе 6 с — потом срыв и гибель. Вытянет только напарник
##     (держит E у крюка). Длинный срыв вырывает плохо забитый крюк. Без страховки — сразу в пропасть;
##   * на той стороне E у столба — отстегнуться (верёвка уползёт назад к крюку). На мосту не прыгнуть и не бежать.

const M := preload("res://scenes/world/mountain_layout.gd")
const WOOD_TEX := "res://assets/bridge/wood_planks_diff_1k.jpg"
const WOOD_NRM := "res://assets/bridge/wood_planks_nor_gl_1k.jpg"
const GATE := preload("res://scenes/world/mountain_gate.gd")
const SFX := preload("res://scripts/sfx.gd")
const N := 140                     ## досок поперёк (по ~0.5 м)
const SPANS := 12                  ## пролётов — на каждом только один
const BREAK_T := 1.7
const DECK_HW := 0.86              ## полуширина настила
const RAIL_H := 1.05               ## высота перил
const RSEG := 24                   ## звеньев перил (коллизия)
## шаг 105: разрушенный участок посередине — 4 дыры по 3 м, между ними «островки» по 1.5 м
const GAPS := [[52, 58], [61, 67], [70, 76], [79, 85]]   ## дыры [от, до)
const SINGLES := [24, 38, 104, 118]                       ## выпавшие доски (перешагнуть)
const LAY_T := 1.7
const CARRY_T := 7.0               ## руки устают: секунд с досками на мосту
const CARRY_V := 2.4               ## с досками по мосту — не быстрее, м/с
const THROW_R := 21.0              ## бросок через разрушенный участок
const HANG_MAX := 70.0
const HAUL_V := 2.2                ## тянут страховку, м/с (двое — быстрее)
const STACK_MAX := 1               ## шаг 130: носильщик берёт по одной доске — в руки перед собой
const PILE_N := 15                 ## досок на том берегу: 12 нужно + 3 запасных
const BOARD_SLOTS := 2             ## одна доска закрывает столько старых (1 м)
const GRIP_T := 15.0               ## висишь на страховке: столько держат руки, если перехватываться
const GRIP_IDLE := 6.0             ## …и столько — если просто висеть
const WALL_CLEAR := 0.8            ## тело не ближе к стене (жёлоб под началом моста — гладкий)
const TRAV_STEP := 0.45            ## перехват по канату, м
const WALL_OUT := 1.7              ## стена пропасти вынесена от кромки рельефа на столько
const END_LEN := 3.6               ## концы настила (на каменных пятах) — прямые, не провисают
const NEAR_K := 3                  ## двое на мосту ближе стольких досок — ломается
const HOOK_MAX := 5
const SLIP := 0.07                 ## храповик лебёдки проскальзывает, ед./с

var mtn: Node
var is_open := false               ## для coop_gate: бот решает сам (bot_target)
var slots := PackedByteArray()     ## 0 — нет доски, 1 — старая, 2 — новая
var tension := 0.0
var phase := 0.0
var gust := 0.0                    ## порыв (0…1)
var gust_dir := 1.0
var carry := {}                    ## pid → в руках одна доска (ремонтник)
var stack_n := 0                   ## досок в стопке у носильщика
var stack_pid := -1                ## кто несёт стопку (берёт у штабеля на том берегу)
var pile_n := PILE_N               ## досок в штабеле
var lost_n := 0                    ## упало в пропасть
var line_spent := false            ## страховку уже использовали — она на том берегу
var line_pid := -1                 ## кто на страховке (−1 — свободна)
var hook_lv := HOOK_MAX            ## шаг 106: крюк забит намертво — страховка держит всегда
var hang := {}                     ## pid → длина верёвки (висит под началом моста)
var near_winch := Vector3.ZERO
var far_winch := Vector3.ZERO
var _wstand: Array = [Vector3.ZERO, Vector3.ZERO]   ## где стоять, крутя рукоять
var pile_pos := Vector3.ZERO
var hook_pos := Vector3.ZERO       ## крюк страховки
var clip_b := Vector3.ZERO         ## столб на той стороне (отстегнуться)
var _edge_p := Vector3.ZERO        ## кромка, через которую идёт верёвка при срыве
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _side := Vector3.RIGHT
var _th := Vector3.FORWARD
var _Lh := 70.0
var _L := 70.0
var _span_t := PackedFloat32Array()
var _span_snd := PackedFloat32Array()
var _sync_t := 0.0
var _clock := 0.0
var _gust_t := 12.0
var _gust_st := 0                  ## 0 тихо, 1 гул (скоро), 2 дует
var _gust_e := 0.0
var _fill := {}
var _slot_cs: Array[CollisionShape3D] = []
var _rail_cs: Array[CollisionShape3D] = []
var _dangles: Array = []
var _crank: Array[Node3D] = []
var _wood_old: Material
var _wood_new: Material
var _hemp: Material
var _line_mat: Material
var _bundles := {}
var _hammers := {}
var _flying: Array = []            ## [узел, откуда, куда, t, T, ловит pid]
var _land: Array = []              ## хост: [осталось, pid ловца, куда]
var _ter_n: Node = null
var _stam := {}                    ## pid → руки (1 — свежие)
var _line := {}                    ## верёвка страховки: P, O, mi
var _reel := 1.0                   ## 0…1: верёвка ползёт назад к крюку
var _reel_from := Vector3.ZERO
var _coil: Node3D                  ## бухта у крюка (страховка свободна)
var _waist := {}                   ## шаг 106: pid → обвязка (два витка верёвки на поясе) у того, кто на страховке
var _hang_k := {}                  ## pid → сколько уже висит (хост)
var _planks_mm: MultiMeshInstance3D
var _wood_mm: ShaderMaterial
var _rope_mm: Material
var _susp_mm: Material
var _seed: Array = []
var _fcache := {}                  ## t → рама (на кадр)
var _state_key := Vector4(-9, -9, -9, -9)
var _line_last := PackedVector3Array()
var _ver := 0
var _noise: FastNoiseLite
var _cliff_mat: ShaderMaterial
var _stack_node: Node3D
var _grip := {}                    ## pid → руки (1 — свежие), пока висит
var _deck_prev := {}               ## pid → [кадр, t, середина настила] — чтобы настил нёс стоящего
var _cp_set := {}
var _pile_boards: Array = []
var _pile_tag: Label3D
var _end_e := 0.05
var _pair_t := 0.0
var _pair_snd := 0.0
var _cs_ver := PackedInt32Array()
var _rl_ver := PackedInt32Array()


func _edge_u(sgn: float) -> float:
	return M.CHASM_U + sgn * (M.CHASM_W * 0.5) / M.len_per_u(M.CHASM_U)


# ---------------------------------------------------------------------------
#  Постройка
# ---------------------------------------------------------------------------

func build() -> void:
	add_to_group("part_sockets")
	var ua := _edge_u(-1.0)
	var ub := _edge_u(1.0)
	var rock: Material = mtn.rock_mat()
	var tc := M.tangent(M.CHASM_U)
	var oc := M.outward(M.CHASM_U)
	_noise = FastNoiseLite.new()
	_noise.seed = 7311
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	_cliff_mat = ShaderMaterial.new()
	_cliff_mat.shader = load("res://shaders/chasm_rock.gdshader")
	_cliff_mat.set_shader_parameter("top_y", M.height(M.CHASM_U))
	var ice_m := StandardMaterial3D.new()
	ice_m.albedo_color = Color(0.72, 0.87, 1.0, 0.82)
	ice_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_m.roughness = 0.08
	ice_m.metallic_specular = 0.9
	var floor_y := M.height(M.CHASM_U) - 72.0
	for sd in [[ua, -1.0], [ub, 1.0]]:
		var u: float = sd[0]
		var sg: float = sd[1]
		var t := M.tangent(u)
		var lat0 := -(M.half_in(u) + M.CHASM_IN)
		var lat1 := M.half_out(u) + M.CHASM_OUT
		var w := lat1 - lat0
		var mid_lat := (lat0 + lat1) * 0.5
		# шаг 106: вместо плит — «кромка»: полоса, которая повторяет рельеф поперёк (тропа, склоны) и уклон тропы
		# вдоль, от 2.4 м до края и до самой стены (WALL_OUT в пропасть). Прячет откос рельефа, ничего не торчит
		var lpu := M.len_per_u(u)
		var kk := (M.height(u - sg * 0.5 / lpu) - M.height(u + sg * 0.5 / lpu))
		var din := -t * sg
		din.y = 0.0
		din = din.normalized()
		var P0 := M.point(u) + M.outward(u) * lat0
		P0.y = M.height(u)
		P0 += din * WALL_OUT
		var hedge := _lip(u, din, kk, lat0, lat1)
		P0.y = float(hedge[0]) + kk * WALL_OUT - 0.04
		# под мостом верх стены ниже настила (настил на том берегу идёт вниз к пропасти)
		var e_a := ua - 1.6 / M.len_per_u(M.CHASM_U)
		var e_b := ub + 1.6 / M.len_per_u(M.CHASM_U)
		var tw := (1.6 + WALL_OUT) / 70.3
		var dy_w := lerpf(M.height(e_a), M.height(e_b), tw if sg < 0.0 else 1.0 - tw) + 0.05
		var tops := PackedFloat32Array()
		var ncol := int(ceil(w / 1.6))
		for ix in ncol + 1:
			var lx := lat0 + w * ix / ncol
			var tp := _lip_h(hedge, lat0, lat1, lx) + kk * WALL_OUT - 0.04
			if absf(lx - -1.0) < 2.0:
				tp = minf(tp, dy_w - 0.5)
			tops.append(tp)
		_cliff(P0, M.outward(u), w, -t * sg, tops, floor_y, 3 if sg < 0.0 else 8, -1.0 - lat0)
		# сосульки под кромкой
		var rng := RandomNumberGenerator.new()
		rng.seed = 7311 + int(sg)
		var imm := MultiMesh.new()
		imm.transform_format = MultiMesh.TRANSFORM_3D
		var cone := CylinderMesh.new()
		cone.top_radius = 0.5
		cone.bottom_radius = 0.0
		cone.height = 1.0
		cone.radial_segments = 5
		cone.rings = 1
		imm.mesh = cone
		imm.instance_count = 70
		for k in 70:
			var lt := rng.randf_range(2.0, w - 2.0)
			var ln := rng.randf_range(0.5, 2.4) * (1.6 if rng.randf() < 0.12 else 1.0)
			var dd := rng.randf_range(0.6, 2.2) if k % 3 else rng.randf_range(6.0, 9.0)
			var ip := P0 + M.outward(u) * lt + Vector3.DOWN * (dd + ln * 0.5) - t * sg * (_woff(lt, dd, 3 if sg < 0.0 else 8, -999.0) + 0.12)
			imm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(0.1 + ln * 0.07, ln, 0.1 + ln * 0.07)), ip))
		var imi := MultiMeshInstance3D.new()
		imi.multimesh = imm
		imi.material_override = ice_m
		imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(imi)
	# торец у горы: стена во весь склон
	var ca := M.point(ua) + M.outward(ua) * (-(M.half_in(ua) + M.CHASM_IN) + 1.9)
	var cb := M.point(ub) + M.outward(ub) * (-(M.half_in(ub) + M.CHASM_IN) + 1.9)
	ca.y = M.height(M.CHASM_U)
	cb.y = ca.y
	var eax := (cb - ca).normalized()
	var ew := ca.distance_to(cb)
	var tops := PackedFloat32Array()
	var enx := int(ceil(ew / 1.6))
	for ix in enx + 1:
		var sp := ca + eax * (ew * ix / enx) - oc * 4.0
		var g := M._ground_raw(sp.x, sp.z, 0.0, 0.0)
		tops.append(maxf(ca.y, g + 1.5) if not is_nan(g) else ca.y)
	_cliff(ca, eax, ew, oc, tops, floor_y, 15, -999.0)
	# дно: темнота и туман
	var deep := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(M.half_in(M.CHASM_U) + M.half_out(M.CHASM_U) + M.CHASM_IN + M.CHASM_OUT + 6.0, 0.2, M.CHASM_W + 2.0)
	deep.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.02, 0.04, 0.08)
	dmat.roughness = 1.0
	deep.material_override = dmat
	var dmid := (M.half_out(M.CHASM_U) + M.CHASM_OUT - M.half_in(M.CHASM_U) - M.CHASM_IN) * 0.5
	deep.transform = Transform3D(Basis(oc, Vector3.UP, -tc), M.point(M.CHASM_U) + oc * dmid + Vector3.DOWN * 75.6)
	# шаг 145: дно выреза — рельеф; тёмная плита лежит на нём и только над вырезом у тропы
	# (наружу склон ниже дна — там плита и туман висели бы в воздухе, их было видно снизу)
	var m_lat0 := -(M.half_in(M.CHASM_U) + M.CHASM_IN)
	var m_lat1 := M.half_out(M.CHASM_U) + 8.0
	var m_mid := (m_lat0 + m_lat1) * 0.5
	dm.size = Vector3(m_lat1 - m_lat0, 0.2, M.CHASM_W + 2.0)
	deep.transform = Transform3D(Basis(oc, Vector3.UP, -tc), M.point(M.CHASM_U) + oc * m_mid + Vector3.DOWN * 75.4)
	add_child(deep)
	var msh := load("res://shaders/abyss_mist.gdshader") as Shader
	if msh:
		for lv in [[-40.0, 0.22], [-47.0, 0.3], [-54.0, 0.4], [-61.0, 0.55], [-68.0, 0.8]]:
			var mist := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(m_lat1 - m_lat0, dm.size.z)
			mist.mesh = pm
			var mm2 := ShaderMaterial.new()
			mm2.shader = msh
			mm2.set_shader_parameter("mist_color", Color(0.34, 0.42, 0.55).lerp(Color(0.04, 0.06, 0.1), (-float(lv[0]) - 40.0) / 28.0))
			mm2.set_shader_parameter("density", float(lv[1]))
			mist.material_override = mm2
			mist.transform = Transform3D(Basis(oc, Vector3.UP, -tc), M.point(M.CHASM_U) + oc * m_mid + Vector3.UP * float(lv[0]))
			mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mist)
	# мост — ближе к скале; концы настила на полках (по 1.6 м за кромкой)
	var lat := -1.0
	var ea := ua - 1.6 / M.len_per_u(M.CHASM_U)
	var eb := ub + 1.6 / M.len_per_u(M.CHASM_U)
	_a = M.point(ea) + M.outward(ea) * lat
	_a.y = M.height(ea) + 0.05
	_b = M.point(eb) + M.outward(eb) * lat
	_b.y = M.height(eb) + 0.05
	_th = Vector3(_b.x - _a.x, 0.0, _b.z - _a.z)
	_Lh = _th.length()
	_th /= _Lh
	_L = _a.distance_to(_b)
	_end_e = END_LEN / _L
	_side = _th.cross(Vector3.UP).normalized()
	if _side.dot(oc) < 0.0:
		_side = -_side
	_edge_p = M.point(ua) + M.outward(ua) * lat
	_edge_p.y = M.height(ua)
	_edge_p += _th * WALL_OUT
	slots.resize(N)
	for k in N:
		slots[k] = 1
	for g in GAPS:
		for k2 in range(int(g[0]), int(g[1])):
			slots[k2] = 0
	for k3 in SINGLES:
		slots[k3] = 0
	for g2 in GAPS:
		slots[int(g2[0]) + 2] = 1           # шаг 106: посреди дыры уцелела одна доска — можно перепрыгнуть
	_span_t.resize(SPANS)
	_span_snd.resize(SPANS)
	_cs_ver.resize(N)
	_cs_ver.fill(-1)
	_rl_ver.resize(RSEG * 2)
	_rl_ver.fill(-1)
	_build_bridge()
	# порог-пандус перед настилом: с тропы на доски без ступеньки
	for e3 in [[0.0, -1.0], [1.0, 1.0]]:
		var fe := _frame(float(e3[0]))
		var dirv := _th * float(e3[1])
		var top_end := fe.origin + Vector3.UP * 0.0
		var g0 := 1e9
		for lxx in [-DECK_HW - 0.3, 0.0, DECK_HW + 0.3]:
			var q: Vector3 = fe.origin + dirv * 1.4 + _side * float(lxx)
			g0 = minf(g0, M.ground(q.x, q.z, 0.0, 0.0))
		var top_start := fe.origin + dirv * 1.4
		top_start.y = g0 - 0.03
		var zl2 := (top_end - top_start).normalized()
		var yl2 := zl2.cross(_side).normalized()
		if yl2.y < 0.0:
			yl2 = -yl2
		var xl2 := yl2.cross(zl2).normalized()
		var ln2 := top_start.distance_to(top_end) + 0.1
		_solid(Vector3(DECK_HW * 2.0 + 0.6, 0.5, ln2), Transform3D(Basis(xl2, yl2, zl2), (top_start + top_end) * 0.5 - yl2 * 0.25), _wood_old)
	# каменные пяты под прямыми концами настила: от края тропы до стены пропасти
	for e2 in [[-0.6 / _L, END_LEN / _L - 0.004], [1.0 - END_LEN / _L + 0.004, 1.0 + 0.6 / _L]]:
		var f0 := _frame(float(e2[0]))
		var f1 := _frame(float(e2[1]))
		var ax := f1.origin - f0.origin
		var zl := ax.normalized()
		var yl := zl.cross(_side).normalized()
		if yl.y < 0.0:
			yl = -yl
		var xl := yl.cross(zl).normalized()
		var hh := 1.6
		var org := (f0.origin + f1.origin) * 0.5 - yl * (0.2 + hh * 0.5)
		_solid(Vector3(DECK_HW * 2.0 + 0.24, hh, ax.length()), Transform3D(Basis(xl, yl, zl), org), mtn.rock_mat())
	var wu1 := ea - 1.4 / M.len_per_u(M.CHASM_U)
	var wu2 := eb + 1.4 / M.len_per_u(M.CHASM_U)
	near_winch = M.point(wu1) + M.outward(wu1) * (lat + DECK_HW + 1.7)
	near_winch.y = M.height(wu1)
	far_winch = M.point(wu2) + M.outward(wu2) * (lat + DECK_HW + 1.7)
	far_winch.y = M.height(wu2)
	_build_winch(near_winch, _th)
	_build_winch(far_winch, -_th)
	# шаг 106: держат лебёдку, стоя сбоку лицом к рукояти
	_wstand = [_crank_stand(0), _crank_stand(1)]
	mtn.add_hold("CHW", _wstand[0], 1.3)
	mtn.add_hold("CHW2", _wstand[1], 1.3)
	# шаг 105: доски — только на том берегу (штабель справа от схода с моста)
	var pu := eb + 4.5 / M.len_per_u(M.CHASM_U)
	pile_pos = M.point(pu) + M.outward(pu) * 1.6
	pile_pos.y = M.ground(pile_pos.x, pile_pos.z, 0.0, 0.0)
	_build_pile(pile_pos)
	var hu := ea - 1.3 / M.len_per_u(M.CHASM_U)
	hook_pos = M.point(hu) + M.outward(hu) * (lat - DECK_HW - 1.0)
	hook_pos.y = M.height(hu) + 0.45
	_build_hook(hook_pos)
	mtn.add_hold("CHA", hook_pos - _th * 0.7 + Vector3.DOWN * 0.45, 1.0)
	_tag(hook_pos + Vector3.UP * 1.6, "СТРАХОВКА — одна, на один переход\nE — пристегнуться", Color(1.0, 0.82, 0.3))
	_pile_tag = _tag(pile_pos + Vector3.UP * 1.6, "", Color(0.95, 0.75, 0.45))
	_tag(near_winch + Vector3.UP * 1.9, "ЛЕБЁДКА\nдержи E — натянуть мост", Color(0.7, 0.85, 1.0))
	_tag(far_winch + Vector3.UP * 1.9, "ЛЕБЁДКА\nдержи E — натянуть мост", Color(0.7, 0.85, 1.0))
	var cu2 := eb + 1.0 / M.len_per_u(M.CHASM_U)
	clip_b = M.point(cu2) + M.outward(cu2) * (lat - DECK_HW - 0.5)
	clip_b.y = M.height(cu2)
	_build_line()
	_update_pile()
	var su := ea - 8.0 / M.len_per_u(M.CHASM_U)
	mtn.sign_at(M.point(su) + M.outward(su) * 2.6, "СТАРЫЙ МОСТ — 70 м. Посередине настил разрушен!\nСтраховка ОДНА и на ОДИН переход (крюк справа, у скалы, E).\nВ дырах осталось по доске — пристёгнутый прыгает по ним\n(или лезет по канатам, E). Сорвётся — вытягивайте (E у крюка).\nна том берегу берёт доски (E) и кидает (Q) вам.\nЛовите и чините дыры (ЛКМ). Досок — с запасом в 3.\nЛебёдка (E) натягивает мост. Ветер — присядь.\nБлиже 2 м друг к другу — доски ломаются!", Color(1.0, 0.6, 0.3))
	GATE.make(self, M.point(M.CHASM_U))


## Насколько скала выступает в пропасть: x — вдоль стены, d — глубина от кромки. Слои-полки, выступы,
## книзу стены сходятся. chute — гладкий жёлоб под началом моста (там висят на страховке)
func _woff(x: float, d: float, sd: int, chute: float) -> float:
	var n1 := _noise.get_noise_2d(x * 0.06 + sd * 37.0, d * 0.08)
	var n2 := _noise.get_noise_2d(x * 0.21 + sd * 13.0 + 11.0, d * 0.25)
	var led := fposmod(d / 7.0 + n1 * 0.6, 1.0)
	var ledge := 0.9 * smoothstep(0.0, 0.12, led) * (1.0 - smoothstep(0.12, 0.9, led))
	var o := maxf(0.7 + 0.9 * n1 + 0.4 * n2 + ledge + d * 0.02, 0.08) * smoothstep(0.0, 2.2, d)
	if chute > -100.0:
		o = lerpf(o, 0.2 * smoothstep(0.0, 1.5, d), 1.0 - smoothstep(2.5, 5.5, absf(x - chute)))
	return o


## Скальная стена: P0 — верхний угол, ax — вдоль, nin — в пропасть; tops — высота верха по столбцам (пусто — ровно)
func _cliff(P0: Vector3, ax: Vector3, width: float, nin: Vector3, tops: PackedFloat32Array, bottom_y: float, sd: int, chute: float) -> void:
	if _ter_n == null:
		_ter_n = get_tree().get_first_node_in_group("terrain")
	var nx := int(ceil(width / 1.6))
	var ny := 46
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + sd
	var cols: Array = []
	for ix in nx + 1:
		var x := width * ix / nx
		var top := tops[ix] if tops.size() > ix else P0.y
		var bot_y := minf(bottom_y, top - 0.3)          # шаг 145: где склон ниже дна — стена не висит
		var cp := P0 + ax * x
		var gn := M._ground_raw(cp.x - nin.x * 3.0, cp.z - nin.z * 3.0, 0.0, 0.0)
		if _ter_n and not is_nan(gn):
			gn = minf(gn, float(_ter_n.height_at(cp.x - nin.x * 3.0, cp.z - nin.z * 3.0)))   # с вырезом пропасти с выступами
		# перед стеной — провал ниже дна (там витком ниже пропасть с выступами): снизу стена висела бы «лезвием»
		var gf: float = float(_ter_n.height_at(cp.x + nin.x * 3.0, cp.z + nin.z * 3.0)) if _ter_n else bottom_y
		if gf < bottom_y - 6.0:
			gn = -INF
		if not is_nan(gn) and gn < bottom_y + 2.0:
			bot_y = top - 0.3          # вырезать там нечего (склон и так ниже дна) — стены нет
		var col := PackedVector3Array()
		for iy in ny + 1:
			var v := float(iy) / ny
			v = v * (0.55 + 0.45 * v)                    # у кромки сетка гуще
			var d := (top - bot_y) * v
			var jit := Vector3.ZERO
			if iy > 0 and ix > 0 and ix < nx:
				jit = ax * rng.randf_range(-0.45, 0.45) + Vector3.UP * rng.randf_range(-0.35, 0.35)
			col.append(P0 + ax * x + Vector3.UP * (top - P0.y) + Vector3.DOWN * d + nin * _woff(x, d, sd, chute) + jit)
		cols.append(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for ix2 in nx:
		var c0: PackedVector3Array = cols[ix2]
		var c1: PackedVector3Array = cols[ix2 + 1]
		for iy2 in ny:
			var quad := [[c0[iy2], c1[iy2], c1[iy2 + 1]], [c0[iy2], c1[iy2 + 1], c0[iy2 + 1]]]
			if (ix2 + iy2) % 2 == 1:
				quad = [[c0[iy2], c1[iy2], c0[iy2 + 1]], [c1[iy2], c1[iy2 + 1], c0[iy2 + 1]]]
			for tri in quad:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c: Vector3 = tri[2]
				if (b - a).cross(c - a).dot(nin) > 0.0:
					var tmp := b
					b = c
					c = tmp
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(c)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cliff_mat
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	shp.backface_collision = true
	cs.shape = shp
	body.add_child(cs)
	add_child(body)


func _rope_shader(base: Color, tracer: Color, fleck: Color, strands: float, pitch: float, laid: float) -> Material:
	var rsh := load("res://shaders/rope_kern.gdshader") as Shader
	if rsh == null:
		return mtn.rope_mat()
	var sm := ShaderMaterial.new()
	sm.shader = rsh
	sm.set_shader_parameter("base_col", base)
	sm.set_shader_parameter("tracer_col", tracer)
	sm.set_shader_parameter("fleck_col", fleck)
	sm.set_shader_parameter("strands", strands)
	sm.set_shader_parameter("pitch", pitch)
	sm.set_shader_parameter("laid", laid)
	return sm


func _build_bridge() -> void:
	_wood_old = _plank_mat(Color(0.62, 0.58, 0.55), 0.93)    # шаг 132: фото-текстура досок
	_wood_new = _plank_mat(Color(1.2, 1.08, 0.95), 0.82)
	_hemp = _rope_shader(Color(0.56, 0.44, 0.28), Color(0.3, 0.22, 0.13), Color(0.6, 0.48, 0.3), 3.0, 9.0, 1.0)
	_line_mat = _rope_shader(Color(0.93, 0.33, 0.07), Color(0.05, 0.09, 0.26), Color(0.96, 0.86, 0.18), 16.0, 170.0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99099
	var pl := _L / N
	var aabb := _bridge_aabb()
	# шаг 102: доски — один MultiMesh, форма моста — в шейдере (процессор только сообщает провис/крен)
	_wood_mm = ShaderMaterial.new()
	_wood_mm.shader = load("res://shaders/bridge_wood.gdshader")
	_wood_mm.set_shader_parameter("half_w", DECK_HW)
	_wood_mm.set_shader_parameter("plank_len", pl)
	if ResourceLoader.exists(WOOD_TEX):
		_wood_mm.set_shader_parameter("wood_tex", load(WOOD_TEX))
		_wood_mm.set_shader_parameter("wood_nrm", load(WOOD_NRM))
		_wood_mm.set_shader_parameter("use_tex", 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = N
	for k in N:
		mm.set_instance_transform(k, Transform3D.IDENTITY)
		_seed.append(rng.randf() * 100.0)
	_planks_mm = MultiMeshInstance3D.new()
	_planks_mm.multimesh = mm
	_planks_mm.material_override = _wood_mm
	_planks_mm.custom_aabb = aabb
	add_child(_planks_mm)
	for k1 in N:
		_plank_custom(k1)
	var body := StaticBody3D.new()
	body.name = "OldBridge"
	add_child(body)
	for k2 in N:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(DECK_HW * 2.0, 0.14, pl + 0.03)
		cs.shape = bs
		body.add_child(cs)
		_slot_cs.append(cs)
	for sgi in 2:
		for j in RSEG:
			var rc := CollisionShape3D.new()
			var rb := BoxShape3D.new()
			rb.size = Vector3(0.14, 0.75, _L / RSEG + 0.05)
			rc.shape = rb
			body.add_child(rc)
			_rail_cs.append(rc)
	# канаты: 4 трубки одним мешем «в координатах моста»
	_rope_mm = _bridge_rope_mat(0)
	var ropes := MeshInstance3D.new()
	ropes.mesh = _static_ropes()
	ropes.material_override = _rope_mm
	ropes.custom_aabb = aabb
	add_child(ropes)
	# подвески — MultiMesh
	_susp_mm = _bridge_rope_mat(1)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.use_custom_data = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.013
	cyl.bottom_radius = 0.013
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	smm.mesh = cyl
	var cnt := (N / 4 + 1) * 2
	smm.instance_count = cnt
	var q := 0
	for k4 in range(0, N + 1, 4):
		for sg2 in [-1.0, 1.0]:
			smm.set_instance_transform(q, Transform3D.IDENTITY)
			smm.set_instance_custom_data(q, Color(float(k4) / N, sg2 * (DECK_HW + 0.06), 0.0, 0.0))
			q += 1
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = smm
	smi.material_override = _susp_mm
	smi.custom_aabb = aabb
	add_child(smi)
	for gi in GAPS.size():
		var g: Array = GAPS[gi]
		for j2 in 2:
			var dmi := MeshInstance3D.new()
			var db := BoxMesh.new()
			db.size = Vector3(rng.randf_range(0.5, 1.1), 0.06, pl * 0.8)
			dmi.mesh = db
			dmi.material_override = _wood_old
			add_child(dmi)
			var gk := float(int(g[0]) + (0 if j2 == 0 else int(g[1]) - int(g[0]) - 1))
			_dangles.append([dmi, gi, (gk + 0.5) / N, -1.0 if j2 == 0 else 1.0, rng.randf_range(1.0, 1.35)])
	# опоры: рамы из бруса с раскосами, канаты обмотаны вокруг стоек, каменные пяты
	var post_m := StandardMaterial3D.new()
	post_m.albedo_color = Color(0.27, 0.21, 0.16)
	post_m.roughness = 0.92
	for e in [[_a, -1.0], [_b, 1.0]]:
		var ep: Vector3 = e[0]
		var dir: float = e[1]
		var root := Node3D.new()
		add_child(root)
		root.global_transform = Transform3D(Basis(_side, Vector3.UP, _side.cross(Vector3.UP).normalized() * 1.0), ep + _th * dir * 0.55)
		var zs := signf(root.global_basis.z.dot(_th * dir))        # локальная ось «от моста»
		for sg3 in [-1.0, 1.0]:
			var x3: float = sg3 * (DECK_HW + 0.16)
			_box(root, post_m, Vector3(0.22, 3.0, 0.22), Vector3(x3, 1.3, 0.0), Vector3(0.0, 0.0, -sg3 * 0.05))
			_box(root, post_m, Vector3(0.14, 2.7, 0.14), Vector3(x3, 1.05, zs * 0.95), Vector3(-zs * 0.72, 0.0, 0.0))
			_box(root, mtn.rock_mat(), Vector3(0.75, 0.5, 0.8), Vector3(x3, 0.05, 0.0), Vector3(0.0, sg3 * 0.3, 0.0))
			_box(root, mtn.rock_mat(), Vector3(0.6, 0.4, 0.6), Vector3(x3 + sg3 * 0.1, 0.0, zs * 1.9), Vector3(0.0, 0.5, 0.0))
			for hy in [RAIL_H - 0.02, 0.06]:
				for qw in 3:
					var wr := MeshInstance3D.new()
					var tor := TorusMesh.new()
					tor.inner_radius = 0.135
					tor.outer_radius = 0.185
					tor.rings = 14
					tor.ring_segments = 6
					wr.mesh = tor
					wr.material_override = _hemp
					root.add_child(wr)
					wr.position = Vector3(x3, hy + qw * 0.045, 0.0)
		_box(root, post_m, Vector3(2.5, 0.2, 0.2), Vector3(0.0, 2.72, 0.0), Vector3.ZERO)


const LIP_STEP := 0.75
const LIP_BACK := 2.4


## Кромка пропасти у моста (шаг 106): высоты по рельефу в 3 м от края (там земля целая), вдоль — уклон тропы.
## Возвращает высоты «на самом краю» по столбцам поперёк — по ним же верх стены
func _lip(u: float, din: Vector3, kk: float, lat0: float, lat1: float) -> PackedFloat32Array:
	var n := int(ceil((lat1 - lat0) / LIP_STEP))
	var he := PackedFloat32Array()
	for i in n + 1:
		var lx := lat0 + (lat1 - lat0) * i / n
		var q := M.point(u) + M.outward(u) * lx - din * 3.2
		var g := M.ground(q.x, q.z, 0.0, 0.0)
		if is_nan(g):
			g = M.height(u) - kk * 3.2
		# шаг 145: по настоящему рельефу (витком ниже его вырезает пропасть с выступами — кромка висела «лезвием»)
		if _ter_n == null:
			_ter_n = get_tree().get_first_node_in_group("terrain")
		if _ter_n:
			g = minf(g, float(_ter_n.height_at(q.x, q.z)))
		he.append(g + kk * 3.2 - 0.02)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ds := [-LIP_BACK, 0.0, WALL_OUT]
	for i in n:
		var la := lat0 + (lat1 - lat0) * i / n
		var lb := lat0 + (lat1 - lat0) * (i + 1) / n
		var cut := absf((la + lb) * 0.5 + 1.0) < DECK_HW + 0.5
		for jj in 2:
			if cut and jj == 1:
				continue                    # под мостом — каменная пята
			var d0: float = ds[jj]
			var d1: float = ds[jj + 1]
			var a0 := _lip_p(u, din, la, d0, float(he[i]) + kk * d0)
			var b0 := _lip_p(u, din, lb, d0, float(he[i + 1]) + kk * d0)
			var a1 := _lip_p(u, din, la, d1, float(he[i]) + kk * d1)
			var b1 := _lip_p(u, din, lb, d1, float(he[i + 1]) + kk * d1)
			for v in [a0, a1, b1, a0, b1, b0]:
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v)
		# передний край кромки — вниз на 1.2 м (сливается со стеной)
		var f0 := _lip_p(u, din, la, WALL_OUT, float(he[i]) + kk * WALL_OUT)
		var f1 := _lip_p(u, din, lb, WALL_OUT, float(he[i + 1]) + kk * WALL_OUT)
		if not cut:
			for v2 in [f0, f1, f1 + Vector3.DOWN * 1.2, f0, f1 + Vector3.DOWN * 1.2, f0 + Vector3.DOWN * 1.2]:
				st.set_uv(Vector2(v2.x + v2.z, v2.y) * 0.25)
				st.add_vertex(v2)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cliff_mat
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := mesh.create_trimesh_shape()
	shp.backface_collision = true
	cs.shape = shp
	body.add_child(cs)
	add_child(body)
	return he


func _lip_p(u: float, din: Vector3, lx: float, d: float, y: float) -> Vector3:
	var q := M.point(u) + M.outward(u) * lx + din * d
	q.y = y
	return q


func _lip_h(he: PackedFloat32Array, lat0: float, lat1: float, lx: float) -> float:
	var n := he.size() - 1
	var f := clampf((lx - lat0) / (lat1 - lat0) * n, 0.0, float(n))
	var i := mini(int(f), n - 1)
	return lerpf(float(he[i]), float(he[i + 1]), f - i)


func _crank_stand(i: int) -> Vector3:
	var cr: Node3D = _crank[i]
	var xs: Vector3 = (cr.get_parent() as Node3D).global_basis.x.normalized()
	var p := cr.global_position + xs * 0.62
	var g := M.ground(p.x, p.z, 0.0, 0.0)
	p.y = g if not is_nan(g) else (cr.get_parent() as Node3D).global_position.y
	return p


## Сплошной блок: видно и можно стоять
func _solid(size: Vector3, xf: Transform3D, mat: Material) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	add_child(b)
	b.global_transform = xf


func _box(par: Node3D, mat: Material, size: Vector3, pos: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	par.add_child(mi)
	mi.position = pos
	mi.rotation = rot


func _bridge_aabb() -> AABB:
	var lo := Vector3(minf(_a.x, _b.x), minf(_a.y, _b.y), minf(_a.z, _b.z)) - Vector3(4.0, 10.0, 4.0)
	var hi := Vector3(maxf(_a.x, _b.x), maxf(_a.y, _b.y), maxf(_a.z, _b.z)) + Vector3(4.0, 3.0, 4.0)
	return AABB(lo, hi - lo)


func _bridge_rope_mat(mode: int) -> Material:
	var sh := load("res://shaders/bridge_rope.gdshader") as Shader
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("rail_h", RAIL_H)
	m.set_shader_parameter("base_col", Color(0.56, 0.44, 0.28))
	m.set_shader_parameter("tracer_col", Color(0.3, 0.22, 0.13))
	m.set_shader_parameter("fleck_col", Color(0.6, 0.48, 0.3))
	m.set_shader_parameter("strands", 3.0)
	m.set_shader_parameter("pitch", 9.0)
	m.set_shader_parameter("laid", 1.0)
	return m


## Четыре каната (перила и несущие) — трубки в координатах моста: x — поперёк, y — вверх, z — t (0…1)
func _static_ropes() -> ArrayMesh:
	var V := PackedVector3Array()
	var Nn := PackedVector3Array()
	var U := PackedVector2Array()
	var T := PackedFloat32Array()
	var I := PackedInt32Array()
	var sides := 10
	var rings := 97
	for r in [[-1.0, RAIL_H, 0.024], [1.0, RAIL_H, 0.024], [-1.0, -0.05, 0.032], [1.0, -0.05, 0.032]]:
		var base := V.size()
		var lx := float(r[0]) * (DECK_HW + 0.06)
		var hy := float(r[1])
		var rr := float(r[2])
		for i in rings:
			var t := float(i) / (rings - 1)
			for j in sides + 1:
				var ang := TAU * float(j) / sides
				V.append(Vector3(lx + cos(ang) * rr, hy + sin(ang) * rr, t))
				Nn.append(Vector3(cos(ang), sin(ang), 0.0))
				U.append(Vector2(float(j) / sides, t * _L))
				T.append_array([-sin(ang), cos(ang), 0.0, 1.0])
		for i2 in rings - 1:
			for j2 in sides:
				var a0 := base + i2 * (sides + 1) + j2
				var b0 := a0 + sides + 1
				I.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = Nn
	arr[Mesh.ARRAY_TANGENT] = T
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_INDEX] = I
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## Данные доски для шейдера: (t, состояние, укладка, зерно)
func _plank_custom(k: int) -> void:
	var fill := 1.0
	if _fill.has(k):
		fill = clampf(float(_fill[k]) / 0.15, 0.0, 1.0)
	_planks_mm.multimesh.set_instance_custom_data(k, Color((k + 0.5) / N, float(slots[k]), fill, float(_seed[k])))


## Рама с кэшем на кадр (для коллизии, опоры верёвки)
func _fr(t: float) -> Transform3D:
	var key := int(t * 4096.0)
	if _fcache.has(key):
		return _fcache[key]
	var f := _frame(t)
	_fcache[key] = f
	return f


## Крюк страховки: железный шлямбур в камне + кольцо; рядом молоток на камне
func _build_hook(at: Vector3) -> void:
	var met := StandardMaterial3D.new()
	met.albedo_color = Color(0.42, 0.43, 0.46)
	met.metallic = 0.85
	met.roughness = 0.35
	var stone := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.9, 0.7, 0.8)
	stone.mesh = sb
	stone.material_override = mtn.rock_mat()
	add_child(stone)
	stone.global_position = at + Vector3.DOWN * 0.3
	var pin := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.03
	pc.bottom_radius = 0.03
	pc.height = 0.3
	pin.mesh = pc
	pin.material_override = met
	add_child(pin)
	pin.global_position = at + Vector3.UP * 0.12
	pin.set_meta("hook_pin", true)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.05
	tor.outer_radius = 0.085
	ring.mesh = tor
	var ym := StandardMaterial3D.new()
	ym.albedo_color = Color(0.95, 0.78, 0.2)
	ym.metallic = 0.9
	ym.roughness = 0.3
	ym.emission_enabled = true
	ym.emission = Color(0.45, 0.32, 0.05)
	ring.material_override = ym
	add_child(ring)
	ring.global_position = at + Vector3.UP * 0.3
	ring.global_basis = Basis(_th, PI * 0.5)
	_hook_pin = pin
	# бухта верёвки (пока страховка свободна)
	_coil = Node3D.new()
	add_child(_coil)
	_coil.global_position = at + _th * -0.35 + Vector3.DOWN * 0.02
	for k in 4:
		var rr := MeshInstance3D.new()
		var tr := TorusMesh.new()
		tr.inner_radius = 0.2
		tr.outer_radius = 0.23
		tr.rings = 28
		tr.ring_segments = 6
		rr.mesh = tr
		rr.material_override = _line_mat
		_coil.add_child(rr)
		rr.position = Vector3(0.0, k * 0.026, 0.0)
		rr.rotation = Vector3(0.04 * sin(k * 2.1), k * 0.8, 0.04 * cos(k * 1.3))


var _hook_pin: MeshInstance3D


func _build_line() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	mi.material_override = _line_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	var P := PackedVector3Array()
	P.resize(40)
	for i in 40:
		P[i] = hook_pos
	_line = {"P": P, "O": P.duplicate(), "mi": mi}


func _build_winch(at: Vector3, face: Vector3) -> void:
	var met := StandardMaterial3D.new()
	met.albedo_color = Color(0.32, 0.34, 0.36)
	met.metallic = 0.7
	met.roughness = 0.45
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	var xs := _side
	var zs := -face
	if xs.cross(Vector3.UP).dot(zs) < 0.0:
		xs = -xs
	root.global_basis = Basis(xs, Vector3.UP, zs)
	for sx in [-0.45, 0.45]:
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.1, 1.0, 0.5)
		leg.mesh = lb
		leg.material_override = met
		root.add_child(leg)
		leg.position = Vector3(sx, 0.5, 0.0)
	var drum := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 0.2
	dc.bottom_radius = 0.2
	dc.height = 0.8
	drum.mesh = dc
	drum.material_override = _hemp
	root.add_child(drum)
	drum.position = Vector3(0.0, 0.85, 0.0)
	drum.rotation = Vector3(0.0, 0.0, PI * 0.5)
	var crank := Node3D.new()
	root.add_child(crank)
	crank.position = Vector3(0.52, 0.85, 0.0)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.05, 0.34, 0.06)
	arm.mesh = ab
	arm.material_override = met
	crank.add_child(arm)
	arm.position = Vector3(0.0, 0.15, 0.0)
	var grip := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.035
	gc.bottom_radius = 0.035
	gc.height = 0.22
	grip.mesh = gc
	grip.material_override = met
	crank.add_child(grip)
	grip.position = Vector3(0.1, 0.3, 0.0)
	grip.rotation = Vector3(0.0, 0.0, PI * 0.5)
	_crank.append(crank)
	var cab := MeshInstance3D.new()
	cab.mesh = ArrayMesh.new()
	cab.material_override = _hemp
	add_child(cab)
	var to := (_a if face.dot(_th) > 0.0 else _b) + _side * (DECK_HW + 0.12) + Vector3.UP * 0.9
	var fr := at + Vector3.UP * 0.85
	_tube(cab, PackedVector3Array([fr, (fr + to) * 0.5 + Vector3.DOWN * 0.08, to]), 0.016, 6)


func _tag(at: Vector3, text: String, col: Color) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 34
	lb.outline_size = 10
	lb.modulate = col
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.0045
	add_child(lb)
	lb.global_position = at
	return lb


## Штабель на том берегу: подкладки и PILE_N досок рядами; берут — доски исчезают сверху
func _build_pile(at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var yaw := atan2(_side.x, _side.z)
	for z in [-0.5, 0.5]:
		var sl := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.16, 0.16, 1.2)
		sl.mesh = sb
		sl.material_override = _wood_old
		add_child(sl)
		sl.global_position = at + _side * z + Vector3.UP * 0.08
		sl.global_basis = Basis(Vector3.UP, atan2(_th.x, _th.z))
	for k in PILE_N:
		var b := _board_mesh()
		add_child(b)
		var row := k % 2
		var lev := k / 2
		b.global_position = at + _th * (float(row) - 0.5) * 0.52 + Vector3.UP * (0.23 + lev * 0.078) + _side * rng.randf_range(-0.05, 0.05)
		b.global_basis = Basis(Vector3.UP, yaw + rng.randf_range(-0.04, 0.04))
		_pile_boards.append(b)


func _update_pile() -> void:
	for k in _pile_boards.size():
		(_pile_boards[k] as Node3D).visible = k < pile_n
	if _pile_tag:
		var need := _need()
		_pile_tag.text = "ДОСКИ: %d\nвсего осталось %d, на дыры нужно %d\nE — взять доску в руки" % [pile_n, boards_left(), need]


## Сколько досок ещё нужно на все дыры
func _need() -> int:
	var n := 0
	for g in GAPS:
		var holes := 0
		for k in range(int(g[0]), int(g[1])):
			if slots[k] == 0:
				holes += 1
		n += int(ceil(float(holes) / BOARD_SLOTS))
	return n


func boards_left() -> int:
	return pile_n + stack_n + carry.size()


## «Доска» — щит из двух свежих досок 1.5 м на двух поперечинах (закрывает две старых)
## Шаг 132: материал бруса/доски — фото-текстура (если ассета нет — простой цвет)
func _plank_mat(tint: Color, rough: float) -> Material:
	if ResourceLoader.exists(WOOD_TEX):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/plank_wood.gdshader")
		m.set_shader_parameter("wood_tex", load(WOOD_TEX))
		m.set_shader_parameter("wood_nrm", load(WOOD_NRM))
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("rough", rough)
		return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.36, 0.3, 0.24) if tint.r < 1.0 else Color(0.72, 0.55, 0.34)
	sm.roughness = rough
	return sm


func _board_mesh() -> Node3D:
	var root := Node3D.new()
	for x in [-0.12, 0.12]:
		var pm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.04, 1.5)
		pm.mesh = bm
		pm.material_override = _wood_new
		root.add_child(pm)
		pm.position = Vector3(x, 0.0, 0.0)
	for z in [-0.52, 0.52]:
		var cm := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.5, 0.035, 0.08)
		cm.mesh = cb
		cm.material_override = _wood_old
		root.add_child(cm)
		cm.position = Vector3(0.0, -0.036, z)
	return root


func _hammer_mesh() -> Node3D:
	var root := Node3D.new()
	var h := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.03, 0.03, 0.32)
	h.mesh = hb
	h.material_override = _wood_new
	root.add_child(h)
	h.position = Vector3(0.0, 0.0, -0.12)
	var head := MeshInstance3D.new()
	var hd := BoxMesh.new()
	hd.size = Vector3(0.05, 0.13, 0.05)
	head.mesh = hd
	var met := StandardMaterial3D.new()
	met.albedo_color = Color(0.3, 0.31, 0.33)
	met.metallic = 0.8
	met.roughness = 0.4
	head.material_override = met
	root.add_child(head)
	head.position = Vector3(0.0, 0.0, -0.27)
	return root


# ---------------------------------------------------------------------------
#  Геометрия моста: провис, раскачка, крен (натяжение + порыв)
# ---------------------------------------------------------------------------

func _sag() -> float:
	return lerpf(5.5, 0.7, tension) + 0.3 * gust


## Насколько мост «гуляет» без натяжения (0 — натянут)
func _wave() -> float:
	return pow(1.0 - tension, 1.5)


func _roll() -> float:
	return deg_to_rad(22.0) * _wave() * sin(phase) + deg_to_rad(17.0) * gust * gust_dir * (0.75 + 0.25 * sin(phase * 2.7))


## Крен в точке t: общий + бегущая по мосту волна (шаг 103)
func _roll_at(t: float) -> float:
	return (_roll() + deg_to_rad(15.0) * _wave() * sin(phase * 1.9 - t * 7.0)) * sin(PI * _u(t))


## Концы настила лежат на каменных пятах прямо; гнётся только пролёт между ними (шаг 105)
func _u(t: float) -> float:
	return clampf((t - _end_e) / (1.0 - 2.0 * _end_e), 0.0, 1.0)


func _sway() -> float:
	return 1.5 * _wave() * sin(phase + 0.7) + 0.7 * gust * gust_dir


func _frame(t: float) -> Transform3D:
	var S := _sag()
	var sx := _sway()
	var u := _u(t)
	var ins := 1.0 / (1.0 - 2.0 * _end_e) if (t > _end_e and t < 1.0 - _end_e) else 0.0
	var sw := sin(PI * u)
	var o := _a.lerp(_b, t) + Vector3.DOWN * S * 4.0 * u * (1.0 - u) + _side * sx * sw \
		+ Vector3.UP * 0.4 * _wave() * sin(phase * 1.3 - t * 9.0) * sw
	var tg := (_b - _a) + (Vector3.DOWN * S * 4.0 * (1.0 - 2.0 * u) + _side * sx * PI * cos(PI * u)) * ins
	tg = tg.normalized()
	var sd := (_side - tg * _side.dot(tg)).normalized()
	var up := tg.cross(sd)
	if up.y < 0.0:
		sd = -sd
		up = -up
	return Transform3D(Basis(sd, up, tg).rotated(tg, _roll_at(t)), o)


func _t_of(p: Vector3) -> float:
	return (Vector3(p.x - _a.x, 0.0, p.z - _a.z)).dot(_th) / _Lh


func _local(p: Vector3) -> Vector3:
	var t := _t_of(p)
	var f := _frame(clampf(t, 0.0, 1.0))
	var lp := f.affine_inverse() * p
	return Vector3(lp.x, lp.y, t)


func _slot_of(t: float) -> int:
	return clampi(int(floor(t * N)), 0, N - 1)


func _span_of(k: int) -> int:
	return clampi(k * SPANS / N, 0, SPANS - 1)


func on_deck(d: Node3D) -> bool:
	var l := _local(d.global_position)
	if l.z < 0.0 or l.z > 1.0 or absf(l.x) > DECK_HW + 0.15 or l.y < -0.35 or l.y > 0.9:
		return false
	# у самого края дыры стоишь на кромке соседней доски — это тоже «на мосту»
	var e := 0.3 / _L
	return slots[_slot_of(l.z)] > 0 or slots[_slot_of(l.z - e)] > 0 or slots[_slot_of(l.z + e)] > 0


func in_zone(p: Vector3) -> bool:
	# шаг 145: и по высоте — под мостом, витком ниже, пропасть с выступами (ледорубы): там мост не при чём
	# (раньше стоящего на выступе «роняло в пропасть моста» и переносило к мосту)
	if absf(p.y - M.height(M.CHASM_U)) > 60.0:
		return false
	var t := _t_of(p)
	return t > -0.15 and t < 1.15 and absf(_local(p).x) < 12.0


func _over_chasm(p: Vector3) -> bool:
	if absf(p.y - M.height(M.CHASM_U)) > 60.0:
		return false
	var along := (p - M.point(M.CHASM_U)).dot(M.tangent(M.CHASM_U))
	if absf(along) < M.CHASM_W * 0.5 + 0.3:
		return true
	if absf(along) > M.CHASM_W * 0.5 + 6.0:
		return false
	var g := M.ground(p.x, p.z, 0.0, 0.0)
	return not is_nan(g) and g < M.height(M.CHASM_U) - 30.0


func far_side(p: Vector3) -> bool:
	return (p - M.point(M.CHASM_U)).dot(M.tangent(M.CHASM_U)) > 0.0


func near(p: Vector3) -> bool:
	return p.distance_to(M.point(M.CHASM_U)) < 62.0


func repaired() -> bool:
	for g in GAPS:
		for k in range(int(g[0]), int(g[1])):
			if slots[k] == 0:
				return false
	return true


## Первая (от этого края) доска дыры, что ещё не заделана; −1 — все целы
func _frontier() -> int:
	for g in GAPS:
		for k in range(int(g[0]), int(g[1])):
			if slots[k] == 0:
				return k
	return -1


func hold_max() -> float:
	return 999.0


## Обвязка на поясе пристёгнутого: два плотных витка и узел спереди; появляется, когда обнёс верёвку вокруг пояса
func _update_waist() -> void:
	var want := -1
	if line_pid >= 0:
		var ld: Node3D = mtn.drone_by_id(line_pid)
		if ld != null and not (int(ld.snow.mpose) == 25 and float(ld.snow.mpose_k) < 0.55):
			want = line_pid
	for pid in _waist.keys():
		if int(pid) != want or not is_instance_valid(_waist[pid]):
			if is_instance_valid(_waist[pid]):
				(_waist[pid] as Node3D).queue_free()
			_waist.erase(pid)
	if want < 0 or _waist.has(want):
		return
	var d: Node3D = mtn.drone_by_id(want)
	var su = d.get("suit")
	var pel: Node3D = su.get("pelvis") if su != null else null
	var root := Node3D.new()
	if pel != null:
		pel.add_child(root)
		root.position = Vector3(0.0, 0.0, 0.0)
	else:
		(d.visual as Node3D).add_child(root)
		root.position = Vector3(0.0, 0.62, 0.0)
	for k in 2:
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.225
		tor.outer_radius = 0.252
		tor.rings = 36
		tor.ring_segments = 6
		ring.mesh = tor
		ring.material_override = _line_mat
		ring.position = Vector3(0.0, -0.01 + k * 0.03, 0.0)
		ring.rotation = Vector3(0.04 * (1 - 2 * k), k * 1.1, 0.0)
		ring.scale = Vector3(1.08, 1.0, 0.94)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
	var knot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.07
	knot.mesh = sm
	knot.material_override = _line_mat
	root.add_child(knot)
	knot.position = Vector3(0.0, 0.005, -0.235)
	_waist[want] = root


## Конец страховки на человеке: пока обвязывается — в кулаках (обносит вокруг пояса), потом — узел на поясе
func _line_end(d: Node3D) -> Vector3:
	var su = d.get("suit")
	if su != null and int(d.snow.mpose) == 25 and float(d.snow.mpose_k) < 0.8 and su.has_method("fist_pos"):
		return (su.fist_pos(0) + su.fist_pos(1)) * 0.5
	return _harness(d)


func _harness(d: Node3D) -> Vector3:
	var su = d.get("suit")
	if su != null and su.has_method("harness_point"):
		return su.harness_point()
	return d.global_position + Vector3.UP * 0.95


func _hands(d: Node3D) -> Vector3:
	var su = d.get("suit")
	if su != null and su.has_method("fist_pos"):
		return (su.fist_pos(0) + su.fist_pos(1)) * 0.5
	return d.global_position + Vector3.UP * 1.0 - (d.visual as Node3D).global_basis.z * 0.4


func _hands_free(d: Node3D) -> bool:
	return d.get("held_parcel") == null and d.get("held_friend") == null and d.get("held_limb") == null \
		and not carry.has(int(d.peer_id))


# ---------------------------------------------------------------------------
#  E: доски / страховка
# ---------------------------------------------------------------------------

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func try_socket(d: Node3D) -> bool:
	var p := d.global_position
	if not near(p) or d.snow.busy():
		return false
	var pid := int(d.peer_id)
	if _flat(p, pile_pos) < 2.0 and absf(p.y - pile_pos.y) < 2.0:
		if line_pid == pid:
			_say(d, "Сначала отойди от моста — страховка останется здесь")
			return true
		if stack_pid >= 0 and stack_pid != pid:
			_say(d, "Доски уже несёт напарник")
			return true
		if pile_n <= 0:
			_say(d, "Штабель пуст")
			return true
		if not _hands_free(d):
			return false
		if stack_n < STACK_MAX:
			_ask("_req_stack", [pid])
			SFX.play(self, pile_pos + Vector3.UP * 0.4, "thunk", -8.0, 1.2)
		return true
	if _flat(p, hook_pos) < 1.7 and absf(p.y - hook_pos.y) < 2.0:
		if line_pid == pid:
			_ask("_req_line", [pid, false, Vector3.ZERO])
			SFX.play(self, hook_pos, "click", -6.0, 0.8)
			return true
		if line_spent:
			_say(d, "Страховку уже использовали — она на том берегу. Дальше — только по починенному мосту (или без страховки, на свой страх и риск)")
			return true
		if line_pid >= 0:
			if hang.is_empty():
				var who: Node3D = mtn.drone_by_id(line_pid)
				_say(d, "Страховка одна — на ней %s" % (String(who.get("display_name")) if who and who.get("display_name") else "напарник"))
				return true
			return false
		d.snow.start_scripted(20, self, {"T": 3.4})
		return true
	if _flat(p, clip_b) < 1.7 and line_pid == pid:
		_ask("_req_line", [pid, false, _harness(d)])
		SFX.play(self, clip_b + Vector3.UP, "click", -6.0, 0.8)
		return true
	# у края дыры: перелезть по канатам (на страховке — сорвёшься и повиснешь; без неё — в пропасть)
	if on_deck(d):
		var gap := _gap_ahead(d)
		if gap.x >= 0:
			if carry.has(pid) or stack_pid == pid or not _hands_free(d):
				_say(d, "С досками по канатам не перелезть")
				return true
			if line_pid != pid:
				_say(d, "БЕЗ СТРАХОВКИ! Один срыв — и в пропасть. На порыве и крене не перехватывайся")
			var l := _local(p)
			d.snow.start_scripted(21, self, {"k0": gap.x, "k1": gap.y, "dir": _face_dir(d),
				"sgn": -1.0 if l.x <= 0.0 else 1.0, "s": 0.0, "tgt": 0.0, "hand": -1, "gt": -10.0, "p0": p})
			return true
	# шаг 142: E с доской в руках (не у дыры и не у штабеля) — кладу доску: она возвращается в штабель
	if (stack_pid == pid and stack_n > 0) or carry.has(pid):
		_ask("_req_putback", [pid, _hands(d)])
		SFX.play(self, _hands(d), "thunk", -8.0, 1.0)
		return true
	return false


@rpc("any_peer", "call_remote", "reliable")
func _req_putback(pid: int, from: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if stack_pid == pid and stack_n > 0:
		_rpc_all("_set_stack", [-1, 0, pile_n + stack_n, lost_n, 3])
	elif carry.has(pid):
		var c := carry.duplicate()
		c.erase(pid)
		_rpc_all("_set_carry", [c.keys(), -1])
		_rpc_all("_set_stack", [stack_pid, stack_n, pile_n + 1, lost_n, 3])
	else:
		return
	_rpc_all("_fly", [from, pile_pos + Vector3.UP * 0.3, -2, 0.6])


func _say(d: Node3D, msg: String) -> void:
	if d == Network.local_player:
		mtn.say(msg)


func _ask(fn: String, args: Array) -> void:
	if multiplayer.is_server():
		callv(fn, args)
	else:
		callv("rpc_id", [1, fn] + args)


func _rpc_all(fn: String, args: Array) -> void:
	if mtn._online():
		callv("rpc", [fn] + args)
	else:
		callv(fn, args)


@rpc("any_peer", "call_remote", "reliable")
func _req_carry(pid: int, on: bool) -> void:
	if not multiplayer.is_server():
		return
	var c := carry.duplicate()
	if on:
		c[pid] = true
	else:
		c.erase(pid)
	_rpc_all("_set_carry", [c.keys(), pid if on else -1])


@rpc("any_peer", "call_remote", "reliable")
func _req_stack(pid: int) -> void:
	if not multiplayer.is_server() or pid == line_pid or (stack_pid >= 0 and stack_pid != pid) or carry.has(pid):
		return
	var take := mini(STACK_MAX - (stack_n if stack_pid == pid else 0), pile_n)
	if take <= 0:
		return
	var have := stack_n if stack_pid == pid else 0
	_rpc_all("_set_stack", [pid, have + take, pile_n - take, lost_n, 1])


## why: 0 — бросил, 1 — взял, 2 — потерял (упал с ним)
@rpc("authority", "call_local", "reliable")
func _set_stack(pid: int, n: int, pile: int, lost: int, why: int) -> void:
	stack_pid = pid if n > 0 else -1
	stack_n = n if pid >= 0 else 0
	pile_n = pile
	lost_n = lost
	_update_pile()
	var me = Network.local_player
	var mp := int(me.peer_id) if me else -2
	if why == 1 and pid == mp:
		mtn.say("Доска в руках. Иди на мост к разрушенному участку, повернись к друзьям — Q: кинуть")
	elif why == 3 and me and near(me.global_position):
		mtn.say("Доску положили — она снова в штабеле (E — взять)")
	elif why == 2 and me and near(me.global_position):
		mtn.say("Доска упала в пропасть! Осталось досок: %d, нужно %d" % [boards_left(), _need()])


@rpc("any_peer", "call_remote", "reliable")
func _req_line(pid: int, on: bool, reel_from: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if on and line_pid < 0 and not line_spent:
		_rpc_all("_set_line", [pid, hook_lv, Vector3.ZERO])
	elif not on and line_pid == pid and not hang.has(pid):
		var d: Node3D = mtn.drone_by_id(pid)
		if d != null and far_side(d.global_position) and _t_of(d.global_position) > 0.9:
			_rpc_all("_spend_line", [pid])
		else:
			_rpc_all("_set_line", [-1, hook_lv, reel_from])


## Пристёгнутый перешёл: страховку отцепил на том берегу — больше её никто не возьмёт
@rpc("authority", "call_local", "reliable")
func _spend_line(pid: int) -> void:
	line_spent = true
	line_pid = -1
	_reel = 1.0
	if _coil:
		_coil.global_position = clip_b + Vector3.UP * 0.05
		_coil.visible = true
	SFX.play(self, clip_b + Vector3.UP, "click", -4.0, 0.8)
	var me = Network.local_player
	if me and near(me.global_position):
		if int(me.peer_id) == pid:
			mtn.say("Перешёл! Страховка осталась здесь. Бери доски у штабеля (E) и кидай друзьям (Q) через разрушенный участок")
		else:
			mtn.say("Напарник перешёл! Страховки больше нет. Ждите доски у разрушенного участка — ловите и чините (ЛКМ)")


@rpc("any_peer", "call_remote", "reliable")
func _req_hook(_pid: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_all("_set_line", [line_pid, mini(hook_lv + 1, HOOK_MAX), Vector3.ZERO])


@rpc("any_peer", "call_remote", "reliable")
func _req_fill(pid: int, k0: int, k1: int) -> void:
	if not multiplayer.is_server() or not carry.has(pid):
		return
	var s2 := slots.duplicate()
	for k in range(maxi(k0, 0), mini(k1, N)):
		if s2[k] == 0:
			s2[k] = 2
	var c := carry.duplicate()
	c.erase(pid)
	_rpc_all("_set_slots", [s2, k0, k1, 0])
	_rpc_all("_set_carry", [c.keys(), -1])


## Бросок доски. Носильщик кидает из стопки НАЗАД (ловит тот, кто ближе к началу моста); ремонтник может
## перебросить свою доску любому перед собой. Ловят с пустыми руками, до 10 м; порыв уносит доску
@rpc("any_peer", "call_remote", "reliable")
func _req_throw(pid: int, from: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var carrier := pid == stack_pid and stack_n > 0 and not carry.has(pid)
	if not carrier and not carry.has(pid):
		return
	var td: Node3D = mtn.drone_by_id(pid)
	var tt := _t_of(td.global_position) if td else 0.0
	var best: Node3D = null
	var bs := 99.0
	for o in get_tree().get_nodes_in_group("player"):
		var od := o as Node3D
		if int(od.peer_id) == pid or bool(od.get("is_dead")) or od.snow.busy() or not _hands_free(od) or int(od.peer_id) == stack_pid:
			continue
		if carrier and _t_of(od.global_position) > tt - 1.0 / _Lh:
			continue
		var to := od.global_position + Vector3.UP * 1.0 - from
		var fl := Vector3(to.x, 0.0, to.z)
		if fl.length() > THROW_R or fl.length() < 1.5 or absf(to.y) > 7.0:
			continue
		if fl.normalized().dot(dir) < 0.5:
			continue
		var sc := fl.length()
		if sc < bs:
			bs = sc
			best = od
	# промах: чем дальше и сильнее ветер — тем вероятнее
	var miss := clampf((bs - 10.0) / 60.0, 0.0, 0.12) + gust * 0.7
	var dest := from + dir * 9.0 + Vector3.DOWN * 0.6
	var cp := -1
	var T := 0.75
	if best != null:
		dest = best.global_position + Vector3.UP * 1.0
		T = 0.55 + bs * 0.045
		if randf() >= miss:
			cp = int(best.peer_id)
		else:
			var off := _side * (1.6 + randf() * 1.5) * (gust_dir if gust > 0.1 else (1.0 if randf() < 0.5 else -1.0))
			dest += off + _th * randf_range(-0.8, 0.8)
	var lost := lost_n + (1 if cp < 0 else 0)
	if carrier:
		_rpc_all("_set_stack", [stack_pid, stack_n - 1, pile_n, lost, 0])
	else:
		lost_n = lost
		var c := carry.duplicate()
		c.erase(pid)
		_rpc_all("_set_carry", [c.keys(), -1])
	_rpc_all("_fly", [from, dest, cp, T])
	if cp >= 0:
		_land.append([T, cp, dest])


@rpc("any_peer", "call_remote", "reliable")
func _req_drop(pid: int, at: Vector3) -> void:
	if not multiplayer.is_server() or not carry.has(pid):
		return
	var c := carry.duplicate()
	c.erase(pid)
	_rpc_all("_set_carry", [c.keys(), -1])
	_rpc_all("_set_stack", [stack_pid, stack_n, pile_n, lost_n + 1, 0])
	_rpc_all("_fly", [at, at + Vector3.DOWN * 0.8 + _side * 0.6, -1, 0.75])


## Сорвался на страховке: крюк держит, если срыв не длиннее, чем он забит; иначе — вырвало
@rpc("any_peer", "call_remote", "reliable")
func _req_fall(pid: int, dist: float, R: float) -> void:
	if not multiplayer.is_server() or line_pid != pid:
		return
	hang[pid] = minf(R, HANG_MAX)
	_hang_k[pid] = 0.0
	_rpc_all("_set_line", [pid, hook_lv, Vector3.ZERO])
	_sync_hang()


@rpc("authority", "call_local", "reliable")
func _set_carry(keys: Array, got: int) -> void:
	carry.clear()
	for k in keys:
		carry[int(k)] = true
	if got >= 0:
		var me = Network.local_player
		if me and int(me.peer_id) == got:
			mtn.say("Поймал доску! К краю дыры, лицом к ней — ЛКМ: прибить")


@rpc("authority", "call_local", "reliable")
func _set_line(pid: int, lv: int, reel_from: Vector3) -> void:
	var was := line_pid
	line_pid = pid
	var up := lv > hook_lv
	hook_lv = lv
	var me = Network.local_player
	var mp := int(me.peer_id) if me else -2
	if was >= 0 and pid < 0:
		var wd: Node3D = mtn.drone_by_id(was)
		_reel = 0.0
		_reel_from = reel_from if reel_from != Vector3.ZERO else (_harness(wd) if wd else hook_pos)
	if pid == mp and was != mp:
		mtn.say("На страховке! Посреди дыр осталось по доске — перепрыгивай (Пробел) или лезь по канатам (E у края). Сорвёшься — повиснешь, напарник вытянет")
	elif was == mp and pid != mp and pid < 0 and me and near(me.global_position) and not me.is_dead:
		mtn.say("Отстегнулся. Верёвка уползает к крюку")
	if up and me and _flat(me.global_position, hook_pos) < 4.0:
		mtn.say("Крюк забит: %d из %d — выдержит срыв до %d м" % [hook_lv, HOOK_MAX, int(hold_max())])


@rpc("authority", "call_local", "reliable")
func _set_slots(arr: PackedByteArray, k0: int, k1: int, why: int) -> void:
	for k in N:
		if arr[k] == 2 and slots[k] != 2:
			_fill[k] = -0.06 * float(k - k0)
	slots = arr
	if _planks_mm:
		for k2 in N:
			_plank_custom(k2)
		_ver += 1                                  # коллизию — пересобрать
	var mid := _frame((float(k0 + k1) * 0.5) / N).origin
	var me = Network.local_player
	if why == 0:
		if me and near(me.global_position):
			var open_more := (k1 < N and slots[k1] == 0) or (k0 > 0 and slots[k0 - 1] == 0)
			mtn.say("Мост починен! Держите дистанцию — не ближе 2 м" if repaired() else ("Доска прибита — в эту дыру ещё одну!" if open_more else "Дыра закрыта! Носильщик — к следующей"))
	else:
		SFX.play(self, mid, "crunch", 0.0, 0.6)
		SFX.play(self, mid, "creak", -2.0, 0.6)


@rpc("authority", "call_local", "reliable")
func _set_hang(arr: Array) -> void:
	hang.clear()
	for e in arr:
		hang[int(e[0])] = float(e[1])


func _sync_hang() -> void:
	var arr: Array = []
	for k in hang:
		arr.append([int(k), float(hang[k])])
	_rpc_all("_set_hang", [arr])


@rpc("authority", "call_remote", "unreliable_ordered")
func _st(t: float, ph: float, g: float, gd: float, hg: Array) -> void:
	tension = t
	phase = ph
	gust = g
	gust_dir = gd
	for e in hg:
		hang[int(e[0])] = float(e[1])


@rpc("authority", "call_local", "reliable")
func _fly(from: Vector3, to: Vector3, cp: int, T: float) -> void:
	var n := _board_mesh()
	add_child(n)
	n.global_position = from
	_flying.append([n, from, to, 0.0, T, cp, Vector3.ZERO])
	if cp == -1:
		var me = Network.local_player
		if me and near(me.global_position):
			mtn.say("Доску унесло в пропасть! Осталось досок: %d, нужно %d" % [boards_left(), _need()])
	SFX.play(self, from, "swish", -6.0, 0.7)


@rpc("authority", "call_local", "reliable")
func _hook_rip(pid: int) -> void:
	SFX.play(self, hook_pos, "clank", 0.0, 0.6)
	SFX.play(self, hook_pos, "crunch", -2.0, 1.2)
	var d: Node3D = mtn.drone_by_id(pid)
	if d != null and d.is_local and d.snow.busy() and int(d.snow.climb) == 16:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.velocity = Vector3.DOWN * 4.0
	var me = Network.local_player
	if me and near(me.global_position):
		mtn.say("КРЮК ВЫРВАЛО! Плохо забит — не выдержал рывка")


@rpc("authority", "call_local", "reliable")
func _hauled(pid: int) -> void:
	hang.erase(pid)
	var d: Node3D = mtn.drone_by_id(pid)
	if d != null and d.is_local and d.snow.busy() and int(d.snow.climb) == 16:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.global_position = hook_pos - _th * 1.2 + _side * 0.8 + Vector3.UP * 0.2
		d.velocity = Vector3.ZERO
		SFX.play(self, d.global_position, "thunk", -6.0, 1.0)
		_say(d, "Вытянули! Начинай переход заново")


@rpc("authority", "call_local", "unreliable")
func _gust_warn(gd: float) -> void:
	var c := _frame(0.5).origin
	SFX.play(self, c + _side * gd * -8.0, "gust", 2.0, 0.9)
	var me = Network.local_player
	if me and in_zone(me.global_position):
		mtn.say("Ветер! Сейчас ударит порыв — присядь (Ctrl)!")


@rpc("authority", "call_local", "unreliable")
func _creak(k: int) -> void:
	var at := _frame((k + 0.5) / N).origin
	SFX.play(self, at, "creak", -2.0, randf_range(0.9, 1.2))
	SFX.play(self, at, "crunch", -8.0, randf_range(1.4, 1.8))
	var me = Network.local_player
	if me and on_deck(me) and absi(_slot_of(_local(me.global_position).z) - k) <= NEAR_K + 1:
		me.add_shake(0.25)
		mtn.say("Доски трещат! Разойдитесь — не ближе 2 м!")


# ---------------------------------------------------------------------------
#  Хост
# ---------------------------------------------------------------------------

func server(delta: float) -> void:
	var held: bool = not mtn.holders("CHW").is_empty() or not mtn.holders("CHW2").is_empty()
	tension = clampf(tension + (0.5 if held else -SLIP) * delta, 0.0, 1.0)
	phase = fposmod(phase + TAU / 3.6 * delta, TAU * 100.0)
	# порывы: гул → удар → стихает
	_gust_t -= delta
	match _gust_st:
		0:
			if _gust_t <= 0.0 and _anyone_near():
				_gust_st = 1
				_gust_t = 2.0
				gust_dir = -1.0 if randf() < 0.5 else 1.0
				_rpc_all("_gust_warn", [gust_dir])
			elif _gust_t <= 0.0:
				_gust_t = 3.0
		1:
			if _gust_t <= 0.0:
				_gust_st = 2
				_gust_e = 0.0
		2:
			_gust_e += delta
			gust = clampf(_gust_e / 0.6, 0.0, 1.0) if _gust_e < 2.8 else clampf(1.0 - (_gust_e - 2.8) / 0.9, 0.0, 1.0)
			if _gust_e > 3.7:
				gust = 0.0
				_gust_st = 0
				_gust_t = randf_range(10.0, 17.0)
	# страховка: вытягивают
	var haul: int = mtn.holders("CHA").size()
	var ch_hang := false
	for pid in hang.keys():
		_hang_k[pid] = float(_hang_k.get(pid, 0.0)) + delta
		var hd: Node3D = mtn.drone_by_id(int(pid))
		if hd == null or bool(hd.get("is_dead")):
			hang.erase(pid)
			ch_hang = true
			continue
		if haul > 0 and float(_hang_k[pid]) > 1.6:
			hang[pid] = float(hang[pid]) - HAUL_V * (1.0 if haul == 1 else 1.7) * delta
			if float(hang[pid]) <= 1.0:
				hang.erase(pid)
				_rpc_all("_hauled", [int(pid)])
				_rpc_all("_set_line", [line_pid, hook_lv, Vector3.ZERO])
				ch_hang = true
	if ch_hang:
		_sync_hang()
	_sync_t -= delta
	if _sync_t <= 0.0 and mtn._online():
		_sync_t = 0.1
		var hg: Array = []
		for k in hang:
			hg.append([int(k), float(hang[k])])
		_st.rpc(tension, phase, gust, gust_dir, hg)
	# пойманные связки
	for i in range(_land.size() - 1, -1, -1):
		var e: Array = _land[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) <= 0.0:
			_land.remove_at(i)
			var cd: Node3D = mtn.drone_by_id(int(e[1]))
			if cd != null and not bool(cd.get("is_dead")) and _hands_free(cd) and (cd.global_position + Vector3.UP).distance_to(e[2]) < 2.6:
				var c := carry.duplicate()
				c[int(e[1])] = true
				_rpc_all("_set_carry", [c.keys(), int(e[1])])
	# погибшие / ушедшие
	var cr2 := carry.duplicate()
	var ch_carry := false
	var on_d: Array = []
	for d in get_tree().get_nodes_in_group("player"):
		var dd := d as Node3D
		var pid2 := int(dd.peer_id)
		var dead := bool(dd.get("is_dead"))
		if cr2.has(pid2) and (dead or not near(dd.global_position)):
			cr2.erase(pid2)
			ch_carry = true
		if pid2 == line_pid and not hang.has(pid2) and (dead or not near(dd.global_position)):
			_rpc_all("_set_line", [-1, hook_lv, _harness(dd)])
		elif pid2 == line_pid and not dead and not dd.snow.busy() and far_side(dd.global_position) and _t_of(dd.global_position) > 1.0 + 1.2 / _Lh:
			_rpc_all("_spend_line", [pid2])         # сошёл с моста на том берегу — страховка отцеплена
		if pid2 == stack_pid and stack_n > 0 and (dead or not near(dd.global_position)):
			_rpc_all("_set_stack", [-1, 0, pile_n, lost_n + stack_n, 2])
		if not dead and not dd.snow.busy() and on_deck(dd):
			on_d.append(_slot_of(_local(dd.global_position).z))
	if ch_carry:
		_rpc_all("_set_carry", [cr2.keys(), -1])
	# двое ближе 2 м: трещит → ломается под обоими
	var pair := Vector2i(-1, -1)
	for i3 in on_d.size():
		for j3 in range(i3 + 1, on_d.size()):
			if absi(int(on_d[i3]) - int(on_d[j3])) <= NEAR_K:
				pair = Vector2i(int(on_d[i3]), int(on_d[j3]))
	if pair.x >= 0:
		_pair_t += delta
		_pair_snd -= delta
		if _pair_t > 0.15 and _pair_snd <= 0.0:
			_pair_snd = 0.45
			_rpc_all("_creak", [(pair.x + pair.y) / 2])
		if _pair_t >= BREAK_T:
			_pair_t = 0.0
			var s2 := slots.duplicate()
			var lo := maxi(mini(pair.x, pair.y) - 1, 0)
			var hi := mini(maxi(pair.x, pair.y) + 2, N)
			for kk in range(lo, hi):
				s2[kk] = 0
			_rpc_all("_set_slots", [s2, lo, hi, 1])
	else:
		_pair_t = maxf(_pair_t - delta * 2.0, 0.0)


func _anyone_near() -> bool:
	for d in get_tree().get_nodes_in_group("player"):
		if in_zone((d as Node3D).global_position):
			return true
	return false


# ---------------------------------------------------------------------------
#  Свои дроны
# ---------------------------------------------------------------------------

func local(d: Node3D, hp: String, _holding: bool, delta: float) -> void:
	var p := d.global_position
	if not near(p) and not in_zone(p):
		d.set("no_jump", false)
		d.set("no_sprint", false)
		return
	var pid := int(d.peer_id)
	var bot := bool(d.get("is_bot"))
	if hp == "CHW" or hp == "CHW2":
		# шаг 106: стою сбоку от лебёдки лицом к рукояти, обе руки на ней — кручу
		var cr: Node3D = _crank[0 if hp == "CHW" else 1]
		var xs: Vector3 = (cr.get_parent() as Node3D).global_basis.x.normalized()
		var stand: Vector3 = _wstand[0 if hp == "CHW" else 1]
		stand.y = d.global_position.y
		d.global_position = d.global_position.lerp(stand, clampf(delta * 6.0, 0.0, 1.0))
		d.velocity = Vector3.ZERO
		var g26: Vector3 = cr.global_transform * Vector3(0.1, 0.3, 0.0)
		var ang: float = fposmod(-cr.rotation.x / TAU, 1.0)
		d.snow.set_mpose(26, ang, g26, xs)
		d.visual.rotation.y = atan2(xs.x, xs.z)
		d.set("no_jump", false)
		d.set("no_sprint", false)
		return
	if hp == "CHA":
		# тяну страховку: перехват за перехватом, корпус назад
		var fc2 := _th
		d.visual.rotation.y = atan2(-fc2.x, -fc2.z)
		d.snow.set_mpose(10, fposmod(_clock * 1.4, 1.0), _edge_p + Vector3.DOWN * 2.0, fc2 + Vector3.DOWN * 0.8)
		if fposmod(_clock, 0.7) < delta:
			SFX.play(self, hook_pos, "rope", -8.0, 1.2)
		return
	if int(d.snow.mpose) in [9, 10] and hp == "":
		d.snow.set_mpose(0)
	var carrying := carry.has(pid)
	var carrier := stack_pid == pid and stack_n > 0
	var deck := on_deck(d)
	d.set("no_jump", false)               # шаг 106: прыгать по уцелевшим доскам можно, бежать — нет
	d.set("no_sprint", deck)
	var l := _local(p)
	if carrying or carrier:
		d.snow.set_mpose(23, 0.0, Vector3.ZERO, Vector3.FORWARD, true)
	elif int(d.snow.mpose) == 23:
		d.snow.set_mpose(0)
	if (carrying or carrier) and not bot and d._just("throw") and not d._can_throw():
		var fw := -(d.visual as Node3D).global_basis.z
		fw.y = 0.0
		d.snow.start_scripted(18, self, {"dir": fw.normalized()})
		return
	if deck:
		# настил уходит вбок вместе с раскачкой — несёт стоящего с собой
		var f := _frame(clampf(l.z, 0.0, 1.0))
		var pv: Array = _deck_prev.get(pid, [])
		if pv.size() == 3 and int(pv[0]) == Engine.get_physics_frames() - 1 and absf(float(pv[1]) - l.z) < 0.004:
			var mv: Vector3 = _frame(clampf(float(pv[1]), 0.0, 1.0)).origin - (pv[2] as Vector3)
			d.global_position += Vector3(mv.x, 0.0, mv.z)
		_deck_prev[pid] = [Engine.get_physics_frames(), l.z, f.origin]
		if not bot:
			var sit := bool(d.get("sitting"))
			var sd := f.basis.x
			var low := -1.0 if sd.y > 0.0 else 1.0           # какая сторона сейчас ниже
			sd.y = 0.0
			sd = sd.normalized()
			var slide := absf(sin(_roll_at(l.z))) * 5.0 * (0.12 if sit else 1.0) * low
			var push := gust * 1.9 * (0.05 if sit else 1.0) * low
			d.global_position += sd * (slide + push) * delta
	if deck:
		if carrying:
			var gap := _gap_ahead(d) if not bot else _gap_fwd(l.z)
			if gap.x >= 0 and (bot or d._just("use_item")):
				var ahead := bot or _face_dir(d) > 0.0
				var k0 := gap.x if ahead else maxi(gap.y - BOARD_SLOTS, gap.x)
				var k1 := mini(gap.x + BOARD_SLOTS, gap.y) if ahead else gap.y
				d.snow.start_scripted(17, self, {"k0": k0, "k1": k1, "kn": k0 if ahead else k1 - 1, "dir": 1.0 if ahead else -1.0, "p0": p, "sent": false})
				return
			if not bot and d._just("use_item"):
				_say(d, "Подойди к краю дыры в настиле и повернись к ней")
		elif carrier and not bot and d._just("use_item") and _gap_ahead(d).x >= 0:
			_say(d, "Доска в руках — повернись к друзьям и кинь её (Q)")
	# сорвался
	# временная точка возрождения — у начала этого моста
	if not _cp_set.has(pid) and d.has_method("set_checkpoint") and not far_side(p):
		_cp_set[pid] = true
		var cu := _edge_u(-1.0) - 11.0 / M.len_per_u(M.CHASM_U)
		var cpp := M.point(cu) + M.outward(cu) * -0.5
		cpp.y = M.height(cu) + 0.8
		d.set_checkpoint(cpp)
	# без страховки ниже настила над пропастью — долгое падение в туман (не цепляюсь за стены и уступы)
	if _over_chasm(p) and not d.snow.busy() and l.y < -2.5 and (line_pid != pid or absf(l.x) >= 12.0):
		d.snow.start_scripted(22, self, {"v": maxf(-d.velocity.y, 3.0)})
		SFX.play(self, p, "swish", -2.0, 0.5)
		return
	if _over_chasm(p) and absf(l.x) < 12.0 and l.z > -0.05 and l.z < 1.05 and l.y < -1.2 and line_pid == pid and not d.snow.busy():
		_start_swing(d)


## Дыра прямо передо мной (по взгляду, до 1.5 м): [от, до); (-1, -1) — нет
func _gap_ahead(d: Node3D) -> Vector2i:
	var fw := -(d.visual as Node3D).global_basis.z
	if absf(fw.dot(_th)) < 0.4:
		return Vector2i(-1, -1)
	var dirt := 1 if fw.dot(_th) > 0.0 else -1
	return _gap_from(_slot_of(_t_of(d.global_position)), dirt)


## Куда смотрю вдоль моста: +1 — к той стороне, −1 — к началу
func _face_dir(d: Node3D) -> float:
	return 1.0 if (-(d.visual as Node3D).global_basis.z).dot(_th) > 0.0 else -1.0


func _gap_fwd(t: float) -> Vector2i:
	return _gap_from(_slot_of(t), 1)


func _gap_from(k0: int, dirt: int) -> Vector2i:
	for step in range(1, 4):
		var k := k0 + dirt * step
		if k < 0 or k >= N:
			break
		if slots[k] == 0:
			var a := k
			var b := k
			while a - 1 >= 0 and slots[a - 1] == 0 and b - a < 7:
				a -= 1
			while b + 1 < N and slots[b + 1] == 0 and b - a < 7:
				b += 1
			if b == a and SINGLES.has(k):
				continue                     # одна выпавшая доска — перешагнуть, не чинить
			return Vector2i(a, b + 1)
	return Vector2i(-1, -1)


func _start_swing(d: Node3D) -> void:
	var p := d.global_position + Vector3.UP * 1.75
	var rel := p - _edge_p
	var R := clampf(rel.length(), 2.5, HANG_MAX)
	var th0 := atan2(maxf(rel.dot(_th), 0.3), maxf(-rel.y, 0.01))
	var ph0 := asin(clampf(rel.dot(_side) / R, -0.6, 0.6))
	var dist := (d.global_position - hook_pos).length()
	var pid := int(d.peer_id)
	_grip[pid] = 1.0
	d.snow.start_scripted(16, self, {"R": R, "th": th0, "w": 0.0, "ph": ph0, "pw": randf_range(-0.2, 0.2), "tw": 0.0, "twv": randf_range(-2.5, 2.5),
		"hit": false, "p0": d.global_position, "dist": dist, "grip": 1.0, "hand": -1, "gt": -10.0, "bt": -10.0})
	_ask("_req_fall", [pid, dist, R])
	SFX.play(self, p, "rope", 0.0, 0.7)
	if d == Network.local_player:
		d.add_shake(0.6)


func _pressed(d: Node3D, h: int) -> bool:
	if bool(d.get("is_bot")):
		return false
	return d._just("use_item" if h == 0 else "use_alt")


func drive(d: Node3D, kind: int, t: float, data: Dictionary, delta: float) -> void:
	match kind:
		16:
			_drive_swing(d, t, data, delta)
		17:
			_drive_lay(d, t, data, delta)
		18:
			_drive_throw(d, t, data, delta)
		19:
			_drive_hammer(d, t, data, delta)
		20:
			_drive_clip(d, t, data, delta)
		21:
			_drive_trav(d, t, data, delta)
		22:
			_drive_abyss(d, t, data, delta)


## Падение в пропасть: тело летит вниз, его разворачивает, руки ловят воздух; стены не задевает; в тумане — конец
## Шаг 129: луч по статичной геометрии (без игроков/ботов)
func _ray(d: Node3D, a: Vector3, b: Vector3) -> Dictionary:
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	var ex: Array[RID] = [(d as CollisionObject3D).get_rid()]
	for i in 4:
		q.exclude = ex
		var r := sp.intersect_ray(q)
		if r.is_empty():
			return r
		if r["collider"] is CharacterBody3D or r["collider"] is RigidBody3D:
			ex.append((r["collider"] as CollisionObject3D).get_rid())
			continue
		return r
	return {}


## Шаг 129: тело ниже настила — выталкиваю из стен пропасти (луч от оси пропасти к телу)
func _unclip(d: Node3D, pos: Vector3) -> Vector3:
	var deck_y := minf(_a.y, _b.y)
	if pos.y > deck_y - 2.0:
		return pos
	var out := pos
	for hgt: float in [0.3, 1.0, 1.6]:
		var at: Vector3 = out + Vector3.UP * hgt
		# середина пропасти на той же высоте и с тем же смещением вдоль трещины
		var mid := (_a + _b) * 0.5
		var thh := Vector3(_th.x, 0.0, _th.z).normalized()
		var rel := at - mid
		rel.y = 0.0
		var safe := Vector3(mid.x, at.y, mid.z) + rel - thh * rel.dot(thh)
		var dir := at - safe
		if dir.length() < 0.05:
			continue
		var dn := dir.normalized()
		var r := _ray(d, safe, at + dn * 0.45)
		if not r.is_empty():
			out += ((r["position"] as Vector3) - dn * 0.45) - at
	return out


func _drive_abyss(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var v := minf(float(data["v"]) + 9.8 * delta, 34.0)
	data["v"] = v
	var p := d.global_position
	var tc := M.tangent(M.CHASM_U)
	var along := (p - M.point(M.CHASM_U)).dot(tc)
	var lim := M.CHASM_W * 0.5 - WALL_OUT - 4.0
	if absf(along) > lim:
		p -= tc * signf(along) * 3.5 * delta
	var pn := p + Vector3.DOWN * v * delta
	# шаг 129: падаю — не сквозь полки и стены
	var hd := _ray(d, p + Vector3.UP * 0.6, pn + Vector3.DOWN * 0.05)
	if not hd.is_empty():
		pn = (hd["position"] as Vector3) + Vector3.UP * 0.05
		if v > 4.0:
			SFX.play(self, pn, "thunk", -4.0, 0.7)
			if d == Network.local_player:
				d.add_shake(0.35)
		data["v"] = 0.0
	p = _unclip(d, pn)
	d.global_position = p
	d.velocity = Vector3.ZERO
	if hd.is_empty():
		d.visual.rotation.y += delta * 1.6
	var fw := -(d.visual as Node3D).global_basis.z
	d.snow.set_mpose(22, 2.0 + 0.25 + 0.2 * sin(t * 9.0), p + Vector3.UP * 4.0, fw)
	if d == Network.local_player and fposmod(t, 0.3) < delta:
		d.add_shake(0.12)
	if t > 2.8:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.kill("Сорвался в пропасть!" if line_spent else "Сорвался в пропасть!\nСтраховка — у крюка в начале моста (E), она одна на всех")


## Укладываю связку у края дыры: подхожу, присел, левая — в настил, правая — молотком (3 удара)
func _drive_lay(d: Node3D, t: float, data: Dictionary, _delta: float) -> void:
	var pid := int(d.peer_id)
	var kn := int(data["kn"])
	var dirk := float(data["dir"])
	var g2 := _frame((kn + 0.5 - dirk * 0.9) / N).origin
	var stand := _frame((kn + 0.5 - dirk * 2.2) / N).origin
	var p0: Vector3 = data["p0"]
	d.global_position = p0.lerp(stand + Vector3.UP * 0.02, smoothstep(0.0, 1.0, clampf(t / 0.25, 0.0, 1.0)))
	var to := _th * dirk
	d.visual.rotation.y = atan2(-to.x, -to.z)
	d.velocity = Vector3.ZERO
	var k := clampf(t / LAY_T, 0.0, 0.999)
	d.snow.set_mpose(23, 1.0 + k, g2, to)
	if k > 0.42:
		var n_hit := int((k - 0.42) / 0.58 * 3.0 + 0.38)
		if n_hit > int(data.get("hits", 0)) and n_hit <= 3:
			data["hits"] = n_hit
			SFX.play(self, g2, "thunk", -6.0, 1.6)
			SFX.play(self, g2, "click", -10.0, 1.2)
	if k >= 0.42 and not bool(data["sent"]):
		data["sent"] = true
		_ask("_req_fill", [pid, int(data["k0"]), int(data["k1"])])
	if t >= LAY_T:
		d.snow.end_scripted()
		d.snow.set_mpose(0)


## Бросок: связку назад к груди → резко вперёд-вверх двумя руками
func _drive_throw(d: Node3D, t: float, data: Dictionary, _delta: float) -> void:
	var dir: Vector3 = data["dir"]
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = atan2(-dir.x, -dir.z)
	var T := 0.5
	d.snow.set_mpose(23, 2.0 + clampf(t / T, 0.0, 0.999), d.global_position + dir, dir)
	if t >= 0.24 and not bool(data.get("sent", false)):
		data["sent"] = true
		_ask("_req_throw", [int(d.peer_id), _hands(d) + dir * 0.3 + Vector3.UP * 0.2, dir])
	if t >= T:
		d.snow.end_scripted()
		d.snow.set_mpose(0)


## Забиваю крюк: присел у камня, левая придерживает, правая — молотком
func _drive_hammer(d: Node3D, t: float, data: Dictionary, _delta: float) -> void:
	var to := hook_pos - d.global_position
	to.y = 0.0
	if to.length() > 0.05:
		d.visual.rotation.y = atan2(-to.x, -to.z)
	d.velocity = Vector3.ZERO
	var T := float(data["T"])
	var k := clampf(t / T, 0.0, 0.999)
	d.snow.set_mpose(23, 1.42 + k * 0.193, hook_pos + Vector3.UP * 0.12, to.normalized())
	if k >= 0.62 and not bool(data.get("hit", false)):
		data["hit"] = true
		SFX.play(self, hook_pos, "clank", -4.0, 1.3)
		SFX.play(self, hook_pos, "thunk", -8.0, 1.8)
		_ask("_req_hook", [int(d.peer_id)])
		if d == Network.local_player:
			d.add_shake(0.12)
	if t >= T:
		d.snow.end_scripted()
		d.snow.set_mpose(0)


## Пристёгиваюсь к крюку: карабин в кольцо, закручиваю муфту
## Шаг 106: обвязываюсь — беру конец верёвки у крюка, несу к поясу, обношу вокруг, вяжу узел, дёргаю — проверил
func _drive_clip(d: Node3D, t: float, data: Dictionary, _delta: float) -> void:
	var to := hook_pos - d.global_position
	to.y = 0.0
	var fw := to.normalized() if to.length() > 0.05 else _th
	d.visual.rotation.y = atan2(-fw.x, -fw.z)
	d.velocity = Vector3.ZERO
	var T := float(data["T"])
	var k := clampf(t / T, 0.0, 0.999)
	var rope_end := hook_pos + Vector3.UP * 0.25 - fw * 0.45
	d.snow.set_mpose(25, k, rope_end, fw)
	if k >= 0.17 and not bool(data.get("sent", false)):
		data["sent"] = true
		SFX.play(self, rope_end, "rope", -8.0, 1.2)
		if line_pid < 0 and not line_spent:
			_ask("_req_line", [int(d.peer_id), true, Vector3.ZERO])
		else:
			_say(d, "Страховку уже взял другой")
			d.snow.end_scripted()
			d.snow.set_mpose(0)
			return
	if k >= 0.4 and not bool(data.get("w1", false)):
		data["w1"] = true
		SFX.play(self, d.global_position + Vector3.UP * 0.6, "rope", -11.0, 0.9)
	if k >= 0.72 and not bool(data.get("kn", false)):
		data["kn"] = true
		SFX.play(self, d.global_position + Vector3.UP * 0.6, "creak", -14.0, 1.6)
	if k >= 0.88 and not bool(data.get("tug", false)):
		data["tug"] = true
		SFX.play(self, d.global_position + Vector3.UP * 0.6, "rope", -6.0, 0.7)
		SFX.play(self, hook_pos, "click", -8.0, 0.9)
	if t >= T:
		d.snow.end_scripted()
		d.snow.set_mpose(0)


## Сорвался на страховке: маятник (вдоль и поперёк), удар о стену, верёвка крутит; вишу — руки слабеют:
## перехватываюсь ЛКМ/ПКМ (15 с), просто вишу — 6 с; потом срыв. Напарник у крюка тянет (E) — руки отдыхают
func _drive_swing(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var pid := int(d.peer_id)
	var bot := bool(d.get("is_bot"))
	var R := float(data["R"])
	if hang.has(pid):
		R = minf(R, float(hang[pid]))
	data["R"] = R
	var th := float(data["th"])
	var w := float(data["w"])
	var ph := float(data["ph"])
	var pw := float(data["pw"])
	var hit := bool(data["hit"])
	var grip := float(data["grip"])
	var thmin := asin(clampf(WALL_CLEAR / maxf(R, 0.9), 0.0, 1.0))
	var gf := gust * gust_dir
	for i in 4:
		var dt := delta / 4.0
		w += (-(9.8 / R) * sin(th) - w * 0.12 + (gust * 3.0 / R) * sin(_clock * 2.3)) * dt
		th += w * dt
		pw += (-(9.8 / R) * sin(ph) - pw * 0.1 + gf * 3.5 / R) * dt
		ph += pw * dt
		if th < thmin:
			var v := absf(w) * R
			if not hit:
				hit = true
				data["hit"] = true
				_wall_hit(d, v, float(data["dist"]))
			elif v > 1.4 and _clock - float(data["bt"]) > 0.6:
				# ветер снова приложил о скалу
				data["bt"] = _clock
				pass
				SFX.play(self, d.global_position + Vector3.UP, "thunk", -6.0, 0.8)
				if d == Network.local_player:
					d.add_shake(0.22)
			th = thmin
			w = absf(w) * 0.22
			pw *= 0.75
	data["th"] = th
	data["w"] = w
	data["ph"] = ph
	data["pw"] = pw
	# верёвка крутит тело
	var tw := float(data["tw"])
	var twv := float(data["twv"])
	twv += (-tw * (5.0 if hit else 1.2) - twv * 0.6 + gf * 1.4 * sin(_clock * 1.9)) * delta
	tw += twv * delta
	data["tw"] = tw
	data["twv"] = twv
	var grab := _edge_p + _th * R * sin(th) * cos(ph) + _side * R * sin(ph) + Vector3.DOWN * R * cos(th) * cos(ph)
	var face := (-_th).rotated(Vector3.UP, clampf(tw, -1.3, 1.3))
	var pos := grab + Vector3.DOWN * 1.72 - face * 0.18
	if t < 0.12:
		var p0: Vector3 = data["p0"]
		pos = p0.lerp(pos, t / 0.12)
	if t >= 0.12:
		pos = _unclip(d, pos)        # шаг 129: на верёвке не влезаю в скалу
	d.global_position = pos
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = atan2(-face.x, -face.z)
	var hauled: bool = mtn.is_active("CHA") and hit
	var hand := int(data["hand"])
	var gt := float(data["gt"])
	if hit:
		for hh in 2:
			if _pressed(d, hh) and hh != hand and _clock - gt > 0.22:
				hand = hh
				gt = _clock
				data["hand"] = hh
				data["gt"] = _clock
				SFX.play(self, grab, "rope", -12.0, 1.5)
		pass                                # шаг 134: руки не устают — просто висит на страховке, пока не вытянут
	data["grip"] = grip
	_grip[pid] = grip
	var k22 := 2.0 + clampf(t / 0.8, 0.0, 0.99)
	if hit:
		if hauled:
			k22 = fposmod(_clock * 1.6, 2.0)
		elif hand >= 0 and _clock - gt < 0.4:
			k22 = float(hand) + clampf((_clock - gt) / 0.4, 0.0, 0.99)
		else:
			k22 = 3.0 + fposmod(_clock * 0.4, 1.0)
	d.snow.set_mpose(22, k22, _edge_p, face)
	if grip <= 0.0:
		grip = 0.0                          # руки устали — висит на обвязке, ждёт, пока вытянут
		data["grip"] = 0.0
		_grip[pid] = 0.0
	if not hang.has(pid) and t > 2.0 and line_pid != pid:
		d.snow.end_scripted()
		d.snow.set_mpose(0)


## Перелезаю дыру по канатам: ноги на несущем, руки на перилах; ЛКМ/ПКМ по очереди — перехват.
## Перехват на порыве или на сильном крене — срыв
func _drive_trav(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var k0 := int(data["k0"])
	var k1 := int(data["k1"])
	var dirk := float(data["dir"])
	var sgn := float(data["sgn"])
	var t0 := ((k0 - 0.5) if dirk > 0.0 else (k1 + 0.5)) / N
	var t1 := ((k1 + 0.5) if dirk > 0.0 else (k0 - 0.5)) / N
	var ln := absf(t1 - t0) * _L
	var s := float(data["s"])
	var tgt := float(data["tgt"])
	var hand := int(data["hand"])
	var gt := float(data["gt"])
	if t > 0.35:
		for hh in 2:
			if _pressed(d, hh) and hh != hand and _clock - gt > 0.2:
				if gust > 0.4 or absf(_roll_at(lerpf(t0, t1, s / ln))) > deg_to_rad(14.0):
					_trav_slip(d, lerpf(t0, t1, s / ln), sgn)
					return
				hand = hh
				gt = _clock
				tgt = minf(tgt + TRAV_STEP, ln)
				SFX.play(self, d.global_position + Vector3.UP, "rope", -10.0, 1.3)
				if randf() < 0.35:
					SFX.play(self, d.global_position, "creak", -10.0, 1.2)
	s = move_toward(s, tgt, 1.9 * delta)
	data["s"] = s
	data["tgt"] = tgt
	data["hand"] = hand
	data["gt"] = gt
	var f := _frame(lerpf(t0, t1, s / ln))
	var out := f.basis.x * sgn
	out.y = 0.0
	out = out.normalized()
	var pos := f * Vector3(sgn * (DECK_HW - 0.3), -0.02, 0.0)
	if t < 0.35:
		var p0: Vector3 = data["p0"]
		pos = p0.lerp(pos, smoothstep(0.0, 1.0, t / 0.35))
	d.global_position = pos
	d.velocity = Vector3.ZERO
	d.visual.rotation.y = atan2(-out.x, -out.z)
	var k24 := 0.999
	if hand >= 0:
		k24 = float(hand) + clampf((_clock - gt) / 0.35, 0.0, 0.999)
	d.snow.set_mpose(24, k24, f * Vector3(sgn * (DECK_HW + 0.06), RAIL_H, 0.0), f.basis.z)
	if s >= ln - 0.01:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.global_position = _frame(t1).origin + Vector3.UP * 0.08


func _trav_slip(d: Node3D, tt: float, sgn: float) -> void:
	var f := _frame(tt)
	d.snow.end_scripted()
	d.snow.set_mpose(0)
	d.global_position = f * Vector3(sgn * (DECK_HW + 0.5), -1.6, 0.0)
	d.velocity = Vector3.DOWN * 2.0
	SFX.play(self, d.global_position + Vector3.UP * 1.5, "rope", -2.0, 1.6)
	_say(d, "Сорвался с каната! На порыве и на крене — замри, не перехватывайся")


## Удар о стену пропасти: чем длиннее маятник — тем сильнее; может оторвать руку или ногу
func _wall_hit(d: Node3D, v: float, _dist: float) -> void:
	SFX.play(self, d.global_position + Vector3.UP, "thunk", 0.0, 0.6)
	SFX.play(self, d.global_position + Vector3.UP, "crunch", -4.0, 0.9)
	if d == Network.local_player:
		d.add_shake(minf(0.3 + v * 0.05, 1.0))
	if not d.is_local or not d.has_method("lose_limb"):
		return
	var kinds: Array = []
	for k in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if d.has_limb(k):
			kinds.append(k)
	var p1 := clampf((v - 8.0) / 20.0, 0.0, 0.85)
	var lost := 0
	if not kinds.is_empty() and randf() < p1:
		var k1: String = kinds.pick_random()
		d.lose_limb(k1, -_th * 2.0 + Vector3.DOWN)
		kinds.erase(k1)
		lost += 1
		if not kinds.is_empty() and v > 16.0 and randf() < (v - 16.0) / 12.0:
			d.lose_limb(kinds.pick_random(), -_th * 2.0)
			lost += 1
	if lost > 0:
		_say(d, "Удар о скалу — %s! Висишь на страховке. Напарник, тяни (E у крюка)!" % ("оторвало деталь" if lost == 1 else "оторвало две детали"))
	else:
		_say(d, "Ударился о скалу! Висишь на страховке. Напарник, тяни (E у крюка)!")


# ---------------------------------------------------------------------------
#  Каждый кадр у всех
# ---------------------------------------------------------------------------

func visual(delta: float) -> void:
	_clock += delta
	if not multiplayer.is_server():
		phase += TAU / 3.6 * delta
	_update_flying(delta)
	_fcache.clear()
	_update_collision()
	_update_waist()
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(M.point(M.CHASM_U)) > 170.0:
		return
	# видеокарте — форма моста (провис, раскачка, крен)
	var S := _sag()
	var sx := _sway()
	var ro := _roll()
	for mat in [_wood_mm, _rope_mm, _susp_mm]:
		var sm := mat as ShaderMaterial
		if sm == null:
			continue
		sm.set_shader_parameter("br_a", _a)
		sm.set_shader_parameter("br_b", _b)
		sm.set_shader_parameter("br_side", _side)
		sm.set_shader_parameter("br_sag", S)
		sm.set_shader_parameter("br_sway", sx)
		sm.set_shader_parameter("br_roll", ro)
		sm.set_shader_parameter("br_len", _L)
		sm.set_shader_parameter("br_e", _end_e)
		sm.set_shader_parameter("br_wave", _wave())
		sm.set_shader_parameter("br_phase", phase)
	# укладываемые доски растут
	for k in _fill.keys():
		_fill[k] = float(_fill[k]) + delta
		_plank_custom(int(k))
		if float(_fill[k]) > 1.0:
			_fill.erase(k)
			_plank_custom(int(k))
	for dg in _dangles:
		var dmi: MeshInstance3D = dg[0]
		var g: Array = GAPS[int(dg[1])]
		var any_hole := false
		for k2 in range(int(g[0]), int(g[1])):
			if slots[k2] == 0:
				any_hole = true
		dmi.visible = any_hole
		if any_hole:
			var f5 := _frame(float(dg[2]))
			var sgd := float(dg[3])
			var hinge := f5 * Vector3(sgd * (DECK_HW - 0.05), -0.04, 0.0)
			var b5 := f5.basis.rotated(f5.basis.z, -sgd * (float(dg[4]) + 0.1 * sin(_clock * 1.3 + float(dg[2]) * 20.0) + 0.4 * gust))
			var ext := ((dmi.mesh as BoxMesh).size.x) * 0.5
			dmi.global_transform = Transform3D(b5, hinge - b5.x * sgd * ext)
	for ci in _crank.size():
		if mtn.is_active("CHW" if ci == 0 else "CHW2"):
			_crank[ci].rotation.x -= delta * 5.0
	if _hook_pin:
		_hook_pin.global_position = hook_pos + Vector3.UP * (0.06 + 0.03 * (HOOK_MAX - hook_lv))
	_update_line(delta)
	_update_bundles()
	_update_stack()
	_update_hammers()


## Коллизия: только доски и перила рядом с игроками и ботами (остальные сдвинутся, когда к ним подойдут).
## Не зависит от камеры — бот у моста не провалится, пока я далеко
func _update_collision() -> void:
	var S := _sag()
	var sx := _sway()
	var ro := _roll()
	var key := Vector4(snappedf(S, 0.01), snappedf(sx, 0.01), snappedf(ro, 0.002), snappedf(phase, 0.03) if _wave() > 0.02 else 0.0)
	if key != _state_key:
		_ver += 1
	_state_key = key
	var lim := sin(deg_to_rad(13.0)) * DECK_HW
	var want := {}
	for d in get_tree().get_nodes_in_group("player"):
		var dp := (d as Node3D).global_position
		if not in_zone(dp):
			continue
		var kc := _slot_of(_t_of(dp))
		for kk in range(kc - 10, kc + 11):
			if kk >= 0 and kk < N:
				want[kk] = true
	for k3 in want.keys():
		var cs := _slot_cs[k3]
		var ok := slots[k3] > 0
		if cs.disabled == ok:
			cs.disabled = not ok
		if _cs_ver[k3] != _ver:
			_cs_ver[k3] = _ver
			var f := _fr((k3 + 0.5) / N)
			cs.global_transform = Transform3D(f.basis, f.origin - f.basis.y * 0.07)
	for sgi in 2:
		var sg := -1.0 if sgi == 0 else 1.0
		for j in RSEG:
			var kj := clampi(int((j + 0.5) / RSEG * N), 0, N - 1)
			var need := false
			for dk in range(-6, 7, 3):
				if want.has(kj + dk):
					need = true
			if not need:
				continue
			var ri := sgi * RSEG + j
			if _rl_ver[ri] == _ver:
				continue
			_rl_ver[ri] = _ver
			var rc := _rail_cs[ri]
			var f2 := _fr((kj + 0.5) / N)
			var edge := f2 * Vector3(sg * DECK_HW, 0.0, 0.0)
			var tj := (j + 0.5) / RSEG
			rc.disabled = f2.origin.y - edge.y > lim or _wave() > 0.35 or tj < _end_e or tj > 1.0 - _end_e     # провисший мост — и перила висят, не держат; у входа — не мешают
			rc.global_transform = Transform3D(f2.basis, f2 * Vector3(sg * (DECK_HW + 0.08), 0.75, 0.0))


func _update_flying(delta: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var e: Array = _flying[i]
		var n: Node3D = e[0]
		e[3] = float(e[3]) + delta
		var k := float(e[3]) / float(e[4])
		var from: Vector3 = e[1]
		var to: Vector3 = e[2]
		if k <= 1.0:
			var drift: Vector3 = e[6]
			drift += _side * gust * gust_dir * 2.0 * delta
			e[6] = drift
			n.global_position = from.lerp(to, k) + Vector3.UP * sin(PI * k) * (0.8 + from.distance_to(to) * 0.1) + drift
			n.global_basis = Basis(Vector3.UP, float(e[3]) * 3.0) * Basis(Vector3.RIGHT, float(e[3]) * 5.0)
		else:
			var cp := int(e[5])
			var cd: Node3D = mtn.drone_by_id(cp) if cp >= 0 else null
			if cd != null and carry.has(cp):
				n.queue_free()
				_flying.remove_at(i)
				SFX.play(self, to, "thunk", -6.0, 1.3)
				continue
			if cp >= 0 and k < 1.6:
				continue                       # ждём, поймал ли (хост)
			# не поймали — падает в пропасть
			var vy := -9.8 * (float(e[3]) - float(e[4]))
			n.global_position += Vector3(0.0, vy * delta, 0.0) + _side * 0.8 * delta
			n.rotate_x(delta * 4.0)
			if float(e[3]) > float(e[4]) + 3.0:
				n.queue_free()
				_flying.remove_at(i)


## Верёвка страховки: от крюка по настилу к обвязке (своя физика), при срыве — натянута через кромку
func _update_line(delta: float) -> void:
	var mi: MeshInstance3D = _line["mi"]
	var P: PackedVector3Array = _line["P"]
	var O: PackedVector3Array = _line["O"]
	var n := P.size()
	var start := hook_pos + Vector3.UP * 0.3
	var d: Node3D = mtn.drone_by_id(line_pid) if line_pid >= 0 else null
	_reel = minf(_reel + delta / 3.0, 1.0)
	_coil.visible = line_pid < 0 and _reel >= 1.0
	if line_spent:
		mi.visible = false
		return
	if d == null and _reel >= 1.0:
		mi.visible = false
		return
	mi.visible = true
	var end: Vector3
	if d != null:
		end = _line_end(d)
	else:
		end = _reel_from.lerp(start, smoothstep(0.0, 1.0, _reel))
	if d != null and d.snow.busy() and int(d.snow.climb) == 16:
		# натянута: крюк → кромка → руки → обвязка
		var su = d.get("suit")
		var hi := end + Vector3.UP * 0.8
		var lo := end + Vector3.UP * 0.5
		if su != null and su.has_method("fist_pos"):
			var f0: Vector3 = su.fist_pos(0)
			var f1: Vector3 = su.fist_pos(1)
			hi = f0 if f0.y > f1.y else f1
			lo = f1 if f0.y > f1.y else f0
		var poly := [start, _edge_p + Vector3.UP * 0.04, hi, lo, end]
		var pts := _resample_poly(poly, n)
		for i in n:
			P[i] = pts[i]
			O[i] = pts[i]
	else:
		var L := clampf(start.distance_to(end) * 1.03 + 0.6, 0.5, 78.0)
		var seg := L / (n - 1)
		var dt := clampf(delta, 1.0 / 120.0, 1.0 / 30.0)
		var grav := Vector3(0.0, -9.8 * dt * dt, 0.0)
		for i in range(1, n - 1):
			var v := (P[i] - O[i]) * 0.98
			O[i] = P[i]
			P[i] += v + grav
		P[0] = start
		P[n - 1] = end
		var gy := PackedFloat32Array()
		gy.resize(n)
		for i in n:
			gy[i] = _line_ground(P[i])
		for it in 14:
			for i in n - 1:
				var dv := P[i + 1] - P[i]
				var ln := dv.length()
				if ln < 0.00001 or ln < seg:
					continue
				var corr := dv * ((ln - seg) / ln)
				if i == 0:
					P[i + 1] -= corr
				elif i + 1 == n - 1:
					P[i] += corr
				else:
					P[i] += corr * 0.5
					P[i + 1] -= corr * 0.5
			for i in range(1, n - 1):
				if P[i].y < gy[i]:
					P[i].y = gy[i]
		for i in range(1, n - 1):
			if P[i].y <= gy[i] + 0.004:
				var o := O[i]
				O[i] = Vector3(lerpf(o.x, P[i].x, 0.7), o.y, lerpf(o.z, P[i].z, 0.7))
	_line["P"] = P
	_line["O"] = O
	# лежит неподвижно — меш не пересобираю
	var moved_l := _line_last.size() != n
	if not moved_l:
		for i in n:
			if P[i].distance_squared_to(_line_last[i]) > 0.00002:
				moved_l = true
				break
	if moved_l:
		_line_last = P.duplicate()
		_tube(mi, _smooth(P), 0.012, 8)


## Где опора под точкой верёвки: на настиле (если доска есть), на полке у краёв; над дырой — нет
func _line_ground(p: Vector3) -> float:
	var t := _t_of(p)
	if t < 0.0:
		return _a.y - 0.04 if _flat(p, hook_pos) > 0.6 else hook_pos.y
	if t > 1.0:
		return _b.y - 0.04
	var k := _slot_of(t)
	var f := _fr((k + 0.5) / N)
	var lp := f.affine_inverse() * p
	if slots[k] > 0 and absf(lp.x) < DECK_HW:
		return (f * Vector3(lp.x, 0.012, 0.0)).y
	return -1e9


func _resample_poly(poly: Array, n: int) -> PackedVector3Array:
	var lens: Array = [0.0]
	for i in poly.size() - 1:
		lens.append(float(lens[i]) + (poly[i] as Vector3).distance_to(poly[i + 1]))
	var total: float = lens[lens.size() - 1]
	var out := PackedVector3Array()
	var j := 0
	for i in n:
		var s := total * float(i) / (n - 1)
		while j < poly.size() - 2 and float(lens[j + 1]) < s:
			j += 1
		var seg := maxf(float(lens[j + 1]) - float(lens[j]), 0.0001)
		out.append((poly[j] as Vector3).lerp(poly[j + 1], clampf((s - float(lens[j])) / seg, 0.0, 1.0)))
	return out


func _smooth(P: PackedVector3Array) -> PackedVector3Array:
	var C := PackedVector3Array()
	var n := P.size()
	for i in n - 1:
		var p0 := P[maxi(i - 1, 0)]
		var p1 := P[i]
		var p2 := P[i + 1]
		var p3 := P[mini(i + 2, n - 1)]
		C.append(p1)
		C.append(0.5 * (p1 + p2) + 0.0625 * ((p1 - p0) - (p3 - p2)))
	C.append(P[n - 1])
	return C


## Стопка досок на спине носильщика (ребёнок модели): видно, сколько осталось
func _update_stack() -> void:
	var d: Node3D = null              # шаг 130: на спине больше не носим — доска в руках (_update_bundles)
	if d == null:
		if _stack_node != null and is_instance_valid(_stack_node):
			_stack_node.queue_free()
		_stack_node = null
		return
	var vis := d.visual as Node3D
	if _stack_node == null or not is_instance_valid(_stack_node) or _stack_node.get_parent() != vis:
		if _stack_node != null and is_instance_valid(_stack_node):
			_stack_node.queue_free()
		_stack_node = Node3D.new()
		vis.add_child(_stack_node)
		# вязанка поперёк спины: щиты лежат друг на друге, концы торчат в стороны; две верёвки
		for k in STACK_MAX:
			var b := _board_mesh()
			_stack_node.add_child(b)
			b.position = Vector3(0.0, 0.04 + k * 0.08, 0.0)
			b.rotation = Vector3(0.0, PI * 0.5, 0.0)
		for x in [-0.38, 0.38]:
			var strap := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.05, 0.56, 0.54)
			strap.mesh = sb
			strap.material_override = _hemp
			_stack_node.add_child(strap)
			strap.position = Vector3(x, 0.24, 0.0)
	var vs := vis.scale
	var inv := Vector3(1.0 / maxf(vs.x, 0.01), 1.0 / maxf(vs.y, 0.01), 1.0 / maxf(vs.z, 0.01))
	_stack_node.transform = Transform3D(Basis(Vector3.RIGHT, 0.1).scaled(inv), Vector3(0.0, 0.74, 0.42) * inv)
	for k2 in STACK_MAX:
		(_stack_node.get_child(k2) as Node3D).visible = k2 < stack_n


## Связка в руках: ребёнок модели (идёт вместе с телом — не дрожит); кладу — опускается к дыре
func _update_bundles() -> void:
	var held: Array = carry.keys()
	if stack_pid >= 0:
		var sd: Node3D = mtn.drone_by_id(stack_pid)
		if sd != null and stack_n > 0 and not held.has(stack_pid):
			held.append(stack_pid)                 # шаг 130: доска носильщика — в руках перед собой
	for pid in _bundles.keys():
		var dd: Node3D = mtn.drone_by_id(int(pid))
		if not held.has(pid) or dd == null:
			if is_instance_valid(_bundles[pid]):
				(_bundles[pid] as Node3D).queue_free()
			_bundles.erase(pid)
	for pid2 in held:
		var d: Node3D = mtn.drone_by_id(int(pid2))
		if d == null:
			continue
		var vis := d.visual as Node3D
		var bn: Node3D = _bundles.get(pid2)
		if bn == null or not is_instance_valid(bn):
			bn = _board_mesh()
			vis.add_child(bn)
			_bundles[pid2] = bn
		var vs := vis.scale
		var inv := Vector3(1.0 / maxf(vs.x, 0.01), 1.0 / maxf(vs.y, 0.01), 1.0 / maxf(vs.z, 0.01))
		var loc := Vector3(0.0, 1.2, -0.52)
		var mk := float(d.snow.mpose_k) if int(d.snow.mpose) == 23 else 0.0
		bn.visible = true
		# шаг 131: несу — доска лежит ровно на ладонях (ставлю её по кистям каждый кадр): руки не проходят сквозь неё,
		# покачивается вместе с руками на ходу
		var su = d.get("suit")
		if mk < 1.0 and int(d.snow.mpose) == 23 and su != null and su.has_method("hand_point"):
			var hl: Vector3 = su.hand_point(0)
			var hr: Vector3 = su.hand_point(1)
			var xa := hr - hl
			if xa.length() > 0.05:
				xa = xa.normalized()
				var fwv := -vis.global_basis.z
				var upv := xa.cross(fwv).normalized()
				if upv.y < 0.0:
					upv = -upv
					xa = -xa
				fwv = upv.cross(xa).normalized()
				bn.global_transform = Transform3D(Basis(fwv, upv, xa), (hl + hr) * 0.5 + upv * 0.09 + fwv * 0.17)
				continue
		if mk >= 1.0 and mk < 2.0:
			var ph := mk - 1.0
			bn.visible = ph < 0.45
			if ph > 0.3:
				var gpt: Vector3 = d.snow.mpose_pt
				var gl := vis.global_transform.affine_inverse() * (gpt + Vector3.UP * 0.05)
				loc = (loc * 1.0).lerp(gl * vs, smoothstep(0.3, 0.42, ph))
		elif mk >= 2.0:
			var e := smoothstep(0.1, 0.45, mk - 2.0)
			loc = Vector3(0.0, 1.2 + 0.3 * e, -0.52 - 0.35 * e)
			bn.visible = mk - 2.0 < 0.48
		bn.transform = Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(inv), loc * inv)


func _update_hammers() -> void:
	for pid5 in _hammers.keys():
		var d3: Node3D = mtn.drone_by_id(int(pid5))
		if d3 == null or int(d3.snow.mpose) != 23 or float(d3.snow.mpose_k) < 1.4 or float(d3.snow.mpose_k) >= 2.0:
			(_hammers[pid5] as Node3D).queue_free()
			_hammers.erase(pid5)
	for d4 in get_tree().get_nodes_in_group("player"):
		var mk := float(d4.snow.mpose_k)
		if int(d4.snow.mpose) == 23 and mk >= 1.4 and mk < 2.0 and d4.get("suit") != null:
			var pid6 := int(d4.peer_id)
			var hm: Node3D = _hammers.get(pid6)
			if hm == null:
				hm = _hammer_mesh()
				add_child(hm)
				_hammers[pid6] = hm
			var fp: Vector3 = d4.suit.fist_pos(1)
			var fw := -(d4.visual as Node3D).global_basis.z
			hm.global_transform = Transform3D(Basis.looking_at((fw + Vector3.DOWN * 0.6).normalized(), Vector3.UP), fp)


## Трубка по точкам; UV вдоль — в метрах; касательные — для рельефа прядей
func _tube(mi: MeshInstance3D, P: PackedVector3Array, rr: float, sides: int) -> void:
	var m := P.size()
	if m < 2:
		return
	var V := PackedVector3Array()
	var Nn := PackedVector3Array()
	var U := PackedVector2Array()
	var T := PackedFloat32Array()
	var I := PackedInt32Array()
	V.resize(m * (sides + 1))
	Nn.resize(m * (sides + 1))
	U.resize(m * (sides + 1))
	T.resize(m * (sides + 1) * 4)
	var nrm := Vector3.ZERO
	var along := 0.0
	for i in m:
		var tg := P[mini(i + 1, m - 1)] - P[maxi(i - 1, 0)]
		tg = tg.normalized() if tg.length() > 0.00001 else Vector3.UP
		if i == 0:
			nrm = tg.cross(Vector3.UP if absf(tg.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			along += P[i].distance_to(P[i - 1])
			nrm = nrm - tg * nrm.dot(tg)
			nrm = nrm.normalized() if nrm.length() > 0.0001 else tg.cross(Vector3.RIGHT).normalized()
		var bn := tg.cross(nrm)
		for j in sides + 1:
			var ang := TAU * float(j) / sides
			var dir := nrm * cos(ang) + bn * sin(ang)
			var q := i * (sides + 1) + j
			V[q] = P[i] + dir * rr
			Nn[q] = dir
			U[q] = Vector2(float(j) / sides, along)
			var tv := -nrm * sin(ang) + bn * cos(ang)
			T[q * 4] = tv.x
			T[q * 4 + 1] = tv.y
			T[q * 4 + 2] = tv.z
			T[q * 4 + 3] = 1.0
	I.resize((m - 1) * sides * 6)
	var w := 0
	for i2 in m - 1:
		for j2 in sides:
			var a0 := i2 * (sides + 1) + j2
			var b0 := a0 + sides + 1
			I[w] = a0
			I[w + 1] = b0
			I[w + 2] = a0 + 1
			I[w + 3] = a0 + 1
			I[w + 4] = b0
			I[w + 5] = b0 + 1
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = Nn
	arr[Mesh.ARRAY_TANGENT] = T
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_INDEX] = I
	var am := mi.mesh as ArrayMesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


# ---------------------------------------------------------------------------
#  Подсказки
# ---------------------------------------------------------------------------

func hint(me: Node3D) -> String:
	var p := me.global_position
	if not near(p) and not in_zone(p):
		return ""
	var pid := int(me.peer_id)
	if me.snow.busy() and int(me.snow.climb) == 16:
		var g := clampf(float(_grip.get(pid, 1.0)), 0.0, 1.0)
		var bar := ""
		for i0 in 8:
			bar += "▮" if float(i0) / 8.0 < g else "▯"
		if mtn.is_active("CHA"):
			return "Тебя тянут! Осталось %.0f м" % float(hang.get(pid, 0.0))
		return "ВИСИШЬ на страховке — держись, ничего нажимать не нужно. Напарник вытянет: E у крюка"
	if me.snow.busy() and int(me.snow.climb) == 21:
		if gust > 0.25 or _gust_st == 1:
			return "ВЕТЕР — ЗАМРИ! Не перехватывайся, пока не стихнет"
		if absf(_roll_at(_t_of(p))) > deg_to_rad(11.0):
			return "Мост кренит — замри! Перехват на крене — срыв"
		return "ЛКМ / ПКМ по очереди — перехват по канату. На порыве и крене — замри"
	var hp: String = mtn._hold_point_of(me) if me._held("interact") else ""
	if hp == "CHW" or hp == "CHW2":
		return "Натягиваешь мост: %d%%" % int(tension * 100.0)
	if hp == "CHA":
		return "Тянешь страховку! Осталось %.0f м" % (float(hang.values()[0]) if not hang.is_empty() else 0.0)
	if not hang.is_empty() and _flat(p, hook_pos) < 3.0:
		return "Напарник висит на страховке — держи E у крюка, тяни!"
	if not hang.is_empty() and not hang.has(pid):
		return "НАПАРНИК ВИСИТ НА СТРАХОВКЕ! Беги к крюку в начале моста — держи E, тяни!"
	if _flat(p, near_winch) < 1.8 or _flat(p, far_winch) < 1.8:
		return "Держи E — натянуть мост лебёдкой (сейчас %d%%; отпустишь — понемногу провиснет)" % int(tension * 100.0)
	var bars := ""
	for i in HOOK_MAX:
		bars += "■" if i < hook_lv else "□"
	if _flat(p, hook_pos) < 1.8:
		if line_spent:
			return "Страховку уже использовали — она на том берегу"
		var who := "свободна — E: пристегнуться (одна, на один переход)" if line_pid < 0 else ("на тебе — E: отстегнуться" if line_pid == pid else "занята")
		return "Страховка %s" % who
	var lined := line_pid == pid
	var carrier := stack_pid == pid and stack_n > 0
	var left := "Досок: %d, нужно %d" % [boards_left(), _need()]
	if on_deck(me):
		var k := _slot_of(_local(p).z)
		for d in get_tree().get_nodes_in_group("player"):
			if d != me and not bool(d.get("is_dead")) and not d.snow.busy() and on_deck(d) and absi(_slot_of(_local(d.global_position).z) - k) <= NEAR_K:
				return "Слишком близко друг к другу — доски трещат! Разойдитесь (2 м)"
		var dist := (p - hook_pos).length()
		var warn := ""
		if not lined:
			warn = "Без страховки! "
		if gust > 0.2:
			return warn + "ПОРЫВ! Присядь (Ctrl)!"
		if carry.has(pid):
			if _gap_ahead(me).x >= 0:
				return warn + "ЛКМ — прибить доску"
			return warn + "Доска в руках: к краю дыры, лицом к ней — ЛКМ. (Q — перебросить другому)"
		var gap := _gap_ahead(me)
		if carrier:
			if _face_dir(me) < 0.0:
				return warn + "Q — кинуть доску другу. %s" % left
			return warn + "Доска в руках. Повернись к друзьям у разрушенного участка — Q: кинуть"
		if gap.x >= 0:
			if lined:
				return warn + "Дыра: прыгай на уцелевшую доску (Пробел) или E — перелезть по канатам"
			if stack_pid >= 0 or pile_n > 0:
				return warn + "Дыра. Стой у края с пустыми руками — тебе кинут доску, поймаешь и прибьёшь (ЛКМ). " + left
			return warn + "Досок больше нет! E — перелезть по канатам без страховки (на свой страх и риск)"
		if _wave() > 0.35:
			return warn + "Мост гуляет — лебёдку никто не держит! Перебежка между качками, на крене — присядь (Ctrl)"
		return warn + "%d м из %d. Не прыгнуть и не бежать" % [int(_local(p).z * _L), int(_L)]
	if _flat(p, pile_pos) < 2.2:
		if lined:
			return "Отойди от моста — страховка отцепится, потом бери доски"
		return "E — взять доску в руки (в штабеле %d). %s" % [pile_n, left]
	if _flat(p, clip_b) < 1.8 and lined:
		return "E — отстегнуться (страховка останется на этом берегу)"
	if far_side(p) and not repaired():
		if carrier:
			return "Доска в руках. На мост — к разрушенному участку, лицом к друзьям — Q"
		if stack_pid < 0 and pile_n > 0:
			return "Друзья ждут доски: штабель справа (E), потом кидай им (Q). " + left
	if not repaired() and not far_side(p):
		if lined:
			return "На страховке: по мосту, дыры — по канатам (E у края). На том берегу — доски, кидай их нам (Q)"
		if line_spent:
			return "Ждите у разрушенного участка: напарник кинет доски — ловите и чините (ЛКМ). " + left
		return "Сначала один переходит на страховке (крюк справа у скалы, E), берёт доски на том берегу и кидает вам"
	return ""


# --- бот (coop_gate) ---
func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	if not near(bot.global_position) or not near(owner_node.global_position) or bot.snow.busy():
		return Vector3.INF
	var bpid := int(bot.peer_id)
	var opid := int(owner_node.peer_id)
	if hang.has(opid):
		return hook_pos - _th * 0.7 + Vector3.DOWN * 0.45            # тянуть страховку
	var fr := _frontier()
	if carry.has(bpid) and fr >= 0:
		return _frame((fr - 2 + 0.5) / N).origin                       # к краю дыры (уложит сам)
	var bf := far_side(bot.global_position)
	var of := far_side(owner_node.global_position)
	# хозяин-носильщик с досками уже за дырой (или лезет через неё) — жду у ближнего края, ловлю
	var o_trav: bool = owner_node.snow.busy() and int(owner_node.snow.climb) == 21
	if (line_pid == opid or stack_pid == opid) and fr >= 0 and not bf and (o_trav or far_side(owner_node.global_position) or (on_deck(owner_node) and _t_of(owner_node.global_position) > float(fr) / N)):
		return _frame((fr - 2 + 0.5) / N).origin
	var o_deck := on_deck(owner_node)
	if on_deck(bot):
		return _b + _th * 2.0 if _t_of(bot.global_position) > 0.5 else _a - _th * 2.0
	if not bf:
		if o_deck or not of:
			return _wstand[0]
		if repaired():
			var bl := _local(bot.global_position)
			if absf(bl.x) > 0.4 or bl.z < -0.2:
				return _a - _th * 0.8
			return _b + _th * 2.0
		return Vector3.INF
	if o_deck or not of:
		return _wstand[1]
	return Vector3.INF


func bot_crank(bot: Node3D, owner_node: Node3D) -> bool:
	var t := bot_target(bot, owner_node)
	if t == Vector3.INF:
		return false
	var spots := [_wstand[0], _wstand[1], hook_pos - _th * 0.7 + Vector3.DOWN * 0.45]
	var ok := false
	for s in spots:
		if t.distance_to(s) < 0.1:
			ok = true
	if not ok:
		return false
	var b := bot.global_position
	return _flat(t, b) < 0.9 and absf(t.y - b.y) < 1.6
