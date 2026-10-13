extends Node3D
## Провал льда — как настоящий:
##  1) предупреждение (warn ≈ 0.45 с): от точки провала разбегается паутина трещин,
##     из трещин выбивает снежную пыль, лёд мелко дрожит и чуть проседает;
##  2) пролом: льдины в середине откидываются вниз, как люки (на ребре), внешние
##     кренятся и уходят под воду — по очереди, от центра к краю; часть всплывает;
##  3) вода: из-под льда выплёскивается тёмный горб воды, брызги, по воде бежит
##     пенное кольцо, со дна поднимаются пузыри, над тёплой водой — пар,
##     на поверхности остаётся шуга (ледяная крошка), покачивается.
## (Дыру во льду открывает ice_river.gd в конце предупреждения.)

var radius := 6.0
var seed_value := 1
var warn := 0.45

const SINK_TIME := 0.7

static var _mat: StandardMaterial3D
static var _edge_mat: StandardMaterial3D
static var _crack_mat: StandardMaterial3D
static var _water_mat: StandardMaterial3D
static var _foam_mat: StandardMaterial3D
static var _slush_mat: StandardMaterial3D

var _pieces: Array = []
var _t := 0.0
var _ice_y := 0.0
var _water_y := 0.0
var _opened := false
var _rng := RandomNumberGenerator.new()
var _cracks: Array = []          # [[точки ломаной (Vector2)], задержка роста]
var _crack_im: ImmediateMesh
var _crack_mi: MeshInstance3D
var _dome: MeshInstance3D
var _foam: MeshInstance3D
var _slush: MultiMeshInstance3D
var _slush_data: Array = []      # [x, z, фаза, наклон]
var _puffs: Array[GPUParticles3D] = []
var _steam: GPUParticles3D
var _bubbles: GPUParticles3D


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.32, 0.56, 0.74, 0.95)
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.roughness = 0.08
		_mat.metallic_specular = 0.9
		_mat.rim_enabled = true
		_mat.rim = 0.6
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_edge_mat = StandardMaterial3D.new()
		_edge_mat.albedo_color = Color(0.72, 0.9, 1.0)
		_edge_mat.roughness = 0.35
		_edge_mat.emission_enabled = true
		_edge_mat.emission = Color(0.25, 0.45, 0.55)
		_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_crack_mat = StandardMaterial3D.new()
		_crack_mat.albedo_color = Color(0.1, 0.26, 0.36, 0.85)
		_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_crack_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = Color(0.03, 0.14, 0.18, 0.85)
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.roughness = 0.04
		_water_mat.metallic_specular = 1.0
		_foam_mat = StandardMaterial3D.new()
		_foam_mat.albedo_color = Color(0.92, 0.97, 1.0, 0.8)
		_foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_foam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_slush_mat = StandardMaterial3D.new()
		_slush_mat.albedo_color = Color(0.82, 0.93, 1.0, 0.92)
		_slush_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_slush_mat.roughness = 0.2

	_ice_y = IceRiver.river_y(global_position.z) + 0.02
	var lake = get_tree().get_first_node_in_group("ice_lake")
	_water_y = lake.water_y(global_position.z) if lake else _ice_y - 0.6
	_rng.seed = seed_value
	_make_cracks()
	# снежная пыль из трещин
	for i in 7:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.2, 0.95) * radius
		var puff := FX.particles(Color(0.95, 0.98, 1.0, 0.85), 14, 0.9, 0.09, 0.6, 2.2, Vector3(0, -3, 0), 40.0)
		puff.position = Vector3(cos(a) * d, 0.05, sin(a) * d)
		add_child(puff)
		_puffs.append(puff)
	# лёгкая дрожь и треск сразу
	_puffs[0].restart()


# ---------------------------------------------------------------------------
#  Паутина трещин: лучи от центра (ломаные, с ответвлениями) и дуги-кольца
# ---------------------------------------------------------------------------
func _make_cracks() -> void:
	var rays := _rng.randi_range(8, 12)
	var start := _rng.randf() * TAU
	for i in rays:
		var a := start + TAU * i / rays + _rng.randf_range(-0.2, 0.2)
		var pts: Array[Vector2] = [Vector2.ZERO]
		var p := Vector2.ZERO
		var len := radius * _rng.randf_range(1.0, 1.25)
		var steps := 7
		for k in steps:
			a += _rng.randf_range(-0.28, 0.28)
			p += Vector2(cos(a), sin(a)) * len / steps
			pts.append(p)
			# ответвление
			if k > 1 and _rng.randf() < 0.35:
				var b := a + _rng.randf_range(0.5, 1.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
				var q := p
				var br: Array[Vector2] = [q]
				for m in 3:
					b += _rng.randf_range(-0.3, 0.3)
					q += Vector2(cos(b), sin(b)) * len / steps * 0.7
					br.append(q)
				_cracks.append([br, float(k) / steps])
		_cracks.append([pts, 0.0])
	# дуги вокруг (лёд «обламывается» кругом)
	for ring in [0.45, 0.85]:
		var r: float = radius * ring
		var a0 := _rng.randf() * TAU
		var segs := 4
		for s in segs:
			var arc: Array[Vector2] = []
			var aa := a0 + TAU * s / segs
			var span := TAU / segs * _rng.randf_range(0.5, 0.85)
			for k in 6:
				var u := aa + span * k / 5.0
				arc.append(Vector2(cos(u), sin(u)) * r * _rng.randf_range(0.95, 1.05))
			_cracks.append([arc, ring])
	_crack_im = ImmediateMesh.new()
	_crack_mi = MeshInstance3D.new()
	_crack_mi.mesh = _crack_im
	_crack_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack_mi)


