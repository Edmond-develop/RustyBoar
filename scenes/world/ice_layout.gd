class_name IceLayout
extends Node3D
## Расставляет препятствия по замёрзшему озеру — поперёк всей ширины,
## по нарастающей сложности (с юга на север):
##
##   312…288  Каток — только снежные заплатки
##   288…246  Торосы: две гряды через всё озеро, мелкие полыньи, первый спуск
##   244…206  Полыньи: тонкий лёд, перешейки с ловушками, разводье с льдинами, россыпь полыней
##   204…172  Ледяные холмы: с вершин по физике скатываются глыбы; второй спуск
##   156…124  Гейзеры и ветер: ряды гейзеров, полыньи, порывы ветра
##   126…92   Последний рубеж: гряда, трамплины, разводье, перешейки с гейзерами
##
## Всё зависит только от «зерна», поэтому одинаково у всех игроков.

const RIDGE := preload("res://scenes/world/ice_ridge.gd")
const SNOW := preload("res://scenes/world/snow_patch.gd")
const SPIKES := preload("res://scenes/world/ice_spikes.gd")
const TRAP := preload("res://scenes/world/spike_trap.gd")
const FLOE := preload("res://scenes/world/floe.gd")
const MOUND := preload("res://scenes/world/ice_mound.gd")
const BOULDERS := preload("res://scenes/world/boulder_spawner.gd")
const GEYSER := preload("res://scenes/world/geyser.gd")
const WIND := preload("res://scenes/world/wind_band.gd")
const RAMP := preload("res://scenes/world/jump_ramp.gd")
const THIN_ICE := preload("res://scenes/world/frozen_lake.gd")
const SLUSH := preload("res://scenes/world/slush.gd")

var river: IceRiver
var rng: RandomNumberGenerator
var _count := 0


func build(lake: IceRiver, random: RandomNumberGenerator) -> void:
	river = lake
	rng = random
	var w := river.half_width

	# ---------------- Каток ----------------
	_scatter_snow(288.0, 310.0, 14)

	# ---------------- Торосы ----------------
	_ridge(282.0, 0.7, 18.0, 26.0, 3.5)
	_ridge(270.0, 1.0, 22.0, 30.0, 3.0)
	_ridge(249.0, 0.8, 25.0, 35.0, 4.0)      # внизу первого спуска — тормози заранее!
	_scatter_snow(250.0, 286.0, 10)
	_scatter(SPIKES, 255.0, 286.0, 18, 2.5)

	# ---------------- Полыньи ----------------
	for p in river.thin_patches:
		var thin := _add(THIN_ICE, "ThinIce", Vector3(p.x, IceRiver.river_y(p.y) + 0.02, p.y))
		thin.radius_x = p.z
		thin.radius_z = p.z
		thin.thick_ring = 2.0          # весь лёд тонкий
		thin.thin_rate = 0.55
	for i in river.band_isthmuses.size():
		if i % 2 == 0:
			var trap := _add(TRAP, "Trap", Vector3(river.band_isthmuses[i], IceRiver.river_y(235.0), 235.0))
			trap.phase = rng.randf()
	# Разводье: два ряда льдин, каждая плавает в своём отрезке
	for lane_z in [223.2, 218.8]:
		var x := -w + 4.0
		while x < w - 4.0:
			var seg := rng.randf_range(13.0, 17.0)
			var floe := _add(FLOE, "Floe", Vector3(x, IceRiver.river_y(lane_z), lane_z))
			floe.from_x = x
			floe.to_x = minf(x + seg - 3.5, w - 2.0)
			floe.period = rng.randf_range(6.0, 9.0)
			floe.phase = rng.randf()
			floe.seed_value = _count
			x += seg
	_slush(216.0, 226.0, 90)
	_scatter_snow(204.0, 215.0, 8)

	# ---------------- Ледяные холмы и глыбы ----------------
	var row_z := [196.0, 183.0]
	for row_i in 2:
		var x := -w + 18.0 + (22.0 if row_i == 1 else 0.0)
		while x < w - 10.0:
			var z: float = row_z[row_i] + rng.randf_range(-2.0, 2.0)
			var mound := _add(MOUND, "Mound", Vector3(x, IceRiver.river_y(z), z))
			mound.cap_height = rng.randf_range(4.5, 6.0)
			mound.footprint = rng.randf_range(11.0, 13.0)
			var spawner := _add(BOULDERS, "Boulders", Vector3(x, IceRiver.river_y(z) + mound.cap_height + 1.5, z))
			spawner.seed_value = _count
			x += 44.0
	_scatter(SPIKES, 174.0, 204.0, 12, 4.0)

	# ---------------- Гейзеры и ветер ----------------
	for gz in [152.0, 144.0, 136.0, 128.0]:
		var x := -w + rng.randf_range(3.0, 10.0)
		while x < w - 3.0:
			var pos := Vector3(x + rng.randf_range(-2.0, 2.0), 0.0, gz + rng.randf_range(-2.0, 2.0))
			if not river.is_hole(pos.x, pos.z, 2.0):
				pos.y = IceRiver.river_y(pos.z)
				var g := _add(GEYSER, "Geyser", pos)
				g.phase = rng.randf()
				g.period = rng.randf_range(4.5, 7.0)
			x += rng.randf_range(10.0, 15.0)
	var wind := _add(WIND, "Wind", Vector3(0, IceRiver.river_y(140.0), 140.0))
	wind.z_max = 157.0
	wind.z_min = 122.0
	wind.half_width = w

	# ---------------- Последний рубеж ----------------
	# Трамплины через каждые ~20 м и проходы в гряде точно напротив них
	var ramp_xs: Array[float] = []
	var rx := -w + 10.0
	while rx < w - 8.0:
		ramp_xs.append(rx)
		rx += 20.0
	var gaps := PackedVector2Array()
	for x in ramp_xs:
		gaps.append(Vector2(x - 2.5, x + 2.5))
	var ridge := _add(RIDGE, "Ridge", Vector3(0, IceRiver.river_y(125.0), 125.0))
	ridge.height = 0.9
	ridge.gaps = gaps
	ridge.seed_value = 999
	ridge.half_width = w
	for x in ramp_xs:
		_add(RAMP, "Ramp", Vector3(x, IceRiver.river_y(117.0), 117.0))
	for i in ramp_xs.size() - 1:
		if i % 3 == 1:
			var trap := _add(TRAP, "Trap", Vector3((ramp_xs[i] + ramp_xs[i + 1]) * 0.5, IceRiver.river_y(121.0), 121.0))
			trap.phase = rng.randf()
	# Одна полоса льдин в финальном разводье
	var fx := -w + 4.0
	while fx < w - 4.0:
		var seg := rng.randf_range(18.0, 24.0)
		var floe := _add(FLOE, "Floe", Vector3(fx, IceRiver.river_y(110.0), 110.0))
		floe.from_x = fx
		floe.to_x = minf(fx + seg - 3.5, w - 2.0)
		floe.period = rng.randf_range(7.0, 10.0)
		floe.phase = rng.randf()
		floe.seed_value = _count
		fx += seg
	_slush(107.0, 113.0, 60)
	_scatter_snow(100.0, 106.0, 14)
	# Перешейки: на каждом втором — гейзер, на остальных — шипы
	for i in river.final_isthmuses.size():
		var ix: float = river.final_isthmuses[i]
		if i % 2 == 0:
			var g := _add(GEYSER, "Geyser", Vector3(ix, IceRiver.river_y(96.0), 96.0))
			g.phase = rng.randf()
		else:
			var s := _add(SPIKES, "Spikes", Vector3(ix + rng.randf_range(-0.8, 0.8), IceRiver.river_y(96.0), 96.0 + rng.randf_range(-1.5, 1.5)))
			s.spike_count = 4
			s.max_height = 1.6

	_flush()


