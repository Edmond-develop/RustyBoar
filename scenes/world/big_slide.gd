extends Node3D
## Большая ледяная горка на катке.
##
##  * ледяная башня ~14 м из глыб; наверх ведёт широкий снежный подъём (с востока);
##  * с вершины на запад уходит извилистый ледяной жёлоб (как бобслей) с бортами,
##    виражами и опорами — он петляет и опускается на лёд катка;
##  * в жёлобе дрон разгоняется сам (до ~22 м/с к концу) и держится трассы;
##  * ощущение скорости: шире обзор, камера отъезжает, лёгкая тряска,
##    «полосы ветра» по краям экрана и снежные брызги из-под дрона;
##  * в конце жёлоб выводит на каток — по скользкому льду дрон катится ещё долго.
## Всё у каждого игрока своё (ускорение — только своему дрону), башня одинакова у всех.

const BUILDER := preload("res://scenes/world/hummock_builder.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")

## Трасса жёлоба: (x, z, высота над льдом) — с вершины башни к катку
const PATH := [
	Vector3(166.0, 880.0, 14.0), Vector3(154.0, 881.0, 13.4), Vector3(141.0, 878.0, 12.6),
	Vector3(132.0, 869.0, 11.6), Vector3(131.0, 856.0, 10.6), Vector3(124.0, 845.0, 9.6),
	Vector3(111.0, 840.0, 8.6), Vector3(99.0, 834.0, 7.5), Vector3(93.0, 822.0, 6.3),
	Vector3(85.0, 810.0, 5.0), Vector3(72.0, 803.0, 3.6), Vector3(58.0, 800.0, 2.2),
	Vector3(44.0, 799.0, 1.0), Vector3(30.0, 799.0, 0.25), Vector3(20.0, 799.0, 0.05),
]
const TOWER := Vector3(170.0, 0.0, 880.0)
const TOWER_H := 14.0
const SPEED_START := 13.0
const SPEED_END := 25.0

var _y := 0.0
var _samples: Array[Vector3] = []        ## точки трассы (мировые), шаг ~1 м
var _tangents: Array[Vector3] = []
var _dist: Array[float] = []             ## пройденное расстояние до точки
var _total := 0.0
var _spray: GPUParticles3D
var _lines: ColorRect
var _lines_mat: ShaderMaterial
var _on_chute := false


func _ready() -> void:
	_y = IceRiver.river_y(TOWER.z) + 0.02
	_sample_path()
	_build_tower()
	_build_climb()
	_build_chute()
	_build_fx()


