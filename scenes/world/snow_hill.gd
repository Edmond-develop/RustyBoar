extends Node3D
## Снежная гора (шаги 139–142, вместо Ледяного каньона).
##
##  * Подъёмник-«турник» над пропастью: на настиле держи E — висишь на перекладине, несёт на вершину.
##  * Вершина (190 м): стойка сноубордов (E — взять доску), стартовые ворота.
##  * Склон горы на всю ширину в густом лесу; по нему — трасса-серпантин ~1.3 км (snow_hill_layout.gd):
##    разгон и трамплин → траверс через лес (ёлки и брёвна прямо на трассе) → шпилька → длинный лесной
##    траверс → шпилька → гребень над ущельями → траверс, где сзади катятся комы и наводятся на тебя →
##    шпилька → трамплины → финиш. С трассы можно уйти в лес и катиться напрямик.
##  * Сноуборд (climb 51): A/D — повороты, S — тормоз, W — присесть/разогнаться, Пробел — прыжок;
##    в воздухе A/D — вращение, W — захват. Кривое приземление, ёлка, бревно, друг, ком — кувырок.
##    В ёлку на большой скорости — отлетает рука (на очень большой — нога), доска улетает: подбери (E).
##
## Рельеф — terrain._hill_height → HILL.hill_y.

const L := preload("res://scenes/world/snow_hill_layout.gd")
const SFX := preload("res://scripts/sfx.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")
const TOW_V := 8.0                  ## скорость троса, м/с
const BOARD_G := 9.8 * 2.0          ## тяжесть на доске (шаг 142: быстрее)
const MAX_V := 38.0
const SPIN_V := 5.6                 ## рад/с — вращение в воздухе
const ARM_V := 15.0                 ## в ёлку с такой скорости — отлетает рука
const LEG_V := 23.0                 ## …а с такой — нога

var _ter: Node
var _tow_len := 1.0
var _hanger_mm: MultiMesh
var _hang_t := 0.0
var _rider_bars: Array[MeshInstance3D] = []
var _hud: CanvasLayer
var _hud_speed: Label
var _hud_trick: Label
var _trick_t := 0.0
var _hint: Label
var _hint_t := 0.0
var _rack_pos := Vector3.ZERO
var _spray: Dictionary = {}          ## игрок → CPUParticles3D
var _snow_mat: StandardMaterial3D
var _board_mesh: ArrayMesh
## снежные комы (сервер катит, всем рассылает)
const BALLS := 5
const BALL_CHASE := 200.0            ## шаг 144: столько метров ком гонится за игроком
var _balls: Array = []               ## [{on, s, lat, r, v, id}]
var _ball_nodes: Array = []          ## [Node3D, MeshInstance3D, CPUParticles3D]
var _ball_spawn_t := 0.0
var _ball_send_t := 0.0
var _ball_id := 0
## брошенные доски (слетели при ударе): id → RigidBody3D
var _loose := {}
var _loose_n := 0
var _last_s := 0.0                   ## для тестов


func _ready() -> void:
	add_to_group("snow_hill")
	# шаг 144: перекладины райдеров ставлю ПОСЛЕ вида от 1-го лица (он двигает тело и камеру в кадре) — не дёргаются
	process_priority = 100
	_ter = get_tree().get_first_node_in_group("terrain")
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.albedo_color = Color(0.93, 0.96, 1.0)
	_snow_mat.roughness = 0.9
	_build_tow()
	var cd := Node3D.new()
	cd.set_script(preload("res://scenes/world/chasm_decor.gd"))
	cd.name = "ChasmDecor"
	add_child(cd)
	_build_top()
	_build_course()
	_build_forest()
	_build_kickers()
	_build_balls()
	_build_hud()
	_checkpoints()


func _checkpoints() -> void:
	var b := L.lift_bottom()
	var fin := L.at(L.FINISH_S + 12.0)
	var list := [[Vector3(b.x - 10.0, 0.0, b.z + 3.0), Vector3(22.0, 8.0, 12.0), "Пропасть", "Контрольная точка у подъёмника"],
		[Vector3(6.0, 0.0, -33.0), Vector3(36.0, 8.0, 22.0), "Вершина Снежной горы", "Контрольная точка — сноуборды у стойки"],
		[Vector3(fin.x, 0.0, fin.y), Vector3(50.0, 8.0, 24.0), "Выкат", "Контрольная точка — спуск позади"]]
	for cp in list:
		var a := Area3D.new()
		a.set_script(CHECKPOINT)
		a.name = "HillCheckpoint_%d" % int(cp[0].z)
		a.set("size", cp[1])
		a.set("title", cp[2])
		a.set("subtitle", cp[3])
		a.set("respawn_offset", Vector3(0.0, 0.6, 0.0))
		a.position = cp[0]
		add_child(a)


## Точка трассы: длина пути s, смещение поперёк d (+ вправо по ходу), на высоте рельефа
func _pt(s: float, d := 0.0) -> Vector3:
	var p := L.at(s)
	var t := L.dir(s)
	var q := p + Vector2(-t.y, t.x) * d
	return Vector3(q.x, _h(q.x, q.y), q.y)


## Направление трассы (в мире) на длине s
func _fw(s: float) -> Vector3:
	var t := L.dir(s)
	return Vector3(t.x, 0.0, t.y)


