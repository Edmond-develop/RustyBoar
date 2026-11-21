extends RefCounted
## Оформление ледяного каньона: у каждой развилки — своя тема-история, своё покрытие дорог,
## свои ворота над выходами и свои предметы вдоль дорог.
##   A  — лагерь экспедиции (дощатый настил, палатки, флажки, гирлянды)
##   F1 — замёрзший водопад (застывшая рябь, ледяные каскады на стенах, сосульки)
##   B  — старая шахта (шпалы и рельсы, крепь над дорогой, вагонетки, руда)
##   F2 — радиомачта (рифлёная решётка, мачта с тарелкой, столбы с проводами)
##   C  — кристальный грот (порода со светящимися жилами, друзы кристаллов)
##   F3 — ледяные статуи (булыжник, ледяные дроны-статуи на столбах)
##   D  — кости левиафана (каменные плиты, череп, рёбра аркой над дорогой)
##   F4 — гейзерное поле (минеральная корка, дымящие трубы, горячий пруд)
##   E  — обломки корабля (стальные листы, корабль торчит из пропасти, обшивка в стенах)
##   F5 — кладбище дронов (ржавый лом, груды дронов, гигантская рука робота)
## Оба выхода с одной развилки оформлены одинаково — по виду не угадать, какой верный.
## Всё мелкое сливается в один меш на материал (мало отрисовок), всё строится по зерну.

const L := preload("res://scenes/world/canyon_layout.gd")
const CD := preload("res://scenes/world/crash_debris.gd")
const ROAD_SHADER := preload("res://shaders/canyon_road.gdshader")
const PROP := preload("res://scenes/world/model_prop.gd")
const SHIP := preload("res://assets/ships/Imperial.glb")

const FORK_THEME := {"A": "camp", "F1": "falls", "B": "mine", "F2": "radio", "C": "crystal",
	"F3": "statues", "D": "bones", "F4": "geyser", "E": "wreck", "F5": "drones"}
const EXTRA_PLATFORMS := {"H1": "camp", "H2": "camp", "Q1": "mine", "Q2": "mine", "H3": "crystal",
	"M": "falls", "L1": "wreck", "L2": "wreck"}
const ROAD_THEME := {
	"AW": "camp", "AW2": "camp", "AE": "camp", "AE2": "camp", "AE3": "camp",
	"F1C": "falls", "F1P": "falls", "F1P2": "falls",
	"BE": "mine", "BW": "mine", "Q2P": "mine", "P2C": "mine",
	"F2a": "radio", "F2b": "radio", "F2S": "radio", "F2a2": "radio",
	"CW": "crystal", "CE": "crystal", "CE2": "crystal",
	"F3a": "statues", "F3aR": "statues", "F3b": "statues", "F3b2": "statues",
	"DW": "bones", "DW2": "bones", "DE": "bones",
	"F4a": "geyser", "F4b": "geyser",
	"EE": "wreck", "EN": "wreck",
	"F5a": "drones", "F5a2": "drones", "F5b": "drones",
}
## Название места на табличке развилки
const TITLE := {"camp": "Лагерь экспедиции", "falls": "Замёрзший водопад", "mine": "Старая шахта",
	"radio": "Радиомачта", "crystal": "Кристальный грот", "statues": "Аллея статуй", "bones": "Кости левиафана",
	"geyser": "Гейзерное поле", "wreck": "Обломки «Кассиопеи»", "drones": "Кладбище дронов"}
## Цвет фонаря над воротами
const GATE_LIGHT := {"camp": Color(1.0, 0.7, 0.35), "falls": Color(0.55, 0.85, 1.0), "mine": Color(1.0, 0.62, 0.25),
	"radio": Color(1.0, 0.2, 0.15), "crystal": Color(0.7, 0.35, 1.0), "statues": Color(0.6, 0.85, 1.0),
	"bones": Color(0.95, 0.85, 0.6), "geyser": Color(1.0, 0.5, 0.2), "wreck": Color(1.0, 0.3, 0.15),
	"drones": Color(1.0, 0.15, 0.1)}

static var _surf := {}
var wall_found := true
var shelves: Array = []              ## [точка на стене, наружу, вдоль] — для проверок


static func road_theme(road: String) -> String:
	return ROAD_THEME.get(road, "")


static func platform_theme(pname: String) -> String:
	if FORK_THEME.has(pname):
		return FORK_THEME[pname]
	return EXTRA_PLATFORMS.get(pname, "")


## Материал покрытия дороги и площадки по теме (null — обычный снег)
static func surface(theme: String) -> Material:
	if theme == "":
		return null
	if _surf.has(theme):
		return _surf[theme]
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	var cfg: Array = {
		"camp": [1, Color(0.42, 0.27, 0.15), Color(0.62, 0.45, 0.28), Color(0, 0, 0), 0.22],
		"falls": [10, Color(0.7, 0.8, 0.9), Color(0.28, 0.52, 0.8), Color(0, 0, 0), 0.08],
		"mine": [2, Color(0.3, 0.2, 0.12), Color(0.45, 0.32, 0.2), Color(0, 0, 0), 0.25],
		"radio": [3, Color(0.42, 0.45, 0.48), Color(0.55, 0.57, 0.6), Color(0, 0, 0), 0.2],
		"crystal": [4, Color(0.13, 0.1, 0.2), Color(0.55, 0.35, 0.95), Color(0.55, 0.3, 1.0), 0.12],
		"statues": [9, Color(0.32, 0.36, 0.42), Color(0.5, 0.54, 0.6), Color(0, 0, 0), 0.12],
		"bones": [5, Color(0.36, 0.33, 0.3), Color(0.55, 0.5, 0.44), Color(0, 0, 0), 0.25],
		"geyser": [6, Color(0.48, 0.27, 0.12), Color(0.74, 0.64, 0.48), Color(1.0, 0.42, 0.1), 0.1],
		"wreck": [7, Color(0.36, 0.4, 0.46), Color(0.5, 0.54, 0.6), Color(0, 0, 0), 0.18],
		"drones": [8, Color(0.3, 0.28, 0.26), Color(0.45, 0.32, 0.2), Color(0, 0, 0), 0.2],
	}[theme]
	m.set_shader_parameter("style", cfg[0])
	m.set_shader_parameter("tint_a", cfg[1])
	m.set_shader_parameter("tint_b", cfg[2])
	m.set_shader_parameter("glow", cfg[3])
	m.set_shader_parameter("snow", cfg[4])
	_surf[theme] = m
	return m


# ---------------------------------------------------------------------------
#  Сборщик: всё мелкое — в один меш на материал
# ---------------------------------------------------------------------------

var cv: Node3D                      ## каньон
var rng := RandomNumberGenerator.new()
var _st := {}                       ## ключ материала → SurfaceTool
var _cables: SurfaceTool
var _boxes: Array = []              ## столкновения: [центр, размер, поворот]
var _mats := {}
var _blink: Array[StandardMaterial3D] = []
var _blink_lights: Array[OmniLight3D] = []
var _hw_cache := {}


func _init(canyon: Node3D) -> void:
	cv = canyon
	rng.seed = 51515


