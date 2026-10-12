extends Node3D
## Место крушения «Ржавого Борова» — база игроков.
##
## Корабль лежит носом в земле (нос — CRASH_NOSE из terrain.gd), за ним тянется
## выжженная борозда. Вдоль неё:
##  * оторванные части: кусок фюзеляжа с рёбрами каркаса, двигатель с ещё
##    раскалённым соплом, крыло, воткнувшееся в землю, тарелка антенны,
##    гнутые балки, рваные листы обшивки, комья вывороченной земли;
##  * грузовые контейнеры корабля — из разбитого вывалились ящики с запчастями и баллоны;
##  * несколько очагов огня с искрами и дымом, тлеющие угли (в шейдере земли);
##  * аварийные маяки с вращающимся лучом, искрящие оборванные кабели,
##    светящаяся лужа топлива, пар, бьющий из пробоин.
## На корпусе — копоть и царапины от удара (hull_damage.gdshader).
## Всё строится по зерну — у всех игроков одинаково.

const PROP := preload("res://scenes/world/model_prop.gd")
const SHIP := preload("res://assets/props/Insurgent.glb")
const DEBRIS := preload("res://scenes/world/crash_debris.gd")
const DAMAGE := preload("res://shaders/hull_damage.gdshader")
const FUEL := preload("res://shaders/fuel_puddle.gdshader")

@export var ship_length := 24.0
@export var ship_yaw_deg := 180.0     ## Куда смотрит нос (подобрано под модель)
@export var nose_down_deg := 6.0      ## Насколько нос зарылся в землю
@export var roll_deg := 7.0           ## Крен на бок
@export var seed_value := 777

const SHIP_PAINT := Color(0.55, 0.58, 0.63)
const DARK_PAINT := Color(0.32, 0.34, 0.38)
const ORANGE := Color(0.86, 0.42, 0.12)

var _terrain: Node
var _rng := RandomNumberGenerator.new()
var _nose := Vector2.ZERO
var _along := Vector2.ZERO
var _side := Vector2.ZERO
var _yaw := 0.0
var _ship: StaticBody3D
var _soft_tex: GradientTexture2D

var _blinkers: Array = []       ## [OmniLight3D, StandardMaterial3D, фаза, скорость]
var _spinners: Array[Node3D] = []
var _sparkers: Array = []       ## [GPUParticles3D, OmniLight3D, таймер]
var _flames: Array = []         ## [OmniLight3D, базовая яркость, фаза]
var _steam: Array = []          ## [GPUParticles3D, таймер]
var _t := 0.0


func _ready() -> void:
	_rng.seed = seed_value
	_build.call_deferred()


