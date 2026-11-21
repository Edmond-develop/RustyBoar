class_name SnowTerrain
extends StaticBody3D
## Процедурный рельеф снежной планеты «Борея».
## Высота в каждой точке = лёгкий шум + специально спланированные участки.
## Тропа идёт с юга (база на месте крушения) на север (z = -200, станция) вдоль x ≈ 0.
##
##   z 1210 … 1020 База: инопланетный луг, разбитый корабль (место крушения ~ z 1110)
##   z 1020 … 945  Переход: трава редеет, иней, сугробы
##   z  945 … 917  Лагерь — контрольная точка Бореи
##   z  915 … 518  Озеро: каток и Ледяной лабиринт (450 м в ширину)
##   z  518 … 302  Ледяное поле (до 800 м) и воронка к каньону — по бокам «крылья» рельефа
##   z  302 … -654 Ледяной каньон: плато +28 м, ущелья с пропастью 60 м, пруды, пещера, подъёмник
##   z -654 …-1668 Снежная пустошь: сугробы, метель, тропа с вешками, скрытые трещины (waste_layout.gd)
##   z-1668 …-1728 «Передышка»: тихое широкое дно перед долиной (то же _valley_height, s < 0)
##   z-1728 …-2588 Лавинная долина (avalanche_layout.gd): перевал, крутые склоны по бокам
##   z-2438 …-2476 Трещины (две пропасти поперёк пути)
##   z-2478 …-2542 Плато бурь (обрывы по бокам)
##   z-2544 …-2586 Каньон с ледяной пещерой
##   z-2586 …-2636 Замёрзшее озеро и станция
##
## Всё севернее долины — прежний мир, сдвинутый к северу (z_old = z + AvalancheLayout.OLD_SHIFT):
## его рельеф считает _old_height() в старых координатах.
## Чтобы поменять форму мира — правь функцию height_at().

@export var size_x := 540.0
@export var size_z := 4975.0
@export var north_edge_z := -3760.0
@export var cell := 1.5
@export var noise_seed := 7
@export var terrain_material: Material

## Трещины: (центр по z, полуширина)
const CREVASSES := [Vector2(-12.0, 3.0), Vector2(-30.0, 3.5)]
const CREVASSE_DEPTH := -30.0
const RIVER_HALF := 225.0  ## Полуширина замёрзшего озера (как в ice_river.gd)
const LAKE_CENTER := Vector2(0.0, -175.0)     ## (в старых координатах)
const OLD_NORTH_EDGE := -215.0                 ## северный край мира в старых координатах
## Каньон: ущелья в плато (canyon_layout.gd); горловина — до ABYSS_S, дно пропасти — ABYSS_Y
const ABYSS_HALF := 300.0
const ABYSS_S := 274.0       ## горловина заходит под площадку A — без щели
const ABYSS_N := CanyonLayout.Z_MIN
const HILL := preload("res://scenes/world/snow_hill_layout.gd")
const ABYSS_Y := CanyonLayout.ABYSS_Y
## «Крылья» рельефа по бокам Ледяного поля (основная сетка — только ±size_x/2)
const WING_Z := Vector2(-666.0, 534.0)
const WASTE_WING_Z := Vector2(-1690.0, -666.0)   ## крыло у пустоши (она шире основной сетки)
const WASTE_WING_OUT := 400.0
const PEAK_WING_Z := Vector2(-3760.0, -2560.0)   ## шаг 73: у Пика мир шире — вокруг горы просторная равнина
const PEAK_WING_OUT := 452.0
const WING_OUT := 452.0
const WING_CELL := 3.0
const LAKE_RADIUS := Vector2(24.0, 17.0)
## Место крушения: где лежит нос корабля, и откуда он прилетел (конец борозды)
const CRASH_NOSE := Vector2(0.0, 1104.0)
const CRASH_TAIL := Vector2(12.0, 1204.0)
const BASE_START_Z := 950.0   ## Отсюда на юг начинается база (луг)
const BASE_SPAWN := Vector2(8.0, 1084.0)   ## Где появляются дроны

## Текстуры земли (нарисованы для игры: цвет + объём)
const TEXTURES := {
	"moss_tex": preload("res://assets/textures/terrain/moss_albedo.png"),
	"moss_nrm": preload("res://assets/textures/terrain/moss_normal.png"),
	"soil_tex": preload("res://assets/textures/terrain/soil_albedo.png"),
	"soil_nrm": preload("res://assets/textures/terrain/soil_normal.png"),
	"rock_tex": preload("res://assets/textures/terrain/rock_albedo.png"),
	"rock_nrm": preload("res://assets/textures/terrain/rock_normal.png"),
	"snow_tex": preload("res://assets/textures/terrain/snow_albedo.png"),
	"snow_nrm": preload("res://assets/textures/terrain/snow_normal.png"),
}

