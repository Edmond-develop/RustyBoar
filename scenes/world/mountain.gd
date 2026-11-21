extends Node3D
## Шаг 72–73: Пик — финальная локация. Строит всё на горе (рельеф — в terrain.gd по MountainLayout)
## и ведёт общие для горы вещи; отдельные испытания — в своих узлах-модулях:
##   * mountain_chasm.gd   — трещина поперёк тропы: перебросить друга, он крепит верёвочный мост;
##   * mountain_mech.gd    — гнёзда механизмов: деталь вставить → повернуть → закрутить (шаг 74);
##   * mountain_spires.gd  — пропасть 60 м с выступами: прыгать, цепляться ледорубами (ЛКМ/ПКМ) (шаг 77);
##   * mountain_glacier.gd — ледник со скрытыми трещинами: связка, щуп, удержать и вытащить (шаг 86);
##   * mountain_ropeway.gd — канатка с плато на Плечо: редуктор-головоломка, зажим, рычаг; пуск вдвоём;
##   * mountain_night.gd   — ночь и буран на Плече: печка в приюте, дрова, греться вместе;
##   * mountain_face.gd    — стена к вершине: скалолазание, связка, подтянуть за руку, лебёдка для посылки;
##   * mountain_scenery.gd — скалы, валуны, осыпи, море облаков, дальние хребты.
## Здесь же: уступы (подсадка с анимацией и верёвочная лестница), леера/фонари/парапет, карнизы,
## базовый лагерь и приюты, вершина (пункт приёма), посылка и финал, подсказки.
## Точки «держи E»: каждый модуль регистрирует свои (add_hold); кто где держит — каждый сообщает хосту,
## хост рассылает (active: точка → id дрона).

const M := preload("res://scenes/world/mountain_layout.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")
const HEATER := preload("res://scenes/world/heat_source.gd")
const WEATHER := preload("res://scenes/world/mountain_weather.gd")
const OBSTACLE := preload("res://scenes/world/mountain_obstacle.gd")
const PARCEL := preload("res://scenes/props/parcel.tscn")
const BUILDER := preload("res://scenes/world/peak_builder.gd")
const LODGE := preload("res://scenes/world/peak_lodge.gd")
const HUT := preload("res://scenes/world/peak_hut.gd")
const CHASM := preload("res://scenes/world/mountain_chasm.gd")
const ROPEWAY := preload("res://scenes/world/mountain_ropeway.gd")
const NIGHT := preload("res://scenes/world/mountain_night.gd")
const FACE := preload("res://scenes/world/mountain_face.gd")
const SCENERY := preload("res://scenes/world/mountain_scenery.gd")
const MECH := preload("res://scenes/world/mountain_mech.gd")
const SPIRES := preload("res://scenes/world/mountain_spires.gd")
const GLACIER := preload("res://scenes/world/mountain_glacier.gd")

const HOLD_R := 1.15               ## на каком расстоянии от точки «держи E»
const HAND_T := 0.38               ## подсадка: руки на плечи друга, ставлю ногу в его ладони (шаг 76)
const LIFT_T := 0.6                ## …друг приседает и толкает вверх (шаг 75: дольше — видно движение)
const FLY_T := 0.42                ## шаг 75: полёт до края уступа
const GRAB_T := 0.85               ## шаг 75: окно «ухватиться» (E) у края (шаг 138: шире; держать E тоже можно)
const EARLY_T := 0.15              ## нажал чуть раньше окна — тоже засчитано
const FOLLOW_T := 0.4              ## подсаживающий после броска: руки вверх, на носках — и обратно
const BOOST_UP := 9.6              ## …и бросает вверх
const BOOST_FWD := 2.2
const MANTLE_T := 1.15             ## вылезти на уступ (вишу на руках, подтягиваюсь, колено, встаю)
const SFX := preload("res://scripts/sfx.gd")
const CORNICE_T := 0.9
const CORNICE_T2 := 0.4
const CORNICE_BACK := 20.0
const PAD_R := 2.6

# для метели (как у пустоши): вешки, леера, изба
var poles: Array[Vector3] = []
var ropes: Array = []
var cabin = null                   ## = self: in_cabin / in_yard по всем избам горы

var obstacles: Array = []          ## уступы (см. _build_step)
var cornices: Array = []
var holds := {}                    ## точка «держи E» → [позиция, радиус, допуск по высоте]
var active := {}                   ## точка → id дрона, который держит (у всех одинаково)
var hold_map := {}                 ## хост: id дрона → точка
var weather: Node
var main_parcel: Node
var delivered := false
var beacon: Node3D                 ## шаг 122: станция-маяк на вершине
var pad := Vector3.ZERO
var warm_spots: Array[Vector3] = []
var builder: Node3D
var lodge: Node3D
var huts: Array = []               ## приюты (peak_hut.gd)
var hut_top: Node3D                ## приют на Плече (ночь)
var chasm: Node3D
var ropeway: Node3D
var night: Node3D
var face: Node3D
var scenery: Node3D
var mech: Node3D                   ## шаг 74: гнёзда механизмов (детали ставятся с анимацией)
var spires: Node3D                 ## шаг 77: пропасть с выступами, ледорубы
var glacier: Node3D                ## шаг 86: ледник со скрытыми трещинами
var modules: Array = []

var _ter: Node
var _rock_mat: Material
var _local := {}                   ## мои дроны: id → точка, где держат E
var _remote := {}                  ## хост: дроны других → точка
var _sent := {}
var _sync_t := 0.0
var _prev_floor := {}
var _boosted := {}                 ## дрон → [сколько ещё, направление, № уступа] — летит на уступ
var _lift_until := {}              ## подсаживающий (мой дрон) → до какого времени поднимает
var _hint: Label
var _hint_t := 0.0
var _parcel_last := Vector3.INF
var _parcel_back_t := 0.0
var _final: CanvasLayer
var _snow_mat: StandardMaterial3D
var _rope_mat: StandardMaterial3D
var _clock := 0.0
var _ladders := {}                 ## шаг 75: № уступа → когда сброшена лестница (висит насовсем)
var _qte: Label3D                  ## шаг 76: маленькая «E» у края (в мире)


func _ready() -> void:
	add_to_group("mountain")
	cabin = self
	_ter = get_tree().get_first_node_in_group("terrain")
	_build_hud()
	_build.call_deferred()


func _gy(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else 0.0


func _online() -> bool:
	return Network.in_game and Network.is_online()


func now() -> float:
	return Network.game_time if Network.in_game else _clock


# ---------------------------------------------------------------------------
#  Постройка
# ---------------------------------------------------------------------------

func _build() -> void:
	_rock_mat = _ter.get("terrain_material") if _ter else null
	if _rock_mat == null:
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.38, 0.4, 0.45)
		_rock_mat = rm
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.albedo_color = Color(0.93, 0.95, 1.0)
	_snow_mat.roughness = 0.9
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.albedo_color = Color(0.95, 0.45, 0.08)
	_rope_mat.roughness = 0.6
	builder = Node3D.new()
	builder.set_script(BUILDER)
	builder.name = "PeakBuild"
	add_child(builder)
	for i in M.STEPS.size():
		_build_step(i)
	_build_lip()
	_build_guides()
	_build_cornices()
	_build_camps()
	_build_summit()
	_build_signs()
	for pair in [["mech", MECH, "Mech"], ["spires", SPIRES, "Spires"], ["glacier", GLACIER, "Glacier"],
			["chasm", CHASM, "Chasm"], ["ropeway", ROPEWAY, "Ropeway"], ["night", NIGHT, "Night"],
			["face", FACE, "Face"], ["scenery", SCENERY, "Scenery"]]:
		var n := Node3D.new()
		n.set_script(pair[1])
		n.name = pair[2]
		n.set("mtn", self)
		add_child(n)
		set(pair[0], n)
		modules.append(n)
	for m in modules:
		if m.has_method("build"):
			m.build()
	builder.flush()
	weather = Node3D.new()
	weather.set_script(WEATHER)
	weather.name = "MountainWeather"
	weather.set("waste", self)
	add_child(weather)
	_spawn_main_parcel.call_deferred()