## Рисуем трещины, выросшие на долю grow (0..1)
func _draw_cracks(grow: float) -> void:
	_crack_im.clear_surfaces()
	_crack_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _crack_mat)
	var any := false
	for c in _cracks:
		var pts: Array = c[0]
		var delay: float = c[1]
		var g := clampf((grow - delay * 0.6) / maxf(1.0 - delay * 0.6, 0.01), 0.0, 1.0)
		if g <= 0.0:
			continue
		var total := float(pts.size() - 1)
		var upto := g * total
		for i in pts.size() - 1:
			if float(i) >= upto:
				break
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if float(i + 1) > upto:
				b = a.lerp(b, upto - float(i))
			var w := lerpf(0.045, 0.014, float(i) / total)
			var d := (b - a)
			if d.length() < 0.001:
				continue
			var n := Vector2(-d.y, d.x).normalized() * w
			var y := 0.025
			var p0 := Vector3(a.x + n.x, y, a.y + n.y)
			var p1 := Vector3(a.x - n.x, y, a.y - n.y)
			var p2 := Vector3(b.x + n.x, y, b.y + n.y)
			var p3 := Vector3(b.x - n.x, y, b.y - n.y)
			_crack_im.surface_add_vertex(p0)
			_crack_im.surface_add_vertex(p2)
			_crack_im.surface_add_vertex(p1)
			_crack_im.surface_add_vertex(p1)
			_crack_im.surface_add_vertex(p2)
			_crack_im.surface_add_vertex(p3)
			any = true
	if not any:
		_crack_im.surface_add_vertex(Vector3.ZERO)
		_crack_im.surface_add_vertex(Vector3.ZERO)
		_crack_im.surface_add_vertex(Vector3.ZERO)
	_crack_im.surface_end()


# ---------------------------------------------------------------------------
#  Пролом: льдины, вода, пена, шуга, пузыри, пар
# ---------------------------------------------------------------------------
func _open() -> void:
	_opened = true
	_crack_mi.visible = false
	# Внутренний круг — 4–5 льдин (откидываются, как люки), внешнее кольцо — 9–12
	_ring(0.0, radius * _rng.randf_range(0.38, 0.48), _rng.randi_range(4, 5), true)
	_ring(radius * 0.43, radius, _rng.randi_range(9, 12), false)

	_burst(0.0, 80, 7.5)
	for i in 6:
		var a := TAU * i / 6.0 + _rng.randf()
		_burst(radius * 0.75, 36, 5.0, Vector3(cos(a), 0, sin(a)))
	# горб воды из-под льда
	var cap := SphereMesh.new()
	cap.radius = radius * 0.35
	cap.height = radius * 0.35
	cap.is_hemisphere = true
	cap.radial_segments = 24
	cap.rings = 6
	cap.material = _water_mat
	_dome = MeshInstance3D.new()
	_dome.mesh = cap
	_dome.position = Vector3(0, _water_y - _ice_y, 0)
	_dome.scale = Vector3(1.0, 0.01, 1.0)
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dome)
	# пенное кольцо
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.0
	ring.rings = 40
	ring.ring_segments = 4
	ring.material = _foam_mat.duplicate()
	_foam = MeshInstance3D.new()
	_foam.mesh = ring
	_foam.position = Vector3(0, _water_y - _ice_y + 0.04, 0)
	_foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foam)
	# шуга: ледяная крошка на воде
	var chip := BoxMesh.new()
	chip.size = Vector3(0.22, 0.06, 0.16)
	chip.material = _slush_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = chip
	mm.instance_count = 70
	_slush = MultiMeshInstance3D.new()
	_slush.multimesh = mm
	_slush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_slush)
	for i in mm.instance_count:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * radius * 0.92
		_slush_data.append([cos(a) * d, sin(a) * d, _rng.randf() * TAU, _rng.randf_range(0.3, 1.4), _rng.randf_range(0.5, 1.6)])
	# пузыри со дна и пар над тёплой водой
	_bubbles = FX.particles(Color(0.85, 0.95, 1.0, 0.7), 60, 2.2, 0.06, 1.0, 2.6, Vector3(0, 1.5, 0), 25.0, false)
	FX.set_box(_bubbles, Vector3(radius * 0.6, 0.2, radius * 0.6))
	_bubbles.position = Vector3(0, _water_y - _ice_y - 2.5, 0)
	add_child(_bubbles)
	_bubbles.emitting = true
	_steam = FX.particles(Color(0.95, 0.97, 1.0, 0.22), 40, 3.5, 0.9, 0.2, 0.7, Vector3(0, 0.25, 0), 20.0, false)
	FX.set_box(_steam, Vector3(radius * 0.7, 0.1, radius * 0.7))
	_steam.position = Vector3(0, _water_y - _ice_y + 0.2, 0)
	add_child(_steam)
	_steam.emitting = true