var _noise := FastNoiseLite.new()
var _big_noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group("safe_ground")
	add_to_group("terrain")
	_noise.seed = noise_seed
	_noise.frequency = 0.03
	_noise.fractal_octaves = 3
	_big_noise.seed = noise_seed + 1
	_big_noise.frequency = 0.008
	var sm := terrain_material as ShaderMaterial
	if sm:
		for key in TEXTURES:
			sm.set_shader_parameter(key, TEXTURES[key])
		# шаг 132: снег в горах — фото-текстура (если файлы на месте)
		if ResourceLoader.exists("res://assets/glacier/snow013_color.jpg"):
			sm.set_shader_parameter("snow2_tex", load("res://assets/glacier/snow013_color.jpg"))
			sm.set_shader_parameter("snow2_nrm", load("res://assets/glacier/snow013_normal.jpg"))
			sm.set_shader_parameter("snow2_on", 1.0)
		sm.set_shader_parameter("crash_nose", CRASH_NOSE)
		sm.set_shader_parameter("crash_tail", CRASH_TAIL)
		sm.set_shader_parameter("meadow_start_z", BASE_START_Z + 15.0)
		sm.set_shader_parameter("meadow_full_z", BASE_START_Z + 85.0)
		sm.set_shader_parameter("ice_wall_rect", Vector4(-360.0, IceRiver.CANYON_S + 1.0, 360.0, IceRiver.CANYON_S + 40.0))   # шаг 139: ледяные стены — только у прохода
		sm.set_shader_parameter("granite_rect", Vector4(-420.0, HILL.Z_TOP - 4.0, 420.0, HILL.CHASM_S + 1.0))       # шаг 143: скалы пропасти
	_build()


## Высота рельефа в точке (x, z).
func height_at(x: float, z: float) -> float:
	if z >= 520.0:
		return _old_height(x, z, z)
	if z <= AvalancheLayout.N_Z:
		return _peak_height(x, z)          # шаг 72: за Лавинной долиной — Пик (прежний мир убран)
	if z <= WasteLayout.N_Z:
		var hv := _valley_height(x, z)
		# у северного края долина переходит в прежний мир (площадка перед Трещинами)
		var tn := smoothstep(AvalancheLayout.N_Z + 40.0, AvalancheLayout.N_Z, z)
		if tn > 0.0:
			hv = lerpf(hv, _peak_height(x, AvalancheLayout.N_Z), tn)
		return hv
	if z <= IceRiver.CANYON_N:
		var h := _waste_height(x, z)
		# у северного края пустошь переходит в Лавинную долину
		var t := smoothstep(WasteLayout.N_Z + 60.0, WasteLayout.N_Z, z)
		if t > 0.0:
			h = lerpf(h, _valley_height(x, WasteLayout.N_Z), t)
		return h
	if z >= IceRiver.CANYON_S + 2.0:
		return _field_height(x, z)
	if z <= IceRiver.CANYON_S - 2.0:
		# шаг 139: Снежная гора (вместо каньона); у северного края — плавно в пустошь
		var hc := _hill_height(x, z)
		var kn := smoothstep(IceRiver.CANYON_N, IceRiver.CANYON_N + 22.0, z)
		if kn < 1.0:
			hc = lerpf(_waste_height(x, z), hc, kn)
		return hc
	var k := (z - (IceRiver.CANYON_S - 2.0)) / 4.0
	return lerpf(_hill_height(x, z), _field_height(x, z), k)


