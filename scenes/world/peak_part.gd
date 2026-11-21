extends Parcel
## Шаг 74: детали механизмов Пика — у каждой своя подробная модель (не коробка с цилиндром):
##   шестерни 12/16/20/24/28 зубьев (сплошная, на 4 спицах, на 5 изогнутых, на 6 спицах с болтами, с окнами),
##   зажим троса (две губки на шарнире, пружины, болты, кусок троса), рычаг сцепления (изогнутая ручка,
##   резиновая рукоять, зубчатый сектор, красный набалдашник), гири 10/15/20/25/35 кг (чугун, ручка, клеймо),
##   манометр (латунь, стекло, шкала с красной зоной, стрелка), маховик вентиля (красный, спицы).
## Ставятся в гнёзда механизмов (mountain_mech.gd) — вставить → повернуть → закрутить, со звуком и искрами.
## Носится как обычная посылка; упала с горы — возвращается домой (home).

const MAT_KEYS := ["steel", "brass", "iron", "rust", "paint_r", "paint_b", "paint_g", "rubber", "glass", "white", "cable", "dark"]

@export var kind := ""                ## gear12…gear28, clamp, lever, w10…w35, gauge, valve
var home := Vector3.ZERO
var teeth := 0
var mass_kg := 0
var spin_node: Node3D                 ## что крутится в механизме (у шестерни — она вся)
var _beam: MeshInstance3D
var _glint: OmniLight3D
static var _mats := {}


static func make(k: String, title: String, pos: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Part_" + k
	body.mass = 3.0 if k.begins_with("w") else 2.0
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = _shape_for(k)
	body.add_child(col)
	var label := Label3D.new()
	label.name = "ValueLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	label.outline_size = 9
	label.visibility_range_end = 30.0
	body.add_child(label)
	body.set_script(load("res://scenes/world/peak_part.gd"))
	body.set("kind", k)
	body.set("display_name", title)
	body.set("base_price", 1)
	body.set("weight", 2 if k.begins_with("w") and int(k.substr(1)) >= 25 else 1)
	body.set("fragility", 0.0)
	body.set("label_height", 0.75)
	body.set("home", pos)
	body.position = pos
	return body


static func _shape_for(k: String) -> Shape3D:
	if k.begins_with("gear"):
		var r := int(k.substr(4)) * 0.025 + 0.03
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = 0.14
		return c
	if k.begins_with("w"):
		var m := int(k.substr(1))
		var s := 0.1 + m * 0.0034
		var b := BoxShape3D.new()
		b.size = Vector3(s * 2.0, s * 1.8, s * 2.0)
		return b
	var bx := BoxShape3D.new()
	match k:
		"clamp": bx.size = Vector3(0.5, 0.3, 0.32)
		"lever": bx.size = Vector3(0.9, 0.22, 0.22)
		"gauge": bx.size = Vector3(0.34, 0.34, 0.16)
		"valve": bx.size = Vector3(0.5, 0.5, 0.14)
		_: bx.size = Vector3(0.4, 0.3, 0.4)
	return bx


func _ready() -> void:
	super._ready()
	add_to_group("peak_part")
	lost_y = home.y - 30.0
	if kind.begins_with("gear"):
		teeth = int(kind.substr(4))
	if kind.begins_with("w"):
		mass_kg = int(kind.substr(1))
	spin_node = Node3D.new()
	spin_node.name = "Model"
	add_child(spin_node)
	_build_model()
	# столб света — видно издалека, где лежит
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.78, 0.35, 0.18)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.5
	cyl.height = 60.0
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.material = bm
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visibility_range_end = 400.0
	add_child(_beam)
	_glint = OmniLight3D.new()
	_glint.light_color = Color(1.0, 0.8, 0.45)
	_glint.light_energy = 0.7
	_glint.omni_range = 3.0
	_glint.distance_fade_enabled = true
	_glint.distance_fade_begin = 30.0
	_glint.distance_fade_length = 10.0
	add_child(_glint)


