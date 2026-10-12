extends Node3D
## Верёвка из инвентаря (до 14 м). Есть у каждого дрона (и у ботов), узел "Rope".
##
## Управление (верёвка надета в инвентаре, I):
##  * ЛКМ — держишь: раскручиваешь петлю над головой; отпустил — бросок туда,
##    куда смотрит камера (сама находит ближайшего друга или груз в «прицеле»);
##  * ПКМ (держать) — тянуть: перехват руками, верёвка укорачивается;
##  * ЛКМ ещё раз — отвязать и смотать.
## Что получается, зависит от того, во что попала петля:
##  * друг в воде — СПАСЕНИЕ: он хватается за конец, не тонет, тянешь — выползает на лёд;
##  * друг на суше — СВЯЗКА: верёвка за пояс; разойтись дальше нельзя, а если один
##    провалился или сорвался — второй его держит (и может вытянуть, ПКМ);
##  * груз — ЛАССО/ВОЛОК: тянешь — груз едет к тебе (лёгкий подтянул — сразу в руки),
##    идёшь прочь — тащишь волоком через плечо (тяжёлый — медленно).
## Сеть: состояние верёвки рассылает хозяин; тянущую силу каждый компьютер
## прикладывает к своему дрону сам, к грузу — хост.

enum S { NONE, SWING, FLY, ATTACHED, RETURN }
enum M { CARGO, RESCUE, TETHER }

const MAX_LEN := 14.0
const MIN_LEN := 1.3
const THROW_SPEED := 17.0
const REEL_SPEED := 2.3
const AIM_ANGLE := 30.0
const SEGMENTS := 22
const ROPE_R := 0.017

var p: CharacterBody3D            ## хозяин (player.gd)
var equipped := false
var state := S.NONE
var mode := M.CARGO
var target: Node3D = null
var length := 0.0
var pulling := false
var aim_override: Node3D = null   ## бот: в кого бросать
var swing_t := 0.0
var throw_t := 0.0                ## сколько назад бросил (для позы)

var _fly_t := 0.0
var _fly_time := 0.3
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.ZERO
var _ret_t := 0.0
var _ret_from := Vector3.ZERO
var _send_t := 0.0
var _end := Vector3.ZERO
var _segs: Array[MeshInstance3D] = []
var _loop: MeshInstance3D
var _waist: MeshInstance3D
var _coil: MeshInstance3D
var _mat: StandardMaterial3D
var _coil_parent: Node3D = null


func setup(player: CharacterBody3D) -> void:
	p = player
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.78, 0.55, 0.28)
	_mat.roughness = 0.85
	var seg := CylinderMesh.new()
	seg.top_radius = ROPE_R
	seg.bottom_radius = ROPE_R
	seg.height = 1.0
	seg.radial_segments = 6
	seg.rings = 1
	seg.material = _mat
	for i in SEGMENTS:
		var mi := MeshInstance3D.new()
		mi.mesh = seg
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_segs.append(mi)
	var loop := TorusMesh.new()
	loop.inner_radius = 0.09
	loop.outer_radius = 0.12
	loop.rings = 16
	loop.ring_segments = 6
	loop.material = _mat
	_loop = MeshInstance3D.new()
	_loop.mesh = loop
	_loop.visible = false
	add_child(_loop)
	var waist := TorusMesh.new()
	waist.inner_radius = 0.29
	waist.outer_radius = 0.33
	waist.rings = 24
	waist.ring_segments = 6
	waist.material = _mat
	_waist = MeshInstance3D.new()
	_waist.mesh = waist
	_waist.visible = false
	add_child(_waist)
	# моток: в руке, когда верёвка надета, иначе — на поясе
	var coil := TorusMesh.new()
	coil.inner_radius = 0.07
	coil.outer_radius = 0.13
	coil.rings = 18
	coil.ring_segments = 10
	coil.material = _mat
	_coil = MeshInstance3D.new()
	_coil.mesh = coil
	_coil.name = "RopeCoil"


