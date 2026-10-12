extends Node3D
## Инопланетный луг вокруг базы (место крушения).
##
## Всё растёт из кода по зерну, поэтому у всех игроков луг одинаковый:
##  * бирюзово-фиолетовая трава пучками (качается на ветру);
##  * светящиеся грибы — гроздьями, шляпки мягко пульсируют;
##  * «фонарики» — тонкие стебли со светящимися шарами наверху;
##  * трубчатые кусты с светящейся кромкой;
##  * тёмные камни с мхом (крупные — твёрдые, об них можно удариться);
##  * в воздухе над лугом летают светящиеся споры.
## Ближе к Борее (на север) растений всё меньше — луг переходит в снег.
## Луг разбит на куски 24×24 м: дальние куски не рисуются.

const PLANT_SHADER := preload("res://shaders/alien_plant.gdshader")
const CELL := 24.0

@export var area_min := Vector2(-74.0, 968.0)   ## (x, z) — северо-западный угол луга
@export var area_max := Vector2(74.0, 1212.0)    ## (x, z) — юго-восточный угол
@export var fade_from_z := 980.0                ## Севернее — растений нет (снег)
@export var full_from_z := 1055.0                ## Южнее — луг в полную силу
@export var seed_value := 5150

var _terrain: Node
var _spores: GPUParticles3D
var _env: Environment
var _fog_base := 0.0
var _fog_color_base := Color.WHITE

## Над лугом воздух прозрачнее и теплее, чем в снежной Борее
const MEADOW_FOG := 0.0025
const MEADOW_FOG_COLOR := Color(0.72, 0.84, 0.86)


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var mats := {
		"grass": _mat(0.09),
		"stiff": _mat(0.04),
		"stalk": _mat(0.05),
	}
	var kinds := [
		# имя, меш, материал, попыток на м², дальность видимости
		["grass", _grass_mesh(rng, false), mats["grass"], 0.75, 60.0],
		["grass_v", _grass_mesh(rng, true), mats["grass"], 0.22, 60.0],
		["mush", _mushroom_mesh(rng), mats["stiff"], 0.010, 130.0],
		["bulb", _bulb_mesh(rng), mats["stalk"], 0.007, 150.0],
		["tube", _tube_mesh(rng), mats["stiff"], 0.006, 130.0],
	]

	var cx0 := floori(area_min.x / CELL)
	var cx1 := floori(area_max.x / CELL)
	var cz0 := floori(area_min.y / CELL)
	var cz1 := floori(area_max.y / CELL)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			for k in kinds:
				_fill_cell(rng, cx, cz, k)

	_place_rocks(rng)
	_make_spores()
	var found := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not found.is_empty():
		_env = (found[0] as WorldEnvironment).environment
		_fog_base = _env.fog_density
		_fog_color_base = _env.fog_light_color