func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var spec: Array = {
		"wood": [Color(0.45, 0.3, 0.18), 0.85, 0.0, Color(0, 0, 0), 0.0],
		"wood_dark": [Color(0.26, 0.17, 0.1), 0.9, 0.0, Color(0, 0, 0), 0.0],
		"canvas_o": [Color(0.86, 0.4, 0.12), 0.9, 0.0, Color(0, 0, 0), 0.0],
		"canvas_b": [Color(0.16, 0.36, 0.62), 0.9, 0.0, Color(0, 0, 0), 0.0],
		"flag_r": [Color(0.82, 0.12, 0.1), 0.8, 0.0, Color(0, 0, 0), 0.0],
		"flag_y": [Color(0.95, 0.75, 0.1), 0.8, 0.0, Color(0, 0, 0), 0.0],
		"bulb": [Color(1.0, 0.85, 0.55), 0.3, 0.0, Color(1.0, 0.7, 0.35), 3.0],
		"rope": [Color(0.5, 0.42, 0.3), 0.95, 0.0, Color(0, 0, 0), 0.0],
		"steel": [Color(0.45, 0.47, 0.5), 0.4, 0.8, Color(0, 0, 0), 0.0],
		"rust": [Color(0.42, 0.22, 0.12), 0.85, 0.35, Color(0, 0, 0), 0.0],
		"rust_o": [Color(0.7, 0.42, 0.15), 0.75, 0.3, Color(0, 0, 0), 0.0],
		"dark": [Color(0.06, 0.06, 0.07), 0.9, 0.0, Color(0, 0, 0), 0.0],
		"ore": [Color(0.3, 0.28, 0.27), 0.95, 0.0, Color(0, 0, 0), 0.0],
		"gold": [Color(1.0, 0.8, 0.3), 0.3, 0.6, Color(1.0, 0.7, 0.2), 1.6],
		"led_g": [Color(0.3, 1.0, 0.4), 0.3, 0.0, Color(0.2, 1.0, 0.35), 3.0],
		"led_o": [Color(1.0, 0.6, 0.2), 0.3, 0.0, Color(1.0, 0.5, 0.1), 3.0],
		"yellow": [Color(0.92, 0.7, 0.08), 0.6, 0.2, Color(0, 0, 0), 0.0],
		"crys_v": [Color(0.32, 0.12, 0.62), 0.08, 0.2, Color(0.5, 0.2, 1.0), 0.7],
		"crys_c": [Color(0.12, 0.45, 0.65), 0.08, 0.2, Color(0.25, 0.8, 1.0), 0.6],
		"ice": [Color(0.42, 0.66, 0.85), 0.05, 0.25, Color(0.1, 0.25, 0.4), 0.35],
		"icefall": [Color(0.35, 0.62, 0.85), 0.04, 0.3, Color(0.12, 0.32, 0.5), 0.45],
		"stone": [Color(0.38, 0.4, 0.44), 0.95, 0.0, Color(0, 0, 0), 0.0],
		"bone": [Color(0.7, 0.64, 0.52), 0.8, 0.0, Color(0, 0, 0), 0.0],
		"crust_o": [Color(0.55, 0.3, 0.12), 0.95, 0.0, Color(0, 0, 0), 0.0],
		"crust_w": [Color(0.8, 0.75, 0.64), 0.9, 0.0, Color(0, 0, 0), 0.0],
		"hot_pool": [Color(0.15, 0.75, 0.72), 0.05, 0.0, Color(0.15, 0.85, 0.8), 1.2],
		"eye": [Color(0.2, 0.02, 0.02), 0.3, 0.0, Color(1.0, 0.1, 0.05), 2.2],
		"moss": [Color(0.3, 0.7, 0.2), 0.9, 0.0, Color(0.35, 1.0, 0.25), 0.9],
	}[key]
	m.albedo_color = spec[0]
	m.roughness = spec[1]
	m.metallic = spec[2]
	if spec[4] > 0.0:
		m.emission_enabled = true
		m.emission = spec[3]
		m.emission_energy_multiplier = spec[4]
	_mats[key] = m
	return m


## Мигающий красный огонь (мачта, ворота): материал + свет, гаснут вместе
func blink(pos: Vector3, parent: Node3D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.08, 0.05)
	m.emission_energy_multiplier = 4.0
	_blink.append(m)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = m
	mi.mesh = sm
	mi.position = pos
	parent.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.15, 0.1)
	l.omni_range = 10.0
	l.light_energy = 1.5
	l.position = pos
	l.distance_fade_enabled = true
	l.distance_fade_begin = 90.0
	l.distance_fade_length = 30.0
	parent.add_child(l)
	_blink_lights.append(l)


func tick(t: float) -> void:
	var on := fmod(t, 1.6) < 0.8
	for m in _blink:
		m.emission_energy_multiplier = 4.0 if on else 0.2
	for l in _blink_lights:
		l.light_energy = 1.5 if on else 0.0


func put(mesh: Mesh, xf: Transform3D, key: String) -> void:
	var st: SurfaceTool = _st.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	st.append_from(mesh, 0, xf)


func box(size: Vector3, pos: Vector3, b: Basis, key: String) -> void:
	var m := BoxMesh.new()
	m.size = size
	put(m, Transform3D(b, pos), key)


func cyl(rt: float, rb: float, h: float, pos: Vector3, b: Basis, key: String, seg: int = 10) -> void:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	m.cap_top = rt > 0.0
	put(m, Transform3D(b, pos), key)


func sph(r: float, pos: Vector3, b: Basis, key: String, seg: int = 12) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(seg / 2, 4)
	put(m, Transform3D(b, pos), key)


## Цилиндр от точки a до точки b
func beam(a: Vector3, b: Vector3, r: float, key: String, seg: int = 8, r_end: float = -1.0) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	cyl(r if r_end < 0.0 else r_end, r, d.length(), (a + b) * 0.5, basis_y(d), key, seg)


## Конус (остриё в сторону dir)
func spike(base: Vector3, dir: Vector3, ln: float, r: float, key: String, seg: int = 6) -> void:
	var d := dir.normalized()
	cyl(0.0, r, ln, base + d * ln * 0.5, basis_y(d), key, seg)


## Дуга из прямых кусков: центр, ось «вбок» (в плоскости дуги), радиус, углы (рад, 0 — вбок, PI/2 — вверх)
func arc(center: Vector3, side: Vector3, radius: float, a0: float, a1: float, r: float, key: String, n: int = 10, r_tip: float = -1.0) -> void:
	var prev := Vector3.ZERO
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		var p := center + side * cos(a) * radius + Vector3.UP * sin(a) * radius
		if i > 0:
			var k := absf(float(i) / n - 0.5) * 2.0
			var rr := lerpf(r, r_tip if r_tip > 0.0 else r, k)
			beam(prev, p, rr, key, 8)
		prev = p


## Столб (из пропасти и т.п.): как beam, но твёрдый — сквозь него не провалиться
func post(a: Vector3, b: Vector3, r: float, key: String, seg: int = 8, r_end: float = -1.0) -> void:
	beam(a, b, r, key, seg, r_end)
	var w := maxf(r, r_end) * 1.7
	solid((a + b) * 0.5, Vector3(w, absf(b.y - a.y), w))


