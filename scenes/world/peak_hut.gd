extends "res://scenes/world/camp_cabin.gd"
## Шаг 73: приют на Пике — маленькая бревенчатая избушка (8×6.4 м) на полке тропы, на плато и на Плече.
## Сруб, окна, крыша со снегом — как у избы «Борея-4» (camp_cabin.gd), внутри — своё:
##   чугунная печка с трубой (греет, светится), нары, стол с лавкой, полка с банками, фонарь, ящик с дровами.
## Двора с частоколом нет — только контрольная точка у крыльца.
## Огонь в печке можно гасить/разжигать (fire 0…1) — на Плече ночью его поддерживают дровами (mountain_night.gd).

var stove_pos := Vector3.ZERO
var fire := 1.0                    ## 0 — погасла, 1 — горит вовсю
var with_checkpoint := true

var _stove_light: OmniLight3D
var _glow: StandardMaterial3D
var _flames: Array = []
var _heat: Node3D
var _lamp: OmniLight3D


func setup_hut(title: String, sub: String) -> void:
	HALF_W = 4.0
	HALF_D = 3.2
	WIN_Z = [0.0]
	YARD_R = 7.0
	sign_text = title
	cp_title = title.get_slice("\n", 0)
	cp_sub = sub


func in_yard(_p: Vector3) -> bool:
	return false


func _interior() -> void:
	var b := B()
	# печка у задней стены
	var sz := -HALF_D + 0.75
	stove_pos = L(0, 0.0, sz)
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.45, 0.1)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.38, 0.06)
	_glow.emission_energy_multiplier = 3.0
	waste.box(Vector3(1.4, 0.06, 1.2), L(0, 0.03, sz + 0.1), b, "cab_stone")
	waste.box(Vector3(0.75, 0.62, 0.62), L(0, 0.52, sz), b, "iron")
	waste.box(Vector3(0.82, 0.05, 0.68), L(0, 0.85, sz), b, "iron")
	for q in [-1.0, 1.0]:
		for w in [-1.0, 1.0]:
			waste.box(Vector3(0.06, 0.22, 0.06), L(q * 0.3, 0.11, sz + w * 0.24), b, "iron")
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.36, 0.26, 0.03)
	door.mesh = dm
	door.material_override = _glow
	door.transform = Transform3D(b, L(0, 0.5, sz + 0.32))
	add_child(door)
	waste.beam(L(0, 0.88, sz - 0.1), L(0, WALL_H + 1.8, sz - 0.1), 0.08, "iron", 8)
	waste.solid_box(L(0, 0.45, sz), Vector3(0.8, 0.9, 0.66), b, waste._solids)
	# чайник на печке
	waste.cyl(0.11, 0.14, 0.18, L(0.15, 0.97, sz), b, "barrel", 10)
	waste.beam(L(0.27, 0.98, sz), L(0.36, 1.06, sz), 0.015, "iron", 4)
	# огонёк за дверцей
	for k in 3:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.6, 0.15)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.45, 0.08)
		fm.emission_energy_multiplier = 4.0
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.22
		var fl := MeshInstance3D.new()
		fl.mesh = sm
		fl.material_override = fm
		fl.position = L(-0.1 + k * 0.1, 0.45, sz + 0.28)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		_flames.append([fm, fl, float(k) * 2.1])
	_stove_light = OmniLight3D.new()
	_stove_light.light_color = Color(1.0, 0.55, 0.25)
	_stove_light.light_energy = 2.0
	_stove_light.omni_range = 7.0
	_stove_light.position = L(0, 0.7, sz + 0.9)
	add_child(_stove_light)
	_heat = Node3D.new()
	_heat.name = "Stove"
	_heat.add_to_group("heat_source")
	_heat.position = L(0, 0.4, sz + 0.7)
	add_child(_heat)
	fire_pos = _heat.position
	# ящик с дровами у печки
	waste.box(Vector3(0.7, 0.4, 0.5), L(1.1, 0.2, sz + 0.05), b, "wood_dark")
	for k in 4:
		waste.beam(L(0.85 + k * 0.17, 0.43, sz - 0.15), L(0.85 + k * 0.17, 0.43, sz + 0.25), 0.07, "cab_logs", 7)
	# коврик и две подушки у печки — посидеть
	waste.box(Vector3(2.4, 0.02, 1.6), L(0, 0.07, sz + 1.6), b, "rug_red")
	waste.box(Vector3(2.0, 0.025, 1.2), L(0, 0.075, sz + 1.6), b, "rug_gold")
	var fc := L(0, 0, sz + 0.4)
	var i := 0
	for deg in [-35.0, 35.0]:
		var a := deg_to_rad(deg)
		var p := fc + r * sin(a) * 1.6 + u * cos(a) * 1.6
		var to_fire := fc - p
		to_fire.y = 0.0
		to_fire = to_fire.normalized()
		var sbasis := Basis(to_fire.cross(Vector3.UP).normalized(), Vector3.UP, -to_fire)
		waste.box(Vector3(0.6, 0.12, 0.6), p + Vector3(0, 0.15, 0), sbasis, ["rug_blue", "blanket"][i])
		var seat := Node3D.new()
		seat.set_script(SEAT)
		seat.name = "Seat%d" % i
		seat.position = p + Vector3(0, 0.1, 0)
		seat.set("face", to_fire)
		add_child(seat)
		seats.append(seat)
		i += 1
	# нары у левой стены
	var bx := -HALF_W + 0.62
	for lv in [[0.35, "blanket"], [1.45, "blanket2"]]:
		var ly: float = lv[0]
		waste.box(Vector3(1.0, 0.2, 2.4), L(bx, ly, 0.3), b, "wood_dark")
		waste.box(Vector3(0.92, 0.14, 2.3), L(bx, ly + 0.17, 0.3), b, lv[1])
		waste.box(Vector3(0.7, 0.12, 0.45), L(bx, ly + 0.3, -0.6), b, "pillow")
	for sz2 in [-0.9, 1.5]:
		for sx in [-0.45, 0.45]:
			waste.box(Vector3(0.08, 2.0, 0.08), L(bx + sx, 1.0, sz2), b, "wood_dark")
	waste.solid_box(L(bx, 1.0, 0.3), Vector3(1.05, 2.0, 2.5), b, waste._solids)
	# стол с лавкой у правой стены
	var tx := HALF_W - 0.75
	waste.box(Vector3(0.9, 0.07, 1.6), L(tx, 0.78, 0.6), b, "wood")
	for sz3 in [-0.65, 0.65]:
		waste.box(Vector3(0.07, 0.76, 0.07), L(tx, 0.38, 0.6 + sz3), b, "wood_dark")
	waste.box(Vector3(0.32, 0.06, 1.5), L(tx - 0.75, 0.45, 0.6), b, "wood")
	waste.solid_box(L(tx - 0.3, 0.42, 0.6), Vector3(1.5, 0.84, 1.6), b, waste._solids)
	waste.cyl(0.05, 0.045, 0.1, L(tx + 0.1, 0.86, 0.3), b, "iron", 8)
	waste.cyl(0.13, 0.13, 0.015, L(tx - 0.1, 0.82, 0.9), b, "cream", 12)
	# полка с банками
	waste.box(Vector3(0.28, 0.05, 1.2), L(HALF_W - 0.35, 1.7, -1.8), b, "wood")
	for j in 3:
		waste.cyl(0.07, 0.07, 0.2, L(HALF_W - 0.35, 1.83, -2.2 + j * 0.4), b, ["jar_r", "jar_y", "iron"][j], 8)
	# фонарь под потолком
	waste.beam(L(0.8, WALL_H, 0.8), L(0.8, WALL_H - 0.5, 0.8), 0.015, "iron", 4)
	waste.cyl(0.04, 0.16, 0.12, L(0.8, WALL_H - 0.55, 0.8), b, "iron", 10)
	waste.sph(0.09, L(0.8, WALL_H - 0.64, 0.8), b, "lamp", 8)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.78, 0.48)
	_lamp.light_energy = 1.0
	_lamp.omni_range = 6.0
	_lamp.position = L(0.8, WALL_H - 0.8, 0.8)
	add_child(_lamp)