# ---------------------------------------------------------------------------
#  Управление (только у того, кто управляет этим дроном)
# ---------------------------------------------------------------------------
func local_update(delta: float) -> void:
	if not p.has_item("rope"):
		equipped = false
	throw_t += delta
	var busy: bool = p.held_parcel != null or p.held_friend != null or p.carried_by != null \
		or p.is_dead or p.is_frozen or p.rescue_role != 0 or p.visual.get_node_or_null("HockeyStick") != null
	match state:
		S.NONE:
			if equipped and not busy and p._just("use_item"):
				_set_state(S.SWING)
		S.SWING:
			swing_t += delta
			if busy:
				_set_state(S.NONE)
			elif not p._held("use_item") or swing_t > 2.5:
				_throw()
		S.FLY:
			_fly_t += delta
			if _fly_t >= _fly_time:
				_arrive()
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
				var sp := REEL_SPEED * (1.25 if mode == M.RESCUE else 1.0)
				length = maxf(length - sp * delta, MIN_LEN)
			# лёгкий груз подтянул вплотную — сразу берём в руки
			if mode == M.CARGO and target is Parcel and (target as Parcel).required_carriers <= 1 \
					and pulling and _flat(p.global_position, target.global_position) < 1.7 and p.held_parcel == null:
				var parcel := target as Parcel
				_detach()
				p.grab_parcel(parcel)
				return
			# друга вытащили из воды — верёвку не держим
			if mode == M.RESCUE and not target.get("is_swimming") and not target.get("is_diving") \
					and _flat(p.global_position, target.global_position) < 2.2:
				_detach()
				return
			_send_t -= delta
			if _send_t <= 0.0:
				_send_t = 0.15
				_sync_len()
		S.RETURN:
			_ret_t += delta
			if _ret_t >= 0.35:
				_set_state(S.NONE)


## Бот или другой код: бросить прямо в этот узел
func throw_at(node: Node3D) -> void:
	if state != S.NONE:
		return
	aim_override = node
	equipped = true
	swing_t = 0.4
	_throw()


func _throw() -> void:
	var from := hand_point()
	var tgt: Node3D = aim_override if is_instance_valid(aim_override) else _pick_target()
	aim_override = null
	throw_t = 0.0
	if p.suit:
		p.suit.throw_anim()
	if tgt != null:
		target = tgt
		_fly_to = _anchor(tgt)
	else:
		target = null
		var dir := _aim_dir()
		_fly_to = from + dir * 8.0 + Vector3.DOWN * 0.8
	_fly_from = from
	_fly_time = clampf(from.distance_to(_fly_to) / THROW_SPEED, 0.15, 0.8)
	_fly_t = 0.0
	_set_state(S.FLY)


func _arrive() -> void:
	if target == null or not is_instance_valid(target) or _flat(p.global_position, _target_pos()) > MAX_LEN + 1.0:
		target = null
		_ret_from = _fly_to
		_set_state(S.RETURN)
		return
	if target is Parcel:
		mode = M.CARGO
	elif target.get("is_swimming") or target.get("is_diving"):
		mode = M.RESCUE
	else:
		mode = M.TETHER
	length = clampf(_flat(p.global_position, _target_pos()) + 0.3, MIN_LEN, MAX_LEN)
	_set_state(S.ATTACHED)
	if target.has_method("on_roped"):
		target.call("on_roped", p, mode)


func _detach() -> void:
	_ret_from = _end
	pulling = false
	if is_instance_valid(target) and target.has_method("on_roped"):
		target.call("on_roped", null, -1)
	target = null
	_set_state(S.RETURN)


## Куда целится: камера (у человека) или взгляд дрона (у бота)
func _aim_dir() -> Vector3:
	var d: Vector3
	if p.is_bot:
		d = -p.visual.global_basis.z
	else:
		d = -p.camera.global_basis.z
	d.y = maxf(d.y, -0.1)
	return d.normalized()