# ---------------------------------------------------------------------------
#  Где что лежит: dist — метры от носа вдоль борозды, off — вбок от неё
# ---------------------------------------------------------------------------
func _ground(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain else 0.0


func _at(dist: float, off: float, lift: float = 0.0) -> Vector3:
	var p := _nose + _along * dist + _side * off
	return Vector3(p.x, _ground(p.x, p.y) + lift, p.y)


func _add_mesh(mesh: Mesh, xform: Transform3D, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.add_to_group("safe_ground")
		var col := CollisionShape3D.new()
		col.shape = mesh.create_trimesh_shape()
		body.transform = xform
		body.add_child(col)
		add_child(body)
	return mi


func _build() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain")
	_nose = SnowTerrain.CRASH_NOSE
	_along = (SnowTerrain.CRASH_TAIL - _nose).normalized()
	_side = Vector2(-_along.y, _along.x)
	_yaw = atan2(_along.x, _along.y)
	_make_soft_texture()

	_build_ship()
	_build_parts()
	_build_cargo()
	_build_small_debris()
	_build_fuel_puddle()

	# Огонь: у носа в воронке — самый сильный
	_add_fire(_at(-1.5, 0.5, 0.15), 1.4, true)
	_add_fire(_at(3.0, -3.0, 0.1), 0.7, false)
	for i in 3:
		_add_smoke(_at(8.0 + i * 5.0, _rng.randf_range(-1.5, 1.5), 3.4 + i * 0.4), 0.9 + i * 0.25)

	_make_labels()
	_make_signpost(Vector3(SnowTerrain.BASE_SPAWN.x + 2.0, 0.0, SnowTerrain.BASE_SPAWN.y - 14.0))
	_attach_to_hull.call_deferred()


# ---------------------------------------------------------------------------
#  Корабль
# ---------------------------------------------------------------------------
func _build_ship() -> void:
	var center := _nose + _along * ship_length * 0.5
	_ship = StaticBody3D.new()
	_ship.set_script(PROP)
	_ship.name = "RustyBoar"
	_ship.set("model", SHIP)
	_ship.set("target_length", ship_length)
	_ship.set("lift", -0.6)
	_ship.set("frost", 0.0)
	_ship.set("snow_drifts", false)
	_ship.set("landing_gear", false)
	_ship.transform = Transform3D(
		Basis(Vector3.UP, _yaw + deg_to_rad(ship_yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(nose_down_deg)) * Basis(Vector3.FORWARD, deg_to_rad(roll_deg)),
		Vector3(center.x, 0.0, center.y))
	add_child(_ship)
	# копоть и царапины поверх модели
	var dmg := ShaderMaterial.new()
	dmg.shader = DAMAGE
	dmg.set_shader_parameter("crash_nose", _nose)
	dmg.set_shader_parameter("crash_dir", _along)
	dmg.set_shader_parameter("ground_y", _ground(center.x, center.y))
	for node in _ship.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = dmg


# ---------------------------------------------------------------------------
#  Оторванные части корабля
# ---------------------------------------------------------------------------
func _build_parts() -> void:
	# Кусок фюзеляжа: лежит на боку, внутри видны рёбра каркаса, внутри горит
	var skin := DEBRIS.metal(SHIP_PAINT, 0.4, 0.6, 0.2, 0.0, 0.0, 0.0, 1.1)
	var ribs := DEBRIS.metal(DARK_PAINT, 0.5, 0.5, 0.45)
	var hs: Array = DEBRIS.hull_section(_rng, 3.0, 5.5, 3.7, skin, ribs)
	var hp := _at(31.0, 3.5, -1.3)
	var hb := Basis(Vector3.UP, _yaw + 0.35) * Basis(Vector3.FORWARD, 1.75) * Basis(Vector3.RIGHT, 0.12)
	_add_mesh(hs[0], Transform3D(hb, hp), true)
	_add_mesh(hs[1], Transform3D(hb, hp), false)
	_add_fire(_at(31.0, 3.0, 0.2), 1.0, true)
	_add_smoke(_at(31.0, 3.5, 2.5), 1.1)

	# Двигатель: перед оторван (оттуда торчат кабели), сопло ещё раскалено
	var eng_body := DEBRIS.metal(DARK_PAINT, 0.45, 0.65, 0.3, 0.0, 0.0, 0.0, 0.7)
	var eng_hot := DEBRIS.metal(Color(0.25, 0.22, 0.2), 0.2, 0.3, 0.0, 0.0, 0.0, 0.85)
	var parts: Array = DEBRIS.engine(_rng, eng_body, eng_hot)
	var ep := _at(52.0, -7.0, 0.55)
	var eb := Basis(Vector3.UP, _yaw + PI + 0.5) * Basis(Vector3.RIGHT, -0.18) * Basis(Vector3.BACK, 0.3)
	_add_mesh(parts[0], Transform3D(eb, ep), true)
	_add_mesh(parts[1], Transform3D(eb, ep), false)
	var front := ep + eb * Vector3(0, 0, 0.3)
	_add_fire(front + Vector3(0, -0.6, 0), 0.9, true)
	var nozzle := ep + eb * Vector3(0, 0, 5.6)
	_add_smoke(nozzle + Vector3.UP * 1.0, 0.7)
	var wire := DEBRIS.metal(Color(0.08, 0.08, 0.09), 0.1, 0.0, 0.0)
	for c in 3:
		var a := TAU * c / 3.0 + 0.3
		var from := ep + eb * Vector3(cos(a) * 1.2, sin(a) * 1.2, 0.2)
		var to := from + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
		to.y = _ground(to.x, to.z) + 0.05
		add_child(_mi(DEBRIS.cable(from, to, 0.4, 0.045, wire)))
		_add_sparker(to)

	# Крыло: воткнулось корнем в землю, конец задран в небо, на нём мигает огонь
	var wing_mat := DEBRIS.metal(SHIP_PAINT, 0.45, 0.65, 0.3, 1.0, 7.4, 0.0, 1.3)
	var wp := _at(41.0, 11.0, -0.9)
	var wb := Basis(Vector3.UP, _yaw - 0.8) * Basis(Vector3.FORWARD, -0.75) * Basis(Vector3.RIGHT, 0.2)
	_add_mesh(DEBRIS.wing(_rng, 8.5, wing_mat), Transform3D(wb, wp), true)
	_add_blinker(wp + wb * Vector3(1.8, 8.6, 0.0), Color(1.0, 0.15, 0.1), 0.9, false)

	# Тарелка антенны
	var dish_mat := DEBRIS.metal(Color(0.85, 0.86, 0.88), 0.3, 0.35, 0.15)
	var dp := _at(21.0, -10.0, 0.2)
	var db := Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, 0.95)
	_add_mesh(DEBRIS.dish(_rng, 2.3, dish_mat), Transform3D(db, dp), true)

	# Гнутые балки каркаса: часть лежит, часть воткнулась в землю
	var beam := DEBRIS.metal(DARK_PAINT, 0.6, 0.55, 0.5)
	for i in 7:
		var dist := 12.0 + i * 11.0 + _rng.randf_range(-3.0, 3.0)
		var off := _rng.randf_range(-6.0, 6.0)
		var stuck := i % 3 == 1
		var bp := _at(dist, off, 0.1 if not stuck else -0.6)
		var bb := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, -0.9 if stuck else _rng.randf_range(-0.1, 0.1))
		_add_mesh(DEBRIS.girder(_rng.randf_range(3.0, 6.0), _rng.randf_range(0.25, 0.9), beam), Transform3D(bb, bp), true)


# ---------------------------------------------------------------------------
#  Груз: разбитый контейнер с вывалившимися припасами и второй, лежащий на боку
# ---------------------------------------------------------------------------
func _build_cargo() -> void:
	var wall := DEBRIS.metal(ORANGE, 0.35, 0.3, 0.35, 0.0, 0.0, 0.0, 1.2)
	var frame := DEBRIS.metal(Color(0.2, 0.2, 0.22), 0.5, 0.4, 0.4)
	var size := Vector3(4.2, 2.3, 2.3)

	# A: у носа корабля, открытым торцом к точке появления
	var cp := _at(5.0, -13.0, 1.0)
	var open_dir := (SnowTerrain.BASE_SPAWN - Vector2(cp.x, cp.z)).normalized()
	var cyaw := atan2(-open_dir.y, open_dir.x)
	var cb := Basis(Vector3.UP, cyaw) * Basis(Vector3.RIGHT, 0.08) * Basis(Vector3.BACK, 0.06)
	var cont: Array = DEBRIS.container(size, wall, frame)
	_add_mesh(cont[0], Transform3D(cb, cp), true)
	_add_mesh(cont[1], Transform3D(cb, cp), false)
	# одна створка висит на петле
	var door_pos := cp + cb * Vector3(size.x / 2, 0.0, -size.z / 2)
	_add_mesh(cont[2], Transform3D(cb * Basis(Vector3.UP, -1.2) * Basis(Vector3.RIGHT, 0.15), door_pos), false)
	_add_logo(cp, cb, size)
	_add_blinker(cp + cb * Vector3(-1.4, size.y / 2 + 0.15, 0.0), Color(1.0, 0.55, 0.1), 1.6, true)
	# из открытого торца вывалились припасы корабля: ящики с запчастями и баллоны
	var crate_mat := DEBRIS.metal(Color(0.3, 0.36, 0.3), 0.4, 0.3, 0.3, 0.0, 0.0, 0.0, 0.5)
	var tank_mat := DEBRIS.metal(Color(0.75, 0.2, 0.15), 0.35, 0.25, 0.2)
	var mouth := cp + cb * Vector3(size.x / 2 + 0.3, -size.y / 2, 0.0)
	var out := (cb * Vector3.RIGHT).normalized()
	var crate := BoxMesh.new()
	crate.material = crate_mat
	var tank := CylinderMesh.new()
	tank.top_radius = 0.22
	tank.bottom_radius = 0.22
	tank.height = 1.2
	tank.material = tank_mat
	for i in 14:
		var dir := out.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
		var dist := pow(_rng.randf(), 0.7) * 5.5
		var p := mouth + dir * dist
		var mi := MeshInstance3D.new()
		if i % 3 == 2:   # баллон, лежит на боку
			mi.mesh = tank
			p.y = _ground(p.x, p.z) + 0.2
			mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), p)
		else:            # ящик с запчастями
			var s := Vector3(_rng.randf_range(0.6, 1.1), _rng.randf_range(0.4, 0.7), _rng.randf_range(0.5, 0.9))
			p.y = _ground(p.x, p.z) + s.y * 0.45
			mi.mesh = crate
			mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2)) * Basis.from_scale(s), p)
		add_child(mi)

	# B: в борозде, на боку, помятый
	var cp2 := _at(45.0, -2.0, 1.0)
	var cb2 := Basis(Vector3.UP, _yaw + 1.2) * Basis(Vector3.RIGHT, PI * 0.5 - 0.15)
	var cont2: Array = DEBRIS.container(size, wall, frame)
	_add_mesh(cont2[0], Transform3D(cb2, cp2), true)
	_add_mesh(cont2[1], Transform3D(cb2, cp2), false)
	_add_logo(cp2, cb2, size)