# ---------------------------------------------------------------------------
#  Трасса
# ---------------------------------------------------------------------------
func _sample_path() -> void:
	var pts: Array[Vector3] = []
	for p in PATH:
		pts.append(Vector3(p.x, _y + p.z, p.y))
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		var seg := int(ceil(p1.distance_to(p2)))
		for k in seg:
			var t := float(k) / seg
			_samples.append(_catmull(p0, p1, p2, p3, t))
	_samples.append(pts[pts.size() - 1])
	_total = 0.0
	for i in _samples.size():
		if i > 0:
			_total += Vector2(_samples[i].x - _samples[i - 1].x, _samples[i].z - _samples[i - 1].z).length()
		_dist.append(_total)
		var a := _samples[maxi(i - 1, 0)]
		var b := _samples[mini(i + 1, _samples.size() - 1)]
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		_tangents.append(t)


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# ---------------------------------------------------------------------------
#  Башня и подъём
# ---------------------------------------------------------------------------
func _build_tower() -> void:
	var b = BUILDER.new(4242)
	b.ground_y = _y
	b.palette = 2
	var base := Vector3(TOWER.x, _y, TOWER.z)
	# три яруса глыб вокруг ядра
	for level in 3:
		var y := _y - 0.3 + level * TOWER_H * 0.32
		var r := 4.4 - level * 0.4
		for k in 7:
			var a := TAU * k / 7.0 + level * 0.45
			var p := base + Vector3(cos(a) * r, 0.0, sin(a) * r)
			p.y = y
			if cos(a) > 0.82 and level > 0:
				continue   # с востока — подъём
			b.rock(b._pick(b.SET_ROUND), p, Vector3(4.2, TOWER_H * 0.42, 3.6), a + PI * 0.5,
				Vector2(b.rng.randf_range(-0.1, 0.1), b.rng.randf_range(-0.1, 0.1)))
	b.finish(self)
	# ядро-столкновение и площадка наверху
	var body := StaticBody3D.new()
	body.add_to_group("safe_ground")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.4, TOWER_H, 8.4)
	col.shape = box
	col.position = base + Vector3(0, TOWER_H * 0.5 - 0.02, 0)
	body.add_child(col)
	add_child(body)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(9.0, 0.3, 9.0)
	tm.material = _snow_mat()
	top.mesh = tm
	top.position = base + Vector3(0, TOWER_H - 0.1, 0)
	add_child(top)
	var sign := Label3D.new()
	sign.text = "ЛЕДЯНАЯ ГОРКА\nподъём — с востока"
	sign.font_size = 72
	sign.outline_size = 16
	sign.modulate = Color(0.75, 0.95, 1.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = base + Vector3(0, TOWER_H + 3.5, 0)
	add_child(sign)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(1.0, 0.45, 0.1)
	flag_mat.emission_enabled = true
	flag_mat.emission = Color(1.0, 0.4, 0.05)
	flag_mat.emission_energy_multiplier = 0.6
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 4.0
	pole.mesh = cm
	pole.position = base + Vector3(2.5, TOWER_H + 2.0, 2.5)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.4, 0.8, 0.04)
	fm.material = flag_mat
	flag.mesh = fm
	flag.position = base + Vector3(3.2, TOWER_H + 3.5, 2.5)
	add_child(flag)


func _snow_mat() -> Material:
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.get("terrain_material"):
		return terrain.terrain_material
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.95, 1.0)
	return m


## Снежный подъём на башню с востока: пологий (27°), шагом можно
func _build_climb() -> void:
	var top := Vector3(TOWER.x + 4.2, _y + TOWER_H, TOWER.z)
	var bottom := Vector3(TOWER.x + 4.2 + 28.0, _y, TOWER.z)
	var v := top - bottom
	var length := v.length()
	var basis := Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, atan2(v.y, Vector2(v.x, v.z).length()))
	var center := (top + bottom) * 0.5 - basis * Vector3(0, 0.35, 0)
	var body := StaticBody3D.new()
	body.add_to_group("safe_ground")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.5, 0.7, length)
	col.shape = sh
	col.transform = Transform3D(basis, center)
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	bm.material = _snow_mat()
	mi.mesh = bm
	mi.transform = col.transform
	body.add_child(mi)
	add_child(body)
	# снежная насыпь под подъёмом и ступеньки-зарубки (только для вида)
	var under := MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.left_to_right = 1.0
	pr.size = Vector3(28.0, TOWER_H, 4.4)
	pr.material = _snow_mat()
	under.mesh = pr
	under.position = Vector3(TOWER.x + 4.2 + 14.0, _y + TOWER_H * 0.5 - 0.4, TOWER.z)
	under.rotation.y = PI
	add_child(under)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.35, 0.22, 0.12)
	for i in 8:
		var t := (i + 0.5) / 8.0
		var p := bottom.lerp(top, t)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.06
			cm.bottom_radius = 0.07
			cm.height = 1.1
			cm.material = post_mat
			post.mesh = cm
			post.position = p + Vector3(0, 0.55, side * 2.35)
			add_child(post)


