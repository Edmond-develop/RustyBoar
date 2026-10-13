extends Node3D
## Верёвка-лассо с карабином (до 14 м). Есть у каждого дрона (и у ботов), узел "Rope".
##
## Как выглядит:
##  * яркий плетёный альпинистский трос; на конце — петля-лассо и стальной карабин
##    с мигающим красным маячком (конец видно издалека, даже в метель);
##  * трос — настоящая «физическая» верёвка из звеньев: провисает, ложится на снег,
##    плавает по воде в полынье, хлещет при броске, натягивается струной;
##  * лишняя верёвка — в мотке на поясе: моток худеет, когда верёвка уходит, и
##    толстеет, когда её выбирают.
##
## Управление (верёвка в руках — инвентарь, I):
##  * ЛКМ держишь — раскручиваешь петлю над головой; видно пунктир броска и цель
##    (СПАСТИ / СВЯЗКА / АРКАН); отпустил — бросок, петля летит по дуге;
##  * ПКМ (держать) — выбирать верёвку перехватом рук;
##  * ЛКМ ещё раз — отвязать и смотать (верёвка ползёт по снегу обратно).
## Что получается, зависит от того, во что попала петля:
##  * друг в воде — СПАСЕНИЕ: он хватается за карабин обеими руками и не тонет;
##    тянешь — выползает на лёд (из-подо льда сначала плывёт к полынье);
##  * друг на суше — СВЯЗКА: петля затягивается на поясе; дальше длины не разойтись,
##    а если один провалился или сорвался — второй держит его (ПКМ — вытянуть);
##  * груз — АРКАН/ВОЛОК: тянешь — груз едет к тебе (лёгкий подтянул — в руки),
##    идёшь прочь — тащишь волоком через плечо (тяжёлый — медленно).
## Сеть: состояние верёвки рассылает хозяин; тянущую силу каждый компьютер
## прикладывает к своему дрону сам, к грузу — хост. Трос каждый считает у себя.

enum S { NONE, SWING, FLY, ATTACHED, RETURN, LYING }
enum M { CARGO, RESCUE, TETHER }

const ROPE_SHADER := preload("res://shaders/rope.gdshader")
const MAX_LEN := 14.0
const MIN_RANGE := 4.0             ## бросок «с ходу» — недалеко
const CHARGE_TIME := 1.3           ## за сколько раскрутки — бросок на всю длину
const MIN_LEN := 1.3
const REEL_SPEED := 2.3
const RETURN_SPEED := 4.6           ## смотка (ПКМ) — перехватом
const AIM_ANGLE := 30.0
const N := 30                      ## звеньев в тросе
const ROPE_R := 0.03
const GRAVITY := Vector3(0, -9.8, 0)

var p: CharacterBody3D             ## хозяин (player.gd)
var equipped := false
var state := S.NONE
var mode := M.CARGO
var target: Node3D = null
var length := 0.0
var pulling := false
var aim_override: Node3D = null    ## бот: в кого бросать
var swing_t := 0.0
var throw_t := 0.0                 ## сколько назад бросил (для позы)

var _swing_a := 0.0                ## угол раскрутки петли
var _haul_ph := 0.0                ## фаза перехвата (руки по очереди тянут)
var _throw_range := MAX_LEN        ## дальность последнего броска
var _fly_t := 0.0
var _fly_time := 0.4
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.ZERO
var _send_t := 0.0
var _end := Vector3.ZERO
var _cur_len := 0.0                ## сколько верёвки сейчас «снаружи»
var _pts := PackedVector3Array()
var _prev := PackedVector3Array()
var _floor := PackedFloat32Array()
var _floor_i := 0
var _sim_on := false
var _loop_r := 0.4                 ## радиус петли
var _tighten := 0.0

var _mat: ShaderMaterial
var _im: ImmediateMesh
var _mesh: MeshInstance3D
var _coil: Node3D
var _coil_parent: Node3D = null
var _clip: Node3D                  ## крюк с защёлкой и маячком
var _gate: Node3D                  ## защёлка крюка (щёлкает при зацепе)
var _clip_t := 9.0                 ## сколько назад зацепился (анимация щелчка)
var _twang := 0.0                  ## верёвка «звенит» после рывка
var _end_v := Vector3.ZERO         ## падающий крюк (отстегнули)
var _hook_rot := Basis.IDENTITY    ## куда смотрит крюк (плавно)
var _spark_fx: GPUParticles3D
var _flash: OmniLight3D
var _led_mat: StandardMaterial3D
var _led_light: OmniLight3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _snap_fx: GPUParticles3D
var _aim_dots: MultiMeshInstance3D
var _aim_ring: MeshInstance3D
var _aim_ring_mat: StandardMaterial3D
var _aim_label: Label3D


