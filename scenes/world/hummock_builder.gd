extends RefCounted
## Строитель торосов — гряд из огромных ледяных глыб.
##
## Глыбы — настоящие 3D-модели скал (CC0, автор Quaternius, папка
## assets/models/ice_rocks), перекрашенные шейдером в лёд. Каждую модель
## растягиваем под нужный размер и поворачиваем как угодно, поэтому из 13 моделей
## получаются тысячи непохожих глыб.
##
## Гряды бывают разных ФОРМ (form) и разного ЛЬДА (palette):
##   форма 0 — «валуны»: круглые тяжёлые глыбы вплотную, сверху ещё одна-две;
##   форма 1 — «зубцы»: высокие острые скалы торчат вверх, у подножия обломки;
##   форма 2 — «плиты»: широкие плоские глыбы, сдвинутые и наползающие друг на друга;
##   форма 3 — «завал»: всё вперемешку, много мелких обломков;
##   форма 4 — «монолиты»: редкие огромные цельные глыбы.
## Виды льда (PALETTES): синий, бирюзовый, снежный белый, тёмный старый,
## мутный молочный, ледниковый зелёный.
##
## Глыбы рисуются через MultiMesh (тысячи глыб почти не тормозят),
## а столкновения у гряды простые — один прямоугольник на отрезок (через щели не пролезть).
## Ледяная горка — гладкий скользкий скат на гряду и спуск по другую сторону.
##
## Использование: задай palette / form, вызови wall(...), pinnacle(...), slide(...)
## — потом finish(узел).

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const CHUNK := 80.0
const FORMS := 5
const ROCK_DIR := "res://assets/models/ice_rocks/"
## Наборы моделей: круглые, острые/высокие, плоские/широкие, мелкие
const SET_ROUND := ["nature_rock_big_1", "nature_rock_big_2", "nature_rock_medium_3", "nature_rock_medium_4"]
const SET_TALL := ["space_rock_1", "space_rock_3", "space_rock_4", "space_rock_large_3", "space_rock_large_2"]
const SET_FLAT := ["space_rock_large_1", "nature_rock_big_2", "nature_rock_medium_2", "nature_rock_medium_1"]
const SET_SMALL := ["nature_rock_medium_1", "nature_rock_medium_2", "space_rock_2", "nature_rock_medium_4"]

## Виды льда: цвета толщи / середины / кромки и характер поверхности
const PALETTES := [
	{"name": "синий", "deep": Color(0.05, 0.22, 0.4), "mid": Color(0.24, 0.56, 0.76), "edge": Color(0.8, 0.94, 1.0),
		"snow": 1.0, "rough": 0.18, "milk": 0.0, "crack": 0.45, "band": 0.35, "glow": 0.06},
	{"name": "бирюзовый", "deep": Color(0.0, 0.3, 0.36), "mid": Color(0.16, 0.74, 0.78), "edge": Color(0.75, 1.0, 0.97),
		"snow": 0.6, "rough": 0.06, "milk": 0.0, "crack": 0.6, "band": 0.25, "glow": 0.12},
	{"name": "снежный", "deep": Color(0.42, 0.56, 0.7), "mid": Color(0.74, 0.84, 0.93), "edge": Color(0.95, 0.98, 1.0),
		"snow": 1.8, "rough": 0.45, "milk": 0.4, "crack": 0.2, "band": 0.2, "glow": 0.03},
	{"name": "тёмный старый", "deep": Color(0.02, 0.09, 0.18), "mid": Color(0.1, 0.28, 0.42), "edge": Color(0.5, 0.72, 0.85),
		"snow": 0.7, "rough": 0.1, "milk": 0.0, "crack": 0.5, "band": 0.55, "glow": 0.06},
	{"name": "молочный", "deep": Color(0.38, 0.5, 0.6), "mid": Color(0.6, 0.73, 0.82), "edge": Color(0.9, 0.95, 0.98),
		"snow": 0.9, "rough": 0.32, "milk": 1.0, "crack": 0.15, "band": 0.15, "glow": 0.05},
	{"name": "ледниковый", "deep": Color(0.01, 0.18, 0.19), "mid": Color(0.15, 0.52, 0.48), "edge": Color(0.7, 0.95, 0.88),
		"snow": 0.8, "rough": 0.14, "milk": 0.15, "crack": 0.5, "band": 0.45, "glow": 0.07},
]