# ---------------------------------------------------------------------------
#  Жёлоб: сечение «корытом», протянутое вдоль трассы
# ---------------------------------------------------------------------------
func _section(extra_l: float, extra_r: float) -> Array[Vector2]:
	# (поперёк вправо, вверх) — изнутри жёлоба слева направо
	return [
		Vector2(-4.3, 2.6 + extra_l), Vector2(-3.8, 1.7 + extra_l * 0.7), Vector2(-3.0, 0.8 + extra_l * 0.3),
		Vector2(-2.0, 0.15), Vector2(0.0, 0.0), Vector2(2.0, 0.15),
		Vector2(3.0, 0.8 + extra_r * 0.3), Vector2(3.8, 1.7 + extra_r * 0.7), Vector2(4.3, 2.6 + extra_r),
	]


func _build_chute() -> void:
	var ice := ShaderMaterial.new()
	ice.shader = ICE_SHADER
	ice.set_shader_parameter("polish", 1.0)
	var shell := ShaderMaterial.new()
	shell.shader = ICE_SHADER
	shell.set_shader_parameter("deep", Color(0.04, 0.2, 0.42))
	shell.set_shader_parameter("mid", Color(0.2, 0.5, 0.78))
	shell.set_shader_parameter("band_scale", 2.0)
	var inner := SurfaceTool.new()
	inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := SurfaceTool.new()
	outer.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_inner: Array[Vector3] = []
	var prev_outer: Array[Vector3] = []
	for i in _samples.size():
		var c := _samples[i]
		var t := _tangents[i]
		var r := Vector3(-t.z, 0.0, t.x)
		# вираж: внешний борт выше
		var ta := _tangents[maxi(i - 3, 0)]
		var tb := _tangents[mini(i + 3, _samples.size() - 1)]
		var turn := ta.cross(tb).y          # >0 — поворот налево
		var bank := clampf(absf(turn) * 3.0, 0.0, 1.6)
		var el := bank if turn < 0.0 else 0.0
		var er := bank if turn > 0.0 else 0.0
		var sec := _section(el, er)
		var ring: Array[Vector3] = []
		for q in sec:
			ring.append(c + r * q.x + Vector3.UP * q.y)
		# наружная оболочка: верх бортов → наружу вниз → дно
		var shell_ring: Array[Vector3] = [
			ring[ring.size() - 1], c + r * 4.7 + Vector3.UP * (2.4 + er), c + r * 4.7 + Vector3.UP * -0.9,
			c + r * -4.7 + Vector3.UP * -0.9, c + r * -4.7 + Vector3.UP * (2.4 + el), ring[0],
		]
		if i > 0:
			_strip(inner, prev_inner, ring)
			_strip(outer, prev_outer, shell_ring)
		prev_inner = ring
		prev_outer = shell_ring
	inner.generate_normals()
	inner.set_material(ice)
	var mesh := inner.commit()
	outer.generate_normals()
	outer.set_material(shell)
	mesh = outer.commit(mesh)
	var body := StaticBody3D.new()
	body.add_to_group("safe_ground")
	body.set_meta("chute", true)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02
	body.physics_material_override = pm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	add_child(body)
	# опоры под жёлобом
	var pillar_mat := ShaderMaterial.new()
	pillar_mat.shader = ICE_SHADER
	pillar_mat.set_shader_parameter("band_scale", 1.5)
	var pbody := StaticBody3D.new()
	add_child(pbody)
	var i := 6
	while i < _samples.size() - 4:
		var c := _samples[i]
		var h := c.y - 0.9 - _y
		if h > 0.8:
			var r := Vector3(-_tangents[i].z, 0.0, _tangents[i].x)
			for side in [-1.0, 1.0]:
				var p: Vector3 = Vector3(c.x, _y + h * 0.5, c.z) + r * side * 3.2
				var pm2 := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.45
				cm.bottom_radius = 0.75
				cm.height = h
				cm.material = pillar_mat
				pm2.mesh = cm
				pm2.position = p
				add_child(pm2)
				var pc := CollisionShape3D.new()
				var cs := CylinderShape3D.new()
				cs.radius = 0.6
				cs.height = h
				pc.shape = cs
				pc.position = p
				pbody.add_child(pc)
		i += 9
	# светящиеся вешки вдоль бортов — трассу видно издалека
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.5, 0.15)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.45, 0.1)
	lamp.emission_energy_multiplier = 2.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.16
	bulb.height = 0.32
	bulb.material = lamp
	i = 2
	while i < _samples.size():
		var c := _samples[i]
		var r := Vector3(-_tangents[i].z, 0.0, _tangents[i].x)
		for side in [-1.0, 1.0]:
			var m := MeshInstance3D.new()
			m.mesh = bulb
			m.position = c + r * side * 4.5 + Vector3.UP * 2.75
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(m)
		i += 5


