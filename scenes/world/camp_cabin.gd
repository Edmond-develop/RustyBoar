extends Node3D
## Лагерь «Борея-4» в Снежной пустоши: двор за частоколом и бревенчатая изба (шаги 54–55).
##  * Двор закрыт частоколом (ворота — с подветренной стороны): внутри ветер не дует и град не бьёт.
##  * Изба 12×9 м: камин (греет и потихоньку чинит корпус), ковёр и подушки полукругом у огня —
##    E — присесть (camp_seat.gd), стол с лавками, двухъярусные нары, сундук, полки, поленница.
##    Стены изнутри — брёвна с волокнами и кольцами на торцах (cabin_decor.gd), гобелен, картины,
##    рога над камином, связки сушёных трав, лыжи, занавески. Внутри метели не видно — тихо и тепло.
##  * Котелок у камина (camp_pot.gd): E — сварить похлёбку, потом каждый берёт миску.
## Строит геометрию через помощники snow_waste.gd (box/cyl/beam/solid_box…).

const POT := preload("res://scenes/world/camp_pot.gd")
const SEAT := preload("res://scenes/world/camp_seat.gd")
const D := preload("res://scenes/world/cabin_decor.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")

var HALF_W := 6.0                 ## полуширина избы (вбок) (шаг 73: можно менять до build — большой лагерь на Пике)
var HALF_D := 4.5                 ## полуглубина (вперёд — к двери)
const WALL_H := 3.0
const DOOR_W := 1.9               ## ширина дверного проёма
const DOOR_H := 2.4
var WIN_Z := [-1.8, 1.8]          ## окна на боковых стенах (вдоль u)
var YARD_R := 13.0                ## радиус двора (частокол)
var sign_text := "ИЗБА «БОРЕЯ-4»\nкамин, похлёбка, тепло"
var cp_title := "Лагерь «Борея-4»"
var cp_sub := "Контрольная точка. За частоколом не дует; в избе — камин и похлёбка"
const HEARTH_HEAL := 1.5          ## починка корпуса у камина, ед./с

var waste: Node3D                 ## snow_waste.gd
var center := Vector3.ZERO        ## середина двора (на земле)
var floor_c := Vector3.ZERO       ## середина пола избы
var u := Vector3.FORWARD          ## к двери (по ветру)
var r := Vector3.RIGHT            ## вбок
var fire_pos := Vector3.ZERO
var pot: Node3D
var seats: Array[Node3D] = []

var _fire_light: OmniLight3D
var _fire_mats: Array = []
var _t := 0.0


func build(w: Node3D, c: Vector3, wind: Vector2) -> void:
	waste = w
	center = c
	u = Vector3(wind.x, 0, wind.y).normalized()
	r = Vector3(u.z, 0, -u.x)          # правая тройка: r × up = u
	_materials()
	# изба — в наветренной половине двора, дверь смотрит по ветру (внутрь двора)
	var hc := c - u * 4.0
	var gmax := -1e9
	var gmin := 1e9
	for ix in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for iz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var q: Vector3 = hc + r * float(ix) * HALF_W + u * float(iz) * HALF_D
			var g: float = w.ground(q.x, q.z)
			gmax = maxf(gmax, g)
			gmin = minf(gmin, g)
	floor_c = Vector3(hc.x, gmax + 0.35, hc.z)
	_cabin(gmin)
	_interior()
	_decor()
	_yard()


func L(x: float, y: float, z: float) -> Vector3:
	return floor_c + r * x + Vector3.UP * y + u * z


func B() -> Basis:
	return Basis(r, Vector3.UP, u)


func in_cabin(p: Vector3) -> bool:
	var l := p - floor_c
	return absf(l.dot(r)) < HALF_W - 0.1 and absf(l.dot(u)) < HALF_D - 0.1 and l.y > -0.6 and l.y < WALL_H + 0.5


func in_yard(p: Vector3) -> bool:
	return Vector2(p.x - center.x, p.z - center.z).length() < YARD_R - 0.6 and absf(p.y - center.y) < 8.0


func _materials() -> void:
	waste._mats["cab_logs"] = D.logs_mat()
	waste._mats["cab_floor"] = D.floor_mat(r)
	waste._mats["cab_stone"] = D.stone_mat()
	_std("herb_g", Color(0.36, 0.44, 0.2))
	_std("herb_y", Color(0.74, 0.6, 0.24))
	_std("herb_r", Color(0.62, 0.22, 0.2))
	_std("herb_l", Color(0.52, 0.42, 0.66))
	_std("curtain", Color(0.72, 0.24, 0.18))
	_std("cream", Color(0.92, 0.88, 0.78))
	_std("shutter", Color(0.18, 0.36, 0.62), 0.7)
	_std("blanket2", Color(0.55, 0.3, 0.16))
	_std("frame_gold", Color(0.78, 0.58, 0.22), 0.4, 0.6)
	_std("window_in", Color(0.5, 0.62, 0.8), 0.2, 0.0, Color(0.42, 0.55, 0.78), 0.7)
	_std("ember", Color(1.0, 0.35, 0.08), 0.5, 0.0, Color(1.0, 0.3, 0.05), 2.5)


func _std(key: String, col: Color, rough := 0.95, metal := 0.0, emit := Color.BLACK, energy := 0.0) -> void:
	if waste._mats.has(key):
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	waste._mats[key] = m


