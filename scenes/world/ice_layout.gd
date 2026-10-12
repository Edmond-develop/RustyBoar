class_name IceLayout
extends Node3D
## Расставляет препятствия по замёрзшему озеру (~450 × 830 м) — поперёк всей
## ширины, по нарастающей сложности, со спокойными полосами между участками:
##
##   912…768  Каток (толстый лёд): большая горка с жёлобом, хоккей дронов (rink.gd)
##   762…525  Ледяной лабиринт: стены из глыб 6–8 м, скользкие участки, арки с сосульками,
##            метель, находки в тупиках; в конце — Ледяной вал с квестом «Зеркала и луч»
##            (toros_field.gd, coop_gate.gd)
##   520…386  Разломы: редкие полыньи, низкая гряда торосов внизу первого спуска
##   378…344  Вмёрзший корабль: обломки, контейнеры, столбы, снежные вихри
##   334…286  Полыньи: тонкий лёд, перешейки, разводье с льдинами, россыпь полыней
##   278…256  Хрустальный лес: рушащиеся кристаллы и чёрный лёд с бегущей трещиной
##   252…238  Второй спуск
##   232…198  Ледяные холмы: глыбы сходят волнами
##   188…144  Гейзеры, ветер и вихри
##   132…92   Последний рубеж: гряда, трамплины, разводье, перешейки
##
## Всё зависит только от «зерна» — одинаково у всех игроков.

const RIDGE := preload("res://scenes/world/ice_ridge.gd")
const SNOW := preload("res://scenes/world/snow_patch.gd")
const SPIKES := preload("res://scenes/world/ice_spikes.gd")
const TRAP := preload("res://scenes/world/spike_trap.gd")
const FLOE := preload("res://scenes/world/floe.gd")
const MOUND := preload("res://scenes/world/ice_mound.gd")
const BOULDERS := preload("res://scenes/world/boulder_spawner.gd")
const ALARM := preload("res://scenes/world/boulder_alarm.gd")
const GEYSER := preload("res://scenes/world/geyser.gd")
const WIND := preload("res://scenes/world/wind_band.gd")
const RAMP := preload("res://scenes/world/jump_ramp.gd")
const THIN_ICE := preload("res://scenes/world/frozen_lake.gd")
const SLUSH := preload("res://scenes/world/slush.gd")
const VORTEX := preload("res://scenes/world/vortex.gd")
const CRACKS := preload("res://scenes/world/crack_zone.gd")
const PILLAR := preload("res://scenes/world/crystal_pillar.gd")
const WRECK := preload("res://scenes/world/wreck.gd")
const DEBRIS := preload("res://scenes/world/debris.gd")
const TOROS := preload("res://scenes/world/toros_field.gd")
const HUMMOCKS := preload("res://scenes/world/hummock_builder.gd")
const RINK := preload("res://scenes/world/rink.gd")

var river: IceRiver
var rng: RandomNumberGenerator
var _count := 0
var _pending: Array[Node3D] = []