func _mat(sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PLANT_SHADER
	m.set_shader_parameter("sway", sway)
	return m


## Сколько растений в этой точке (0 — снег, 1 — полный луг) и можно ли тут расти
func density(x: float, z: float) -> float:
	var d := smoothstep(fade_from_z, full_from_z, z)
	# у корабля, на борозде и на месте появления — вытоптано
	var nose := Vector2(x, z).distance_to(SnowTerrain.CRASH_NOSE)
	d *= smoothstep(12.0, 22.0, nose)
	d *= smoothstep(3.0, 7.0, _furrow_dist(x, z))
	d *= 1.0 - 0.75 * scorch(x, z)   # выжженная земля — растений почти нет
	d *= smoothstep(3.0, 7.0, Vector2(x, z).distance_to(SnowTerrain.BASE_SPAWN))
	return d


## Насколько выжжено (0..1) — так же, как в шейдере земли, только с запасом по краю
func scorch(x: float, z: float) -> float:
	var a := SnowTerrain.CRASH_NOSE
	var ab := SnowTerrain.CRASH_TAIL - a
	var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var width := 7.5 * lerpf(1.0, 0.45, t) + 3.0
	var line := 1.0 - smoothstep(width * 0.55, width, _furrow_dist(x, z))
	var ship := 1.0 - smoothstep(13.0, 20.0, Vector2(x, z).distance_to(a + ab.normalized() * 12.0))
	return maxf(line * smoothstep(0.98, 0.9, t), ship)


func _furrow_dist(x: float, z: float) -> float:
	var a := SnowTerrain.CRASH_NOSE
	var ab := SnowTerrain.CRASH_TAIL - a
	var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return Vector2(x, z).distance_to(a + ab * t)


func _ground(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain else 0.0


func _fill_cell(rng: RandomNumberGenerator, cx: int, cz: int, kind: Array) -> void:
	var tries := int(CELL * CELL * float(kind[3]))
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in tries:
		var x := (cx + rng.randf()) * CELL
		var z := (cz + rng.randf()) * CELL
		var r := rng.randf()
		if x < area_min.x or x > area_max.x or z < area_min.y or z > area_max.y:
			continue
		# пятна: растения собираются группами
		var clump := 0.5 + 0.5 * sin(x * 0.21 + cos(z * 0.17) * 2.0) * cos(z * 0.13 - x * 0.05)
		if r > density(x, z) * (0.35 + 0.65 * clump):
			continue
		var s := rng.randf_range(0.75, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
		b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.12)) * b
		xforms.append(Transform3D(b, Vector3(x, _ground(x, z) - 0.03, z)))
		var c := _tint(rng, kind[0])
		var burn := scorch(x, z)
		if burn > 0.0:   # обугленные растения: чёрные, светящиеся части погасли
			c = c.lerp(Color(0.12, 0.09, 0.08), clampf(burn * 1.4, 0.0, 0.95))
		colors.append(c)
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = kind[1]
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = kind[2]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = kind[4]
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)


## Оттенок экземпляра: трава от бирюзы до зелени, грибы и шары — бирюзовые, розовые, жёлтые
func _tint(rng: RandomNumberGenerator, kind: String) -> Color:
	match kind:
		"grass":
			return Color(1, 1, 1).lerp(Color(0.8, 1.1, 0.9), rng.randf())
		"grass_v":
			return Color(1, 1, 1).lerp(Color(1.15, 0.9, 1.1), rng.randf())
		"mush", "bulb":
			var glows := [Color(0.35, 1.0, 0.95), Color(1.0, 0.45, 0.9), Color(0.75, 1.0, 0.35), Color(0.55, 0.6, 1.0)]
			return glows[rng.randi() % glows.size()]
		"tube":
			return [Color(0.75, 0.45, 1.0), Color(0.45, 0.85, 1.0), Color(1.0, 0.55, 0.6)][rng.randi() % 3]
	return Color.WHITE


# ---------------------------------------------------------------------------
#  Формы растений (строятся один раз, рисуются тысячами)
# ---------------------------------------------------------------------------

func _v(st: SurfaceTool, p: Vector3, c: Color, glow: float = 0.0) -> void:
	st.set_color(c)
	st.set_uv(Vector2(glow, 0.0))
	st.add_vertex(p)


## Пучок травинок: изогнутые сужающиеся ленты; низ тёмный, кончики светлые
func _grass_mesh(rng: RandomNumberGenerator, violet: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.02, 0.12, 0.12)
	var tip := Color(0.5, 0.28, 0.85) if violet else Color(0.18, 0.62, 0.5)
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var root := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		var height := rng.randf_range(0.35, 0.85)
		var lean := rng.randf_range(0.15, 0.45)
		var w := rng.randf_range(0.035, 0.06)
		var segs := 3
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := root + dir * lean * t0 * t0 + Vector3.UP * height * t0
			var p1 := root + dir * lean * t1 * t1 + Vector3.UP * height * t1
			var w0 := w * (1.0 - t0)
			var w1 := w * (1.0 - t1) + 0.002
			var c0 := base.lerp(tip, t0)
			var c1 := base.lerp(tip, t1)
			_v(st, p0 - side * w0, c0); _v(st, p0 + side * w0, c0); _v(st, p1 + side * w1, c1)
			_v(st, p0 - side * w0, c0); _v(st, p1 + side * w1, c1); _v(st, p1 - side * w1, c1)
	st.generate_normals()
	return st.commit()