# ---------------------------------------------------------------------------
#  Сруб: фундамент, крыльцо, стены, окна, крыша
# ---------------------------------------------------------------------------

func _cabin(gmin: float) -> void:
	var b := B()
	var sb: StaticBody3D = waste._shelter_body
	# фундамент и пол
	var fh := floor_c.y - gmin + 0.6
	waste.box(Vector3(HALF_W * 2.0 + 0.3, fh, HALF_D * 2.0 + 0.3), L(0, -fh * 0.5 - 0.02, 0), b, "cab_stone")
	# коллизия фундамента — ровно под стенами (без выступа-порожка у двери)
	waste.solid_box(L(0, -fh * 0.5 - 0.01, 0), Vector3(HALF_W * 2.0 + 0.3, fh, HALF_D * 2.0), b, sb)
	waste.box(Vector3(HALF_W * 2.0 - 0.3, 0.06, HALF_D * 2.0 - 0.3), L(0, 0.03, 0), b, "cab_floor")
	# крыльцо: ступеньки (для вида) и пологий пандус под ними (по нему и ходят)
	var e := L(0, 0, HALF_D + 3.0)
	var drop: float = floor_c.y - waste.ground(e.x, e.z)
	var run := maxf(3.0, drop * 2.2)
	e = L(0, 0, HALF_D + run)
	drop = floor_c.y - waste.ground(e.x, e.z)
	var n_st := maxi(int(ceil(drop / 0.22)), 1)
	for k in n_st:
		var y0 := -drop * (k + 1) / n_st
		waste.box(Vector3(DOOR_W + 0.6, drop / n_st + 0.05, run / n_st + 0.05), L(0, y0 + drop / n_st * 0.5, HALF_D + run * (k + 0.5) / n_st), b, "wood_dark")
	for s in [-1.0, 1.0]:
		waste.beam(L(s * (DOOR_W * 0.5 + 0.3), 0.0, HALF_D + 0.1), L(s * (DOOR_W * 0.5 + 0.3), -drop, HALF_D + run), 0.07, "cab_logs", 6)
		waste.beam(L(s * (DOOR_W * 0.5 + 0.3), 0.9, HALF_D + 0.1), L(s * (DOOR_W * 0.5 + 0.3), 0.9 - drop, HALF_D + run), 0.05, "cab_logs", 6)
		waste.beam(L(s * (DOOR_W * 0.5 + 0.3), -drop - 0.2, HALF_D + run), L(s * (DOOR_W * 0.5 + 0.3), 1.0 - drop, HALF_D + run), 0.06, "cab_logs", 6)
	var ang := atan2(drop, run)
	var ramp_len := sqrt(drop * drop + run * run) + 0.6
	# верхний край пандуса — вровень с полом у порога, лишние 0.6 м уходят в снег внизу
	var rd := Vector3(0, -sin(ang), cos(ang))
	var top := Vector3(0, -0.1 / cos(ang), HALF_D)
	var rc := top + rd * (ramp_len * 0.5)
	waste.solid_box(L(rc.x, rc.y, rc.z), Vector3(DOOR_W + 0.6, 0.2, ramp_len), b * Basis(Vector3.RIGHT, ang), sb)
	# стены из брёвен (и снаружи, и изнутри — одни и те же брёвна), коллизия — плиты
	var th := 0.32
	var side_holes: Array = []
	for z in WIN_Z:
		side_holes.append(Vector2(z, 1.4))
	_log_wall(L(0, 0, -HALF_D), r, HALF_W * 2.0, -u, [])
	_log_wall(L(-HALF_W, 0, 0), u, HALF_D * 2.0, -r, side_holes)
	_log_wall(L(HALF_W, 0, 0), u, HALF_D * 2.0, r, side_holes)
	_log_wall(L(0, 0, HALF_D), r, HALF_W * 2.0, u, [Vector2(0.0, DOOR_W)], true)
	waste.solid_box(L(0, WALL_H * 0.5, -HALF_D), Vector3(HALF_W * 2.0, WALL_H, th), b, sb)
	waste.solid_box(L(-HALF_W, WALL_H * 0.5, 0), Vector3(th, WALL_H, HALF_D * 2.0), b, sb)
	waste.solid_box(L(HALF_W, WALL_H * 0.5, 0), Vector3(th, WALL_H, HALF_D * 2.0), b, sb)
	var dh := DOOR_W * 0.5
	var seg := HALF_W - dh
	for s in [-1.0, 1.0]:
		waste.solid_box(L(s * (dh + seg * 0.5), WALL_H * 0.5, HALF_D), Vector3(seg, WALL_H, th), b, sb)
	waste.solid_box(L(0, (DOOR_H + WALL_H) * 0.5, HALF_D), Vector3(DOOR_W, WALL_H - DOOR_H, th), b, sb)
	# дверная коробка и распахнутая внутрь дверь
	for s in [-1.0, 1.0]:
		waste.box(Vector3(0.12, DOOR_H, 0.46), L(s * (dh + 0.04), DOOR_H * 0.5, HALF_D), b, "wood_dark")
	waste.box(Vector3(DOOR_W + 0.3, 0.16, 0.46), L(0, DOOR_H + 0.05, HALF_D), b, "wood_dark")
	waste.box(Vector3(DOOR_W + 0.2, 0.06, 0.5), L(0, 0.04, HALF_D), b, "wood_dark")
	var dl_len := DOOR_W - 0.1
	var dz := HALF_D - 0.3
	waste.box(Vector3(dl_len, DOOR_H - 0.1, 0.07), L(dh + dl_len * 0.5 + 0.08, (DOOR_H - 0.1) * 0.5, dz), b, "wood")
	for k in 4:
		waste.box(Vector3(0.03, DOOR_H - 0.2, 0.08), L(dh + 0.08 + dl_len * (k + 0.5) / 4.0, (DOOR_H - 0.1) * 0.5, dz), b, "wood_dark")
	for y in [0.45, DOOR_H - 0.5]:
		waste.box(Vector3(dl_len * 0.7, 0.07, 0.09), L(dh + 0.08 + dl_len * 0.35, y, dz), b, "iron")
	waste.sph(0.05, L(dh + dl_len - 0.05, 1.1, dz - 0.07), b, "iron", 6)
	# окна на боковых стенах: снаружи — тёплый свет, ставни и белые наличники; внутри — синий вечер и занавески
	for s in [-1.0, 1.0]:
		for z in WIN_Z:
			_window(s, z)
	# крыша (вальмовая) со снегом и потолок с балками
	var rs := Vector3((HALF_W + 0.7) * 1.4142, 1.0, (HALF_D + 0.7) * 1.4142)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 1.0
	roof.height = 1.0
	roof.radial_segments = 4
	roof.rings = 1
	waste.put(roof, Transform3D(Basis(r * rs.x, Vector3.UP * 2.4, u * rs.z) * Basis(Vector3.UP, PI * 0.25), L(0, WALL_H + 1.2, 0)), "wood_dark")
	waste.put(roof, Transform3D(Basis(r * rs.x * 0.92, Vector3.UP * 2.2, u * rs.z * 0.92) * Basis(Vector3.UP, PI * 0.25), L(0, WALL_H + 1.38, 0)), "snowblock")
	waste.box(Vector3(HALF_W * 2.0, 0.08, HALF_D * 2.0), L(0, WALL_H, 0), b, "cab_floor")
	waste.solid_box(L(0, WALL_H + 0.1, 0), Vector3(HALF_W * 2.0 + 0.4, 0.2, HALF_D * 2.0 + 0.4), b, sb)
	for z in [-3.0, -1.0, 1.0, 3.0]:
		waste.beam(L(-HALF_W, WALL_H - 0.12, z), L(HALF_W, WALL_H - 0.12, z), 0.12, "cab_logs", 8)
	# труба и дым
	var fz := -HALF_D + 0.5
	waste.box(Vector3(1.0, 2.9, 0.9), L(0, WALL_H + 1.6, fz), b, "cab_stone")
	waste.box(Vector3(1.15, 0.12, 1.05), L(0, WALL_H + 3.05, fz), b, "cab_stone")
	var smoke := FX.particles(Color(0.55, 0.55, 0.58, 0.45), 40, 4.0, 0.9, 0.6, 1.2, Vector3(0.6, 0.6, 0.0), 12.0, false)
	smoke.position = L(0, WALL_H + 3.2, fz)
	smoke.emitting = true
	add_child(smoke)
	# фонарь над дверью
	waste.box(Vector3(0.25, 0.3, 0.25), L(0, 2.75, HALF_D + 0.35), b, "lamp")
	var dl := OmniLight3D.new()
	dl.light_color = Color(1.0, 0.75, 0.4)
	dl.light_energy = 1.6
	dl.omni_range = 8.0
	dl.position = L(0, 2.6, HALF_D + 0.8)
	add_child(dl)
	var sign := Label3D.new()
	sign.text = sign_text
	sign.font_size = 30
	sign.outline_size = 9
	sign.modulate = Color(1.0, 0.85, 0.55)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = L(0, 3.5, HALF_D + 0.5)
	add_child(sign)