func _ring(r_in: float, r_out: float, count: int, hinge: bool) -> void:
	var start := _rng.randf() * TAU
	var angles: Array[float] = []
	for i in count + 1:
		angles.append(start + TAU * i / count + (_rng.randf_range(-0.12, 0.12) if i > 0 and i < count else 0.0))
	angles[count] = angles[0] + TAU
	for i in count:
		var a0: float = angles[i]
		var a1: float = angles[i + 1]
		var poly := PackedVector2Array()
		var steps := 4
		for s in steps + 1:
			var a := lerpf(a0, a1, float(s) / steps)
			poly.append(Vector2(cos(a), sin(a)) * r_out * _rng.randf_range(0.95, 1.02))
		if r_in < 0.05:
			poly.append(Vector2.ZERO)
		else:
			for s in range(steps, -1, -1):
				var a := lerpf(a0, a1, float(s) / steps)
				poly.append(Vector2(cos(a), sin(a)) * r_in * _rng.randf_range(0.97, 1.05))
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= poly.size()
		var am := (a0 + a1) * 0.5
		var out_dir := Vector2(cos(am), sin(am))
		# шарнир — внешний край льдины (люк откидывается вниз к центру)
		var pivot := out_dir * r_out * 0.97 if hinge else center
		var local := PackedVector2Array()
		for p in poly:
			local.append((p - center) * 0.93 + (center - pivot))
		var holder := Node3D.new()
		holder.position = Vector3(pivot.x, 0.0, pivot.y)
		add_child(holder)
		var piece := MeshInstance3D.new()
		piece.mesh = _slab(local, _rng.randf_range(0.25, 0.4))
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(piece)
		var tangent := Vector3(-out_dir.y, 0.0, out_dir.x)
		var floats := not hinge and _rng.randf() < 0.55
		_pieces.append({
			"node": holder,
			"delay": (center.length() / maxf(radius, 0.1)) * 0.22 + _rng.randf_range(0.0, 0.06),
			"axis": tangent if hinge else Vector3.UP.cross(-Vector3(out_dir.x, 0, out_dir.y)).normalized(),
			"tilt": (_rng.randf_range(1.1, 1.5) if hinge else _rng.randf_range(0.35, 0.8) * (1.0 if floats else 1.6)),
			"hinge": hinge,
			"floats": floats,
			"spin": _rng.randf_range(-0.4, 0.4),
		})


## Плоская льдина по контуру: верх, низ, торцы; торцы светлые (свежий скол)
func _slab(poly: PackedVector2Array, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var top := 0.0
	var bottom := -thick
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= n
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(c.x, top, c.y))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(a.x, top, a.y))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(c.x, bottom, c.y))
		st.add_vertex(Vector3(a.x, bottom, a.y))
		st.add_vertex(Vector3(b.x, bottom, b.y))
	var top_mesh := st.commit()
	top_mesh.surface_set_material(0, _mat)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var side := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		st2.set_normal(-side)
		st2.add_vertex(Vector3(a.x, top, a.y))
		st2.add_vertex(Vector3(b.x, top, b.y))
		st2.add_vertex(Vector3(a.x, bottom, a.y))
		st2.add_vertex(Vector3(b.x, top, b.y))
		st2.add_vertex(Vector3(b.x, bottom, b.y))
		st2.add_vertex(Vector3(a.x, bottom, a.y))
	st2.set_material(_edge_mat)
	return st2.commit(top_mesh)


func _burst(dist: float, amount: int, speed: float, dir: Vector3 = Vector3.ZERO) -> void:
	var p := FX.particles(Color(0.85, 0.95, 1.0, 0.9), amount, 1.2, 0.12, speed * 0.5, speed, Vector3(0, -12, 0), 35.0)
	p.position = dir * dist + Vector3(0, _water_y - _ice_y + 0.2, 0)
	add_child(p)
	p.restart()