func _h(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else 0.0


func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _cyl(r: float, hgt: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = hgt
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = m
	return mi


func _box(sz: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = m
	return mi


## Отрезок-цилиндр между двумя точками
func _rod(a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := _cyl(r, a.distance_to(b), m)
	add_child(mi)
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	return mi


func _sign(at: Vector3, text: String, col: Color, size := 30) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.outline_size = 8
	lb.modulate = col
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(lb)
	lb.global_position = at + Vector3.UP * 2.6
	var post := _cyl(0.06, 1.8, _mat(Color(0.35, 0.3, 0.25)))
	add_child(post)
	post.global_position = at + Vector3.UP * 0.9


# ---------------------------------------------------------------------------
#  Подъёмник-«турник» (шаг 140): трос над пропастью, на нём — перекладины. Держишь E — висишь
#  на перекладине, тебя несёт на вершину. Отпустил над пропастью — падаешь.
#  Трос: вверх — x = LIFT_X, обратно — на 3 м в стороне. Опоры: в пропасти и на краю вершины.
# ---------------------------------------------------------------------------

const LANE := 3.0
const HANGER_GAP := 24.0

func _cable(k: float, lane: float) -> Vector3:
	return L.cable_point(k) + Vector3(lane * LANE, 0.0, 0.0)


## Цилиндр в SurfaceTool от a до b
static func _st_cyl(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color, seg := 10) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := ax.cross(u)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := (u * cos(a0) + v * sin(a0)) * r
		var d1 := (u * cos(a1) + v * sin(a1)) * r
		_quad(st, a + d0, b + d0, b + d1, a + d1, col)
		_quad(st, a, a + d0, a + d1, a + d1, col)
		_quad(st, b, b + d1, b + d0, b + d0, col)


static func _st_wheel(st: SurfaceTool, c: Vector3, axis: Vector3, r: float, w: float, col: Color, hub: Color) -> void:
	_st_cyl(st, c - axis * w * 0.5, c + axis * w * 0.5, r, col, 16)
	_st_cyl(st, c - axis * (w * 0.5 + 0.02), c + axis * (w * 0.5 + 0.02), r * 0.3, hub, 8)


## Перекладина с кареткой (начало координат — точка на тросе; перекладина — вдоль X на ROD ниже)
static func make_hanger_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := Color(0.36, 0.38, 0.42)
	var dark := Color(0.12, 0.12, 0.14)
	var yellow := Color(0.95, 0.68, 0.1)
	var rubber := Color(0.06, 0.06, 0.07)
	# каретка: два ролика на тросе, щёки, зажим
	for zz in [-0.22, 0.22]:
		_st_wheel(st, Vector3(0.0, 0.0, zz), Vector3.RIGHT, 0.09, 0.06, dark, steel)
	_box_v(st, Vector3(0.07, -0.02, 0.0), Vector3(0.025, 0.2, 0.62), steel)
	_box_v(st, Vector3(-0.07, -0.02, 0.0), Vector3(0.025, 0.2, 0.62), steel)
	_box_v(st, Vector3(0.0, -0.16, 0.0), Vector3(0.18, 0.12, 0.3), yellow)
	_box_v(st, Vector3(0.0, -0.24, 0.0), Vector3(0.1, 0.06, 0.12), dark)
	# штанга: верх — потолще (пружинный стакан), ниже — труба
	_st_cyl(st, Vector3(0.0, -0.26, 0.0), Vector3(0.0, -0.62, 0.0), 0.05, yellow)
	_st_cyl(st, Vector3(0.0, -0.62, 0.0), Vector3(0.0, -L.ROD + 0.04, 0.0), 0.024, steel)
	_st_cyl(st, Vector3(0.0, -0.63, 0.0), Vector3(0.0, -0.66, 0.0), 0.055, dark)
	# перекладина: труба, резиновые ручки, жёлтые заглушки, косынки к штанге
	var y := -L.ROD
	_st_cyl(st, Vector3(-0.42, y, 0.0), Vector3(0.42, y, 0.0), 0.022, steel)
	for sx in [-1.0, 1.0]:
		_st_cyl(st, Vector3(sx * 0.12, y, 0.0), Vector3(sx * 0.34, y, 0.0), 0.03, rubber, 12)
		_st_cyl(st, Vector3(sx * 0.42, y, 0.0), Vector3(sx * 0.46, y, 0.0), 0.034, yellow)
		_st_cyl(st, Vector3(0.0, y + 0.16, 0.0), Vector3(sx * 0.1, y, 0.0), 0.012, steel, 6)
	_box_v(st, Vector3(0.0, y, 0.0), Vector3(0.07, 0.07, 0.07), dark)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.45
	m.metallic = 0.4
	st.set_material(m)
	return st.commit()


## Решётчатая опора: от земли до верха (y_top), с траверсой на два троса
func _tower(z: float, y_top: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.55, 0.18, 0.12)
	var steel := Color(0.36, 0.38, 0.42)
	var cx := L.LIFT_X + LANE * 0.5
	var y0 := minf(_h(cx - 2.0, z), _h(cx + 2.0, z)) - 2.0
	var hgt := y_top - y0
	var spread := clampf(hgt * 0.08, 1.2, 4.0)
	var legs: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			legs.append(Vector3(sx, 0.0, sz))
	var ring := func(t: float) -> Array:
		var w := lerpf(spread, 0.7, t)
		var out := []
		for l in legs:
			out.append(Vector3(cx + l.x * w, y0 + hgt * t, z + l.z * w * 0.8))
		return out
	var n := maxi(int(hgt / 5.0), 2)
	var prev: Array = ring.call(0.0)
	for i in range(1, n + 1):
		var cur: Array = ring.call(float(i) / n)
		for j in 4:
			_st_cyl(st, prev[j], cur[j], 0.12, col, 6)
			var jn := (j + 1) % 4
			if j == 0 or j == 2:
				_st_cyl(st, prev[j], cur[jn], 0.05, col, 5)
				_st_cyl(st, prev[jn], cur[j], 0.05, col, 5)
			else:
				_st_cyl(st, prev[j], cur[jn], 0.05, col, 5)
			_st_cyl(st, cur[j], cur[jn], 0.06, col, 5)
		prev = cur
	# траверса и ролики под оба троса
	var top := Vector3(cx, y_top + 0.15, z)
	_box_v(st, top + Vector3(0.0, 0.25, 0.0), Vector3(LANE + 2.0, 0.3, 0.5), col)
	for lane in [0.0, 1.0]:
		var px: float = L.LIFT_X + lane * LANE
		_box_v(st, Vector3(px, y_top + 0.05, z), Vector3(0.14, 0.4, 1.4), steel)
		for zz in [-0.45, 0.0, 0.45]:
			_st_wheel(st, Vector3(px, y_top - 0.08, z + zz), Vector3.RIGHT, 0.13, 0.08, Color(0.12, 0.12, 0.14), steel)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.3
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "LiftTower"
	add_child(mi)


## Станция: площадка, рама, большой обводной шкив между тросами, будка
func _station(at: Vector3, top: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.55, 0.18, 0.12)
	var steel := Color(0.36, 0.38, 0.42)
	var wood := Color(0.42, 0.29, 0.18)
	var cy: float = (L.CABLE[0] as Vector2).y if not top else (L.CABLE[L.CABLE.size() - 1] as Vector2).y
	var cx := L.LIFT_X + LANE * 0.5
	var back := 1.0 if not top else -1.0        # шкив — с дальней от пропасти стороны
	var wz := at.z + back * 1.6
	var gy := at.y
	# настил под тросом (тут хватаются и сходят)
	_box_v(st, Vector3(cx - 0.5, gy - 0.25, at.z - back * 1.0), Vector3(7.0, 0.5, 6.5), wood)
	for i in 7:
		_box_v(st, Vector3(cx - 0.5, gy + 0.005, at.z - back * 1.0 - 3.0 + i * 1.0), Vector3(7.0, 0.02, 0.05), Color(0.3, 0.2, 0.12))
	# рама: четыре стойки и балка
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_st_cyl(st, Vector3(cx + sx * 2.6, gy - 0.3, wz + sz * 1.2), Vector3(cx + sx * 2.0, cy + 0.9, wz + sz * 0.8), 0.13, col, 8)
	_box_v(st, Vector3(cx, cy + 0.95, wz), Vector3(5.0, 0.35, 2.0), col)
	# шкив (лежит плашмя), вал, привод
	_st_wheel(st, Vector3(cx, cy, wz), Vector3.UP, LANE * 0.5, 0.18, Color(0.15, 0.15, 0.17), steel)
	_st_cyl(st, Vector3(cx, cy, wz), Vector3(cx, cy + 0.95, wz), 0.12, steel)
	_box_v(st, Vector3(cx + 1.6, cy + 1.45, wz), Vector3(1.4, 0.7, 1.0), Color(0.2, 0.32, 0.5))
	# перила по краю у пропасти
	if not top:
		for i in 6:
			var px := cx - 3.5 + i * 1.3
			_st_cyl(st, Vector3(px, gy, at.z - 4.3), Vector3(px, gy + 1.1, at.z - 4.3), 0.04, steel, 6)
		_st_cyl(st, Vector3(cx - 3.6, gy + 1.1, at.z - 4.3), Vector3(cx - 3.6 + 6.6, gy + 1.1, at.z - 4.3), 0.04, steel, 6)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.2
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "LiftStation"
	add_child(mi)
	# настил — твёрдый
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(7.0, 0.5, 6.5)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(cx - 0.5, gy - 0.25, at.z - back * 1.0)
	# будка оператора
	var hut := _box(Vector3(3.2, 2.6, 2.6), _mat(Color(0.55, 0.22, 0.16)))
	add_child(hut)
	hut.global_position = Vector3(cx + 6.0, _h(cx + 6.0, at.z + back * 2.0) + 1.3, at.z + back * 2.0)
	var roof := _box(Vector3(3.7, 0.3, 3.1), _snow_mat)
	add_child(roof)
	roof.global_position = hut.global_position + Vector3.UP * 1.45


func _build_tow() -> void:
	_tow_len = L.cable_len()
	var steel := _mat(Color(0.3, 0.31, 0.34), 0.4, 0.7)
	# трос: каждый отрезок ломаной, вверх и обратно
	for lane in [0.0, 1.0]:
		for i in L.CABLE.size() - 1:
			var a: Vector2 = L.CABLE[i]
			var b: Vector2 = L.CABLE[i + 1]
			var cab := _rod(Vector3(L.LIFT_X + lane * LANE, a.y, a.x), Vector3(L.LIFT_X + lane * LANE, b.y, b.x), 0.035, steel)
			cab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # тонкий длинный трос в тенях мерцал
	# опоры: в пропасти и на краю вершины
	_tower(L.TOWER_Z, (L.CABLE[1] as Vector2).y)
	_tower((L.CABLE[2] as Vector2).x, (L.CABLE[2] as Vector2).y)
	_station(L.lift_bottom(), false)
	_station(L.lift_top(), true)
	var bot := L.lift_bottom()
	_sign(Vector3(bot.x - 4.5, L.LEDGE_Y, bot.z + 4.5),
		"ПОДЪЁМНИК НА СНЕЖНУЮ ГОРУ\nВстань на настил под тросом\nи ДЕРЖИ E — повиснешь на перекладине.\nОтпустишь E над пропастью — сорвёшься!", Color(1.0, 0.85, 0.4))
	# перекладины по кругу (вверх — по ближнему тросу, вниз — по дальнему)
	_hanger_mesh = make_hanger_mesh()
	var count := int(_tow_len * 2.0 / HANGER_GAP)
	_hanger_mm = MultiMesh.new()
	_hanger_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hanger_mm.mesh = _hanger_mesh
	_hanger_mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _hanger_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "LiftHangers"
	add_child(mmi)


var _hanger_mesh: ArrayMesh


func _update_hangers(delta: float) -> void:
	var count := _hanger_mm.instance_count
	_hang_t += delta * TOW_V / (_tow_len * 2.0)
	# у кого перекладина в руках — пустые рядом не рисую (иначе едут бок о бок)
	var riders: Array[Vector3] = []
	for d in get_tree().get_nodes_in_group("player"):
		if d.get("snow") != null and int(d.snow.mpose) == 50:
			riders.append(d.snow.mpose_pt)
	for i in count:
		var u := fposmod(_hang_t + float(i) / count, 1.0)
		var up := u < 0.5
		var k := u * 2.0 if up else (1.0 - u) * 2.0
		var c := _cable(k, 0.0 if up else 1.0)
		var near_rider := false
		if up:
			for r in riders:
				if r.distance_to(c) < HANGER_GAP * 0.55:
					near_rider = true
		if near_rider:
			_hanger_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), c))
			continue
		var sw := sin(_hang_t * 40.0 + i * 1.7) * 0.05
		var b := Basis(Vector3.RIGHT, sw) if up else Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, sw)
		_hanger_mm.set_instance_transform(i, Transform3D(b, c))


# ---------------------------------------------------------------------------
#  Вершина: стойка сноубордов, ворота; трасса: вешки, гребень, финиш
# ---------------------------------------------------------------------------

func board_mesh() -> ArrayMesh:
	if _board_mesh != null:
		return _board_mesh
	_board_mesh = make_board_mesh()
	return _board_mesh