## Окно в боковой стене s (−1 — левая, +1 — правая) в точке z вдоль u
func _window(s: float, z: float) -> void:
	var b := B()
	var wx := s * HALF_W
	var cy := 1.6
	# стекло: снаружи тёплое, изнутри — холодный вечер за окном
	waste.box(Vector3(0.03, 0.84, 1.36), L(wx + s * 0.05, cy, z), b, "window")
	waste.box(Vector3(0.03, 0.84, 1.36), L(wx - s * 0.05, cy, z), b, "window_in")
	# переплёт
	waste.box(Vector3(0.14, 0.05, 1.36), L(wx, cy, z), b, "wood_dark")
	waste.box(Vector3(0.14, 0.84, 0.05), L(wx, cy, z), b, "wood_dark")
	# снаружи: белый наличник с «кокошником» и синие ставни
	var o := wx + s * 0.22
	waste.box(Vector3(0.06, 0.1, 1.7), L(o, cy + 0.5, z), b, "cream")
	waste.box(Vector3(0.06, 0.1, 1.7), L(o, cy - 0.5, z), b, "cream")
	for q in [-1.0, 1.0]:
		waste.box(Vector3(0.06, 1.1, 0.1), L(o, cy, z + q * 0.8), b, "cream")
	var kb := b * Basis(Vector3.RIGHT, PI * 0.25)
	waste.box(Vector3(0.05, 0.42, 0.42), L(o, cy + 0.62, z), kb, "cream")
	waste.box(Vector3(0.08, 0.14, 0.14), L(o + s * 0.02, cy + 0.62, z), kb, "shutter")
	waste.box(Vector3(0.2, 0.06, 1.8), L(wx + s * 0.25, cy - 0.58, z), b, "wood_dark")
	for q in [-1.0, 1.0]:
		var hinge: float = z + q * 0.85
		waste.box(Vector3(0.05, 0.86, 0.66), L(o + s * 0.03, cy, hinge + q * 0.33), b, "shutter")
		waste.box(Vector3(0.06, 0.06, 0.5), L(o + s * 0.06, cy + 0.25, hinge + q * 0.33), b, "cream")
		waste.box(Vector3(0.06, 0.06, 0.5), L(o + s * 0.06, cy - 0.25, hinge + q * 0.33), b, "cream")
	# изнутри: подоконник, карниз и занавески
	var i := wx - s * 0.24
	waste.box(Vector3(0.24, 0.05, 1.6), L(i, cy - 0.47, z), b, "wood")
	waste.beam(L(i - s * 0.04, cy + 0.6, z - 1.0), L(i - s * 0.04, cy + 0.6, z + 1.0), 0.018, "iron", 5)
	for q in [-1.0, 1.0]:
		for k in 3:
			waste.box(Vector3(0.04, 1.15, 0.13), L(i - s * (0.04 + 0.025 * (k % 2)), cy + 0.02, z + q * (0.62 + k * 0.11)), b, "curtain")
	waste.box(Vector3(0.05, 0.2, 1.9), L(i - s * 0.07, cy + 0.5, z), b, "curtain")


