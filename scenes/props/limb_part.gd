extends RigidBody3D
## Оторванная рука или нога. Лежит, кувыркается, на воде держится на плаву.
## Её можно поднять (E) — несу на плече, как трофей, рваным краем назад; кинуть (Q);
## а другу — прикрутить обратно (держать E рядом). Ремонт идёт по шагам:
##   вставляю в гнездо со щелчком → закручиваю 4 болта ключом (искры) →
##   соединяю провода (синий разряд, друга дёргает) → простукиваю ключом.
## Из рваного края искрит и капает гидравлика.

const SUIT := preload("res://scenes/player/exo_suit.gd")

var part_id := ""
var owner_id := 0          ## чья это деталь (peer_id дрона)
var kind := "arm_l"
var holder: Node3D = null  ## кто держит (рука)
var repair_target: Node3D = null   ## (старое поле, не используется)
var repair_k := 0.0
var _end := Vector3(0, -0.7, 0)
var _spark: GPUParticles3D
var _drip: GPUParticles3D
var _spark_t := 0.0
var _lake: Node = null
var _home := Vector3.ZERO

# ремонт
var _bolts: Array[Node3D] = []
var _collar: MeshInstance3D      ## хомут на руке/ноге под суставом — в него вкручиваются болты
var _ax := Vector3.DOWN          ## ось детали (от рваного края к кисти/ступне)
var _au := Vector3.RIGHT
var _av := Vector3.BACK
const COLLAR_AT := 0.13          ## хомут — на столько ниже сустава вдоль оси
var _bolt_base := 0.0          ## угол первого болта (болты — со стороны того, кто чинит)
var _rep_on := false
var _rep_from := Transform3D.IDENTITY
var _rep_prev := 0.0
var _arcs: Array[MeshInstance3D] = []
var _arc_mesh: Array[ImmediateMesh] = []
var _flash: OmniLight3D
var _flash_e := 0.0


func setup(visual: Node3D, end: Vector3) -> void:
	add_to_group("limb_part")
	process_physics_priority = 10      # после дронов: уже знаю, где их руки в этом кадре
	_end = end
	add_child(visual)
	mass = 5.0
	linear_damp = 0.3
	angular_damp = 1.5
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough = true
	pm.bounce = 0.15
	physics_material_override = pm
	collision_layer = 1
	collision_mask = 1
	continuous_cd = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var length := maxf(end.length(), 0.3)
	cap.radius = 0.1
	cap.height = length + 0.2
	cs.shape = cap
	var dir := end.normalized() if end.length() > 0.01 else Vector3.DOWN
	var b := Basis(Quaternion(Vector3.UP, dir)) if dir.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	cs.transform = Transform3D(b, end * 0.5)
	add_child(cs)
	_spark = FX.particles(Color(1.0, 0.78, 0.35, 1.0), 10, 0.3, 0.012, 1.0, 2.4, Vector3(0, -9, 0), 70.0, true, true)
	add_child(_spark)
	_drip = FX.particles(Color(0.32, 0.18, 0.05, 0.9), 6, 0.8, 0.014, 0.0, 0.3, Vector3(0, -6, 0), 15.0, false)
	add_child(_drip)
	_drip.emitting = true
	get_tree().create_timer(12.0).timeout.connect(func():
		if is_instance_valid(_drip):
			_drip.emitting = false)
	_ax = end.normalized() if end.length() > 0.01 else Vector3.DOWN
	_au = _ax.cross(Vector3.FORWARD if absf(_ax.z) < 0.9 else Vector3.RIGHT).normalized()
	_av = _ax.cross(_au).normalized()
	# болты (появляются, когда чиню)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.74, 0.74, 0.78)
	steel.metallic = 0.95
	steel.roughness = 0.22
	for j in 4:
		var bn := Node3D.new()
		bn.visible = false
		add_child(bn)
		var hm := MeshInstance3D.new()
		var hc := CylinderMesh.new()
		hc.top_radius = 0.018
		hc.bottom_radius = 0.018
		hc.height = 0.013
		hc.radial_segments = 6
		hm.mesh = hc
		hm.material_override = steel
		bn.add_child(hm)
		var wm := MeshInstance3D.new()
		var wc := CylinderMesh.new()
		wc.top_radius = 0.024
		wc.bottom_radius = 0.024
		wc.height = 0.004
		wc.radial_segments = 12
		wm.mesh = wc
		wm.material_override = steel
		wm.position = Vector3(0, -0.009, 0)
		bn.add_child(wm)
		var sm := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.007
		sc.bottom_radius = 0.007
		sc.height = 0.04
		sc.radial_segments = 6
		sm.mesh = sc
		sm.material_override = steel
		sm.position = Vector3(0, -0.03, 0)
		bn.add_child(sm)
		_bolts.append(bn)
	_collar = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.07
	tor.outer_radius = 0.092
	tor.rings = 20
	tor.ring_segments = 8
	_collar.mesh = tor
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.85, 0.62, 0.2)
	cm.metallic = 0.9
	cm.roughness = 0.3
	_collar.material_override = cm
	_collar.transform = Transform3D(Basis(_au, _ax, -_av).orthonormalized(), _ax * COLLAR_AT)
	_collar.visible = false
	add_child(_collar)
	# молнии разряда
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color(0.7, 0.9, 1.0)
	am.vertex_color_use_as_albedo = false
	for k in 3:
		var im := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = am
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_arcs.append(mi)
		_arc_mesh.append(im)
	_flash = OmniLight3D.new()
	_flash.light_energy = 0.0
	_flash.omni_range = 2.5
	add_child(_flash)