func _box(parent: Node3D, size: Vector3, xf: Transform3D, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.transform = xf
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		parent.add_child(body)
	return mi


func rock_mat() -> Material:
	return _rock_mat


func rope_mat() -> Material:
	return _rope_mat


## Точка «держи E» (модули регистрируют свои)
func add_hold(id: String, pos: Vector3, r := HOLD_R, dy := 1.6) -> void:
	holds[id] = [pos, r, dy]


func is_active(id: String) -> bool:
	return active.has(id)


## Хост: кто (id дронов) держит E у точки
func holders(id: String) -> Array:
	var out: Array = []
	for pid in hold_map:
		if String(hold_map[pid]) == id:
			out.append(int(pid))
	return out


## Уступ на тропе: стенка из скалы с выступами, камень для подсадки, лестница наверху
func _build_step(i: int) -> void:
	var s: Array = M.STEPS[i]
	var u: float = s[0]
	var t := M.tangent(u)
	var out := M.outward(u)
	var du := 0.8 / M.len_per_u(u)
	var p0 := M.point(u - du)
	var y0 := M.height(u - du * 2.0)
	var y1 := M.height(u + du * 4.0)
	var c := Vector3(p0.x, y0, p0.z)
	var hin := M.half_in(u)
	var hout := M.half_out(u)
	var wid := hin + hout + 3.0
	var mid_lat := (hout - hin) * 0.5
	var bas := Basis(out, Vector3.UP, -t)
	var hh := (y1 - y0) + 2.0
	var cen := c + t * 1.25 + out * mid_lat + Vector3.UP * (hh * 0.5 - 2.0)
	var wall := _box(self, Vector3(wid, hh, 2.5), Transform3D(bas, cen), _rock_mat, true)
	wall.name = "Ledge%d" % i
	# неровная скала поверх стенки: выпуклые глыбы (без коллизии)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7300 + i
	for k in 9:
		var lat := lerpf(-hin, hout, (k + 0.5) / 9.0) + rng.randf_range(-0.4, 0.4)
		var hy := rng.randf_range(0.2, y1 - y0 - 0.3)
		var rs := Vector3(rng.randf_range(0.8, 1.5), rng.randf_range(0.5, 1.0), rng.randf_range(0.3, 0.6))
		if absf(lat + (hin - 1.6)) < 1.0:
			continue                                   # шаг 76: где висит лестница — стена гладкая
		builder.rock_vis(c + out * lat + Vector3.UP * hy + t * 0.05, rs, atan2(t.x, t.z) + rng.randf_range(-0.3, 0.3), "rock")
	var top_exit := c + t * 1.6 + Vector3(0, y1 - y0 + 0.15, 0)
	var ob := {"u": u, "i": i, "t": t, "out": out, "foot": c, "y0": y0, "y1": y1,
		"hin": hin, "hout": hout, "top_exit": top_exit}
	ob["boost"] = c - t * 1.25 + out * mid_lat + Vector3.UP * 0.05
	var lat2 := -out * (hin - 1.6)
	ob["ladder_foot"] = c - t * 0.5 + lat2
	ob["ladder_base"] = c + lat2
	ob["anchor"] = c + t * 2.4 - out * (hin - 3.0) + Vector3.UP * (y1 - y0 + 0.05)
	ob["ladder_top"] = c + lat2 + Vector3.UP * (y1 - y0)
	ob["hold_boost"] = "B%d" % i
	ob["hold_anchor"] = "A%d" % i
	add_hold("B%d" % i, ob["boost"])
	add_hold("A%d" % i, ob["anchor"])
	_build_ladder(ob)
	# камень для подсадки (на нём стоит подсаживающий — видно, где встать)
	var stone := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.5
	sm.bottom_radius = 0.62
	sm.height = 0.12
	sm.material = _rock_mat
	stone.mesh = sm
	stone.position = (ob["boost"] as Vector3) + Vector3.UP * 0.0
	add_child(stone)
	if i == 0:
		_decor_step0(ob, c, t, out, hin, hout, y1)
	obstacles.append(ob)
	var gate := Node3D.new()
	gate.set_script(OBSTACLE)
	gate.set("mtn", self)
	gate.set("idx", obstacles.size() - 1)
	gate.add_to_group("coop_gate")
	add_child(gate)
	gate.global_position = c


## Крюк-стойка
func post(at: Vector3, col: Color, parent: Node3D = null) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.6
	m.roughness = 0.4
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.09
	cm.height = 1.0
	cm.material = m
	mi.mesh = cm
	mi.position = at + Vector3.UP * 0.5
	(parent if parent else self).add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.12
	tm.material = m
	ring.mesh = tm
	ring.position = at + Vector3.UP * 1.0
	ring.rotation.x = PI * 0.5
	(parent if parent else self).add_child(ring)


## Верёвочная лестница: висит, пока наверху держат E; иначе — скатана у крюка
## Шаг 75: первый уступ (4.5 м) — козырёк-зацеп у края (за него хватаются), сосульки под ним,
## старый крюк с обрывком верёвки, трещины-полки, табличка
func _decor_step0(ob: Dictionary, c: Vector3, t: Vector3, out: Vector3, hin: float, hout: float, y1: float) -> void:
	var b: Node3D = builder
	var rng := RandomNumberGenerator.new()
	rng.seed = 7575
	var top := float(y1)
	var face := c + t * 0.02
	var lat := -hin
	var lad_lat := -(hin - 1.6)
	while lat < hout:
		var w := rng.randf_range(0.9, 1.5)
		if absf(lat + w * 0.5 - lad_lat) < 0.9:
			lat += w
			continue
		b.rock_vis(face + out * (lat + w * 0.5) + Vector3.UP * (top - c.y - 0.12) - t * 0.18, Vector3(w * 0.6, 0.28, 0.42), atan2(t.x, t.z) + rng.randf_range(-0.2, 0.2), "rock")
		b.box(Vector3(w, 0.12, 0.6), face + out * (lat + w * 0.5) + Vector3.UP * (top - c.y + 0.05) - t * 0.1, Basis(out, Vector3.UP, -t), "snowblock")
		# сосульки под козырьком
		for k in 2:
			var ic := face + out * (lat + rng.randf_range(0.1, w - 0.1)) + Vector3.UP * (top - c.y - 0.45) - t * 0.3
			var ln := rng.randf_range(0.25, 0.6)
			b.cyl(rng.randf_range(0.04, 0.07), 0.0, ln, ic + Vector3.DOWN * ln * 0.3, Basis.IDENTITY, "ice", 6)
		lat += w
	# полки-трещины на стене (видно, что лезть нельзя — гладко)
	for k in 4:
		var hy := rng.randf_range(0.8, top - c.y - 1.0)
		b.box(Vector3(rng.randf_range(0.8, 2.0), 0.05, 0.08), face + out * rng.randf_range(lad_lat + 1.2, hout - 1.0) + Vector3.UP * hy - t * 0.02, Basis(out, Vector3.UP, -t) * Basis(Vector3.BACK, rng.randf_range(-0.3, 0.3)), "dark")
	# старый крюк и обрывок верёвки
	var pit := face + out * (hout - 2.2) + Vector3.UP * (top - c.y - 1.4) - t * 0.05
	b.beam(pit, pit - t * 0.18, 0.025, "iron", 6)
	b.cyl(0.05, 0.05, 0.02, pit - t * 0.18, basis_y_t(t), "iron", 8)
	b.beam(pit - t * 0.16, pit - t * 0.22 + Vector3.DOWN * 0.9 + out * 0.1, 0.02, "rope", 5)
	sign_at(c - t * 4.5 + out * (hout - 1.2), "УСТУП 4,5 м\nЗапрыгнуть нельзя — только с подсадкой.\nДруг подбросит до края —\nв этот миг ЖМИ E: ухватиться!\nНаверху E у мотка — лестница", Color(1.0, 0.85, 0.5))


static func basis_y_t(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## Шаг 76: верёвочная лестница с деревянными ступенями: от столбика наверху — через край — вниз до самого снега
## (на 0.32 м от скалы, камни за ней убраны — не уходит в текстуру); у неё своя коллизия (когда сброшена)
func _build_ladder(ob: Dictionary) -> void:
	var t: Vector3 = ob["t"]
	var out: Vector3 = ob["out"]
	var base: Vector3 = ob["ladder_base"]
	var ltop: Vector3 = ob["ladder_top"]
	var off := -t * 0.32
	var MB = preload("res://scenes/world/peak_part.gd").ModelBuilder
	var mb = MB.new()
	var g := _gy(base.x + off.x, base.z + off.z)
	var anchor: Vector3 = ob["anchor"]
	var edge := ltop + Vector3.UP * 0.06 - t * 0.06
	var hang_top := ltop + off + Vector3.UP * 0.02
	var bottom := Vector3(base.x, g + 0.03, base.z) + off
	for sd in [-1.0, 1.0]:
		var so: Vector3 = out * sd * 0.26
		# от столбика к краю, через край, вниз, последний кусок лежит на снегу
		mb.beam(anchor + Vector3.UP * 0.55 + so * 0.6, edge + so, 0.022, "rope", 5)
		mb.beam(edge + so, hang_top + so, 0.022, "rope", 5)
		mb.beam(hang_top + so, bottom + so, 0.022, "rope", 5)
		mb.beam(bottom + so, bottom + so - t * 0.45 + Vector3.DOWN * 0.02, 0.022, "rope", 5)
	var n := int((hang_top.y - bottom.y) / 0.32)
	for k in n:
		var y := hang_top.y - 0.22 - k * 0.32
		if y < bottom.y + 0.12:
			break
		var p := Vector3(bottom.x, y, bottom.z)
		mb.cyl(0.03, 0.03, 0.6, p, _basis_along(out), "wood", 7)
		for sd2 in [-1.0, 1.0]:
			mb.sph(0.04, p + out * sd2 * 0.26, Basis.IDENTITY, "rope", 6)
	var lad := Node3D.new()
	lad.name = "RopeLadder%d" % int(ob["i"])
	mb.commit(lad, func(k: String) -> Material: return builder.mat(k))
	lad.visible = false
	add_child(lad)
	ob["ladder_mi"] = lad
	# коллизия (включается, когда лестница сброшена): тонкая плита за ступенями
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var len := hang_top.y - bottom.y
	bs.size = Vector3(0.62, len, 0.06)
	cs.shape = bs
	cs.disabled = true
	body.add_child(cs)
	add_child(body)
	body.global_transform = Transform3D(Basis(out, Vector3.UP, out.cross(Vector3.UP)), (hang_top + bottom) * 0.5 + t * 0.08)
	ob["ladder_cs"] = cs
	post(ob["anchor"], Color(0.95, 0.45, 0.08))
	var roll := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 0.62
	cm.radial_segments = 10
	cm.rings = 1
	cm.material = builder.mat("rope")
	roll.mesh = cm
	roll.position = ltop + t * 0.5 + Vector3.UP * 0.2
	roll.basis = Basis(Quaternion(Vector3.UP, out))
	add_child(roll)
	ob["roll_mi"] = roll


static func _basis_along(ax: Vector3) -> Basis:
	var y := ax.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


func _quad_box(st: SurfaceTool, center: Vector3, size: Vector3, ax := Vector3.RIGHT) -> void:
	var x := ax.normalized() * size.x * 0.5
	var y := Vector3.UP * size.y * 0.5
	var z := x.cross(Vector3.UP).normalized() * size.z * 0.5
	if size.y > size.x:
		x = Vector3.RIGHT * size.x * 0.5
		z = Vector3.BACK * size.z * 0.5
	var c := [center - x - y - z, center + x - y - z, center + x + y - z, center - x + y - z,
		center - x - y + z, center + x - y + z, center + x + y + z, center - x + y + z]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f in faces:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var cc: Vector3 = c[f[2]]
		var d: Vector3 = c[f[3]]
		for v in [a, cc, b, a, d, cc]:
			st.add_vertex(v)


## Фонари-вешки у скалы, леера и парапет по краю
func _build_guides() -> void:
	var pole_mm := MultiMesh.new()
	pole_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 2.0
	pm.radial_segments = 6
	pm.rings = 1
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.2, 0.22)
	pm.material = pole_mat
	pole_mm.mesh = pm
	var lamp_mm := MultiMesh.new()
	lamp_mm.transform_format = MultiMesh.TRANSFORM_3D
	var lm := SphereMesh.new()
	lm.radius = 0.11
	lm.height = 0.22
	lm.radial_segments = 8
	lm.rings = 4
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.6, 0.2)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.55, 0.15)
	lamp_mat.emission_energy_multiplier = 5.0
	lamp_mat.disable_fog = true
	lm.material = lamp_mat
	lamp_mm.mesh = lm
	var post_mm := MultiMesh.new()
	post_mm.transform_format = MultiMesh.TRANSFORM_3D
	var ptm := CylinderMesh.new()
	ptm.top_radius = 0.04
	ptm.bottom_radius = 0.05
	ptm.height = 1.1
	ptm.radial_segments = 6
	ptm.rings = 1
	ptm.material = pole_mat
	post_mm.mesh = ptm
	var rope_mm := MultiMesh.new()
	rope_mm.transform_format = MultiMesh.TRANSFORM_3D
	var rm := CylinderMesh.new()
	rm.top_radius = 0.025
	rm.bottom_radius = 0.025
	rm.height = 1.0
	rm.radial_segments = 5
	rm.rings = 1
	rm.material = _rope_mat
	rope_mm.mesh = rm
	var stone_mm := MultiMesh.new()
	stone_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sbm := BoxMesh.new()
	sbm.size = Vector3(1.0, 1.0, 1.0)
	sbm.material = _rock_mat
	stone_mm.mesh = sbm
	var pole_x: Array[Transform3D] = []
	var lamp_x: Array[Transform3D] = []
	var post_x: Array[Transform3D] = []
	var rope_x: Array[Transform3D] = []
	var stone_x: Array[Transform3D] = []
	var parapet := StaticBody3D.new()
	parapet.name = "Parapet"
	add_child(parapet)
	var u := 0.004
	while u < 0.99:
		var p := M.point(u)
		var q := p - M.outward(u) * (M.half_in(u) - 0.5)
		q.y = M.height(u)
		if not _near_step(u, 5.0) and M.chasm_d(u) > M.CHASM_W * 0.5 + 3.0 and not _near_camp(u, 12.0) and not M.in_glacier(u, 8.0):
			pole_x.append(Transform3D(Basis.IDENTITY, q + Vector3.UP * 1.0))
			lamp_x.append(Transform3D(Basis.IDENTITY, q + Vector3.UP * 2.05))
			poles.append(q)
		u += 18.0 / M.len_per_u(u)
	u = 0.03
	var seg := 0
	var prev := Vector3.INF
	while u < 0.985:
		var step := 6.0 / M.len_per_u(u)
		var hole := u > 0.6 and (seg % 10) >= 8
		var skip := _near_step(u, 4.0) or M.in_cornice(u) or _near_camp(u, 12.0) or M.chasm_d(u) < M.CHASM_W * 0.5 + 3.5 or M.in_glacier(u, 8.0)
		var edge := M.point(u) + M.outward(u) * (M.half_out(u) - 0.35)
		edge.y = M.height(u)
		if u < M.RAIL_FROM:
			if not skip:
				var t := M.tangent(u)
				var sxf := Transform3D(Basis(M.outward(u), Vector3.UP, -t) * Basis.from_scale(Vector3(0.7, 1.05, 6.2)), edge + Vector3.UP * 0.45)
				stone_x.append(sxf)
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.7, 1.4, 6.2)
				cs.shape = bs
				cs.transform = Transform3D(Basis(M.outward(u), Vector3.UP, -t), edge + Vector3.UP * 0.6)
				parapet.add_child(cs)
			prev = Vector3.INF
		else:
			if skip or hole:
				prev = Vector3.INF
			else:
				post_x.append(Transform3D(Basis.IDENTITY, edge + Vector3.UP * 0.55))
				var top := edge + Vector3.UP * 1.0
				if prev != Vector3.INF and prev.distance_to(top) < 9.0:
					var d := top - prev
					var b := Basis(Quaternion(Vector3.UP, d.normalized())) * Basis.from_scale(Vector3(1.0, d.length(), 1.0))
					rope_x.append(Transform3D(b, (prev + top) * 0.5))
					ropes.append([prev, top])
				prev = top
		u += step
		seg += 1
	# шаг 74: кусками по 90 м (что за камерой — не рисуется) и с дальностью видимости
	multi_chunks(self, pole_mm.mesh, pole_x, 260.0)
	multi_chunks(self, lamp_mm.mesh, lamp_x, 700.0)
	multi_chunks(self, post_mm.mesh, post_x, 200.0)
	multi_chunks(self, rope_mm.mesh, rope_x, 200.0)
	multi_chunks(self, stone_mm.mesh, stone_x, 450.0)