## Стена из горизонтальных брёвен; holes — проёмы (x вдоль стены, ширина), door — с дверным проёмом
func _log_wall(mid: Vector3, along: Vector3, length: float, out: Vector3, holes: Array, door := false) -> void:
	var n := 10
	for k in n:
		var y := 0.16 + k * (WALL_H - 0.1) / n
		var segs: Array = [[-length * 0.5 - 0.25, length * 0.5 + 0.25]]
		for h in holes:
			var hx: float = h.x
			var hw: float = h.y * 0.5
			var in_hole := false
			if door:
				in_hole = y < DOOR_H - 0.1
			else:
				in_hole = y > 1.1 and y < 2.05
			if not in_hole:
				continue
			var ns: Array = []
			for sgm in segs:
				if hx - hw > sgm[0]:
					ns.append([sgm[0], minf(sgm[1], hx - hw)])
				if hx + hw < sgm[1]:
					ns.append([maxf(sgm[0], hx + hw), sgm[1]])
			segs = ns
		for sgm in segs:
			var a: Vector3 = mid + along * float(sgm[0]) + Vector3.UP * y + out * 0.02
			var e: Vector3 = mid + along * float(sgm[1]) + Vector3.UP * y + out * 0.02
			waste.beam(a, e, 0.17, "cab_logs", 10)
		# пакля между брёвнами — светлая полоска
		if k > 0:
			for sgm in segs:
				var a2: Vector3 = mid + along * float(sgm[0]) + Vector3.UP * (y - 0.145)
				var e2: Vector3 = mid + along * float(sgm[1]) + Vector3.UP * (y - 0.145)
				waste.beam(a2, e2, 0.105, "herb_y", 6)


# ---------------------------------------------------------------------------
#  Внутри: камин, место у огня, стол, нары, сундук, полки, поленница, лампы
# ---------------------------------------------------------------------------