func _process(delta: float) -> void:
	super._process(delta)
	var show := not is_delivered and not is_held
	_beam.visible = show
	_glint.visible = show
	value_label.visible = not is_delivered
	if show:
		_beam.global_position = global_position + Vector3(0, 30.0, 0)


## Вернуть домой (упала в пропасть) — хост
func server_return_to_path() -> void:
	if not multiplayer.is_server() or is_carried() or is_delivered:
		return
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, home + Vector3.UP * 0.4)
	if Network.is_online():
		_net_state.rpc(global_position, quaternion)


## Хост: снять со «сдана» и отдать в руки (сняли деталь с механизма)
func server_take_back(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_undeliver.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _undeliver(peer_id: int) -> void:
	is_delivered = false
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	_set_holders([peer_id])


func _update_label() -> void:
	if value_label == null:
		return
	value_label.text = display_name
	value_label.modulate = Color(1.0, 0.85, 0.5)


# ---------------------------------------------------------------------------
#  Модели
# ---------------------------------------------------------------------------

static func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"steel":
			m.albedo_color = Color(0.62, 0.64, 0.68)
			m.metallic = 0.85
			m.roughness = 0.32
		"brass":
			m.albedo_color = Color(0.78, 0.6, 0.28)
			m.metallic = 0.9
			m.roughness = 0.28
		"iron":
			m.albedo_color = Color(0.17, 0.17, 0.18)
			m.metallic = 0.6
			m.roughness = 0.62
		"rust":
			m.albedo_color = Color(0.46, 0.24, 0.14)
			m.metallic = 0.45
			m.roughness = 0.8
		"paint_r":
			m.albedo_color = Color(0.78, 0.13, 0.1)
			m.metallic = 0.25
			m.roughness = 0.45
		"paint_b":
			m.albedo_color = Color(0.16, 0.3, 0.55)
			m.metallic = 0.35
			m.roughness = 0.45
		"paint_g":
			m.albedo_color = Color(0.2, 0.42, 0.26)
			m.metallic = 0.3
			m.roughness = 0.5
		"rubber":
			m.albedo_color = Color(0.07, 0.07, 0.07)
			m.roughness = 0.92
		"glass":
			m.albedo_color = Color(0.8, 0.9, 1.0, 0.25)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic_specular = 1.0
		"white":
			m.albedo_color = Color(0.93, 0.91, 0.84)
			m.roughness = 0.6
		"cable":
			m.albedo_color = Color(0.3, 0.3, 0.32)
			m.metallic = 0.7
			m.roughness = 0.5
		"dark":
			m.albedo_color = Color(0.05, 0.05, 0.06)
			m.roughness = 0.7
		"glow_r":
			m.albedo_color = Color(1.0, 0.25, 0.15)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.2, 0.1)
			m.emission_energy_multiplier = 2.0
		"glow_g":
			m.albedo_color = Color(0.3, 1.0, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.2, 1.0, 0.35)
			m.emission_energy_multiplier = 2.5
		"glow_y":
			m.albedo_color = Color(1.0, 0.75, 0.2)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.7, 0.15)
			m.emission_energy_multiplier = 2.0
	_mats[key] = m
	return m


func _build_model() -> void:
	var mb := ModelBuilder.new()
	if kind.begins_with("gear"):
		gear_model(mb, teeth)
	elif kind.begins_with("w"):
		weight_model(mb, mass_kg)
	else:
		match kind:
			"clamp": clamp_model(mb)
			"lever": lever_model(mb)
			"gauge": gauge_model(mb)
			"valve": valve_model(mb)
	mb.commit(spin_node, mat)


