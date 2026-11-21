extends Parcel
## Деталь ворот каньона («печать» со знаком). Лежит на дне Глубокого озера.
## Тяжёлая, тонет; водонепроницаемая — её можно нести под водой (с ней тонешь быстрее,
## всплываешь медленнее). Принёс к гнезду у ворот — встаёт на место (canyon_gate.gd).

const SYM := preload("res://scenes/world/gate_symbols.gd")

@export var kind := 0                 ## 0, 1, 2 — какое гнездо
@export var symbol := 0               ## знак (0…5)
var dive_ok := true                   ## игрок не роняет её в воде

const LABEL_NEAR := 4.0                ## с какого расстояния видна надпись печати


static func make(kind_id: int, title: String, sym: int, pos: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "GatePart%d" % kind_id
	body.mass = 6.0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 0.25
	col.shape = shape
	col.name = "CollisionShape3D"
	body.add_child(col)
	var label := Label3D.new()
	label.name = "ValueLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.outline_size = 10
	body.add_child(label)
	body.set_script(load("res://scenes/world/gate_part.gd"))
	body.set("kind", kind_id)
	body.set("symbol", sym)
	body.set("display_name", title)
	body.set("base_price", 1)
	body.set("weight", 1)
	body.set("fragility", 0.0)
	body.set("label_height", 0.9)
	body.set("lost_y", -40.0)
	body.set("soak_percent", 0.0)
	body.position = pos
	return body


func _ready() -> void:
	super._ready()
	add_to_group("gate_part")
	# старый каменный диск, обросший илом, с тусклой ледяной кромкой и выбитым знаком.
	# Ничего не светится — печати надо искать на дне самим.
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.2, 0.22, 0.24)
	stone.roughness = 0.9
	stone.metallic = 0.1
	var disk := CylinderMesh.new()
	disk.top_radius = 0.5
	disk.bottom_radius = 0.5
	disk.height = 0.22
	disk.radial_segments = 16
	disk.material = stone
	var mi := MeshInstance3D.new()
	mi.mesh = disk
	add_child(mi)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.46
	rim.outer_radius = 0.56
	rim.rings = 16
	rim.ring_segments = 6
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.32, 0.42, 0.5)
	ice.roughness = 0.6
	rim.material = ice
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim
	add_child(rmi)
	var sm := SYM.mesh(symbol, 0.3, 0.04)
	var sym_mat := StandardMaterial3D.new()
	sym_mat.albedo_color = (SYM.COLORS[symbol] as Color).darkened(0.55)
	sym_mat.roughness = 0.8
	sym_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for face in [1.0, -1.0]:
		var smi := MeshInstance3D.new()
		smi.mesh = sm
		smi.material_override = sym_mat
		smi.position = Vector3(0, 0.125 * face, 0)
		smi.rotation = Vector3(-PI * 0.5 * face, 0, 0)
		add_child(smi)


## Не плавает — тонет и ложится на дно
func _float_in_water(_delta: float) -> bool:
	return false


func _process(delta: float) -> void:
	super._process(delta)
	# надпись — только вблизи (или когда несут): издалека печать не видна
	if value_label:
		var me: Node3D = Network.local_player if is_instance_valid(Network.local_player) else null
		value_label.visible = is_carried() or (me != null and me.global_position.distance_to(global_position) < LABEL_NEAR)


func _update_label() -> void:
	if value_label == null:
		return
	value_label.text = "%s\nзнак: %s" % [display_name, SYM.NAMES[symbol]]
	value_label.modulate = SYM.COLORS[symbol]
