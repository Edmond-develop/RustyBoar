extends Parcel
## Деталь подъёмника (шестерня, зажим троса, рычаг). Носится как лёгкая посылка.
## Над ней стоит столб света — его видно издалека, из-за стен ущелий.
## Принёс к приводу подъёмника — она встаёт на место (cable_lift.gd).

@export var kind := 0            ## 0 — шестерня, 1 — зажим, 2 — рычаг

var _beam: MeshInstance3D


static func make(kind_id: int, title: String, pos: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "LiftPart%d" % kind_id
	body.mass = 2.0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.35, 0.5)
	col.shape = box
	col.name = "CollisionShape3D"
	body.add_child(col)
	var label := Label3D.new()
	label.name = "ValueLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.outline_size = 10
	body.add_child(label)
	body.set_script(load("res://scenes/world/lift_item.gd"))
	body.set("kind", kind_id)
	body.set("display_name", title)
	body.set("base_price", 1)
	body.set("weight", 1)
	body.set("fragility", 0.0)
	body.set("label_height", 0.7)
	body.position = pos
	return body


func _ready() -> void:
	super._ready()
	add_to_group("lift_part")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.72, 0.55, 0.25)
	metal.metallic = 0.9
	metal.roughness = 0.35
	metal.emission_enabled = true
	metal.emission = Color(1.0, 0.6, 0.2)
	metal.emission_energy_multiplier = 0.35
	match kind:
		0:   # шестерня
			var disk := CylinderMesh.new()
			disk.top_radius = 0.28
			disk.bottom_radius = 0.28
			disk.height = 0.12
			disk.material = metal
			_add_mesh(disk, Vector3.ZERO, Vector3.ZERO)
			for i in 10:
				var a := TAU * i / 10.0
				var tooth := BoxMesh.new()
				tooth.size = Vector3(0.1, 0.12, 0.09)
				tooth.material = metal
				_add_mesh(tooth, Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32), Vector3(0, -a, 0))
		1:   # зажим троса
			for sgn in [-1.0, 1.0]:
				var jaw := BoxMesh.new()
				jaw.size = Vector3(0.42, 0.12, 0.14)
				jaw.material = metal
				_add_mesh(jaw, Vector3(0, sgn * 0.08, 0), Vector3.ZERO)
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.04
			bolt.bottom_radius = 0.04
			bolt.height = 0.36
			bolt.material = metal
			_add_mesh(bolt, Vector3(0.15, 0, 0), Vector3.ZERO)
		_:   # рычаг
			var rod := CylinderMesh.new()
			rod.top_radius = 0.035
			rod.bottom_radius = 0.045
			rod.height = 0.7
			rod.material = metal
			_add_mesh(rod, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			var knob := SphereMesh.new()
			knob.radius = 0.09
			knob.height = 0.18
			knob.material = metal
			_add_mesh(knob, Vector3(0.36, 0, 0), Vector3.ZERO)
	# столб света
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.75, 0.3, 0.22)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.6
	cyl.height = 70.0
	cyl.material = bm
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 1.2
	light.omni_range = 5.0
	add_child(light)


func _add_mesh(m: Mesh, pos: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	add_child(mi)


func _process(delta: float) -> void:
	super._process(delta)
	if _beam:
		_beam.visible = not is_delivered
		_beam.global_position = global_position + Vector3(0, 35.0, 0)


func _update_label() -> void:
	if value_label == null:
		return
	value_label.text = "%s\nдеталь подъёмника" % display_name
	value_label.modulate = Color(1.0, 0.8, 0.4)