## Шестерня: ось — local Y (лежит плашмя), лицо сверху. Свой узор у каждой.
static func gear_model(mb: ModelBuilder, n: int) -> void:
	var rp := n * 0.025
	var key := "steel"
	match n:
		12: key = "steel"
		16: key = "brass"
		20: key = "rust"
		24: key = "paint_b"
		28: key = "paint_g"
	var th := 0.09
	var rim_in := rp - 0.08 if n >= 16 else 0.045
	mb.add(gear_ring_mesh(n, rp, th, rim_in), Transform3D.IDENTITY, key)
	# ступица и шпонка
	var hub_r := 0.075 if n < 20 else 0.09
	mb.cyl(hub_r, hub_r, th + 0.04, Vector3.ZERO, Basis.IDENTITY, "steel" if key != "steel" else "iron", 16)
	mb.cyl(0.03, 0.03, th + 0.05, Vector3.ZERO, Basis.IDENTITY, "dark", 10)
	mb.box(Vector3(0.016, th + 0.05, 0.02), Vector3(0.032, 0, 0), Basis.IDENTITY, "dark")
	match n:
		12:
			# сплошная (шестерёнка мотора-малышка): фаска, кольцо
			mb.cyl(rim_in + 0.15, rim_in + 0.15, th * 0.6, Vector3.ZERO, Basis.IDENTITY, key, 20)
		16:
			for i in 4:
				var a := TAU * i / 4.0
				var d := Vector3(cos(a), 0, sin(a))
				mb.box(Vector3(rim_in - hub_r + 0.02, th * 0.7, 0.045), d * (hub_r + rim_in) * 0.5, Basis(Vector3.UP, -a), key)
		20:
			# 5 изогнутых спиц (каждая из двух кусочков)
			for i in 5:
				var a0 := TAU * i / 5.0
				var p0 := Vector3(cos(a0), 0, sin(a0)) * hub_r
				var a1 := a0 + 0.35
				var pm := Vector3(cos(a0 + 0.2), 0, sin(a0 + 0.2)) * (hub_r + rim_in) * 0.5
				var p1 := Vector3(cos(a1), 0, sin(a1)) * (rim_in + 0.01)
				mb.beam(p0, pm, 0.022, key, 6)
				mb.beam(pm, p1, 0.022, key, 6)
		24:
			for i in 6:
				var a := TAU * i / 6.0
				var d := Vector3(cos(a), 0, sin(a))
				mb.box(Vector3(rim_in - hub_r + 0.02, th * 0.6, 0.04), d * (hub_r + rim_in) * 0.5, Basis(Vector3.UP, -a), key)
				# болты на ободе
				mb.cyl(0.016, 0.016, th + 0.03, d.rotated(Vector3.UP, TAU / 12.0) * (rim_in + 0.035), Basis.IDENTITY, "steel", 6)
		28:
			# диск с окнами (окна — тёмные вставки), полоса краски
			mb.cyl(rim_in + 0.01, rim_in + 0.01, th * 0.5, Vector3.ZERO, Basis.IDENTITY, key, 28)
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				var d := Vector3(cos(a), 0, sin(a))
				mb.cyl(0.07, 0.07, th * 0.55, d * (hub_r + rim_in) * 0.52, Basis.IDENTITY, "dark", 12)
	# клеймо числа зубьев — точки на ступице (n/4 штук)
	for i in n / 4:
		var a := TAU * i / float(n / 4)
		mb.box(Vector3(0.012, 0.01, 0.012), Vector3(cos(a), 0, sin(a)) * (hub_r + 0.02) + Vector3.UP * (th * 0.5 + 0.02), Basis.IDENTITY, "white")