func solid(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	_boxes.append([center, size, yaw])


static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


static func yaw_b(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw)


## Всё накопленное — в узел: меш на материал, столкновения одним телом
func flush(node_name: String, vis_end: float) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	cv.add_child(root)
	for key in _st:
		var st: SurfaceTool = _st[key]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = mesh
		mi.material_override = mat(key) if not key.begins_with("@") else _mats[key]
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_st.clear()
	if not _boxes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Props"
		root.add_child(body)
		for bx in _boxes:
			var shape := BoxShape3D.new()
			shape.size = bx[1]
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = bx[0]
			col.rotation.y = bx[2]
			body.add_child(col)
		_boxes.clear()
	return root


## Материал-шейдер под своим ключом (ключ начинается с @)
func shader_key(key: String, m: Material) -> String:
	_mats[key] = m
	return key


# ---------------------------------------------------------------------------
#  Где ставить: свободные места на площадке, стена ущелья, бок дороги
# ---------------------------------------------------------------------------

## Свободные направления на краю площадки (не на дорогах, не у таблички и жаровни)
func slots(c: Vector3, r: float, extra_used: Array, count: int) -> Array[float]:
	var used: Array[float] = []
	for a in extra_used:
		used.append(float(a))
	for key in L.ROADS:
		var pts: Array = L.ROADS[key]
		for e in [pts[0], pts[-1]]:
			var d := Vector2(e[0] - c.x, e[2] - c.z)
			if d.length() < r + 15.0:
				used.append(atan2(d.y, d.x))
	for lp in L.LIFT:
		var dl := Vector2(lp.x - c.x, lp.z - c.z)
		if dl.length() < r + 4.0:
			used.append(atan2(dl.y, dl.x))
	var out: Array[float] = []
	for n in count:
		var best := 0.0
		var best_d := -1.0
		for i in 48:
			var a := TAU * i / 48.0
			var md := TAU
			for u in used:
				md = minf(md, absf(wrapf(a - u, -PI, PI)))
			for u in out:
				md = minf(md, absf(wrapf(a - u, -PI, PI)) * 1.3)
			if md > best_d:
				best_d = md
				best = a
		if best_d < 0.42:
			break
		out.append(best)
	return out


static func ang_dir(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, sin(a))


## Точка на стене ущелья на высоте y, если идти от p в сторону dir
## (wall_found — нашлась ли стена; если нет, украшение не ставим, чтобы не висело в воздухе)
func wall_pt(p: Vector3, dir: Vector3, y: float) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	wall_found = true
	for i in 100:
		var q := p + d * (6.0 + i * 0.5)
		if _ground(q) >= y:
			# уточнить, где именно поверхность (между q − 0.5 и q)
			var lo := 6.0 + (i - 1) * 0.5
			var hi := 6.0 + i * 0.5
			if i == 0:
				lo = 0.0
				if _ground(p + d * lo) >= y:
					return Vector3(p.x, y, p.z)
			for j in 5:
				var mid := (lo + hi) * 0.5
				var qm := p + d * mid
				if _ground(qm) >= y:
					hi = mid
				else:
					lo = mid
			var qs := p + d * hi
			return Vector3(qs.x, y, qs.z)
	wall_found = false
	return Vector3(p.x, y, p.z) + d * 18.0


## Высота настоящего рельефа (стены ущелья, обрывы прудов) в точке
func _ground(q: Vector3) -> float:
	var t: Node = cv.get("_terrain")
	if t:
		return t.height_at(q.x, q.z)
	return L.wall_height(q.x, q.z)


## Рядом ли ловушка (там не ставим арок и столбов — мешали бы)
func near_trap(p: Vector3, dist: float) -> bool:
	var segs: Array = []
	for pd in L.PENDULUMS:
		segs.append([pd[0], pd[1]])
	for v in L.VISES:
		segs.append([v[0], v[1]])
	for gc in L.CRACKS:
		segs.append([gc[0], gc[1]])
	for x in L.CRUMBLES + L.ICEFALLS + L.BRIDGES + L.FAKE_BRIDGES:
		segs.append([x[0], x[1]])
	for sg in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (ap - ab * t).length() < dist:
			return true
	return false


func near_platform(p: Vector3, pad: float) -> bool:
	for key in L.PLATFORMS:
		var pl: Array = L.PLATFORMS[key]
		if Vector2(p.x - pl[0], p.z - pl[2]).length() < float(pl[3]) + pad:
			return true
	return false


## Точки вдоль дороги через каждые step м: [точка, вдоль, вбок, номер]
func road_spots(road: String, step: float, start: float = 8.0) -> Array:
	var path: Array = cv.road_paths.get(road, [])
	var out := []
	if path.size() < 2:
		return out
	var acc := 0.0
	var next := start
	var n := 0
	var fs: Dictionary = cv.form_sections.get(road, {})
	var skip0 := 1 << 30
	var skip1 := -1
	if not fs.is_empty() and String(fs["kind"]) in ["tunnel", "rope", "floes", "spiral"]:
		skip0 = int(fs["k0"]) - 2
		skip1 = int(fs["k1"]) + 2
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var seg := a.distance_to(b)
		if i >= skip0 and i <= skip1:
			acc += seg
			while next <= acc:
				next += step
			continue
		while acc + seg >= next:
			var t := (next - acc) / maxf(seg, 0.001)
			var p := a.lerp(b, t)
			var f := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			out.append([p, f, Vector3(-f.z, 0.0, f.x), n])
			n += 1
			next += step
		acc += seg
	return out


func road_hw(road: String) -> float:
	return float(L.ROAD_WIDTH.get(road, 7.5)) * 0.5


# ---------------------------------------------------------------------------
#  Сборка
# ---------------------------------------------------------------------------

## Площадки (развилки и промежуточные) и дороги. Ворота строит каньон через gate().
func build(sign_angles: Dictionary) -> void:
	var all := FORK_THEME.duplicate()
	all.merge(EXTRA_PLATFORMS)
	for pname in all:
		var theme: String = all[pname]
		var p: Array = L.PLATFORMS[pname]
		var c := Vector3(p[0], p[1], p[2])
		var r: float = p[3]
		var used: Array = []
		if sign_angles.has(pname):
			used.append(sign_angles[pname])
		used.append(cv.heater_angle(c, r))
		var sl := slots(c, r, used, 5)
		rng.seed = hash(pname) & 0xffffff
		var root_extra := Node3D.new()
		call("_plat_" + theme, c, r, sl, FORK_THEME.has(pname), pname, root_extra)
		var root := flush("Theme_%s" % pname, 250.0)
		root.add_child(root_extra)
	for road in ROAD_THEME:
		if not cv.road_paths.has(road):
			continue
		var theme: String = ROAD_THEME[road]
		rng.seed = hash(road) & 0xffffff
		var root_extra := Node3D.new()
		call("_road_" + theme, road, road_hw(road), root_extra)
		var root := flush("ThemeRoad_%s" % road, 230.0)
		root.add_child(root_extra)
	_cave_altar()
	flush("CaveAltar", 120.0)


## Ворота над выходом с развилки: g — середина дороги у края площадки, dir — наружу
func gate(theme: String, g: Vector3, dir: Vector3, w: float, parent: Node3D) -> void:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var yaw := atan2(dir.x, dir.z)
	var hw := w * 0.5
	call("_gate_" + theme, g, dir, side, hw, yaw, parent)


# ---------------------------------------------------------------------------
#  Лагерь экспедиции
# ---------------------------------------------------------------------------

func _tent(p: Vector3, yaw: float, key: String) -> void:
	var m := PrismMesh.new()
	m.size = Vector3(3.0, 2.2, 3.6)
	put(m, Transform3D(yaw_b(yaw), p + Vector3(0, 1.1, 0)), key)
	box(Vector3(0.9, 1.4, 0.05), p + yaw_b(yaw) * Vector3(0, 0.7, 1.82), yaw_b(yaw), "dark")
	beam(p + yaw_b(yaw) * Vector3(0, 0, 1.9), p + yaw_b(yaw) * Vector3(0, 2.5, 1.9), 0.04, "steel")
	# растяжки
	for sx in [-1.0, 1.0]:
		beam(p + yaw_b(yaw) * Vector3(sx * 0.6, 1.9, 1.7), p + yaw_b(yaw) * Vector3(sx * 2.3, 0.0, 2.4), 0.015, "rope", 4)
	solid(p + Vector3(0, 1.0, 0), Vector3(3.0, 2.0, 3.4), yaw)


func _crates(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw)
	box(Vector3(1.0, 1.0, 1.0), p + b * Vector3(0, 0.5, 0), b, "wood")
	box(Vector3(1.0, 1.0, 1.0), p + b * Vector3(1.05, 0.5, 0.1), yaw_b(yaw + 0.2), "wood")
	box(Vector3(0.8, 0.8, 0.8), p + b * Vector3(0.45, 1.4, 0.05), yaw_b(yaw - 0.3), "wood_dark")
	solid(p + b * Vector3(0.5, 0.7, 0), Vector3(2.2, 1.4, 1.2), yaw)


func _flagpole(p: Vector3, h: float, key: String) -> Vector3:
	beam(p, p + Vector3(0, h, 0), 0.07, "steel")
	box(Vector3(1.5, 0.95, 0.04), p + Vector3(0.78, h - 0.6, 0), Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), key)
	solid(p + Vector3(0, h * 0.5, 0), Vector3(0.25, h, 0.25))
	return p + Vector3(0, h - 0.1, 0)


## Гирлянда лампочек на провисшем проводе
func _string_lights(a: Vector3, b: Vector3, sag: float, n: int) -> void:
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		beam(prev, p, 0.015, "dark", 4)
		if i < n:
			sph(0.09, p + Vector3(0, -0.12, 0), Basis(), "bulb", 6)
		prev = p


func _plat_camp(c: Vector3, r: float, sl: Array[float], is_fork: bool, _pname: String, extra: Node3D) -> void:
	if sl.is_empty():
		return
	var rr := r - 2.4
	if is_fork:
		var keys := ["canvas_o", "canvas_b"]
		var tops: Array[Vector3] = []
		for i in mini(2, sl.size()):
			var tp := c + ang_dir(sl[i]) * rr
			_tent(tp, -sl[i] + PI * 0.5, keys[i])
			tops.append(tp + Vector3(0, 2.25, 0))
		if sl.size() > 2:
			_crates(c + ang_dir(sl[2]) * (rr + 0.4), -sl[2])
		if sl.size() > 3:
			var fp := c + ang_dir(sl[3]) * (r - 1.2)
			var top := _flagpole(fp, 7.0, "flag_r")
			for t in tops:
				_string_lights(top, t, 0.8, 10)
		# сани с ящиком
		if sl.size() > 4:
			var sp := c + ang_dir(sl[4]) * rr
			var b := yaw_b(-sl[4])
			box(Vector3(0.9, 0.12, 2.0), sp + Vector3(0, 0.3, 0), b, "wood")
			for sx in [-0.4, 0.4]:
				box(Vector3(0.06, 0.08, 2.3), sp + b * Vector3(sx, 0.06, 0.1), b, "steel")
			box(Vector3(0.7, 0.55, 0.9), sp + Vector3(0, 0.65, 0), b, "canvas_b")
			solid(sp + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 2.2), -sl[4])
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 1.2
		l.omni_range = 14.0
		l.position = c + Vector3(0, 4.0, 0)
		extra.add_child(l)
	else:
		_crates(c + ang_dir(sl[0]) * rr, -sl[0])
		if sl.size() > 1:
			_flagpole(c + ang_dir(sl[1]) * (r - 1.2), 5.0, "flag_y")


func _gate_camp(g: Vector3, _dir: Vector3, side: Vector3, hw: float, yaw: float, _parent: Node3D) -> void:
	var b := yaw_b(yaw)
	for sgn in [-1.0, 1.0]:
		post(g + side * sgn * (hw + 0.7) + Vector3(0, -12.0, 0), g + side * sgn * (hw + 0.7) + Vector3(0, 6.6, 0), 0.3, "wood_dark", 8)
	var bl := g + side * -(hw + 1.6) + Vector3(0, 6.2, 0)
	var br := g + side * (hw + 1.6) + Vector3(0, 6.2, 0)
	beam(bl, br, 0.26, "wood", 8)
	# флажки-вымпелы
	var n := int(hw * 2.0 / 0.9)
	for i in n:
		var p := bl.lerp(br, (i + 1.0) / (n + 1.0)) + Vector3(0, -0.45, 0)
		var m := PrismMesh.new()
		m.size = Vector3(0.5, 0.6, 0.03)
		put(m, Transform3D(b * Basis(Vector3.RIGHT, PI), p), ["flag_r", "flag_y", "canvas_b"][i % 3])
	# доска с надписью и фонарь
	box(Vector3(3.2, 0.7, 0.1), g + Vector3(0, 7.1, 0), b, "wood")
	beam(g + Vector3(0, 6.0, 0), g + Vector3(0, 5.3, 0), 0.02, "rope", 4)
	sph(0.22, g + Vector3(0, 5.1, 0), Basis(), "bulb", 8)