# ---------------------------------------------------------------------------

func _add(scr: Script, prefix: String, pos: Vector3) -> Node3D:
	_count += 1
	var node: Node3D
	match scr:
		RIDGE, SNOW, SPIKES, MOUND, RAMP:
			node = StaticBody3D.new()
		FLOE:
			node = AnimatableBody3D.new()
		_:
			node = Node3D.new()
	node.set_script(scr)
	node.name = "%s_%d" % [prefix, _count]
	node.position = pos
	# В сцену узел добавляется позже (в _flush), чтобы вызывающий код успел
	# задать ему свойства — их читает _ready при добавлении.
	_pending.append(node)
	return node


var _pending: Array[Node3D] = []


func _ridge(z: float, height: float, gap_min: float, gap_max: float, gap_width: float) -> void:
	var gaps := PackedVector2Array()
	var x := -river.half_width + rng.randf_range(4.0, gap_max)
	while x < river.half_width - 3.0:
		gaps.append(Vector2(x - gap_width * 0.5, x + gap_width * 0.5))
		x += rng.randf_range(gap_min, gap_max)
	var ridge := _add(RIDGE, "Ridge", Vector3(0, IceRiver.river_y(z), z))
	ridge.height = height
	ridge.gaps = gaps
	ridge.seed_value = int(z * 13.0)
	ridge.half_width = river.half_width


func _scatter(scr: Script, z_min: float, z_max: float, count: int, clearance: float) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 10:
		tries += 1
		var x := rng.randf_range(-river.half_width + 3.0, river.half_width - 3.0)
		var z := rng.randf_range(z_min, z_max)
		if river.is_hole(x, z, clearance):
			continue
		var n := _add(scr, "Spikes", Vector3(x, IceRiver.river_y(z), z))
		n.spike_count = rng.randi_range(4, 7)
		n.max_height = rng.randf_range(1.3, 2.3)
		placed += 1


func _scatter_snow(z_min: float, z_max: float, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 10:
		tries += 1
		var x := rng.randf_range(-river.half_width + 3.0, river.half_width - 3.0)
		var z := rng.randf_range(z_min, z_max)
		if river.is_hole(x, z, 3.0):
			continue
		var s := _add(SNOW, "Snow", Vector3(x, IceRiver.river_y(z), z))
		s.blobs = rng.randi_range(3, 6)
		s.size = rng.randf_range(1.6, 3.2)
		s.seed_value = _count
		placed += 1


func _slush(z_min: float, z_max: float, count: int) -> void:
	var s := _add(SLUSH, "Slush", Vector3(0, IceRiver.river_y((z_min + z_max) * 0.5) - river.water_depth, 0))
	s.z_min = z_min
	s.z_max = z_max
	s.count = count
	s.half_width = river.half_width
	s.seed_value = int(z_min)


## Добавляет все созданные узлы в сцену.
func _flush() -> void:
	for n in _pending:
		add_child(n)
	_pending.clear()