func _interior() -> void:
	var b := B()
	var fz := -HALF_D + 0.5
	# камин из камня
	for s in [-1.0, 1.0]:
		waste.box(Vector3(0.55, 1.5, 0.8), L(s * 1.05, 0.75, fz), b, "cab_stone")
	waste.box(Vector3(2.65, 0.35, 0.8), L(0, 1.67, fz), b, "cab_stone")
	waste.box(Vector3(3.1, 0.12, 1.0), L(0, 1.91, fz + 0.08), b, "wood_dark")
	waste.box(Vector3(2.1, WALL_H - 1.97, 0.6), L(0, (1.97 + WALL_H) * 0.5, fz - 0.08), b, "cab_stone")
	waste.box(Vector3(1.6, 1.45, 0.1), L(0, 0.75, fz - 0.3), b, "soot")
	for s in [-1.0, 1.0]:
		waste.box(Vector3(0.06, 1.45, 0.6), L(s * 0.76, 0.75, fz - 0.02), b, "soot")
	waste.box(Vector3(1.6, 0.06, 0.62), L(0, 1.48, fz - 0.02), b, "soot")
	waste.box(Vector3(2.9, 0.1, 0.75), L(0, 0.05, fz + 0.72), b, "cab_stone")
	waste.solid_box(L(0, 0.95, fz), Vector3(2.65, 1.9, 0.8), b, waste._solids)
	# дрова, угли и огонь
	for k in 3:
		var a := L(-0.35 + k * 0.08, 0.2 + k * 0.05, fz - 0.05 + k * 0.1)
		waste.beam(a, a + r * 0.7, 0.07, "cab_logs", 7)
	waste.box(Vector3(1.0, 0.06, 0.4), L(0, 0.1, fz), b, "ember")
	for k in 4:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.55, 0.12)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.45, 0.08)
		fm.emission_energy_multiplier = 4.0
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.6
		var fl := MeshInstance3D.new()
		fl.mesh = sm
		fl.material_override = fm
		fl.position = L(-0.3 + k * 0.2, 0.42, fz + 0.02)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		_fire_mats.append([fm, fl, float(k) * 1.7])
	var sparks := FX.particles(Color(1.0, 0.6, 0.2, 0.9), 14, 1.2, 0.025, 0.4, 1.0, Vector3(0, 0.6, 0), 25.0, false, true)
	sparks.position = L(0, 0.5, fz)
	sparks.emitting = true
	add_child(sparks)
	fire_pos = L(0, 0.4, fz + 0.3)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.6, 0.28)
	_fire_light.light_energy = 2.6
	_fire_light.omni_range = 9.0
	_fire_light.shadow_enabled = false
	_fire_light.position = L(0, 0.9, fz + 0.8)
	add_child(_fire_light)
	var heat := Node3D.new()
	heat.name = "Hearth"
	heat.add_to_group("heat_source")
	heat.position = fire_pos
	add_child(heat)
	# на полке камина: часы, свечи, банки
	waste.box(Vector3(0.3, 0.3, 0.16), L(0, 2.12, fz + 0.35), b, "wood_dark")
	waste.cyl(0.1, 0.1, 0.02, L(0, 2.13, fz + 0.44), Basis(r, u, -Vector3.UP), "cream", 12)
	waste.box(Vector3(0.012, 0.07, 0.01), L(0, 2.16, fz + 0.455), b, "dark")
	waste.box(Vector3(0.05, 0.012, 0.01), L(0.022, 2.13, fz + 0.455), b, "dark")
	for s in [-1.0, 1.0]:
		waste.cyl(0.035, 0.035, 0.22, L(s * 1.3, 2.08, fz + 0.35), b, "candle", 8)
		waste.sph(0.025, L(s * 1.3, 2.22, fz + 0.35), b, "lamp", 6)
		waste.cyl(0.07, 0.07, 0.18, L(s * 0.75, 2.06, fz + 0.35), b, "jar_r" if s < 0 else "jar_y", 8)
	# котелок на очаге
	pot = Node3D.new()
	pot.set_script(POT)
	pot.name = "CampPot"
	pot.position = L(0.0, 0.1, fz + 0.62)
	add_child(pot)
	# ковёр перед камином и подушки полукругом — сесть у огня
	var rz := -1.8
	waste.box(Vector3(4.6, 0.02, 3.0), L(0, 0.07, rz), b, "rug_red")
	waste.box(Vector3(4.1, 0.025, 2.5), L(0, 0.075, rz), b, "rug_gold")
	waste.box(Vector3(3.7, 0.03, 2.1), L(0, 0.08, rz), b, "rug_red")
	for k in 7:
		waste.box(Vector3(0.16, 0.035, 1.8), L(-1.5 + k * 0.5, 0.085, rz), b, "rug_blue")
	var fc := L(0, 0, fz + 0.4)
	var cols := ["rug_blue", "rug_gold", "blanket", "blanket2"]
	var i := 0
	for deg in [-55.0, -20.0, 20.0, 55.0]:
		var a := deg_to_rad(deg)
		var p := fc + r * sin(a) * 2.6 + u * cos(a) * 2.6
		var to_fire := (fc - p)
		to_fire.y = 0.0
		to_fire = to_fire.normalized()
		var sbasis := Basis(to_fire.cross(Vector3.UP).normalized(), Vector3.UP, -to_fire)
		waste.box(Vector3(0.66, 0.12, 0.66), p + Vector3(0, 0.15, 0), sbasis, cols[i])
		waste.box(Vector3(0.5, 0.06, 0.5), p + Vector3(0, 0.23, 0), sbasis, cols[(i + 1) % 4])
		var seat := Node3D.new()
		seat.set_script(SEAT)
		seat.name = "Seat%d" % i
		seat.position = p + Vector3(0, 0.1, 0)
		seat.set("face", to_fire)
		add_child(seat)
		seats.append(seat)
		i += 1
	# стол с лавками справа (под окном)
	var tx := 4.2
	var tz := 1.4
	waste.box(Vector3(1.1, 0.08, 2.2), L(tx, 0.8, tz), b, "wood")
	for sx in [-0.45, 0.45]:
		for sz in [-0.95, 0.95]:
			waste.box(Vector3(0.08, 0.78, 0.08), L(tx + sx, 0.39, tz + sz), b, "wood_dark")
	for sx in [-0.9, 0.9]:
		waste.box(Vector3(0.34, 0.06, 2.0), L(tx + sx, 0.45, tz), b, "wood")
		for sz in [-0.8, 0.8]:
			waste.box(Vector3(0.3, 0.42, 0.06), L(tx + sx, 0.22, tz + sz), b, "wood_dark")
	waste.solid_box(L(tx, 0.42, tz), Vector3(2.2, 0.84, 2.2), b, waste._solids)
	for k in 4:
		var mx := tx - 0.3 + (k % 2) * 0.6
		var mz := tz - 0.6 + (k / 2) * 1.2
		waste.cyl(0.13, 0.13, 0.015, L(mx, 0.845, mz), b, "cream", 12)
		waste.cyl(0.05, 0.045, 0.1, L(mx + 0.17, 0.89, mz + 0.1), b, "iron", 8)
	waste.cyl(0.04, 0.04, 0.16, L(tx, 0.92, tz), b, "candle", 8)
	waste.sph(0.025, L(tx, 1.02, tz), b, "lamp", 6)
	waste.sph(0.13, L(tx, 0.88, tz + 0.35), b.scaled(Vector3(1.0, 0.6, 1.5)), "herb_y", 8)
	# двухъярусные нары слева от двери, вдоль передней стены
	var bx := -4.4
	var bz := HALF_D - 0.72
	for sx in [-1.2, 1.2]:
		for sz in [-0.48, 0.48]:
			waste.box(Vector3(0.1, 2.0, 0.1), L(bx + sx, 1.0, bz + sz), b, "wood_dark")
	for lv in [[0.35, "blanket"], [1.45, "blanket2"]]:
		var ly: float = lv[0]
		waste.box(Vector3(2.4, 0.2, 1.0), L(bx, ly, bz), b, "wood_dark")
		waste.box(Vector3(2.3, 0.14, 0.92), L(bx, ly + 0.17, bz), b, lv[1])
		waste.box(Vector3(0.45, 0.12, 0.7), L(bx - 0.9, ly + 0.3, bz), b, "pillow")
		waste.box(Vector3(2.3, 0.06, 0.06), L(bx, ly + 0.32, bz - 0.47), b, "wood_dark")
	for k in 5:
		waste.box(Vector3(0.36, 0.04, 0.04), L(bx + 1.0, 0.45 + k * 0.28, bz - 0.55), b, "wood")
	waste.solid_box(L(bx, 1.0, bz), Vector3(2.5, 2.0, 1.05), b, waste._solids)
	# сундук под левым окном
	var cz: float = WIN_Z[0]
	waste.box(Vector3(0.62, 0.48, 1.1), L(-HALF_W + 0.55, 0.26, cz), b, "wood")
	waste.box(Vector3(0.66, 0.1, 1.14), L(-HALF_W + 0.55, 0.55, cz), b, "wood_dark")
	for q in [-0.35, 0.35]:
		waste.box(Vector3(0.68, 0.6, 0.06), L(-HALF_W + 0.55, 0.3, cz + q), b, "iron")
	waste.box(Vector3(0.04, 0.1, 0.12), L(-HALF_W + 0.87, 0.42, cz), b, "frame_gold")
	waste.solid_box(L(-HALF_W + 0.55, 0.3, cz), Vector3(0.66, 0.6, 1.14), b, waste._solids)
	# полки с банками на левой стене у камина
	for k in 2:
		var sy := 1.3 + k * 0.5
		waste.box(Vector3(0.3, 0.05, 1.4), L(-HALF_W + 0.4, sy, -3.4), b, "wood")
		for j in 4:
			var jk: String = ["jar_r", "jar_y", "iron", "jar_y"][(j + k) % 4]
			waste.cyl(0.07, 0.07, 0.2, L(-HALF_W + 0.4, sy + 0.12, -3.95 + j * 0.37), b, jk, 8)
	# поленница справа от камина: торцы с кольцами
	for row in 4:
		for k in 5 - row:
			var px := 2.15 + k * 0.24 + row * 0.12
			var py := 0.12 + row * 0.21
			waste.beam(L(px, py, -HALF_D + 0.25), L(px, py, -HALF_D + 0.85), 0.11, "cab_logs", 8)
	waste.solid_box(L(2.65, 0.45, -HALF_D + 0.55), Vector3(1.3, 0.9, 0.65), b, waste._solids)
	# вешалка у двери: шарф и шапка
	var hx := -1.9
	var hz := HALF_D - 0.4
	waste.beam(L(hx, 0.0, hz), L(hx, 1.9, hz), 0.04, "wood_dark", 6)
	for q in [-1.0, 1.0]:
		waste.beam(L(hx, 1.75, hz), L(hx + q * 0.22, 1.85, hz), 0.015, "iron", 4)
	waste.box(Vector3(0.12, 0.7, 0.04), L(hx + 0.24, 1.48, hz), b, "curtain")
	waste.cyl(0.13, 0.15, 0.14, L(hx - 0.22, 1.82, hz), b, "rug_blue", 10)
	waste.solid_cyl(L(hx, 0.9, hz), 0.15, 1.8, waste._solids)
	# лампы под потолком: над столом и посреди комнаты
	for lp in [Vector2(tx, tz), Vector2(-1.5, 1.2)]:
		waste.beam(L(lp.x, WALL_H, lp.y), L(lp.x, WALL_H - 0.55, lp.y), 0.015, "iron", 4)
		waste.cyl(0.04, 0.2, 0.14, L(lp.x, WALL_H - 0.6, lp.y), b, "iron", 10)
		waste.sph(0.1, L(lp.x, WALL_H - 0.7, lp.y), b, "lamp", 8)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.78, 0.48)
		ll.light_energy = 1.2
		ll.omni_range = 7.0
		ll.position = L(lp.x, WALL_H - 0.85, lp.y)
		add_child(ll)