func build(lake: IceRiver, random: RandomNumberGenerator) -> void:
	river = lake
	rng = random
	var w := river.half_width

	# ---------------- Каток ----------------
	var rink := Node3D.new()
	rink.set_script(RINK)
	rink.name = "Rink"
	_pending.append(rink)
	# у края катка — сугробы и обломки, середина чистая
	_scatter_snow(766.0, 776.0, 14)
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var d := _add(DEBRIS, "Debris", Vector3(side * rng.randf_range(206.0, 219.0), 0.0, rng.randf_range(780.0, 905.0)))
		d.kind = rng.randi_range(0, 3)
		d.seed_value = _count

	# ---------------- Ледяной лабиринт ----------------
	var toros := Node3D.new()
	toros.set_script(TOROS)
	toros.name = "Toros"
	toros.set("half_width", w)
	_pending.append(toros)

	# ---------------- Разломы ----------------
	_scatter_snow(392.0, 515.0, 26)
	_scatter_spikes(400.0, 512.0, 20, 3.0)
	_hummock_row(386.0, 1.1, 24.0, 34.0, 4.5)   # внизу первого спуска — тормози заранее!

	# ---------------- Вмёрзший корабль ----------------
	var wreck_x := rng.randf_range(-20.0, 20.0)
	var wreck := _add(WRECK, "Wreck", Vector3(wreck_x, IceRiver.river_y(361.0), 361.0))
	wreck.seed_value = 4242
	# Обломки и грузы по всей ширине
	var dx := -w + 6.0
	while dx < w - 6.0:
		if absf(dx - wreck_x) > 26.0:
			var d := _add(DEBRIS, "Debris", Vector3(dx, IceRiver.river_y(361.0), rng.randf_range(348.0, 374.0)))
			d.kind = rng.randi_range(0, 3)
			d.seed_value = _count
		dx += rng.randf_range(7.0, 12.0)
	for i in 2:
		var v := _add(VORTEX, "Vortex", Vector3(-60.0 + i * 120.0, IceRiver.river_y(361.0), 361.0))
		v.range_x = 70.0
		v.range_z = 9.0
		v.phase = i * 0.5

	# ---------------- Полыньи ----------------
	for p in river.thin_patches:
		var thin := _add(THIN_ICE, "ThinIce", Vector3(p.x, IceRiver.river_y(p.y) + 0.02, p.y))
		thin.radius_x = p.z
		thin.radius_z = p.z
		thin.thick_ring = 2.0
		thin.thin_rate = 0.55
	for i in river.band_isthmuses.size():
		if i % 2 == 0:
			var trap := _add(TRAP, "Trap", Vector3(river.band_isthmuses[i], IceRiver.river_y(319.0), 319.0))
			trap.phase = rng.randf()
	for lane_z in [303.2, 298.8]:
		_floe_lane(lane_z, 13.0, 18.0, 6.0, 9.0)
	_slush(296.0, 306.0, 90)
	_scatter_snow(308.0, 314.0, 10)

	# ---------------- Хрустальный лес и чёрный лёд ----------------
	var seg_x := -w
	var crack_turn := rng.randf() < 0.5
	while seg_x < w - 10.0:
		var seg_w := rng.randf_range(22.0, 30.0)
		if crack_turn:
			var cz := _add(CRACKS, "BlackIce", Vector3(seg_x + seg_w * 0.5, IceRiver.river_y(267.0), 267.0))
			cz.half_x = seg_w * 0.5 - 1.0
			cz.half_z = 6.0
		else:
			for i in rng.randi_range(2, 4):
				var pp := Vector3(seg_x + rng.randf_range(3.0, seg_w - 3.0), 0.0, rng.randf_range(260.0, 275.0))
				pp.y = IceRiver.river_y(pp.z)
				var pillar := _add(PILLAR, "Crystal", pp)
				pillar.height = rng.randf_range(5.5, 9.0)
				pillar.radius = rng.randf_range(0.55, 0.9)
				pillar.seed_value = _count
		crack_turn = not crack_turn
		seg_x += seg_w

	# ---------------- Ледяные холмы и волны глыб ----------------
	var row_z := [226.0, 206.0]
	for row_i in 2:
		var x := -w + 20.0 + (24.0 if row_i == 1 else 0.0)
		while x < w - 12.0:
			var z: float = row_z[row_i] + rng.randf_range(-2.0, 2.0)
			var mound := _add(MOUND, "Mound", Vector3(x, IceRiver.river_y(z), z))
			mound.cap_height = rng.randf_range(4.5, 6.0)
			mound.footprint = rng.randf_range(11.0, 13.0)
			var spawner := _add(BOULDERS, "Boulders", Vector3(x, IceRiver.river_y(z) + mound.cap_height + 1.5, z))
			spawner.seed_value = _count
			spawner.per_wave = 5 if row_i == 0 else 4
			x += 38.0
	var alarm := _add(ALARM, "BoulderAlarm", Vector3(0, 0, 215.0))
	alarm.z_max = 236.0
	alarm.z_min = 194.0
	_scatter_spikes(196.0, 234.0, 8, 5.0)

	# ---------------- Гейзеры, ветер и вихри ----------------
	for gz in [184.0, 168.0, 152.0]:
		var x := -w + rng.randf_range(4.0, 12.0)
		while x < w - 4.0:
			var pos := Vector3(x + rng.randf_range(-3.0, 3.0), 0.0, gz + rng.randf_range(-2.5, 2.5))
			if not river.is_hole(pos.x, pos.z, 2.0):
				pos.y = IceRiver.river_y(pos.z)
				var g := _add(GEYSER, "Geyser", pos)
				g.phase = rng.randf()
				g.period = rng.randf_range(4.5, 7.0)
			x += rng.randf_range(16.0, 22.0)
	var wind := _add(WIND, "Wind", Vector3(0, IceRiver.river_y(166.0), 166.0))
	wind.z_max = 190.0
	wind.z_min = 142.0
	wind.half_width = w
	for i in 3:
		var v := _add(VORTEX, "Vortex", Vector3(-90.0 + i * 90.0, IceRiver.river_y(166.0), 166.0))
		v.range_x = 45.0
		v.range_z = 16.0
		v.speed = 0.05
		v.phase = i * 0.33
	_scatter_snow(136.0, 142.0, 10)

	# ---------------- Последний рубеж ----------------
	var ramp_xs: Array[float] = []
	var rx := -w + 10.0
	while rx < w - 8.0:
		ramp_xs.append(rx)
		rx += 22.0
	var gaps := PackedVector2Array()
	for x in ramp_xs:
		gaps.append(Vector2(x - 2.5, x + 2.5))
	var ridge := _add(RIDGE, "Ridge", Vector3(0, IceRiver.river_y(131.0), 131.0))
	ridge.height = 0.9
	ridge.gaps = gaps
	ridge.seed_value = 999
	ridge.half_width = w
	ridge.style = 1
	for x in ramp_xs:
		_add(RAMP, "Ramp", Vector3(x, IceRiver.river_y(123.0), 123.0))
	for i in ramp_xs.size() - 1:
		if i % 3 == 1:
			var trap := _add(TRAP, "Trap", Vector3((ramp_xs[i] + ramp_xs[i + 1]) * 0.5, IceRiver.river_y(127.0), 127.0))
			trap.phase = rng.randf()
	_floe_lane(116.0, 18.0, 24.0, 7.0, 10.0)
	_slush(113.0, 119.0, 60)
	_scatter_snow(103.0, 111.0, 16)
	for i in river.final_isthmuses.size():
		var ix: float = river.final_isthmuses[i]
		if i % 2 == 0:
			var g := _add(GEYSER, "Geyser", Vector3(ix, IceRiver.river_y(98.0), 98.0))
			g.phase = rng.randf()
		else:
			var s := _add(SPIKES, "Spikes", Vector3(ix + rng.randf_range(-0.8, 0.8), IceRiver.river_y(98.0), 98.0 + rng.randf_range(-1.5, 1.5)))
			s.spike_count = 4
			s.max_height = 1.6

	_flush()