## Доска 1.6 × 0.3 м: середина плоская, носы загнуты; сверху — тёмная с оранжевыми полосами, скользяк светлый
static func make_board_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 24
	var ln := 1.6
	var w := 0.3
	var th := 0.03
	var pts: Array[Vector3] = []
	for i in nx + 1:
		var u := float(i) / nx * 2.0 - 1.0          # −1…1 по длине
		var tip := smoothstep(0.76, 1.0, absf(u))
		var hw := w * 0.5 * (1.0 - 0.5 * pow(smoothstep(0.84, 1.0, absf(u)), 2.0)) * (1.0 - 0.06 * (1.0 - absf(u)))
		pts.append(Vector3(u * ln * 0.5, tip * tip * 0.12, hw))
	# шаг 143: яркая доска — синяя, по всей длине белая полоса, нос оранжевый (сразу видно, куда смотрит)
	var top_c := Color(0.08, 0.32, 0.85)
	var lane_c := Color(0.95, 0.97, 1.0)
	var nose_c := Color(1.0, 0.42, 0.05)
	var tail_c := Color(0.05, 0.16, 0.45)
	for i in nx:
		var a := pts[i]
		var b := pts[i + 1]
		var u := (float(i) + 0.5) / nx * 2.0 - 1.0
		var c := top_c
		if u > 0.7:
			c = nose_c
		elif u < -0.76:
			c = tail_c
		# три полосы поперёк: синяя | белая | синяя
		for k in 3:
			var f0: float = [-1.0, -0.28, 0.28][k]
			var f1: float = [-0.28, 0.28, 1.0][k]
			var cc := lane_c if (k == 1 and u > -0.76 and u <= 0.7) else c
			_quad(st, Vector3(a.x, a.y + th, a.z * f0), Vector3(b.x, b.y + th, b.z * f0), Vector3(b.x, b.y + th, b.z * f1), Vector3(a.x, a.y + th, a.z * f1), cc)
		_quad(st, Vector3(a.x, a.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, -b.z), Vector3(a.x, a.y, -a.z), Color(0.8, 0.82, 0.88))
		for sgn in [-1.0, 1.0]:
			var p0 := Vector3(a.x, a.y, a.z * sgn)
			var p1 := Vector3(b.x, b.y, b.z * sgn)
			_quad(st, p0, p1, p1 + Vector3.UP * th, p0 + Vector3.UP * th, Color(0.75, 0.75, 0.78))
	# торцы носов
	for e in [0, nx]:
		var q: Vector3 = pts[e]
		_quad(st, Vector3(q.x, q.y, -q.z), Vector3(q.x, q.y, q.z), Vector3(q.x, q.y + th, q.z), Vector3(q.x, q.y + th, -q.z), Color(0.75, 0.75, 0.78))
	# крепления: пятка-хайбэк и ремни
	for sx in [-0.27, 0.27]:
		_box_v(st, Vector3(sx, th + 0.02, 0.0), Vector3(0.2, 0.04, 0.26), Color(0.95, 0.5, 0.1))
		_box_v(st, Vector3(sx, th + 0.12, 0.12), Vector3(0.18, 0.2, 0.03), Color(0.2, 0.2, 0.22))
		_box_v(st, Vector3(sx, th + 0.08, -0.03), Vector3(0.21, 0.03, 0.06), Color(0.2, 0.2, 0.22))
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)


static func _box_v(st: SurfaceTool, c: Vector3, sz: Vector3, col: Color) -> void:
	var h := sz * 0.5
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col)


func _build_top() -> void:
	# шаг 143: стойка — прямо перед выходом с подъёмника, на пути к старту
	_rack_pos = Vector3(-5.5, 0.0, -44.0)
	_rack_pos.y = _h(_rack_pos.x, _rack_pos.z)
	var wood := _mat(Color(0.45, 0.3, 0.18))
	var rack := _box(Vector3(4.6, 0.12, 0.6), wood)
	add_child(rack)
	rack.global_position = _rack_pos + Vector3.UP * 1.25
	for sx in [-2.2, 2.2]:
		var leg := _box(Vector3(0.12, 1.3, 0.5), wood)
		add_child(leg)
		leg.global_position = _rack_pos + Vector3(sx, 0.65, 0.0)
	for i in 6:
		var b := MeshInstance3D.new()
		b.mesh = board_mesh()
		add_child(b)
		b.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 0.12), _rack_pos + Vector3(-1.8 + i * 0.72, 0.85, 0.22))
	# вывеска над стойкой и флажки — видно сразу, как сходишь с подъёмника
	var orange := _mat(Color(1.0, 0.45, 0.08))
	for sx in [-2.6, 2.6]:
		_rod(_rack_pos + Vector3(sx, 0.0, -0.2), _rack_pos + Vector3(sx, 3.6, -0.2), 0.07, orange)
	var banner := _box(Vector3(5.6, 0.8, 0.08), orange)
	add_child(banner)
	banner.global_position = _rack_pos + Vector3(0.0, 3.3, -0.2)
	var bl := Label3D.new()
	bl.text = "СНОУБОРДЫ  ·  E"
	bl.font_size = 72
	bl.outline_size = 10
	add_child(bl)
	bl.global_position = banner.global_position + Vector3(0.0, 0.0, 0.06)
	var bl2 := bl.duplicate() as Label3D
	add_child(bl2)
	bl2.global_position = banner.global_position + Vector3(0.0, 0.0, -0.06)
	bl2.rotation.y = PI
	_sign(_rack_pos + Vector3(-3.8, 0.0, 1.2),
		"СНОУБОРДЫ — E: взять доску\nA/D — повороты, S — тормоз\nW — разогнаться\nПробел — прыжок, в воздухе:\nA/D — вращение, W — захват\nE на месте — снять доску", Color(0.6, 0.95, 1.0))


func _build_course() -> void:
	# вешки по краям трассы (оранжевые слева, синие справа)
	var mo := MultiMesh.new()
	var mb := MultiMesh.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.05
	pole.height = 2.2
	for mm in [mo, mb]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pole
	var a: Array[Transform3D] = []
	var b: Array[Transform3D] = []
	var s := 12.0
	var tot := L.total()
	while s < L.FINISH_S:
		var rk := L.ridge_k(s)
		var w := L.half_w(s) - 1.0 if rk < 0.5 else L.RIDGE_HALF - 0.6
		for sd in [-1.0, 1.0]:
			var p := _pt(s, sd * w)
			var t := Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
			if sd < 0.0:
				a.append(t)
			else:
				b.append(t)
		s += 18.0 if rk < 0.5 else 8.0
	mo.instance_count = a.size()
	mb.instance_count = b.size()
	for i in a.size():
		mo.set_instance_transform(i, a[i])
	for i in b.size():
		mb.set_instance_transform(i, b[i])
	for pair in [[mo, Color(1.0, 0.4, 0.05)], [mb, Color(0.15, 0.4, 1.0)]]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = pair[0]
		mi.material_override = _mat(pair[1])
		add_child(mi)
	# таблички (справа от трассы)
	_sign(_pt(92.0, L.HALF_W + 2.0), "ЛЕС\nЁлки и брёвна прямо на трассе!\nОбъезжай (A/D), бревно — перепрыгни (Пробел)", Color(0.7, 1.0, 0.6))
	for i in [2, 3, 4]:
		var sc := L.s_of_corner(i)
		_sign(_pt(sc - 70.0, -(L.HALF_W + 2.0)), "ШПИЛЬКА!\nКрутой поворот — тормози (S)", Color(1.0, 0.6, 0.3))
	_sign(_pt(L.CHASE_S.x - 15.0, -(L.half_w(L.CHASE_S.x - 15.0) + 2.0)), "ОСТОРОЖНО: КОМЫ!\nШирокий склон. Сзади катятся снежные комы\nи гонятся за тобой ~200 м.\nУходи резко в сторону!", Color(1.0, 0.8, 0.4))
	# финиш
	var blue := _mat(Color(0.15, 0.4, 1.0))
	for sx in [-10.0, 10.0]:
		var p2 := _pt(L.FINISH_S, sx)
		_rod(p2, p2 + Vector3.UP * 4.6, 0.14, blue)
	var fl := Label3D.new()
	fl.text = "ФИНИШ"
	fl.font_size = 110
	fl.outline_size = 10
	add_child(fl)
	var f0 := _pt(L.FINISH_S)
	fl.global_position = f0 + Vector3.UP * 4.4
	var fd := _fw(L.FINISH_S)
	fl.rotation.y = atan2(fd.x, fd.z)


# ---------------------------------------------------------------------------
#  Лес (шаг 142): весь склон в ёлках (Quaternius, CC0) — кусками по 64 м; вблизи — модели,
#  вдали — простые ёлки. На трассе — ёлки и брёвна в лесной части. У каждой ёлки — ствол-опора.
# ---------------------------------------------------------------------------

const NATURE := "res://assets/hill_nature/"
const PINES := ["PineTree_Snow_1", "PineTree_Snow_2", "PineTree_Snow_4", "PineTree_Snow_5"]
const DEAD := ["CommonTree_Dead_Snow_1"]
const DECOR := ["TreeStump_Snow", "Bush_Snow_1", "Bush_Snow_2", "Rock_Snow_3", "Rock_Snow_6"]
const CHUNK := 64.0
## нижние ветки у ёлок Quaternius (в долях масштаба): у 1-й и 2-й лапы до земли, у 4-й и 5-й — высоко
const PINE_LOW_R := {"PineTree_Snow_1": 0.85, "PineTree_Snow_2": 0.8, "PineTree_Snow_4": 0.3, "PineTree_Snow_5": 0.22}
const NEAR_R := 95.0

var _nature := {}                ## модель → Mesh (с нашими материалами)
var _chunks := {}                ## Vector2i → {"near": {модель: [xf]}, "far": [xf], "cols": [Vector4]}
var _far_mesh: ArrayMesh


## Модель Quaternius (CC0) с материалами под гору: снег белый, хвоя тёмная, кора
func _nat(name: String) -> Mesh:
	if _nature.has(name):
		return _nature[name]
	var src: Mesh = load(NATURE + name + ".obj")
	var m := src.duplicate() as Mesh
	for i in m.get_surface_count():
		var sm := src.surface_get_material(i)
		var nm: String = sm.resource_name if sm else ""
		m.surface_set_material(i, _nat_mat(nm))
	_nature[name] = m
	return m


var _nat_mats := {}
func _nat_mat(nm: String) -> Material:
	if _nat_mats.has(nm):
		return _nat_mats[nm]
	var mt := StandardMaterial3D.new()
	match nm:
		"Snow":
			mt.albedo_color = Color(0.9, 0.93, 0.98)
			mt.roughness = 0.85
		"Green":
			mt.albedo_color = Color(0.07, 0.17, 0.1)
			mt.roughness = 0.95
		"Wood":
			mt.albedo_color = Color(0.25, 0.16, 0.1)
			mt.roughness = 0.95
		_:
			mt.albedo_color = Color(0.3, 0.31, 0.35)
			mt.roughness = 0.9
	_nat_mats[nm] = mt
	return mt


