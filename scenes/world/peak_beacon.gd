extends Node3D
## Шаг 122: станция-маяк на вершине Пика (финал).
##   * решётчатая мачта 14 м, наверху вращается маяк (два красных луча) и мигает белый строб;
##   * станция из Kenney Space Kit: модуль, тарелка, антенна, генератор, бочки, контейнеры (CC0);
##   * приёмник посылки: светящиеся столбики вокруг зелёного круга и «голограмма» над ним;
##   * флаг на ветру; при доставке — луч в небо, салют, маяк вспыхивает зелёным.

const KIT := "res://assets/peak/"

var _rot: Node3D
var _strobe: OmniLight3D
var _strobe_m: StandardMaterial3D
var _holo: MeshInstance3D
var _holo_m: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_m: StandardMaterial3D
var _spots: Array = []
var _party := -1.0
var _t := 0.0
var _fw_t := 0.0
var _top := Vector3.ZERO
var _pad := Vector3.ZERO


## Модель из набора: вписать по высоте (или по большей стороне), поставить «на землю» в foot, повернуть yaw
func kit(path: String, foot: Vector3, yaw: float, size: float, by_height := false, solid := true) -> Node3D:
	if not ResourceLoader.exists(KIT + path):
		return null
	var n: Node3D = (load(KIT + path) as PackedScene).instantiate()
	var bb := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var x := Transform3D.IDENTITY
		var q: Node = mi
		while q != n:
			x = (q as Node3D).transform * x
			q = q.get_parent()
		var b2: AABB = x * mi.get_aabb()
		bb = b2 if first else bb.merge(b2)
		first = false
	var k := size / maxf(bb.size.y if by_height else maxf(bb.size.x, maxf(bb.size.y, bb.size.z)), 0.0001)
	var holder := Node3D.new()
	add_child(holder)
	holder.global_transform = Transform3D(Basis(Vector3.UP, yaw), foot)
	holder.add_child(n)
	var c := bb.get_center()
	n.transform = Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(-c.x, -bb.position.y, -c.z) * k)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bb.size * k * Vector3(0.9, 1.0, 0.9)
		cs.shape = bs
		cs.position = Vector3(0, bb.size.y * k * 0.5, 0)
		body.add_child(cs)
		holder.add_child(body)
	return holder


