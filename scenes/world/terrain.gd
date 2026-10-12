class_name SnowTerrain
extends StaticBody3D
## Процедурный рельеф снежной планеты «Борея».
## Высота в каждой точке = лёгкий шум + специально спланированные участки.
## Тропа идёт с юга (база на месте крушения) на север (z = -200, станция) вдоль x ≈ 0.
##
##   z 1210 … 1020 База: инопланетный луг, разбитый корабль (место крушения ~ z 1110)
##   z 1020 … 945  Переход: трава редеет, иней, сугробы
##   z  945 … 917  Лагерь — контрольная точка Бореи
##   z  915 … 80   Огромное замёрзшее озеро на всю ширину (~450 × 830 м),
##                 первые 150 м — каток
##   z   72 … 8    Лавинный склон (гора на западе)
##   z   -2 … -40  Трещины (две пропасти поперёк пути)
##   z  -42 … -106 Плато бурь (обрывы по бокам)
##   z -108 … -150 Каньон с ледяной пещерой
##   z -150 … -200 Замёрзшее озеро и станция
##
## Чтобы поменять форму мира — правь функцию height_at().

@export var size_x := 540.0
@export var size_z := 1430.0
@export var north_edge_z := -215.0
@export var cell := 1.5
@export var noise_seed := 7
@export var terrain_material: Material

## Трещины: (центр по z, полуширина)
const CREVASSES := [Vector2(-12.0, 3.0), Vector2(-30.0, 3.5)]
const CREVASSE_DEPTH := -30.0
const RIVER_HALF := 225.0  ## Полуширина замёрзшего озера (как в ice_river.gd)
const LAKE_CENTER := Vector2(0.0, -175.0)
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
		sm.set_shader_parameter("crash_nose", CRASH_NOSE)
		sm.set_shader_parameter("crash_tail", CRASH_TAIL)
		sm.set_shader_parameter("meadow_start_z", BASE_START_Z + 15.0)
		sm.set_shader_parameter("meadow_full_z", BASE_START_Z + 85.0)
	_build()


## Высота рельефа в точке (x, z).
func height_at(x: float, z: float) -> float:
	var ax := absf(x)
	var h := _noise.get_noise_2d(x, z) * 1.6

	# Вдоль тропы ровнее, в стороне — крупные холмы
	h *= lerpf(1.0, 0.2, 1.0 - smoothstep(5.0, 16.0, ax))
	h += maxf(_big_noise.get_noise_2d(x, z), 0.0) * 10.0 * smoothstep(20.0, 45.0, ax)

	# Замёрзшее озеро: дно подо льдом и пологие берега далеко по краям
	var wr := _band(z, 917.0, 80.0, 6.0)
	if wr > 0.0:
		var ry := IceRiver.river_y(z)
		# Вода только под льдом (с запасом от краёв) — у входа на лёд нет провала
		var water := _band(z, 912.0, 93.0, 1.0)
		var inside := 1.0 - smoothstep(RIVER_HALF - 1.0, RIVER_HALF + 1.0, ax)
		var bed := ry - (IceRiver.WATER_GAP + IceRiver.lake_depth(x, z)) * water
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
	edge += clampf((north_edge_z + 7.0 - z) * 1.5, 0.0, 45.0)
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

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