func _pick_target() -> Node3D:
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
		if dist < 1.2 or dist > MAX_LEN:
			continue
		var ang := rad_to_deg(aim_h.angle_to(to / dist))
		if ang > AIM_ANGLE:
			continue
		var score := ang + dist * 0.6
		if score < best_score:
			best_score = score
			best = c
	return best


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
					if not in_trouble(target) and dist - length > 0.6:
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
			want = minf(ex * 2.0, 3.0)
		var toward := vel.dot(dir)
		if toward < want:
			vel += dir * (want - toward)
	return vel


func _physics_process(delta: float) -> void:
	# хост тянет груз за верёвку (чья бы верёвка ни была)
	if p == null or state != S.ATTACHED or mode != M.CARGO or not multiplayer.is_server():
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
		return p.suit.hand_point(1)
	return p.global_position + Vector3.UP * 1.0


func _target_pos() -> Vector3:
	if not is_instance_valid(target):
		return p.global_position
	return target.global_position


## Куда цепляется конец
func _anchor(t: Node3D) -> Vector3:
	if t is Parcel:
		return t.global_position + Vector3.UP * 0.1
	if t.get("suit") != null:
		if mode == M.RESCUE and state == S.ATTACHED:
			return t.suit.hand_point(1)
		return t.global_position + Vector3.UP * 0.95
	return t.global_position + Vector3.UP


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
		S.FLY, S.RETURN:
			st = 3
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
	return {"state": st, "anchor": anchor, "drag": drag, "brace": brace, "swing_t": swing_t, "throw_t": throw_t}


## Подсказка для экрана
func hint() -> String:
	if not equipped:
		return ""
	match state:
		S.NONE:
			return "ЛКМ (держать и отпустить) — бросить верёвку"
		S.SWING:
			return "Отпусти ЛКМ — бросок"
		S.ATTACHED:
			var what := "груз"
			if mode == M.RESCUE:
				what = "друга из воды"
			elif mode == M.TETHER:
				what = "друга (связка)"
			return "ПКМ (держать) — тянуть %s     ЛКМ — отвязать" % what
	return ""


# ---------------------------------------------------------------------------
#  Отрисовка (у всех)
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if p == null or p.suit == null:
		return
	_update_coil()
	var hand := hand_point()
	var pts: Array[Vector3] = []
	_loop.visible = false
	_waist.visible = false
	match state:
		S.NONE:
			pass
		S.SWING:
			# петля крутится над головой
			var head: Vector3 = p.suit.head.global_position + Vector3.UP * 0.35
			var a := swing_t * 11.0
			_end = head + Vector3(cos(a), 0.0, sin(a)) * 0.55
			pts = _curve(hand, _end, 0.05, 6)
			_loop.visible = true
			_loop.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.2), _end)
		S.FLY:
			var u := clampf(_fly_t / maxf(_fly_time, 0.01), 0.0, 1.0)
			if is_instance_valid(target):
				_fly_to = _fly_to.lerp(_anchor(target), clampf(delta * 12.0, 0.0, 1.0))
			_end = _fly_from.lerp(_fly_to, u) + Vector3.UP * sin(u * PI) * _fly_from.distance_to(_fly_to) * 0.15
			pts = _curve(hand, _end, 0.05, SEGMENTS)
			_loop.visible = true
			_loop.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (2.2 - u * 0.8)), _end)
		S.ATTACHED:
			if not is_instance_valid(target):
				return
			_end = _anchor(target)
			var dist := hand.distance_to(_end)
			var slack := maxf(length - _flat(p.global_position, _target_pos()), 0.0)
			var sag := clampf(slack * 0.45 + dist * 0.02, 0.02, 1.6)
			var pose_d := pose()
			if pose_d["drag"]:
				var sh: Vector3 = p.suit.torso.global_transform * Vector3(0.24, 0.55, 0.05)
				pts = _curve(hand, sh, 0.0, 4)
				pts.pop_back()
				pts.append_array(_curve(sh, _end, sag, SEGMENTS - 4))
			else:
				pts = _curve(hand, _end, sag, SEGMENTS)
			if mode == M.TETHER:
				_waist.visible = true
				_waist.global_transform = Transform3D(Basis(Vector3.UP, target.global_rotation.y), target.global_position + Vector3.UP * 0.93)
			elif mode == M.CARGO:
				_loop.visible = true
				var ext := Vector3(0.3, 0.3, 0.3)
				if target is Parcel:
					ext = p.suit.extents(target)
				var r := Vector2(ext.x, ext.z).length() / 0.105
				_loop.global_transform = Transform3D(target.global_basis.orthonormalized().scaled(Vector3(r, 1.0, r)), target.global_position + Vector3.UP * 0.02)
			else:
				_loop.visible = true
				_loop.global_transform = Transform3D(Basis.IDENTITY, _end)
		S.RETURN:
			var u := clampf(_ret_t / 0.35, 0.0, 1.0)
			_end = _ret_from.lerp(hand, u * u)
			pts = _curve(hand, _end, 0.3 * (1.0 - u), 10)
	_draw_line(pts)