# ---------------------------------------------------------------------------
#  Украшения: гобелен, картины, рога, травы, лыжи
# ---------------------------------------------------------------------------

func _decor() -> void:
	var b := B()
	var bw := -HALF_D + 0.2           # поверхность задней стены изнутри
	# гобелен слева от камина
	_picture(D.tapestry(), L(-3.4, 1.65, bw + 0.02), u, Vector2(1.6, 2.2))
	waste.beam(L(-4.35, 2.8, bw + 0.06), L(-2.45, 2.8, bw + 0.06), 0.03, "wood_dark", 6)
	for s in [-1.0, 1.0]:
		waste.sph(0.05, L(-3.4 + s * 0.97, 2.8, bw + 0.06), b, "frame_gold", 6)
	# картины справа от камина
	_framed(D.painting(0), L(3.0, 1.75, bw + 0.02), Vector2(1.12, 0.8), "frame_gold")
	_framed(D.painting(1), L(4.65, 1.6, bw + 0.02), Vector2(0.62, 0.8), "wood_dark")
	# рога над камином
	var fz := -HALF_D + 0.5
	var az := fz + 0.24
	waste.box(Vector3(0.42, 0.3, 0.05), L(0, 2.5, az), b, "wood")
	waste.sph(0.09, L(0, 2.5, az + 0.05), b, "bone", 8)
	for s in [-1.0, 1.0]:
		var p0 := L(s * 0.08, 2.54, az + 0.08)
		var p1 := L(s * 0.42, 2.64, az + 0.16)
		var p2 := L(s * 0.7, 2.86, az + 0.12)
		waste.beam(p0, p1, 0.035, "bone", 6, 0.03)
		waste.beam(p1, p2, 0.03, "bone", 6, 0.015)
		waste.beam(p1, L(s * 0.4, 2.87, az + 0.2), 0.025, "bone", 5, 0.01)
		waste.beam(p0.lerp(p1, 0.5), L(s * 0.22, 2.84, az + 0.18), 0.025, "bone", 5, 0.01)
		waste.beam(p1.lerp(p2, 0.6), L(s * 0.76, 2.7, az + 0.22), 0.02, "bone", 5, 0.008)
	# гирлянда сушёных трав вдоль задней стены справа и под балкой посреди избы
	_herbs(L(1.4, 2.88, bw + 0.08), L(5.6, 2.88, bw + 0.08), 7)
	_herbs(L(-4.6, WALL_H - 0.27, -1.0), L(-1.6, WALL_H - 0.27, -1.0), 5)
	_herbs(L(1.6, WALL_H - 0.27, 1.0), L(5.2, WALL_H - 0.27, 1.0), 6)
	# лыжи крест-накрест и снегоступы на передней стене справа от двери
	var fw := HALF_D - 0.2
	for s in [-1.0, 1.0]:
		var sb := b * Basis(Vector3.BACK, s * 0.32)
		waste.box(Vector3(0.09, 1.9, 0.03), L(3.6 + s * 0.12, 1.45, fw - 0.03 - (s + 1.0) * 0.02), sb, "curtain")
		waste.beam(L(3.6 - s * 0.45, 0.6, fw - 0.1), L(3.6 + s * 0.2, 2.3, fw - 0.1), 0.012, "iron", 4)
	for q in [-0.3, 0.3]:
		var sc := L(5.0 + q, 1.55, fw - 0.03)
		waste.cyl(0.22, 0.22, 0.03, sc, Basis(r * 0.7, u, -Vector3.UP * 1.2), "wood", 10)
		waste.cyl(0.18, 0.18, 0.035, sc, Basis(r * 0.7, u, -Vector3.UP * 1.2), "herb_y", 10)