## Твёрдая кромка полки снаружи (сетка рельефа скругляет край): плиты вровень с полкой
func _build_lip() -> void:
	var body := StaticBody3D.new()
	body.name = "Lip"
	add_child(body)
	var xf: Array[Transform3D] = []
	var bounds: Array[float] = []
	for c in M.CORNICES:
		bounds.append(float(c[0]))
		bounds.append(float(c[1]))
	for sgn in [-1.0, 1.0]:
		bounds.append(M.CHASM_U + sgn * (M.CHASM_W * 0.5 + 0.3) / M.len_per_u(M.CHASM_U))
	bounds.append(M.SP_U0 - 0.3 / M.len_per_u(M.SP_U0))
	bounds.append(M.sp_u1() + 0.3 / M.len_per_u(M.SP_U0))
	var u0 := 0.0
	while M.height(u0) < 5.0:
		u0 += 0.001
	while u0 < 0.99:
		var u1 := minf(u0 + 4.0 / M.len_per_u(u0), 0.99)
		for b in bounds:
			if b > u0 + 0.00001 and b < u1:
				u1 = b
		var um := (u0 + u1) * 0.5
		var near_step := false
		for st in M.STEPS:
			var su := float(st[0])
			if su > u0 - 1.5 / M.len_per_u(su) and su < u1 + 1.5 / M.len_per_u(su):
				near_step = true
		if not near_step and M.chasm_d(um) > M.CHASM_W * 0.5 and not M.in_glacier(um, 1.0):
			var hi := M.half_out(um) + 0.02
			var lo := maxf(M.half_out(um) - 1.7, -M.half_in(um) + 0.8)
			var latc := (lo + hi) * 0.5
			var a := M.point(u0) + M.outward(u0) * latc
			var b2 := M.point(u1) + M.outward(u1) * latc
			var fwd := b2 - a
			var fl := fwd.length()
			if fl > 0.2:
				var fn := fwd / fl
				var side := M.outward(um)
				side = (side - fn * side.dot(fn)).normalized()
				var up := fn.cross(side)
				if up.y < 0.0:
					side = -side
					up = -up
				var basis := Basis(side, up, fn)
				var size := Vector3(hi - lo, 2.5, fl + 0.3)
				var c := (a + b2) * 0.5 + Vector3.UP * 0.03 - up * 1.25
				xf.append(Transform3D(basis * Basis.from_scale(size), c))
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = size
				cs.shape = bs
				cs.transform = Transform3D(basis, c)
				body.add_child(cs)
		u0 = u1
	var bm := BoxMesh.new()
	bm.material = _rock_mat
	multi_chunks(self, bm, xf, 450.0)