func _curve(a: Vector3, b: Vector3, sag: float, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var c := (a + b) * 0.5 + Vector3.DOWN * sag * 2.0
	for i in n + 1:
		var t := float(i) / n
		var q := a.lerp(c, t).lerp(c.lerp(b, t), t)
		out.append(q)
	return out


func _draw_line(pts: Array[Vector3]) -> void:
	for i in SEGMENTS:
		var mi := _segs[i]
		if i + 1 >= pts.size():
			mi.visible = false
			continue
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var len := d.length()
		if len < 0.001:
			mi.visible = false
			continue
		mi.visible = true
		var y := d / len
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		mi.global_transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)


## Моток: в левой руке (надета, не брошена) или на поясе
func _update_coil() -> void:
	var visible_coil: bool = p.has_item("rope") and state != S.ATTACHED and state != S.FLY
	var parent: Node3D = null
	if visible_coil:
		parent = p.suit.coil_mount(equipped and p.held_parcel == null and p.held_friend == null)
	if parent != _coil_parent:
		if _coil.get_parent():
			_coil.get_parent().remove_child(_coil)
		if parent:
			parent.add_child(_coil)
			_coil.transform = Transform3D.IDENTITY
		_coil_parent = parent


# ---------------------------------------------------------------------------
#  Сеть: хозяин рассылает состояние
# ---------------------------------------------------------------------------
func _set_state(s: int) -> void:
	state = s
	if s == S.SWING:
		swing_t = 0.0
	elif s == S.RETURN:
		_ret_t = 0.0
	elif s == S.NONE:
		target = null
		pulling = false
	if p.call("_online"):
		var path := target.get_path() if is_instance_valid(target) else NodePath("")
		_rpc_state.rpc(s, mode, path, length, equipped, _fly_from, _fly_to, _fly_time)


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
	state = s
	mode = m
	length = len
	equipped = eq
	target = get_node_or_null(path) as Node3D if not path.is_empty() else null
	if s == S.FLY:
		_fly_from = from
		_fly_to = to
		_fly_time = ft
		_fly_t = 0.0
		throw_t = 0.0
	elif s == S.SWING:
		swing_t = 0.0
	elif s == S.RETURN:
		_ret_t = 0.0
		_ret_from = _end
	if s == S.ATTACHED and was != S.ATTACHED and is_instance_valid(target) and target.has_method("on_roped"):
		target.call("on_roped", p, m)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_len(len: float, pull: bool) -> void:
	length = len
	pulling = pull


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	if is_instance_valid(_coil) and _coil.get_parent() == null:
		_coil.queue_free()
