class_name IceLayout
extends Node3D
## Расставляет препятствия по замёрзшему озеру (~450 × 830 м) — поперёк всей
## ширины, по нарастающей сложности, со спокойными полосами между участками:
##
##   912…768  Каток (толстый лёд): большая горка с жёлобом, хоккей дронов (rink.gd)
##   762…525  Ледяной лабиринт: стены из глыб 6–8 м, скользкие участки, арки с сосульками,
##            метель, находки в тупиках; в конце — Ледяной вал с квестом «Зеркала и луч»
##            (toros_field.gd, coop_gate.gd)
##   518…345  Ледяное поле (до 800 м в ширину): полыньи, сугробы, шипы, гряды-ориентиры,
##            вмёрзшие обломки, снежные вихри — иди куда хочешь
##   345…-34  Воронка и Ледяной каньон — строит ice_canyon.gd
##   -654…-1668 Снежная пустошь с метелью — строит snow_waste.gd (план — waste_layout.gd)
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
const HILL := preload("res://scenes/world/snow_hill.gd")
const LAKE_ROCKS := preload("res://scenes/world/lake_rocks.gd")
const WASTE := preload("res://scenes/world/snow_waste.gd")
const S := IceRiver.SHIFT

var river: IceRiver
var rng: RandomNumberGenerator
var _count := 0
var _pending: Array[Node3D] = []


func build(lake: IceRiver, random: RandomNumberGenerator) -> void:
	river = lake
	rng = random
	var w := IceRiver.LAKE_HALF

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

	# ---------------- Ледяное поле ----------------
	_field()

	# ---------------- Снежная гора: подъёмник, спуск на сноуборде (шаг 139, вместо Ледяного каньона) ----------------
	var hill := Node3D.new()
	hill.set_script(HILL)
	hill.name = "SnowHill"
	_pending.append(hill)

	# ---------------- Снежная пустошь (после каньона) ----------------
	var waste := Node3D.new()
	waste.set_script(WASTE)
	waste.name = "SnowWaste"
	_pending.append(waste)

	_flush()


# ---------------------------------------------------------------------------
#  Ледяное поле: широкое, открытое — можно идти куда угодно. Опасности разбросаны
#  по всей площади, а гряды торосов служат ориентирами.
# ---------------------------------------------------------------------------

func _field() -> void:
	var z0 := IceRiver.FIELD_N + 4.0
	var z1 := 512.0
	# шаг 140: вихри, шипы, кристаллы, торосы и обломки убраны — на поле только сугробы,
	# полыньи и валуны (lake_rocks.gd); в проходе у пропасти — завал и тонкий лёд
	_scatter_snow(z0, z1, 70)
	var rocks := Node3D.new()
	rocks.set_script(LAKE_ROCKS)
	rocks.name = "LakeRocks"
	_pending.append(rocks)


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
		var z := rng.randf_range(z_min, z_max)
		var hw := IceRiver.hw_at(z)
		var x := rng.randf_range(-hw + 5.0, hw - 5.0)
		if IceRiver.in_lake(x, z, 3.0) and not river.is_hole(x, z, clearance):
			return Vector3(x, IceRiver.river_y(z), z)
	return Vector3(0, IceRiver.river_y(z_min), z_min)


func _ridge(z: float, height: float, gap_min: float, gap_max: float, gap_width: float, style: int) -> void:
	var gaps := PackedVector2Array()
	var x := -IceRiver.LAKE_HALF + rng.randf_range(4.0, gap_max)
	while x < IceRiver.LAKE_HALF - 3.0:
		gaps.append(Vector2(x - gap_width * 0.5, x + gap_width * 0.5))
		x += rng.randf_range(gap_min, gap_max)
	var ridge := _add(RIDGE, "Ridge", Vector3(0, IceRiver.river_y(z), z))
	ridge.height = height
	ridge.gaps = gaps
	ridge.seed_value = int(z * 13.0)
	ridge.half_width = IceRiver.LAKE_HALF
	ridge.style = style


## Низкая гряда торосов поперёк озера с проходами (можно и перепрыгнуть с разбега)
func _hummock_row(z: float, height: float, gap_min: float, gap_max: float, gap_width: float) -> void:
	var b = HUMMOCKS.new(int(z * 17.0))
	b.ground_y = IceRiver.river_y(z) + 0.02
	var w := IceRiver.LAKE_HALF
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
	var w := IceRiver.LAKE_HALF
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
		var z := rng.randf_range(z_min, z_max)
		var hw := IceRiver.hw_at(z)
		var x := rng.randf_range(-hw + 3.0, hw - 3.0)
		if not IceRiver.in_lake(x, z, 3.0) or river.is_hole(x, z, clearance):
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
		var z := rng.randf_range(z_min, z_max)
		var hw := IceRiver.hw_at(z)
		var x := rng.randf_range(-hw + 3.0, hw - 3.0)
		if not IceRiver.in_lake(x, z, 3.0) or river.is_hole(x, z, 3.0):
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
	s.half_width = IceRiver.LAKE_HALF
	s.seed_value = int(z_min)


func _flush() -> void:
	for n in _pending:
		add_child(n)
	_pending.clear()