func _add_logo(pos: Vector3, basis: Basis, size: Vector3) -> void:
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "«РЖАВЫЙ БОРОВ»\nГРУЗОВОЙ ОТСЕК"
		l.font_size = 64
		l.outline_size = 0
		l.modulate = Color(0.12, 0.1, 0.1, 0.9)
		l.pixel_size = 0.006
		l.double_sided = false
		var face := basis * Basis(Vector3.UP, 0.0 if side > 0.0 else PI)
		l.transform = Transform3D(face, pos + basis * Vector3(0.0, 0.25, side * (size.z / 2 + 0.07)))
		add_child(l)


# ---------------------------------------------------------------------------
#  Мелочь: рваные листы обшивки, комья земли
# ---------------------------------------------------------------------------
func _build_small_debris() -> void:
	var paints := [SHIP_PAINT, SHIP_PAINT, DARK_PAINT, Color(0.3, 0.45, 0.75)]
	for i in 18:
		var dist := _rng.randf_range(10.0, 90.0)
		var off := _rng.randf_range(-8.0, 8.0)
		var upright := _rng.randf() < 0.3
		var mat := DEBRIS.metal(paints[i % paints.size()], _rng.randf_range(0.25, 0.6), _rng.randf_range(0.3, 0.8), 0.25,
			1.0 if i % 7 == 3 else 0.0, 0.0)
		var w := _rng.randf_range(1.2, 3.4)
		var h := _rng.randf_range(0.8, 2.2)
		var mesh := DEBRIS.torn_plate(_rng, w, h, _rng.randf_range(0.1, 0.6), mat)
		var p := _at(dist, off, 0.05 if not upright else h * 0.25)
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		b = b * (Basis(Vector3.RIGHT, _rng.randf_range(-0.4, 0.4)) if upright else Basis(Vector3.RIGHT, -PI * 0.5 + _rng.randf_range(-0.25, 0.25)))
		_add_mesh(mesh, Transform3D(b, p), w > 2.0)

	# комья вывороченной земли на валах борозды
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.12, 0.09, 0.08)
	soil.roughness = 1.0
	var clod := DEBRIS.clod(_rng)
	clod.surface_set_material(0, soil)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = clod
	var xs: Array[Transform3D] = []
	for i in 180:
		var dist := _rng.randf_range(-6.0, 95.0)
		var off := (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(3.8, 8.5) * lerpf(1.0, 0.5, clampf(dist / 100.0, 0.0, 1.0))
		var s := _rng.randf_range(0.12, 0.55)
		var p := _at(dist, off, s * 0.2)
		xs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * _rng.randf_range(0.6, 1.0), s)), p))
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# ---------------------------------------------------------------------------
#  Лужа топлива
# ---------------------------------------------------------------------------
func _build_fuel_puddle() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FUEL
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 1
	plane.material = mat
	var p := _at(13.0, 6.5, 0.06)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.transform = Transform3D(Basis(Vector3.UP, 0.7) * Basis.from_scale(Vector3(3.8, 1.0, 2.6)), p)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 1.0, 0.75)
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	glow.position = p + Vector3.UP * 0.5
	add_child(glow)
	# испарения
	var vapor := _soft_particles(20, 3.5, 0.9, Color(0.4, 1.0, 0.8, 0.25), Color(0.4, 1.0, 0.8, 0.0), 0.15, 0.4, Vector3(0, 0.15, 0), false)
	FX.set_box(vapor, Vector3(2.5, 0.05, 1.6))
	vapor.position = p + Vector3.UP * 0.2
	add_child(vapor)