## Дальняя ёлка: три конуса хвои со снежными шапками (~100 треугольников)
func _make_far() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 2.0
	trunk.radial_segments = 4
	trunk.rings = 0
	trunk.cap_top = false
	trunk.cap_bottom = false
	st.set_color(Color(0.25, 0.16, 0.1))
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	for i in 3:
		var k := float(i) / 3.0
		var r := lerpf(2.7, 1.0, k)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r
		cone.height = 3.2
		cone.radial_segments = 6
		cone.rings = 0
		cone.cap_top = false
		var y := 1.6 + i * 2.0
		st.set_color(Color(0.07, 0.17, 0.1))
		st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, y + 1.6, 0)))
		var cap := CylinderMesh.new()
		cap.top_radius = 0.0
		cap.bottom_radius = r * 0.8
		cap.height = 1.7
		cap.radial_segments = 6
		cap.rings = 0
		cap.cap_top = false
		cap.cap_bottom = false
		st.set_color(Color(0.9, 0.93, 0.98))
		st.append_from(cap, 0, Transform3D(Basis.IDENTITY, Vector3(0, y + 2.45, 0)))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	st.set_material(m)
	st.generate_normals()
	return st.commit()


func _chunk_of(x: float, z: float) -> Dictionary:
	var key := Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))
	if not _chunks.has(key):
		_chunks[key] = {"near": {}, "far": [], "cols": []}
	return _chunks[key]


func _put(name: String, xf: Transform3D, far := false, col_r := 0.0) -> void:
	var ch := _chunk_of(xf.origin.x, xf.origin.z)
	var nd: Dictionary = ch["near"]
	if not nd.has(name):
		nd[name] = []
	(nd[name] as Array).append(xf)
	if far:
		# дальняя ёлка такой же высоты
		(ch["far"] as Array).append(Transform3D(xf.basis * Basis.from_scale(Vector3(0.42, 0.33, 0.42)), xf.origin))
	if col_r > 0.0:
		(ch["cols"] as Array).append(Vector4(xf.origin.x, xf.origin.y, xf.origin.z, col_r))


func _near_kicker(s: float) -> bool:
	for k in L.KICKERS_S:
		if absf(s - float(k)) < 24.0:
			return true
	return false


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14201
	_far_mesh = _make_far()
	var step := 10.0
	var x := -378.0
	while x <= 378.0:
		var z := -44.0
		while z >= -650.0:
			var px := x + rng.randf_range(-4.5, 4.5)
			var pz := z + rng.randf_range(-4.5, 4.5)
			z -= step
			var glade := rng.randf()
			var pick := rng.randi()
			var sc := rng.randf_range(3.3, 5.2)
			var yaw := rng.randf() * TAU
			var keep := rng.randf()
			if glade < 0.1:
				continue                                # полянки
			if pz > -58.0 and absf(px) < 50.0:
				continue                                # вершина, старт
			var nr: Array = L.near(px, pz)
			var d := absf(float(nr[0]))
			var s: float = nr[1]
			if d < L.half_w(s) + 1.5:
				# на трассе: только в лесной части и редко
				if L.forest_k(s) < 0.5 or keep > 0.2 or _near_kicker(s):
					continue
			elif L.wide_k(s) > 0.3 and d < L.half_w(s) + 8.0:
				continue                                # шаг 144: широкий склон комов — простор по краям
			if s > L.FINISH_S - 30.0 and d < 40.0:
				continue
			var y := _h(px, pz)
			if pick % 9 == 0:
				_put(DEAD[0], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc * 0.85), Vector3(px, y - 0.2, pz)), false, 0.25 * sc)
			else:
				# шаг 143: опора — ствол с нижними ветками (сквозь ёлку не пройти и не проехать)
				var pn: String = PINES[pick % PINES.size()]
				if d < L.half_w(s) + 4.0:
					pn = PINES[2 + pick % 2]          # на трассе — стройные ёлки (лапы высоко)
				_put(pn, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(px, y - 0.2, pz)), true, PINE_LOW_R.get(pn, 0.3) * sc)
		x += step
	# по краям трассы — пни, кусты, камни
	var s2 := 20.0
	while s2 < L.FINISH_S:
		for sd in [-1.0, 1.0]:
			if rng.randf() < 0.45:
				var q := _pt(s2 + rng.randf_range(-6.0, 6.0), sd * (L.half_w(s2) + rng.randf_range(1.5, 6.0)))
				var dn: String = DECOR[rng.randi() % DECOR.size()]
				var dsc := rng.randf_range(1.2, 2.0)
				_put(dn, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * dsc), q + Vector3.DOWN * 0.1), false,
					0.0 if dn.begins_with("Bush") else 0.5 * dsc)
		s2 += 14.0
	# поваленные брёвна поперёк трассы в лесу (перепрыгни — Пробел, или объедь)
	for ls in [150.0, 215.0, 340.0, 410.0, 480.0, 545.0, 615.0, 665.0]:
		var dd := rng.randf_range(-11.0, 11.0)
		var q2 := _pt(ls, dd)
		var t := L.dir(ls)
		var lyaw := atan2(-t.y, t.x) + rng.randf_range(-0.3, 0.3)
		var lsc := rng.randf_range(2.0, 2.6)
		_put("WoodLog_Snow", Transform3D(Basis(Vector3.UP, lyaw).scaled(Vector3(lsc, 1.3, lsc)), q2 + Vector3.DOWN * 0.15))
		var body := StaticBody3D.new()
		body.add_to_group("hill_tree")
		body.set_meta("log", true)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6 * lsc, 0.6, 2.3 * lsc)
		cs.shape = bs
		body.add_child(cs)
		add_child(body)
		body.global_transform = Transform3D(Basis(Vector3.UP, lyaw), q2 + Vector3.UP * 0.2)
	# узлы: на кусок — по модели вблизи, одна дальняя; опоры — одним телом на кусок
	for key in _chunks:
		var ch: Dictionary = _chunks[key]
		var center := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		center.y = _h(center.x, center.z)
		var nd: Dictionary = ch["near"]
		for name in nd:
			var arr: Array = nd[name]
			var mi := _mm(_nat(name), arr, center)
			mi.visibility_range_end = NEAR_R if (name in PINES or name in DEAD) else NEAR_R * 0.8
			mi.visibility_range_end_margin = 6.0
		var far: Array = ch["far"]
		if not far.is_empty():
			var fm := _mm(_far_mesh, far, center)
			fm.visibility_range_begin = NEAR_R - 6.0
			fm.visibility_range_begin_margin = 6.0
			fm.visibility_range_end = 1400.0
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cols: Array = ch["cols"]
		if not cols.is_empty():
			var body2 := StaticBody3D.new()
			body2.add_to_group("hill_tree")
			add_child(body2)
			for c in cols:
				var v4: Vector4 = c
				var cs2 := CollisionShape3D.new()
				var sh := CylinderShape3D.new()
				sh.radius = v4.w
				sh.height = 4.0
				cs2.shape = sh
				body2.add_child(cs2)
				cs2.global_position = Vector3(v4.x, v4.y + 1.8, v4.z)


func _mm(mesh: Mesh, arr: Array, center: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = arr.size()
	for i in arr.size():
		var xf: Transform3D = arr[i]
		mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - center))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	mi.global_position = center
	return mi


# ---------------------------------------------------------------------------
#  Трамплины: вал из снега поперёк трассы, крутизна у кромки ~30°, синяя кромка
# ---------------------------------------------------------------------------

func _build_kickers() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.97, 1.0)
	m.roughness = 0.85
	var tex = load("res://assets/avalanche/snow_debris_color.jpg") if ResourceLoader.exists("res://assets/avalanche/snow_debris_color.jpg") else null
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.3, 0.3, 0.3)
	for kz in L.KICKERS_S:
		var s0: float = kz
		var hgt := 2.2 if s0 < 200.0 else 2.6
		var ln := 7.5
		var half := 4.5
		var nu := 10
		var nv := 4
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		for i in nu + 1:
			var u := float(i) / nu
			var prof := hgt * pow(u, 1.7)
			for j in nv + 1:
				var v := float(j) / nv * 2.0 - 1.0
				var edge := 1.0 - pow(absf(v), 6.0)
				var p := _pt(s0 - ln * 0.5 + u * ln, v * half)
				verts.append(p + Vector3.UP * (prof * edge - 0.05))
		for i in nu:
			for j in nv:
				var a := i * (nv + 1) + j
				var b := a + 1
				var c := a + nv + 1
				var d := c + 1
				idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
		var base := verts.size()
		var fwd := _fw(s0)
		for j in nv + 1:
			var tv: Vector3 = verts[nu * (nv + 1) + j]
			var bp := tv + fwd * 0.4
			verts.append(Vector3(bp.x, _h(bp.x, bp.z) - 0.3, bp.z))
		for j in nv:
			var a2 := nu * (nv + 1) + j
			idx.append_array(PackedInt32Array([a2, base + j, a2 + 1, a2 + 1, base + j, base + j + 1]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_INDEX] = idx
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_normals()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		add_child(body)
		# синяя полоса по кромке
		var lip_c := _pt(s0 + ln * 0.5 - 0.12)
		var lip := _box(Vector3(half * 2.0 - 0.6, 0.06, 0.25), _mat(Color(0.1, 0.35, 0.95)))
		add_child(lip)
		lip.global_transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), lip_c + Vector3.UP * (hgt - 0.02))
		for sd in [-1.0, 1.0]:
			var fp := _pt(s0 + ln * 0.5, sd * (half + 0.6))
			_rod(fp, fp + Vector3.UP * 2.0, 0.05, _mat(Color(1.0, 0.85, 0.1)))


# ---------------------------------------------------------------------------
#  Снежные комы (шаг 142): на участке CHASE_S сзади один за другим скатываются комы и наводятся
#  на ближайшего райдера; за ~14 м до него наводка «застывает» — успей резко свернуть.
#  Катит сервер, остальным — 15 раз в секунду (s, смещение, радиус).
# ---------------------------------------------------------------------------

