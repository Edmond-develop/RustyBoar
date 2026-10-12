extends Node3D
## Ледяной лабиринт на озере (вся ширина, ~200 м в длину) и площадка с Ледяным валом.
##
##  * стены из огромных глыб 6–8 м — выше дрона, не перепрыгнуть и не перелезть;
##    мостов и горок через стены нет — только искать путь;
##  * коридоры узкие (клетка 10 м), путь петляет: лабиринт «идеальный» (из любой
##    клетки в любую — один путь) плюс редкие обходные кольца; много тупиков;
##  * между стенами — плотный снег (держит хорошо, лёд под ним толстый);
##  * скользкие участки: гладкий голый лёд в части клеток — на поворотах заносит;
##  * ледяные арки над коридорами, под ними — сосульки: срываются, когда дрон рядом
##    (особенно если шумит — бег, прыжки);
##  * порывы ветра: между ними штиль; порыв налетает снежной пеленой поперёк
##    коридоров и сносит дрона (у расщелин — прямо в воду);
##  * находки в тупиках: обломки корабля, ящики, жаровни (отогреться);
##  * лабиринт поделён на «районы» ~45×40 м: в каждом свой лёд и своя форма стен
##    (валуны, зубцы, плиты, завалы, монолиты — из 3D-моделей скал);
##  * на севере — площадка перед Ледяным валом: квест «Живые зеркала» (coop_gate.gd).
## Всё строится по зерну — у всех игроков одинаково.