func _road_camp(road: String, hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 15.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 3.0) or near_trap(p, 6.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		# вешка с флажком на краю дороги
		var mp: Vector3 = p + sd * sgn * (hw - 0.25)
		beam(mp, mp + Vector3(0, 1.7, 0), 0.04, "steel", 5)
		box(Vector3(0.04, 0.28, 0.45), mp + Vector3(0, 1.5, 0), Basis(Vector3.UP, atan2(sd.x, sd.z)), "flag_r" if s[3] % 4 < 2 else "flag_y")
		# через одну — фонарь на свае из пропасти
		if s[3] % 3 == 1:
			var lp: Vector3 = p - sd * sgn * (hw + 1.3)
			post(lp + Vector3(0, -14.0, 0), lp + Vector3(0, 3.2, 0), 0.16, "wood_dark", 6)
			beam(lp + Vector3(0, 3.0, 0), lp + Vector3(0, 3.0, 0) + sd * sgn * 0.9, 0.05, "wood_dark", 4)
			sph(0.14, lp + Vector3(0, 2.75, 0) + sd * sgn * 0.85, Basis(), "bulb", 6)


# ---------------------------------------------------------------------------
#  Замёрзший водопад
# ---------------------------------------------------------------------------

## Застывший каскад на стене: несколько ледяных столбов от плато в пропасть
func _cascade(base: Vector3, out: Vector3, width: float) -> void:
	var sd := Vector3(-out.z, 0.0, out.x)
	var n := int(width / 1.6) + 2
	for i in n:
		var k := (float(i) / (n - 1) - 0.5) * width
		# верх и низ столба — в самой стене (стена книзу ближе, кверху дальше), без зазора
		var px := base + sd * k
		var top := wall_pt(px + out * 7.0, -out, L.PLATEAU - 3.0)
		top = (top - out * 0.8 + Vector3(0, 5.0, 0)) if wall_found else (px + Vector3(0, L.PLATEAU - base.y + 2.0, 0) - out * 0.5)
		var ly := base.y - rng.randf_range(30.0, 50.0)
		var low := wall_pt(base + sd * k * 1.15 + out * 7.0, -out, ly)
		low = (low - out * rng.randf_range(0.5, 1.5)) if wall_found else (base + sd * k * 1.15 + Vector3(0, ly - base.y, 0) - out * 1.0)
		var rad := rng.randf_range(0.9, 1.7) * (1.0 - absf(k) / width)
		beam(low, top, rad + 0.5, "icefall", 7, rad + 0.9)
	# наплыв внизу у дороги
	sph(width * 0.35, base - out * 1.2 + Vector3(0, -3.0, 0), Basis().scaled(Vector3(1.0, 0.6, 0.6)), "icefall", 10)


func _icicles(a: Vector3, b: Vector3, n: int, len_max: float) -> void:
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		spike(p, Vector3.DOWN, rng.randf_range(0.5, len_max), rng.randf_range(0.08, 0.2), "ice", 5)


func _plat_falls(c: Vector3, r: float, sl: Array[float], _is_fork: bool, pname: String, extra: Node3D) -> void:
	# каскады на стенах за площадкой
	for i in mini(3, sl.size()):
		var d := ang_dir(sl[i])
		var w := wall_pt(c, d, c.y)
		if wall_found:
			_cascade(w, -d, rng.randf_range(5.0, 9.0))
	# ледяные сталагмиты по краю
	for i in range(0, sl.size(), 2):
		var sp := c + ang_dir(sl[i] + 0.25) * (r - 1.8)
		for k in 4:
			var o := Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
			spike(sp + o, Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)), rng.randf_range(1.0, 2.8), rng.randf_range(0.2, 0.4), "ice", 6)
		solid(sp + Vector3(0, 0.9, 0), Vector3(1.8, 1.8, 1.8))
	if pname == "M":
		# у пещеры: светящийся ядовитый мох
		for i in 7:
			var mp := c + Vector3(rng.randf_range(-5.0, 5.0), 0.04, rng.randf_range(-5.0, 5.0))
			cyl(rng.randf_range(0.4, 0.9), rng.randf_range(0.6, 1.2), 0.06, mp, Basis(), "moss", 8)
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.85, 1.0)
	l.light_energy = 1.0
	l.omni_range = 16.0
	l.position = c + Vector3(0, 5.0, 0)
	extra.add_child(l)


func _gate_falls(g: Vector3, _dir: Vector3, side: Vector3, hw: float, yaw: float, _parent: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		var p: Vector3 = g + side * sgn * (hw + 0.9)
		post(p + Vector3(0, -12.0, 0), p + Vector3(0, 6.8, 0), 0.7, "icefall", 7, 0.5)
	var bl := g + side * -(hw + 1.5) + Vector3(0, 6.6, 0)
	var br := g + side * (hw + 1.5) + Vector3(0, 6.6, 0)
	box(Vector3(hw * 2.0 + 3.4, 0.9, 1.2), (bl + br) * 0.5, yaw_b(yaw), "icefall")
	_icicles(bl + Vector3(0, -0.45, 0), br + Vector3(0, -0.45, 0), 11, 2.2)


func _road_falls(road: String, hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 13.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 2.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		var w := wall_pt(p, sd * sgn, p.y + 7.0)
		var f: Vector3 = s[1]
		if wall_found:
			# ледяной карниз, вросший в стену, — сосульки висят под ним, а не в воздухе
			var o := -sd * sgn
			shelves.append([w, o, f])
			var shelf_b := Basis(Vector3.UP.cross(o).normalized(), Vector3.UP, o)
			sph(1.0, w - o * 0.3 + Vector3(0, 0.35, 0), Basis(shelf_b.x * 3.4, shelf_b.y * 0.85, shelf_b.z * 2.1), "ice", 12)
			_icicles(w + o * 0.75 - f * 2.4 + Vector3(0, 0.15, 0), w + o * 0.75 + f * 2.4 + Vector3(0, 0.15, 0), 6, 3.0)
		if s[3] % 4 == 2:
			var cw := wall_pt(p, sd * sgn, p.y)
			if wall_found:
				_cascade(cw, -sd * sgn, rng.randf_range(3.0, 5.0))


## Каменный алтарь в зале пещеры под шестерёнкой
func _cave_altar() -> void:
	var gp: Vector3 = L.PARTS[0][1]
	box(Vector3(1.4, 0.6, 1.4), gp + Vector3(0, 0.3, 0), Basis(), "stone")
	box(Vector3(1.0, 0.25, 1.0), gp + Vector3(0, 0.72, 0), yaw_b(0.6), "stone")
	solid(gp + Vector3(0, 0.42, 0), Vector3(1.4, 0.84, 1.4))
	for i in 6:
		var a := TAU * i / 6.0
		var bp := gp + Vector3(cos(a) * 2.2, 0.0, sin(a) * 2.2)
		spike(bp, Vector3(cos(a) * 0.3, 1.0, sin(a) * 0.3), rng.randf_range(0.8, 1.6), 0.18, "moss", 5)


# ---------------------------------------------------------------------------
#  Старая шахта
# ---------------------------------------------------------------------------

## Крепь: две стойки по краям дороги и поперечина
func _frame(p: Vector3, f: Vector3, sd: Vector3, hw: float, h: float, lantern: bool) -> void:
	var yaw := atan2(f.x, f.z)
	var b := yaw_b(yaw)
	for sgn in [-1.0, 1.0]:
		var pp: Vector3 = p + sd * sgn * (hw - 0.2)
		box(Vector3(0.36, h, 0.36), pp + Vector3(0, h * 0.5, 0), b, "wood_dark")
		solid(pp + Vector3(0, h * 0.5, 0), Vector3(0.36, h, 0.36), yaw)
		# откос
		beam(pp + Vector3(0, h - 1.4, 0), pp - sd * sgn * 1.2 + Vector3(0, h - 0.2, 0), 0.1, "wood_dark", 4)
	box(Vector3(0.45, 0.45, hw * 2.0 + 0.5), p + Vector3(0, h, 0), Basis(Vector3.UP, yaw + PI * 0.5), "wood")
	if lantern:
		beam(p + Vector3(0, h - 0.2, 0), p + Vector3(0, h - 0.8, 0), 0.02, "dark", 4)
		cyl(0.12, 0.16, 0.3, p + Vector3(0, h - 1.0, 0), Basis(), "rust", 6)
		sph(0.12, p + Vector3(0, h - 1.05, 0), Basis(), "bulb", 6)


func _cart(p: Vector3, yaw: float, tipped: bool) -> void:
	var b := yaw_b(yaw)
	if tipped:
		b = b * Basis(Vector3.FORWARD, 1.2)
	var up := b * Vector3.UP
	box(Vector3(1.1, 0.8, 1.7), p + up * 0.75, b, "rust")
	box(Vector3(0.9, 0.1, 1.5), p + up * 1.12, b, "dark")
	for sx in [-0.5, 0.5]:
		for sz in [-0.55, 0.55]:
			cyl(0.25, 0.25, 0.12, p + b * Vector3(sx * 1.15, 0.28, sz), b * Basis(Vector3.FORWARD, PI * 0.5), "steel", 10)
	solid(p + Vector3(0, 0.7, 0), Vector3(1.4, 1.4, 1.9), yaw)


func _ore_pile(p: Vector3) -> void:
	for i in 7:
		var o := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
		sph(rng.randf_range(0.25, 0.5), p + o + Vector3(0, 0.2, 0), Basis().scaled(Vector3(1.0, 0.7, 1.0)), "ore", 6)
	for i in 6:
		var o2 := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.2, 0.5), rng.randf_range(-0.9, 0.9))
		sph(rng.randf_range(0.08, 0.16), p + o2, Basis(), "gold", 5)
	solid(p + Vector3(0, 0.3, 0), Vector3(1.8, 0.6, 1.8))