func _build_balls() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.94, 0.96, 1.0)
	m.roughness = 0.95
	if ResourceLoader.exists("res://assets/avalanche/snow_debris_color.jpg"):
		m.albedo_texture = load("res://assets/avalanche/snow_debris_color.jpg")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/avalanche/snow_debris_normal.jpg")
		m.uv1_scale = Vector3(2.0, 1.0, 1.0)
	var pm := QuadMesh.new()
	pm.size = Vector2(0.6, 0.6)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(1, 1, 1, 0.8)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.material = pmat
	for i in BALLS:
		var root := Node3D.new()
		add_child(root)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 20
		sm.rings = 12
		mi.mesh = sm
		mi.material_override = m
		root.add_child(mi)
		var fx := CPUParticles3D.new()
		fx.amount = 50
		fx.lifetime = 1.2
		fx.emitting = false
		fx.local_coords = false
		fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fx.emission_sphere_radius = 2.0
		fx.direction = Vector3.UP
		fx.spread = 70.0
		fx.initial_velocity_min = 2.0
		fx.initial_velocity_max = 6.0
		fx.gravity = Vector3(0, -6, 0)
		fx.scale_amount_min = 0.4
		fx.scale_amount_max = 1.2
		fx.mesh = pm
		root.add_child(fx)
		root.visible = false
		_ball_nodes.append([root, mi, fx])
		_balls.append({"on": false, "s": 0.0, "lat": 0.0, "r": 2.5, "v": 0.0, "ts": 0.0, "tl": 0.0, "tr": 2.5})


## Кто на доске на участке комов: [игрок, s, d, скорость]
func _riders_in_chase() -> Array:
	var out := []
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead or d.get("snow") == null:
			continue
		var p: Vector3 = (d as Node3D).global_position
		if p.z > -380.0 or p.z < -620.0:
			continue
		var nr: Array = L.near(p.x, p.z)
		var s: float = nr[1]
		if s < L.CHASE_S.x - 20.0 or s > L.CHASE_S.y + 40.0 or absf(float(nr[0])) > L.half_w(s) + 12.0:
			continue
		out.append([d, s, float(nr[0]), Vector3(d.velocity.x, 0.0, d.velocity.z).length()])
	return out


func _balls_server(delta: float) -> void:
	var riders := _riders_in_chase()
	_ball_spawn_t -= delta
	if _ball_spawn_t <= 0.0 and not riders.is_empty():
		var r0: Array = riders[randi() % riders.size()]
		if float(r0[1]) < L.CHASE_S.y - 40.0 and int(r0[0].snow.climb) == 51:
			for b in _balls:
				if not bool(b["on"]):
					b["on"] = true
					b["s"] = maxf(float(r0[1]) - 40.0, L.CHASE_S.x - 60.0)
					b["lat"] = float(r0[2])
					b["r"] = randf_range(2.3, 3.4)
					b["v"] = maxf(float(r0[3]) + 6.0, 16.0)
					b["run"] = 0.0
					SFX.play(self, _pt(float(b["s"]), float(b["lat"])) + Vector3.UP * 3.0, "snowslide", 2.0, 0.7)
					break
			_ball_spawn_t = randf_range(3.6, 5.6)
	for b in _balls:
		if not bool(b["on"]):
			continue
		var bs: float = b["s"]
		# цель — ближайший впереди
		var tgt: Array = []
		for r in riders:
			var ds := float(r[1]) - bs
			if ds > -2.0 and ds < 160.0 and (tgt.is_empty() or ds < float(tgt[1]) - bs):
				tgt = r
		var v: float = b["v"]
		# шаг 144: первые ~200 м ком гонится за райдером (повторяет повороты), дальше катится сам — прямо
		var chasing: bool = float(b.get("run", 0.0)) < BALL_CHASE
		if chasing and not tgt.is_empty():
			var ds2 := float(tgt[1]) - bs
			v = move_toward(v, clampf(float(tgt[3]) + (12.0 if ds2 > 20.0 else 5.0), 15.0, 42.0), 8.0 * delta)
			if ds2 > 5.0:
				var hw := L.half_w(bs) - 2.0
				b["lat"] = move_toward(float(b["lat"]), clampf(float(tgt[2]), -hw, hw), 9.0 * delta)
		else:
			v = move_toward(v, 22.0, 3.0 * delta)
		b["v"] = v
		b["s"] = bs + v * delta
		b["run"] = float(b.get("run", 0.0)) + v * delta
		b["r"] = minf(float(b["r"]) + 0.12 * delta, 4.4)
		if float(b["s"]) > L.CHASE_S.y + 70.0:
			b["on"] = false
	_ball_send_t -= delta
	if _ball_send_t <= 0.0:
		_ball_send_t = 1.0 / 15.0
		var pk := PackedFloat32Array()
		for b in _balls:
			pk.append_array(PackedFloat32Array([1.0 if bool(b["on"]) else 0.0, float(b["s"]), float(b["lat"]), float(b["r"])]))
		if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.get_peers().size() > 0:
			_balls_sync.rpc(pk)


@rpc("authority", "call_remote", "unreliable_ordered")
func _balls_sync(pk: PackedFloat32Array) -> void:
	for i in mini(_balls.size(), pk.size() / 4):
		var b: Dictionary = _balls[i]
		var on := pk[i * 4] > 0.5
		if on and not bool(b["on"]):
			b["s"] = pk[i * 4 + 1]
			b["lat"] = pk[i * 4 + 2]
		b["on"] = on
		b["ts"] = pk[i * 4 + 1]
		b["tl"] = pk[i * 4 + 2]
		b["r"] = pk[i * 4 + 3]


func _balls_process(delta: float) -> void:
	var server := multiplayer.is_server()
	if server:
		_balls_server(delta)
	for i in _balls.size():
		var b: Dictionary = _balls[i]
		var nodes: Array = _ball_nodes[i]
		var root: Node3D = nodes[0]
		var on: bool = b["on"]
		if root.visible != on:
			root.visible = on
			(nodes[2] as CPUParticles3D).emitting = on
			if not on:
				SFX.play(self, root.global_position, "crunch", 2.0, 0.6)
		if not on:
			continue
		if not server:
			# у клиента — догоняю присланное (и чуть вперёд)
			b["ts"] = float(b["ts"]) + 20.0 * delta
			b["s"] = lerpf(float(b["s"]), float(b["ts"]), clampf(delta * 8.0, 0.0, 1.0))
			b["lat"] = lerpf(float(b["lat"]), float(b["tl"]), clampf(delta * 8.0, 0.0, 1.0))
		var r: float = b["r"]
		var prev := root.global_position
		var pos := _pt(float(b["s"]), float(b["lat"])) + Vector3.UP * r * 0.9
		root.global_position = pos
		var mi: MeshInstance3D = nodes[1]
		mi.scale = Vector3.ONE * r
		(nodes[2] as CPUParticles3D).emission_sphere_radius = r
		var mv := pos - prev
		mv.y = 0.0
		if mv.length() > 0.01 and mv.length() < 5.0:
			mi.rotate(mv.normalized().cross(Vector3.UP).normalized(), -mv.length() / r)
		# сбивает (у себя — сам игрок, боты — на сервере)
		for d in get_tree().get_nodes_in_group("player"):
			if not d.is_local or d.is_dead:
				continue
			var dp: Vector3 = d.global_position + Vector3.UP * 0.9
			if dp.distance_to(pos) < r + 0.55 and int(d.snow.climb) != 52:
				knock(d, _fw(float(b["s"])) * minf(float(b["v"]) if server else 20.0, 14.0) + Vector3.UP * 5.0, true)


# ---------------------------------------------------------------------------
#  HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_hud_speed = Label.new()
	_hud_speed.add_theme_font_size_override("font_size", 26)
	_hud_speed.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_speed.add_theme_constant_override("outline_size", 6)
	# шаг 143: скорость — внизу справа (посередине внизу теперь видно доску)
	_hud_speed.anchor_left = 1.0
	_hud_speed.anchor_right = 1.0
	_hud_speed.anchor_top = 1.0
	_hud_speed.anchor_bottom = 1.0
	_hud_speed.offset_left = -300.0
	_hud_speed.offset_right = -40.0
	_hud_speed.offset_top = -90.0
	_hud_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_hud_speed)
	_hud_trick = Label.new()
	_hud_trick.add_theme_font_size_override("font_size", 46)
	_hud_trick.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_hud_trick.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_trick.add_theme_constant_override("outline_size", 10)
	_hud_trick.anchor_left = 0.5
	_hud_trick.anchor_right = 0.5
	_hud_trick.anchor_top = 0.3
	_hud_trick.anchor_bottom = 0.3
	_hud_trick.offset_left = -400.0
	_hud_trick.offset_right = 400.0
	_hud_trick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_hud_trick)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -420.0
	_hint.offset_right = 420.0
	_hint.offset_top = -190.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_hint)


func _trick(txt: String) -> void:
	_hud_trick.text = txt
	_trick_t = 1.8


func say(txt: String, t := 0.3) -> void:
	_hint.text = txt
	_hint_t = t


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_hangers(delta)
	_balls_process(delta)
	var me: Node3D = Network.local_player
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_local or d.is_dead or d.get("snow") == null:
			continue
		if d.global_position.z > L.Z_FOOT + 30.0 or d.global_position.z < L.Z_END - 20.0:
			continue
		_local_player(d, d == me)
	_catch_up_bots()


## Перекладины тех, кто висит на подъёмнике. Ставлю каждый кадр отрисовки по ТЕЛУ (оно плавно сглажено
## между кадрами физики): руки и перекладина не «разъезжаются» — от 1-го лица ничего не дёргается
func _rider_bars_update() -> void:
	var n := 0
	for d2 in get_tree().get_nodes_in_group("player"):
		if d2.get("snow") != null and int(d2.snow.mpose) == 50:
			if n >= _rider_bars.size():
				var hb := MeshInstance3D.new()
				hb.mesh = _hanger_mesh
				hb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(hb)
				_rider_bars.append(hb)
			var vis: Node3D = d2.visual
			var bar_c: Vector3 = vis.global_transform * Vector3(0.0, L.HANG, 0.0)
			var bar2 := _rider_bars[n]
			bar2.visible = true
			var dv: Vector3 = d2.snow.mpose_dir
			var yaw := atan2(-dv.x, -dv.z) if Vector2(dv.x, dv.z).length() > 0.01 else 0.0
			bar2.global_transform = Transform3D(Basis(Vector3.UP, yaw), bar_c + Vector3.UP * L.ROD)
			n += 1
	for i in range(n, _rider_bars.size()):
		_rider_bars[i].visible = false