const BUILDER := preload("res://scenes/world/hummock_builder.gd")
const GATE := preload("res://scenes/world/coop_gate.gd")
const ICICLE := preload("res://scenes/world/icicle.gd")
const DEBRIS := preload("res://scenes/world/debris.gd")
const HEATER := preload("res://scenes/world/heat_source.gd")
const SNOW := preload("res://scenes/world/snow_patch.gd")
const BLIZZARD := preload("res://scenes/world/blizzard.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const MAP := preload("res://scenes/world/maze_map.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")

@export var half_width := 225.0
@export var z_south := 762.0      ## Южный край лабиринта (вход)
@export var z_north := 562.0      ## Северный край лабиринта (выход на площадку)
@export var wall_z := 525.0       ## Ледяной вал с воротами
@export var cell := 10.0
@export var seed_value := 7311
@export var slick_chance := 0.1   ## Доля клеток со скользким льдом
@export var arch_chance := 0.07   ## Доля прямых коридоров с аркой и сосульками
@export var crevasse_chance := 0.22   ## Доля коридоров «с юга на север» с расщелиной вдоль стены
@export var crevasse_width := 3.4

const SHIELD_H := 1.1        ## Высота луча над льдом = высота щитов на дронах

var _b
var _rng := RandomNumberGenerator.new()
var _gy := 0.0
var _cols := 0
var _rows := 0
var _x0 := 0.0
var _h := []                 ## стенки поперёк озера: _h[r][c]
var _v := []                 ## стенки вдоль озера: _v[r][c]
var _dead_ends: Array[Vector2i] = []
var crevasse_rects: Array[Vector4] = []   ## расщелины с водой (x_min, x_max, z_min, z_max)
var slick_rects: Array[Vector4] = []      ## скользкий лёд (для карты)
var barrier := Vector4()                  ## барьер на площадке (x_min, x_max, z, -) — для карты
var beam_stop := Vector2()                ## глыба, в которую упирается луч маяка
var _crev_cells := {}


func _ready() -> void:
	_rng.seed = seed_value
	_b = BUILDER.new(seed_value + 1)
	_gy = IceRiver.river_y(z_south) + 0.02
	_b.ground_y = _gy
	_maze()
	_crevasses()
	_snow_floor()
	_slick_patches()
	_arches()
	_finds()
	_plaza()
	_entrance_checkpoint()
	_b.finish(self)
	_blizzard()
	var map := CanvasLayer.new()
	map.set_script(MAP)
	map.set("maze", self)
	map.name = "MazeMap"
	add_child(map)


## Плотный снег между стенами (держит хорошо). Пол собран из полос — в расщелинах его нет.
func _snow_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "SnowFloor"
	body.add_to_group("safe_ground")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	add_child(body)
	var terrain := get_tree().get_first_node_in_group("terrain")
	var mat: Material = terrain.terrain_material if terrain and terrain.terrain_material else null
	# полосы: юг (до входа), каждый ряд лабиринта, север (площадка)
	var bands: Array[Vector2] = [Vector2(z_south, z_south + 4.0), Vector2(wall_z - 3.0, z_north)]
	for r in _rows:
		bands.append(Vector2(z_south - (r + 1) * cell, z_south - r * cell))
	for band in bands:
		# куски по x между расщелинами этого ряда
		var cuts: Array[Vector2] = []
		for cr in crevasse_rects:
			if cr.z < band.y - 0.1 and cr.w > band.x + 0.1:
				cuts.append(Vector2(cr.x, cr.y))
		cuts.sort_custom(func(p, q): return p.x < q.x)
		var x := -half_width
		for cut in cuts + [Vector2(half_width, half_width)]:
			if cut.x - x > 0.05:
				_floor_box(body, mat, Vector3((x + cut.x) * 0.5, _gy, (band.x + band.y) * 0.5), Vector3(cut.x - x, 0.2, band.y - band.x))
			x = cut.y


func _floor_box(body: StaticBody3D, mat: Material, center: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = center + Vector3(0, -0.04, 0)
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.14, size.z)
	if mat:
		bm.material = mat
	mi.mesh = bm
	mi.position = center + Vector3(0, -0.01, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Расщелины: в коридорах «юг—север» вдоль одной из стен — полоса открытой ледяной воды.
## Остаётся узкий карниз; порыв ветра сбоку может сдуть дрона в воду.
func _crevasses() -> void:
	var river := get_tree().get_first_node_in_group("ice_lake")
	var face := (2.2 * 1.55 + 0.35) * 0.5     # где кончается стена (как в hummock_builder.wall)
	var made := 0
	for r in range(2, _rows - 3):
		for c in _cols:
			var ns: bool = _v[r][c] and _v[r][c + 1] and not _h[r][c] and not _h[r + 1][c]
			if not ns or _rng.randf() >= crevasse_chance or made >= 16:
				continue
			# соседние клетки тоже не трогаем — чтобы расщелины не сливались
			if _crev_cells.has(Vector2i(c, r - 1)) or _crev_cells.has(Vector2i(c, r + 1)):
				continue
			made += 1
			_crev_cells[Vector2i(c, r)] = true
			var left := _rng.randf() < 0.5
			var wx := _x0 + c * cell if left else _x0 + (c + 1) * cell
			var x0 := wx + face if left else wx - face - crevasse_width
			var x1 := x0 + crevasse_width
			var z0 := z_south - (r + 1) * cell
			var z1 := z_south - r * cell
			var rect := Vector4(x0, x1, z0, z1)
			crevasse_rects.append(rect)
			if river:
				river.rects.append(rect)
			_crevasse_visual(rect)
	if river and not crevasse_rects.is_empty():
		river._refresh_area(-half_width, half_width, z_north, z_south)


## Стенки расщелины — тёмный лёд от кромки до воды, и снежный бортик по краю
func _crevasse_visual(r: Vector4) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = ICE_SHADER
	mat.set_shader_parameter("deep", Color(0.01, 0.06, 0.16))
	mat.set_shader_parameter("mid", Color(0.05, 0.2, 0.4))
	mat.set_shader_parameter("snow_amount", 0.0)
	mat.set_shader_parameter("band_scale", 6.0)
	var depth := 1.6
	var y := _gy + 0.06 - depth * 0.5
	var parts := [
		[Vector3(r.x - 0.1, y, (r.z + r.w) * 0.5), Vector3(0.2, depth, r.w - r.z)],
		[Vector3(r.y + 0.1, y, (r.z + r.w) * 0.5), Vector3(0.2, depth, r.w - r.z)],
		[Vector3((r.x + r.y) * 0.5, y, r.z - 0.1), Vector3(r.y - r.x + 0.4, depth, 0.2)],
		[Vector3((r.x + r.y) * 0.5, y, r.w + 0.1), Vector3(r.y - r.x + 0.4, depth, 0.2)],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[1]
		bm.material = mat
		mi.mesh = bm
		mi.position = pt[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# предупреждающие вешки по краю
	var flag := StandardMaterial3D.new()
	flag.albedo_color = Color(0.1, 0.5, 1.0)
	flag.emission_enabled = true
	flag.emission = Color(0.1, 0.5, 1.0)
	flag.emission_energy_multiplier = 1.2
	for k in 3:
		var z := lerpf(r.z + 1.5, r.w - 1.5, k / 2.0)
		for ex in [r.x, r.y]:
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.06
			cm.height = 1.2
			cm.material = flag
			post.mesh = cm
			post.position = Vector3(ex, _gy + 0.6, z)
			add_child(post)


# ---------------------------------------------------------------------------
#  Лабиринт
# ---------------------------------------------------------------------------
func _cell_center(c: int, r: int) -> Vector2:
	return Vector2(_x0 + (c + 0.5) * cell, z_south - (r + 0.5) * cell)


func _maze() -> void:
	_cols = int(half_width * 2.0 / cell)
	_rows = int((z_south - z_north) / cell)
	_x0 = -_cols * cell * 0.5
	for r in _rows + 1:
		_h.append([])
		for c in _cols:
			_h[r].append(true)
	for r in _rows:
		_v.append([])
		for c in _cols + 1:
			_v[r].append(true)
	# обход в глубину: чаще идём прямо — получаются длинные извилистые ходы
	var visited := {}
	var start := Vector2i(_cols / 2, 0)
	var stack: Array[Vector2i] = [start]
	var last_dir := {start: Vector2i(0, 1)}
	visited[start] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var opts: Array[Vector2i] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if nb.x >= 0 and nb.x < _cols and nb.y >= 0 and nb.y < _rows and not visited.has(nb):
				opts.append(d)
		if opts.is_empty():
			stack.pop_back()
			continue
		var d: Vector2i = opts[_rng.randi() % opts.size()]
		var ld: Vector2i = last_dir.get(cur, Vector2i.ZERO)
		if opts.has(ld) and _rng.randf() < 0.35:
			d = ld
		var nxt := cur + d
		if nxt.x != cur.x:
			_v[cur.y][maxi(cur.x, nxt.x)] = false
		else:
			_h[maxi(cur.y, nxt.y)][cur.x] = false
		visited[nxt] = true
		last_dir[nxt] = d
		stack.append(nxt)
	# редкие обходные кольца
	for r in range(1, _rows):
		for c in _cols:
			if _h[r][c] and _rng.randf() < 0.04:
				_h[r][c] = false
	for r in _rows:
		for c in range(1, _cols):
			if _v[r][c] and _rng.randf() < 0.04:
				_v[r][c] = false
	# входы с юга и выходы на площадку
	for c in [_cols / 6, _cols / 2, _cols * 5 / 6]:
		_h[0][c] = false
	for c in [_cols / 2 - 6, _cols / 2 + 1, _cols / 2 + 7]:
		_h[_rows][c] = false

	var pin := {}
	for r in _rows + 1:
		for c in _cols:
			if not _h[r][c]:
				continue
			var z := z_south - r * cell
			_wall(Vector2(_x0 + c * cell, z), Vector2(_x0 + (c + 1) * cell, z))
			pin[Vector2i(c, r)] = int(pin.get(Vector2i(c, r), 0)) + 1
			pin[Vector2i(c + 1, r)] = int(pin.get(Vector2i(c + 1, r), 0)) + 1
	for r in _rows:
		for c in _cols + 1:
			if not _v[r][c]:
				continue
			var x := _x0 + c * cell
			_wall(Vector2(x, z_south - r * cell), Vector2(x, z_south - (r + 1) * cell))
			pin[Vector2i(c, r)] = int(pin.get(Vector2i(c, r), 0)) + 1
			pin[Vector2i(c, r + 1)] = int(pin.get(Vector2i(c, r + 1), 0)) + 1
	# высокие скалы там, где сходятся три-четыре стены
	for k in pin:
		if int(pin[k]) >= 3:
			var p := Vector2(_x0 + k.x * cell, z_south - k.y * cell)
			_style_at(p)
			_b.pinnacle(p, _rng.randf_range(7.5, 9.5))
	# тупики (клетки с одним выходом)
	for r in _rows:
		for c in _cols:
			var closed := int(_h[r][c]) + int(_h[r + 1][c]) + int(_v[r][c]) + int(_v[r][c + 1])
			if closed == 3:
				_dead_ends.append(Vector2i(c, r))


## Вид льда и форма стены для точки: по району + иногда случайно
func _style_at(p: Vector2) -> void:
	var key := Vector2i(floori((p.x + 1000.0) / 45.0), floori(p.y / 40.0))
	var hv := absi(hash(key * 7 + Vector2i(seed_value, 0)))
	_b.palette = hv % BUILDER.PALETTES.size()
	_b.form = (hv / 11) % BUILDER.FORMS
	if _rng.randf() < 0.2:
		_b.palette = _rng.randi() % BUILDER.PALETTES.size()
	if _rng.randf() < 0.15:
		_b.form = _rng.randi() % BUILDER.FORMS


func _wall(a: Vector2, b: Vector2) -> void:
	_style_at((a + b) * 0.5)
	var lo: float = [6.0, 6.5, 5.8, 6.0, 6.4][_b.form]
	var hi: float = [7.4, 8.4, 7.0, 7.6, 8.0][_b.form]
	_b.wall(a, b, _rng.randf_range(lo, hi), 2.2)


# ---------------------------------------------------------------------------
#  Скользкий лёд, арки с сосульками, находки, метель
# ---------------------------------------------------------------------------
func _slick_patches() -> void:
	var body := StaticBody3D.new()
	body.name = "SlickIce"
	body.add_to_group("safe_ground")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02
	body.physics_material_override = pm
	add_child(body)
	var mat := ShaderMaterial.new()
	mat.shader = ICE_SHADER
	mat.set_shader_parameter("polish", 1.0)
	mat.set_shader_parameter("deep", Color(0.05, 0.25, 0.5))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	mesh.material = mat
	var xs: Array[Transform3D] = []
	for r in range(1, _rows - 1):
		for c in _cols:
			if _rng.randf() >= slick_chance or _crev_cells.has(Vector2i(c, r)):
				continue
			var p := _cell_center(c, r)
			# скользкая полоса тянется в соседнюю клетку, если там проход
			var size := Vector3(cell - 1.5, 0.1, cell - 1.5)
			var center := Vector3(p.x, _gy + 0.04, p.y)
			if c + 1 < _cols and not _v[r][c + 1] and _rng.randf() < 0.5:
				size.x += cell
				center.x += cell * 0.5
			elif not _h[r + 1][c] and _rng.randf() < 0.5:
				size.z += cell
				center.z -= cell * 0.5
			var col := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = size
			col.shape = sh
			col.position = center
			body.add_child(col)
			xs.append(Transform3D(Basis.from_scale(size), center))
			slick_rects.append(Vector4(center.x - size.x * 0.5, center.x + size.x * 0.5, center.z - size.z * 0.5, center.z + size.z * 0.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Арки из глыб над прямыми коридорами; под аркой висят сосульки
func _arches() -> void:
	var made := 0
	for r in range(1, _rows - 1):
		for c in _cols:
			var ns: bool = _v[r][c] and _v[r][c + 1] and not _h[r][c] and not _h[r + 1][c]
			var ew: bool = _h[r][c] and _h[r + 1][c] and (c == 0 or not _v[r][c]) and (c == _cols - 1 or not _v[r][c + 1])
			if not (ns or ew) or _rng.randf() >= arch_chance or made >= 30 or _crev_cells.has(Vector2i(c, r)):
				continue
			made += 1
			var p := _cell_center(c, r)
			var y := _gy + 6.2
			var yaw := 0.0 if ns else PI * 0.5      # арка лежит поперёк коридора
			_style_at(p)
			_b.rock(_b._pick(_b.SET_FLAT), Vector3(p.x, y, p.y), Vector3(cell + 3.0, 1.6, 2.6), yaw,
				Vector2(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05)))
			var across := Vector3(1, 0, 0) if ns else Vector3(0, 0, 1)
			for k in 3:
				var ic := Node3D.new()
				ic.set_script(ICICLE)
				ic.set("floor_y", _gy)
				ic.set("length", _rng.randf_range(1.2, 2.0))
				ic.position = Vector3(p.x, y + 0.05, p.y) + across * (-2.4 + k * 2.4 + _rng.randf_range(-0.5, 0.5))
				add_child(ic)


## Находки в тупиках: обломки, ящики, жаровни.
func _finds() -> void:
	for de in _dead_ends:
		if de.y == 0:
			continue
		var p := _cell_center(de.x, de.y)
		var pos := Vector3(p.x, _gy, p.y)
		var roll := _rng.randf()
		if roll < 0.35:
			var d := StaticBody3D.new()
			d.set_script(DEBRIS)
			d.set("kind", _rng.randi_range(1, 3))
			d.set("seed_value", de.x * 100 + de.y)
			d.position = pos
			d.rotation.y = _rng.randf() * TAU
			add_child(d)
		elif roll < 0.5:
			var h := Node3D.new()
			h.set_script(HEATER)
			h.position = pos
			add_child(h)
		elif roll < 0.75:
			var s := StaticBody3D.new()
			s.set_script(SNOW)
			s.set("blobs", _rng.randi_range(3, 5))
			s.set("size", _rng.randf_range(1.6, 2.4))
			s.set("seed_value", de.x * 31 + de.y)
			s.position = pos
			add_child(s)


## Контрольная точка у входа в лабиринт: вошёл в лабиринт (с любого входа) —
## сгоревший в луче дрон появится у среднего входа, а не в лагере.
func _entrance_checkpoint() -> void:
	var mid := _cell_center(_cols / 2, 0)
	var cp := Area3D.new()
	cp.set_script(CHECKPOINT)
	cp.name = "MazeCheckpoint"
	cp.set("title", "Контрольная точка")
	cp.set("subtitle", "Сгоревший в луче дрон появится здесь, у входа в лабиринт")
	cp.set("snap_to_terrain", false)
	cp.set("size", Vector3(half_width * 2.0, 10.0, 6.0))
	cp.set("respawn_offset", Vector3(0.0, 0.5, 7.0))     # появиться — снаружи, перед входом
	cp.position = Vector3(mid.x, _gy, z_south - 4.0)      # сработает в первом ряду клеток
	add_child(cp)


func _blizzard() -> void:
	var bz := Node3D.new()
	bz.set_script(BLIZZARD)
	bz.name = "MazeBlizzard"
	bz.set("zone_z_max", z_south)
	bz.set("zone_z_min", wall_z)            # порывы долетают и до площадки у вала
	bz.set("zone_half_width", half_width)
	bz.set("max_fog", 0.035)
	bz.set("calm_between_gusts", true)     # между порывами — штиль
	bz.set("gust_wind", 6.8)               # стоишь — сносит на ~12 м; идёшь против — сносит назад
	bz.set("gust_kick", 5.0)               # в начале порыва — рывок вбок
	bz.set("gust_warning", 1.0)
	bz.set("gust_duration", 2.0)
	bz.set("gust_fade", 1.2)
	bz.set("gust_interval_min", 8.0)
	bz.set("gust_interval_max", 14.0)
	var we := get_tree().current_scene.get_node_or_null("WorldEnvironment") if get_tree().current_scene else null
	if we:
		bz.set("environment_path", we.get_path())
	add_child(bz)


# ---------------------------------------------------------------------------
#  Площадка перед Ледяным валом: маяк, барьер, глыба-упор, вал и ворота с печатью
# ---------------------------------------------------------------------------
func _plaza() -> void:
	var gate_w := 9.0
	var wall_h := 9.0
	_b.palette = 0
	_b.form = 4
	var x := -half_width
	while x < half_width - 0.1:
		var x1 := minf(x + 15.0, half_width)
		if x < gate_w * 0.5 and x1 > -gate_w * 0.5:
			if x < -gate_w * 0.5:
				_b.wall(Vector2(x, wall_z), Vector2(-gate_w * 0.5, wall_z), wall_h, 3.0)
			if x1 > gate_w * 0.5:
				_b.wall(Vector2(gate_w * 0.5, wall_z), Vector2(x1, wall_z), wall_h, 3.0)
		else:
			_b.wall(Vector2(x, wall_z), Vector2(x1, wall_z), wall_h * _rng.randf_range(0.95, 1.12), 3.0)
		x = x1
	_b.palette = 1
	_b.form = 1
	_b.pinnacle(Vector2(-gate_w * 0.5 - 1.6, wall_z), 11.0)
	_b.pinnacle(Vector2(gate_w * 0.5 + 1.6, wall_z), 11.0)

	var w := wall_z
	# Маяк в нише у западного края: бьёт лучом на восток вдоль площадки (на высоте щитов)
	var beacon := Vector3(-48.0, _gy + SHIELD_H, w + 30.0)
	_b.palette = 3
	_b.form = 0
	for k in 6:
		var a := PI * 0.5 + PI * k / 5.0          # полукольцо глыб с запада, открыто на восток
		_b.rock(_b._pick(_b.SET_ROUND), Vector3(beacon.x + cos(a) * 3.2, _gy - 0.2, beacon.z - sin(a) * 3.2),
			Vector3(3.2, 3.4, 2.8), a)
	# Длинный ледяной барьер между лучом и воротами — напрямую в печать не попасть
	_b.palette = 1
	_b.form = 2
	_b.wall(Vector2(-34.0, w + 18.0), Vector2(-2.0, w + 18.0), 3.4, 2.2)
	_b.wall(Vector2(-2.0, w + 18.0), Vector2(30.0, w + 18.0), 3.4, 2.2)
	barrier = Vector4(-34.0, 30.0, w + 18.0, 0.0)
	# Глыба на востоке — дальше луч маяка не идёт
	_b.palette = 3
	_b.form = 4
	_b.rock("space_rock_large_2", Vector3(50.0, _gy - 0.3, w + 30.0), Vector3(6.0, 5.0, 5.0), 0.6)
	_b._box(Vector3(50.0, _gy + 2.2, w + 30.0), Basis.IDENTITY, Vector3(4.6, 4.4, 4.2))
	beam_stop = Vector2(50.0, w + 30.0)

	var gate := Node3D.new()
	gate.set_script(GATE)
	gate.name = "IceGate"
	gate.position = Vector3(0.0, _gy, wall_z)
	gate.set("gate_width", gate_w)
	gate.set("gate_height", wall_h)
	gate.set("beam_y", _gy + SHIELD_H)
	gate.set("beacon_pos", beacon)
	gate.set("beacon_dir", Vector3(1, 0, 0))
	gate.set("zone", Rect2(-half_width, wall_z + 1.5, half_width * 2.0, z_north - wall_z - 1.0))
	gate.set("bot_spot_a", Vector3(40.0, _gy, w + 30.0))
	gate.set("bot_spot_b", Vector3(46.0, _gy, w + 22.0))
	add_child(gate)
