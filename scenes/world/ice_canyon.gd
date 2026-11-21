extends Node3D
## Воронка, узкий проход и Ледяной каньон (шаги 41–42) — между Ледяным полем и старым озером.
##
##   z 385…330  Воронка: поле сужается, по краям — высокие ледяные стены
##   z 330…279  Узкий проход и горловина между ледяными стенами, контрольная точка
##   z 279…-352 Ледяное плато, прорезанное ущельями. План дорог, развилок и ловушек —
##              в canyon_layout.gd. Каждая дорога идёт по своему ущелью: внизу пропасть,
##              по бокам — стены, соседних дорог не видно.
##
## Дороги — длинные призмы: сверху снег (держит) или гладкий лёд (скользко, на спуске несёт),
## бока — отвесный лёд до дна пропасти. Упал — разбился (дрон гибнет ниже y = -20).
## Всё построено по фиксированным точкам — одинаково у всех игроков.

const HUMMOCKS := preload("res://scenes/world/hummock_builder.gd")
const BRIDGE := preload("res://scenes/world/thin_ice_bridge.gd")
const SLOW_FLOOR := preload("res://scenes/world/slow_ice_floor.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")
const HEATER := preload("res://scenes/world/heat_source.gd")
const WIND := preload("res://scenes/world/wind_band.gd")
const CAVE := preload("res://scenes/world/cave_trap.gd")
const CRUMBLE := preload("res://scenes/world/crumble_road.gd")
const SNOW_BRIDGE := preload("res://scenes/world/snow_bridge.gd")
const ICEFALL := preload("res://scenes/world/falling_ice.gd")
const PENDULUM := preload("res://scenes/world/pendulum.gd")
const VISE := preload("res://scenes/world/vise_walls.gd")
const GEYSER_CRACK := preload("res://scenes/world/geyser_crack.gd")
const LIFT := preload("res://scenes/world/cable_lift.gd")
const LIFT_ITEM := preload("res://scenes/world/lift_item.gd")
const DEBRIS := preload("res://scenes/world/debris.gd")
const THEMES := preload("res://scenes/world/canyon_themes.gd")
const FORMS_B := preload("res://scenes/world/canyon_forms.gd")
const GATE := preload("res://scenes/world/canyon_gate.gd")
const ROCKS := preload("res://scenes/world/canyon_rocks.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const MIST_SHADER := preload("res://shaders/abyss_mist.gdshader")
const L := preload("res://scenes/world/canyon_layout.gd")

const BOTTOM := -72.0           ## Докуда опускаются бока дорог (ниже дна пропасти)
const ICE_FRICTION := 0.045     ## Как у льда озера

## Развилки: где развилка, какие дороги из неё — выбор (ворота над ними), и что написано на табличке
const FORKS := {
	"A": [["AW", "AE"], "Две дороги.\nВерная — одна"],
	"B": [["BE", "BW"], "Здесь повернули назад\nне все"],
	"C": [["CW", "CE"], "Слышишь ветер?\nЗначит, выход близко"],
	"D": [["DW", "DE"], "Маятник отсчитывает\nвремя смелых"],
	"E": [["EE", "EN"], "Стены сходятся —\nне останавливайся"],
	"F1": [["F1C", "F1P"], "Тепло обманчиво"],
	"F2": [["F2a", "F2b"], "Свет в конце —\nне всегда выход"],
	"F3": [["F3a", "F3b"], "Лёд тонок,\nвода глубока"],
	"F4": [["F4a", "F4b"], "Кто спешит —\nтого раздавит"],
	"F5": [["F5a", "F5b"], "Снег мягок,\nда не держит"],
}

var _snow_mat: ShaderMaterial
var _wl: Array[float] = []          ## полуширина дороги влево/вправо у каждой точки (карниз шире к стене)
var _wr: Array[float] = []
var _stair_mat: ShaderMaterial
var _ice_mat: ShaderMaterial
var _cliff_mat: ShaderMaterial
var _snow_pm: PhysicsMaterial
var _ice_pm: PhysicsMaterial
var _terrain: Node
var _env: Environment
var _base_fog := 0.0
var _fog_k := 0.0
var _platforms: Array = []      ## [центр, радиус]
## Отрезки дорог (для проверок и тестов): [a, b, ширина, вид]
var segments: Array = []
## Осевые линии дорог (точки через ~1.2 м) — для тестов и ботов
var road_paths := {}
var cliff_spots: Array = []         ## места для наплывов на боках дорог и площадок: [край, наружу, низ, клин, имя]
var face_spots: Array = []          ## места для наплывов на лицевых стенах тоннелей: [точка, наружу]
var rocks: RefCounted
var form_sections := {}              ## дорога → {kind, side, k0, k1} (участок особой формы на road_paths)
var forms: RefCounted
var gate: Node3D
var cave: Node3D
var fake_bridge: StaticBody3D
var trap_bridges: Array = []
var fake_bridges: Array = []
var crumbles: Array = []
var lift: Node3D
var parts: Array = []
var pit_floor: StaticBody3D
var themes: RefCounted


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain")
	_make_materials()
	for key in L.PLATFORMS:
		var p: Array = L.PLATFORMS[key]
		_platforms.append([Vector3(p[0], p[1], p[2]), float(p[3]), String(key)])
	for key in L.ROADS:
		_road(String(key), L.ROADS[key], float(L.ROAD_WIDTH.get(key, 7.5)), BOTTOM)
	for p in _platforms:
		_platform(p[0], p[1], p[2])
	_twin_bridges()
	_traps()
	forms = FORMS_B.new(self)
	forms.build()
	# финал: ворота на выходе и печати на дне Глубокого озера
	gate = Node3D.new()
	gate.set_script(GATE)
	gate.name = "ExitGate"
	add_child(gate)
	gate.spawn_parts(self)
	_walls()
	_forks()
	# ледяные наплывы на стенах ущелий, обрывах прудов и боках дорог — стены не плоские
	rocks = ROCKS.new(self)
	rocks.build(_terrain, _cliff_mat)
	_mist()
	_checkpoints()
	_heaters()
	_winds()
	var we := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment if get_tree().current_scene else null
	if we and we.environment:
		_env = we.environment
		_base_fog = _env.fog_density


func _physics_process(_delta: float) -> void:
	if forms:
		forms.physics_tick()


## В каньоне дымка реже — видно, как глубоко внизу пропасть
func _process(delta: float) -> void:
	if themes:
		themes.tick(Network.game_time if Network.in_game else Time.get_ticks_msec() / 1000.0)
	if _env == null:
		return
	var me = Network.local_player
	var want := 0.0
	if me and is_instance_valid(me):
		var p: Vector3 = me.global_position
		if p.z < IceRiver.PASS_S and p.z > IceRiver.CANYON_N - 10.0 and absf(p.x) < 330.0:
			want = 1.0
	if want == 0.0 and _fog_k == 0.0:
		return
	_fog_k = move_toward(_fog_k, want, delta * 0.5)
	_env.fog_density = _base_fog * lerpf(1.0, 0.4, smoothstep(0.0, 1.0, _fog_k))


# ---------------------------------------------------------------------------
#  Материалы: снег сверху, гладкий лёд на спусках, слоистый лёд на обрывах
# ---------------------------------------------------------------------------

func _make_materials() -> void:
	_snow_mat = _ice_shader_mat(Color(0.42, 0.56, 0.7), Color(0.74, 0.84, 0.93), Color(0.95, 0.98, 1.0), 1.8, 0.45)
	_ice_mat = _ice_shader_mat(Color(0.02, 0.16, 0.32), Color(0.16, 0.48, 0.74), Color(0.42, 0.7, 0.9), 0.0, 0.05)
	_ice_mat.set_shader_parameter("polish", 1.0)
	_ice_mat.set_shader_parameter("crack_amount", 0.6)
	_cliff_mat = _ice_shader_mat(Color(0.02, 0.1, 0.2), Color(0.13, 0.33, 0.5), Color(0.6, 0.8, 0.92), 0.6, 0.12)
	_cliff_mat.set_shader_parameter("band_amount", 0.4)
	_cliff_mat.set_shader_parameter("band_scale", 0.35)
	_cliff_mat.set_shader_parameter("depth_dark", 1.0)
	_snow_pm = PhysicsMaterial.new()
	_snow_pm.friction = 1.0
	_ice_pm = PhysicsMaterial.new()
	_ice_pm.friction = ICE_FRICTION


func _ice_shader_mat(deep: Color, mid: Color, edge: Color, snow: float, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ICE_SHADER
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("mid", mid)
	m.set_shader_parameter("edge", edge)
	m.set_shader_parameter("snow_amount", snow)
	m.set_shader_parameter("base_rough", rough)
	m.set_shader_parameter("band_scale", 1.2)
	return m


# ---------------------------------------------------------------------------
#  Дорога: плавная линия через точки, сверху — полоса, по бокам — обрыв до дна
#  (bottom — докуда бока: у дорог — до дна пропасти, у мостов — толщина пролёта)
# ---------------------------------------------------------------------------

func _road(road_name: String, pts: Array, width: float, bottom: float) -> void:
	var ctrl: Array[Vector3] = []
	var kinds: Array[String] = []
	for p in pts:
		ctrl.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		kinds.append(String(p[3]))
	# концы у площадок — продлить внутрь площадки (до половины радиуса)
	for pl in _platforms:
		var c: Vector3 = pl[0]
		var r: float = pl[1]
		for end in [0, 1]:
			var e: Vector3 = ctrl[0] if end == 0 else ctrl[-1]
			var flat := Vector2(e.x - c.x, e.z - c.z)
			if flat.length() < r + 14.0 and flat.length() > r * 0.5 and absf(e.y - c.y) < 1.0:
				var inner := Vector3(c.x, c.y, c.z) + Vector3(flat.x, 0.0, flat.y).normalized() * r * 0.45
				if end == 0:
					ctrl.insert(0, inner)
					kinds.insert(0, "s")
				else:
					ctrl.append(inner)
					kinds[-1] = "s"
					kinds.append("")
	# высота вдоль дороги — плавная кривая без ступенек (монотонный сплайн по длине пути)
	var dist: Array[float] = [0.0]
	for i in range(1, ctrl.size()):
		dist.append(dist[-1] + maxf(Vector2(ctrl[i].x - ctrl[i - 1].x, ctrl[i].z - ctrl[i - 1].z).length(), 0.01))
	var slope := _mono_slopes(ctrl, dist)
	# выборка точек по кривой
	var pos: Array[Vector3] = []
	var qkind: Array[String] = []       # вид полосы от точки k до k+1
	for i in ctrl.size() - 1:
		var p0: Vector3 = ctrl[maxi(i - 1, 0)] if i > 0 else ctrl[i] * 2.0 - ctrl[i + 1]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[i + 2] if i + 2 < ctrl.size() else p2 * 2.0 - p1
		var n := maxi(int(ceil(Vector2(p2.x - p1.x, p2.z - p1.z).length() / 1.2)), 2)
		for k in n:
			var t := float(k) / n
			var q := _catmull(p0, p1, p2, p3, t)
			q.y = _hermite(p1.y, p2.y, slope[i], slope[i + 1], dist[i + 1] - dist[i], t)
			pos.append(q)
			qkind.append(kinds[i])
		segments.append([p1, p2, width, kinds[i]])
	pos.append(ctrl[-1])
	road_paths[road_name] = pos
	# поперечные векторы
	var sides: Array[Vector3] = []
	for k in pos.size():
		var a: Vector3 = pos[maxi(k - 1, 0)]
		var b: Vector3 = pos[mini(k + 1, pos.size() - 1)]
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		sides.append(Vector3(-t.z, 0.0, t.x))
	var hw := width * 0.5
	# особая форма: на участке [k0, k1] дороги нет (подвесной мост, льдины) или она иная
	var form: Array = L.FORMS.get(road_name, [])
	var kind := ""
	var sec0 := 0
	var sec1 := 0
	var acc: Array[float] = [0.0]
	for k in range(1, pos.size()):
		acc.append(acc[-1] + pos[k].distance_to(pos[k - 1]))
	if not form.is_empty():
		kind = String(form[0])
		var t0: float = form[2]
		var t1: float = form[3]
		while sec0 < pos.size() - 1 and acc[sec0] < acc[-1] * t0:
			sec0 += 1
		sec1 = sec0
		while sec1 < pos.size() - 1 and acc[sec1] < acc[-1] * t1:
			sec1 += 1
		form_sections[road_name] = {"kind": kind, "side": int(form[1]), "k0": sec0, "k1": sec1}
	var k0 := pos.size()
	var k1 := pos.size()
	if kind == "rope" or kind == "floes":
		k0 = sec0
		k1 = sec1
	# низ боков у каждой точки: до дна пропасти, у мостков и спирали — тонкий настил, у арки — дуга
	var bot: Array[float] = []
	var span := maxf(acc[sec1] - acc[sec0], 1.0) if kind == "arch" else 1.0
	for k in pos.size():
		var y := bottom
		if kind == "stilts":
			y = pos[k].y - 0.7
		elif kind == "spiral":
			y = pos[k].y - 1.0
		elif kind == "arch" and k >= sec0 and k <= sec1:
			var u := (acc[k] - acc[sec0]) / span
			y = maxf(pos[k].y - 1.1 - span * 0.42 * pow(1.0 - sin(PI * u), 1.6), BOTTOM)
		bot.append(y)
	var flare := 0.32 if kind == "ridge" else 0.0
	# карниз и мостки: со стороны стены дорога доходит до самой стены — без щели и без «бумажных» полос
	_wl.clear()
	_wr.clear()
	for k in pos.size():
		_wl.append(hw)
		_wr.append(hw)
	if kind == "ledge" or kind == "stilts":
		var side := float(form[1])
		var ext: Array[float] = []
		for k in pos.size():
			var g := _wall_gap(pos[k], sides[k] * side, hw, pos[k].y + 0.4)
			ext.append(clampf(g + 1.2, 0.0, 7.5) if g < 6.5 else 0.0)
		for k in pos.size():
			var e := 0.0
			var n := 0
			for j in range(maxi(k - 2, 0), mini(k + 3, pos.size())):
				e += ext[j]
				n += 1
			if side > 0.0:
				_wr[k] = hw + e / n
			else:
				_wl[k] = hw + e / n
	var ranges: Array = []
	if k0 < pos.size():
		ranges = [[0, k0], [k1, pos.size() - 1]]
	else:
		ranges = [[0, pos.size() - 1]]
	# верх: по кускам одного вида — свой материал и своё трение
	for rg in ranges:
		var r0: int = rg[0]
		var r1: int = rg[1]
		if r1 <= r0:
			continue
		var run_start := r0
		for k in range(r0 + 1, r1 + 1):
			var end_run := k == r1 or qkind[k] != qkind[run_start]
			if end_run:
				_road_top(road_name, pos, sides, hw, run_start, k, qkind[run_start])
				run_start = k
	# бока и торцы (одним куском) + упрощённые столкновения боков (чтобы не проваливаться сквозь них)
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cf := PackedVector3Array()
	for k in pos.size() - 1:
		if k >= k0 and k < k1:
			continue
		for sgn in [-1.0, 1.0]:
			var s0: Vector3 = sides[k] * sgn * (_wr[k] if sgn > 0.0 else _wl[k])
			var s1: Vector3 = sides[k + 1] * sgn * (_wr[k + 1] if sgn > 0.0 else _wl[k + 1])
			var a := pos[k] + s0
			var b := pos[k + 1] + s1
			var out: Vector3 = (sides[k] + sides[k + 1]).normalized() * sgn
			_wall_pts(v, nrm, a, b, out, bot[k], bot[k + 1], flare)
			# места для ледяных наплывов на боку (canyon_rocks.gd); у стены карниза бок спрятан в стене
			if k % 5 == 0 and kind != "stilts" and kind != "spiral" and not (kind == "tunnel" and k >= sec0 - 2 and k <= sec1 + 2):
				if not (kind == "ledge" and sgn * float(form[1]) > 0.0):
					cliff_spots.append([a, out, bot[k], flare, road_name])
			var ca := Vector3(a.x, maxf(bot[k], a.y - 24.0), a.z) + out * minf((a.y - maxf(bot[k], a.y - 24.0)) * flare, 8.0)
			var cb := Vector3(b.x, maxf(bot[k + 1], b.y - 24.0), b.z) + out * minf((b.y - maxf(bot[k + 1], b.y - 24.0)) * flare, 8.0)
			cf.append_array(PackedVector3Array([a, b, cb, a, cb, ca]))
	var ends: Array[int] = [0, pos.size() - 1]
	if k0 < pos.size():
		ends.append(k0)
		ends.append(k1)
	for e in ends:
		var d := (pos[mini(e + 1, pos.size() - 1)] - pos[maxi(e - 1, 0)])
		d.y = 0.0
		var out := -d.normalized() if (e == 0 or e == k1) else d.normalized()
		var l := pos[e] - sides[e] * _wl[e]
		var r := pos[e] + sides[e] * _wr[e]
		_wall_pts(v, nrm, l, r, out, bot[e], bot[e], 0.0)
	if kind == "arch":
		# опоры арки: под концами дуги — до дна пропасти
		for e in [sec0, sec1]:
			var d2 := (pos[mini(e + 1, pos.size() - 1)] - pos[maxi(e - 1, 0)])
			d2.y = 0.0
			var out2 := d2.normalized() if e == sec0 else -d2.normalized()
			var l2 := pos[e] - sides[e] * _wl[e]
			var r2 := pos[e] + sides[e] * _wr[e]
			l2.y = bot[e]
			r2.y = bot[e]
			_wall_pts(v, nrm, l2, r2, out2, BOTTOM, BOTTOM, 0.0)
	# низ настила / дуги
	for k in pos.size() - 1:
		if k >= k0 and k < k1:
			continue
		if bot[k] <= BOTTOM + 0.5 and bot[k + 1] <= BOTTOM + 0.5:
			continue
		var a := pos[k] - sides[k] * _wl[k]
		var b := pos[k] + sides[k] * _wr[k]
		var c := pos[k + 1] - sides[k + 1] * _wl[k + 1]
		var d := pos[k + 1] + sides[k + 1] * _wr[k + 1]
		a.y = bot[k]
		b.y = bot[k]
		c.y = bot[k + 1]
		d.y = bot[k + 1]
		_quad(v, nrm, a, b, d, c, Vector3.DOWN)
	_add_mesh(road_name + "_Cliff", v, nrm, _cliff_mat, true)
	var cbody := StaticBody3D.new()
	cbody.name = road_name + "_CliffCol"
	add_child(cbody)
	var cshape := ConcavePolygonShape3D.new()
	cshape.backface_collision = true
	cshape.set_faces(cf)
	var ccol := CollisionShape3D.new()
	ccol.shape = cshape
	cbody.add_child(ccol)
	# карниз: полоса утоптанного снега от края дороги до самой стены — без щели, куда можно провалиться
	# крутые снежные участки — ледяные ступени
	_stairs(road_name, pos, sides, hw, qkind, k0, k1)


## Расстояние от края дороги до стены ущелья на высоте y (или 99, если стены рядом нет)
func _wall_gap(p: Vector3, dir: Vector3, hw: float, y: float) -> float:
	for i in 40:
		var g := i * 0.25
		var q := p + dir * (hw + g)
		if L.wall_height(q.x, q.z) >= y:
			return g
	return 99.0


func _shoulder(road_name: String, pos: Array[Vector3], sides: Array[Vector3], hw: float, side: float) -> void:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var gaps: Array[float] = []
	for k in pos.size():
		gaps.append(_wall_gap(pos[k], sides[k] * side, hw, pos[k].y + 0.4))
	for k in pos.size() - 1:
		var g0 := gaps[k]
		var g1 := gaps[k + 1]
		if g0 > 7.0 or g1 > 7.0 or (g0 < 0.1 and g1 < 0.1):
			continue
		var n0: Vector3 = sides[k] * side
		var n1: Vector3 = sides[k + 1] * side
		var a := pos[k] + n0 * (hw - 0.05) + Vector3(0, -0.03, 0)
		var b := pos[k + 1] + n1 * (hw - 0.05) + Vector3(0, -0.03, 0)
		var c := pos[k + 1] + n1 * (hw + g1 + 1.0) + Vector3(0, 0.1, 0)
		var d := pos[k] + n0 * (hw + g0 + 1.0) + Vector3(0, 0.1, 0)
		_quad(v, nrm, a, b, c, d, Vector3.UP)
	if v.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = road_name + "_Shoulder"
	body.add_to_group("safe_ground")
	body.add_to_group("canyon_road")
	body.physics_material_override = _snow_pm
	add_child(body)
	var mi := _add_mesh("Top", v, nrm, _snow_mat, false, body)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(v)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


func _stairs(road_name: String, pos: Array[Vector3], sides: Array[Vector3], hw: float, qkind: Array[String], k0: int, k1: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var carry := 0.0
	for k in pos.size() - 1:
		if (k >= k0 and k < k1) or qkind[k] == "i":
			continue
		var a: Vector3 = pos[k]
		var b: Vector3 = pos[k + 1]
		var flat := Vector2(b.x - a.x, b.z - a.z).length()
		if flat < 0.01 or absf(b.y - a.y) / flat < 0.17:
			continue
		var f := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var tread := 0.55
		var s := carry
		while s < flat:
			var s1 := minf(s + tread, flat)
			var y0 := lerpf(a.y, b.y, s / flat)
			var y1 := lerpf(a.y, b.y, s1 / flat)
			var top := maxf(y0, y1)
			var h := absf(y1 - y0) + 0.3
			var c := a + f * ((s + s1) * 0.5)
			var bm := BoxMesh.new()
			bm.size = Vector3(hw * 2.0 - 0.1, h, s1 - s + 0.02)
			st.append_from(bm, 0, Transform3D(Basis.looking_at(f, Vector3.UP), Vector3(c.x, top - h * 0.5 + 0.02, c.z)))
			any = true
			s = s1
		carry = 0.0
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = road_name + "_Stairs"
	mi.mesh = st.commit()
	if not _stair_mat:
		_stair_mat = _ice_shader_mat(Color(0.3, 0.45, 0.6), Color(0.66, 0.78, 0.9), Color(0.92, 0.96, 1.0), 1.4, 0.6)
		_stair_mat.set_shader_parameter("crack_amount", 0.8)
		_stair_mat.set_shader_parameter("band_scale", 3.0)
	mi.material_override = _stair_mat
	mi.visibility_range_end = 260.0
	add_child(mi)


func _road_top(road_name: String, pos: Array[Vector3], sides: Array[Vector3], hw: float, k0: int, k1: int, kind: String) -> void:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var along := 0.0
	for k in range(1, k0 + 1):
		along += pos[k].distance_to(pos[k - 1])
	for k in range(k0, k1):
		var step := pos[k + 1].distance_to(pos[k])
		var a := pos[k] - sides[k] * _wl[k]
		var b := pos[k] + sides[k] * _wr[k]
		var c := pos[k + 1] - sides[k + 1] * _wl[k + 1]
		var d := pos[k + 1] + sides[k + 1] * _wr[k + 1]
		var ua := Vector2(-_wl[k], along)
		var ub := Vector2(_wr[k], along)
		var uc := Vector2(-_wl[k + 1], along + step)
		var ud := Vector2(_wr[k + 1], along + step)
		_tri_uv(v, nrm, uv, a, b, d, ua, ub, ud)
		_tri_uv(v, nrm, uv, a, d, c, ua, ud, uc)
		along += step
	var icy := kind == "i"
	var body := StaticBody3D.new()
	body.name = "%s_%s%d" % [road_name, "Ice" if icy else "Snow", k0]
	body.add_to_group("safe_ground")
	body.add_to_group("canyon_road")
	body.physics_material_override = _ice_pm if icy else _snow_pm
	add_child(body)
	var mat: Material = _ice_mat
	if not icy:
		mat = THEMES.surface(THEMES.road_theme(road_name))
		if mat == null:
			mat = _snow_mat
	var mi := _add_mesh("Top", v, nrm, mat, false, body, uv, hw)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(v)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)


## Треугольник лицом вверх, с координатами покрытия
func _tri_uv(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var fn := (c - a).cross(b - a)
	if fn.length_squared() < 1e-8:
		return
	if fn.y < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		fn = -fn
	fn = fn.normalized()
	v.append(a)
	v.append(b)
	v.append(c)
	uv.append(ua)
	uv.append(ub)
	uv.append(uc)
	for i in 3:
		n.append(fn)


## Наклоны для плавной высоты: без перехлёста (Фрич — Карлсон)
static func _mono_slopes(ctrl: Array[Vector3], dist: Array[float]) -> Array[float]:
	var n := ctrl.size()
	var dl: Array[float] = []
	for i in n - 1:
		dl.append((ctrl[i + 1].y - ctrl[i].y) / (dist[i + 1] - dist[i]))
	var m: Array[float] = []
	m.resize(n)
	m[0] = 0.0          # концы дорог — ровные (стыкуются с площадками и берегами вровень)
	m[n - 1] = 0.0
	for i in range(1, n - 1):
		m[i] = 0.0 if dl[i - 1] * dl[i] <= 0.0 else (dl[i - 1] + dl[i]) * 0.5
	for i in n - 1:
		if absf(dl[i]) < 1e-5:
			m[i] = 0.0
			m[i + 1] = 0.0
			continue
		var a := m[i] / dl[i]
		var b := m[i + 1] / dl[i]
		var h := a * a + b * b
		if h > 9.0:
			var tau := 3.0 / sqrt(h)
			m[i] = tau * a * dl[i]
			m[i + 1] = tau * b * dl[i]
	return m


static func _hermite(y0: float, y1: float, m0: float, m1: float, h: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * y0 + (t3 - 2.0 * t2 + t) * h * m0 + (-2.0 * t3 + 3.0 * t2) * y1 + (t3 - t2) * h * m1


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Отвесная стенка от верхнего края a-b до дна — полосами (на больших плоскостях
## туман и свет считаются неровно, поэтому делим её по высоте)
const WALL_STEPS := [0.0, 1.5, 4.0, 8.0, 13.0, 19.0, 26.0, 34.0, 44.0, 56.0, 70.0, 90.0]

## Как _wall, но низ у концов свой и бока могут расходиться книзу (flare — на метр глубины)
func _wall_pts(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, out: Vector3, ba: float, bb: float, flare: float) -> void:
	for i in WALL_STEPS.size() - 1:
		var ya0 := maxf(a.y - WALL_STEPS[i], ba)
		var ya1 := maxf(a.y - WALL_STEPS[i + 1], ba)
		var yb0 := maxf(b.y - WALL_STEPS[i], bb)
		var yb1 := maxf(b.y - WALL_STEPS[i + 1], bb)
		if ya0 <= ba and yb0 <= bb:
			break
		var oa0 := out * (minf((a.y - ya0) * flare, 8.0) + _relief(a.x, ya0, a.z, a.y - ya0))
		var oa1 := out * (minf((a.y - ya1) * flare, 8.0) + _relief(a.x, ya1, a.z, a.y - ya1))
		var ob0 := out * (minf((b.y - yb0) * flare, 8.0) + _relief(b.x, yb0, b.z, b.y - yb0))
		var ob1 := out * (minf((b.y - yb1) * flare, 8.0) + _relief(b.x, yb1, b.z, b.y - yb1))
		_quad(v, n, Vector3(a.x, ya0, a.z) + oa0, Vector3(b.x, yb0, b.z) + ob0, Vector3(b.x, yb1, b.z) + ob1, Vector3(a.x, ya1, a.z) + oa1, out)


## Рельеф обрыва: выступы и впадины (0…1.6 м наружу); у самого верха — ноль, чтобы край дороги был ровным
static func _relief(x: float, y: float, z: float, depth: float) -> float:
	var r := 0.75 + 0.5 * sin(0.37 * x + 0.23 * y + 0.11 * z) * sin(0.29 * z - 0.41 * y + 0.3 * x) \
		+ 0.3 * sin(1.1 * y + 0.7 * x - 0.4 * z)
	return maxf(r, 0.0) * smoothstep(0.3, 3.0, depth)


func _wall(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, out: Vector3, bottom: float = BOTTOM) -> void:
	_wall_pts(v, n, a, b, out, bottom, bottom, 0.0)
	return
	for i in WALL_STEPS.size() - 1:
		var ya0 := maxf(a.y - WALL_STEPS[i], bottom)
		var ya1 := maxf(a.y - WALL_STEPS[i + 1], bottom)
		var yb0 := maxf(b.y - WALL_STEPS[i], bottom)
		var yb1 := maxf(b.y - WALL_STEPS[i + 1], bottom)
		if ya0 <= bottom and yb0 <= bottom:
			break
		_quad(v, n, Vector3(a.x, ya0, a.z), Vector3(b.x, yb0, b.z), Vector3(b.x, yb1, b.z), Vector3(a.x, ya1, a.z), out)


## Четырёхугольник a-b-c-d (по кругу), лицом в сторону want
func _quad(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	_tri(v, n, a, b, c, want)
	_tri(v, n, a, c, d, want)


func _tri(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	var fn := (c - a).cross(b - a)
	if fn.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		fn = -fn
	if fn.length_squared() < 1e-8:
		return
	fn = fn.normalized()
	for p in [a, b, c]:
		v.append(p)
		n.append(fn)


func _add_mesh(mesh_name: String, v: PackedVector3Array, n: PackedVector3Array, mat: Material, far_cull: bool, parent: Node = null,
		uv: PackedVector2Array = PackedVector2Array(), hw: float = 0.0) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	if uv.size() == v.size():
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var uv2 := PackedVector2Array()
		uv2.resize(v.size())
		uv2.fill(Vector2(hw, 0.0))
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if far_cull:
		mi.visibility_range_end = 420.0
	(parent if parent else self).add_child(mi)
	return mi


# ---------------------------------------------------------------------------
#  Площадка (развилка, разворот): неровный многоугольник на ледяном столбе
# ---------------------------------------------------------------------------

func _platform(c: Vector3, r: float, pname: String = "") -> void:
	var sides_n := 22
	var ring: Array[Vector3] = []
	for i in sides_n:
		var a := TAU * i / sides_n
		var rr := r * (1.07 + 0.04 * sin(a * 3.0 + c.x * 0.1) + 0.03 * cos(a * 5.0 + c.z * 0.1))   # не меньше r
		ring.append(Vector3(c.x + cos(a) * rr, c.y + 0.03, c.z + sin(a) * rr))
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var top := c + Vector3(0, 0.03, 0)
	for i in sides_n:
		var q0: Vector3 = ring[i]
		var q1: Vector3 = ring[(i + 1) % sides_n]
		_tri_uv(v, nrm, uv, top, q0, q1, Vector2(top.x, top.z), Vector2(q0.x, q0.z), Vector2(q1.x, q1.z))
	var body := StaticBody3D.new()
	body.name = "Platform_%d_%d" % [int(c.x), int(c.z)]
	body.add_to_group("safe_ground")
	body.add_to_group("canyon_road")
	body.physics_material_override = _snow_pm
	add_child(body)
	var pmat: Material = THEMES.surface(THEMES.platform_theme(pname))
	_add_mesh("Top", v, nrm, pmat if pmat else _snow_mat, false, body, uv, 0.0)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(v)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	for i in sides_n:
		var a := ring[i]
		var b := ring[(i + 1) % sides_n]
		var out := ((a + b) * 0.5 - c)
		out.y = 0.0
		_wall(sv, sn, a, b, out.normalized())
		cliff_spots.append([(a + b) * 0.5, out.normalized(), BOTTOM, 0.0, pname])
	_add_mesh("Cliff_%d_%d" % [int(c.x), int(c.z)], sv, sn, _cliff_mat, true)
	# бока площадки твёрдые (сверху 24 м) — сорвавшийся не пролетает сквозь них
	var cf := PackedVector3Array()
	for i in sides_n:
		var a2: Vector3 = ring[i]
		var b2: Vector3 = ring[(i + 1) % sides_n]
		var dn := Vector3(0, -24.0, 0)
		cf.append_array(PackedVector3Array([a2, b2, b2 + dn, a2, b2 + dn, a2 + dn]))
	var cs := ConcavePolygonShape3D.new()
	cs.backface_collision = true
	cs.set_faces(cf)
	var cc := CollisionShape3D.new()
	cc.shape = cs
	body.add_child(cc)
	segments.append([c, c, r * 2.0, "s"])


# ---------------------------------------------------------------------------
#  Два моста между Q1 и Q2: ледяной (настоящий, скользкий) и снежный (ложный)
# ---------------------------------------------------------------------------

func _twin_bridges() -> void:
	var a: Vector3 = L.TWIN_REAL[0]
	var b: Vector3 = L.TWIN_REAL[1]
	_road("TwinIce", [[a.x, a.y, a.z, "i"], [b.x, b.y, b.z, ""]], 4.6, a.y - 1.8)
	fake_bridge = StaticBody3D.new()
	fake_bridge.set_script(SNOW_BRIDGE)
	fake_bridge.name = "FakeSnowBridge"
	fake_bridge.set("a", L.TWIN_FAKE[0])
	fake_bridge.set("b", L.TWIN_FAKE[1])
	fake_bridge.set("width", 4.6)
	add_child(fake_bridge)


# ---------------------------------------------------------------------------
#  Ловушки
# ---------------------------------------------------------------------------

func _traps() -> void:
	# тонкие мосты — рушатся под весом
	for br in L.BRIDGES:
		var a: Vector3 = br[0]
		var b: Vector3 = br[1]
		var d := b - a
		d.y = 0.0
		var tb := StaticBody3D.new()
		tb.set_script(BRIDGE)
		tb.name = "TrapBridge%d" % trap_bridges.size()
		tb.set("length", d.length() + 2.2)      # чуть заходит на концы дорог (и чуть выше их — без мерцания)
		tb.set("width", 4.0)
		tb.set("respawn_time", 9.0)
		tb.position = (a + b) * 0.5 + Vector3(0, -0.13, 0)
		tb.rotation.y = atan2(d.x, d.z)
		add_child(tb)
		trap_bridges.append(tb)
	# снежные ложные мосты
	for fb in L.FAKE_BRIDGES:
		var sb := StaticBody3D.new()
		sb.set_script(SNOW_BRIDGE)
		sb.name = "SnowBridge%d" % fake_bridges.size()
		sb.set("a", fb[0])
		sb.set("b", fb[1])
		sb.set("width", 6.0)
		add_child(sb)
		fake_bridges.append(sb)
	# яма-тупик: скользкий лёд над пропастью, медленно трещит (~30 с) и проваливается
	pit_floor = StaticBody3D.new()
	pit_floor.set_script(SLOW_FLOOR)
	pit_floor.name = "PitFloor"
	pit_floor.set("length", L.PIT_HALF * 2.0)
	pit_floor.set("width", L.PIT_HALF * 2.0)
	pit_floor.set("stress_rate", 0.034)
	pit_floor.set("recovery", 0.01)
	pit_floor.set("landing_stress", 0.04)
	pit_floor.set("carry_mult", 1.3)
	pit_floor.set("run_mult", 1.0)
	pit_floor.set("respawn_time", 12.0)
	pit_floor.position = L.PIT + Vector3(0, -0.18, 0)
	pit_floor.physics_material_override = _ice_pm
	add_child(pit_floor)
	# дороги, осыпающиеся за спиной
	for cr in L.CRUMBLES:
		var c := Node3D.new()
		c.set_script(CRUMBLE)
		c.name = "CrumbleRoad%d" % crumbles.size()
		c.set("a", cr[0])
		c.set("b", cr[1])
		c.set("width", 8.0)
		add_child(c)
		crumbles.append(c)
	# ущелья с падающими глыбами
	var k := 0
	for f in L.ICEFALLS:
		var fall := Node3D.new()
		fall.set_script(ICEFALL)
		fall.name = "IceFall%d" % k
		fall.set("a", f[0])
		fall.set("b", f[1])
		fall.set("top_y", L.PLATEAU + 4.0)
		fall.set("period", 1.1)
		fall.set("lateral", 2.6)
		add_child(fall)
		k += 1
	# ледяные маятники — расставлены по самой дороге (она может изгибаться)
	k = 0
	for pd in L.PENDULUMS:
		var cnt: int = pd[2]
		var spots := along_road(pd[0], pd[1], cnt)
		for i in cnt:
			var pen := Node3D.new()
			pen.set_script(PENDULUM)
			pen.name = "Pendulum%d" % k
			pen.set("road_dir", spots[i][1])
			pen.set("period", 3.3 + 0.35 * (i % 4))
			pen.set("phase", i * 1.9)
			pen.position = spots[i][0] + Vector3(0, 1.6, 0)
			add_child(pen)
			k += 1
	# коридоры-тиски: сплошные стены вдоль дороги, сходятся волной
	k = 0
	for v in L.VISES:
		var vw := Node3D.new()
		vw.set_script(VISE)
		vw.name = "Vise%d" % k
		vw.set("path", path_between(v[0], v[1]))
		add_child(vw)
		k += 1
	# гейзерные трещины
	k = 0
	for gc in L.CRACKS:
		var a: Vector3 = gc[0]
		var b: Vector3 = gc[1]
		var cnt: int = gc[2]
		for i in cnt:
			var cr := Node3D.new()
			cr.set_script(GEYSER_CRACK)
			cr.name = "GeyserCrack%d" % k
			cr.set("road_dir", b - a)
			cr.set("period", 5.2 + 0.9 * i)
			cr.set("phase", i * 0.41)
			cr.position = a.lerp(b, (i + 0.5) / cnt)
			add_child(cr)
			k += 1
	# пещера-«убежище»
	cave = Node3D.new()
	cave.set_script(CAVE)
	cave.name = "CaveTrap"
	add_child(cave)
	# подъёмник и три детали к нему
	lift = Node3D.new()
	lift.set_script(LIFT)
	lift.name = "CableLift"
	lift.set("dock_a", L.LIFT[0])
	lift.set("dock_b", L.LIFT[1])
	add_child(lift)
	for i in L.PARTS.size():
		var part := LIFT_ITEM.make(i, L.PARTS[i][0], L.PARTS[i][1] + Vector3(0, 0.6, 0))
		add_child(part)
		parts.append(part)


## Кусок осевой линии дороги от точки, ближайшей к a, до ближайшей к b
func path_between(a: Vector3, b: Vector3) -> Array:
	var best: Array = []
	var best_d := 1e9
	for key in road_paths:
		var path: Array = road_paths[key]
		var ia := 0
		var ib := 0
		var da := 1e9
		var db := 1e9
		for i in path.size():
			var q: Vector3 = path[i]
			var d1 := Vector2(q.x - a.x, q.z - a.z).length()
			var d2 := Vector2(q.x - b.x, q.z - b.z).length()
			if d1 < da:
				da = d1
				ia = i
			if d2 < db:
				db = d2
				ib = i
		if da + db < best_d:
			best_d = da + db
			best = []
			var step := 1 if ib >= ia else -1
			var i2 := ia
			while true:
				best.append(path[i2])
				if i2 == ib:
					break
				i2 += step
	return best


## Точки на осевой линии дороги между a и b (равными долями пути): [[точка, направление], ...]
func along_road(a: Vector3, b: Vector3, cnt: int) -> Array:
	var best_path: Array = []
	var best_i := 0
	var best_j := 0
	var best_d := 1e9
	for key in road_paths:
		var path: Array = road_paths[key]
		var ia := -1
		var ja := -1
		var da := 1e9
		var db := 1e9
		for i in path.size():
			var q: Vector3 = path[i]
			var d1 := Vector2(q.x - a.x, q.z - a.z).length()
			var d2 := Vector2(q.x - b.x, q.z - b.z).length()
			if d1 < da:
				da = d1
				ia = i
			if d2 < db:
				db = d2
				ja = i
		if da + db < best_d:
			best_d = da + db
			best_path = path
			best_i = ia
			best_j = ja
	var out := []
	if best_path.is_empty() or best_d > 12.0:
		for i in cnt:
			out.append([a.lerp(b, (i + 0.5) / cnt), b - a])
		return out
	var step := 1 if best_j >= best_i else -1
	var pts: Array[Vector3] = []
	var i2 := best_i
	while true:
		pts.append(best_path[i2])
		if i2 == best_j:
			break
		i2 += step
	var acc: Array[float] = [0.0]
	for i in range(1, pts.size()):
		acc.append(acc[-1] + pts[i].distance_to(pts[i - 1]))
	for n in cnt:
		var want: float = acc[-1] * (n + 0.5) / cnt
		var j := 1
		while j < acc.size() - 1 and acc[j] < want:
			j += 1
		var t := clampf((want - acc[j - 1]) / maxf(acc[j] - acc[j - 1], 0.001), 0.0, 1.0)
		out.append([pts[j - 1].lerp(pts[j], t), pts[j] - pts[j - 1]])
	return out


# ---------------------------------------------------------------------------
#  Ледяные стены: воронка, проход, горловина; у выхода из каньона
# ---------------------------------------------------------------------------

func _walls() -> void:
	var b = HUMMOCKS.new(30241)
	var fz := IceRiver.FIELD_N
	var cz := IceRiver.CANYON_S
	b.ground_y = 0.02
	for sgn in [-1.0, 1.0]:
		var a := Vector2(sgn * (IceRiver.FIELD_HALF + 1.5), fz)
		var e := Vector2(sgn * 15.5, IceRiver.PASS_S)
		for i in 9:
			b.palette = [0, 3, 5][i % 3]
			b.form = [4, 1, 4][i % 3]
			var p0: Vector2 = a.lerp(e, float(i) / 9.0)
			var p1: Vector2 = a.lerp(e, float(i + 1) / 9.0)
			b.wall(p0, p1, lerpf(10.0, 16.0, float(i) / 8.0), 3.0)
		b.palette = 3
		b.form = 4
		b.wall(Vector2(sgn * 15.5, IceRiver.PASS_S), Vector2(sgn * 15.5, cz), 20.0, 3.2)
		b.palette = 0
		b.wall(Vector2(sgn * 15.5, cz), Vector2(sgn * 15.5, 277.0), 22.0, 3.2)
		b.pinnacle(Vector2(sgn * 16.5, 276.0), 26.0)
		b.pinnacle(Vector2(sgn * 16.5, IceRiver.PASS_S), 24.0)
	# выход из каньона: по бокам дороги — глыбы на кромке, дальше — стена плато
	b.ground_y = IceRiver.river_y(IceRiver.CANYON_N - 1.0) + 0.02
	for sgn in [-1.0, 1.0]:
		b.palette = 3
		b.form = 4
		b.wall(Vector2(sgn * 7.5, L.Z_MIN - 0.8), Vector2(sgn * 22.0, L.Z_MIN - 0.8), 9.0, 2.6)
		b.pinnacle(Vector2(sgn * 8.5, L.Z_MIN - 1.0), 12.0)
	b.finish(self)


# ---------------------------------------------------------------------------
#  Развилки: ворота над каждой дорогой (одинаковые — по ним не угадаешь),
#  табличка с загадкой, брошенные вещи прошлой экспедиции
# ---------------------------------------------------------------------------

func _forks() -> void:
	themes = THEMES.new(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var sign_angles := {}
	for fork in FORKS:
		var p: Array = L.PLATFORMS[fork]
		var c := Vector3(p[0], p[1], p[2])
		var r: float = p[3]
		var theme: String = THEMES.FORK_THEME[fork]
		var used: Array[float] = []
		var gates := Node3D.new()
		gates.name = "Gates_%s" % fork
		add_child(gates)
		for road in FORKS[fork][0]:
			var pts: Array = L.ROADS[road]
			var e := Vector3(pts[0][0], pts[0][1], pts[0][2])
			var dir := Vector3(e.x - c.x, 0.0, e.z - c.z).normalized()
			used.append(atan2(dir.z, dir.x))
			var w: float = float(L.ROAD_WIDTH.get(road, 7.5))
			var g := c + dir * (r + 2.0)
			# ворота в стиле развилки — над обоими выходами одинаковые
			themes.gate(theme, g, dir, w, gates)
			var light := OmniLight3D.new()
			light.light_color = THEMES.GATE_LIGHT[theme]
			light.light_energy = 1.4
			light.omni_range = 9.0
			light.position = g + Vector3(0, 5.6, 0)
			light.distance_fade_enabled = true
			light.distance_fade_begin = 110.0
			light.distance_fade_length = 30.0
			gates.add_child(light)
		themes.flush("GateMeshes_%s" % fork, 300.0).reparent(gates)
		# табличка у центра
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.12
		cm.height = 2.6
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.3, 0.26, 0.22)
		metal.metallic = 0.6
		metal.roughness = 0.6
		cm.material = metal
		post.mesh = cm
		var free_ang := _free_angle(used, rng)
		var sp := c + Vector3(cos(free_ang), 0.0, sin(free_ang)) * (r * 0.55)
		post.position = sp + Vector3(0, 1.3, 0)
		add_child(post)
		var label := Label3D.new()
		label.text = FORKS[fork][1]
		label.font_size = 52
		label.outline_size = 14
		label.modulate = Color(1.0, 0.85, 0.5)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.position = sp + Vector3(0, 3.2, 0)
		add_child(label)
		var name_l := Label3D.new()
		name_l.text = "развилка %s · %s" % [fork, THEMES.TITLE[theme]]
		name_l.font_size = 30
		name_l.outline_size = 8
		name_l.modulate = Color(0.8, 0.9, 1.0, 0.85)
		name_l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		name_l.position = sp + Vector3(0, 2.1, 0)
		add_child(name_l)
		sign_angles[fork] = free_ang
	# площадки и дороги — в своём стиле
	themes.build(sign_angles)


## Куда на площадке ставится жаровня (то же место считают и украшения — чтобы не налезть)
func heater_angle(c: Vector3, r: float) -> float:
	var used: Array[float] = []
	for key in L.ROADS:
		for e in [L.ROADS[key][0], L.ROADS[key][-1]]:
			var d := Vector2(e[0] - c.x, e[2] - c.z)
			if d.length() < r + 5.0:
				used.append(atan2(d.y, d.x))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 7.0 + c.z)
	return _free_angle(used, rng) + 0.5


## Направление от центра площадки, где дальше всего до занятых (дорог, табличек)
func _free_angle(used: Array[float], rng: RandomNumberGenerator) -> float:
	var best := 0.0
	var best_d := -1.0
	for i in 36:
		var a := TAU * i / 36.0 + rng.randf_range(-0.05, 0.05)
		var md := TAU
		for u in used:
			md = minf(md, absf(wrapf(a - u, -PI, PI)))
		if md > best_d:
			best_d = md
			best = a
	return best


# ---------------------------------------------------------------------------
#  Туман в пропасти: дна почти не видно — кажется бездонной
# ---------------------------------------------------------------------------

func _mist() -> void:
	for layer in 2:
		var pm := PlaneMesh.new()
		pm.size = Vector2(L.X_MAX - L.X_MIN + 20.0, L.Z_MAX - L.Z_MIN + 10.0)
		pm.subdivide_width = 60
		pm.subdivide_depth = 60
		var m := ShaderMaterial.new()
		m.shader = MIST_SHADER
		m.set_shader_parameter("density", 0.85 if layer == 0 else 0.4)
		m.set_shader_parameter("mist_color", Color(0.13, 0.21, 0.32) if layer == 0 else Color(0.3, 0.42, 0.56))
		m.set_shader_parameter("drift", Vector2(0.012, 0.007) * (1.0 if layer == 0 else -1.3))
		pm.material = m
		var mi := MeshInstance3D.new()
		mi.name = "Mist%d" % layer
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((L.X_MIN + L.X_MAX) * 0.5, -44.0 + layer * 14.0, (L.Z_MAX + L.Z_MIN) * 0.5)
		add_child(mi)


# ---------------------------------------------------------------------------
#  Контрольные точки, жаровни, ветер, табличка у пруда
# ---------------------------------------------------------------------------

func _checkpoints() -> void:
	var list := [[Vector3(0.0, 0.0, 291.0), Vector3(26.0, 8.0, 12.0), "Ледяной каньон", "Контрольная точка у входа"]]
	for f in ["B", "C", "D", "E", "L1", "L2", "GT"]:
		var p: Array = L.PLATFORMS[f]
		list.append([Vector3(p[0], p[1], p[2]), Vector3(18.0, 8.0, 18.0), "Развилка %s" % f, "Контрольная точка — дальше снова выбор"])
	for cp in list:
		var a := Area3D.new()
		a.set_script(CHECKPOINT)
		a.name = "Checkpoint_%d" % int(cp[0].z)
		a.set("snap_to_terrain", false)
		a.set("size", cp[1])
		a.set("respawn_offset", Vector3(0.0, 0.6, 0.0))
		a.set("title", cp[2])
		a.set("subtitle", cp[3])
		a.position = cp[0]
		add_child(a)
	var warn := Label3D.new()
	warn.text = "Лёд в трещинах — не стой на месте"
	warn.font_size = 40
	warn.outline_size = 12
	warn.modulate = Color(0.75, 0.9, 1.0)
	warn.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	warn.position = Vector3(-14.0, -6.0, 92.0)
	var lift_sign := Label3D.new()
	lift_sign.text = "Подъёмник «Борея-2»"
	lift_sign.font_size = 46
	lift_sign.outline_size = 12
	lift_sign.modulate = Color(1.0, 0.85, 0.5)
	lift_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lift_sign.position = Vector3(L.PLATFORMS["L1"][0] - 5.0, L.PLATFORMS["L1"][1] + 4.5, L.PLATFORMS["L1"][2] + 4.0)
	add_child(lift_sign)
	var lake_sign := Label3D.new()
	lake_sign.text = "Глубокое озеро\nтри печати ворот — где-то на дне (E — взять под водой)\nвода ледяная: грейся у жаровни"
	lake_sign.font_size = 38
	lake_sign.outline_size = 12
	lake_sign.modulate = Color(0.7, 0.9, 1.0)
	lake_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lake_sign.position = Vector3(-8.0, 1.5, -632.0)
	add_child(lake_sign)
	add_child(warn)


func _heaters() -> void:
	var list: Array[Vector3] = [Vector3(9.0, IceRiver.river_y(IceRiver.CANYON_N - 6.0), IceRiver.CANYON_N - 6.0)]
	for f in ["A", "B", "C", "D", "E", "Q2", "L1", "L2", "F1", "F2", "F3", "F4", "F5", "GT"]:
		var p: Array = L.PLATFORMS[f]
		var c := Vector3(p[0], p[1], p[2])
		var r: float = p[3]
		var ang := heater_angle(c, r)
		list.append(c + Vector3(cos(ang), 0.0, sin(ang)) * (r * 0.62) + Vector3(0, 0.03, 0))
	for p in list:
		var h := Node3D.new()
		h.set_script(HEATER)
		h.name = "Heater_%d_%d" % [int(p.x), int(p.z)]
		h.position = p
		add_child(h)


## Сильные порывы ветра поперёк ущелий — сносит к краю. Пригнуться (Ctrl) — сносит слабее
func _winds() -> void:
	var i := 0
	for w in L.WINDS:
		var n := Node3D.new()
		n.set_script(WIND)
		n.name = "CanyonWind%d" % i
		n.set("z_max", w[0])
		n.set("z_min", w[1])
		n.set("strength", w[2])
		n.set("center_x", w[3])
		n.set("half_width", w[4])
		n.set("period", 8.5)
		n.set("gust_time", 4.2)
		n.set("hint", "Ctrl — присесть, чтобы не сдуло")
		n.position = Vector3(w[3], -4.0, (w[0] + w[1]) * 0.5)
		add_child(n)
		i += 1