## Гроздь светящихся грибов: бледные ножки и светящиеся шляпки
func _mushroom_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_c := Color(0.82, 0.86, 0.8)
	for i in rng.randi_range(3, 5):
		var off := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		var h := rng.randf_range(0.18, 0.6)
		var r := h * rng.randf_range(0.35, 0.55)
		var tilt := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		_cylinder(st, off, off + Vector3.UP * h + tilt, r * 0.18, r * 0.14, stem_c, 0.0, 6)
		_cap(st, off + Vector3.UP * h + tilt, r, r * 0.55, Color(1, 1, 1), 1.0)
	st.generate_normals()
	return st.commit()


## «Фонарики»: тонкие высокие стебли со светящимися шарами
func _bulb_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stalk_c := Color(0.12, 0.3, 0.28)
	for i in rng.randi_range(2, 4):
		var off := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		var h := rng.randf_range(0.9, 1.9)
		var bend := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		var mid := off + Vector3.UP * h * 0.5 + bend * 0.3
		var topp := off + Vector3.UP * h + bend
		_cylinder(st, off, mid, 0.025, 0.02, stalk_c, 0.0, 5)
		_cylinder(st, mid, topp, 0.02, 0.014, stalk_c, 0.0, 5)
		_sphere(st, topp + Vector3.UP * 0.07, rng.randf_range(0.07, 0.13), Color(1, 1, 1), 1.0)
	st.generate_normals()
	return st.commit()


## Трубчатый куст: открытые трубки разной высоты, светится кромка
func _tube_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rng.randi_range(4, 7):
		var off := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
		var h := rng.randf_range(0.35, 1.2)
		var r := rng.randf_range(0.06, 0.12)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		_cylinder(st, off, off + Vector3.UP * h + lean, r * 0.8, r, Color(0.55, 0.5, 0.65), 0.0, 7)
		_cylinder(st, off + Vector3.UP * (h - 0.06) + lean, off + Vector3.UP * h + lean, r * 1.02, r * 1.05, Color(1, 1, 1), 1.0, 7)
	st.generate_normals()
	return st.commit()


func _cylinder(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, c: Color, glow: float, n: int) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		_v(st, a + d0 * ra, c, glow); _v(st, b + d0 * rb, c, glow); _v(st, b + d1 * rb, c, glow)
		_v(st, a + d0 * ra, c, glow); _v(st, b + d1 * rb, c, glow); _v(st, a + d1 * ra, c, glow)


## Шляпка гриба: купол сверху и плоское дно
func _cap(st: SurfaceTool, center: Vector3, r: float, h: float, c: Color, glow: float) -> void:
	var n := 9
	var rings := 3
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for j in rings:
			var t0 := float(j) / rings
			var t1 := float(j + 1) / rings
			var r0 := r * cos(t0 * PI * 0.5)
			var r1 := r * cos(t1 * PI * 0.5)
			var y0 := h * sin(t0 * PI * 0.5)
			var y1 := h * sin(t1 * PI * 0.5)
			var p00 := center + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := center + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := center + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := center + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			_v(st, p00, c, glow); _v(st, p01, c, glow); _v(st, p11, c, glow)
			_v(st, p00, c, glow); _v(st, p11, c, glow); _v(st, p10, c, glow)
		# дно шляпки — чуть темнее и слабее светится
		var dim := c.darkened(0.3)
		_v(st, center, dim, glow * 0.5)
		_v(st, center + Vector3(cos(a1) * r, 0.0, sin(a1) * r), dim, glow * 0.5)
		_v(st, center + Vector3(cos(a0) * r, 0.0, sin(a0) * r), dim, glow * 0.5)


func _sphere(st: SurfaceTool, center: Vector3, r: float, c: Color, glow: float) -> void:
	var n := 8
	var rings := 5
	for j in rings:
		var b0 := PI * float(j) / rings - PI * 0.5
		var b1 := PI * float(j + 1) / rings - PI * 0.5
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var p00 := center + Vector3(cos(a0) * cos(b0), sin(b0), sin(a0) * cos(b0)) * r
			var p10 := center + Vector3(cos(a1) * cos(b0), sin(b0), sin(a1) * cos(b0)) * r
			var p01 := center + Vector3(cos(a0) * cos(b1), sin(b1), sin(a0) * cos(b1)) * r
			var p11 := center + Vector3(cos(a1) * cos(b1), sin(b1), sin(a1) * cos(b1)) * r
			_v(st, p00, c, glow); _v(st, p01, c, glow); _v(st, p11, c, glow)
			_v(st, p00, c, glow); _v(st, p11, c, glow); _v(st, p10, c, glow)