func _rod_basis(a: Vector3, b: Vector3) -> Basis:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


func _process(delta: float) -> void:
	_rider_bars_update()
	_trick_t -= delta
	_hud_trick.visible = _trick_t > 0.0
	if _trick_t > 0.0:
		_hud_trick.modulate.a = clampf(_trick_t / 0.4, 0.0, 1.0)
	_hint_t -= delta
	_hint.visible = _hint_t > 0.0
	var me = Network.local_player
	var riding: bool = me != null and is_instance_valid(me) and int(me.snow.climb) == 51
	_hud_speed.visible = riding
	if riding:
		_hud_speed.text = "%d км/ч" % roundi(Vector3(me.velocity.x, 0.0, me.velocity.z).length() * 3.6)


func _local_player(d: Node3D, is_me: bool) -> void:
	var p := d.global_position
	var busy: bool = d.snow.busy()
	# сорвался в пропасть
	if L.over_chasm(p) and p.y < L.CHASM_Y + 32.0 and not busy:
		d.kill("Сорвался в пропасть!\nНа подъёмнике держи E до самой вершины")
		return
	# подъёмник: на настиле под тросом держи E — повиснешь на перекладине
	var bot := L.lift_bottom()
	if not busy and d.is_on_floor() and absf(p.x - bot.x) < 1.6 and absf(p.z - bot.z) < 2.6:
		if is_me:
			say("Держи E — схватиться за перекладину")
		if d._held("interact"):
			d.snow.start_scripted(50, self, {"k": clampf((bot.z - p.z) / _tow_len, 0.0, 0.01), "sw": 0.0, "swv": -0.9, "from": p})
			if is_me and d.fp_view:
				# от 1-го лица взгляд — вдоль троса вверх: видно перекладину с руками и вершину
				d.camera_pivot.rotation.y = 0.0
				d.camera_pivot.rotation.x = 0.5
			SFX.play(self, p + Vector3.UP * 2.0, "clank", -6.0, 1.1)
			return
	elif not busy and is_me and Vector2(p.x - bot.x - 1.5, p.z - bot.z).length() < 7.0:
		say("Подъёмник: встань под тросом (на настиле) и держи E", 0.2)
	# стойка сноубордов
	if not busy and Vector2(p.x - _rack_pos.x, p.z - _rack_pos.z).length() < 3.0:
		if is_me:
			say("E — взять сноуборд")
		if d._just("interact"):
			start_board(d, Vector3.ZERO)
			return
	if busy:
		return
	# слетевшая доска рядом — E: встать на неё
	for id in _loose:
		var lb: RigidBody3D = _loose[id]
		if is_instance_valid(lb) and lb.global_position.distance_to(p + Vector3.UP * 0.5) < 2.3:
			if is_me:
				say("E — встать на доску", 0.2)
			if d._just("interact"):
				if _online():
					_take_loose.rpc(int(id))
				else:
					_take_loose(int(id))
				start_board(d, Vector3.ZERO)
			return
	# на вершине без доски — подсказка
	if is_me and p.z < L.Z_TOP and p.z > L.Z_START - 4.0:
		say("Сноуборды — у оранжевой вывески впереди (E)", 0.2)


## Бот отстал (хозяин уехал на подъёмнике / на доске) — переношу к хозяину
func _catch_up_bots() -> void:
	if not multiplayer.is_server():
		return
	if Engine.get_physics_frames() % 30 != 0:
		return
	for b in get_tree().get_nodes_in_group("player"):
		if not bool(b.get("is_bot")) or b.is_dead:
			continue
		var bcl := int(b.snow.climb)
		if b.snow.busy() and bcl != 51:
			continue
		var br = b.get_node_or_null("Brain")
		if br == null or not br.has_method("_owner"):
			continue
		var o = br._owner()
		if o == null or o == b or not is_instance_valid(o):
			continue
		var op: Vector3 = (o as Node3D).global_position
		if not L.on_hill(op) or op.z > L.Z_FOOT - 4.0:
			continue
		var oc := int(o.snow.climb)
		var bd2 := (b as Node3D).global_position.distance_to(op)
		if bcl == 51:
			if oc == 51 and bd2 > 30.0:
				b.snow.end_scripted()
			else:
				continue
		if oc == 50:
			# хозяин на подъёмнике — бот цепляется следом (сам не отпускает)
			var lb := L.lift_bottom()
			if b.global_position.distance_to(lb) > 3.0:
				b.teleport_to(lb + Vector3(0.0, 0.4, 0.0))
			b.snow.start_scripted(50, self, {"k": maxf(float(o.snow._cl_data.get("k", 0.0)) - 0.06, 0.0), "sw": 0.0, "swv": -0.6, "from": lb})
			continue
		if L.over_chasm(op) or (op.z < L.CHASM_S and op.z > L.Z_TOP and oc != 51):
			continue                      # хозяин над пропастью — к нему не переносить
		if oc == 51 and bd2 > 10.0:
			var bk := Vector3(o.velocity.x, 0.0, o.velocity.z)
			bk = -bk.normalized() * 6.0 + Vector3(3.0, 0.0, 0.0) if bk.length() > 1.0 else Vector3(3.0, 0.0, 5.0)
			var to2 := op + bk
			to2.y = _h(to2.x, to2.z) + 0.3
			b.teleport_to(to2)
			start_board(b, Vector3(o.velocity.x, 0.0, o.velocity.z) * 0.9, float(o.snow._cl_data.get("h", 0.0)))
			continue
		if oc == 51 and bd2 <= 10.0:
			start_board(b, Vector3(o.velocity.x, 0.0, o.velocity.z) * 0.5, float(o.snow._cl_data.get("h", 0.0)))
			continue
		if bd2 > 32.0:
			var back := Vector3(o.velocity.x, 0.0, o.velocity.z)
			back = -back.normalized() * 4.0 if back.length() > 1.0 else Vector3(0, 0, 4.0)
			var to := op + back
			to.y = _h(to.x, to.z) + 0.4
			b.teleport_to(to)


# ---------------------------------------------------------------------------
#  Сноуборд и подъёмник: сценарии (snow_state.drive)
# ---------------------------------------------------------------------------

func start_board(d: Node3D, v: Vector3, heading := NAN) -> void:
	if d.snow.busy():
		d.snow.end_scripted()
	var h := heading
	if is_nan(h):
		if v.length() > 0.5:
			h = atan2(-v.x, -v.z)
		else:
			# нос — вниз по трассе
			var dp := d.global_position
			var nr: Array = L.near(dp.x, dp.z)
			var fwd := _fw(float(nr[1]) + 4.0)
			h = atan2(-fwd.x, -fwd.z)
	d.snow.start_scripted(51, self, {"h": h, "v": v, "air": false, "spin": 0.0, "grab": 0.0, "air_t": 0.0, "edge": 0.0})
	d.velocity = v
	if d == Network.local_player:
		say("На доске! A/D — повороты, S — тормоз, Пробел — прыжок", 2.5)


func knock(d: Node3D, impulse: Vector3, from_ball := false, lose_board := false) -> void:
	if not d.is_local:
		_rpc_knock.rpc_id(d.get_multiplayer_authority(), int(d.peer_id), impulse)
		return
	var had := int(d.snow.climb) == 51 or bool(d.snow._cl_data.get("board", false))
	if int(d.snow.climb) == 52:
		return
	d.snow.end_scripted()
	d.snow.start_scripted(52, self, {"v": impulse, "board": had and not lose_board, "lost": had and lose_board})
	d.velocity = impulse
	SFX.play(self, d.global_position, "crunch", -2.0, 0.9)
	if d == Network.local_player:
		d.add_shake(0.35)
		if from_ball:
			say("Снежный ком сбил!", 1.5)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_knock(pid: int, impulse: Vector3) -> void:
	for d in get_tree().get_nodes_in_group("player"):
		if int(d.peer_id) == pid and d.is_local:
			knock(d, impulse)


func drive(d: Node3D, kind: int, t: float, data: Dictionary, delta: float) -> void:
	match kind:
		50:
			_drive_tow(d, t, data, delta)
		51:
			_drive_board(d, t, data, delta)
		52:
			_drive_crash(d, t, data, delta)