var rng := RandomNumberGenerator.new()
var ground_y := 0.02             ## Высота льда, на котором стоят торосы
var palette := 0                 ## Каким льдом строить следующие гряды (номер в PALETTES)
var form := 0                    ## Какой формы следующие гряды (0..4, см. вверху)

static var _rocks := {}          ## имя модели -> [Mesh, AABB] (загружаются один раз)
var _mats: Array[ShaderMaterial] = []
var _polish_mat: ShaderMaterial
var _drift_mesh: SphereMesh
var _chunks := {}                ## Vector2i -> {"mm": {ключ: [[Transform3D], [Color]]}, "drifts": [...], "boxes": [[Transform3D, Vector3]]}
var _slides: Array = []          ## [Transform3D, Vector3 size]


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	for p in PALETTES:
		var m := ShaderMaterial.new()
		m.shader = ICE_SHADER
		m.set_shader_parameter("deep", p["deep"])
		m.set_shader_parameter("mid", p["mid"])
		m.set_shader_parameter("edge", p["edge"])
		m.set_shader_parameter("snow_amount", p["snow"])
		m.set_shader_parameter("base_rough", p["rough"])
		m.set_shader_parameter("milk", p["milk"])
		m.set_shader_parameter("crack_amount", p["crack"])
		m.set_shader_parameter("band_amount", p["band"])
		m.set_shader_parameter("glow", p["glow"])
		m.set_shader_parameter("band_scale", 3.0)
		_mats.append(m)
	_polish_mat = ShaderMaterial.new()
	_polish_mat.shader = ICE_SHADER
	_polish_mat.set_shader_parameter("polish", 1.0)
	_load_rocks()
	_drift_mesh = SphereMesh.new()
	_drift_mesh.radius = 0.5
	_drift_mesh.height = 1.0
	_drift_mesh.is_hemisphere = true
	_drift_mesh.radial_segments = 10
	_drift_mesh.rings = 4
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.93, 0.95, 1.0)
	snow.roughness = 0.9
	_drift_mesh.material = snow


## Загрузить модели скал (меш + габариты) — один раз на всю игру
static func _load_rocks() -> void:
	if not _rocks.is_empty():
		return
	var names := {}
	for list in [SET_ROUND, SET_TALL, SET_FLAT, SET_SMALL]:
		for n in list:
			names[n] = true
	for n in names:
		var sc := load(ROCK_DIR + n + ".glb") as PackedScene
		if sc == null:
			push_warning("Нет модели скалы: " + n)
			continue
		var inst := sc.instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var mi := found[0] as MeshInstance3D
			_rocks[n] = [mi.mesh, mi.mesh.get_aabb()]
		inst.free()


# ---------------------------------------------------------------------------
#  Учёт глыб по кускам 60×60 м
# ---------------------------------------------------------------------------
func _chunk(p: Vector3) -> Dictionary:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not _chunks.has(key):
		_chunks[key] = {"mm": {}, "drifts": [], "boxes": []}
	return _chunks[key]


