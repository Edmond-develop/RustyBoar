extends Node
## Оптимизация уровня (ставится уровнем после постройки мира):
##  * мелкое и среднее вдали не рисуется (дальность видимости по размеру предмета);
##    крошки (заклёпки, камушки) не отбрасывают тень;
##  * лампы и огни плавно гаснут вдали (их свет там всё равно не виден за туманом);
##  * постоянные эффекты-частицы вдали прячутся (и не считаются);
##  * ловушки, гейзеры, сосульки, льдины далеко от всех дронов засыпают и не нагружают физику;
##    подходит кто-то ближе — просыпаются (у гейзеров и льдин ход — по общему времени, ничего не сбивается).
## Дроны, их детали и то, что появляется позже (снаряды, осколки), не трогаем.
## Шаг 74: ещё —
##  * простые фигуры (цилиндры, шары) по умолчанию из 64 граней — мелким хватает 8–16 (меньше треугольников);
##  * крупное (20…1500 м) без дальности видимости — не рисуется дальше 600…1600 м (там всё равно туман);
##    так на горе не рисуются, например, дно озера и торосы Ледяной реки в 2 км.

const SLEEP_SCRIPTS := ["icicle.gd", "geyser.gd", "floe.gd", "crystal_pillar.gd", "ice_spikes.gd",
	"spike_trap.gd", "boulder_spawner.gd", "falling_ice.gd"]
const SLEEP_DIST := 85.0
const FX_DIST := 75.0

var level: Node
var _sleepers: Array[Node3D] = []
var _fx: Array[GPUParticles3D] = []
var _tick := 0.0
var _phase := 0
var stats := {}


func _ready() -> void:
	_tune.call_deferred()


func _tune() -> void:
	if level == null:
		level = get_parent()
	# детализацию скал (у моделей есть упрощённые версии) снижать пораньше — вдали не видно разницы
	get_viewport().mesh_lod_threshold = 3.0
	var culled := 0
	var unshadowed := 0
	for n in level.find_children("*", "GeometryInstance3D", true, false):
		if _skip(n):
			continue
		var g := n as GeometryInstance3D
		if g is GPUParticles3D:
			var p := g as GPUParticles3D
			if p.visibility_range_end <= 0.0:
				p.visibility_range_end = FX_DIST
				p.visibility_range_end_margin = 8.0
			if not p.one_shot:
				_fx.append(p)
			continue
		if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0:
			continue
		var s := _size(g)
		if s <= 0.0:
			continue
		var end := 0.0
		if s < 0.6:
			end = 45.0
		elif s < 2.0:
			end = 80.0
		elif s < 6.0:
			end = 130.0
		elif s < 20.0:
			end = 220.0
		if end > 0.0:
			g.visibility_range_end = end
			g.visibility_range_end_margin = end * 0.1
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			culled += 1
		if s < 0.6 and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			unshadowed += 1
	var far := 0
	for n2 in level.find_children("*", "GeometryInstance3D", true, false):
		if _skip(n2) or n2.is_in_group("no_far_cull"):
			continue
		var g2 := n2 as GeometryInstance3D
		_lowpoly(g2)
		if g2 is GPUParticles3D or g2.visibility_range_end > 0.0 or g2.visibility_range_begin > 0.0:
			continue
		if _in_terrain(g2):
			continue
		var s2 := _size(g2)
		if s2 >= 20.0 and s2 < 1500.0:
			g2.visibility_range_end = clampf(s2 * 2.5, 600.0, 1600.0)
			g2.visibility_range_end_margin = 40.0
			far += 1
	var lights := 0
	for l in level.find_children("*", "Light3D", true, false):
		if _skip(l) or l is DirectionalLight3D:
			continue
		var lt := l as Light3D
		if not lt.distance_fade_enabled:
			lt.distance_fade_enabled = true
			lt.distance_fade_begin = 45.0
			lt.distance_fade_length = 12.0
			lt.distance_fade_shadow = 30.0
			lights += 1
	for n in level.find_children("*", "", true, false):
		if _skip(n):
			continue
		var sc: Script = n.get_script()
		if sc != null and SLEEP_SCRIPTS.has(sc.resource_path.get_file()) and n is Node3D:
			_sleepers.append(n as Node3D)
	stats = {"culled": culled, "unshadowed": unshadowed, "lights": lights, "fx": _fx.size(), "sleepers": _sleepers.size(), "far": far}