## Венец шестерни с зубьями (эвольвента упрощённо — трапеции), ось Y, толщина th
static func gear_ring_mesh(n: int, rp: float, th: float, r_in: float) -> ArrayMesh:
	var m := 2.0 * rp / n
	var r_tip := rp + m
	var r_root := rp - 1.25 * m
	var pts: Array[Vector2] = []
	var seg := 6
	for i in n:
		var a0 := TAU * i / n
		var w := TAU / n
		# дно впадины → бок → вершина → бок
		for s in seg:
			var f := float(s) / seg
			var a := a0 + w * f
			var r: float
			if f < 0.18:
				r = r_root
			elif f < 0.38:
				r = lerpf(r_root, r_tip, (f - 0.18) / 0.2)
			elif f < 0.62:
				r = r_tip
			elif f < 0.82:
				r = lerpf(r_tip, r_root, (f - 0.62) / 0.2)
			else:
				r = r_root
			pts.append(Vector2(cos(a), sin(a)) * r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cnt := pts.size()
	var h := th * 0.5
	for i in cnt:
		var j := (i + 1) % cnt
		var a := pts[i]
		var b := pts[j]
		var ia := a.normalized() * r_in
		var ib := b.normalized() * r_in
		# верх
		_tri(st, Vector3(a.x, h, a.y), Vector3(ib.x, h, ib.y), Vector3(b.x, h, b.y), Vector3.UP)
		_tri(st, Vector3(a.x, h, a.y), Vector3(ia.x, h, ia.y), Vector3(ib.x, h, ib.y), Vector3.UP)
		# низ
		_tri(st, Vector3(a.x, -h, a.y), Vector3(b.x, -h, b.y), Vector3(ib.x, -h, ib.y), Vector3.DOWN)
		_tri(st, Vector3(a.x, -h, a.y), Vector3(ib.x, -h, ib.y), Vector3(ia.x, -h, ia.y), Vector3.DOWN)
		# наружный бок
		var e := b - a
		var nn := Vector3(e.y, 0, -e.x).normalized()
		if nn.dot(Vector3(a.x, 0, a.y)) < 0.0:
			nn = -nn
		_quad(st, Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(b.x, -h, b.y), Vector3(a.x, -h, a.y), nn)
		# внутренний бок
		var ni := -Vector3(ia.x + ib.x, 0, ia.y + ib.y).normalized()
		_quad(st, Vector3(ib.x, h, ib.y), Vector3(ia.x, h, ia.y), Vector3(ia.x, -h, ia.y), Vector3(ib.x, -h, ib.y), ni)
	# с индексами — иначе при склейке с BoxMesh/CylinderMesh (у них индексы) венец пропадает
	st.index()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# порядок обхода — по нормали (Godot: по часовой стрелке — лицо)
	var fn := (b - a).cross(c - a)
	st.set_normal(n)
	if fn.dot(n) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Гиря: чугунное тело, ручка, клеймо (белое пятно с числом рисок)
static func weight_model(mb: ModelBuilder, kg: int) -> void:
	var s := 0.1 + kg * 0.0034
	var key := "iron" if kg != 25 else "rust"
	# тело: бочонок из трёх цилиндров
	mb.cyl(s * 0.85, s, s * 0.5, Vector3(0, -s * 0.55, 0), Basis.IDENTITY, key, 18)
	mb.cyl(s, s * 0.95, s * 0.5, Vector3(0, -s * 0.05, 0), Basis.IDENTITY, key, 18)
	mb.cyl(s * 0.6, s * 0.95, s * 0.3, Vector3(0, s * 0.35, 0), Basis.IDENTITY, key, 18)
	# ручка (дуга из кусочков)
	var hr := s * 0.55
	var prev := Vector3(-hr, s * 0.45, 0)
	for i in range(1, 9):
		var a := PI * i / 8.0
		var p := Vector3(-cos(a) * hr, s * 0.45 + sin(a) * hr * 0.9, 0)
		mb.beam(prev, p, s * 0.1, key, 8)
		prev = p
	# клеймо спереди: белый круг и риски по числу десятков, красная — пятёрка
	var face := Vector3(0, -s * 0.1, s * 0.97)
	mb.cyl(s * 0.38, s * 0.38, 0.012, face, Basis(Vector3.RIGHT, PI * 0.5), "white", 16)
	var tens := kg / 10
	var five := (kg % 10) >= 5
	var total := tens + (1 if five else 0)
	for i in total:
		var x := (i - (total - 1) * 0.5) * s * 0.16
		var red := five and i == total - 1
		mb.box(Vector3(s * 0.07, s * (0.36 if not red else 0.2), 0.01), face + Vector3(x, 0, 0.01), Basis.IDENTITY, "paint_r" if red else "dark")
	# низ: квадратное основание
	mb.box(Vector3(s * 1.3, s * 0.12, s * 1.3), Vector3(0, -s * 0.8, 0), Basis.IDENTITY, key)


## Зажим троса: две губки с канавкой, шарнир, две пружины, два болта, кусок троса
static func clamp_model(mb: ModelBuilder) -> void:
	for sg in [-1.0, 1.0]:
		mb.box(Vector3(0.42, 0.08, 0.2), Vector3(0, sg * 0.075, 0), Basis.IDENTITY, "steel")
		mb.box(Vector3(0.44, 0.03, 0.22), Vector3(0, sg * 0.12, 0), Basis.IDENTITY, "paint_r")
		# канавка (тёмная полоса)
		mb.box(Vector3(0.44, 0.02, 0.05), Vector3(0, sg * 0.03, 0), Basis.IDENTITY, "dark")
	# шарнир сбоку
	mb.cyl(0.035, 0.035, 0.24, Vector3(-0.23, 0, 0), Basis(Vector3.RIGHT, PI * 0.5), "iron", 10)
	# болты с пружинами
	for bx in [0.08, 0.17]:
		mb.cyl(0.018, 0.018, 0.36, Vector3(bx, 0, 0.06), Basis.IDENTITY, "steel", 8)
		mb.cyl(0.04, 0.04, 0.03, Vector3(bx, 0.17, 0.06), Basis.IDENTITY, "iron", 6)
		mb.cyl(0.04, 0.04, 0.03, Vector3(bx, -0.17, 0.06), Basis.IDENTITY, "iron", 6)
		for k in 5:
			var tm := TorusMesh.new()
			tm.inner_radius = 0.022
			tm.outer_radius = 0.032
			tm.rings = 8
			tm.ring_segments = 4
			mb.add(tm, Transform3D(Basis.IDENTITY, Vector3(bx, 0.14 + k * 0.012, 0.06)), "steel")
	# кусок троса в канавке
	mb.cyl(0.022, 0.022, 0.7, Vector3(0, 0, -0.02), Basis(Vector3.FORWARD, PI * 0.5), "cable", 8)


## Рычаг сцепления: ось-втулка, изогнутая ручка, резиновая рукоять, зубчатый сектор, набалдашник
static func lever_model(mb: ModelBuilder) -> void:
	mb.cyl(0.07, 0.07, 0.16, Vector3(-0.36, 0, 0), Basis(Vector3.RIGHT, PI * 0.5), "iron", 14)
	mb.cyl(0.03, 0.03, 0.18, Vector3(-0.36, 0, 0), Basis(Vector3.RIGHT, PI * 0.5), "dark", 8)
	mb.beam(Vector3(-0.36, 0, 0), Vector3(0.05, 0.05, 0), 0.03, "steel", 8)
	mb.beam(Vector3(0.05, 0.05, 0), Vector3(0.3, 0.15, 0), 0.028, "steel", 8)
	# рукоять с рёбрами
	mb.beam(Vector3(0.3, 0.15, 0), Vector3(0.44, 0.2, 0), 0.04, "rubber", 10)
	for k in 4:
		var p := Vector3(0.3, 0.15, 0).lerp(Vector3(0.44, 0.2, 0), (k + 0.5) / 4.0)
		mb.cyl(0.046, 0.046, 0.012, p, ModelBuilder.basis_y(Vector3(0.14, 0.05, 0)), "rubber", 10)
	mb.sph(0.05, Vector3(0.47, 0.21, 0), Basis.IDENTITY, "paint_r", 10)
	# зубчатый сектор вокруг оси
	for i in 9:
		var a := -0.9 + i * 0.22
		var d := Vector3(cos(a), sin(a), 0)
		mb.box(Vector3(0.03, 0.03, 0.05), Vector3(-0.36, 0, 0) + d * 0.13, Basis(Vector3.BACK, a), "brass")
	mb.box(Vector3(0.2, 0.06, 0.04), Vector3(-0.3, 0.0, 0), Basis.IDENTITY, "brass")


## Манометр: латунный корпус, белая шкала, красная зона, стрелка, стекло, штуцер
static func gauge_model(mb: ModelBuilder) -> void:
	var b := Basis(Vector3.RIGHT, PI * 0.5)       # лицом вперёд (+Z)
	mb.cyl(0.16, 0.16, 0.07, Vector3.ZERO, b, "brass", 24)
	mb.cyl(0.14, 0.14, 0.01, Vector3(0, 0, 0.036), b, "white", 24)
	for i in 11:
		var a := lerpf(-2.3, 2.3, i / 10.0)
		var d := Vector3(sin(a), cos(a), 0)
		mb.box(Vector3(0.008, 0.025 if i % 5 == 0 else 0.015, 0.004), d * 0.115 + Vector3(0, 0, 0.042), Basis(Vector3.BACK, -a), "paint_r" if i >= 8 else "dark")
	mb.box(Vector3(0.008, 0.1, 0.004), Vector3(0.02, 0.04, 0.046), Basis(Vector3.BACK, -0.5), "paint_r")
	mb.cyl(0.015, 0.015, 0.01, Vector3(0, 0, 0.048), b, "dark", 8)
	mb.cyl(0.15, 0.15, 0.008, Vector3(0, 0, 0.054), b, "glass", 24)
	mb.cyl(0.03, 0.03, 0.12, Vector3(0, -0.2, 0), Basis.IDENTITY, "brass", 8)
	mb.cyl(0.045, 0.045, 0.03, Vector3(0, -0.25, 0), Basis.IDENTITY, "brass", 6)


## Маховик вентиля: обод, 5 спиц, ступица — красный чугун
static func valve_model(mb: ModelBuilder) -> void:
	var b := Basis(Vector3.RIGHT, PI * 0.5)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.19
	tm.outer_radius = 0.235
	tm.rings = 24
	tm.ring_segments = 8
	mb.add(tm, Transform3D(b, Vector3.ZERO), "paint_r")
	for i in 5:
		var a := TAU * i / 5.0
		mb.beam(Vector3.ZERO, Vector3(cos(a), sin(a), 0) * 0.2, 0.018, "paint_r", 6)
	mb.cyl(0.05, 0.05, 0.08, Vector3.ZERO, b, "iron", 12)
	mb.box(Vector3(0.03, 0.03, 0.09), Vector3.ZERO, Basis.IDENTITY, "dark")
	# ручка на ободе
	mb.cyl(0.018, 0.018, 0.12, Vector3(0.21, 0, 0.06), b, "rubber", 8)


# ---------------------------------------------------------------------------
## Сборщик: всё в один меш на материал
class ModelBuilder:
	var _st := {}

	func add(m: Mesh, xf: Transform3D, key: String) -> void:
		if not _st.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[key] = st
		for si in m.get_surface_count():
			(_st[key] as SurfaceTool).append_from(m, si, xf)

	func box(size: Vector3, pos: Vector3, b: Basis, key: String) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(m, Transform3D(b, pos), key)

	func cyl(rt: float, rb: float, h: float, pos: Vector3, b: Basis, key: String, seg := 10) -> void:
		var m := CylinderMesh.new()
		m.top_radius = rt
		m.bottom_radius = rb
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		add(m, Transform3D(b, pos), key)

	func sph(r: float, pos: Vector3, b: Basis, key: String, seg := 10) -> void:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = seg
		m.rings = maxi(seg / 2, 4)
		add(m, Transform3D(b, pos), key)

	func beam(a: Vector3, b: Vector3, r: float, key: String, seg := 6) -> void:
		var d := b - a
		if d.length() < 0.001:
			return
		cyl(r, r, d.length(), (a + b) * 0.5, basis_y(d), key, seg)

	static func basis_y(dir: Vector3) -> Basis:
		var y := dir.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		return Basis(x, y, z)

	func commit(parent: Node3D, matf: Callable) -> void:
		for key: String in _st:
			var st: SurfaceTool = _st[key]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = matf.call(key)
			parent.add_child(mi)
		_st.clear()