func _physics_process(delta: float) -> void:
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(0.8, 2.5)
		_spark.restart()
	_flash_e = maxf(_flash_e - delta * 12.0, 0.0)
	_flash.light_energy = _flash_e
	if holder != null and is_instance_valid(holder):
		freeze = true
		collision_layer = 0
		var who: Node3D = holder.get("act_target")
		var fixing: bool = int(holder.get("act_mode")) == 1 and holder.get("held_limb") == self \
			and who != null and is_instance_valid(who)
		if fixing:
			var k := float(holder.get("act_k"))
			if not _rep_on:
				_rep_begin(who)
			global_transform = repair_xform(k, who)
			_rep_update(k, who, delta)
		else:
			if _rep_on:
				_rep_end()
			var tgt: Transform3D = _hold_xform()
			var carry = holder.suit.limb_carry_xform()
			if carry != null:
				tgt = carry
			# плавно — из руки на плечо, с земли в руку
			global_transform = global_transform.orthonormalized().interpolate_with(tgt, clampf(delta * 16.0, 0.0, 1.0))
		return
	if _rep_on:
		_rep_end()
	if freeze:
		freeze = false
		collision_layer = 1
	if _lake == null:
		_lake = get_tree().get_first_node_in_group("ice_lake")
	# на воде держится (внутри — воздух), чуть покачивается
	if _lake and _lake.is_hole(global_position.x, global_position.z):
		var wy: float = _lake.water_y(global_position.z)
		if global_position.y < wy:
			apply_central_force(Vector3.UP * mass * 14.0 * clampf(wy - global_position.y, 0.0, 1.0))
			linear_velocity *= 0.97
			angular_velocity *= 0.96
	if global_position.y < -40.0:
		# упала совсем вниз — найдётся у места возрождения хозяина
		var o = Network.find_player(owner_id)
		global_position = (o.get("_spawn_position") if o else Vector3.ZERO) + Vector3.UP * 1.5
		linear_velocity = Vector3.ZERO


## Запасной хват: в кулаке, как дубинка (когда на плечо нельзя — плыву и т.п.)
func _hold_xform() -> Transform3D:
	var h := holder
	var idx: int = 1 if bool(h.suit.has_limb("arm_r")) else 0
	var hand: Transform3D = (h.suit.hand_xform(idx) as Transform3D).orthonormalized()
	var s := -1.0 if idx == 0 else 1.0
	return hand * Transform3D(Basis(Vector3.RIGHT, PI * 0.55), Vector3(-s * 0.04, -0.1, 0.0))


# ---------------------------------------------------------------------------
#  Ремонт
# ---------------------------------------------------------------------------

## Где деталь при прогрессе k: подношу (0–0.2), щелчок — вошла (0.2–0.24), сидит,
## пока не все болты — чуть шатается
func repair_xform(k: float, who: Node3D) -> Transform3D:
	var sock: Transform3D = (who.suit.socket_xform(kind) as Transform3D).orthonormalized()
	var pre := sock * Transform3D(Basis.IDENTITY, Vector3(0, -0.17, 0))
	if k < 0.2:
		var from := _rep_from if _rep_on else global_transform.orthonormalized()
		return from.interpolate_with(pre, smoothstep(0.0, 0.2, k))
	if k < 0.24:
		var u := (k - 0.2) / 0.04
		return sock * Transform3D(Basis.IDENTITY, Vector3(0, -0.17 * (1.0 - u * u) + 0.012 * sin(u * PI), 0))
	var loose := 1.0 - clampf((k - SUIT.BOLT_K0) / (SUIT.BOLT_DK * 4.0), 0.0, 1.0)
	var wob := Basis(Vector3.RIGHT, sin(k * 90.0) * 0.035 * loose) * Basis(Vector3.FORWARD, cos(k * 70.0) * 0.03 * loose)
	return sock * Transform3D(wob, Vector3.ZERO)


## Куда смотрит болт j (наружу от оси, в осях детали)
func bolt_dir(j: int) -> Vector3:
	var a := _bolt_base + (float(j) - 1.5) * 0.75
	return _au * cos(a) + _av * sin(a)


## Где болт j при прогрессе k (в осях детали): подносится, вкручивается в хомут
func bolt_local(j: int, k: float) -> Vector3:
	var t := clampf((k - (SUIT.BOLT_K0 + j * SUIT.BOLT_DK)) / (SUIT.BOLT_DK * 0.85), 0.0, 1.0)
	return bolt_dir(j) * lerpf(0.15, 0.1, t) + _ax * COLLAR_AT