func setup(player: CharacterBody3D) -> void:
	p = player
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mat = ShaderMaterial.new()
	_mat.shader = ROPE_SHADER
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	add_child(_mesh)
	_pts.resize(N)
	_prev.resize(N)
	_floor.resize(N)
	for i in N:
		_floor[i] = -1000.0
	# моток: несколько витков, перехваченных обвязкой, и свисающий хвостик
	_coil = Node3D.new()
	_coil.name = "RopeCoil"
	for k in 4:
		var loop := TorusMesh.new()
		var rr := 0.155 + 0.012 * k
		loop.inner_radius = rr - 0.034
		loop.outer_radius = rr
		loop.rings = 22
		loop.ring_segments = 8
		loop.material = _mat
		var lm := MeshInstance3D.new()
		lm.mesh = loop
		lm.position = Vector3(0.0, (k - 1.5) * 0.026, 0.006 * (k % 2))
		lm.rotation = Vector3(0.06 * (k % 2 * 2 - 1), 0.4 * k, 0.05 * (k - 1.5))
		_coil.add_child(lm)
	var wrap_mat := StandardMaterial3D.new()
	wrap_mat.albedo_color = Color(0.12, 0.13, 0.16)
	wrap_mat.roughness = 0.6
	for side in [-1.0, 1.0]:
		var wrap := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.036
		wm.bottom_radius = 0.036
		wm.height = 0.13
		wm.radial_segments = 8
		wm.material = wrap_mat
		wrap.mesh = wm
		wrap.position = Vector3(0.16 * side, 0.0, 0.0)
		_coil.add_child(wrap)
	var tail := MeshInstance3D.new()
	var tm0 := CylinderMesh.new()
	tm0.top_radius = 0.022
	tm0.bottom_radius = 0.02
	tm0.height = 0.2
	tm0.radial_segments = 6
	tm0.material = _mat
	tail.mesh = tm0
	tail.position = Vector3(0.05, -0.02, 0.2)
	tail.rotation = Vector3(1.25, 0.0, 0.25)
	_coil.add_child(tail)
	# крюк: стальной стержень с ушком под верёвку, загнутый зуб с остриём,
	# пружинная защёлка и маячок на стержне. Ось +Y — к верёвке, зуб — внизу.
	_clip = Node3D.new()
	_clip.visible = false
	add_child(_clip)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.84)
	steel.metallic = 0.95
	steel.roughness = 0.22
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.25, 0.1)
	paint.metallic = 0.4
	paint.roughness = 0.35
	# ушко
	var eye := TorusMesh.new()
	eye.inner_radius = 0.022
	eye.outer_radius = 0.04
	eye.rings = 14
	eye.ring_segments = 6
	eye.material = steel
	var eye_m := MeshInstance3D.new()
	eye_m.mesh = eye
	eye_m.position = Vector3(0, 0.16, 0)
	eye_m.rotation = Vector3(PI * 0.5, 0, 0)
	_clip.add_child(eye_m)
	# стержень (в оранжевой краске — видно на снегу)
	var shank := MeshInstance3D.new()
	var shm := CylinderMesh.new()
	shm.top_radius = 0.02
	shm.bottom_radius = 0.024
	shm.height = 0.22
	shm.radial_segments = 8
	shm.material = paint
	shank.mesh = shm
	shank.position = Vector3(0, 0.02, 0)
	_clip.add_child(shank)
	# загиб зуба: сегменты по дуге
	var arc_c := Vector3(0.075, -0.09, 0)
	var arc_r := 0.075
	var segs := 6
	for k in segs:
		var a0 := PI + PI * float(k) / segs
		var a1 := PI + PI * float(k + 1) / segs
		var p0 := arc_c + Vector3(cos(a0), sin(a0), 0) * arc_r
		var p1 := arc_c + Vector3(cos(a1), sin(a1), 0) * arc_r
		var seg := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.019
		sm.bottom_radius = 0.019
		sm.height = p0.distance_to(p1) + 0.01
		sm.radial_segments = 8
		sm.material = steel
		seg.mesh = sm
		seg.transform = Transform3D(_basis_y(p1 - p0), (p0 + p1) * 0.5)
		_clip.add_child(seg)
	# остриё вверх
	var tip := MeshInstance3D.new()
	var tipm := CylinderMesh.new()
	tipm.top_radius = 0.002
	tipm.bottom_radius = 0.019
	tipm.height = 0.09
	tipm.radial_segments = 8
	tipm.material = steel
	tip.mesh = tipm
	tip.position = arc_c + Vector3(arc_r, 0.045, 0)
	_clip.add_child(tip)
	# защёлка: от стержня к острию, на шарнире
	_gate = Node3D.new()
	_gate.position = Vector3(0.0, -0.02, 0)
	_clip.add_child(_gate)
	var gate := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.16, 0.012, 0.016)
	gm.material = steel
	gate.mesh = gm
	gate.position = Vector3(0.075, 0.0, 0)
	gate.rotation = Vector3(0, 0, -0.32)
	_gate.add_child(gate)
	# маячок на стержне
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.07, 0.045)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.5
	bm.material = dark
	body.mesh = bm
	body.position = Vector3(-0.04, 0.05, 0)
	_clip.add_child(body)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(1.0, 0.15, 0.1)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1.0, 0.15, 0.1)
	_led_mat.emission_energy_multiplier = 6.0
	var led := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.014
	lm.height = 0.028
	lm.radial_segments = 8
	lm.rings = 4
	lm.material = _led_mat
	led.mesh = lm
	led.position = Vector3(-0.068, 0.06, 0)
	_clip.add_child(led)
	_halo = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.05
	hm.height = 0.1
	hm.radial_segments = 10
	hm.rings = 5
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.0)
	hm.material = _halo_mat
	_halo.mesh = hm
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = led.position
	_clip.add_child(_halo)
	_led_light = OmniLight3D.new()
	_led_light.light_color = Color(1.0, 0.2, 0.15)
	_led_light.omni_range = 1.6
	_led_light.light_energy = 0.0
	_led_light.position = led.position
	_clip.add_child(_led_light)
	_clip.scale = Vector3.ONE * 1.5
	# искры и вспышка при зацепе
	_spark_fx = FX.particles(Color(1.0, 0.75, 0.3, 1.0), 18, 0.35, 0.018, 2.0, 5.0, Vector3(0, -9, 0), 120.0)
	_spark_fx.top_level = true
	add_child(_spark_fx)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.6)
	_flash.omni_range = 2.5
	_flash.light_energy = 0.0
	_flash.top_level = true
	add_child(_flash)
	# «щелчок» петли: волокна и снег
	_snap_fx = FX.particles(Color(1.0, 0.8, 0.5, 0.9), 16, 0.45, 0.025, 1.5, 3.5, Vector3(0, -6, 0), 180.0)
	_snap_fx.top_level = true
	add_child(_snap_fx)
	# прицел: пунктир броска и метка цели (видно только тому, кто бросает)
	_aim_dots = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 22
	var dot := SphereMesh.new()
	dot.radius = 0.026
	dot.height = 0.052
	dot.radial_segments = 8
	dot.rings = 4
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.no_depth_test = true
	dot.material = dm
	mm.mesh = dot
	_aim_dots.multimesh = mm
	_aim_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_dots.visible = false
	add_child(_aim_dots)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.66
	tm.rings = 32
	tm.ring_segments = 4
	_aim_ring_mat = StandardMaterial3D.new()
	_aim_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_ring_mat.no_depth_test = true
	tm.material = _aim_ring_mat
	_aim_ring = MeshInstance3D.new()
	_aim_ring.mesh = tm
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_ring.visible = false
	add_child(_aim_ring)
	_aim_label = Label3D.new()
	_aim_label.font_size = 44
	_aim_label.outline_size = 10
	_aim_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_aim_label.no_depth_test = true
	_aim_label.visible = false
	add_child(_aim_label)