# ---------------------------------------------------------------------------
#  То, что крепится к корпусу (ищем поверхность корабля лучами)
# ---------------------------------------------------------------------------
func _attach_to_hull() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	# маяки и пар — на крыше
	for d in [7.0, 17.0]:
		var top := _ray_ship(space, _at(d, 0.0, 30.0), _at(d, 0.0, -5.0))
		if top != Vector3.INF:
			_add_blinker(top + Vector3.UP * 0.15, Color(1.0, 0.5, 0.08), 1.3 if d < 10.0 else 1.9, true)
	for d in [11.0, 20.0]:
		var top := _ray_ship(space, _at(d, 1.5, 30.0), _at(d, 1.5, -5.0))
		if top != Vector3.INF:
			_add_steam(top)
	# оборванные кабели — свисают с бортов до земли и искрят
	var wire := DEBRIS.metal(Color(0.07, 0.07, 0.08), 0.1, 0.0, 0.0)
	for c in [[9.0, 1.0], [15.0, -1.0], [19.0, 1.0]]:
		var d: float = c[0]
		var s: float = c[1]
		var hit := _ray_ship(space, _at(d, s * 14.0, 2.6), _at(d, 0.0, 2.6))
		if hit == Vector3.INF:
			continue
		var outw := (Vector3(_side.x, 0, _side.y) * s).normalized()
		var to := hit + outw * _rng.randf_range(1.0, 2.2)
		to.y = _ground(to.x, to.z) + 0.05
		add_child(_mi(DEBRIS.cable(hit, to, 0.5, 0.05, wire)))
		_add_sparker(to)