## Полоса треугольников между двумя соседними сечениями
func _strip(st: SurfaceTool, a: Array[Vector3], b: Array[Vector3]) -> void:
	for k in a.size() - 1:
		var p0 := a[k]
		var p1 := a[k + 1]
		var q0 := b[k]
		var q1 := b[k + 1]
		st.add_vertex(p0); st.add_vertex(q1); st.add_vertex(p1)
		st.add_vertex(p0); st.add_vertex(q0); st.add_vertex(q1)


# ---------------------------------------------------------------------------
#  Ощущение скорости и разгон
# ---------------------------------------------------------------------------
func _build_fx() -> void:
	_spray = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 70, 0.6, 0.07, 2.5, 5.0, Vector3(0, -9, 0), 35.0, false)
	_spray.top_level = true
	add_child(_spray)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_lines = ColorRect.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// «Полосы ветра» по краям экрана — чем быстрее, тем гуще
uniform float amount = 0.0;
float h(float n) { return fract(sin(n * 91.73) * 43758.545); }
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.78;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float ray = floor(a * 70.0);
	float t = floor(TIME * 14.0);
	float on = step(0.72, h(ray + t * 0.37));
	float len = 0.25 + 0.3 * h(ray * 3.1 + t);
	float m = on * smoothstep(len, len + 0.25, r);
	COLOR = vec4(1.0, 1.0, 1.0, m * amount * 0.5);
}
"""
	_lines_mat = ShaderMaterial.new()
	_lines_mat.shader = sh
	_lines.material = _lines_mat
	_lines.visible = false
	layer.add_child(_lines)


## Ближайшая точка трассы к позиции (номер)
func _nearest(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in _samples.size():
		var d := Vector2(p.x - _samples[i].x, p.z - _samples[i].z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func _physics_process(delta: float) -> void:
	var me: CharacterBody3D = Network.local_player
	var fx := 0.0
	_on_chute = false
	if me and not bool(me.get("is_dead")):
		var p := me.global_position
		# грубая проверка: рядом ли вообще горка
		if Vector2(p.x - 100.0, p.z - 840.0).length() < 110.0:
			var i := _nearest(p)
			var c := _samples[i]
			var t := _tangents[i]
			var r := Vector3(-t.z, 0.0, t.x)
			var off := (p - c).dot(r)
			if absf(off) < 4.2 and p.y > c.y - 0.6 and p.y < c.y + 3.0 and i < _samples.size() - 2:
				_on_chute = true
				var frac := _dist[i] / _total
				var want := lerpf(SPEED_START, SPEED_END, frac)
				var hv := Vector3(me.velocity.x, 0.0, me.velocity.z)
				var along := hv.dot(t)
				# разгон по трассе
				if along < want:
					along = minf(along + 14.0 * delta, want)
				# держим трассу: скорость поворачивает вдоль жёлоба и чуть к середине
				var side_v := hv.dot(r)
				side_v = lerpf(side_v, -off * 1.2, clampf(delta * 5.0, 0.0, 1.0))
				var nv := t * along + r * side_v
				me.velocity.x = nv.x
				me.velocity.z = nv.z
				fx = clampf((along - 6.0) / 14.0, 0.0, 1.0)
				me.set_speed_fx(fx)
				_spray.global_position = p + Vector3.UP * 0.1 - t * 0.6
	_spray.emitting = _on_chute and fx > 0.2
	_lines.visible = fx > 0.05
	_lines_mat.set_shader_parameter("amount", fx)
