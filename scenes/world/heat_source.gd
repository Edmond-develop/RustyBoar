extends Node3D
## Жаровня — бочка с огнём. Рядом с ней лёд на дроне тает в разы быстрее,
## а вмёрзший в глыбу дрон оттаивает сам. Дрон ищет жаровни по группе "heat_source".

@export var heat_radius := 6.0      ## В каком радиусе греет (м)

var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("heat_source")

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.2, 0.2)
	metal.metallic = 0.7
	metal.roughness = 0.55
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.38
	cyl.bottom_radius = 0.34
	cyl.height = 0.95
	cyl.material = metal
	barrel.mesh = cyl
	barrel.position.y = 0.475
	add_child(barrel)

	# раскалённые угли сверху
	var coal_mat := StandardMaterial3D.new()
	coal_mat.albedo_color = Color(1.0, 0.4, 0.1)
	coal_mat.emission_enabled = true
	coal_mat.emission = Color(1.0, 0.35, 0.08)
	coal_mat.emission_energy_multiplier = 4.0
	var coals := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.33
	disc.bottom_radius = 0.33
	disc.height = 0.04
	disc.material = coal_mat
	coals.mesh = disc
	coals.position.y = 0.93
	add_child(coals)

	# огонь и искры
	var fire := FX.particles(Color(1.0, 0.55, 0.15, 0.9), 40, 0.7, 0.1, 0.8, 1.6, Vector3(0, 2.0, 0), 12.0, false, true)
	FX.set_box(fire, Vector3(0.22, 0.02, 0.22))
	fire.position.y = 0.97
	add_child(fire)
	fire.emitting = true
	var sparks := FX.particles(Color(1.0, 0.8, 0.4, 1.0), 12, 1.6, 0.025, 1.0, 2.4, Vector3(0, 0.5, 0), 25.0, false, true)
	sparks.position.y = 1.0
	add_child(sparks)
	sparks.emitting = true

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.light_energy = 2.0
	_light.omni_range = heat_radius + 2.0
	_light.position.y = 1.5
	_light.shadow_enabled = false
	add_child(_light)

	# Об бочку можно удариться
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.4
	cs.height = 1.0
	shape.shape = cs
	shape.position.y = 0.5
	body.add_child(shape)
	add_child(body)

	# Надпись, чтобы было понятно, зачем она
	var tag := Label3D.new()
	tag.text = "Жаровня — греет"
	tag.font_size = 36
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.8, 0.55)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 1.9
	tag.visibility_range_end = 25.0
	add_child(tag)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 2.0 + sin(_t * 9.0) * 0.25 + sin(_t * 23.0) * 0.15
