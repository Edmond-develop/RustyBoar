extends Node3D
## Шаг 74: гнёзда механизмов Пика — куда ставят детали (peak_part.gd).
## Подошёл с деталью к гнезду, E — деталь «вставлена» и ставится, пока держишь E (можно и другу продолжить):
##   1) вставить — деталь въезжает в гнездо по оси;  2) повернуть — доворачивается до щелчка;
##   3) закрутить болты — гайки по очереди накручиваются (трещотка ключа).
## Руки работают (поза 14: толкаю → кручу двумя руками → ключом), звук на каждом этапе, искры в конце,
## лампочка гнезда: красная → жёлтая (ставят) → зелёная. Снимаемые детали (шестерни, гири): E пустыми руками.
## Хозяин гнезда (модуль) решает, подходит ли деталь (socket_accept → "" или причина), и узнаёт о
## поставленной/снятой (on_socket / on_unsocket). Решает хост; прогресс шлётся всем 10 раз/с.

const SFX := preload("res://scripts/sfx.gd")
const PART := preload("res://scenes/world/peak_part.gd")
const SLIDE_END := 0.34
const TURN_END := 0.6
const REACH := 2.1                ## с какого расстояния до гнезда E ставит деталь

var mtn: Node
var sockets := {}                 ## id → словарь гнезда
var _sync_t := 0.0
var _sparks: GPUParticles3D
var _puff: GPUParticles3D
var _lamp_mats := {}
var _bolt_mesh: ArrayMesh
var _bolt_mat: StandardMaterial3D
var _reject_ms := -10000