## Шаг 74: много одинаковых предметов — MultiMesh кусками по клеткам (рисуются только те, что в кадре и ближе vis)
static func multi_chunks(parent: Node3D, mesh: Mesh, xfs: Array, vis: float, cell := 90.0, mat: Material = null, shadow := false, vis_begin := 0.0) -> void:
	var cells := {}
	for x in xfs:
		var o: Vector3 = (x as Transform3D).origin
		var key := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(x)
	for key in cells:
		var arr: Array = cells[key]
		var c := Vector3.ZERO
		for x in arr:
			c += (x as Transform3D).origin
		c /= float(arr.size())
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for k in arr.size():
			var x2: Transform3D = arr[k]
			mm.set_instance_transform(k, Transform3D(x2.basis, x2.origin - c))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.position = c
		if mat:
			mi.material_override = mat
		mi.visibility_range_end = vis
		mi.visibility_range_end_margin = vis * 0.08
		if vis_begin > 0.0:
			mi.visibility_range_begin = vis_begin
			mi.visibility_range_begin_margin = vis_begin * 0.08
		if not shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


func _near_step(u: float, m: float) -> bool:
	for s in M.STEPS:
		if absf(u - float(s[0])) * M.len_per_u(float(s[0])) < m:
			return true
	return false


func _near_camp(u: float, m: float) -> bool:
	for c in M.CAMPS:
		if absf(u - float(c)) * M.len_per_u(float(c)) < m:
			return true
	return false


## Снежные карнизы: снаружи полки — плиты снега над пустотой (кусками по 3 м)
func _build_cornices() -> void:
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.94, 0.96, 1.0)
	cmat.roughness = 0.85
	for c in M.CORNICES:
		var u: float = c[0]
		while u < float(c[1]):
			var step := 3.0 / M.len_per_u(u)
			var um := u + step * 0.5
			var t := M.tangent(um)
			var out := M.outward(um)
			var w := M.width(um)
			var inner := -w * 0.5 + M.CORNICE_STRIP
			var outer := w * 0.5 + 0.6
			var cw := outer - inner
			var y := M.height(um)
			var cen := M.point(um) + out * (inner + cw * 0.5)
			cen.y = y - 0.25
			var xf := Transform3D(Basis(out, Vector3.UP, -t), cen)
			var body := StaticBody3D.new()
			body.transform = xf
			body.add_to_group("safe_ground")
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(cw, 0.5, 3.05)
			cs.shape = bs
			body.add_child(cs)
			add_child(body)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(cw, 0.55, 3.05)
			mi.mesh = bm
			mi.material_override = cmat
			mi.transform = xf
			add_child(mi)
			var lip := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 0.7
			lip.mesh = sm
			lip.material_override = cmat
			lip.transform = Transform3D(Basis(out, Vector3.UP, -t) * Basis.from_scale(Vector3(1.3, 0.6, 3.4)), cen + out * (cw * 0.5) + Vector3.UP * 0.05)
			add_child(lip)
			cornices.append([body, mi, cs, xf, Vector3(cw, 0.5, 3.05), 0.0, -1.0, lip])
			u += step


## Базовый лагерь у подножия и приюты: на полке (2), на плато, на Плече
func _build_camps() -> void:
	lodge = Node3D.new()
	lodge.set_script(LODGE)
	lodge.name = "BaseLodge"
	lodge.setup()
	builder.add_child(lodge)
	var start := M.point(0.0)
	var lc := Vector3(start.x - 46.0, 0.0, start.z + 66.0)
	var to_start := Vector2(start.x - lc.x, start.z - lc.z).normalized()
	lodge.build(builder, Vector3(lc.x, _gy(lc.x, lc.z), lc.z), to_start)
	for ci in M.CAMPS.size():
		var u: float = M.CAMPS[ci]
		var out := M.outward(u)
		var t := M.tangent(u)
		# изба — у скалы, дверью к краю полки (на тропу)
		var c := M.point(u) - out * (M.half_in(u) - 3.8)
		_make_hut(c, out, "ПРИЮТ «%s»\nпечка, нары, тепло" % ["ПЕРВЫЙ", "ВТОРОЙ"][ci],
			"Контрольная точка. Высота %d м — погрейтесь у печки" % int(M.height(u)), true)
	# на плато — у нижней станции канатки
	var pc := Vector3(M.CX + 18.0, M.H_SP, M.CZ - 22.0)
	_make_hut(pc, Vector3(0.6, 0.0, 0.8).normalized(), "ПРИЮТ «ПЛАТО»\nканатка на Плечо — рядом",
		"Контрольная точка. 380 м. Почините канатку — она везёт к вершине", true)
	# на Плече — приют, где пережидают ночь и буран
	var sc := Vector3(M.BX + 10.5, M.SH_Y, M.SH_ZS - 7.5)
	hut_top = _make_hut(sc, Vector3(-1.0, 0.0, 0.0), "ПРИЮТ «ПЛЕЧО»\nукрытие на ночь",
		"Контрольная точка. 520 м. Дальше — ночная дорога к стене", true)


func _make_hut(c: Vector3, door_dir: Vector3, title: String, sub: String, cp: bool) -> Node3D:
	var h := Node3D.new()
	h.set_script(HUT)
	h.name = "Hut%d" % huts.size()
	h.setup_hut(title, sub)
	h.set("with_checkpoint", cp)
	builder.add_child(h)
	# build ставит избу на 4 м «против двери» от середины двора — сдвигаю середину вперёд
	var dd := Vector3(door_dir.x, 0.0, door_dir.z).normalized()
	var yc := c + dd * 4.0
	h.build(builder, Vector3(yc.x, _gy(yc.x, yc.z), yc.z), Vector2(dd.x, dd.z))
	huts.append(h)
	warm_spots.append(h.fire_pos)
	return h


## Внутри какой-нибудь избы горы (для погоды: тут не метёт и тепло)
func in_cabin(p: Vector3) -> bool:
	if lodge and lodge.in_cabin(p):
		return true
	if ropeway and ropeway.in_cabin(p):
		return true
	for h in huts:
		if h.in_cabin(p):
			return true
	return false


func in_yard(p: Vector3) -> bool:
	return lodge != null and lodge.in_yard(p)


func _checkpoint(at: Vector3, size: Vector3, title: String, sub: String) -> void:
	var cp := Area3D.new()
	cp.set_script(CHECKPOINT)
	cp.name = "PeakCP_%d" % int(at.y)
	cp.set("snap_to_terrain", false)
	cp.set("size", size)
	cp.set("respawn_offset", Vector3(0.0, 0.6, 0.0))
	cp.set("title", title)
	cp.set("subtitle", sub)
	cp.position = at
	add_child(cp)