## Снежная пустошь: сугробы и заструги, у тропы ровнее, трещины под снегом, по бокам горы
func _waste_height(x: float, z: float) -> float:
	var ax := absf(x)
	var bn := _big_noise.get_noise_2d(x * 1.6, z * 1.6)
	var dunes := bn * 2.4 + _noise.get_noise_2d(x * 0.55, z * 0.55) * 0.9
	# заструги — мелкие гребешки, вытянутые поперёк ветра
	var sas := 0.2 * sin(x * 0.5 + z * 0.33 + _noise.get_noise_2d(x * 1.7, z * 1.7) * 3.0)
	var pd := WasteLayout.path_dist(x, z)
	var h := WasteLayout.base_y(z) + (dunes + sas) * lerpf(0.22, 1.0, smoothstep(4.0, 16.0, pd))
	# трещина: под пластом — провал; вокруг снег ровный (вровень с пластом)
	var cr := WasteLayout.crack_at(x, z)
	if cr.x < 7.0:
		if cr.x < -0.2:
			return WasteLayout.CRACK_DEPTH
		h = lerpf(cr.y, h, smoothstep(0.6, 7.0, cr.x))
	# у выхода из каньона — ровно, на уровне берега
	h = lerpf(h, -2.5, smoothstep(-690.0, -657.0, z))
	# горы по бокам
	var edge := clampf((ax - 286.0) * 1.5, 0.0, 70.0)
	return h + edge + edge * 0.25 * _big_noise.get_noise_2d(z * 2.0, x * 2.0)


## Шаг 72–73: Пик (MountainLayout) — предвершина со спиральной тропой и главная вершина к северу;
## вокруг равнина, по краям — зубчатые горы-рамка
func _peak_height(x: float, z: float) -> float:
	var n1 := _big_noise.get_noise_2d(x * 1.8, z * 1.8)
	var n2 := _noise.get_noise_2d(x * 0.6, z * 0.6)
	var dx := x - MountainLayout.CX
	var dz := z - MountainLayout.CZ
	var r := sqrt(dx * dx + dz * dz)
	var bx := x - MountainLayout.BX
	var bz := z - MountainLayout.BZ
	var rb := sqrt(bx * bx + bz * bz)
	var calm := minf(smoothstep(MountainLayout.R0 + 15.0, MountainLayout.R0 + 70.0, r), smoothstep(250.0, 320.0, rb))
	var plain := MountainLayout.BASE_Y + (n2 * 0.6 + 2.0 * _big_noise.get_noise_2d(x * 0.7, z * 0.7)) * calm
	# горы-рамка: край неровный (отроги и заливы), склоны с контрфорсами, наверху — зубцы и пики
	var wob := _big_noise.get_noise_2d(z * 0.9 + 77.0, 3.0) * 40.0 + _noise.get_noise_2d(z * 0.25, 9.0) * 10.0
	var wob2 := _big_noise.get_noise_2d(x * 0.9 - 51.0, 7.0) * 40.0
	var ex := clampf((absf(x) - MountainLayout.EDGE_X - wob) * 1.6, 0.0, 160.0)
	var en := clampf((MountainLayout.PLAIN_N - z - wob2) * 1.6, 0.0, 160.0)
	var f := maxf(ex, en)
	if f > 0.0:
		var rn := 1.0 - absf(_big_noise.get_noise_2d(x * 1.15 + 300.0, z * 1.15))
		var gully := absf(sin((x + z) * 0.045 + n1 * 3.0)) * 2.0 - 1.0
		plain += f * (1.0 + 0.3 * n1) + gully * 9.0 * smoothstep(5.0, 40.0, f) + pow(rn, 3.0) * 190.0 * smoothstep(15.0, 120.0, f)
	var h := plain
	var g := MountainLayout.ground(x, z, n1, n2)
	if not is_nan(g):
		h = maxf(h, g)
	var gb := MountainLayout.block(x, z, n1, n2)
	if not is_nan(gb):
		h = maxf(h, gb)
	# шаг 79: широкая пропасть с выступами
	var cv := MountainLayout.sp_carve(x, z)
	if not is_nan(cv):
		h = minf(h, cv)
	# шаг 86: ледник — ровное поле (поверхность — своя сетка), у трещин — глубоко
	var gv := MountainLayout.gl_carve(x, z)
	if not is_nan(gv):
		h = gv
	return h