## Картинка-квад на стене: смотрит в сторону n (в комнату)
func _picture(img: Image, pos: Vector3, n: Vector3, size: Vector2) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = D.tex_mat(img)
	var x := Vector3.UP.cross(n).normalized()
	mi.transform = Transform3D(Basis(x, Vector3.UP, n), pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Картина в раме на задней стене
func _framed(img: Image, pos: Vector3, size: Vector2, frame: String) -> void:
	var b := B()
	_picture(img, pos + u * 0.03, u, size)
	var t := 0.07
	waste.box(Vector3(size.x + t * 2.0, size.y + t * 2.0, 0.03), pos, b, "wood_dark")
	waste.box(Vector3(size.x + t * 2.0, t, 0.06), pos + Vector3.UP * (size.y * 0.5 + t * 0.5) + u * 0.02, b, frame)
	waste.box(Vector3(size.x + t * 2.0, t, 0.06), pos - Vector3.UP * (size.y * 0.5 + t * 0.5) + u * 0.02, b, frame)
	waste.box(Vector3(t, size.y, 0.06), pos + r * (size.x * 0.5 + t * 0.5) + u * 0.02, b, frame)
	waste.box(Vector3(t, size.y, 0.06), pos - r * (size.x * 0.5 + t * 0.5) + u * 0.02, b, frame)


## Верёвка с провисом и пучки трав вниз головой
func _herbs(a: Vector3, e: Vector3, n: int) -> void:
	var b := B()
	var prev := a
	for k in range(1, 9):
		var t := k / 8.0
		var p := a.lerp(e, t) - Vector3.UP * 0.12 * sin(t * PI)
		waste.beam(prev, p, 0.01, "wood_dark", 4)
		prev = p
	var kinds := ["herb_g", "herb_y", "herb_r", "herb_l", "herb_g", "herb_y"]
	for k in n:
		var t := (k + 0.5) / n
		var p := a.lerp(e, t) - Vector3.UP * 0.12 * sin(t * PI)
		var hang := 0.06 + 0.04 * (k % 2)
		waste.beam(p, p - Vector3.UP * hang, 0.008, "herb_y", 4)
		waste.sph(0.025, p - Vector3.UP * hang, b, "curtain", 5)
		var key: String = kinds[(k * 5 + n) % kinds.size()]
		waste.cyl(0.025, 0.085, 0.3, p - Vector3.UP * (hang + 0.17), b * Basis(Vector3.UP, k * 1.3), key, 7)
		for j in 3:
			var off := r * (j - 1) * 0.04 + u * 0.02 * (j % 2)
			waste.beam(p - Vector3.UP * (hang + 0.28) + off, p - Vector3.UP * (hang + 0.4) + off * 1.6, 0.008, "herb_g", 3)


# ---------------------------------------------------------------------------
#  Двор
# ---------------------------------------------------------------------------

func _yard() -> void:
	var sb: StaticBody3D = waste._shelter_body
	# частокол по кругу, ворота — по ветру (с подветренной стороны)
	var gate_a := atan2(u.z, u.x)
	var n := 170
	for k in n:
		var a := TAU * k / n
		var da := absf(wrapf(a - gate_a, -PI, PI))
		if da < 0.13:
			continue
		var q := Vector2(center.x + cos(a) * YARD_R, center.z + sin(a) * YARD_R)
		var g: float = waste.ground(q.x, q.y)
		var h := 2.9 + 0.25 * sin(k * 1.7)
		var base := Vector3(q.x, g - 0.4, q.y)
		waste.beam(base, base + Vector3(0, h + 0.4, 0), 0.19, "cab_logs", 7, 0.12)
		if k % 4 == 0:
			var a2 := a + TAU * 2.0 / n
			var mid_a := a + TAU * 1.5 / n
			if absf(wrapf(a2 - gate_a, -PI, PI)) >= 0.13:
				var cq := Vector2(center.x + cos(mid_a) * YARD_R, center.z + sin(mid_a) * YARD_R)
				var cg: float = waste.ground(cq.x, cq.y)
				waste.solid_box(Vector3(cq.x, cg + 1.4, cq.y), Vector3(0.5, 3.4, YARD_R * TAU / n * 4.4), Basis(Vector3.UP, -mid_a), sb)
	# столбы ворот с фонарями
	for s in [-1.0, 1.0]:
		var a: float = gate_a + s * 0.16
		var q := Vector3(center.x + cos(a) * YARD_R, 0.0, center.z + sin(a) * YARD_R)
		q.y = waste.ground(q.x, q.z)
		waste.beam(q - Vector3(0, 0.4, 0), q + Vector3(0, 3.6, 0), 0.25, "cab_logs", 8)
		waste.sph(0.16, q + Vector3(0, 3.75, 0), Basis(), "lamp", 8)
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.7, 0.35)
	gl.light_energy = 1.8
	gl.omni_range = 10.0
	gl.position = center + u * YARD_R + Vector3(0, 3.6, 0)
	add_child(gl)
	# во дворе: поленница, бочки
	for k in 6:
		var q := center + r * (6.0 + (k % 3) * 0.6) + u * (3.0 + (k / 3) * 0.5)
		q.y = waste.ground(q.x, q.z)
		waste.beam(q + Vector3(0, 0.15 + (k / 3) * 0.3, 0) - u * 0.6, q + Vector3(0, 0.15 + (k / 3) * 0.3, 0) + u * 0.6, 0.14, "cab_logs", 7)
	waste.solid_box(center + r * 6.6 + u * 3.25 + Vector3(0, waste.ground(center.x, center.z) - center.y + 0.4, 0), Vector3(2.0, 0.8, 1.4), Basis(r, Vector3.UP, u), waste._solids)
	for k in 3:
		var q := center - r * (6.5 + k * 0.8) + u * 2.0
		q.y = waste.ground(q.x, q.z)
		waste.cyl(0.32, 0.32, 0.95, q + Vector3(0, 0.45, 0), Basis(), "barrel", 10)
		waste.solid_cyl(q + Vector3(0, 0.45, 0), 0.34, 0.95)
	# контрольная точка — у крыльца
	var cp := Area3D.new()
	cp.set_script(CHECKPOINT)
	cp.name = "CampCheckpoint"
	cp.set("snap_to_terrain", false)
	cp.set("size", Vector3(46.0, 10.0, 46.0))
	# сама точка (её столб с фонарём) — во дворе перед крыльцом, не в избе
	var cpp := center + u * 8.5
	cpp.y = waste.ground(cpp.x, cpp.z)
	cp.set("respawn_offset", (L(0, 0.6, HALF_D + 3.5) - cpp))
	cp.set("title", cp_title)
	cp.set("subtitle", cp_sub)
	cp.position = cpp
	add_child(cp)


func _process(delta: float) -> void:
	_t += delta
	var fl := 0.8 + 0.2 * sin(_t * 7.0) + 0.1 * sin(_t * 13.3)
	if _fire_light:
		_fire_light.light_energy = 2.6 * fl
	for e in _fire_mats:
		var m: StandardMaterial3D = e[0]
		var mi: MeshInstance3D = e[1]
		var ph: float = e[2]
		m.emission_energy_multiplier = 3.0 + 1.5 * sin(_t * 9.0 + ph)
		mi.scale = Vector3(1.0, 0.85 + 0.25 * sin(_t * 8.0 + ph), 1.0)


func _physics_process(delta: float) -> void:
	# у камина корпус потихоньку чинится
	var me = Network.local_player
	if me == null or not is_instance_valid(me) or me.is_dead:
		return
	if me.global_position.distance_to(fire_pos) < 3.5 and me.health < me.max_health:
		me.health = minf(me.health + HEARTH_HEAL * delta, me.max_health)
		if Engine.get_physics_frames() % 15 == 0:
			me.health_changed.emit(me.health, me.max_health)