## Цилиндры/шары/кольца с лишними гранями — по размеру (мелким — 8, средним — 16, крупным — 32)
func _lowpoly(g: GeometryInstance3D) -> void:
	var m: Mesh = null
	if g is MeshInstance3D:
		m = (g as MeshInstance3D).mesh
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		m = (g as MultiMeshInstance3D).multimesh.mesh
	if m == null or not (m is PrimitiveMesh) or m.has_meta("lowpoly"):
		return
	m.set_meta("lowpoly", true)
	if m is CylinderMesh:
		var c := m as CylinderMesh
		var r := maxf(c.top_radius, c.bottom_radius)
		var want := 8 if r < 0.25 else (16 if r < 1.5 else 32)
		if c.radial_segments > want:
			c.radial_segments = want
		if c.rings > 1 and c.height < 6.0:
			c.rings = 1
	elif m is SphereMesh:
		var sp := m as SphereMesh
		var want2 := 10 if sp.radius < 0.25 else (18 if sp.radius < 1.5 else 32)
		if sp.radial_segments > want2:
			sp.radial_segments = want2
			sp.rings = maxi(want2 / 2, 4)
	elif m is TorusMesh:
		var tm := m as TorusMesh
		if tm.rings > 24:
			tm.rings = 24
		if tm.ring_segments > 10:
			tm.ring_segments = 10
	elif m is CapsuleMesh:
		var cm := m as CapsuleMesh
		if cm.radial_segments > 16:
			cm.radial_segments = 16
			cm.rings = mini(cm.rings, 6)


func _in_terrain(n: Node) -> bool:
	var p := n
	while p != null and p != level:
		if p.is_in_group("terrain"):
			return true
		p = p.get_parent()
	return false


func _skip(n: Node) -> bool:
	var p := n
	while p != null and p != level:
		if p.is_in_group("player") or p.is_in_group("limb_part") or p.name == "Players" or p.name == "LimbParts":
			return true
		p = p.get_parent()
	return false


## Самая длинная сторона предмета в мире (м)
func _size(g: GeometryInstance3D) -> float:
	var ab := g.get_aabb()
	if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		ab = (g as MultiMeshInstance3D).multimesh.get_aabb()
	var sc := g.global_basis.get_scale()
	return maxf(ab.size.x * absf(sc.x), maxf(ab.size.y * absf(sc.y), ab.size.z * absf(sc.z)))


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var who: Array[Vector3] = []
	for d in get_tree().get_nodes_in_group("player"):
		who.append((d as Node3D).global_position)
	var cam := get_viewport().get_camera_3d()
	if cam:
		who.append(cam.global_position)
	if who.is_empty():
		return
	# по кусочку за раз, чтобы не было рывков
	_phase = (_phase + 1) % 4
	for i in range(_phase, _sleepers.size(), 4):
		var n := _sleepers[i]
		if not is_instance_valid(n):
			continue
		var near := _near(n.global_position, who, SLEEP_DIST)
		var want := Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
		if n.process_mode != want:
			n.process_mode = want
	for i in range(_phase, _fx.size(), 4):
		var p := _fx[i]
		if not is_instance_valid(p):
			continue
		var cam_near := cam == null or p.global_position.distance_to(cam.global_position) < FX_DIST + 10.0
		if p.visible != cam_near:
			p.visible = cam_near


static func _near(p: Vector3, who: Array[Vector3], r: float) -> bool:
	for w in who:
		if p.distance_squared_to(w) < r * r:
			return true
	return false