func _drive_tow(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var k: float = data["k"]
	k = minf(k + TOW_V * delta / _tow_len, 1.0)
	data["k"] = k
	var c := _cable(k, 0.0)
	var dirv := _cable(minf(k + 0.01, 1.0), 0.0) - _cable(maxf(k - 0.01, 0.0), 0.0)
	dirv.y = 0.0
	dirv = dirv.normalized() if dirv.length() > 0.001 else Vector3.FORWARD
	var bar := c - Vector3.UP * L.ROD
	var feet := bar - Vector3.UP * L.HANG
	# первые доли секунды — тянусь к перекладине (с места на настиле)
	var from: Vector3 = data.get("from", feet)
	var grab := smoothstep(0.0, 0.35, t)
	var pos := from.lerp(feet, grab)
	var vel := (pos - d.global_position) / maxf(delta, 0.001)
	d.global_position = pos
	d.velocity = vel
	# маятник: тело качается вокруг перекладины (рывок на старте, ветер, разгон)
	var sw: float = data.get("sw", 0.0)
	var swv: float = data.get("swv", 0.0)
	swv += (-9.8 / 1.15 * sin(sw) - 0.7 * swv + sin(t * 0.7) * 0.15 + sin(t * 1.9 + 1.0) * 0.08) * delta
	sw += swv * delta
	sw = clampf(sw, -0.6, 0.6)
	data["sw"] = sw
	data["swv"] = swv
	d.snow.set_mpose(50, sw * grab, bar, dirv, true)
	var me: bool = d == Network.local_player
	if me:
		say("Держи E!  %d%%" % roundi(k * 100.0) if L.over_chasm(feet) else "Держи E  %d%%" % roundi(k * 100.0), 0.2)
	var let_go: bool = t > 0.6 and not d._held("interact") and not bool(d.get("is_bot"))
	if k >= 1.0 or let_go:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		if k >= 1.0:
			var top := L.lift_top()
			d.global_position = top + Vector3(0.0, 0.25, -2.5)
			d.velocity = dirv * 1.5
			if me:
				say("Вершина! Сноуборды — прямо впереди, у оранжевой вывески (E)", 4.0)
		else:
			d.velocity = dirv * TOW_V * 0.8
			SFX.play(self, d.global_position + Vector3.UP * 2.0, "swish", -4.0, 0.8)
			if me and L.over_chasm(d.global_position):
				say("Сорвался!", 2.0)


func _drive_board(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var h: float = data["h"]
	var v: Vector3 = d.velocity
	var me_local: bool = d == Network.local_player
	var bot := bool(d.get("is_bot"))
	var ax := 0.0
	var fw := false
	var brake := false
	if not bot:
		ax = (1.0 if d._held("move_right") else 0.0) - (1.0 if d._held("move_left") else 0.0)
		fw = d._held("move_forward")
		brake = d._held("move_back")
	else:
		# бот едет за хозяином: рулит на точку впереди (ось трассы, ближе к хозяину), обогнал — тормозит
		var bp := d.global_position
		var nb: Array = L.near(bp.x, bp.z)
		var bs: float = nb[1]
		var o = d.get_node("Brain")._owner() if d.has_node("Brain") else null
		var lat_t := 0.0
		if o and is_instance_valid(o):
			var op: Vector3 = (o as Node3D).global_position
			var no: Array = L.near(op.x, op.z)
			if float(no[1]) < bs - 6.0:
				brake = true
			lat_t = clampf(float(no[0]) + 3.0, -L.HALF_W + 4.0, L.HALF_W - 4.0) * (1.0 - L.gully_k(bs))
		var look := 10.0 + Vector3(v.x, 0.0, v.z).length() * 0.6
		var tp := _pt(bs + look, lat_t)
		var want := atan2(-(tp.x - bp.x), -(tp.z - bp.z))
		ax = clampf(wrapf(h - want, -PI, PI) * 3.0, -1.0, 1.0)
		if absf(wrapf(h - want, -PI, PI)) > 0.6 and Vector3(v.x, 0.0, v.z).length() > 14.0:
			brake = true                  # шпилька — притормаживаю
	var nrm: Array = L.near(d.global_position.x, d.global_position.z)
	data["s"] = nrm[1]
	data["d"] = nrm[0]
	var on_floor: bool = d.is_on_floor()
	var was_air: bool = data["air"]
	var hv := Vector3(-sin(h), 0.0, -cos(h))
	var speed := Vector3(v.x, 0.0, v.z).length()
	if on_floor:
		var n: Vector3 = d.get_floor_normal()
		var bd := (hv - n * hv.dot(n)).normalized()
		var lat := n.cross(bd).normalized()
		# move_and_slide обнуляет вертикаль на полу — возвращаю скорость в плоскость склона (той же горизонтали)
		# шаг 144: «поднимаю» горизонталь на склон ВЕРТИКАЛЬНО (то же направление и та же горизонтальная скорость).
		# Раньше проецировал по нормали — на крутом скорость поворачивалась вбок, кант её гасил: доска
		# «вязла» и останавливалась на крутых участках и шпильках.
		if not was_air and n.y > 0.2:
			v = Vector3(v.x, -(v.x * n.x + v.z * n.z) / n.y, v.z)
		# приземлился (подскок на кочке короче 0.22 с — не прыжок: без проверок и очков)
		if was_air and float(data["air_t"]) < 0.22 and not bool(data.get("jumped", false)):
			data["air"] = false
		elif was_air:
			data["air"] = false
			data["jumped"] = false
			var hvel := Vector3(v.x, 0.0, v.z)
			var bad := false
			if hvel.length() > 3.0:
				var ang := hvel.normalized().angle_to(hv)
				ang = minf(ang, PI - ang)                 # задом наперёд (свитч) — тоже можно
				bad = ang > 0.8
			if v.y < -21.0:
				bad = true
			if bad:
				knock(d, Vector3(v.x, 2.0, v.z) * 0.8)
				if me_local:
					_trick("Кривое приземление!")
				return
			_landed(d, data)
		var g := Vector3(0.0, -BOARD_G * 1.3, 0.0)     # по склону тянет сильнее (быстрее катится)
		v += (g - n * g.dot(n)) * delta
		var vpar := v.dot(bd)
		# шаг 143: еду хвостом вперёд — доска «перекидывается» (нос всегда по ходу): A/D не путаются
		# шаг 144: медленно назад — не разворачиваю (раньше доска «сама поворачивалась»), просто гашу откат
		if vpar < 0.0 and vpar >= -4.0:
			var vb0 := vpar - vpar * exp(-8.0 * delta)
			v -= bd * vb0
			vpar -= vb0
		if vpar < -4.0:
			h = wrapf(h + PI, -PI, PI)
			hv = -hv
			bd = -bd
			lat = n.cross(bd).normalized()
			vpar = -vpar
		# поворот: A — налево, D — направо (как видно на экране); на скорости — плавнее
		var tr := lerpf(2.6, 1.35, clampf(absf(vpar) / 26.0, 0.0, 1.0))
		var dh := -ax * tr * delta
		h += dh
		# карвинг: скорость поворачивает вместе с доской почти без потерь (на тормозе — юзом)
		if absf(dh) > 0.0:
			var vn0 := v.dot(n)
			var vt := (v - n * vn0).rotated(n, dh * (0.25 if brake else 1.0))
			v = vt + n * vn0
			hv = Vector3(-sin(h), 0.0, -cos(h))
			bd = (hv - n * hv.dot(n)).normalized()
			lat = n.cross(bd).normalized()
			vpar = v.dot(bd)
		var vlat := v.dot(lat)
		# кант держит: боковое скольжение гасится (на тормозе — юзом поперёк, сильнее)
		vlat *= exp(-(9.0 if not brake else 4.0) * delta)
		var drag := 0.15 + 0.0022 * vpar * vpar * (0.6 if fw else 1.0)
		if brake:
			drag += 11.0
		var fin_k := smoothstep(L.FINISH_S + 5.0, L.FINISH_S + 25.0, float(data.get("s", 0.0)))
		drag += 4.0 * fin_k             # за финишем — рыхлый снег, торможу
		vpar = signf(vpar) * maxf(absf(vpar) - drag * delta, 0.0)
		# шаг 144: доска сама катится вперёд (на пологих траверсах не «вязнет»), W — разгон до крейсерской
		if not brake and fin_k < 0.5:
			var cruise := 24.0 if fw else 12.0
			if vpar < cruise:
				vpar = minf(vpar + (8.0 if fw else 3.5) * delta, cruise)
		var vn := minf(v.dot(n), 0.0)
		v = bd * vpar + lat * vlat + n * vn
		data["edge"] = lerpf(float(data["edge"]), -ax * clampf(absf(vpar) / 10.0, 0.25, 1.0) + (-0.6 if brake else 0.0), clampf(delta * 6.0, 0.0, 1.0))
		# прыжок
		if (d._just("jump") if not bot else false):
			v += n * 6.0 + Vector3.UP * 1.5
			data["air"] = true
			data["spin"] = 0.0
			data["grab"] = 0.0
			data["air_t"] = 0.0
			data["jumped"] = true
			SFX.play(self, d.global_position, "swish", -6.0, 1.2)
		_spray_fx(d, brake or absf(ax) > 0.5 and speed > 8.0, v)
	else:
		if not was_air:
			data["air"] = true
			data["spin"] = 0.0
			data["grab"] = 0.0
			data["air_t"] = 0.0
		data["air_t"] = float(data["air_t"]) + delta
		v.y -= BOARD_G * delta
		# вращение и захват
		var sp := ax * SPIN_V * delta
		h -= sp
		data["spin"] = float(data["spin"]) + sp
		if fw:
			data["grab"] = float(data["grab"]) + delta
		data["edge"] = lerpf(float(data["edge"]), 0.0, clampf(delta * 4.0, 0.0, 1.0))
		_spray_fx(d, false, v)
	var hs := Vector3(v.x, 0.0, v.z)
	if hs.length() > MAX_V:
		hs = hs.normalized() * MAX_V
		v.x = hs.x
		v.z = hs.z
	data["h"] = h
	var before := Vector3(v.x, 0.0, v.z).length()
	# шаг 143: камера смотрит туда, куда еду (мышью можно оглянуться — взгляд плавно вернётся вперёд);
	# от 1-го лица — чуть вниз: видно доску, ноги и трассу
	if me_local and d.controlled:
		var cy := atan2(-v.x, -v.z) if before > 3.0 else h
		var fpv: bool = d.fp_view
		d.camera_pivot.rotation.y = lerp_angle(d.camera_pivot.rotation.y, cy, clampf(delta * (3.5 if fpv else 2.5), 0.0, 1.0))
		if fpv:
			d.camera_pivot.rotation.x = lerpf(d.camera_pivot.rotation.x, -0.56, clampf(delta * 1.5, 0.0, 1.0))
		d._speed_fx = maxf(d._speed_fx, clampf((before - 12.0) / 22.0, 0.0, 0.45))
	d.velocity = v
	d.floor_snap_length = 0.9 if not bool(data["air"]) else 0.0
	d.move_and_slide()
	d.floor_snap_length = 0.1
	# врезался (ёлка, глыба, трамплин боком)
	var after := Vector3(d.velocity.x, 0.0, d.velocity.z).length()
	for ci in d.get_slide_collision_count():
		var col: KinematicCollision3D = d.get_slide_collision(ci)
		var cobj: Object = col.get_collider()
		if cobj is Node and (cobj as Node).is_in_group("hill_tree") and before > 5.0:
			var is_log := (cobj as Node).has_meta("log")
			var hard := before >= ARM_V and not is_log
			knock(d, -Vector3(v.x, 0.0, v.z) * 0.25 + Vector3.UP * 3.0, false, hard)
			if hard:
				_tree_hit(d, before, col.get_position(), Vector3(v.x, 0.0, v.z))
			if me_local:
				_trick("Бревно!" if is_log else ("Ёлка! Доска улетела" if hard else "Ёлка!"))
			return
	if before > 12.0 and after < before - 9.0 and on_floor:
		knock(d, Vector3(v.x, 0.0, v.z) * 0.3 + Vector3.UP * 3.0)
		return
	# столкновение с другом
	for o in get_tree().get_nodes_in_group("player"):
		if o == d or o.is_dead:
			continue
		var op: Vector3 = (o as Node3D).global_position
		var dp := op - d.global_position
		if Vector2(dp.x, dp.z).length() < 1.15 and absf(dp.y) < 1.6:
			var rel := Vector3(v.x - o.velocity.x, 0.0, v.z - o.velocity.z)
			if rel.length() > 4.0 and rel.dot(Vector3(dp.x, 0.0, dp.z)) > 0.0:
				knock(o, Vector3(v.x, 0.0, v.z) * 0.85 + Vector3.UP * 4.0)
				knock(d, Vector3(v.x, 0.0, v.z) * 0.25 + Vector3.UP * 3.0)
				if me_local:
					_trick("Сбил друга!")
				return
	# поза (остальным — 10 раз в секунду): dir — нос доски, pt — (кант, присед, захват), k — 1 в воздухе
	var crouch := 0.0
	if fw and on_floor:
		crouch = 1.0
	var land_t: float = float(data.get("land", 0.0))
	if land_t > 0.0:
		crouch = maxf(crouch, land_t / 0.3)
		data["land"] = land_t - delta
	var real_air := bool(data["air"]) and (float(data["air_t"]) > 0.15 or bool(data.get("jumped", false)))
	var grab := 1.0 if (real_air and fw) else 0.0
	d.snow.set_mpose(51, 1.0 if real_air else 0.0, Vector3(float(data["edge"]), crouch, grab), Vector3(-sin(h), 0.0, -cos(h)), true)
	# конец: выкатился внизу и остановился / E на месте — снять доску
	var p := d.global_position
	var slow := Vector3(d.velocity.x, 0.0, d.velocity.z).length() < 2.0
	var bot_done := false
	if bot and slow and t > 2.0 and d.has_node("Brain"):
		var ow = d.get_node("Brain")._owner()
		bot_done = ow == null or not is_instance_valid(ow) or int(ow.snow.climb) != 51
	# бот застрял (ёлка, бревно) — переношу чуть дальше по трассе
	if bot:
		data["stuck"] = float(data.get("stuck", 0.0)) + delta if Vector3(d.velocity.x, 0.0, d.velocity.z).length() < 1.0 else 0.0
		if float(data["stuck"]) > 2.5:
			data["stuck"] = 0.0
			var np := _pt(float(data.get("s", 0.0)) + 9.0, clampf(float(data.get("d", 0.0)), -L.HALF_W + 3.0, L.HALF_W - 3.0) + randf_range(-3.0, 3.0))
			d.global_position = np + Vector3.UP * 0.4
			var f2 := _fw(float(data.get("s", 0.0)) + 12.0)
			data["h"] = atan2(-f2.x, -f2.z)
	var fin := float(data.get("s", 0.0)) > L.FINISH_S + 8.0 and absf(float(data.get("d", 99.0))) < 40.0
	if bot_done or (fin and slow) or p.z < L.Z_END - 5.0 or (slow and t > 1.0 and not bot and d._just("interact")) or not L.on_hill(p) and p.z > L.Z_FOOT:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		d.visual.rotation.y = h
		if me_local:
			var tt: float = t
			say("Финиш! Спуск за %d:%02d" % [int(tt) / 60, int(tt) % 60] if fin else "Доска снята", 4.0)


func _landed(d: Node3D, data: Dictionary) -> void:
	data["land"] = 0.3
	var air_t: float = data["air_t"]
	var spin := absf(float(data["spin"]))
	var deg := int(round(spin / PI)) * 180
	var names: Array[String] = []
	if deg >= 180:
		names.append(str(deg))
	if float(data["grab"]) > 0.25:
		names.append("захват")
	if names.is_empty() and air_t > 1.0:
		names.append("полёт %.1f с" % air_t)
	SFX.play(self, d.global_position, "thunk", -4.0, 0.8)
	if not names.is_empty() and d == Network.local_player:
		_trick(" + ".join(names))


func _drive_crash(d: Node3D, t: float, data: Dictionary, delta: float) -> void:
	var v: Vector3 = d.velocity
	v.y -= BOARD_G * delta
	if d.is_on_floor():
		var n: Vector3 = d.get_floor_normal()
		var g := Vector3(0.0, -BOARD_G, 0.0)
		v += (g - n * g.dot(n)) * delta * 0.6
		var hs := Vector3(v.x, 0.0, v.z)
		hs = hs.move_toward(Vector3.ZERO, (9.0 + hs.length() * 0.5) * delta)
		v.x = hs.x
		v.z = hs.z
		if t > 0.15:
			_spray_fx(d, hs.length() > 2.0, v)
	d.velocity = v
	d.move_and_slide()
	var hv := Vector3(v.x, 0.0, v.z)
	var dirv: Vector3 = data.get("dir", Vector3.FORWARD)
	if hv.length() > 1.0:
		dirv = hv.normalized()
		data["dir"] = dirv
	# фаза кувырка: 0–1.1 кувырок, 1.1–1.45 лежу (пока несёт — лежу), 1.45–1.9 встаю
	var ph: float = data.get("ph", 0.0)
	var spd := Vector3(d.velocity.x, 0.0, d.velocity.z).length()
	if not (ph > 1.3 and ph < 1.45 and spd > 1.8):
		ph += delta
	data["ph"] = ph
	d.snow.set_mpose(52, ph, Vector3.ZERO, dirv, true)
	if ph >= 1.9:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		if bool(data.get("board", false)) and L.on_hill(d.global_position) and d.global_position.z < L.Z_START + 6.0:
			start_board(d, Vector3.ZERO)
		elif d == Network.local_player:
			if bool(data.get("lost", false)):
				say("Доска улетела — подойди и подбери её (E)", 3.0)
			else:
				say("Встал. Отряхнулся.", 1.5)


## Ёлка на большой скорости: немного урона, отлетает рука (на очень большой — нога), доска улетает
func _tree_hit(d: Node3D, speed: float, at: Vector3, v: Vector3) -> void:
	d.take_damage(5.0, "hit", at)
	var kinds: Array[String] = []
	if speed >= LEG_V:
		for k in ["leg_l", "leg_r"]:
			if d.has_limb(k):
				kinds.append(k)
	if kinds.is_empty():
		for k in ["arm_l", "arm_r"]:
			if d.has_limb(k):
				kinds.append(k)
	if not kinds.is_empty():
		var k2: String = kinds[randi() % kinds.size()]
		d.lose_limb(k2, -v.normalized() * 2.5 + Vector3.UP * 4.0 + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		if d == Network.local_player:
			say("Оторвало %s! Друг может прикрутить (E с деталью)" % d.limb_name(k2, true), 3.5)
	var bv := v * 0.45 + Vector3.UP * 5.5 + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	var bp := d.global_position + Vector3.UP * 0.4
	_loose_n += 1
	var id := int(d.peer_id) * 1000 + _loose_n
	if _online():
		_spawn_loose.rpc(id, bp, bv)
	else:
		_spawn_loose(id, bp, bv)


func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and multiplayer.get_peers().size() > 0


@rpc("any_peer", "call_local", "reliable")
func _spawn_loose(id: int, at: Vector3, vel: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 4.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 0.08, 0.3)
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = board_mesh()
	rb.add_child(mi)
	rb.physics_material_override = PhysicsMaterial.new()
	rb.physics_material_override.friction = 0.9
	rb.physics_material_override.bounce = 0.15
	add_child(rb)
	rb.global_position = at
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-8, 8), randf_range(-6, 6))
	_loose[id] = rb
	# через 3 минуты пропадает
	get_tree().create_timer(180.0).timeout.connect(func():
		if _loose.has(id):
			_take_loose(id))


@rpc("any_peer", "call_local", "reliable")
func _take_loose(id: int) -> void:
	var rb = _loose.get(id)
	_loose.erase(id)
	if rb != null and is_instance_valid(rb):
		(rb as Node).queue_free()


## Снег из-под канта
func _spray_fx(d: Node3D, on: bool, v: Vector3) -> void:
	var sp: CPUParticles3D = _spray.get(d)
	if sp == null or not is_instance_valid(sp):
		sp = CPUParticles3D.new()
		sp.amount = 50
		sp.lifetime = 0.7
		sp.local_coords = false
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 0.35
		sp.spread = 35.0
		sp.initial_velocity_min = 3.0
		sp.initial_velocity_max = 6.0
		sp.gravity = Vector3(0, -7, 0)
		sp.scale_amount_min = 0.25
		sp.scale_amount_max = 0.7
		var qm := QuadMesh.new()
		qm.size = Vector2(0.45, 0.45)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.material = m
		sp.mesh = qm
		add_child(sp)
		_spray[d] = sp
	sp.emitting = on
	if on:
		sp.global_position = d.global_position + Vector3.UP * 0.15
		var back := -Vector3(v.x, 0.0, v.z).normalized()
		sp.direction = (back * 0.4 + Vector3.UP * 0.8 + Vector3(-back.z, 0.0, back.x) * 0.6).normalized()