func _plat_mine(c: Vector3, r: float, sl: Array[float], is_fork: bool, _pname: String, extra: Node3D) -> void:
	if sl.is_empty():
		return
	var rr := r - 2.3
	_cart(c + ang_dir(sl[0]) * rr, -sl[0], false)
	if sl.size() > 1:
		var tp := c + ang_dir(sl[1]) * rr
		_cart(tp, -sl[1], true)
		_ore_pile(tp + ang_dir(sl[1] + PI * 0.5) * 1.6)
	if is_fork and sl.size() > 2:
		# штабель рельсов
		var sp := c + ang_dir(sl[2]) * rr
		var b := yaw_b(-sl[2])
		for i in 4:
			box(Vector3(0.14, 0.14, 3.0), sp + b * Vector3(-0.3 + i * 0.2, 0.07 + (i % 2) * 0.14, 0), b, "steel")
		solid(sp + Vector3(0, 0.2, 0), Vector3(1.0, 0.4, 3.0), -sl[2])
	if is_fork and sl.size() > 3:
		# столб с фонарём
		var lp := c + ang_dir(sl[3]) * (r - 1.2)
		box(Vector3(0.3, 4.2, 0.3), lp + Vector3(0, 2.1, 0), Basis(), "wood_dark")
		beam(lp + Vector3(0, 4.0, 0), lp + Vector3(0, 4.0, 0) - ang_dir(sl[3]) * 1.3, 0.08, "wood_dark", 4)
		sph(0.18, lp + Vector3(0, 3.6, 0) - ang_dir(sl[3]) * 1.25, Basis(), "bulb", 8)
		solid(lp + Vector3(0, 2.1, 0), Vector3(0.3, 4.2, 0.3))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.3)
		l.light_energy = 1.4
		l.omni_range = 13.0
		l.position = lp + Vector3(0, 3.4, 0) - ang_dir(sl[3]) * 1.25
		extra.add_child(l)


func _gate_mine(g: Vector3, dir: Vector3, side: Vector3, hw: float, yaw: float, parent: Node3D) -> void:
	_frame(g, dir, side, hw, 6.0, true)
	box(Vector3(3.4, 0.9, 0.12), g + Vector3(0, 6.75, 0), yaw_b(yaw), "wood")
	var lb := Label3D.new()
	lb.text = "ШАХТА «ГЛУБОКАЯ»"
	lb.font_size = 40
	lb.outline_size = 10
	lb.modulate = Color(1.0, 0.85, 0.55)
	lb.position = g + Vector3(0, 6.75, 0) - dir * 0.08
	lb.rotation.y = yaw + PI
	lb.visibility_range_end = 120.0
	parent.add_child(lb)


func _road_mine(road: String, hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 12.0, 10.0):
		var p: Vector3 = s[0]
		if near_platform(p, 2.5) or near_trap(p, 7.0):
			continue
		_frame(p, s[1], s[2], hw, 5.2, s[3] % 2 == 0)


# ---------------------------------------------------------------------------
#  Радиомачта
# ---------------------------------------------------------------------------

func _mast(base: Vector3, h: float) -> Vector3:
	var legs: Array[Vector3] = []
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		legs.append(Vector3(cos(a), 0.0, sin(a)))
	var w0 := 1.3
	var w1 := 0.25
	var steps := int(h / 2.4)
	for i in 4:
		beam(base + legs[i] * w0, base + legs[i] * w1 + Vector3(0, h, 0), 0.07, "steel", 5)
	for k in steps:
		var y0 := h * k / steps
		var y1 := h * (k + 1) / steps
		var s0 := lerpf(w0, w1, y0 / h)
		var s1 := lerpf(w0, w1, y1 / h)
		for i in 4:
			var j := (i + 1) % 4
			beam(base + legs[i] * s0 + Vector3(0, y0, 0), base + legs[j] * s1 + Vector3(0, y1, 0), 0.035, "steel", 4)
			beam(base + legs[i] * s1 + Vector3(0, y1, 0), base + legs[j] * s1 + Vector3(0, y1, 0), 0.03, "steel", 4)
	solid(base + Vector3(0, 3.0, 0), Vector3(2.0, 6.0, 2.0))
	beam(base + Vector3(0, h, 0), base + Vector3(0, h + 3.0, 0), 0.05, "steel", 5)
	return base + Vector3(0, h + 3.1, 0)


func _plat_radio(c: Vector3, r: float, sl: Array[float], _is_fork: bool, _pname: String, extra: Node3D) -> void:
	if sl.is_empty():
		return
	var mp := c + ang_dir(sl[0]) * (r - 2.4)
	var top := _mast(mp, 18.0)
	blink(top, extra)
	blink(mp + Vector3(0, 10.0, 0), extra)
	# тарелка на середине мачты
	var dish := MeshInstance3D.new()
	dish.mesh = CD.dish(rng, 1.8, CD.metal(Color(0.8, 0.82, 0.85), 0.3, 0.2, 0.2))
	dish.position = mp + Vector3(0, 12.0, 0) - ang_dir(sl[0]) * 1.1
	dish.basis = basis_y(-ang_dir(sl[0]) + Vector3(0, 0.6, 0))
	dish.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra.add_child(dish)
	# растяжки
	var cab := shader_key("@cable", CD.metal(Color(0.15, 0.15, 0.16), 0.2, 0.3, 0.1))
	for i in 3:
		var a := sl[0] + PI + (i - 1) * 0.9
		var anchor := c + ang_dir(a) * (r - 0.6)
		put(CD.cable(mp + Vector3(0, 15.0, 0), anchor + Vector3(0, 0.1, 0), 0.4, 0.03, _mats[cab]), Transform3D(), cab)
		box(Vector3(0.3, 0.3, 0.3), anchor + Vector3(0, 0.15, 0), Basis(), "steel")
	# шкафы с аппаратурой
	for i in range(1, mini(3, sl.size())):
		var bp := c + ang_dir(sl[i]) * (r - 2.0)
		var b := yaw_b(-sl[i] + PI * 0.5)
		box(Vector3(1.0, 1.7, 0.6), bp + Vector3(0, 0.85, 0), b, "steel")
		for k in 4:
			box(Vector3(0.06, 0.06, 0.02), bp + b * Vector3(-0.3 + k * 0.2, 1.4, -0.31), b, "led_g" if k % 2 == 0 else "led_o")
		box(Vector3(0.8, 0.3, 0.02), bp + b * Vector3(0, 1.05, -0.31), b, "dark")
		solid(bp + Vector3(0, 0.85, 0), Vector3(1.0, 1.7, 0.6), -sl[i] + PI * 0.5)
	if sl.size() > 3:
		var rp := c + ang_dir(sl[3]) * (r - 2.0)
		cyl(0.7, 0.7, 0.9, rp + Vector3(0, 0.7, 0), Basis(Vector3.RIGHT, PI * 0.5) * yaw_b(-sl[3]), "wood", 12)
		solid(rp + Vector3(0, 0.7, 0), Vector3(1.4, 1.4, 1.0), -sl[3])