## Поставить скалу name так, чтобы её габарит стал size (ширина, высота, толщина),
## низ — в точке base, поворот yaw, лёгкий наклон tilt.
func rock(name: String, base: Vector3, size: Vector3, yaw: float, tilt: Vector2 = Vector2.ZERO, pal: int = -1) -> void:
	if not _rocks.has(name):
		return
	if pal < 0:
		pal = palette
	var ab: AABB = _rocks[name][1]
	var s := Vector3(size.x / ab.size.x, size.y / ab.size.y, size.z / ab.size.z)
	var off := -Vector3(ab.position.x + ab.size.x * 0.5, ab.position.y + ab.size.y * 0.06, ab.position.z + ab.size.z * 0.5)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.FORWARD, tilt.y) * Basis.from_scale(s)
	var xf := Transform3D(basis, base) * Transform3D(Basis.IDENTITY, off)
	var c := _chunk(base)
	var key := "%d|%s" % [pal, name]
	if not c["mm"].has(key):
		c["mm"][key] = [[], []]
	c["mm"][key][0].append(xf)
	var tint := rng.randf_range(0.9, 1.08)
	c["mm"][key][1].append(Color(tint * rng.randf_range(0.93, 1.0), tint, tint * rng.randf_range(1.0, 1.06)))


func _pick(list: Array) -> String:
	return list[rng.randi() % list.size()]


func _box(pos: Vector3, basis: Basis, size: Vector3) -> void:
	_chunk(pos)["boxes"].append([Transform3D(basis, pos), size])


func _drift(pos: Vector3, basis: Basis) -> void:
	_chunk(pos)["drifts"].append(Transform3D(basis, pos))


# ---------------------------------------------------------------------------
#  Гряда
# ---------------------------------------------------------------------------