## Лавинная долина: ровное дно вдоль тропы, по бокам — крутые склоны (чем выше, тем круче), гребни
func _valley_height(x: float, z: float) -> float:
	var s := AvalancheLayout.s_of(z)
	var cx := AvalancheLayout.center_x(s)
	var hw := AvalancheLayout.half_w(s)
	var dx := x - cx
	var d := absf(dx) - hw
	var h := AvalancheLayout.floor_y(s)
	# дно: мелкие сугробы, к краям чуть выше (тропа — посередине)
	h += _noise.get_noise_2d(x * 0.7, z * 0.7) * 0.45 + 0.0005 * dx * dx
	# шаг 66: трещины поперёк дна в зоне погони
	h += AvalancheLayout.crack_off(x, s)
	if d > 0.0:
		var wall := 0.3 * d + 0.011 * d * d
		# рёбра и кулуары — желоба, по которым сходит снег
		var rib := _big_noise.get_noise_2d(z * 1.4 + signf(dx) * 300.0, d * 0.6)
		wall += rib * 9.0 * smoothstep(8.0, 40.0, d)
		wall += _noise.get_noise_2d(x * 0.35, z * 0.35) * 2.5 * smoothstep(4.0, 20.0, d)
		h += minf(wall, 140.0 + rib * 20.0)
		# шаг 137: за гребнем склонов — высокие горы (до ~250 м): с них сходят дальние лавины, видно со дна долины
		var mt := maxf(d - 92.0, 0.0)
		if mt > 0.0:
			h += mt * (1.6 + 0.45 * rib) + _big_noise.get_noise_2d(x * 0.9 + 77.0, z * 0.9) * 16.0 * smoothstep(0.0, 30.0, mt)
	return h


## Ледяное поле и воронка: дно подо льдом шириной hw_at(z), берег, за ним горы
func _field_height(x: float, z: float) -> float:
	var ax := absf(x)
	var hw := IceRiver.hw_at(z)
	var ry := IceRiver.river_y(z)
	var water := smoothstep(IceRiver.CANYON_S, IceRiver.CANYON_S + 8.0, z)
	var inside := 1.0 - smoothstep(hw - 1.0, hw + 1.0, ax)
	var bed := ry - (IceRiver.WATER_GAP + IceRiver.lake_depth(x, z)) * water
	var shore := ry + clampf((ax - hw) * 0.35, 0.0, 6.0)
	var h := lerpf(shore, bed, inside)
	var edge := clampf((ax - hw - 12.0) * 1.5, 0.0, 45.0)
	var bn := _big_noise.get_noise_2d(z * 2.0, x * 2.0)
	h += edge + edge * 0.15 * bn
	return h


## Ледяной каньон: горловина у z 302…279, дальше пропасть 60 м во всю ширину,
## отвесные стены и горы по бокам; в пропасти — три пруда на «столбах» (берег 4 м и обрыв)
func _canyon_height(x: float, z: float) -> float:
	var ax := absf(x)
	var bn := _big_noise.get_noise_2d(z * 2.0, x * 2.0)
	# северная кромка: берег старого озера на его уровне (над ним — стена плато)
	if z < CanyonLayout.Z_MIN and ax < IceRiver.LAKE_HALF:
		return IceRiver.river_y(IceRiver.CANYON_N - 0.1)
	# горловина: ровный снег шириной 28 м, по бокам — стены
	if z > ABYSS_S:
		var wall := clampf((ax - 14.0) * 4.0, 0.0, 30.0)
		return wall + wall * 0.2 * bn + clampf((ax - 40.0) * 0.6, 0.0, 30.0)
	# пещера-«убежище»: ровный пол под ледяной крышей
	if CanyonLayout.in_cave(x, z):
		return CanyonLayout.CAVE_Y - 0.02
	# ущелья в ледяном плато: внутри — пропасть, по краю — отвесная стена
	var d := CanyonLayout.wall_d(x, z)
	var floor_y := ABYSS_Y + _noise.get_noise_2d(x * 0.7, z * 0.7) * 4.0
	var top := CanyonLayout.PLATEAU + bn * 4.0 + clampf((ax - 345.0) * 1.5, 0.0, 25.0)
	var h := floor_y
	if d > 0.0:
		h = lerpf(floor_y, top, smoothstep(0.0, CanyonLayout.WALL, d))
	# пруды: дно под водой, береговая кромка и обрыв в пропасть
	for p in IceRiver.POOLS:
		var px := maxf(maxf(p[0] - x, x - p[1]), 0.0)
		var pz := maxf(maxf(p[2] - z, z - p[3]), 0.0)
		var pd := sqrt(px * px + pz * pz)
		var y: float = p[4]
		if pd <= 0.0:
			var inner := minf(minf(x - p[0], p[1] - x), minf(z - p[2], p[3] - z))
			var bed := y - IceRiver.WATER_GAP - IceRiver.lake_depth(x, z)
			return lerpf(y - 0.02, bed, smoothstep(0.6, 2.6, inner))
		# кромка неровной ширины (4…7.4 м), обрыв — уступами (не плоская стенка)
		var rw := 4.0 + CanyonLayout.pool_rim_extra(x, z)
		var s := pd - rw
		# за 4 м кромка чуть понижается (дороги, подходящие к пруду снизу, не упираются в неё)
		var lip := maxf(minf(pd, rw) - 4.0, 0.0) * 0.35
		var rim := y - lip if s < 0.0 else y - lip - (s * 7.0 + 2.2 * sin(s * 1.3))
		h = maxf(h, rim)
	return h


