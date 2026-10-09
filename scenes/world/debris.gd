extends StaticBody3D
## Вмёрзшие обломки: одиночные препятствия на льду разной формы.
##   0 — контейнер, вмёрзший под углом
##   1 — груда бочек
##   2 — покосившийся столб-маяк с фонарём и сосульками
##   3 — штабель ящиков

@export_enum("Контейнер", "Бочки", "Столб", "Ящики") var kind := 0
@export var seed_value := 1

static var _mats := {}


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		0:
			var c: Color = [Color(0.8, 0.35, 0.15), Color(0.2, 0.5, 0.6), Color(0.75, 0.6, 0.15)][rng.randi() % 3]
			_box(Vector3(0, 0.8, 0), Vector3(2.4, 2.4, 5.5),
				Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(0.15, 0.35)), _mat(c, 0.5))
			_snow(Vector3(0, 2.0, 0), Vector3(1.8, 0.35, 3.5))
		1:
			for i in rng.randi_range(3, 6):
				var p := Vector3(rng.randf_range(-1.2, 1.2), 0.3, rng.randf_range(-1.2, 1.2))
				var tipped := rng.randf() < 0.4
				_cyl(p + Vector3(0, 0.15 if tipped else 0.2, 0), 0.4, 1.0,
					Vector3(PI * 0.5 if tipped else 0.0, rng.randf() * TAU, 0.0), _mat(Color(0.75, 0.22, 0.15), 0.6))
		2:
			# Покосившийся столб: наклон вокруг ОСНОВАНИЯ, фонарь — на верхушке столба
			var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
			var pole_h := 5.0
			var pole := CylinderMesh.new()
			pole.top_radius = 0.1
			pole.bottom_radius = 0.14
			pole.height = pole_h
			pole.material = _mat(Color(0.2, 0.22, 0.25), 0.8)
			var pmi := MeshInstance3D.new()
			pmi.mesh = pole
			pmi.transform = Transform3D(tilt, tilt * Vector3(0, pole_h * 0.5, 0))
			add_child(pmi)
			var shape := CylinderShape3D.new()
			shape.radius = 0.14
			shape.height = pole_h
			var col := CollisionShape3D.new()
			col.shape = shape
			col.transform = pmi.transform
			add_child(col)
			# Кронштейн и плафон фонаря
			var top := tilt * Vector3(0, pole_h, 0)
			var arm := BoxMesh.new()
			arm.size = Vector3(0.08, 0.08, 0.7)
			arm.material = pole.material
			var ami := MeshInstance3D.new()
			ami.mesh = arm
			ami.transform = Transform3D(tilt, top + tilt * Vector3(0, -0.1, 0.3))
			add_child(ami)
			var lamp_pos := top + tilt * Vector3(0, -0.3, 0.62)
			var lamp := CylinderMesh.new()
			lamp.top_radius = 0.12
			lamp.bottom_radius = 0.22
			lamp.height = 0.25
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(1, 0.8, 0.45)
			lm.emission_enabled = true
			lm.emission = Color(1, 0.7, 0.3)
			lm.emission_energy_multiplier = 3.0
			lamp.material = lm
			var lmi := MeshInstance3D.new()
			lmi.mesh = lamp
			lmi.transform = Transform3D(tilt, lamp_pos)
			add_child(lmi)
			var light := OmniLight3D.new()
			light.light_color = Color(1, 0.72, 0.4)
			light.omni_range = 7.0
			light.light_energy = 1.0
			light.position = lamp_pos - Vector3(0, 0.2, 0)
			add_child(light)
			# Сосульки свисают с плафона строго вниз
			for i in 4:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.04
				cone.bottom_radius = 0.0
				cone.height = rng.randf_range(0.25, 0.6)
				cone.material = _mat(Color(0.75, 0.92, 1.0), 0.05)
				var ic := MeshInstance3D.new()
				ic.mesh = cone
				ic.position = lamp_pos + Vector3(rng.randf_range(-0.15, 0.15), -0.15 - cone.height * 0.5, rng.randf_range(-0.15, 0.15))
				add_child(ic)
			# Снег у основания
			_snow(Vector3(0, 0.0, 0), Vector3(1.4, 0.4, 1.4))
		3:
			for i in rng.randi_range(3, 5):
				var s := rng.randf_range(0.7, 1.1)
				var p := Vector3(rng.randf_range(-1.0, 1.0), s * 0.5 + (s if i >= 3 else 0.0), rng.randf_range(-1.0, 1.0))
				_box(p, Vector3.ONE * s, Vector3(0, rng.randf() * TAU, rng.randf_range(-0.1, 0.1)), _mat(Color(0.6, 0.45, 0.28), 0.9))


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var key := "%s_%s" % [c, rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = 0.4 if rough < 0.7 else 0.0
		_mats[key] = m
	return _mats[key]


func _box(pos: Vector3, size: Vector3, rot: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.rotation = rot
	add_child(col)


func _cyl(pos: Vector3, r: float, h: float, rot: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.rotation = rot
	add_child(col)


func _snow(pos: Vector3, size: Vector3) -> void:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.is_hemisphere = true
	m.material = _mat(Color(0.95, 0.97, 1.0), 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.scale = size
	add_child(mi)