func _ray_ship(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.get("collider") != _ship:
		return Vector3.INF
	return hit["position"]


func _mi(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


# ---------------------------------------------------------------------------
#  Эффекты: огонь, дым, искры, маяки, пар
# ---------------------------------------------------------------------------
func _make_soft_texture() -> void:
	_soft_tex = GradientTexture2D.new()
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.5, Color(1, 1, 1, 0.5))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_soft_tex.gradient = g


## Мягкие частицы-картинки (огонь, дым, пар): растут, меняют цвет и тают
func _soft_particles(amount: int, lifetime: float, size: float, c0: Color, c1: Color,
		v_min: float, v_max: float, gravity: Vector3, additive: bool, mid: Color = Color(0, 0, 0, -1)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.gravity = gravity
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.6 if not additive else 0.15))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, c0)
	if mid.a >= 0.0:
		ramp.add_point(0.4, mid)
	ramp.set_color(ramp.get_point_count() - 1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size) * 2.0
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p


## Очаг огня: языки пламени, летящие вверх угольки, дым и (по желанию) свет
func _add_fire(pos: Vector3, size: float, with_light: bool) -> void:
	var flames := _soft_particles(int(28 * size + 10), 0.8, 0.45 * size,
		Color(1.0, 0.85, 0.45, 1.0), Color(0.45, 0.06, 0.01, 0.0), 1.0 * size, 2.2 * size, Vector3(0, 1.2, 0), true, Color(1.0, 0.42, 0.08, 0.85))
	FX.set_box(flames, Vector3(0.45, 0.05, 0.45) * size)
	flames.position = pos
	add_child(flames)
	var embers := FX.particles(Color(1.0, 0.6, 0.2, 1.0), int(16 * size + 6), 2.2, 0.025, 0.8, 2.2, Vector3(0.2, 0.9, 0), 30.0, false, true)
	var pm := embers.process_material as ParticleProcessMaterial
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	embers.position = pos
	embers.emitting = true
	add_child(embers)
	_add_smoke(pos + Vector3.UP * (1.2 * size), 0.6 * size + 0.3)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.22)
		l.light_energy = 1.6 * size
		l.omni_range = 6.0 + 4.0 * size
		l.position = pos + Vector3.UP * 0.8
		add_child(l)
		_flames.append([l, l.light_energy, _rng.randf() * 10.0])