func _heater(at: Vector3) -> void:
	var hs := Node3D.new()
	hs.set_script(HEATER)
	hs.position = at
	add_child(hs)
	warm_spots.append(at)


## Держится за крюк / камень (держит E у точки) или вцепился в стену — ветер не сносит
func gripping(d: Node3D) -> bool:
	if _local.has(int(d.peer_id)):
		return true
	return d.get("snow") != null and int(d.snow.climb) > 0


## Тепло ли тут (у печки, в станции на вершине)
func warm_at(p: Vector3) -> bool:
	for w in warm_spots:
		if w.distance_to(p) < 4.0:
			return true
	if night and night.has_method("cold_inside") and hut_top and hut_top.in_cabin(p):
		return not night.cold_inside()
	return in_cabin(p)


## Вершина: станция «Пик», антенна, площадка приёма
func _build_summit() -> void:
	var s := M.summit()
	s.y = _gy(s.x, s.z)
	pad = s + Vector3(4.0, 0.0, 4.0)
	pad.y = _gy(pad.x, pad.z)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.75, 0.77, 0.8)
	metal.metallic = 0.6
	metal.roughness = 0.35
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.45, 0.08)
	var st := s + Vector3(4.0, 0.0, -9.0)
	st.y = _gy(st.x, st.z)
	# шаг 122: станция-маяк (Kenney Space Kit + решётчатая мачта с вращающимся маяком)
	beacon = Node3D.new()
	beacon.set_script(load("res://scenes/world/peak_beacon.gd"))
	beacon.name = "PeakBeacon"
	add_child(beacon)
	beacon.call("build", self, s, st, pad)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.3, 1.0, 0.5)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 1.0, 0.5)
	ring_mat.emission_energy_multiplier = 2.5
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = PAD_R - 0.15
	tm.outer_radius = PAD_R
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.position = pad + Vector3.UP * 0.05
	add_child(ring)
	_box(self, Vector3(PAD_R * 1.6, 0.12, PAD_R * 1.6), Transform3D(Basis.IDENTITY, pad + Vector3.UP * 0.03), metal, false)
	sign_at(pad + Vector3(0.0, 0.0, 3.5), "СТАНЦИЯ-МАЯК «ПИК»\nПоставь посылку\nв светящийся круг", Color(0.3, 0.9, 0.5))
	warm_spots.append(st)
	_heater(st + Vector3(-2.5, 0.0, 3.0))
	_checkpoint(s, Vector3(30, 10, 30), "Вершина «Пик»", "700 м. Пункт приёма — зелёный круг")


func _build_signs() -> void:
	var base := M.point(0.0) + Vector3(8.0, 0.0, 14.0)
	base.y = _gy(base.x, base.z)
	sign_at(base, "ПИК — 700 м\nТропа на предвершину (380 м), канатка на Плечо (520 м),\nночная дорога и ледовая стена 152 м — на ледорубах.\nВЕТЕР: в порыв — Ctrl (присесть) или держись за леер.\nМОРОЗ: держитесь вместе, грейтесь в приютах.", Color(0.95, 0.75, 0.1))
	for ob in obstacles:
		var t: Vector3 = ob["t"]
		var at: Vector3 = (ob["foot"] as Vector3) - t * 7.0 + (ob["out"] as Vector3) * (float(ob["hout"]) - 1.2)
		sign_at(at, "УСТУП\nОдин держит E у камня —\nдругой прыгает рядом.\nНаверху — E у крюка: лестница", Color(0.95, 0.75, 0.1))
	for c in M.CORNICES:
		var u: float = float(c[0]) - 8.0 / M.len_per_u(float(c[0]))
		var at2 := M.point(u) - M.outward(u) * (M.half_in(u) - 1.0)
		sign_at(at2, "КАРНИЗЫ!\nСнаружи — снег над пустотой.\nИдите у скалы, по одному", Color(1.0, 0.45, 0.3))


func sign_at(at: Vector3, text: String, col: Color, parent: Node3D = null) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 30
	lb.outline_size = 8
	lb.modulate = col
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.position = at + Vector3.UP * 2.6
	(parent if parent else self).add_child(lb)
	var pst := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.06
	cm.height = 1.8
	pst.mesh = cm
	pst.position = at + Vector3.UP * 0.9
	(parent if parent else self).add_child(pst)


func _spawn_main_parcel() -> void:
	var root := get_tree().current_scene
	if root == null or root.has_node("MainParcel"):
		return
	var p := PARCEL.instantiate()
	p.name = "MainParcel"
	p.set("display_name", "Посылка для станции «Пик»")
	p.set("base_price", 1000)
	var at := Vector3(4.0, 0.0, 1079.0)
	at.y = _gy(at.x, at.z) + 0.8
	p.position = at
	root.add_child(p)
	main_parcel = p


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_far_hide(delta)
	_scan_local(delta)
	if multiplayer.is_server():
		_server(delta)
	_update_visuals()
	for m in modules:
		if m.has_method("visual"):
			m.visual(delta)
	_update_hint(delta)


## Шаг 74: с горы не видно дна озера Ледяной реки (в 2 км, под льдом и туманом) — не рисуем его
var _far_t := 0.0
var _far_nodes: Array[Node3D] = []
func _far_hide(delta: float) -> void:
	_far_t -= delta
	if _far_t > 0.0:
		return
	_far_t = 1.0
	if _far_nodes.is_empty():
		for nm in ["LakeBed"]:
			var n := get_tree().current_scene.find_child(nm, true, false)
			if n is Node3D:
				_far_nodes.append(n as Node3D)
		if _far_nodes.is_empty():
			_far_t = 10.0
			return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var far := cam.global_position.z < -2300.0
	for n in _far_nodes:
		if is_instance_valid(n) and n.visible == far:
			n.visible = not far


func _scan_local(delta: float) -> void:
	var now_h := {}
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_local or d.is_dead or d.get("snow") == null or not M.on_mountain(d.global_position):
			_prev_floor.erase(int(d.peer_id))
			continue
		var pid := int(d.peer_id)
		var holding: bool = d._held("interact")
		var busy: bool = d.snow.busy()
		var hp := ""
		if holding and not busy:
			hp = _hold_point_of(d)
			if hp != "":
				now_h[pid] = hp
		var on_floor: bool = d.is_on_floor()
		_boost_air(d, pid, on_floor, delta)
		if not busy:
			_try_climb(d, holding)
			_try_boost(d, bool(_prev_floor.get(pid, false)), hp)
			for m in modules:
				if m.has_method("local") and not d.snow.busy():
					m.local(d, hp, holding, delta)
			_pose_hold(d, hp)
		_prev_floor[pid] = on_floor
	_local = now_h
	if multiplayer.is_server():
		return
	for k in now_h:
		if String(_sent.get(k, "")) != String(now_h[k]):
			_report.rpc_id(1, int(k), String(now_h[k]))
	for k2 in _sent:
		if not now_h.has(k2):
			_report.rpc_id(1, int(k2), "")
	_sent = now_h.duplicate()


## Поза моего дрона у точки «держи E» (подсаживаю, держу лестницу/верёвку…)
func _pose_hold(d: Node3D, hp: String) -> void:
	var pid := int(d.peer_id)
	var lift_t: float = float(_lift_until.get(pid, -1.0)) - now()
	if hp.begins_with("B"):
		var ob: Dictionary = obstacles[int(hp.substr(1))]
		var t: Vector3 = ob["t"]
		d.visual.rotation.y = atan2(t.x, t.z)           # спиной к уступу, лицом к тому, кто разбегается
		# шаг 76: встаю точно на камень — ладони там, куда прыгающий ставит ногу
		var bp: Vector3 = ob["boost"]
		if d.is_on_floor() and Vector2(d.global_position.x - bp.x, d.global_position.z - bp.z).length() > 0.03:
			var np: Vector3 = d.global_position.lerp(Vector3(bp.x, d.global_position.y, bp.z), 0.2)
			d.global_position = np
		if lift_t > 0.0:
			# k: <0 — друг встаёт в ладони (принимаю вес), 0..1 — присел и толкнул, 1..1.67 — руки вверх, обратно
			var el := HAND_T + LIFT_T + FOLLOW_T - lift_t
			d.snow.set_mpose(4, (el - HAND_T) / LIFT_T, (ob["boost"] as Vector3) - t * 0.45, -t)
		else:
			d.snow.set_mpose(3, 0.0, (ob["boost"] as Vector3) - t * 0.45, -t)
		return
	if hp.begins_with("A"):
		var ob2: Dictionary = obstacles[int(hp.substr(1))]
		d.snow.set_mpose(11, 0.0, ob2["ladder_top"], ob2["t"])
		return
	if d.snow.mpose in [3, 4, 11] and lift_t <= 0.0:
		d.snow.set_mpose(0)