## Гряда торосов от a до b (точки на льду, x/z). height — высота гряды.
## skip — точки вдоль гряды (0..1), где глыб нет (проход или горка), skip_w — ширина пропуска, м.
## Вид гряды берётся из palette и form.
func wall(a: Vector2, b: Vector2, height: float, thick: float = 2.2, skip: Array = [], skip_w: float = 3.6, solid: bool = true) -> void:
	var seg_len := a.distance_to(b)
	if seg_len < 0.5:
		return
	var dir := (b - a) / seg_len
	var yaw := atan2(-dir.y, dir.x)
	var side := Vector3(-dir.y, 0.0, dir.x)
	var vis_thick := thick * 1.55          # глыбы толще коробки столкновений — стена объёмная
	var step: float = [3.0, 2.4, 4.2, 2.6, 5.5][form]
	var count := maxi(int(seg_len / step), 1)
	for i in count + 1:
		var t := (float(i) + rng.randf_range(-0.25, 0.25)) / count
		t = clampf(t, 0.0, 1.0)
		var blocked := false
		for s in skip:
			if absf((t - float(s)) * seg_len) < skip_w * 0.5 + 1.2:
				blocked = true
		if blocked:
			continue
		var p2 := a + (b - a) * t
		var base := Vector3(p2.x, ground_y - 0.15, p2.y) + side * rng.randf_range(-0.08, 0.08) * thick
		var flip := PI if rng.randf() < 0.5 else 0.0
		var yj := yaw + flip + rng.randf_range(-0.35, 0.35)
		# высокие стены (больше 5.5 м) — в два яруса: глыба на глыбе
		var tiers := 2 if height > 5.5 and form != 4 else 1
		for tier in tiers:
			var th := height * (0.62 if tiers == 2 else 1.0)
			var tb := base + Vector3.UP * (tier * height * 0.42) + side * rng.randf_range(-0.2, 0.2) * tier
			var yt := yj + tier * ((PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.2, 0.2))
			match form:
				1:   # зубцы
					rock(_pick(SET_TALL), tb, Vector3(rng.randf_range(2.6, 3.6), th * rng.randf_range(1.0, 1.35), vis_thick * rng.randf_range(0.85, 1.05)), yt,
						Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15)))
				2:   # плиты
					rock(_pick(SET_FLAT), tb, Vector3(rng.randf_range(5.0, 7.0), th * rng.randf_range(0.8, 1.05), vis_thick * rng.randf_range(1.0, 1.25)), yt,
						Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.2, 0.2)))
				3:   # завал
					var set: Array = [SET_ROUND, SET_TALL, SET_FLAT][rng.randi() % 3]
					rock(_pick(set), tb, Vector3(rng.randf_range(3.0, 4.5), th * rng.randf_range(0.85, 1.15), vis_thick * rng.randf_range(0.9, 1.15)), yt,
						Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)))
				4:   # монолиты
					rock(_pick(["space_rock_large_2", "space_rock_large_3", "nature_rock_big_1"]), tb,
						Vector3(rng.randf_range(6.0, 7.5), th * rng.randf_range(1.0, 1.2), vis_thick * rng.randf_range(1.1, 1.3)), yt)
				_:   # валуны
					rock(_pick(SET_ROUND), tb, Vector3(rng.randf_range(3.6, 4.8), th * rng.randf_range(0.9, 1.1), vis_thick * rng.randf_range(0.95, 1.15)), yt,
						Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1)))
		# сверху иногда лежит глыба поменьше
		if form != 4 and rng.randf() < [0.35, 0.15, 0.4, 0.3, 0.0][form]:
			var top := base + Vector3(0, height * rng.randf_range(0.55, 0.75), 0) + side * rng.randf_range(-0.3, 0.3)
			var sz := rng.randf_range(1.6, 2.6)
			rock(_pick(SET_ROUND if form != 2 else SET_FLAT), top, Vector3(sz * 1.3, sz * 0.8, sz), rng.randf() * TAU,
				Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)))
		# обломки у подножия с обеих сторон
		var rubble: float = [0.5, 0.7, 0.4, 1.0, 0.6][form]
		if rng.randf() < rubble:
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var rs := rng.randf_range(0.8, 1.6)
			rock(_pick(SET_SMALL), base + side * sgn * (vis_thick * 0.5 + rng.randf_range(-0.1, 0.35)) + Vector3(0, -0.15, 0),
				Vector3(rs * 1.3, rs * 0.6, rs * 0.8), rng.randf() * TAU, Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)))
	# снежные надувы вдоль гряды с обеих сторон
	var drift_k: float = [1.0, 0.8, 1.2, 1.0, 1.4][form]
	if PALETTES[palette]["snow"] > 1.2:
		drift_k *= 1.4
	for sgn in [-1.0, 1.0]:
		var mid := (a + b) * 0.5
		var db := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(seg_len * 0.95, rng.randf_range(0.6, 1.1) * minf(height, 3.0) * 0.35 * drift_k, rng.randf_range(2.4, 3.4)))
		_drift(Vector3(mid.x, ground_y - 0.05, mid.y) + side * sgn * (vis_thick * 0.5), db)
	if solid:
		var mid := (a + b) * 0.5
		# столкновение — по внешнему краю глыб (чтобы дрон не «входил» в стену),
		# и чуть длиннее отрезка — концы стены тоже твёрдые
		_box(Vector3(mid.x, ground_y + height * 0.48, mid.y), Basis(Vector3.UP, yaw), Vector3(seg_len + 1.6, height * 0.96, vis_thick + 0.35))


## Высокая скала (на стыках гряд и как украшение)
func pinnacle(p: Vector2, height: float) -> void:
	var base := Vector3(p.x, ground_y - 0.2, p.y)
	var w := rng.randf_range(3.0, 3.8)
	match form:
		0, 2:
			rock(_pick(SET_ROUND), base, Vector3(w * 1.1, height * 1.05, w), rng.randf() * TAU)
		4:
			rock("space_rock_large_3", base, Vector3(w * 1.3, height * 1.3, w * 1.2), rng.randf() * TAU)
		_:
			rock(_pick(["space_rock_1", "space_rock_3", "space_rock_4", "space_rock_large_3"]), base, Vector3(w, height * 1.3, w * 0.9), rng.randf() * TAU,
				Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)))
	_box(Vector3(p.x, ground_y + height * 0.48, p.y), Basis.IDENTITY, Vector3(w * 0.95, height * 0.96, w * 0.95))