## Шаг 139: Снежная гора — склон над озером (подъёмник), вершина, трасса для сноуборда
## (изгибы, лес, гребень над ущельями, выкат), по бокам — высокие берега и горы
func _hill_height(x: float, z: float) -> float:
	var ax := absf(x)
	var bn := _big_noise.get_noise_2d(z * 2.0, x * 2.0)
	var n1 := _noise.get_noise_2d(x * 0.5, z * 0.5)
	var mt := clampf((ax - 385.0) * 1.2, 0.0, 150.0)            # горы по краям мира (шаг 142: шире)
	if z > HILL.Z_TOP:
		# шаг 140: уступ у льда → пропасть во всю ширину → отвесная стена горы
		var fy := HILL.face_y(z)
		var pw := clampf((ax - IceRiver.PASS_HALF - 12.0) * 1.5, 0.0, 45.0) * smoothstep(HILL.CHASM_S - 2.0, HILL.CHASM_S + 4.0, z)
		# стены пропасти и горы неровные (рёбра, выступы), дно — в снегу и обломках
		var wall_k := smoothstep(HILL.CHASM_S + 1.0, HILL.CHASM_S - 3.0, z) * (1.0 - smoothstep(HILL.CHASM_S - 6.0, HILL.CHASM_S - 12.0, z)) \
				+ smoothstep(HILL.CHASM_N + 8.0, HILL.CHASM_N - 6.0, z) * smoothstep(-2.0, 8.0, z)
		var rib := _big_noise.get_noise_2d(x * 3.0, z * 0.7) * 6.0 + n1 * 2.0
		var floor_m := (1.0 - smoothstep(HILL.CHASM_N + 4.0, HILL.CHASM_N - 4.0, z)) * smoothstep(HILL.CHASM_S - 8.0, HILL.CHASM_S - 14.0, z)
		var floor_n := (maxf(bn, 0.0) * 5.0 + n1 * 0.9) * floor_m
		var ledge_n := n1 * 0.25 * smoothstep(HILL.CHASM_S + 2.0, HILL.CHASM_S + 5.0, z)
		var h0 := fy + pw + rib * wall_k + floor_n + ledge_n + mt + mt * 0.25 * bn
		# шаг 143: русло реки по дну пропасти
		var rd := absf(z - HILL.river_z(x))
		var ch := (1.0 - smoothstep(HILL.river_hw(x), HILL.river_hw(x) + 5.0, rd)) * floor_m * (1.0 - smoothstep(380.0, 400.0, ax))
		return lerpf(h0, HILL.RIVER_Y - 2.0 + n1 * 0.3, ch)
	# шаг 142: склон горы на всю ширину, по нему — трасса-серпантин (ровная поперёк), вокруг — лес
	var mt2 := clampf((ax - 385.0) * 1.2, 0.0, 150.0)
	var h := HILL.hill_y(x, z)
	var nr: Array = HILL.near(x, z)
	var hw := HILL.half_w(float(nr[1]))
	var off := smoothstep(hw - 2.0, hw + 10.0, absf(float(nr[0])))
	h += n1 * lerpf(0.15, 1.1, off) + bn * 3.5 * off       # шаг 144: на трассе — ровнее (доска не «цепляется» за кочки)
	# у вершины — ровная площадка
	h = lerpf(h, HILL.TOP_Y + n1 * 0.3, smoothstep(HILL.Z_START + 4.0, HILL.Z_TOP, z))
	return h + mt2 + mt2 * 0.25 * bn


