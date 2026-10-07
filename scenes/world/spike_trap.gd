extends Node3D
## Ловушка: шипы периодически выпрыгивают из льда.
## Перед ударом плита светится красным — успей проскочить.

@export var idle_time := 2.2
@export var warning_time := 0.9
@export var up_time := 1.1
@export_range(0.0, 1.0) var phase := 0.0
@export var hit_strength := 7.0

var _t := 0.0
var _spikes: Node3D
var _plate_mat: StandardMaterial3D
var _area: Area3D
var _hit_this_cycle := false


func _ready() -> void:
	var cycle := idle_time + warning_time + up_time + 0.3
	_t = phase * cycle

	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = Color(0.2, 0.22, 0.26)
	_plate_mat.metallic = 0.7
	_plate_mat.roughness = 0.4
	_plate_mat.emission_enabled = true
	_plate_mat.emission = Color(1, 0.15, 0.1)
	_plate_mat.emission_energy_multiplier = 0.0
	var plate := CylinderMesh.new()
	plate.top_radius = 1.1
	plate.bottom_radius = 1.15
	plate.height = 0.06
	plate.material = _plate_mat
	var plate_mi := MeshInstance3D.new()
	plate_mi.mesh = plate
	plate_mi.position.y = 0.03
	add_child(plate_mi)

	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.75, 0.9, 1.0)
	spike_mat.metallic = 0.3
	spike_mat.roughness = 0.1
	_spikes = Node3D.new()
	add_child(_spikes)
	var offsets := [Vector2(0, 0), Vector2(0.55, 0.2), Vector2(-0.5, 0.3), Vector2(0.2, -0.55),
		Vector2(-0.35, -0.45), Vector2(0.6, -0.3), Vector2(-0.65, -0.05)]
	for o in offsets:
		var off: Vector2 = o
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.13
		cone.height = 1.1
		cone.radial_segments = 6
		cone.rings = 1
		cone.material = spike_mat
		var m := MeshInstance3D.new()
		m.mesh = cone
		m.position = Vector3(off.x, 0.55, off.y)
		_spikes.add_child(m)
	_spikes.position.y = -1.2

	_area = Area3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.4, 2.2)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.7
	_area.add_child(col)
	add_child(_area)


func _physics_process(delta: float) -> void:
	_t += delta
	var cycle := idle_time + warning_time + up_time + 0.3
	var t := fmod(_t, cycle)
	var target_y := -1.2
	var glow := 0.0
	var dangerous := false

	if t < idle_time:
		_hit_this_cycle = false
	elif t < idle_time + warning_time:
		glow = 2.0 + sin(_t * 30.0) * 1.5
		target_y = -1.05
	elif t < idle_time + warning_time + up_time:
		target_y = 0.0
		glow = 3.0
		dangerous = true

	_spikes.position.y = lerpf(_spikes.position.y, target_y, 25.0 * delta)
	_plate_mat.emission_energy_multiplier = glow

	if dangerous and not _hit_this_cycle:
		for body in _area.get_overlapping_bodies():
			if body.has_method("receive_hit"):
				var dir: Vector3 = body.global_position - global_position
				dir.y = 0.0
				if dir.length() < 0.1:
					dir = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
				body.receive_hit(dir.normalized(), hit_strength, global_position + Vector3.UP * 0.5)
				_hit_this_cycle = true