# ---------------------------------------------------------------------------
#  Управление (только у того, кто управляет этим дроном)
# ---------------------------------------------------------------------------
func local_update(delta: float) -> void:
	if not p.has_item("rope"):
		equipped = false
	throw_t += delta
	var busy: bool = p.held_parcel != null or p.held_friend != null or p.carried_by != null \
		or p.arms_count() < 2 or p.held_limb != null \
		or p.is_dead or p.is_frozen or p.rescue_role != 0 or p.downed \
		or p.visual.get_node_or_null("HockeyStick") != null
	match state:
		S.NONE:
			if equipped and not busy and p._just("use_item"):
				_set_state(S.SWING)
		S.SWING:
			if busy:
				_set_state(S.NONE)
			elif not p._held("use_item") or swing_t > 5.0:
				_throw()
		S.FLY:
			if _fly_t >= _fly_time:
				if is_instance_valid(target):
					_arrive()
				else:
					_set_state(S.LYING)       # промах: крюк лежит, пока не смотаешь (ПКМ)
		S.ATTACHED:
			var lost: bool = not is_instance_valid(target) or target.get("is_dead") == true or p.is_dead \
				or _flat(p.global_position, _target_pos()) > MAX_LEN + 4.0
			if target is Parcel and (target as Parcel).is_delivered:
				lost = true
			if lost or p._just("use_item") or p.carried_by != null:
				_detach()
				return
			pulling = p._held("use_alt")
			if pulling:
				# тянем рывками: каждая рука — свой рывок
				var sp := REEL_SPEED * (1.25 if mode == M.RESCUE else 1.0)
				var f := fposmod(_haul_ph * 2.0, 1.0)
				var pulse := pow(maxf(sin(f * PI), 0.0), 1.5) * 1.85
				length = maxf(length - sp * pulse * delta, MIN_LEN)
			# лёгкий груз подтянул вплотную — сразу берём в руки
			if mode == M.CARGO and target is Parcel and (target as Parcel).required_carriers <= 1 \
					and pulling and _flat(p.global_position, target.global_position) < 1.7 and p.held_parcel == null:
				var parcel := target as Parcel
				_detach()
				p.grab_parcel(parcel)
				return
			# друга вытащили из воды — верёвку больше не держим
			if mode == M.RESCUE and not target.get("is_swimming") and not target.get("is_diving") \
					and target.get("rescue_role") == 0 and _flat(p.global_position, target.global_position) < 2.4:
				_detach()
				return
			_send_t -= delta
			if _send_t <= 0.0:
				_send_t = 0.15
				_sync_len()
		S.LYING:
			# верёвка лежит; ПКМ — сматывать
			if p._held("use_alt"):
				_set_state(S.RETURN)
			elif _flat(p.global_position, _end) > MAX_LEN * 2.5:
				_set_state(S.NONE)            # унесло далеко (телепорт) — верёвка сама в мотке
		S.RETURN:
			if _cur_len <= 0.35:
				_set_state(S.NONE)
			elif not p._held("use_alt"):
				_set_state(S.LYING)           # отпустил ПКМ — пусть лежит


## Бот или другой код: бросить прямо в этот узел
func throw_at(node: Node3D) -> void:
	if state != S.NONE:
		return
	aim_override = node
	equipped = true
	swing_t = 0.5
	_throw()


func _throw() -> void:
	_throw_range = range_now() if state == S.SWING and aim_override == null else MAX_LEN
	var tgt: Node3D = aim_override if is_instance_valid(aim_override) else _pick_target(_throw_range)
	aim_override = null
	throw_t = 0.0
	if p.suit:
		p.suit.throw_anim()
	var from := _knot_point() if state == S.SWING else hand_point()
	target = tgt
	if tgt != null:
		_fly_to = _anchor(tgt)
	else:
		_fly_to = _miss_point(from, _throw_range)
	_fly_from = from
	_fly_time = clampf(from.distance_to(_fly_to) / 15.0 + 0.18, 0.28, 0.95)
	_set_state(S.FLY)


func _arrive() -> void:
	if target == null or not is_instance_valid(target) or _flat(p.global_position, _target_pos()) > MAX_LEN + 1.0:
		target = null
		_set_state(S.LYING)
		return
	if target is Parcel:
		mode = M.CARGO
	elif target.get("is_swimming") or target.get("is_diving"):
		mode = M.RESCUE
	else:
		mode = M.TETHER
	length = clampf(_flat(p.global_position, _target_pos()) + 0.4, MIN_LEN, MAX_LEN)
	_set_state(S.ATTACHED)
	if target.has_method("on_roped"):
		target.call("on_roped", p, mode)


func _detach() -> void:
	pulling = false
	if is_instance_valid(target) and target.has_method("on_roped"):
		target.call("on_roped", null, -1)
	target = null
	_set_state(S.LYING)                # крюк отстёгнут и падает — лежит, пока не смотаешь


## Куда целится: камера (у человека) или взгляд дрона (у бота)
func _aim_dir() -> Vector3:
	var d: Vector3
	if not p.controlled:
		d = -p.visual.global_basis.z
	else:
		d = -p.camera.global_basis.z
	d.y = maxf(d.y, -0.1)
	return d.normalized()


## Насколько далеко полетит петля сейчас (чем дольше раскручиваешь — тем дальше)
func range_now() -> float:
	return lerpf(MIN_RANGE, MAX_LEN, charge())


## 0..1 — сила раскрутки (для шкалы на экране)
func charge() -> float:
	return clampf(swing_t / CHARGE_TIME, 0.0, 1.0) if state == S.SWING else 0.0