func _gate_radio(g: Vector3, _dir: Vector3, side: Vector3, hw: float, yaw: float, parent: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		var p: Vector3 = g + side * sgn * (hw + 0.6)
		post(p + Vector3(0, -12.0, 0), p + Vector3(0, 6.5, 0), 0.18, "steel", 8)
	beam(g + side * -(hw + 0.6) + Vector3(0, 6.3, 0), g + side * (hw + 0.6) + Vector3(0, 6.3, 0), 0.15, "steel", 8)
	box(Vector3(2.6, 0.8, 0.08), g + Vector3(0, 5.6, 0), yaw_b(yaw), "yellow")
	box(Vector3(2.4, 0.12, 0.09), g + Vector3(0, 5.6, 0), yaw_b(yaw) * Basis(Vector3.FORWARD, 0.3), "dark")
	blink(g + Vector3(0, 6.75, 0), parent)


func _road_radio(road: String, hw: float, _extra: Node3D) -> void:
	var cab := shader_key("@cable", CD.metal(Color(0.15, 0.15, 0.16), 0.2, 0.3, 0.1))
	var prev := Vector3.ZERO
	for s in road_spots(road, 18.0, 6.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		var pp: Vector3 = p + sd * (hw + 1.2)
		post(pp + Vector3(0, -14.0, 0), pp + Vector3(0, 5.0, 0), 0.13, "wood_dark", 6)
		box(Vector3(0.1, 0.1, 1.6), pp + Vector3(0, 4.6, 0), Basis(Vector3.UP, atan2(sd.x, sd.z)), "wood_dark")
		var top := pp + Vector3(0, 4.75, 0)
		cyl(0.05, 0.07, 0.2, top, Basis(), "crust_w", 6)
		if prev != Vector3.ZERO and prev.distance_to(top) < 30.0:
			put(CD.cable(prev, top, 0.9, 0.025, _mats[cab]), Transform3D(), cab)
		prev = top


# ---------------------------------------------------------------------------
#  Кристальный грот
# ---------------------------------------------------------------------------

func _crystal(base: Vector3, dir: Vector3, ln: float, rad: float, key: String) -> void:
	var d := dir.normalized()
	var body := ln * 0.75
	cyl(rad, rad * 1.1, body, base + d * body * 0.5, basis_y(d), key, 6)
	cyl(0.0, rad, ln - body, base + d * (body + (ln - body) * 0.5), basis_y(d), key, 6)


func _druse(base: Vector3, up: Vector3, n: int, size: float) -> void:
	for i in n:
		var d := (up + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.6, 0.6))).normalized()
		_crystal(base + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)) * size, d,
			rng.randf_range(1.2, 2.6) * size, rng.randf_range(0.18, 0.32) * size, "crys_v" if rng.randf() < 0.55 else "crys_c")


func _plat_crystal(c: Vector3, r: float, sl: Array[float], is_fork: bool, _pname: String, extra: Node3D) -> void:
	for i in mini(4 if is_fork else 2, sl.size()):
		var bp := c + ang_dir(sl[i]) * (r - 2.0)
		_druse(bp, Vector3.UP, 7, 1.0 if i % 2 == 0 else 0.75)
		solid(bp + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 1.8))
	# громадные кристаллы растут из стен вокруг
	for i in mini(3, sl.size()):
		var d := ang_dir(sl[i] + 0.2)
		var w := wall_pt(c, d, c.y + rng.randf_range(2.0, 8.0))
		if wall_found:
			_druse(w + d * 1.6, -d + Vector3(0, 0.5, 0), 4, 2.6)
	var l := OmniLight3D.new()
	l.light_color = Color(0.65, 0.35, 1.0)
	l.light_energy = 1.6
	l.omni_range = 16.0
	l.position = c + Vector3(0, 3.0, 0)
	extra.add_child(l)