func _mat(c: Color, metal := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * e
	m.disable_fog = true
	return m


func _beam_to(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := (b - a).normalized()
	var bx := Basis(Quaternion(Vector3.UP, d)) if absf(d.dot(Vector3.UP)) < 0.9999 else Basis.IDENTITY
	mi.global_transform = Transform3D(bx, (a + b) * 0.5)


func _block(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos


## s — центр вершины (на земле), st — где станция, pad — приёмник посылки
func build(mtn: Node, s: Vector3, st: Vector3, pad: Vector3) -> void:
	_pad = pad
	var steel := _mat(Color(0.72, 0.74, 0.78), 0.8, 0.35)
	var dark := _mat(Color(0.16, 0.17, 0.2), 0.5, 0.5)
	var red := _mat(Color(0.85, 0.12, 0.08), 0.2, 0.45)
	var white := _mat(Color(0.92, 0.92, 0.94), 0.1, 0.5)
	# --- станция ---
	kit("kit/structure_detailed.glb", st, 0.0, 4.2, true)
	kit("kit/satelliteDish_large.glb", st + Vector3(-4.6, 0, 1.2), 0.6, 4.2, true)
	kit("kit/machine_wireless.glb", st + Vector3(3.6, 0, 1.4), -0.4, 2.0, true)
	kit("kit/machine_generator.glb", st + Vector3(3.4, 0, -1.6), 0.0, 1.5, true)
	kit("kit/barrels.glb", st + Vector3(-2.6, 0, 3.4), 0.3, 1.2, true)
	kit("station/container-tall.glb", st + Vector3(2.6, 0, 3.2), 0.0, 2.2, true)
	kit("station/container-tall.glb", st + Vector3(3.6, 0, 3.0), 0.4, 2.2, true)
	kit("kit/satelliteDish_detailed.glb", st + Vector3(0.0, 4.2, 0.0), 2.2, 1.8, true, false)
	# --- мачта маяка: решётка из четырёх ног, раскосы, площадка наверху ---
	var mb := st + Vector3(-6.5, 0.0, -2.5)
	mb.y = mtn._gy(mb.x, mb.z)
	var H := 14.0
	var legs: Array = []
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		legs.append(Vector2(cos(a), sin(a)))
	var lvl := 0.0
	while lvl < H - 0.1:
		var l2 := minf(lvl + 2.0, H)
		var w0 := lerpf(1.1, 0.45, lvl / H)
		var w1 := lerpf(1.1, 0.45, l2 / H)
		for i in 4:
			var p0: Vector2 = legs[i] * w0
			var p1: Vector2 = legs[i] * w1
			var q1: Vector2 = legs[(i + 1) % 4] * w1
			var m := red if int(lvl / 2.0) % 2 == 0 else white
			_beam_to(mb + Vector3(p0.x, lvl, p0.y), mb + Vector3(p1.x, l2, p1.y), 0.045, m)
			_beam_to(mb + Vector3(p0.x, lvl, p0.y), mb + Vector3(q1.x, l2, q1.y), 0.02, steel)
		lvl = l2
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, H, 1.8)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = mb + Vector3.UP * H * 0.5
	_block(Vector3(1.4, 0.12, 1.4), mb + Vector3.UP * H, dark)
	_top = mb + Vector3.UP * (H + 0.75)
	# вращающийся маяк: колпак, два прожектора спина к спине
	_block(Vector3(0.7, 0.9, 0.7), mb + Vector3.UP * (H + 0.5), dark)
	_rot = Node3D.new()
	add_child(_rot)
	_rot.global_position = _top
	var lamp_m := _glow(Color(1.0, 0.25, 0.15), 3.5)
	for sgn in [-1.0, 1.0]:
		var hd := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.16
		cm.height = 0.35
		hd.mesh = cm
		hd.material_override = lamp_m
		_rot.add_child(hd)
		hd.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * sgn), Vector3(0, 0, -0.25 * sgn))
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.25, 0.15)
		sp.light_energy = 12.0
		sp.spot_range = 140.0
		sp.spot_angle = 9.0
		sp.shadow_enabled = false
		sp.distance_fade_enabled = true
		sp.distance_fade_begin = 320.0
		sp.distance_fade_length = 40.0
		_rot.add_child(sp)
		sp.transform = Transform3D(Basis(Vector3.UP, 0.0 if sgn < 0 else PI) * Basis(Vector3.RIGHT, -0.12), Vector3(0, 0, -0.4 * sgn))
		_spots.append(sp)
	_strobe_m = _glow(Color(1.0, 1.0, 1.0), 1.0)
	var sb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sb.mesh = sm
	sb.material_override = _strobe_m
	add_child(sb)
	sb.global_position = _top + Vector3.UP * 0.55
	_strobe = OmniLight3D.new()
	_strobe.light_color = Color(0.9, 0.95, 1.0)
	_strobe.omni_range = 30.0
	_strobe.shadow_enabled = false
	add_child(_strobe)
	_strobe.global_position = _top + Vector3.UP * 0.6
	# --- флаг ---
	var fp := s + Vector3(-1.5, 0, 5.5)
	fp.y = mtn._gy(fp.x, fp.z)
	_beam_to(fp, fp + Vector3.UP * 5.5, 0.05, steel)
	var flag := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 1.25)
	pm.subdivide_width = 12
	pm.subdivide_depth = 6
	pm.orientation = PlaneMesh.FACE_Z
	flag.mesh = pm
	var fsh := Shader.new()
	fsh.code = """shader_type spatial;
render_mode cull_disabled;
void vertex() {
	float k = (VERTEX.x + 1.0) * 0.5;
	VERTEX.z += sin(VERTEX.x * 3.0 - TIME * 6.0) * 0.16 * k + sin(VERTEX.y * 4.0 - TIME * 4.0) * 0.04 * k;
}
void fragment() {
	vec2 u = UV;
	vec3 c = u.y < 0.5 ? vec3(0.95, 0.42, 0.08) : vec3(0.95, 0.95, 0.97);
	if (abs(u.x - 0.3) < 0.07 || abs(u.y - 0.5) < 0.09) c = vec3(0.12, 0.2, 0.55);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	EMISSION = c * 0.3;
}"""
	var fm := ShaderMaterial.new()
	fm.shader = fsh
	flag.material_override = fm
	add_child(flag)
	flag.global_position = fp + Vector3(1.05, 4.85, 0)
	# --- приёмник посылки: светящиеся столбики, «голограмма» ---
	var cyan := _glow(Color(0.35, 0.95, 1.0), 2.5)
	for i in 6:
		var a2 := i * TAU / 6.0
		var pp := pad + Vector3(cos(a2), 0, sin(a2)) * 2.9
		pp.y = mtn._gy(pp.x, pp.z)
		_beam_to(pp, pp + Vector3.UP * 0.9, 0.06, dark)
		_block(Vector3(0.16, 0.16, 0.16), pp + Vector3.UP * 0.98, cyan)
	_holo = MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 1.9
	hm.bottom_radius = 2.4
	hm.height = 2.6
	hm.cap_top = false
	hm.cap_bottom = false
	hm.radial_segments = 24
	_holo.mesh = hm
	_holo_m = StandardMaterial3D.new()
	_holo_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_holo_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_holo_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_holo_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_holo_m.albedo_color = Color(0.2, 0.9, 0.5, 0.18)
	_holo_m.disable_fog = true
	_holo.material_override = _holo_m
	_holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_holo)
	_holo.global_position = pad + Vector3.UP * 1.35
	var pl := OmniLight3D.new()
	pl.light_color = Color(0.4, 1.0, 0.6)
	pl.light_energy = 1.6
	pl.omni_range = 7.0
	add_child(pl)
	pl.global_position = pad + Vector3.UP * 1.5
	# луч в небо (включается при доставке)
	_beam = MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 2.2
	bmesh.bottom_radius = 0.6
	bmesh.height = 260.0
	bmesh.cap_top = false
	bmesh.cap_bottom = false
	_beam.mesh = bmesh
	_beam_m = _holo_m.duplicate()
	_beam_m.albedo_color = Color(0.3, 1.0, 0.55, 0.0)
	_beam.material_override = _beam_m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_beam.global_position = pad + Vector3.UP * 130.0