## Ледяная горка через гряду: въезд с одной стороны, спуск — с другой.
## center — точка на гряде, dir — направление въезда (поперёк гряды), top — высота верха.
func slide(center: Vector2, dir: Vector2, top: float, thick: float, up_len: float = 7.5, down_len: float = 9.0, kicker: bool = false) -> void:
	dir = dir.normalized()
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var c3 := Vector3(center.x, ground_y, center.y)
	var yaw := atan2(-dir.x, -dir.y)
	var w := 3.4
	# въезд: от земли до верха гряды
	var up_start := c3 - d3 * (thick * 0.5 + up_len)
	var up_end := c3 - d3 * (thick * 0.5) + Vector3.UP * top
	_ramp(up_start, up_end, w)
	# мостик по верху гряды
	var bridge_b := Basis(Vector3.UP, yaw)
	_slides.append([Transform3D(bridge_b, c3 + Vector3.UP * (top - 0.2)), Vector3(w, 0.4, thick + 0.4)])
	# спуск
	var down_start := c3 + d3 * (thick * 0.5) + Vector3.UP * top
	var down_end := c3 + d3 * (thick * 0.5 + down_len)
	_ramp(down_start, down_end, w)
	if kicker:   # трамплин на конце спуска
		var k0 := down_end
		var k1 := down_end + d3 * 1.6 + Vector3.UP * 0.5
		_ramp(k0, k1, w)


func _ramp(from: Vector3, to: Vector3, w: float) -> void:
	var v := to - from
	var flat := Vector3(v.x, 0.0, v.z)
	var length := v.length()
	var yaw := atan2(-flat.x, -flat.z)
	var pitch := atan2(v.y, flat.length())
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var center := (from + to) * 0.5 - basis * Vector3(0, 0.2, 0)
	_slides.append([Transform3D(basis, center), Vector3(w, 0.4, length)])


## Собрать всё в узлы под parent
func finish(parent: Node3D) -> void:
	for key in _chunks:
		var c: Dictionary = _chunks[key]
		for mk in c["mm"]:
			var parts: PackedStringArray = (mk as String).split("|")
			var pal := int(parts[0])
			var mesh: Mesh = _rocks[parts[1]][0]
			var xs: Array = c["mm"][mk][0]
			var cols: Array = c["mm"][mk][1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
				mm.set_instance_color(i, cols[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _mats[pal]
			mmi.visibility_range_end = 200.0
			parent.add_child(mmi)
		var drifts: Array = c["drifts"]
		if not drifts.is_empty():
			var dm := MultiMesh.new()
			dm.transform_format = MultiMesh.TRANSFORM_3D
			dm.mesh = _drift_mesh
			dm.instance_count = drifts.size()
			for i in drifts.size():
				dm.set_instance_transform(i, drifts[i])
			var dmi := MultiMeshInstance3D.new()
			dmi.multimesh = dm
			dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dmi.visibility_range_end = 200.0
			parent.add_child(dmi)
		var boxes: Array = c["boxes"]
		if not boxes.is_empty():
			var body := StaticBody3D.new()
			body.add_to_group("safe_ground")
			var pm := PhysicsMaterial.new()
			pm.friction = 0.5
			body.physics_material_override = pm
			for b in boxes:
				var col := CollisionShape3D.new()
				var sh := BoxShape3D.new()
				sh.size = b[1]
				col.shape = sh
				col.transform = b[0]
				body.add_child(col)
			parent.add_child(body)
	# горки — гладкий скользкий лёд
	if not _slides.is_empty():
		var body := StaticBody3D.new()
		body.add_to_group("safe_ground")
		var slick := PhysicsMaterial.new()
		slick.friction = 0.02
		body.physics_material_override = slick
		for s in _slides:
			var col := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = s[1]
			col.shape = sh
			col.transform = s[0]
			body.add_child(col)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = s[1]
			bm.material = _polish_mat
			mi.mesh = bm
			mi.transform = s[0]
			parent.add_child(mi)
		parent.add_child(body)