func _rep_begin(who: Node3D) -> void:
	_rep_on = true
	_rep_from = global_transform.orthonormalized()
	_rep_prev = 0.0
	# болты — на той стороне, где стоит чинящий
	var sock: Transform3D = (who.suit.socket_xform(kind) as Transform3D).orthonormalized()
	var hl := sock.affine_inverse() * (holder.global_position + Vector3.UP * 1.1)
	_bolt_base = atan2(hl.dot(_av), hl.dot(_au))


func _rep_end() -> void:
	_rep_on = false
	_collar.visible = false
	for b in _bolts:
		b.visible = false
	for a in _arcs:
		a.visible = false


func _rep_update(k: float, who: Node3D, delta: float) -> void:
	var prev := _rep_prev
	_rep_prev = k
	_collar.visible = k >= 0.22
	# болты
	for j in 4:
		var k0: float = SUIT.BOLT_K0 + j * SUIT.BOLT_DK
		var b := _bolts[j]
		b.visible = k >= k0
		if not b.visible:
			continue
		var dir := bolt_dir(j)
		var t := clampf((k - k0) / (SUIT.BOLT_DK * 0.85), 0.0, 1.0)
		b.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, t * TAU * 3.0), bolt_local(j, k))
		if t > 0.0 and t < 1.0 and randf() < delta * 10.0:
			_burst(global_transform * bolt_local(j, k), Color(1.0, 0.75, 0.3), 4, 0.2, 0.6, 1.6)
		var done: float = k0 + SUIT.BOLT_DK * 0.85
		if prev < done and k >= done:
			# затянул: искры веером и «дзынь»
			_burst(global_transform * bolt_local(j, k), Color(1.0, 0.82, 0.4), 22, 0.35, 1.5, 3.2)
			_flash.light_color = Color(1.0, 0.8, 0.5)
			_flash_e = 1.5
			who.suit.jolt(0.25)
	# щелчок: вошла в гнездо
	if prev < 0.24 and k >= 0.24:
		_burst(global_position, Color(1.0, 0.95, 0.8), 26, 0.3, 1.0, 3.0)
		_flash.light_color = Color(1.0, 0.95, 0.85)
		_flash_e = 2.5
		who.suit.jolt(0.9)
		who.suit.emote(SUIT.Mood.HURT, 0.4)
		holder.suit.emote(SUIT.Mood.FOCUS, 2.0)
	# провода: синий разряд, друга дёргает
	var arc_on := k >= 0.76 and k < 0.86
	for a in _arcs:
		a.visible = arc_on and randf() < 0.8
	if arc_on:
		_draw_arcs(who)
		_flash.light_color = Color(0.5, 0.75, 1.0)
		_flash_e = maxf(_flash_e, randf_range(1.0, 3.5))
		if randf() < delta * 12.0:
			_burst(global_position + Vector3(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06), randf_range(-0.06, 0.06)),
				Color(0.55, 0.8, 1.0), 8, 0.25, 1.0, 2.5)
	if prev < 0.78 and k >= 0.78:
		_burst(global_position, Color(0.55, 0.82, 1.0), 40, 0.45, 2.0, 4.0)
		_flash_e = 5.0
		who.suit.jolt(1.2)
		who.suit.emote(SUIT.Mood.HURT, 0.6)
		holder.suit.jolt(0.6)
		if bool(who.get("is_local")):
			who.set("_shake", maxf(float(who.get("_shake")), 0.3))
	# простукиваю: тук-тук
	for tk in [0.9, 0.96]:
		if prev < tk and k >= tk:
			_burst(global_transform * (_end * 0.22), Color(1.0, 0.9, 0.6), 10, 0.2, 0.8, 2.0)
			who.suit.jolt(0.3)


## Ломаные молнии между гнездом и деталью
func _draw_arcs(who: Node3D) -> void:
	var sock: Transform3D = (who.suit.socket_xform(kind) as Transform3D).orthonormalized()
	for n in _arcs.size():
		var im := _arc_mesh[n]
		im.clear_surfaces()
		var a0 := randf() * TAU
		var p0 := sock * Vector3(cos(a0) * 0.05, 0.03, sin(a0) * 0.05)
		var a1 := a0 + randf_range(-1.0, 1.0)
		var p1 := global_transform * Vector3(cos(a1) * 0.07, -0.1 - randf() * 0.05, sin(a1) * 0.07)
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var prev := p0
		for s in 6:
			var t := float(s + 1) / 6.0
			var q := p0.lerp(p1, t)
			if s < 5:
				q += Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), randf_range(-0.03, 0.03))
			im.surface_add_vertex(prev)
			im.surface_add_vertex(q)
			prev = q
		im.surface_end()
		_arcs[n].global_transform = Transform3D.IDENTITY


func _burst(at: Vector3, c: Color, n: int, life: float, smin: float, smax: float) -> void:
	var p := FX.particles(c, n, life, 0.011, smin, smax, Vector3(0, -9, 0), 180.0, true, true)
	p.top_level = true
	add_child(p)
	p.global_position = at
	p.restart()
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)