# ---------------------------------------------------------------------------
#  Камни и споры
# ---------------------------------------------------------------------------

func _place_rocks(rng: RandomNumberGenerator) -> void:
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.24, 0.23, 0.28)
	rock_mat.roughness = 0.95
	var moss_mat := StandardMaterial3D.new()
	moss_mat.albedo_color = Color(0.2, 0.5, 0.42)
	moss_mat.roughness = 1.0
	var shapes: Array[ArrayMesh] = []
	for i in 4:
		shapes.append(_rock_mesh(rng))
	var placed := 0
	var tries := 0
	while placed < 150 and tries < 2000:
		tries += 1
		var x := rng.randf_range(area_min.x, area_max.x)
		var z := rng.randf_range(area_min.y + 15.0, area_max.y)
		if rng.randf() > density(x, z) or absf(x) < 4.0:
			continue
		placed += 1
		var big := rng.randf() < 0.25
		var r := rng.randf_range(0.8, 1.9) if big else rng.randf_range(0.2, 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = shapes[rng.randi() % shapes.size()]
		mi.material_override = rock_mat
		mi.material_overlay = null
		var y := _ground(x, z) - r * 0.35
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, r * rng.randf_range(0.55, 0.9), r * rng.randf_range(0.8, 1.2))), Vector3(x, y, z))
		add_child(mi)
		# мох на макушке
		var moss := MeshInstance3D.new()
		var cap := SphereMesh.new()
		cap.radius = 0.75
		cap.height = 0.5
		cap.is_hemisphere = true
		cap.radial_segments = 8
		cap.rings = 3
		moss.mesh = cap
		moss.material_override = moss_mat
		moss.position = Vector3(0, 0.55, 0)
		moss.scale = Vector3(1.0, 0.6, 1.0)
		mi.add_child(moss)
		if big:
			var body := StaticBody3D.new()
			body.add_to_group("safe_ground")
			var col := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = r * 0.8
			col.shape = sh
			body.position = Vector3(x, y + r * 0.1, z)
			body.add_child(col)
			add_child(body)


## Неровный камень: сфера со смещёнными вершинами, гранёная
func _rock_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 7
	var rings := 5
	var pts := {}
	for j in rings + 1:
		for i in n:
			var b := PI * float(j) / rings - PI * 0.5
			var a := TAU * i / n
			var k := rng.randf_range(0.75, 1.15) if j > 0 and j < rings else 1.0
			pts[Vector2i(i, j)] = Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b)) * k
	for j in rings:
		for i in n:
			var i1 := (i + 1) % n
			var p00: Vector3 = pts[Vector2i(i, j)]
			var p10: Vector3 = pts[Vector2i(i1, j)]
			var p01: Vector3 = pts[Vector2i(i, j + 1)]
			var p11: Vector3 = pts[Vector2i(i1, j + 1)]
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
	st.generate_normals()
	return st.commit()


## Светящиеся споры в воздухе вокруг камеры (только над лугом)
func _make_spores() -> void:
	_spores = FX.particles(Color(0.6, 1.0, 0.85, 0.9), 140, 7.0, 0.022, 0.05, 0.25, Vector3(0, 0.04, 0), 180.0, false, true)
	FX.set_box(_spores, Vector3(14.0, 4.0, 14.0))
	var pm := _spores.process_material as ParticleProcessMaterial
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_speed_random = 0.3
	_spores.top_level = true
	_spores.emitting = true
	add_child(_spores)


func _process(_delta: float) -> void:
	if _spores == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	_spores.global_position = p
	var k := smoothstep(fade_from_z, full_from_z, p.z)
	_spores.amount_ratio = k
	if _env:
		_env.fog_density = lerpf(_fog_base, MEADOW_FOG, k)
		_env.fog_light_color = _fog_color_base.lerp(MEADOW_FOG_COLOR, k)