func _hold_point_of(d: Node3D) -> String:
	var p := d.global_position
	var best := ""
	var bd := INF
	for id in holds:
		var h: Array = holds[id]
		var q: Vector3 = h[0]
		var dd := Vector2(q.x - p.x, q.z - p.z).length()
		if dd < float(h[1]) and absf(q.y - p.y) < float(h[2]) and dd < bd:
			bd = dd
			best = String(id)
	return best


@rpc("any_peer", "call_remote", "reliable")
func _report(id: int, hp: String) -> void:
	if hp == "":
		_remote.erase(id)
	else:
		_remote[id] = hp


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_active(arr: Array) -> void:
	var a := {}
	for k in range(0, arr.size() - 1, 2):
		a[String(arr[k])] = int(arr[k + 1])
	active = a


func _server(delta: float) -> void:
	_ladder_server()
	var a := {}
	var hm := {}
	for k in _local:
		a[String(_local[k])] = int(k)
		hm[int(k)] = String(_local[k])
	for k2 in _remote:
		a[String(_remote[k2])] = int(k2)
		hm[int(k2)] = String(_remote[k2])
	active = a
	hold_map = hm
	_sync_t -= delta
	if _online() and _sync_t <= 0.0:
		_sync_t = 0.1
		var arr: Array = []
		for k3 in active:
			arr.append(k3)
			arr.append(active[k3])
		_sync_active.rpc(arr)
	_cornice_server(delta)
	_parcel_server(delta)
	for m in modules:
		if m.has_method("server"):
			m.server(delta)


func ladder_down(i: int) -> bool:
	return _ladders.has(i)


## Хост: кто-то нажал E у мотка наверху — лестница падает и остаётся
func _ladder_server() -> void:
	for oi in obstacles.size():
		var ob: Dictionary = obstacles[oi]
		if ob.has("no_ladder") or _ladders.has(oi):
			continue
		if not holders(String(ob["hold_anchor"])).is_empty():
			if _online():
				_drop_ladder.rpc(oi, now())
			else:
				_drop_ladder(oi, now())


@rpc("authority", "call_local", "reliable")
func _drop_ladder(oi: int, t0: float) -> void:
	if _ladders.has(oi):
		return
	_ladders[oi] = t0
	var ob: Dictionary = obstacles[oi]
	SFX.play(self, ob["ladder_top"], "slide", 0.0, 0.8)
	SFX.play(self, ob["ladder_top"], "creak", -4.0)


## Лестница: держат наверху — внизу держи E у лестницы
func _try_climb(d: Node3D, holding: bool) -> void:
	if not holding or not d.is_on_floor() or d.held_parcel != null or d.held_friend != null:
		return
	var p := d.global_position
	for oi in obstacles.size():
		var ob: Dictionary = obstacles[oi]
		if absf(p.y - float(ob["y0"])) > 1.4 or ob.has("no_ladder"):
			continue
		var lf: Vector3 = ob["ladder_foot"]
		if ladder_down(oi) and Vector2(lf.x - p.x, lf.z - p.z).length() < 1.1:
			var hgt := float(ob["y1"]) - float(ob["y0"])
			d.snow.start_climb(1, (ob["ladder_base"] as Vector3) - (ob["t"] as Vector3) * 0.25, hgt, -(ob["t"] as Vector3), ob["top_exit"], oi, self)
			return


# ---------------------------------------------------------------------------
#  Подсадка: разбегаюсь, прыгаю у друга — встаю ногой в его ладони, он поднимает и бросает вверх,
#  у края цепляюсь руками и вылезаю
# ---------------------------------------------------------------------------

func _try_boost(d: Node3D, was_floor: bool, my_hold: String) -> void:
	if my_hold != "" or d.velocity.y < 2.0 or not was_floor:
		return
	var p := d.global_position
	for oi in obstacles.size():
		var ob: Dictionary = obstacles[oi]
		var hid := String(ob["hold_boost"])
		if not active.has(hid) or int(active[hid]) == int(d.peer_id):
			continue
		var b: Vector3 = ob["boost"]
		if Vector2(b.x - p.x, b.z - p.z).length() < 2.6 and absf(b.y - p.y) < 1.3:
			d.snow.start_scripted(4, self, {"ob": oi, "from": p, "holder": int(active[hid])})
			if _online():
				_boost_event.rpc(int(active[hid]), oi)
			else:
				_boost_event(int(active[hid]), oi)
			return


## Подсаживающему: «на ладони встали — поднимай» (у его хозяина)
@rpc("any_peer", "call_local", "reliable")
func _boost_event(holder: int, _oi: int) -> void:
	for d in get_tree().get_nodes_in_group("player"):
		if int(d.peer_id) == holder and d.is_local:
			_lift_until[holder] = now() + HAND_T + LIFT_T + FOLLOW_T
			if d == Network.local_player:
				d.add_shake(0.12)


## Сценарий движения (зовёт snow_state, пока climb ≥ 4): подсадка (4), вылезти на уступ (5)
func drive(d: Node3D, kind: int, t: float, data: Dictionary, _delta: float) -> void:
	var ob: Dictionary = obstacles[int(data["ob"])]
	var tv: Vector3 = ob["t"]
	if kind == 4:
		var boost: Vector3 = ob["boost"]
		var jr := tv.cross(Vector3.UP).normalized()          # правая рука прыгающего (лицом к уступу, +t)
		d.visual.rotation.y = atan2(-tv.x, -tv.z)
		d.velocity = Vector3.ZERO
		var y1 := float(ob["y1"])
		var shoulders := boost + Vector3.UP * 1.32 - tv * 0.06
		# куда долетаю: лицом к скале, руки — у самого края
		var grab := Vector3(float((ob["foot"] as Vector3).x), y1 - 2.0, float((ob["foot"] as Vector3).z)) - tv * 0.38
		var t_rel := HAND_T + LIFT_T * 0.85
		var t2 := t_rel + FLY_T
		if t < HAND_T:
			# подбегаю вплотную, руки — на плечи другу, правую ногу — в его сцепленные ладони
			var k := smoothstep(0.0, 1.0, t / HAND_T)
			var o0 := cup_point(boost, tv, -0.1) - _foot_off(tv, jr, 0.0)
			var pos := from_lerp(data["from"], o0, k)
			d.global_position = pos
			d.snow.set_mpose(5, 0.25 * k, shoulders, tv)
		elif t < t_rel:
			# стою ногой в ладонях: друг приседает — проседаю с ним, толкает — поднимает меня на ноге
			var k2 := (t - HAND_T) / LIFT_T
			var sv := smoothstep(0.35, 0.85, k2)
			d.global_position = cup_point(boost, tv, k2) - _foot_off(tv, jr, sv)
			d.snow.set_mpose(5, 0.25 + 0.5 * sv, shoulders + Vector3.UP * 1.2 * sv, tv)
			data["rel"] = d.global_position
			if k2 > 0.35 and not data.has("push"):
				data["push"] = true
				SFX.play(self, boost + Vector3.UP, "thunk", -8.0, 1.6)
		elif t < t2:
			# оттолкнулся от ладоней — лечу к краю, руки тянутся вверх
			var k3 := (t - t_rel) / FLY_T
			var rel: Vector3 = data.get("rel", boost + Vector3.UP * 1.9)
			grab.y = maxf(grab.y, rel.y + 0.45)
			var pos3 := rel.lerp(grab, 1.0 - pow(1.0 - k3, 2.0))
			pos3.y = lerpf(rel.y, grab.y, 1.0 - pow(1.0 - k3, 3.0))
			d.global_position = pos3
			d.snow.set_mpose(5, 0.75 + 0.25 * k3, grab + Vector3.UP * 2.0, tv)
			# шаг 138: E в полёте — тоже засчитано (раньше «слишком рано» срывало — казалось, что E не работает)
			if d == Network.local_player and (d._just("interact") or d._held("interact")) and t > t_rel + FLY_T * 0.3:
				data["caught"] = true
			if not data.has("whoosh"):
				data["whoosh"] = true
				SFX.play(self, d.global_position, "puff", -8.0, 0.7)
		elif t < t2 + GRAB_T:
			# пальцы у края — успей схватиться (E)
			var k4 := (t - t2) / GRAB_T
			grab.y = maxf(grab.y, float((data.get("rel", boost) as Vector3).y) + 0.45)
			d.global_position = grab + Vector3.DOWN * 0.25 * k4 * k4
			d.snow.set_mpose(5, 1.0, grab + Vector3.UP * 2.0, tv)
			var me_local: bool = d == Network.local_player
			if me_local:
				_qte_show(Vector3(grab.x, y1 + 0.35, grab.z) + tv * 0.3, true)
			var bot_auto: bool = bool(d.get("is_bot")) and k4 > 0.35
			if bool(data.get("caught", false)) or bot_auto or (me_local and (d._just("interact") or d._held("interact"))):
				_qte_show(Vector3.ZERO, false)
				SFX.play(self, d.global_position + Vector3.UP * 2.0, "thunk", -6.0, 1.4)
				if me_local:
					d.add_shake(0.08)
				d.snow.end_scripted()
				d.snow.start_scripted(5, self, {"ob": int(data["ob"]), "from": d.global_position})
				return
		else:
			# не успел (или схватился раньше времени) — сорвался вниз
			if d == Network.local_player:
				_qte_show(Vector3.ZERO, false)
				say("Сорвался! Жми E, когда руки у края" if not bool(data.get("early", false)) else "Рано — руки соскользнули. Жми E у самого края")
				d.add_shake(0.12)
			SFX.play(self, d.global_position, "slide", -2.0, 0.7)
			d.snow.end_scripted()
			d.snow.set_mpose(0)
			d.velocity = -tv * 2.2 + Vector3.DOWN * 0.5
			d.set("_soft_landing", true)
	elif kind == 5:
		var from2: Vector3 = data["from"]
		var top: Vector3 = ob["top_exit"]
		var k3 := clampf(t / MANTLE_T, 0.0, 1.0)
		var edge_y := float(ob["y1"])
		var pos2 := Vector3.ZERO
		# шаг 76: ладони легли на край — вишу (ноги качнулись), подтягиваюсь, колено на край, встаю
		var hang := Vector3(from2.x, edge_y - 2.05, from2.z)
		var pk := 0.0
		if k3 < 0.2:
			var h0 := smoothstep(0.0, 1.0, k3 / 0.2)
			pos2 = from2.lerp(hang, h0) + tv * 0.05 * sin(h0 * PI)
			pk = 0.15 * h0
		elif k3 < 0.62:
			var a := smoothstep(0.0, 1.0, (k3 - 0.2) / 0.42)
			pos2 = hang.lerp(Vector3(from2.x, edge_y - 0.35, from2.z), a)
			pk = lerpf(0.15, 0.55, a)
		else:
			var b := smoothstep(0.0, 1.0, (k3 - 0.62) / 0.38)
			var mid := Vector3(from2.x, edge_y - 0.35, from2.z)
			pos2 = mid.lerp(top, b) + Vector3.UP * sin(b * PI) * 0.25
			pk = lerpf(0.55, 1.0, b)
		d.global_position = pos2
		d.velocity = Vector3.ZERO
		d.visual.rotation.y = atan2(-tv.x, -tv.z)
		d.snow.set_mpose(6, pk, (ob["foot"] as Vector3) + Vector3.UP * (edge_y - float(ob["y0"])) + tv * 0.05, tv)
		if k3 >= 1.0:
			d.snow.end_scripted()
			d.snow.set_mpose(0)
			d.global_position = top
			d.velocity = Vector3.ZERO