## Столб дыма: тёмные клубы растут, светлеют и тают, ветер сносит их в сторону
func _add_smoke(pos: Vector3, size: float) -> void:
	var p := _soft_particles(30, 6.0, size, Color(0.1, 0.09, 0.1, 0.7), Color(0.45, 0.45, 0.48, 0.0), 0.8, 1.4, Vector3(0.35, 0.25, -0.1), false)
	p.position = pos
	add_child(p)


## Оборванный кабель на земле: время от времени сыплет искрами и вспыхивает
func _add_sparker(pos: Vector3) -> void:
	var sp := FX.particles(Color(1.0, 0.85, 0.5, 1.0), 22, 0.6, 0.022, 1.5, 3.5, Vector3(0, -9.8, 0), 70.0, true, true)
	sp.position = pos + Vector3.UP * 0.1
	add_child(sp)
	var l := OmniLight3D.new()
	l.light_color = Color(0.7, 0.85, 1.0)
	l.light_energy = 0.0
	l.omni_range = 3.5
	l.position = pos + Vector3.UP * 0.3
	add_child(l)
	_sparkers.append([sp, l, _rng.randf_range(0.5, 3.0)])


## Аварийный маяк: мигающий колпак, а если spin — ещё и вращающийся луч
func _add_blinker(pos: Vector3, color: Color, speed: float, spin: bool) -> void:
	var house := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.2
	cm.height = 0.18
	cm.material = DEBRIS.metal(Color(0.15, 0.15, 0.16), 0.3, 0.2, 0.0)
	house.mesh = cm
	house.position = pos
	add_child(house)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = color
	glass.emission_enabled = true
	glass.emission = color
	glass.emission_energy_multiplier = 4.0
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.is_hemisphere = true
	sm.material = glass
	dome.mesh = sm
	dome.position = pos + Vector3.UP * 0.09
	add_child(dome)
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = 5.0
	l.position = pos + Vector3.UP * 0.3
	add_child(l)
	_blinkers.append([l, glass, _rng.randf() * TAU, speed])
	if spin:
		var pivot := Node3D.new()
		pivot.position = pos + Vector3.UP * 0.15
		add_child(pivot)
		var beam := SpotLight3D.new()
		beam.light_color = color
		beam.light_energy = 5.0
		beam.spot_range = 16.0
		beam.spot_angle = 18.0
		beam.rotation.x = -0.12
		pivot.add_child(beam)
		_spinners.append(pivot)


