extends Area3D
## Контрольная точка. Дрон, зашедший сюда, после поломки возрождается здесь.
## Маяк красный, пока ты тут не был, и зелёный — когда точка твоя.
## (Позже здесь же откроется лавка барыги.)

@export var title := "Контрольная точка"
@export_multiline var subtitle := "Теперь ты возродишься здесь"
@export var size := Vector3(16.0, 8.0, 14.0)
@export var respawn_offset := Vector3(0.0, 0.5, 4.0)   ## Где появиться относительно точки
@export var snap_to_terrain := true   ## Поставить на землю (на льду озера — выключить)

var _lamp_mat: StandardMaterial3D
var _light: OmniLight3D
var _activated := false
var _t := 0.0


func _ready() -> void:
	monitoring = true
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position.y = size.y * 0.5
	add_child(col)
	body_entered.connect(_on_body_entered)
	_build_beacon.call_deferred()


func _build_beacon() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain and snap_to_terrain:
		global_position.y = terrain.height_at(global_position.x, global_position.z)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.32, 0.36)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.14
	cm.height = 3.2
	cm.material = metal
	pole.mesh = cm
	pole.position = Vector3(-4.0, 1.6, 0.0)
	add_child(pole)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.25, 0.2)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.2, 0.15)
	_lamp_mat.emission_energy_multiplier = 3.0
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.material = _lamp_mat
	lamp.mesh = sm
	lamp.position = Vector3(-4.0, 3.35, 0.0)
	add_child(lamp)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.2)
	_light.light_energy = 1.2
	_light.omni_range = 6.0
	_light.position = lamp.position
	add_child(_light)


func _on_body_entered(body: Node3D) -> void:
	if body != Network.local_player or _activated:
		return
	_activated = true
	if body.has_method("set_checkpoint"):
		body.set_checkpoint(global_position + respawn_offset)
	_lamp_mat.albedo_color = Color(0.3, 1.0, 0.45)
	_lamp_mat.emission = Color(0.2, 1.0, 0.4)
	_light.light_color = Color(0.3, 1.0, 0.45)
	get_tree().call_group("level", "show_banner", title, subtitle)


func _process(delta: float) -> void:
	_t += delta
	if _light:
		_light.light_energy = 1.2 + sin(_t * (6.0 if not _activated else 2.0)) * 0.4