## Шаг 76: где сцепленные ладони подсаживающего при ходе k (те же кривые, что у его рук в exo_suit, поза 4)
static func cup_point(boost: Vector3, tv: Vector3, k: float) -> Vector3:
	var hh := 0.45
	var ff := 0.42
	if k >= 0.0 and k < 0.35:
		hh = lerpf(0.45, 0.3, k / 0.35)
		ff = lerpf(0.42, 0.38, k / 0.35)
	elif k >= 0.35 and k < 0.8:
		var b := smoothstep(0.0, 1.0, (k - 0.35) / 0.45)
		hh = lerpf(0.3, 1.95, b)
		ff = lerpf(0.38, 0.08, b)
	elif k >= 0.8:
		var c := clampf((k - 0.8) / 0.35, 0.0, 1.0)
		hh = lerpf(1.95, 2.12, sin(c * PI * 0.5))
		ff = lerpf(0.08, -0.12, c)
	return boost - tv * ff + Vector3.UP * (hh - 0.02)


## Где правая стопа прыгающего относительно его точки: s=0 — нога поднята вперёд (в ладони), s=1 — стою на ней
static func _foot_off(tv: Vector3, jr: Vector3, s: float) -> Vector3:
	return jr * 0.1 + Vector3.UP * (0.42 * (1.0 - s) + 0.05) + tv * (0.25 * (1.0 - s))


static func from_lerp(a: Vector3, b: Vector3, k: float) -> Vector3:
	var p := a.lerp(b, k)
	p.y += sin(k * PI) * 0.25
	return p


## В полёте после подсадки: несёт к уступу; у края — цепляюсь и вылезаю
func _boost_air(d: Node3D, pid: int, on_floor: bool, delta: float) -> void:
	var bst: Array = _boosted.get(pid, [])
	if bst.is_empty():
		return
	bst[0] = float(bst[0]) - delta
	var bd: Vector3 = bst[1]
	var ob: Dictionary = obstacles[int(bst[2])]
	var hv := Vector3(d.velocity.x, 0.0, d.velocity.z)
	if hv.dot(bd) < BOOST_FWD:
		d.velocity += bd * (BOOST_FWD - hv.dot(bd))
	var p := d.global_position
	var along := (p - (ob["foot"] as Vector3)).dot(bd)
	var edge_y := float(ob["y1"])
	if not d.snow.busy() and p.y > edge_y - 1.35 and along > -1.9 and along < 0.6:
		_boosted.erase(pid)
		d.snow.start_scripted(5, self, {"ob": int(bst[2]), "from": p})
		return
	if float(bst[0]) <= 0.0 or (on_floor and float(bst[0]) < 1.0):
		_boosted.erase(pid)
		if d.snow.mpose == 5:
			d.snow.set_mpose(0)


func gust_hard() -> bool:
	return weather != null and weather.gust_hard()


# ---------------------------------------------------------------------------
#  Карнизы
# ---------------------------------------------------------------------------

func _cornice_server(delta: float) -> void:
	var t_now := Time.get_ticks_msec() / 1000.0
	for ci in cornices.size():
		var c: Array = cornices[ci]
		if float(c[6]) > t_now:
			continue
		var xf: Transform3D = c[3]
		var sz: Vector3 = c[4]
		var n := 0
		for d in get_tree().get_nodes_in_group("player"):
			if d.is_dead:
				continue
			var l := xf.affine_inverse() * (d as Node3D).global_position
			if absf(l.x) < sz.x * 0.5 + 0.4 and absf(l.z) < sz.z * 0.5 + 0.4 and l.y > -0.8 and l.y < 1.2:
				n += 1
		if n > 0:
			c[5] = float(c[5]) + delta
			if float(c[5]) > (CORNICE_T2 if n >= 2 else CORNICE_T):
				c[5] = 0.0
				if _online():
					_collapse.rpc(ci)
				else:
					_collapse(ci)
		else:
			c[5] = maxf(float(c[5]) - delta * 0.5, 0.0)