## Пар из пробоины: бьёт струёй порывами
func _add_steam(pos: Vector3) -> void:
	var p := _soft_particles(26, 1.6, 0.5, Color(0.92, 0.95, 1.0, 0.55), Color(1, 1, 1, 0.0), 3.0, 5.0, Vector3(0.4, -0.5, 0), false)
	p.one_shot = true
	p.explosiveness = 0.2
	p.preprocess = 0.0
	p.emitting = false
	p.position = pos
	add_child(p)
	_steam.append([p, _rng.randf_range(1.0, 4.0)])


# ---------------------------------------------------------------------------
#  Надписи
# ---------------------------------------------------------------------------
func _make_labels() -> void:
	var center := _nose + _along * ship_length * 0.5
	var sign := Label3D.new()
	sign.text = "«РЖАВЫЙ БОРОВ»"
	sign.font_size = 96
	sign.outline_size = 18
	sign.modulate = Color(1.0, 0.78, 0.45)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(center.x, _ground(center.x, center.y) + 10.0, center.y)
	add_child(sign)
	var sub := Label3D.new()
	sub.text = "место крушения · база"
	sub.font_size = 48
	sub.outline_size = 12
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.position = sign.position + Vector3.DOWN * 1.1
	add_child(sub)


## Указатель к Борее
func _make_signpost(pos: Vector3) -> void:
	pos.y = _ground(pos.x, pos.z)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.3, 0.26)
	wood.roughness = 0.9
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.09
	cm.height = 2.4
	cm.material = wood
	post.mesh = cm
	post.position = pos + Vector3.UP * 1.2
	add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.4, 0.06)
	bm.material = wood
	board.mesh = bm
	board.position = pos + Vector3.UP * 2.1
	add_child(board)
	var label := Label3D.new()
	label.text = "↑ БОРЕЯ  ·  лёд и снег"
	label.font_size = 40
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = pos + Vector3.UP * 2.7
	add_child(label)


func _process(delta: float) -> void:
	_t += delta
	for b in _blinkers:
		var on := sin(_t * TAU * float(b[3]) * 0.5 + float(b[2])) > 0.2
		(b[0] as OmniLight3D).light_energy = 2.5 if on else 0.2
		(b[1] as StandardMaterial3D).emission_energy_multiplier = 5.0 if on else 0.4
	for s in _spinners:
		s.rotation.y += delta * 4.0
	for f in _flames:
		var l := f[0] as OmniLight3D
		var ph: float = f[2]
		l.light_energy = float(f[1]) * (0.85 + 0.15 * sin(_t * 11.0 + ph) + 0.1 * sin(_t * 27.0 + ph * 2.0))
	for s in _sparkers:
		var l := s[1] as OmniLight3D
		l.light_energy = maxf(l.light_energy - delta * 12.0, 0.0)
		s[2] = float(s[2]) - delta
		if float(s[2]) <= 0.0:
			s[2] = _rng.randf_range(0.6, 3.5)
			(s[0] as GPUParticles3D).restart()
			l.light_energy = 3.0
	for s in _steam:
		s[1] = float(s[1]) - delta
		if float(s[1]) <= 0.0:
			s[1] = _rng.randf_range(3.0, 7.0)
			(s[0] as GPUParticles3D).restart()