## Прежний рельеф (до шага 41). z — в старых координатах; zn — настоящая z (для озера).
func _old_height(x: float, z: float, zn: float) -> float:
	var ax := absf(x)
	var h := _noise.get_noise_2d(x, z) * 1.6

	# Вдоль тропы ровнее, в стороне — крупные холмы
	h *= lerpf(1.0, 0.2, 1.0 - smoothstep(5.0, 16.0, ax))
	h += maxf(_big_noise.get_noise_2d(x, z), 0.0) * 10.0 * smoothstep(20.0, 45.0, ax)

	# Замёрзшее озеро: дно подо льдом и пологие берега далеко по краям
	var wr := _band(z, 917.0, 80.0, 6.0)
	if wr > 0.0:
		var ry := IceRiver.river_y(zn)
		# Вода только под льдом (с запасом от краёв) — у входа на лёд нет провала
		var water := _band(z, 912.0, 93.0, 1.0)
		if zn < 520.0:
			water *= smoothstep(IceRiver.CANYON_N, IceRiver.CANYON_N - 6.0, zn)   # у каньона — берег
		var inside := 1.0 - smoothstep(RIVER_HALF - 1.0, RIVER_HALF + 1.0, ax)
		var bed := ry - (IceRiver.WATER_GAP + IceRiver.lake_depth(x, zn)) * water
		var shore := ry + clampf((ax - RIVER_HALF) * 0.35, 0.0, 6.0)
		h = lerpf(h, lerpf(shore, bed, inside), wr)

	# Лавинный склон — гора к западу от тропы
	var wb := _band(z, 72.0, 8.0, 10.0)
	if x < -8.0:
		h += wb * minf((-8.0 - x) * 0.55, 36.0)

	# Трещины: ровная площадка и две пропасти
	var wc := _band(z, -2.0, -40.0, 6.0) * (1.0 - smoothstep(55.0, 65.0, ax))
	h = lerpf(h, 0.0, wc)
	for item in CREVASSES:
		var c: Vector2 = item
		var k := 1.0 - smoothstep(c.y - 0.6, c.y + 0.6, absf(z - c.x))
		k *= 1.0 - smoothstep(76.0, 78.0, ax)
		h = lerpf(h, CREVASSE_DEPTH, k)

	# Плато бурь: возвышенность с обрывами по бокам
	var wd := _band(z, -52.0, -96.0, 10.0)
	var plateau := lerpf(6.0, -18.0, smoothstep(15.0, 18.5, ax))
	h = lerpf(h, plateau, wd)

	# Каньон: ровное дно и отвесные стены
	var we := _band(z, -112.0, -150.0, 4.0)
	h = lerpf(h, 0.0, we * (1.0 - smoothstep(12.0, 14.0, ax)))
	h += we * clampf((ax - 14.0) * 3.0, 0.0, 40.0)

	# Озеро: ровный берег и котловина под льдом
	var lx := (x - LAKE_CENTER.x) / LAKE_RADIUS.x
	var lz := (z - LAKE_CENTER.y) / LAKE_RADIUS.y
	var d := sqrt(lx * lx + lz * lz)
	h = lerpf(h, 0.0, 1.0 - smoothstep(1.0, 1.4, d))
	h = lerpf(h, -6.0, 1.0 - smoothstep(0.98, 1.08, d))

	# База: пологие холмы луга, ровная площадка у корабля и борозда от падения
	var wbase := smoothstep(BASE_START_Z, BASE_START_Z + 60.0, z)
	if wbase > 0.0:
		h += _big_noise.get_noise_2d(x * 1.7 + 40.0, z * 1.7) * 2.6 * wbase * smoothstep(6.0, 26.0, ax)
		var to_nose := Vector2(x, z).distance_to(CRASH_NOSE)
		h = lerpf(h, 0.25, (1.0 - smoothstep(16.0, 30.0, to_nose)) * wbase)
		h += _furrow(x, z) * wbase

	# Горы по краям мира (слишком крутые, чтобы забраться)
	var edge_start := lerpf(70.0, RIVER_HALF + 12.0, _band(z, 920.0, 84.0, 8.0))
	var edge := clampf((ax - edge_start) * 1.5, 0.0, 45.0)
	edge += clampf((z - 1205.0) * 1.5, 0.0, 45.0)
	edge += clampf((OLD_NORTH_EDGE + 7.0 - z) * 1.5, 0.0, 45.0)
	h += edge + edge * 0.15 * _big_noise.get_noise_2d(z * 2.0, x * 2.0)
	return h