func build() -> void:
	add_to_group("part_sockets")
	SFX.prewarm()
	_sparks = FX.particles(Color(1.0, 0.75, 0.3), 26, 0.45, 0.035, 2.0, 4.5, Vector3(0, -9.0, 0), 70.0, true, true)
	add_child(_sparks)
	_puff = FX.particles(Color(0.85, 0.85, 0.85, 0.5), 14, 0.9, 0.18, 0.4, 1.2, Vector3(0, 0.6, 0), 60.0, true)
	add_child(_puff)
	for k in ["glow_r", "glow_y", "glow_g"]:
		_lamp_mats[k] = PART.mat(k)
	# болт: шестигранная головка с шайбой
	var mb = PART.ModelBuilder.new()
	mb.cyl(0.03, 0.03, 0.022, Vector3(0, 0.011, 0), Basis.IDENTITY, "steel", 6)
	mb.cyl(0.042, 0.042, 0.006, Vector3.ZERO, Basis.IDENTITY, "steel", 12)
	mb.cyl(0.012, 0.012, 0.09, Vector3(0, -0.045, 0), Basis.IDENTITY, "steel", 6)
	var tmp := Node3D.new()
	mb.commit(tmp, Callable(PART, "mat"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in tmp.get_children():
		st.append_from((c as MeshInstance3D).mesh, 0, Transform3D.IDENTITY)
	_bolt_mesh = st.commit()
	tmp.free()
	_bolt_mat = PART.mat("steel")


## Новое гнездо. seat — где и как стоит деталь; axis — откуда её вставляют (наружу, к игроку);
## stand — где стоит ставящий. opts: slide (м), turn (рад), bolts (шт), bolt_r (м), time (с), removable, title,
## lamp_at (точка лампочки), spin_axis (у шестерён — их ось).
func add_socket(id: String, owner_node: Node, seat: Transform3D, axis: Vector3, stand: Vector3, opts := {}) -> Dictionary:
	var s := {
		"id": id, "owner": owner_node, "seat": seat, "axis": axis.normalized(), "stand": stand,
		"slide": float(opts.get("slide", 0.45)), "turn": float(opts.get("turn", PI * 0.5)),
		"nb": int(opts.get("bolts", 2)), "bolt_r": float(opts.get("bolt_r", 0.2)),
		"time": float(opts.get("time", 2.6)), "removable": bool(opts.get("removable", false)),
		"title": String(opts.get("title", "гнездо")), "state": 0, "part": null, "prog": 0.0, "last_k": 0.0,
		"spin": 0.0, "bolts": [], "bolt_base": [], "lamp": null, "who": 0,
	}
	# болты (лежат по кругу вокруг оси; один — по центру)
	var ax: Vector3 = s["axis"]
	var p1 := ax.cross(Vector3.UP)
	if p1.length() < 0.1:
		p1 = ax.cross(Vector3.RIGHT)
	p1 = p1.normalized()
	var p2 := ax.cross(p1).normalized()
	var nb: int = s["nb"]
	for i in nb:
		var a := TAU * i / maxf(nb, 1) + 0.4
		var r: float = 0.0 if nb == 1 else float(s["bolt_r"])
		var base: Vector3 = seat.origin + (p1 * cos(a) + p2 * sin(a)) * r + ax * float(opts.get("bolt_out", 0.06))
		var mi := MeshInstance3D.new()
		mi.mesh = _bolt_mesh
		mi.material_override = _bolt_mat
		mi.visible = false
		add_child(mi)
		(s["bolts"] as Array).append(mi)
		(s["bolt_base"] as Array).append(base)
	if opts.has("lamp_at"):
		var lm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		sm.radial_segments = 8
		sm.rings = 4
		lm.mesh = sm
		lm.material_override = _lamp_mats["glow_r"]
		lm.position = opts["lamp_at"]
		add_child(lm)
		s["lamp"] = lm
	mtn.add_hold("S:" + id, stand, 1.0, 1.8)
	sockets[id] = s
	return s


func part_in(id: String) -> Node:
	var s: Dictionary = sockets.get(id, {})
	return s.get("part") if int(s.get("state", 0)) == 2 else null


func is_done(id: String) -> bool:
	return int((sockets.get(id, {}) as Dictionary).get("state", 0)) == 2


# ---------------------------------------------------------------------------
#  E у гнезда (зовёт игрок)
# ---------------------------------------------------------------------------

func try_socket(d: Node3D) -> bool:
	var part = d.get("held_parcel")
	var p := d.global_position
	if part != null and part.get("kind") != null and String(part.get("kind")) != "":
		var best := ""
		var bd := REACH
		for id in sockets:
			var s: Dictionary = sockets[id]
			if int(s["state"]) != 0:
				continue
			var dd := minf(p.distance_to(s["stand"]), p.distance_to((s["seat"] as Transform3D).origin))
			if dd < bd:
				bd = dd
				best = id
		if best == "":
			return false
		var why: String = sockets[best]["owner"].socket_accept(best, part)
		if why != "":
			# не подходит: первый раз — подсказка (деталь в руках), второй раз подряд — просто положить
			if Time.get_ticks_msec() - _reject_ms < 2500:
				return false
			_reject_ms = Time.get_ticks_msec()
			mtn.say(why + "  (ещё раз E — положить)")
			SFX.play(self, (sockets[best]["seat"] as Transform3D).origin, "fail", -4.0)
			return true
		if multiplayer.is_server():
			_req_install(best, part.get_path(), int(d.peer_id))
		else:
			_req_install.rpc_id(1, best, part.get_path(), int(d.peer_id))
		return true
	if part == null:
		# рядом лежит деталь — E её поднимает (снимать с механизма — когда рядом ничего не лежит)
		for lp in get_tree().get_nodes_in_group("peak_part"):
			if not lp.is_delivered and not lp.is_held and (lp as Node3D).global_position.distance_to(p) < 1.7:
				return false
		# только что ставили рядом — второе нажатие E не снимает другую деталь
		for id3 in sockets:
			var s3: Dictionary = sockets[id3]
			if p.distance_to(s3["stand"]) < 2.5 and (int(s3["state"]) == 1 or mtn.now() - float(s3.get("done_t", -100.0)) < 1.5):
				return false
		var cand := ""
		var cand_t := -1e9
		for id2 in sockets:
			var s2: Dictionary = sockets[id2]
			if int(s2["state"]) != 2 or not bool(s2["removable"]):
				continue
			if p.distance_to(s2["stand"]) < 1.5 or p.distance_to((s2["seat"] as Transform3D).origin) < 1.6:
				# снимаю ближайшую; если места совпадают (чаша весов) — последнюю поставленную
				var sc := -p.distance_to(s2["stand"]) * 100.0 + float(s2.get("done_t", 0.0)) * 0.001
				if sc > cand_t:
					cand_t = sc
					cand = id2
		if cand != "":
			var own: Node = sockets[cand]["owner"]
			if own.has_method("can_remove") and not own.can_remove(cand):
				mtn.say("Сейчас не снять — механизм работает")
				return true
			if multiplayer.is_server():
				_req_remove(cand, int(d.peer_id))
			else:
				_req_remove.rpc_id(1, cand, int(d.peer_id))
			return true
	return false


@rpc("any_peer", "call_remote", "reliable")
func _req_install(id: String, path: NodePath, pid: int) -> void:
	if not multiplayer.is_server() or not sockets.has(id):
		return
	var s: Dictionary = sockets[id]
	var part := get_node_or_null(path)
	if int(s["state"]) != 0 or part == null or part.is_delivered or not (part.holders as Array).has(pid):
		return
	if String(s["owner"].socket_accept(id, part)) != "":
		return
	if mtn._online():
		_begin.rpc(id, path, pid)
	else:
		_begin(id, path, pid)


@rpc("authority", "call_local", "reliable")
func _begin(id: String, path: NodePath, pid: int) -> void:
	var s: Dictionary = sockets[id]
	var part := get_node_or_null(path)
	if part == null:
		return
	s["state"] = 1
	s["part"] = part
	s["prog"] = 0.0
	s["last_k"] = 0.0
	s["who"] = pid
	part._set_delivered(_xf(s, 0.0))
	for b in s["bolts"]:
		(b as Node3D).visible = false
	SFX.play(self, (s["seat"] as Transform3D).origin, "slide", -2.0)


@rpc("any_peer", "call_remote", "reliable")
func _req_remove(id: String, pid: int) -> void:
	if not multiplayer.is_server() or not sockets.has(id):
		return
	var s: Dictionary = sockets[id]
	if int(s["state"]) != 2 or not bool(s["removable"]) or s["part"] == null:
		return
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or d.get("held_parcel") != null:
		return
	if mtn._online():
		_removed.rpc(id, pid)
	else:
		_removed(id, pid)


@rpc("authority", "call_local", "reliable")
func _removed(id: String, pid: int) -> void:
	var s: Dictionary = sockets[id]
	var part = s["part"]
	s["state"] = 0
	s["prog"] = 0.0
	s["part"] = null
	s["spin"] = 0.0
	for b in s["bolts"]:
		(b as Node3D).visible = false
	if part != null and is_instance_valid(part):
		part._undeliver(pid)
	SFX.play(self, (s["seat"] as Transform3D).origin, "ratchet", -3.0, 1.3)
	s["owner"].on_unsocket(id, part)


@rpc("authority", "call_local", "reliable")
func _done(id: String) -> void:
	var s: Dictionary = sockets[id]
	s["state"] = 2
	s["prog"] = 1.0
	s["done_t"] = mtn.now()
	var at: Vector3 = (s["seat"] as Transform3D).origin
	SFX.play(self, at, "clank", 0.0, 0.9)
	SFX.play(self, at, "ding", -6.0)
	_sparks.global_position = at + (s["axis"] as Vector3) * 0.15
	_sparks.restart()
	_sparks.emitting = true
	var me = Network.local_player
	if me and me.global_position.distance_to(at) < 6.0:
		me.add_shake(0.06)
	s["owner"].on_socket(id, s["part"])


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_prog(arr: Array) -> void:
	for k in range(0, arr.size() - 1, 2):
		var s: Dictionary = sockets.get(String(arr[k]), {})
		if not s.is_empty() and int(s["state"]) == 1:
			s["prog"] = float(arr[k + 1])


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func server(delta: float) -> void:
	var out := []
	for id in sockets:
		var s: Dictionary = sockets[id]
		if int(s["state"]) != 1:
			continue
		var part = s["part"]
		if part == null or not is_instance_valid(part):
			s["state"] = 0
			continue
		if _held_at(s):
			s["prog"] = minf(float(s["prog"]) + delta / float(s["time"]), 1.0)
			if float(s["prog"]) >= 1.0:
				if mtn._online():
					_done.rpc(id)
				else:
					_done(id)
				continue
		out.append(id)
		out.append(float(s["prog"]))
	_sync_t -= delta
	if _sync_t <= 0.0 and not out.is_empty() and mtn._online():
		_sync_t = 0.1
		_sync_prog.rpc(out)


## Хост: держит ли кто-то E у этого гнезда (или у соседнего с тем же местом — чаши весов)
func _held_at(s: Dictionary) -> bool:
	if not mtn.holders("S:" + String(s["id"])).is_empty():
		return true
	for pid in mtn.hold_map:
		var h := String(mtn.hold_map[pid])
		if mtn.holds.has(h) and (mtn.holds[h][0] as Vector3).distance_to(s["stand"]) < 0.8:
			return true
	return false


## Гнездо, которое ставят с этого места (несколько гнёзд с одним местом — какое сейчас ставят)
func _installing_from(hp: String) -> Dictionary:
	if not mtn.holds.has(hp):
		return {}
	var at: Vector3 = mtn.holds[hp][0]
	for id in sockets:
		var s: Dictionary = sockets[id]
		if int(s["state"]) == 1 and (s["stand"] as Vector3).distance_to(at) < 0.8:
			return s
	return {}


## Сдвинуть гнездо (чаша весов качается) — стоящая деталь едет вместе
func move_seat(id: String, xf: Transform3D) -> void:
	if not sockets.has(id):
		return
	var s: Dictionary = sockets[id]
	var d := xf.origin - (s["seat"] as Transform3D).origin
	s["seat"] = xf
	var bb: Array = s["bolt_base"]
	for i in bb.size():
		bb[i] = (bb[i] as Vector3) + d
	if int(s["state"]) == 2 and s["part"] != null and is_instance_valid(s["part"]):
		(s["part"] as Node3D).global_transform = _xf(s, 1.0)


func local(d: Node3D, hp: String, _holding: bool, _delta: float) -> void:
	if hp != "":
		var s: Dictionary = _installing_from(hp)
		if not s.is_empty() and int(s["state"]) == 1:
			var at: Vector3 = (s["seat"] as Transform3D).origin
			var to := at - d.global_position
			d.visual.rotation.y = lerp_angle(d.visual.rotation.y, atan2(-to.x, -to.z), 0.25)
			d.snow.set_mpose(14, float(s["prog"]), at, -(s["axis"] as Vector3))
			return
	if d.snow.mpose == 14:
		d.snow.set_mpose(0)


func visual(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	for id in sockets:
		var s: Dictionary = sockets[id]
		var st := int(s["state"])
		var lamp = s["lamp"]
		if lamp:
			var k := "glow_r" if st == 0 else ("glow_g" if st == 2 else ("glow_y" if fmod(mtn.now(), 0.5) < 0.3 else "glow_r"))
			(lamp as MeshInstance3D).material_override = _lamp_mats[k]
		if st == 0:
			continue
		var part = s["part"]
		if part == null or not is_instance_valid(part):
			continue
		if (s["seat"] as Transform3D).origin.distance_squared_to(cp) > 90.0 * 90.0 and st == 2 and float(s["spin"]) == 0.0:
			continue
		# у не-хоста прогресс догоняет присланный плавно (шлётся 10 раз/с)
		var k2 := float(s["prog"])
		if st == 1 and not multiplayer.is_server():
			k2 = move_toward(float(s.get("vis_k", 0.0)), k2, delta * 1.5)
		s["vis_k"] = k2
		(part as Node3D).global_transform = _xf(s, k2)
		_bolts(s, k2)
		_stage_sfx(s, k2)


## Где деталь при прогрессе k (0 — у входа, повёрнута; 1 — на месте)
func _xf(s: Dictionary, k: float) -> Transform3D:
	var seat: Transform3D = s["seat"]
	var ax: Vector3 = s["axis"]
	var a := smoothstep(0.0, SLIDE_END, k)
	var b := smoothstep(SLIDE_END, TURN_END, k)
	var ang := float(s["turn"]) * (1.0 - b) + float(s["spin"])
	var bas := Basis(ax, ang) * seat.basis if absf(ang) > 0.0001 else seat.basis
	return Transform3D(bas, seat.origin + ax * float(s["slide"]) * (1.0 - a))


func _bolts(s: Dictionary, k: float) -> void:
	var bolts: Array = s["bolts"]
	var n := bolts.size()
	var ax: Vector3 = s["axis"]
	var bb := ModelBasis.y_to(ax)
	for i in n:
		var mi := bolts[i] as MeshInstance3D
		var span := (1.0 - TURN_END) / maxf(n, 1)
		var c := clampf((k - TURN_END - i * span) / span, 0.0, 1.0)
		mi.visible = k > TURN_END + i * span - 0.02
		if not mi.visible:
			continue
		var base: Vector3 = (s["bolt_base"] as Array)[i]
		mi.global_transform = Transform3D(Basis(ax, c * TAU * 4.0) * bb, base + ax * 0.09 * (1.0 - c))


## Звуки по этапам — у каждого свои (по пересечению порогов)
func _stage_sfx(s: Dictionary, k: float) -> void:
	var lk := float(s["last_k"])
	s["last_k"] = k
	if k <= lk:
		return
	var at: Vector3 = (s["seat"] as Transform3D).origin
	if lk < SLIDE_END and k >= SLIDE_END:
		SFX.play(self, at, "thunk", -1.0)
		SFX.play(self, at, "clank", -8.0, 1.3)
		_puff.global_position = at
		_puff.restart()
		_puff.emitting = true
	if lk < TURN_END and k >= TURN_END:
		SFX.play(self, at, "latch", 0.0)
	var n := (s["bolts"] as Array).size()
	for i in n:
		var t0 := TURN_END + i * (1.0 - TURN_END) / maxf(n, 1)
		if lk < t0 + 0.01 and k >= t0 + 0.01:
			SFX.play(self, at, "ratchet", -2.0, 1.0 + i * 0.08)


func hint(me: Node3D) -> String:
	var p := me.global_position
	var part = me.get("held_parcel")
	var best := {}
	var bd := 2.6
	for id in sockets:
		var s: Dictionary = sockets[id]
		var dd: float = p.distance_to(s["stand"])
		if dd < bd:
			bd = dd
			best = s
	if best.is_empty():
		return ""
	var st := int(best["state"])
	var title: String = best["title"]
	if st == 1:
		var k := float(best["prog"])
		var stage := "вставляю" if k < SLIDE_END else ("доворачиваю до щелчка" if k < TURN_END else "закручиваю болты")
		var pn: String = best["part"].display_name if best["part"] else "деталь"
		if String(mtn._hold_point_of(me)) != "":
			return "%s: %s… %d%% (держи E)" % [pn, stage, int(k * 100.0)]
		return "«%s» вставлена не до конца — держи E у гнезда" % pn
	if st == 0 and part != null and part.get("kind") != null:
		var why: String = best["owner"].socket_accept(String(best["id"]), part)
		if why != "":
			return why
		return "E — поставить «%s»: %s" % [part.display_name, title]
	if st == 0 and part == null:
		return "Пустое гнездо: %s" % title
	if st == 2 and part == null and bool(best["removable"]):
		return "%s — E: снять «%s»" % [title, best["part"].display_name if best["part"] else "деталь"]
	return ""


## Для шестерён: угол поворота детали в гнезде (крутится механизм)
func set_spin(id: String, ang: float) -> void:
	if sockets.has(id):
		sockets[id]["spin"] = ang
		if int(sockets[id]["state"]) == 2 and sockets[id]["part"] != null:
			(sockets[id]["part"] as Node3D).global_transform = _xf(sockets[id], 1.0)


class ModelBasis:
	static func y_to(dir: Vector3) -> Basis:
		var y := dir.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		return Basis(x, y, z)