func _gate_crystal(g: Vector3, _dir: Vector3, side: Vector3, hw: float, _yaw: float, _parent: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		var base: Vector3 = g + side * sgn * (hw + 1.4) + Vector3(0, -5.0, 0)
		var tip: Vector3 = g - side * sgn * 1.2 + Vector3(0, 9.5, 0)
		_crystal(base, tip - base, base.distance_to(tip), 0.75, "crys_v" if sgn < 0 else "crys_c")
		_druse(g + side * sgn * (hw - 0.2) + Vector3(0, -0.5, 0), Vector3(sgn * side.x, 1.0, sgn * side.z), 4, 0.8)


func _road_crystal(road: String, _hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 12.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 2.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		var w := wall_pt(p, sd * sgn, p.y + rng.randf_range(0.5, 9.0))
		var ds := rng.randf_range(1.2, 2.4)
		if wall_found:
			_druse(w + sd * sgn * ds * 0.6, -sd * sgn + Vector3(0, rng.randf_range(-0.2, 0.7), 0), 4, ds)


# ---------------------------------------------------------------------------
#  Аллея статуй
# ---------------------------------------------------------------------------

## Ледяная статуя дрона (s — масштаб, yaw — куда смотрит, pose — поза)
func _statue(p: Vector3, yaw: float, s: float, pose: int) -> void:
	var b := yaw_b(yaw)
	var k := "ice"
	for sx in [-0.22, 0.22]:
		cyl(0.16 * s, 0.2 * s, 1.0 * s, p + b * Vector3(sx * s, 0.5 * s, 0), b, k, 6)
	var torso := CapsuleMesh.new()
	torso.radius = 0.42 * s
	torso.height = 1.5 * s
	torso.radial_segments = 8
	torso.rings = 3
	put(torso, Transform3D(b, p + Vector3(0, 1.65 * s, 0)), k)
	sph(0.36 * s, p + Vector3(0, 2.65 * s, 0), b, k, 10)
	box(Vector3(0.5, 0.14, 0.12) * s, p + b * Vector3(0, 2.68 * s, 0.3 * s), b, "dark")
	var sh_l := p + b * Vector3(-0.5 * s, 2.1 * s, 0)
	var sh_r := p + b * Vector3(0.5 * s, 2.1 * s, 0)
	match pose:
		0:   # рука вверх — указывает вдаль
			beam(sh_r, sh_r + b * Vector3(0.3, 1.1, 0.5) * s, 0.12 * s, k, 6)
			beam(sh_l, sh_l + b * Vector3(-0.2, -0.9, 0.1) * s, 0.12 * s, k, 6)
		1:   # руки к груди
			beam(sh_r, sh_r + b * Vector3(-0.3, -0.5, 0.5) * s, 0.12 * s, k, 6)
			beam(sh_l, sh_l + b * Vector3(0.3, -0.5, 0.5) * s, 0.12 * s, k, 6)
		_:   # обе руки вверх
			beam(sh_r, sh_r + b * Vector3(0.2, 1.1, 0.0) * s, 0.12 * s, k, 6)
			beam(sh_l, sh_l + b * Vector3(-0.2, 1.1, 0.0) * s, 0.12 * s, k, 6)


func _plat_statues(c: Vector3, r: float, sl: Array[float], _is_fork: bool, _pname: String, extra: Node3D) -> void:
	for i in mini(4, sl.size()):
		var sp := c + ang_dir(sl[i]) * (r - 2.0)
		box(Vector3(1.5, 0.8, 1.5), sp + Vector3(0, 0.4, 0), yaw_b(-sl[i]), "stone")
		_statue(sp + Vector3(0, 0.8, 0), -sl[i] - PI * 0.5, 1.25, i % 3)
		solid(sp + Vector3(0, 1.8, 0), Vector3(1.5, 3.6, 1.5), -sl[i])
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.85, 1.0)
	l.light_energy = 1.0
	l.omni_range = 14.0
	l.position = c + Vector3(0, 5.0, 0)
	extra.add_child(l)


func _gate_statues(g: Vector3, _dir: Vector3, side: Vector3, hw: float, yaw: float, _parent: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		var p: Vector3 = g + side * sgn * (hw + 1.7)
		cyl(1.0, 1.3, 14.0, p + Vector3(0, -7.0, 0), Basis(), "stone", 8)
		solid(p + Vector3(0, -7.0, 0), Vector3(1.9, 14.0, 1.9))
		_statue(p, yaw + (PI * 0.5 if sgn < 0 else -PI * 0.5), 2.1, 2)
	box(Vector3(0.6, 0.6, hw * 2.0 + 4.6), g + Vector3(0, 8.3, 0), Basis(Vector3.UP, yaw + PI * 0.5), "ice")


func _road_statues(road: String, hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 16.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 2.0) or near_trap(p, 5.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		var pp: Vector3 = p + sd * sgn * (hw + 1.6)
		cyl(0.8, 1.0, 26.0, pp + Vector3(0, -12.8, 0), Basis(), "stone", 7)
		solid(pp + Vector3(0, -12.8, 0), Vector3(1.5, 26.0, 1.5))
		_statue(pp + Vector3(0, 0.2, 0), atan2(-sd.x * sgn, -sd.z * sgn), 1.1, rng.randi_range(0, 2))


# ---------------------------------------------------------------------------
#  Кости левиафана
# ---------------------------------------------------------------------------

func _skull(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw)
	sph(2.2, p + Vector3(0, 1.4, 0), b.scaled(Vector3(1.0, 0.8, 1.15)), "bone", 14)
	box(Vector3(2.4, 1.2, 2.6), p + b * Vector3(0, 0.7, 2.4), b, "bone")
	for sx in [-0.8, 0.8]:
		sph(0.6, p + b * Vector3(sx, 2.0, 1.85), Basis(), "dark", 8)
	box(Vector3(2.2, 0.4, 2.4), p + b * Vector3(0, 0.1, 2.6), b * Basis(Vector3.RIGHT, 0.35), "bone")
	for i in 8:
		var tx := -0.95 + i * 0.27
		spike(p + b * Vector3(tx, 0.15, 3.6), Vector3.DOWN, 0.6, 0.1, "bone", 5)
	solid(p + Vector3(0, 1.4, 0), Vector3(4.4, 2.8, 4.4), yaw)


## Позвоночник из пропасти: позвонки по дуге
func _spine(base: Vector3, to: Vector3, n: int) -> void:
	for i in n:
		var t := float(i) / (n - 1)
		var p := base.lerp(to, t) + Vector3(0, sin(t * PI) * 3.0, 0)
		cyl(0.9 - t * 0.3, 0.9 - t * 0.3, 0.6, p, Basis(), "bone", 10)
		box(Vector3(0.25, 1.2, 0.25), p + Vector3(0, 0.6, 0), Basis(), "bone")


func _rib_arch(center: Vector3, side: Vector3, radius: float) -> void:
	arc(center, side, radius, 0.35, PI - 0.35, 0.55, "bone", 12, 0.3)
	# концы рёбер уходят вниз в пропасть
	for sgn in [-1.0, 1.0]:
		var foot: Vector3 = center + side * sgn * cos(0.35) * radius + Vector3.UP * sin(0.35) * radius
		beam(foot, foot + side * sgn * 1.5 + Vector3(0, -9.0, 0), 0.5, "bone", 8, 0.25)


func _plat_bones(c: Vector3, r: float, sl: Array[float], _is_fork: bool, _pname: String, _extra: Node3D) -> void:
	if sl.is_empty():
		return
	_skull(c + ang_dir(sl[0]) * (r - 3.0) + Vector3(0, -0.5, 0), -sl[0] - PI * 0.5)
	if sl.size() > 1:
		var d := ang_dir(sl[1])
		_spine(c + d * (r + 3.0) + Vector3(0, -22.0, 0), c + d * (r + 1.5) + Vector3(0, 3.0, 0), 14)
	# три ребра аркой над площадкой
	var ax := ang_dir(sl[0] + PI * 0.5)
	var sd := Vector3(-ax.z, 0.0, ax.x)
	for k in [-5.0, 0.0, 5.0]:
		_rib_arch(c + ax * k + Vector3(0, -6.0, 0), sd, r + 6.0)


func _gate_bones(g: Vector3, dir: Vector3, side: Vector3, hw: float, _yaw: float, _parent: Node3D) -> void:
	_rib_arch(g + dir * 0.5 + Vector3(0, -4.0, 0), side, hw + 7.5)


func _road_bones(road: String, hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 9.0, 6.0):
		var p: Vector3 = s[0]
		if near_platform(p, 1.0) or near_trap(p, 6.0):
			continue
		if s[3] < 6:
			_rib_arch(p + Vector3(0, -4.0, 0), s[2], hw + 7.5 - s[3] * 0.4)
		elif s[3] % 3 == 0:
			var sgn := 1.0 if s[3] % 2 == 0 else -1.0
			var sd: Vector3 = s[2]
			var pp: Vector3 = p + sd * sgn * (hw + 1.8)
			_spine(pp + Vector3(0, -16.0, 0) + sd * sgn * 2.0, pp + Vector3(0, 1.0, 0), 9)


# ---------------------------------------------------------------------------
#  Гейзерное поле
# ---------------------------------------------------------------------------

func _steam(p: Vector3, parent: Node3D, strong: bool) -> void:
	var st := FX.particles(Color(0.95, 0.96, 1.0, 0.32 if strong else 0.22), 24 if strong else 14, 3.0, 0.9, 1.0, 2.4,
		Vector3(0, 0.6, 0), 12.0, false)
	st.position = p
	st.emitting = true
	st.visibility_range_end = 160.0
	parent.add_child(st)


func _chimney(p: Vector3, h: float, parent: Node3D, steam: bool) -> void:
	cyl(0.45, 1.25, h, p + Vector3(0, h * 0.5, 0), Basis(), "crust_o", 9)
	solid(p + Vector3(0, h * 0.5, 0), Vector3(1.8, h, 1.8))
	for k in 3:
		var y := h * (0.3 + k * 0.25)
		cyl(lerpf(1.25, 0.45, y / h) + 0.12, lerpf(1.25, 0.45, y / h) + 0.18, 0.25, p + Vector3(0, y, 0), Basis(), "crust_w", 9)
	if steam:
		_steam(p + Vector3(0, h + 0.2, 0), parent, true)


func _plat_geyser(c: Vector3, r: float, sl: Array[float], _is_fork: bool, _pname: String, extra: Node3D) -> void:
	for i in mini(3, sl.size()):
		var vp := c + ang_dir(sl[i]) * (r - 2.2)
		if i == 1:
			# горячий пруд — можно наступить
			cyl(1.6, 1.6, 0.05, vp + Vector3(0, 0.05, 0), Basis(), "hot_pool", 18)
			cyl(1.9, 2.0, 0.12, vp + Vector3(0, 0.03, 0), Basis(), "crust_w", 18)
			_steam(vp + Vector3(0, 0.2, 0), extra, false)
		else:
			sph(1.0, vp + Vector3(0, 0.1, 0), Basis().scaled(Vector3(1.0, 0.5, 1.0)), "crust_o", 10)
			cyl(0.35, 0.35, 0.05, vp + Vector3(0, 0.6, 0), Basis(), "dark", 10)
			_steam(vp + Vector3(0, 0.6, 0), extra, true)
			solid(vp + Vector3(0, 0.3, 0), Vector3(1.8, 0.6, 1.8))
	# минеральные террасы стекают в пропасть
	if sl.size() > 3:
		var d := ang_dir(sl[3])
		for k in 5:
			var tp := c + d * (r + 1.0 + k * 1.3) + Vector3(0, -0.4 - k * 1.6, 0)
			cyl(2.6 - k * 0.25, 2.4 - k * 0.25, 0.6, tp, Basis(), "crust_w" if k % 2 == 0 else "crust_o", 14)
			cyl(2.2 - k * 0.25, 2.2 - k * 0.25, 0.05, tp + Vector3(0, 0.31, 0), Basis(), "hot_pool", 14)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.25)
	l.light_energy = 1.4
	l.omni_range = 15.0
	l.position = c + Vector3(0, 3.0, 0)
	extra.add_child(l)


func _gate_geyser(g: Vector3, _dir: Vector3, side: Vector3, hw: float, _yaw: float, parent: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		_chimney(g + side * sgn * (hw + 1.4) + Vector3(0, -9.0, 0), 15.0, parent, true)


func _road_geyser(road: String, hw: float, extra: Node3D) -> void:
	for s in road_spots(road, 20.0, 10.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 2.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		_chimney(p + sd * sgn * (hw + 1.4) + Vector3(0, -12.0, 0), rng.randf_range(12.0, 16.0), extra, s[3] % 2 == 0)


# ---------------------------------------------------------------------------
#  Обломки корабля
# ---------------------------------------------------------------------------

func _plat_wreck(c: Vector3, r: float, sl: Array[float], is_fork: bool, pname: String, extra: Node3D) -> void:
	if sl.is_empty():
		return
	var hull := CD.metal(Color(0.55, 0.58, 0.63), 0.4, 0.5, 0.35, 0.0, 0.0, 0.0, 1.0)
	if is_fork:
		# корабль торчит из пропасти носом вверх — вдоль края площадки, подальше от дорог
		var road_ang := slots(c, r, [], 1)
		var a0: float = road_ang[0] if not road_ang.is_empty() else sl[0]
		var d := ang_dir(a0)
		var t := Vector3(-d.z, 0.0, d.x)
		var ship := StaticBody3D.new()
		ship.set_script(PROP)
		ship.set("model", SHIP)
		ship.set("target_length", 28.0)
		ship.set("snap_to_ground", false)
		ship.set("snow_drifts", false)
		ship.set("frost", 0.55)
		ship.position = c + d * (r + 7.0) + Vector3(0, -4.0, 0)
		ship.basis = Basis.looking_at(t, Vector3.UP) * Basis(Vector3.RIGHT, 0.95) * Basis(Vector3.FORWARD, 0.3)
		extra.add_child(ship)
		# двигатель с ещё тёплым соплом
		if sl.size() > 1:
			var hot := StandardMaterial3D.new()
			hot.albedo_color = Color(0.3, 0.1, 0.05)
			hot.emission_enabled = true
			hot.emission = Color(1.0, 0.4, 0.1)
			hot.emission_energy_multiplier = 2.0
			var eng: Array = CD.engine(rng, hull, hot)
			var ep := c + ang_dir(sl[1]) * (r - 2.6)
			for m in eng:
				var mi := MeshInstance3D.new()
				mi.mesh = m
				mi.position = ep + Vector3(0, 1.0, 0)
				mi.basis = Basis(Vector3.UP, -sl[1]) * Basis(Vector3.RIGHT, 0.15)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				extra.add_child(mi)
			solid(ep + Vector3(0, 1.0, 0), Vector3(2.4, 2.0, 3.2), -sl[1])
	# рваные листы обшивки, воткнутые по краю
	var key := shader_key("@hull_%s" % pname, hull)
	for i in range(1 if is_fork else 0, mini(4, sl.size())):
		var pp := c + ang_dir(sl[i]) * (r - 1.6)
		put(CD.torn_plate(rng, 2.4, 2.0, 0.5, hull), Transform3D(Basis(Vector3.UP, -sl[i]) * Basis(Vector3.RIGHT, 0.35), pp + Vector3(0, 0.7, 0)), key)
		solid(pp + Vector3(0, 0.9, 0), Vector3(2.2, 1.8, 0.6), -sl[i] + PI * 0.5)
	if pname == "L1":
		var cont: Array = CD.container(Vector3(2.4, 2.4, 5.0), CD.metal(Color(0.8, 0.4, 0.12), 0.4, 0.3, 0.4), hull)
		var cp := c + ang_dir(sl[0]) * (r - 3.0)
		for m in cont:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = m
			mi2.position = cp
			mi2.basis = Basis(Vector3.UP, -sl[0])
			extra.add_child(mi2)
		solid(cp + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 5.0), -sl[0])


func _gate_wreck(g: Vector3, dir: Vector3, side: Vector3, hw: float, _yaw: float, parent: Node3D) -> void:
	# рёбра каркаса корабля аркой
	arc(g + Vector3(0, -3.0, 0), side, hw + 6.5, 0.3, PI - 0.3, 0.32, "steel", 12)
	arc(g + dir * 1.4 + Vector3(0, -3.0, 0), side, hw + 6.5, 0.3, PI - 0.3, 0.32, "steel", 12)
	for k in 5:
		var a := 0.6 + k * (PI - 1.2) / 4.0
		var p := g + side * cos(a) * (hw + 6.5) + Vector3(0, -3.0 + sin(a) * (hw + 6.5), 0)
		beam(p, p + dir * 1.4, 0.14, "steel", 5)
	blink(g + Vector3(0, hw + 3.4, 0) + dir * 0.7, parent)


func _road_wreck(road: String, hw: float, _extra: Node3D) -> void:
	var hull := CD.metal(Color(0.5, 0.53, 0.58), 0.45, 0.55, 0.45, 0.0, 0.0, 0.0, 1.0)
	var key := shader_key("@hullroad_%s" % road, hull)
	for s in road_spots(road, 14.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 2.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		var w := wall_pt(p, sd * sgn, p.y + rng.randf_range(-1.0, 6.0))
		if not wall_found:
			continue
		var b := basis_y(-sd * sgn + Vector3(0, 0.3, 0)) * Basis(Vector3.UP, rng.randf() * TAU)
		put(CD.torn_plate(rng, rng.randf_range(2.0, 3.6), rng.randf_range(1.5, 2.6), 0.6, hull), Transform3D(b, w), key)
		if s[3] % 3 == 1 and not near_trap(p, 6.0):
			# балка наискосок над дорогой
			var a: Vector3 = wall_pt(p, sd, p.y + 5.0)
			var e: Vector3 = wall_pt(p + s[1] * 6.0, -sd, p.y + 8.0)
			beam(a, e, 0.22, "rust", 6)


# ---------------------------------------------------------------------------
#  Кладбище дронов
# ---------------------------------------------------------------------------

func _dead_drone(p: Vector3, yaw: float, s: float, lying: bool) -> void:
	var b := yaw_b(yaw)
	if lying:
		b = b * Basis(Vector3.FORWARD, rng.randf_range(1.0, 1.6))
	var up := b * Vector3.UP
	box(Vector3(0.8, 1.0, 0.5) * s, p + up * 0.9 * s, b, "rust_o")
	sph(0.38 * s, p + up * 1.75 * s, b, "rust", 10)
	box(Vector3(0.36, 0.1, 0.06) * s, p + up * 1.78 * s + b * Vector3(0, 0, 0.36 * s), b, "eye")
	beam(p + b * Vector3(0.5, 1.3, 0) * s, p + b * Vector3(0.8, 0.5, 0.3) * s, 0.1 * s, "steel", 5)
	beam(p + b * Vector3(-0.2, 0.4, 0) * s, p + b * Vector3(-0.3, -0.4, 0.2) * s, 0.12 * s, "steel", 5)


func _plat_drones(c: Vector3, r: float, sl: Array[float], _is_fork: bool, _pname: String, extra: Node3D) -> void:
	for i in mini(3, sl.size()):
		var pp := c + ang_dir(sl[i]) * (r - 2.2)
		for k in rng.randi_range(4, 6):
			var o := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 0.4) * k * 0.3, rng.randf_range(-1.0, 1.0))
			_dead_drone(pp + o, rng.randf() * TAU, rng.randf_range(0.6, 0.9), true)
		solid(pp + Vector3(0, 0.7, 0), Vector3(2.4, 1.4, 2.4))
	# гигантская рука робота из пропасти
	if sl.size() > 3:
		var d := ang_dir(sl[3])
		var sh := c + d * (r + 5.0) + Vector3(0, -26.0, 0)
		var el := c + d * (r + 4.0) + Vector3(0, 5.0, 0)
		var wr := c + d * (r - 0.5) + Vector3(0, 8.0, 0)
		beam(sh, el, 1.1, "rust", 10, 0.9)
		sph(1.3, el, Basis(), "steel", 12)
		beam(el, wr, 0.8, "rust_o", 10, 0.6)
		sph(0.8, wr, Basis(), "steel", 10)
		for k in 3:
			var a := sl[3] + (k - 1) * 0.8
			var fd := (ang_dir(a + PI) * 0.6 + Vector3(0, -1.0, 0)).normalized()
			beam(wr, wr + fd * 2.4, 0.22, "steel", 6, 0.1)
		sph(0.2, el + Vector3(0, 0.6, 0) - d * 1.1, Basis(), "eye", 6)
	var lb := Label3D.new()
	lb.text = "НЕ ВХОДИТЬ\nкладбище дронов"
	lb.font_size = 44
	lb.outline_size = 12
	lb.modulate = Color(1.0, 0.35, 0.25)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.position = c + ang_dir(sl[0] if sl.size() > 0 else 0.0) * (r - 2.2) + Vector3(0, 3.0, 0)
	lb.visibility_range_end = 90.0
	extra.add_child(lb)


func _gate_drones(g: Vector3, _dir: Vector3, side: Vector3, hw: float, yaw: float, parent: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		var p: Vector3 = g + side * sgn * (hw + 1.2)
		post(p + Vector3(0, -10.0, 0), p + Vector3(0, 6.6, 0), 0.25, "rust", 8)
		for k in 4:
			_dead_drone(p + Vector3(0, -1.0 + k * 1.7, 0), yaw + k * 1.3, 0.7, false)
	var bl: Vector3 = g + side * -(hw + 1.2) + Vector3(0, 6.5, 0)
	var br: Vector3 = g + side * (hw + 1.2) + Vector3(0, 6.5, 0)
	beam(bl, br, 0.22, "rust", 8)
	for k in 3:
		var hp := bl.lerp(br, (k + 1) / 4.0)
		beam(hp, hp + Vector3(0, -1.6, 0), 0.03, "steel", 4)
		_dead_drone(hp + Vector3(0, -3.6, 0), yaw + k, 0.65, false)
	blink(g + Vector3(0, 7.0, 0), parent)


func _road_drones(road: String, hw: float, _extra: Node3D) -> void:
	for s in road_spots(road, 18.0):
		var p: Vector3 = s[0]
		var sd: Vector3 = s[2]
		if near_platform(p, 2.0):
			continue
		var sgn := 1.0 if s[3] % 2 == 0 else -1.0
		var pp: Vector3 = p + sd * sgn * (hw + 1.3)
		post(pp + Vector3(0, -14.0, 0), pp + Vector3(0, 5.5, 0), 0.14, "rust", 6)
		var arm: Vector3 = pp + Vector3(0, 5.3, 0) - sd * sgn * 0.8
		beam(pp + Vector3(0, 5.3, 0), arm, 0.08, "rust", 5)
		beam(arm, arm + Vector3(0, -1.2, 0), 0.025, "steel", 4)
		_dead_drone(arm + Vector3(0, -3.0, 0), rng.randf() * TAU, 0.6, false)
