extends Node3D
## Видимые подводные течения (IceRiver.streams):
##  * в воде — поток мути и пузырьков несётся от полыньи под лёд, к соседней полынье;
##  * на поверхности полыньи, где течение начинается, — пенные полосы утягивает к краю,
##    вода «тёмная и живая»: так видно, что сюда лучше не падать;
##  * над течением лёд темнее (это делает карта глубины в ice_river.gd).


func _ready() -> void:
	var lake := get_parent()
	for s in IceRiver.streams:
		var a := Vector3(s[0], 0.0, s[1])
		var b := Vector3(s[2], 0.0, s[3])
		var dir := (b - a)
		var L := dir.length()
		dir /= L
		var w: float = s[4]
		var sp: float = s[5]
		var wy: float = lake.water_y(a.z)
		var basis := Basis.looking_at(-dir, Vector3.UP)     # локальная +Z — по течению
		# муть в потоке (под водой)
		var silt := FX.particles(Color(0.78, 0.9, 0.92, 0.55), 160, (L + 4.0) / sp, 0.035, sp * 0.85, sp * 1.1, Vector3.ZERO, 4.0, false)
		var pm := silt.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0, 0, 1)
		FX.set_box(silt, Vector3(w * 0.45, 1.0, 0.8))
		silt.local_coords = false
		silt.transform = Transform3D(basis, a + Vector3(0, wy - 1.8, 0) - dir * 2.0)
		silt.visibility_aabb = AABB(Vector3(-w, -3, -2), Vector3(w * 2, 6, L + 8))
		add_child(silt)
		silt.emitting = true
		# пузырьки, которые несёт поток
		var bub := FX.particles(Color(0.9, 0.97, 1.0, 0.7), 60, (L + 4.0) / sp, 0.05, sp * 0.8, sp, Vector3(0, 0.35, 0), 6.0, false)
		var pm2 := bub.process_material as ParticleProcessMaterial
		pm2.direction = Vector3(0, 0, 1)
		FX.set_box(bub, Vector3(w * 0.35, 0.8, 0.5))
		bub.local_coords = false
		bub.transform = Transform3D(basis, a + Vector3(0, wy - 2.2, 0) - dir * 1.5)
		bub.visibility_aabb = AABB(Vector3(-w, -3, -2), Vector3(w * 2, 6, L + 8))
		add_child(bub)
		bub.emitting = true
		# пена на поверхности полыньи: полосы тянет к краю, под лёд
		var r := _hole_radius(lake, a)
		var foam := FX.particles(Color(0.93, 0.97, 1.0, 0.4), 120, (r * 2.0) / 1.1, 0.045, 0.9, 1.3, Vector3.ZERO, 3.0, false)
		var pm3 := foam.process_material as ParticleProcessMaterial
		pm3.direction = Vector3(0, 0, 1)
		pm3.scale_min = 0.6
		pm3.scale_max = 1.4
		FX.set_box(foam, Vector3(r * 0.7, 0.01, 0.4))
		foam.local_coords = false
		foam.transform = Transform3D(basis, a + Vector3(0, wy + 0.04, 0) - dir * r * 0.85)
		add_child(foam)
		foam.emitting = true


func _hole_radius(lake: Node, p: Vector3) -> float:
	for c in lake.get("circles"):
		if Vector2(c.x - p.x, c.y - p.z).length() < 0.1:
			return c.z
	return 2.0