func _pick_target(max_range := MAX_LEN) -> Node3D:
	var aim := _aim_dir()
	var aim_h := Vector3(aim.x, 0.0, aim.z).normalized()
	var best: Node3D = null
	var best_score := INF
	var cands: Array = []
	for d in get_tree().get_nodes_in_group("player"):
		if d != p and not d.get("is_dead") and d.get("carried_by") == null:
			cands.append(d)
	for pc in get_tree().get_nodes_in_group("parcel"):
		if not (pc as Parcel).is_delivered and not (pc as Parcel).holders.has(p.peer_id):
			cands.append(pc)
	for c in cands:
		var to := (c as Node3D).global_position - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 1.2 or dist > minf(max_range + 1.0, MAX_LEN):
			continue
		var ang := rad_to_deg(aim_h.angle_to(to / dist))
		if ang > AIM_ANGLE:
			continue
		var score := ang + dist * 0.6
		if score < best_score:
			best_score = score
			best = c
	return best


## Промах: куда упадёт конец (на дальность броска вперёд, на снег)
func _miss_point(from: Vector3, rng := 9.0) -> Vector3:
	var aim := _aim_dir()
	var q := Vector3(p.global_position.x, from.y, p.global_position.z) + Vector3(aim.x, 0.0, aim.z).normalized() * rng
	var y := _ground_at(q, from.y + 3.0)
	if y < -999.0:
		y = p.global_position.y
	return Vector3(q.x, y + 0.03, q.z)


# ---------------------------------------------------------------------------
#  Силы (каждый компьютер — для своего дрона; хост — для грузов)
# ---------------------------------------------------------------------------

## Поправить скорость своего дрона: держу верёвку / меня тянут за верёвку
func adjust_velocity(vel: Vector3, _delta: float) -> Vector3:
	# 1) я держу верёвку
	if state == S.ATTACHED and is_instance_valid(target):
		var to := _target_pos() - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.01 and dist > length:
			var dir := to / dist
			var away := -vel.dot(dir)
			match mode:
				M.CARGO:
					var limit := 1.5 if is_heavy_cargo() else 3.2
					if away > limit:
						vel += dir * (away - limit)
				M.RESCUE:
					if away > 0.0:
						vel += dir * away
				M.TETHER:
					if away > 0.0:
						vel += dir * away
					# связка: друг тянет к себе, если я ушёл далеко (кроме момента, когда я сам тяну)
					if not pulling and not in_trouble(target) and dist - length > 0.6:
						vel += dir * minf((dist - length) * 2.0, 3.0)
	# 2) меня держат чужие верёвки
	for r in ropes_on(p):
		var to: Vector3 = r.p.global_position - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.01 or dist <= r.length:
			continue
		var dir := to / dist
		var ex: float = dist - r.length
		var want := minf(ex * 4.0, 6.0)
		if r.mode == M.TETHER and not in_trouble(p):
			# на суше: тянут — волочёт к тянущему (упираться бесполезно)
			want = minf(ex * 4.0, 4.4) if r.pulling else minf(ex * 2.0, 3.0)
		var toward := vel.dot(dir)
		if toward < want:
			vel += dir * (want - toward)
	return vel


func _physics_process(delta: float) -> void:
	if p == null:
		return
	_simulate(delta)
	# хост тянет груз за верёвку (чья бы верёвка ни была)
	if state != S.ATTACHED or mode != M.CARGO or not multiplayer.is_server():
		return
	var parcel := target as Parcel
	if parcel == null or parcel.is_held or parcel.freeze:
		return
	var to := p.global_position - parcel.global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= length or dist < 0.01:
		return
	var max_sp := 1.6 if is_heavy_cargo() else 4.0
	var want := to / dist * minf((dist - length) * 4.0, max_sp)
	parcel.linear_velocity.x = lerpf(parcel.linear_velocity.x, want.x, clampf(delta * 10.0, 0.0, 1.0))
	parcel.linear_velocity.z = lerpf(parcel.linear_velocity.z, want.z, clampf(delta * 10.0, 0.0, 1.0))
	parcel.sleeping = false


func is_heavy_cargo() -> bool:
	var parcel := target as Parcel
	return parcel != null and (parcel.required_carriers > 1 or parcel.carry_weight() >= 3)


## В беде: в воде, падает или вмёрз
static func in_trouble(d: Node) -> bool:
	if d == null:
		return false
	if bool(d.get("is_swimming")) or bool(d.get("is_diving")) or bool(d.get("is_frozen")):
		return true
	if d.has_method("is_grounded"):
		return not bool(d.call("is_grounded"))
	return false


## Все натянутые на этого дрона чужие верёвки
func ropes_on(d: Node) -> Array:
	var out := []
	for o in get_tree().get_nodes_in_group("player"):
		if o == d:
			continue
		var r = o.get("rope")
		if r != null and r.state == S.ATTACHED and r.target == d:
			out.append(r)
	return out


## Кто-то тянет этого дрона (держит за верёвку) — для воды
func roped_by(d: Node) -> Node:
	var rs := ropes_on(d)
	return rs[0] if not rs.is_empty() else null


# ---------------------------------------------------------------------------
#  Точки
# ---------------------------------------------------------------------------
func hand_point() -> Vector3:
	if p.suit:
		return p.suit.grip_point(1)
	return p.global_position + Vector3.UP * 1.0


func _target_pos() -> Vector3:
	if not is_instance_valid(target):
		return p.global_position
	return target.global_position


## Куда цепляется конец
func _anchor(t: Node3D) -> Vector3:
	if t is Parcel:
		# за обвязку ящика: верхнее ребро со стороны хозяина
		var ext: Vector3 = p.suit.extents(t) if p.suit else Vector3(0.3, 0.3, 0.3)
		var to := p.global_position - t.global_position
		to.y = 0.0
		return t.global_position + to.normalized() * (maxf(ext.x, ext.z) * 0.85) + Vector3.UP * (ext.y + 0.02)
	if t.get("is_frozen") == true:
		# глыба со льдом: зуб крюка впивается в лёд
		var tb := p.global_position - t.global_position
		tb.y = 0.0
		return t.global_position + Vector3.UP * 0.95 + tb.normalized() * 0.86
	if t.get("suit") != null:
		# за кольцо на поясе скафандра
		return t.suit.harness_point()
	return t.global_position + Vector3.UP