func _process(delta: float) -> void:
	_t += delta
	if not _opened:
		# предупреждение: трещины бегут от центра, из них пылит снег
		var g := clampf(_t / maxf(warn, 0.05), 0.0, 1.0)
		_draw_cracks(1.0 - pow(1.0 - g, 2.0))
		var k := int(g * _puffs.size())
		for i in mini(k, _puffs.size()):
			if not _puffs[i].emitting and _puffs[i].get_meta("done", false) == false:
				_puffs[i].restart()
				_puffs[i].set_meta("done", true)
		_crack_mi.position.y = -0.02 * g + sin(_t * 70.0) * 0.004
		if _t >= warn:
			_open()
		return
	var t0 := _t - warn
	var all_done := true
	for item in _pieces:
		var obj = item["node"]
		if not is_instance_valid(obj):
			continue
		var node := obj as Node3D
		var t: float = maxf(t0 - float(item["delay"]), 0.0)
		var k := clampf(t / SINK_TIME, 0.0, 1.0)
		var ease := k * k * (3.0 - 2.0 * k)
		if item["hinge"]:
			# люк: откидывается вниз на ребре и, сорвавшись, тонет
			var swing := float(item["tilt"]) * ease
			node.basis = Basis(item["axis"], swing)
			node.position.y = lerpf(0.0, _water_y - _ice_y - 3.0, smoothstep(0.55, 1.0, k) * smoothstep(0.55, 1.0, k))
			if t > SINK_TIME * 1.4:
				node.queue_free()
			else:
				all_done = false
		elif item["floats"]:
			# проседает, ныряет и всплывает на поверхность воды
			var dip := sin(clampf(t / (SINK_TIME * 1.6), 0.0, 1.0) * PI) * 0.35
			var drop := lerpf(0.0, _water_y - _ice_y + 0.12, ease) - dip
			var settle := clampf((t - SINK_TIME) / 1.0, 0.0, 1.0)
			var tilt: float = item["tilt"] * ease * (1.0 - settle * 0.85)
			node.basis = Basis(item["axis"], tilt) * Basis(Vector3.UP, float(item["spin"]) * ease)
			node.position.y = drop + sin(_t * 1.5 + node.position.x) * 0.03 * settle
			if t < SINK_TIME * 2.6:
				all_done = false
		else:
			var drop2 := lerpf(0.0, _water_y - _ice_y - 2.5, ease * ease)
			node.basis = Basis(item["axis"], float(item["tilt"]) * ease) * Basis(Vector3.UP, float(item["spin"]) * ease)
			node.position.y = drop2
			if k >= 1.0:
				node.queue_free()
			else:
				all_done = false
	# горб воды: поднимается и опадает
	if is_instance_valid(_dome):
		var dk := clampf(t0 / 0.65, 0.0, 1.0)
		var h := sin(dk * PI) * 0.9 * (1.0 - dk * 0.3)
		_dome.scale = Vector3(1.0 + dk * 0.6, maxf(h, 0.01), 1.0 + dk * 0.6)
		if dk >= 1.0:
			_dome.queue_free()
		all_done = false
	# пенное кольцо разбегается и тает
	if is_instance_valid(_foam):
		var fk := clampf(t0 / 1.6, 0.0, 1.0)
		var r := lerpf(0.6, radius * 1.02, 1.0 - pow(1.0 - fk, 2.0))
		_foam.scale = Vector3(r, 1.0, r)
		(_foam.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = 0.8 * (1.0 - fk)
		if fk >= 1.0:
			_foam.queue_free()
	# шуга покачивается на волнах (с затуханием)
	if _slush:
		var mm := _slush.multimesh
		var wave := 0.12 * exp(-t0 * 0.5) + 0.02
		for i in _slush_data.size():
			var d: Array = _slush_data[i]
			var ph: float = d[2]
			var y := _water_y - _ice_y + 0.02 + sin(_t * 1.7 + ph) * wave
			var b := Basis(Vector3.UP, ph + _t * 0.05).scaled(Vector3.ONE * float(d[4]))
			b = Basis(Vector3.RIGHT, sin(_t * 1.3 + ph) * 0.15 * float(d[3])) * b
			mm.set_instance_transform(i, Transform3D(b, Vector3(d[0], y, d[1])))
	# пузыри и пар — недолго
	if _bubbles and t0 > 3.0:
		_bubbles.emitting = false
	if _steam and t0 > 6.0:
		_steam.emitting = false
	if all_done and t0 > 8.0:
		set_process(false)   # остаются плавающие льдины и шуга
