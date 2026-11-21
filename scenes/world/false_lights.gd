extends Node3D
## Ложные огни Снежной пустоши: в белой мгле за скрытыми трещинами мерцают оранжевые огоньки —
## точь-в-точь фонарики вешек. Пойдёшь на такой — уйдёшь с тропы прямо на трещину.
## Вблизи (ближе FADE_NEAR м) огонёк тает и появляется снова только через RETURN_TIME с.
## Видны только в густой метели. У каждого игрока свои (это только картинка).

const W := preload("res://scenes/world/waste_layout.gd")
const FADE_NEAR := 13.0
const RETURN_TIME := 30.0
const COUNT := 10

var storm: Node                     ## waste_storm.gd — сила метели
var lights: Array = []              ## [узел, материал, свет, основа, фаза, скрыт_до]
var _t := 0.0


func _ready() -> void:
	var ter = get_tree().get_first_node_in_group("terrain")
	var picked := 0
	var i := 0
	for cr in W.cracks():
		i += 1
		if picked >= COUNT:
			break
		var a: Vector2 = cr[0]
		var b: Vector2 = cr[1]
		var c := (a + b) * 0.5
		if W.storm(c.y) < 0.75:
			continue
		# огонёк — за трещиной, если смотреть с тропы
		var pp := W.point_at(W.nearest_s(c.x, c.y))
		if c.distance_to(pp) > 34.0:
			continue                 # дальше в мгле огонька всё равно не видно
		var away := (c - pp).normalized()
		var q := c + away * (float(cr[2]) + 4.0)
		var y: float = (ter.height_at(q.x, q.y) if ter else W.base_y(q.y)) + 2.9
		_make(Vector3(q.x, y, q.y), float(i) * 1.37)
		picked += 1


func _make(pos: Vector3, phase: float) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.6, 0.2, 0.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.12)
	m.emission_energy_multiplier = 3.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var s := SphereMesh.new()
	s.radius = 0.11
	s.height = 0.22
	s.radial_segments = 8
	s.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	# ореол: туман на него не действует (виден дальше настоящих фонарей — потому и манит)
	var hm := StandardMaterial3D.new()
	hm.albedo_texture = _glow_tex()
	hm.albedo_color = Color(1.0, 0.62, 0.25, 0.0)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.disable_fog = true
	hm.no_depth_test = false
	var hq := QuadMesh.new()
	hq.size = Vector2(1.4, 1.4)
	var halo := MeshInstance3D.new()
	halo.mesh = hq
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 1.3
	l.omni_range = 7.0
	l.shadow_enabled = false
	n.add_child(l)
	lights.append([n, m, l, pos, phase, -1.0, hm])


static func _glow_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.18, Color(1, 1, 1, 0.75))
	g.add_point(0.45, Color(1, 1, 1, 0.18))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _process(delta: float) -> void:
	_t += delta
	var me = Network.local_player
	var st: float = storm.get("intensity") if storm else 1.0
	for e in lights:
		var n: Node3D = e[0]
		var m: StandardMaterial3D = e[1]
		var l: OmniLight3D = e[2]
		var base: Vector3 = e[3]
		var ph: float = e[4]
		# медленно плывёт и покачивается, как фонарь на ветру
		n.position = base + Vector3(sin(_t * 0.23 + ph) * 1.6, sin(_t * 1.7 + ph) * 0.12, cos(_t * 0.19 + ph * 2.0) * 1.6)
		var vis := smoothstep(0.55, 0.85, st)
		if me and is_instance_valid(me):
			var d: float = (me.global_position - n.global_position).length()
			if d < FADE_NEAR and e[5] < _t:
				e[5] = _t + RETURN_TIME          # подошёл — тает
		if e[5] > _t:
			vis = 0.0
		var cur := m.albedo_color.a
		cur = move_toward(cur, vis, delta * (0.8 if vis < cur else 0.3))
		var flick := 0.85 + 0.15 * sin(_t * 9.0 + ph * 3.0)
		m.albedo_color.a = cur
		m.emission_energy_multiplier = 3.2 * cur * flick
		l.light_energy = 1.3 * cur * flick
		n.visible = cur > 0.01
		var hm: StandardMaterial3D = e[6]
		var far := 1.0
		if me and is_instance_valid(me):
			far = exp(-(me.global_position - n.global_position).length() * 0.028)
		hm.albedo_color.a = cur * flick * (0.25 + 0.75 * far)