## Раскрутка: крюк крутится на коротком конце сбоку, по кругу вдоль взгляда
func _swing_center() -> Vector3:
	return p.suit.torso.global_transform * Vector3(0.36, 0.48, -0.02)


func _knot_point() -> Vector3:
	var fwd: Vector3 = -p.visual.global_basis.z
	return _swing_center() + (fwd * sin(_swing_a) + Vector3.UP * cos(_swing_a)) * _loop_r


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
#  Для анимации скафандра
# ---------------------------------------------------------------------------
func pose() -> Dictionary:
	var st := 0
	var anchor := Vector3.ZERO
	var drag := false
	var brace := false
	match state:
		S.NONE:
			st = 1 if equipped else 0
		S.SWING:
			st = 2
		S.FLY:
			st = 3
			anchor = _end
		S.RETURN:
			st = 5                 # сматываю перехватом
			anchor = _pts[N - 1] if _sim_on else _end
		S.LYING:
			st = 4                 # держу лежащую верёвку
			anchor = _end
		S.ATTACHED:
			anchor = _end
			var to := _target_pos() - p.global_position
			to.y = 0.0
			var taut := to.length() > length - 0.15
			st = 5 if pulling else 4
			if mode == M.CARGO and taut and not pulling:
				var v := Vector3(p.velocity.x, 0.0, p.velocity.z)
				if v.length() > 0.5 and v.dot(to) < 0.0:
					drag = true
					st = 6
			if mode != M.CARGO and taut and in_trouble(target) and not pulling:
				brace = true
				st = 7
	return {"state": st, "anchor": anchor, "drag": drag, "brace": brace, "swing_t": swing_t,
		"swing_a": _swing_a, "throw_t": throw_t, "haul": _haul_ph, "charge": charge()}


## Подсказка для экрана
func hint() -> String:
	if not equipped:
		return ""
	match state:
		S.NONE:
			return "ЛКМ (держать) — раскрутить крюк, отпустить — бросить"
		S.SWING:
			var t := _pick_target(range_now())
			return "Отпусти ЛКМ — бросок" + ("  →  %s" % _target_name(t) if t else "  (цели нет — мимо)")
		S.FLY:
			return "Летит!"
		S.ATTACHED:
			var what := "груз"
			if mode == M.RESCUE:
				what = "друга из воды"
			elif mode == M.TETHER:
				what = "друга (связка)"
			return "ПКМ (держать) — тянуть %s     ЛКМ — отцепить крюк" % what
		S.RETURN:
			return "Сматываю верёвку… (отпусти ПКМ — пусть лежит)"
		S.LYING:
			return "Крюк лежит в %d м.  ПКМ (держать) — смотать верёвку" % roundi(_flat(p.global_position, _end))
	return ""


func _target_name(t: Node3D) -> String:
	if t is Parcel:
		return (t as Parcel).display_name
	return str(t.get("player_name"))


# ---------------------------------------------------------------------------
#  Трос: физика (у всех — по одинаковым концам)
# ---------------------------------------------------------------------------
func _simulate(delta: float) -> void:
	if p.suit == null:
		return
	var hand := hand_point()
	match state:
		S.NONE:
			_sim_on = false
			_cur_len = 0.0
			return
		S.SWING:
			swing_t += delta
			var spin := lerpf(4.5, 13.0, clampf(swing_t / CHARGE_TIME, 0.0, 1.0))
			_swing_a += spin * delta
			_loop_r = lerpf(0.42, 0.8, clampf(swing_t / CHARGE_TIME, 0.0, 1.0))
			_end = _knot_point()
			_sim_on = false
			_cur_len = 0.0
			return
		S.FLY:
			_fly_t += delta
			var u := clampf(_fly_t / maxf(_fly_time, 0.01), 0.0, 1.0)
			var t := minf(_fly_t, _fly_time)
			var v0 := (_fly_to - _fly_from - 0.5 * GRAVITY * _fly_time * _fly_time) / _fly_time
			var e := _fly_from + v0 * t + 0.5 * GRAVITY * t * t
			if is_instance_valid(target):
				_fly_to = _fly_to.lerp(_anchor(target), clampf(delta * 8.0, 0.0, 1.0))
				e = e.lerp(_anchor(target), smoothstep(0.75, 1.0, u))
			_end = e
			_cur_len = hand.distance_to(_end) * 1.08 + 0.3
		S.ATTACHED:
			if not is_instance_valid(target):
				return
			if pulling:
				_haul_ph += delta * 1.5
			_end = _anchor(target)
			_cur_len = maxf(length + 0.2, hand.distance_to(_end) * 1.005)
			_tighten = move_toward(_tighten, 1.0, delta * 4.0)
		S.RETURN:
			_cur_len = maxf(_cur_len - RETURN_SPEED * delta, 0.0)
			_haul_ph += delta * 2.0
		S.LYING:
			# крюк падает и лежит; хозяин отходит — верёвка разматывается,
			# дальше длины — крюк волочится следом
			var g := _ground_at(_end, _end.y + 0.6)
			var lake := get_tree().get_first_node_in_group("ice_lake")
			if lake and lake.is_hole(_end.x, _end.z):
				g = IceRiver.bed_y(_end.x, _end.z)
			if _end.y > g + 0.05:
				_end_v.y -= 9.8 * delta
				_end += _end_v * delta
			if _end.y <= g + 0.04:
				_end.y = g + 0.04
				_end_v = Vector3.ZERO
			var hd := hand.distance_to(_end)
			if hd > MAX_LEN:
				var pulled := hand + (_end - hand).normalized() * MAX_LEN
				_end = Vector3(pulled.x, maxf(pulled.y, _ground_at(pulled, pulled.y + 1.0) + 0.04), pulled.z)
			_cur_len = clampf(maxf(_cur_len, hd * 1.03), 0.3, MAX_LEN + 0.5)
	if not _sim_on:
		_sim_on = true
		for i in N:
			_pts[i] = hand.lerp(_end, float(i) / (N - 1)) if state != S.FLY else hand
			_prev[i] = _pts[i]
			_floor[i] = -1000.0
	# звенья
	var rest := maxf(_cur_len, 0.05) / (N - 1)
	var free_end := state == S.RETURN
	_twang = maxf(_twang - delta * 2.2, 0.0)
	var dt2 := delta * delta
	for i in range(1, N):
		if i == N - 1 and not free_end:
			continue
		var cur := _pts[i]
		var v := (cur - _prev[i]) * 0.985
		_prev[i] = cur
		_pts[i] = cur + v + GRAVITY * dt2
	# натянутая верёвка дрожит
	var taut := state == S.ATTACHED and hand.distance_to(_end) > _cur_len * 0.97
	if taut and (pulling or in_trouble(target)):
		var side := (_end - hand).cross(Vector3.UP).normalized()
		for i in range(2, N - 2):
			_pts[i] += side * sin(Time.get_ticks_msec() * 0.06 + i) * 0.0025
	if _twang > 0.0 and state == S.ATTACHED:
		# щелчок крюка: по тросу бежит волна
		var side2 := (_end - hand).cross(Vector3.UP).normalized()
		for i in range(2, N - 2):
			var u2 := float(i) / (N - 1)
			_pts[i] += (side2 * 0.6 + Vector3.UP) * sin(u2 * PI * 3.0 - Time.get_ticks_msec() * 0.03) * 0.03 * _twang * sin(u2 * PI)
	_pts[0] = hand
	if not free_end:
		_pts[N - 1] = _end
	for it in 14:
		for i in N - 1:
			var a := _pts[i]
			var b := _pts[i + 1]
			var d := b - a
			var len := d.length()
			if len < 0.0001:
				continue
			var diff := (len - rest) / len
			var pin_a := i == 0
			var pin_b := i + 1 == N - 1 and not free_end
			if pin_a and pin_b:
				continue
			elif pin_a:
				_pts[i + 1] = b - d * diff
			elif pin_b:
				_pts[i] = a + d * diff
			else:
				_pts[i] = a + d * diff * 0.5
				_pts[i + 1] = b - d * diff * 0.5
		_pts[0] = hand
		if not free_end:
			_pts[N - 1] = _end
	# в полёте трос хлещет — сглаживаем изломы, чтобы летел красивой дугой
	if state == S.FLY:
		for pass_i in 2:
			for i in range(1, N - 1):
				_pts[i] = _pts[i].lerp((_pts[i - 1] + _pts[i + 1]) * 0.5, 0.5)
	# снег и вода под тросом
	_update_floor()
	for i in range(1, N):
		var fl := _floor[i]
		if _pts[i].y < fl + ROPE_R:
			_pts[i].y = fl + ROPE_R
			_prev[i] = _prev[i].lerp(_pts[i], 0.6)   # трение о снег
	if free_end:
		_end = _pts[N - 1]