## Борозда, которую корабль пропахал при падении: канава с валами земли по бокам,
## у носа — вывороченный холм грунта.
func _furrow(x: float, z: float) -> float:
	var a := CRASH_NOSE
	var b := CRASH_TAIL
	var ab := b - a
	var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var d := Vector2(x, z).distance_to(a + ab * t)
	var depth := lerpf(1.5, 0.3, t) * (1.0 - smoothstep(2.5, 4.5, d))
	var berm := lerpf(0.9, 0.2, t) * smoothstep(3.5, 5.0, d) * (1.0 - smoothstep(5.5, 8.5, d))
	var fade := smoothstep(1.0, 0.85, t)   # к дальнему концу борозда сходит на нет
	# вал грунта перед носом
	var front := Vector2(x, z).distance_to(a - ab.normalized() * 5.0)
	var mound := 0.7 * (1.0 - smoothstep(1.5, 5.0, front))
	return (berm - depth) * fade + mound


## 1 внутри диапазона z_lo…z_hi, плавно спадает до 0 за его краями.
func _band(z: float, z_hi: float, z_lo: float, edge: float) -> float:
	return smoothstep(z_lo - edge, z_lo, z) * (1.0 - smoothstep(z_hi, z_hi + edge, z))


func _build() -> void:
	var nx := int(size_x / cell) + 1
	var nz := int(size_z / cell) + 1
	var x0 := -size_x * 0.5
	var z0 := north_edge_z + size_z   # южный край

	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		var z := z0 - iz * cell
		for ix in nx:
			heights[iz * nx + ix] = height_at(x0 + ix * cell, z)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var i := iz * nx + ix
			verts[i] = Vector3(x0 + ix * cell, heights[i], z0 - iz * cell)
			var hl := heights[iz * nx + maxi(ix - 1, 0)]
			var hr := heights[iz * nx + mini(ix + 1, nx - 1)]
			var hs := heights[maxi(iz - 1, 0) * nx + ix]        # южнее (z больше)
			var hn := heights[mini(iz + 1, nz - 1) * nx + ix]   # севернее (z меньше)
			normals[i] = Vector3(-(hr - hl) / (2.0 * cell), 1.0, -(hs - hn) / (2.0 * cell)).normalized()

	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			indices[k] = a
			indices[k + 1] = c
			indices[k + 2] = b
			indices[k + 3] = b
			indices[k + 4] = c
			indices[k + 5] = d
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if terrain_material:
		mesh.surface_set_material(0, terrain_material)

	# видимая часть — кусками (что за камерой, не рисуется), вдали — вдвое реже сетка
	_build_chunks(verts, normals, nx, nz)

	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	for sgn in [-1.0, 1.0]:
		_build_wing(sgn, WING_Z, WING_OUT)
		_build_wing(sgn, WASTE_WING_Z, WASTE_WING_OUT)
		_build_wing(sgn, PEAK_WING_Z, PEAK_WING_OUT)