@rpc("authority", "call_local", "reliable")
func _collapse(ci: int) -> void:
	var c: Array = cornices[ci]
	c[6] = Time.get_ticks_msec() / 1000.0 + CORNICE_BACK
	(c[2] as CollisionShape3D).disabled = true
	(c[1] as MeshInstance3D).visible = false
	(c[7] as MeshInstance3D).visible = false
	var xf: Transform3D = c[3]
	for k in 5:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.6, 1.2), randf_range(0.3, 0.6), randf_range(0.6, 1.2))
		mi.mesh = bm
		mi.material_override = (c[1] as MeshInstance3D).material_override
		add_child(mi)
		mi.global_position = xf * Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.3, 1.3))
		var tw := create_tween()
		tw.tween_property(mi, "global_position", mi.global_position + Vector3(randf_range(-2, 2), -40.0, randf_range(-2, 2)), 2.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(mi.queue_free)
	if Network.local_player and Network.local_player.global_position.distance_to(xf.origin) < 30.0:
		Network.local_player.add_shake(0.3)
	get_tree().create_timer(CORNICE_BACK).timeout.connect(func():
		(c[2] as CollisionShape3D).disabled = false
		(c[1] as MeshInstance3D).visible = true
		(c[7] as MeshInstance3D).visible = true)


# ---------------------------------------------------------------------------
#  Посылка: упала с горы — назад; на площадке приёма — финал
# ---------------------------------------------------------------------------

func _parcel_server(delta: float) -> void:
	if main_parcel == null or not is_instance_valid(main_parcel) or delivered:
		return
	var pp: Vector3 = (main_parcel as Node3D).global_position
	var held: bool = main_parcel.is_held
	var hoisted: bool = (face != null and face.has_method("parcel_busy") and face.parcel_busy()) or (spires != null and spires.parcel_busy())
	if held and M.on_mountain(pp):
		for h in main_parcel.holders:
			var drone := drone_by_id(int(h))
			if drone and drone.is_on_floor():
				_parcel_last = drone.global_position + Vector3.UP * 0.8
	_parcel_back_t -= delta
	if not held and not hoisted and _parcel_last != Vector3.INF and pp.y < _parcel_last.y - 18.0 and M.on_mountain(pp) and _parcel_back_t <= 0.0:
		_parcel_back_t = 2.0
		var rb := main_parcel as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.global_position = _parcel_last
		get_tree().call_group("level", "show_banner", "Посылка сорвалась вниз…", "Её вернули туда, где несли в последний раз")
	if not held and not hoisted and Vector2(pp.x - pad.x, pp.z - pad.z).length() < PAD_R and absf(pp.y - pad.y) < 1.6 \
			and (main_parcel as RigidBody3D).linear_velocity.length() < 1.0:
		var xf := (main_parcel as Node3D).global_transform
		if _online():
			main_parcel._set_delivered.rpc(xf)
			_finish.rpc(int(main_parcel.price), int(main_parcel.base_price))
		else:
			main_parcel._set_delivered(xf)
			_finish(int(main_parcel.price), int(main_parcel.base_price))


## Последнее надёжное место посылки (лебёдка подняла — тут)
func set_parcel_last(p: Vector3) -> void:
	_parcel_last = p


func drone_by_id(id: int) -> Node3D:
	for d in get_tree().get_nodes_in_group("player"):
		if int(d.peer_id) == id:
			return d
	return null


@rpc("authority", "call_local", "reliable")
func _finish(price: int, base_price: int) -> void:
	if delivered:
		return
	delivered = true
	if beacon:
		beacon.call("celebrate")
	var level := get_tree().get_first_node_in_group("level")
	var elapsed: float = float(level.get("elapsed")) if level else 0.0
	var deaths: int = int(level.get("deaths")) if level else 0
	var names: Array[String] = []
	for d in get_tree().get_nodes_in_group("player"):
		names.append(String(d.get("player_name")))
	_final = CanvasLayer.new()
	_final.layer = 40
	add_child(_final)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_final.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(760, 420)
	box.position = Vector2(-380, -210)
	_final.add_child(box)
	var lines := [
		["ПОСЫЛКА ДОСТАВЛЕНА!", 54, Color(0.4, 1.0, 0.55)],
		["Станция «Пик», высота %d м" % int(M.PEAK), 26, Color(0.85, 0.92, 1.0)],
		["", 14, Color.WHITE],
		["Время экспедиции: %s" % _fmt(elapsed), 30, Color.WHITE],
		["Поломок дронов: %d" % deaths, 30, Color.WHITE],
		["Состояние посылки: %d%%  (%d кр из %d)" % [roundi(100.0 * price / maxf(base_price, 1.0)), price, base_price], 30, Color.WHITE],
		["Команда: %s" % ", ".join(names), 24, Color(1.0, 0.85, 0.5)],
		["", 14, Color.WHITE],
		["Спасибо за игру!   (Esc — закрыть)", 22, Color(0.75, 0.8, 0.9)],
	]
	for ln in lines:
		var l := Label.new()
		l.text = ln[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(ln[1]))
		l.add_theme_color_override("font_color", ln[2])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		box.add_child(l)


func _fmt(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _unhandled_input(event: InputEvent) -> void:
	if _final and event.is_action_pressed("ui_cancel"):
		_final.queue_free()
		_final = null


# ---------------------------------------------------------------------------
#  Вид и подсказки
# ---------------------------------------------------------------------------

func _update_visuals() -> void:
	for oi in obstacles.size():
		var ob: Dictionary = obstacles[oi]
		if ob.has("no_ladder"):
			continue
		var down := ladder_down(oi)
		var lad := ob["ladder_mi"] as Node3D
		var roll := ob["roll_mi"] as MeshInstance3D
		if not down:
			lad.visible = false
			roll.visible = true
			continue
		# разматывается сверху вниз за 0.7 с, внизу — стук
		var k := clampf((now() - float(_ladders[oi])) / 0.7, 0.0, 1.0)
		var kk := 1.0 - pow(1.0 - k, 2.0)
		var top: Vector3 = (ob["ladder_top"] as Vector3) + Vector3.UP * 0.3
		lad.visible = true
		lad.transform = Transform3D(Basis.from_scale(Vector3(1.0, maxf(kk, 0.02), 1.0)), Vector3(0.0, top.y * (1.0 - maxf(kk, 0.02)), 0.0))
		roll.visible = k < 1.0
		roll.scale = Vector3.ONE * (1.0 - 0.7 * k)
		if k >= 1.0 and not ob.has("ladder_thud"):
			ob["ladder_thud"] = true
			(ob["ladder_cs"] as CollisionShape3D).disabled = false
			SFX.play(self, ob["ladder_base"], "thunk", -2.0, 1.3)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 7)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-500, -150)
	_hint.size = Vector2(1000, 60)
	_hint.visible = false
	layer.add_child(_hint)
## Шаг 76: «E» маленькой меткой у края уступа (над руками), мигает; без полосок и крупных надписей
func _qte_show(at: Vector3, on: bool) -> void:
	if _qte == null:
		_qte = Label3D.new()
		_qte.text = "E"
		_qte.font_size = 56
		_qte.outline_size = 12
		_qte.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_qte.no_depth_test = true
		_qte.fixed_size = true
		_qte.pixel_size = 0.0012
		_qte.modulate = Color(1.0, 0.88, 0.35)
		add_child(_qte)
	_qte.visible = on
	if on:
		_qte.global_position = at
		_qte.modulate.a = 0.65 + 0.35 * sin(now() * 18.0)

func say(msg: String) -> void:
	_hint.text = msg
	_hint_t = 0.25


func _update_hint(delta: float) -> void:
	_hint_t -= delta
	var me: Node3D = Network.local_player
	if me and is_instance_valid(me) and not me.is_dead and M.on_mountain(me.global_position):
		_context_hint(me)
	_hint.visible = _hint_t > 0.0


func _context_hint(me: Node3D) -> void:
	for m in modules:
		if m.has_method("hint"):
			var h: String = m.hint(me)
			if h != "":
				say(h)
				return
	if me.snow.climb == 1:
		say("Поднимаюсь по лестнице…")
		return
	var hp := _hold_point_of(me)
	var holding: bool = me._held("interact")
	if hp.begins_with("B"):
		say("Подсаживаешь — друг разбегается и прыгает рядом" if holding else "Держи E — сложить руки «ступенькой» и подсадить друга")
		return
	if hp.begins_with("A"):
		var oiA := -1
		for k in obstacles.size():
			if String(obstacles[k].get("hold_anchor", "")) == hp:
				oiA = k
		say("Лестница сброшена — друг может лезть (держи E у её низа)" if oiA >= 0 and ladder_down(oiA) else "E — сбросить лестницу друзьям внизу")
		return
	if weather and weather.intensity > 0.3 and weather.gust_phase in [1, 2]:
		var safe: bool = me.get("sitting") or gripping(me) or weather.protection < 0.05
		if not safe:
			say("Гул в скалах — сейчас ПОРЫВ! Ctrl — присесть, или схватись за леер / фонарь" if weather.gust_phase == 1 \
				else "ПОРЫВ! Ctrl — присесть, или держись за леер / фонарь!")
			return
	var p := me.global_position
	for oi in obstacles.size():
		var ob2: Dictionary = obstacles[oi]
		if absf(p.y - float(ob2["y0"])) > 1.4:
			continue
		var rel := p - (ob2["foot"] as Vector3)
		if absf(rel.dot(ob2["t"] as Vector3)) > 4.0 or absf(rel.dot(ob2["out"] as Vector3)) > 7.0:
			continue
		if active.has(String(ob2["hold_boost"])):
			say("Разбегись и прыгни рядом с другом — он подсадит!")
		elif not ob2.has("no_ladder") and ladder_down(oi):
			say("Лестница сброшена: держи E у неё — лезть")
		elif oi == 0:
			say("Уступ 4,5 м: друг держит E у камня — подсадит до края; у края ЖМИ E — ухватиться!")
		else:
			say("Уступ: одному не запрыгнуть. Друг держит E у камня — подсадит")
		return