## Высота снега/воды под звеньями (несколько лучей за кадр, между ними — плавно)
func _update_floor() -> void:
	var lake := get_tree().get_first_node_in_group("ice_lake")
	for k in 3:
		_floor_i = (_floor_i + 1) % 10
		var i := mini(_floor_i * 3 + 1, N - 1)
		var q := _pts[i]
		var y := _ground_at(q, q.y + 1.5)
		if lake and lake.is_hole(q.x, q.z):
			y = IceRiver.bed_y(q.x, q.z)      # в полынье верёвка тонет до дна (к глыбе на дне)
		_floor[i] = y
	for s in 10:
		var i0 := mini(s * 3 + 1, N - 1)
		var i1 := mini((s + 1) * 3 + 1, N - 1)
		if i1 <= i0:
			for j in range(i0 + 1, N):
				_floor[j] = _floor[i0]
			continue
		for j in range(i0 + 1, i1):
			_floor[j] = lerpf(_floor[i0], _floor[i1], float(j - i0) / (i1 - i0))
	_floor[0] = _floor[1]


func _ground_at(q: Vector3, from_y: float) -> float:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, from_y, q.z), Vector3(q.x, from_y - 8.0, q.z), 1)
	var ex: Array[RID] = []
	for d in get_tree().get_nodes_in_group("player"):
		if d is CollisionObject3D:
			ex.append((d as CollisionObject3D).get_rid())
	ray.exclude = ex
	var hit := space.intersect_ray(ray)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -1000.0


# ---------------------------------------------------------------------------
#  Отрисовка (у всех)
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if p == null or p.suit == null:
		return
	_update_coil()
	_im.clear_surfaces()
	_clip.visible = false
	_led_light.light_energy = 0.0
	_update_aim()
	if state == S.NONE:
		return
	var hand := hand_point()
	var knot := _end
	var cd := Vector3.DOWN            ## направление троса у крюка (от руки к крюку)
	var lying := false
	match state:
		S.SWING:
			knot = _knot_point()
			_tube([hand, hand.lerp(knot, 0.5) + Vector3.DOWN * 0.03, knot])
			cd = (knot - hand).normalized()
		S.FLY, S.RETURN, S.LYING:
			if not _sim_on:
				return
			_tube(_smooth(_pts))
			knot = _pts[N - 1]
			cd = (_pts[N - 1] - _pts[N - 3]).normalized()
			lying = state != S.FLY and knot.y < _ground_at(knot, knot.y + 0.5) + 0.12
			if state != S.FLY:
				_tail(hand)
		S.ATTACHED:
			if not is_instance_valid(target) or not _sim_on:
				return
			_tube(_smooth(_pts))
			cd = (_pts[N - 1] - _pts[N - 3]).normalized()
			_tail(hand)
	_place_hook(knot, cd, lying, _delta)
	var blink := fmod(Time.get_ticks_msec() * 0.001, 0.8) < 0.18
	_led_mat.emission_energy_multiplier = 8.0 if blink else 1.2
	_led_light.light_energy = 1.2 if blink else 0.0
	_halo_mat.albedo_color.a = 0.55 if blink else 0.0