## «Крыло» рельефа сбоку от основной сетки — там, где Ледяное поле шире её (сетка реже)
func _build_wing(sgn: float, wz: Vector2, w_out: float) -> void:
	var xa := size_x * 0.5
	var nx := int((w_out - xa) / WING_CELL) + 1
	var nz := int((wz.y - wz.x) / WING_CELL) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	for iz in nz:
		var z := wz.y - iz * WING_CELL
		for ix in nx:
			var x := sgn * (xa + ix * WING_CELL)
			var h := height_at(x, z)
			verts[iz * nx + ix] = Vector3(x, h, z)
			var hx := height_at(x + 0.75, z) - height_at(x - 0.75, z)
			var hz := height_at(x, z + 0.75) - height_at(x, z - 0.75)
			normals[iz * nx + ix] = Vector3(-hx / 1.5, 1.0, -hz / 1.5).normalized()
	var idx := PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			if sgn > 0.0:
				idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
			else:
				idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if terrain_material:
		mesh.surface_set_material(0, terrain_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Wing%s%d" % ["E" if sgn > 0.0 else "W", int(wz.x)]
	add_child(mi)
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


## Куски рельефа по CHUNK клеток: рядом — полная сетка, дальше FAR_FROM м — каждая вторая вершина.
## Точка куска — в его середине (по ней считается дальность).
const CHUNK := 64                ## шаг 74: было 40 — меньше кусков (вызовов отрисовки)
const NORTH_WALL := 7.0           ## шаг 70: ширина обрыва каньона к пустоши
const GATE_FRONT := -650.3        ## шаг 70: тут кончается дорога LX (у ворот), дальше — снег
const FAR_FROM := 120.0
const LOD_STEPS := [1, 2, 4, 8]
const LOD_DIST := [140.0, 420.0, 1000.0]

func _build_chunks(verts: PackedVector3Array, normals: PackedVector3Array, nx: int, nz: int) -> void:
	var cz := 0
	while cz < nz - 1:
		var ez := mini(cz + CHUNK, nz - 1)
		var cx := 0
		while cx < nx - 1:
			var ex := mini(cx + CHUNK, nx - 1)
			var center := (verts[cz * nx + cx] + verts[ez * nx + ex]) * 0.5
			# шаг 75: точка куска — на средней высоте, а к дальностям — пол-перепада высот куска:
			# иначе у высоких кусков (обрывы горы) рядом с игроком включалась грубая сетка, и камера
			# у скалы оказывалась «внутри» неё — гора просвечивала насквозь
			var lo := INF
			var hi := -INF
			var zz := cz
			while zz <= ez:
				var xx := cx
				while xx <= ex:
					var hy := verts[zz * nx + xx].y
					lo = minf(lo, hy)
					hi = maxf(hi, hy)
					xx += 4
				zz += 4
			center.y = (lo + hi) * 0.5
			var bonus := (hi - lo) * 0.5
			# шаг 74: 4 уровня детализации (вдали — реже сетка), у дальних — «юбка» вниз (без щелей на стыках)
			for li in LOD_STEPS.size():
				var step: int = LOD_STEPS[li]
				var m := _chunk_mesh(verts, normals, nx, cx, cz, ex, ez, step, center)
				var mi := MeshInstance3D.new()
				mi.mesh = m
				mi.position = center
				if li > 0:
					mi.visibility_range_begin = float(LOD_DIST[li - 1]) + bonus
					mi.visibility_range_begin_margin = 6.0
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if li < LOD_STEPS.size() - 1:
					mi.visibility_range_end = float(LOD_DIST[li]) + bonus
					mi.visibility_range_end_margin = 6.0
				add_child(mi)
			cx = ex
		cz = ez


func _chunk_mesh(verts: PackedVector3Array, normals: PackedVector3Array, nx: int, cx: int, cz: int,
		ex: int, ez: int, step: int, center: Vector3) -> ArrayMesh:
	var xs: Array[int] = []
	var x := cx
	while x < ex:
		xs.append(x)
		x += step
	xs.append(ex)
	var zs: Array[int] = []
	var z := cz
	while z < ez:
		zs.append(z)
		z += step
	zs.append(ez)
	var w := xs.size()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	v.resize(w * zs.size())
	n.resize(w * zs.size())
	for j in zs.size():
		for i in w:
			var src: int = zs[j] * nx + xs[i]
			v[j * w + i] = verts[src] - center
			n[j * w + i] = normals[src]
	var idx := PackedInt32Array()
	for j in zs.size() - 1:
		for i in w - 1:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
	if step > 1:
		# юбка: по краю куска — полоса вниз (закрывает щели к соседу с другой детализацией)
		var depth := 1.5 * step
		var hgt := zs.size()
		var rings: Array = []
		var top: Array[int] = []
		var bot: Array[int] = []
		for i in w:
			top.append(i)
			bot.append((hgt - 1) * w + i)
		var lef: Array[int] = []
		var rig: Array[int] = []
		for j in hgt:
			lef.append(j * w)
			rig.append(j * w + w - 1)
		rings.append(top)
		rings.append(bot)
		rings.append(lef)
		rings.append(rig)
		for edge in rings:
			var e: Array = edge
			var base := v.size()
			# шаг 138: на крутых склонах грубая сетка расходится с соседней на десятки метров — короткая юбка
			# не закрывала щель, и издали в горах «светилось» небо сквозь склон. Юбка — по крутизне края
			var st := 0.0
			for k3 in e.size() - 1:
				var a3 := v[int(e[k3])]
				var b3 := v[int(e[k3 + 1])]
				st = maxf(st, absf(a3.y - b3.y) / maxf(Vector2(a3.x - b3.x, a3.z - b3.z).length(), 0.1))
			depth = 1.5 * step * (1.0 + 3.0 * minf(st, 4.0))
			for k2 in e.size():
				v.append(v[int(e[k2])] + Vector3.DOWN * depth)
				n.append(n[int(e[k2])])
			for k2 in e.size() - 1:
				var p0 := int(e[k2])
				var p1 := int(e[k2 + 1])
				var q0 := base + k2
				var q1 := base + k2 + 1
				idx.append_array(PackedInt32Array([p0, p1, q1, p0, q1, q0, p0, q1, p1, p0, q0, q1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if terrain_material:
		m.surface_set_material(0, terrain_material)
	return m