func _decor() -> void:
	var bw := -HALF_D + 0.2
	_framed(D.painting(0), L(-2.3, 1.7, bw + 0.02), Vector2(0.8, 0.6), "wood_dark")
	_herbs(L(1.0, 2.85, bw + 0.08), L(3.4, 2.85, bw + 0.08), 4)


func _yard() -> void:
	if not with_checkpoint:
		return
	var cp := Area3D.new()
	cp.set_script(CHECKPOINT)
	cp.name = "HutCheckpoint"
	cp.set("snap_to_terrain", false)
	cp.set("size", Vector3(18.0, 8.0, 18.0))
	var cpp := L(0, 0, HALF_D + 2.5)
	cpp.y = waste.ground(cpp.x, cpp.z)
	cp.set("respawn_offset", (L(0, 0.6, 0.6) - cpp))
	cp.set("title", cp_title)
	cp.set("subtitle", cp_sub)
	cp.position = cpp
	add_child(cp)


## Огонь в печке (0 — погасла)
func set_fire(k: float) -> void:
	fire = clampf(k, 0.0, 1.0)
	var on := fire > 0.01
	if _heat:
		if on and not _heat.is_in_group("heat_source"):
			_heat.add_to_group("heat_source")
		elif not on and _heat.is_in_group("heat_source"):
			_heat.remove_from_group("heat_source")


func _process(delta: float) -> void:
	_t += delta
	var fl := 0.8 + 0.2 * sin(_t * 7.0) + 0.1 * sin(_t * 13.3)
	var k := clampf(fire * 1.5, 0.0, 1.0)
	if _stove_light:
		_stove_light.light_energy = 2.0 * fl * k
	if _glow:
		_glow.emission_energy_multiplier = (2.0 + 1.0 * sin(_t * 9.0)) * k
	for e in _flames:
		var m: StandardMaterial3D = e[0]
		var mi: MeshInstance3D = e[1]
		mi.visible = fire > 0.01
		m.emission_energy_multiplier = (3.0 + 1.5 * sin(_t * 9.0 + float(e[2]))) * k
		mi.scale = Vector3(1.0, (0.7 + 0.3 * sin(_t * 8.0 + float(e[2]))) * (0.4 + 0.6 * k), 1.0)


func _physics_process(delta: float) -> void:
	if fire > 0.2:
		super._physics_process(delta)