## Хвост троса: через вторую руку и петлёй вниз — к мотку на поясе
func _tail(hand: Vector3) -> void:
	var belt: Vector3 = p.suit.coil_mount(false).global_position
	var h0: Vector3 = p.suit.grip_point(0)
	var sag := 0.3 + 0.08 * sin(_haul_ph * TAU * 2.0) if (pulling or state == S.RETURN) else 0.26
	var mid := (h0 + belt) * 0.5 + Vector3.DOWN * sag
	if h0.distance_to(hand) < 0.7:
		_tube([hand, hand.lerp(h0, 0.5) + Vector3.DOWN * 0.03, h0, h0.lerp(mid, 0.5) + Vector3.DOWN * 0.04, mid, mid.lerp(belt, 0.5), belt], 0.9)
	else:
		mid = (hand + belt) * 0.5 + Vector3.DOWN * 0.22
		_tube([hand, hand.lerp(mid, 0.5), mid, mid.lerp(belt, 0.5), belt], 0.9)


## Крюк: ушко к тросу, зуб — вниз/вперёд. Зацепился — защёлка щёлкает, крюк «садится» на кольцо.
func _place_hook(knot: Vector3, cd: Vector3, lying: bool, delta: float) -> void:
	_clip.visible = true
	if cd.length() < 0.5:
		cd = Vector3.DOWN
	var y := -cd.normalized()                    # ось крюка — назад по тросу
	var b: Basis
	if lying:
		# лежит на снегу плашмя
		var yh := Vector3(y.x, 0.0, y.z)
		yh = yh.normalized() if yh.length() > 0.01 else Vector3.FORWARD
		b = Basis(yh.cross(Vector3.UP).normalized(), yh, Vector3.UP)
	else:
		var side := y.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		b = Basis(side, y, side.cross(y).normalized())
	if state == S.FLY:
		# в полёте крюк кувыркается, перед целью выравнивается
		var u := clampf(_fly_t / maxf(_fly_time, 0.01), 0.0, 1.0)
		var spin := (1.0 - smoothstep(0.55, 0.85, u)) * _fly_t * 16.0
		b = b * Basis(Vector3.RIGHT, spin)
	_hook_rot = Basis(_hook_rot.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), clampf(delta * 18.0, 0.0, 1.0)))
	if state == S.SWING or state == S.FLY:
		_hook_rot = b
	var pos := knot
	_clip_t += delta
	var gate_open := 0.0
	if state == S.ATTACHED:
		# зуб садится на кольцо пояса: в первые доли секунды крюк «доезжает» и щёлкает
		var bend := _hook_rot * (Vector3(0.075, -0.165, 0.0) * 1.5)
		var settle := 1.0 - smoothstep(0.0, 0.14, _clip_t)
		pos = knot - bend - _hook_rot.y * 0.12 * settle
		if _clip_t < 0.1:
			gate_open = 0.9
		elif _clip_t < 0.28:
			gate_open = -0.25 * sin((_clip_t - 0.1) / 0.18 * PI * 2.0) * (1.0 - (_clip_t - 0.1) / 0.18)
	elif state == S.FLY:
		var u2 := clampf(_fly_t / maxf(_fly_time, 0.01), 0.0, 1.0)
		gate_open = 0.9 * smoothstep(0.7, 0.95, u2) if is_instance_valid(target) else 0.0
	_gate.rotation.z = gate_open
	_clip.global_transform = Transform3D(_hook_rot.scaled(Vector3.ONE * 1.5), pos)
	_flash.light_energy = maxf(_flash.light_energy - delta * 12.0, 0.0)


func _update_aim() -> void:
	var show: bool = state == S.SWING and p.controlled
	_aim_dots.visible = show
	_aim_ring.visible = show
	_aim_label.visible = show
	if not show:
		return
	var from := _knot_point()
	var tgt := _pick_target(range_now())
	var to: Vector3
	var col := Color(0.8, 0.85, 0.9)
	var text := "%d м" % roundi(range_now())
	if tgt:
		to = _anchor(tgt)
		if tgt is Parcel:
			col = Color(1.0, 0.8, 0.25)
			text = "ГРУЗ"
		elif tgt.get("is_swimming") or tgt.get("is_diving"):
			col = Color(0.35, 0.75, 1.0)
			text = "СПАСТИ"
		else:
			col = Color(0.45, 1.0, 0.55)
			text = "СВЯЗКА"
	else:
		to = _miss_point(from, range_now())
	var T := clampf(from.distance_to(to) / 15.0 + 0.18, 0.28, 0.95)
	var v0 := (to - from - 0.5 * GRAVITY * T * T) / T
	var mm := _aim_dots.multimesh
	var flow := fmod(Time.get_ticks_msec() * 0.0015, 1.0)
	for i in mm.instance_count:
		var u := (float(i) + flow) / mm.instance_count
		var t := u * T
		var q := from + v0 * t + 0.5 * GRAVITY * t * t
		var sc := lerpf(0.7, 1.15, u)
		if q.distance_to(from) < 0.7:
			sc = 0.0                 # у самой головы не мельтешим
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), q))
		mm.set_instance_color(i, Color(col.r, col.g, col.b, lerpf(0.35, 0.95, u)))
	var base := (tgt.global_position if tgt else to) + Vector3.UP * 0.05
	if tgt and (tgt.get("is_swimming") or tgt.get("is_diving")):
		var lake := get_tree().get_first_node_in_group("ice_lake")
		if lake:
			base.y = lake.water_y(base.z) + 0.05
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.08
	_aim_ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(pulse, 1.0, pulse)), base)
	_aim_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
	_aim_label.text = text
	_aim_label.modulate = col
	_aim_label.global_position = base + Vector3.UP * (2.35 if tgt and not (tgt is Parcel) else 1.1)


## Сгладить ломаную (между звеньями — ещё по точке)
func _smooth(pts: PackedVector3Array) -> Array:
	var out: Array = []
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		out.append(p1)
		out.append((p1 + p2) * 0.5 + ((p1 - p0) - (p3 - p2)) * 0.0625)
	out.append(pts[n - 1])
	return out