## Посылка доставлена — праздник
func celebrate() -> void:
	_party = 0.0
	_beam.visible = true
	for sp in _spots:
		(sp as SpotLight3D).light_color = Color(0.3, 1.0, 0.45)


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	# дальше 400 м — не крутить и не мигать (не видно)
	if cam == null or cam.global_position.distance_to(_top) > 400.0:
		return
	var party := _party >= 0.0
	_rot.rotation.y += delta * (3.5 if party else 1.6)
	var ph := fmod(_t, 1.6 if not party else 0.35)
	var on := ph < 0.08
	_strobe.light_energy = 6.0 if on else 0.0
	_strobe_m.albedo_color = Color(4.0, 4.0, 4.0) if on else Color(0.3, 0.3, 0.32)
	_holo_m.albedo_color.a = 0.12 + 0.08 * sin(_t * 2.4)
	_holo.rotation.y += delta * 0.6
	if party:
		_party += delta
		_beam_m.albedo_color.a = minf(_party * 0.3, 0.35) * (0.85 + 0.15 * sin(_t * 5.0))
		_fw_t -= delta
		if _fw_t <= 0.0 and _party < 25.0:
			_fw_t = randf_range(0.35, 0.8)
			_firework()


func _firework() -> void:
	var cols := [Color(1.0, 0.4, 0.2), Color(0.3, 1.0, 0.5), Color(0.4, 0.7, 1.0), Color(1.0, 0.9, 0.3), Color(1.0, 0.4, 0.9)]
	var c: Color = cols[randi() % cols.size()]
	var sp := FX.particles(c, 60, 1.6, 0.09, 6.0, 12.0, Vector3(0, -3, 0), 180.0, true, true)
	add_child(sp)
	sp.global_position = _pad + Vector3(randf_range(-25, 25), randf_range(35, 60), randf_range(-25, 25))
	sp.emitting = true
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 4.0
	l.omni_range = 40.0
	add_child(l)
	l.global_position = sp.global_position
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.2)
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		sp.queue_free()
		l.queue_free())