# ---------------------------------------------------------------------------

func _add(scr: Script, prefix: String, pos: Vector3) -> Node3D:
	_count += 1
	var node: Node3D
	match scr:
		RIDGE, SNOW, SPIKES, MOUND, RAMP, WRECK, DEBRIS:
			node = StaticBody3D.new()
		FLOE:
			node = AnimatableBody3D.new()
		_:
			node = Node3D.new()
	node.set_script(scr)
	node.name = "%s_%d" % [prefix, _count]
	node.position = pos
	# В сцену узел добавится в _flush(), чтобы вызывающий код успел задать свойства
	_pending.append(node)
	return node


func _free_spot(z_min: float, z_max: float, clearance: float) -> Vector3:
	for i in 30:
		var x := rng.randf_range(-river.half_width + 5.0, river.half_width - 5.0)
		var z := rng.randf_range(z_min, z_max)
		if not river.is_hole(x, z, clearance):
			return Vector3(x, IceRiver.river_y(z), z)
	return Vector3(0, IceRiver.river_y(z_min), z_min)


func _ridge(z: float, height: float, gap_min: float, gap_max: float, gap_width: float, style: int) -> void:
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
	ridge.style = style


## Низкая гряда торосов поперёк озера с проходами (можно и перепрыгнуть с разбега)
func _hummock_row(z: float, height: float, gap_min: float, gap_max: float, gap_width: float) -> void:
	var b = HUMMOCKS.new(int(z * 17.0))
	b.ground_y = IceRiver.river_y(z) + 0.02
	var w := river.half_width
	var x := -w
	while x < w:
		var next := minf(x + rng.randf_range(gap_min, gap_max), w)
		b.palette = rng.randi() % HUMMOCKS.PALETTES.size()
		b.form = rng.randi() % HUMMOCKS.FORMS
		b.wall(Vector2(x, z), Vector2(next - gap_width, z), height, 2.0)
		x = next
	var holder := Node3D.new()
	holder.name = "HummockRow_%d" % int(z)
	_pending.append(holder)
	b.finish(holder)


func _floe_lane(lane_z: float, seg_min: float, seg_max: float, period_min: float, period_max: float) -> void:
	var w := river.half_width
	var x := -w + 4.0
	while x < w - 4.0:
		var seg := rng.randf_range(seg_min, seg_max)
		var floe := _add(FLOE, "Floe", Vector3(x, IceRiver.river_y(lane_z), lane_z))
		floe.from_x = x
		floe.to_x = minf(x + seg - 3.5, w - 2.0)
		floe.period = rng.randf_range(period_min, period_max)
		floe.phase = rng.randf()
		floe.seed_value = _count
		x += seg


func _scatter_spikes(z_min: float, z_max: float, count: int, clearance: float) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 10:
		tries += 1
		var x := rng.randf_range(-river.half_width + 3.0, river.half_width - 3.0)
		var z := rng.randf_range(z_min, z_max)
		if river.is_hole(x, z, clearance):
			continue
		var n := _add(SPIKES, "Spikes", Vector3(x, IceRiver.river_y(z), z))
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


func _flush() -> void:
	for n in _pending:
		add_child(n)
	_pending.clear()