## Трубка вдоль точек (плетёный трос)
func _tube(pts: Array, r_mul := 1.0) -> void:
	var n := pts.size()
	if n < 2:
		return
	var r := ROPE_R * r_mul
	var sides := 8
	var normal := Vector3.ZERO
	var rings: Array = []
	var dist := 0.0
	for i in n:
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, n - 1)]
		var t := b - a
		if t.length() < 0.00001:
			t = Vector3.FORWARD
		t = t.normalized()
		if i == 0:
			normal = t.cross(Vector3.UP)
			if normal.length() < 0.01:
				normal = t.cross(Vector3.RIGHT)
		normal = (normal - t * normal.dot(t))
		if normal.length() < 0.0001:
			normal = t.cross(Vector3.RIGHT)
		normal = normal.normalized()
		var bi := t.cross(normal)
		if i > 0:
			dist += (pts[i] as Vector3).distance_to(pts[i - 1])
		rings.append([pts[i], normal, bi, dist, t])
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	for i in n - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var u0: float = r0[3] * 3.0
			var u1: float = r1[3] * 3.0
			var k0 := float(k) / sides
			var k1 := float(k + 1) / sides
			_vert(r0, a0, r, Vector2(u0, k0))
			_vert(r1, a0, r, Vector2(u1, k0))
			_vert(r1, a1, r, Vector2(u1, k1))
			_vert(r0, a0, r, Vector2(u0, k0))
			_vert(r1, a1, r, Vector2(u1, k1))
			_vert(r0, a1, r, Vector2(u0, k1))
	_im.surface_end()


func _vert(ring: Array, a: float, r: float, uv: Vector2) -> void:
	var nrm := (ring[1] as Vector3) * cos(a) + (ring[2] as Vector3) * sin(a)
	_im.surface_set_normal(nrm)
	_im.surface_set_tangent(Plane(ring[4] as Vector3, 1.0))
	_im.surface_set_uv(uv)
	_im.surface_add_vertex((ring[0] as Vector3) + nrm * r)


## Петля-лассо: кольцо из того же троса, узел — в точке knot
func _ring(c: Vector3, n: Vector3, r: float, knot: Vector3) -> void:
	n = n.normalized()
	var u := knot - c
	u = u - n * u.dot(n)
	if u.length() < 0.001:
		u = _flat_dir(Vector3.FORWARD, n)
	u = u.normalized()
	var w := n.cross(u)
	var pts: Array = []
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(c + (u * cos(a) + w * sin(a)) * r)
	_tube(pts, 1.0)


## Направление в плоскости петли (перпендикулярно n), ближе всего к d
static func _flat_dir(d: Vector3, n: Vector3) -> Vector3:
	var x := d - n * d.dot(n)
	if x.length() < 0.001:
		x = Vector3.RIGHT - n * n.x
	return x.normalized()


static func _basis_y(y: Vector3) -> Basis:
	y = y.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## Моток: в левой руке (надета, не брошена) или на поясе; худеет, когда верёвка снаружи
func _update_coil() -> void:
	var have: bool = p.has_item("rope")
	var parent: Node3D = null
	if have:
		var in_hand: bool = equipped and (state == S.NONE or state == S.SWING) and p.held_parcel == null and p.held_friend == null \
			and p.has_limb("arm_l")
		parent = p.suit.coil_mount(in_hand)
	if parent != _coil_parent:
		if _coil.get_parent():
			_coil.get_parent().remove_child(_coil)
		if parent:
			parent.add_child(_coil)
			_coil.transform = Transform3D.IDENTITY
		_coil_parent = parent
	var k := 1.0 - clampf(_cur_len / MAX_LEN, 0.0, 1.0) * 0.55
	_coil.scale = Vector3(k, 1.0, k)


# ---------------------------------------------------------------------------
#  Сеть: хозяин рассылает состояние
# ---------------------------------------------------------------------------
func _set_state(s: int) -> void:
	var was := state
	state = s
	_on_state(was, s)
	if p.call("_online"):
		var path := target.get_path() if is_instance_valid(target) else NodePath("")
		_rpc_state.rpc(s, mode, path, length, equipped, _fly_from, _fly_to, _fly_time)


func _on_state(was: int, s: int) -> void:
	match s:
		S.SWING:
			swing_t = 0.0
			_loop_r = 0.3
		S.FLY:
			_fly_t = 0.0
			throw_t = 0.0
			_sim_on = false
			_end = _fly_from
		S.ATTACHED:
			_tighten = 0.0
			_clip_t = 0.0
			_twang = 1.0
			_snap_fx.global_position = _end
			_snap_fx.restart()
			_spark_fx.global_position = _end
			_spark_fx.restart()
			_flash.global_position = _end + Vector3.UP * 0.2
			_flash.light_energy = 3.0
		S.LYING:
			_end_v = Vector3.ZERO
			if was == S.RETURN and _sim_on:
				_end = _pts[N - 1]
		S.RETURN:
			if was == S.ATTACHED or was == S.FLY or was == S.LYING:
				_cur_len = maxf(_cur_len, hand_point().distance_to(_end))
		S.NONE:
			target = null
			pulling = false
			_sim_on = false
			_cur_len = 0.0


func set_equipped(on: bool) -> void:
	equipped = on
	if p.call("_online"):
		var path := target.get_path() if is_instance_valid(target) else NodePath("")
		_rpc_state.rpc(state, mode, path, length, equipped, _fly_from, _fly_to, _fly_time)


func _sync_len() -> void:
	if p.call("_online"):
		_rpc_len.rpc(length, pulling)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_state(s: int, m: int, path: NodePath, len: float, eq: bool, from: Vector3, to: Vector3, ft: float) -> void:
	var was := state
	mode = m
	length = len
	equipped = eq
	target = get_node_or_null(path) as Node3D if not path.is_empty() else null
	_fly_from = from
	_fly_to = to
	_fly_time = ft
	state = s
	_on_state(was, s)
	if s == S.ATTACHED and was != S.ATTACHED and is_instance_valid(target) and target.has_method("on_roped"):
		target.call("on_roped", p, m)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_len(len: float, pull: bool) -> void:
	length = len
	pulling = pull


func _exit_tree() -> void:
	if is_instance_valid(_coil) and _coil.get_parent() == null:
		_coil.queue_free()
