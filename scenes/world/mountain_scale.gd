extends Node3D
## Шаг 74: «Весы-замок» — первая задачка на смекалку (лёгкая, в начале тропы, u 0.2).
## Тропу перегородила каменная плита в раме. Рядом у скалы — весы: на левой чаше камень «60 кг»,
## правая пустая (3 места). Гири 10, 15, 20, 25, 35 кг лежат по тропе ниже (столбы света).
## Положить на правую чашу гири ровно на 60 кг (25+35, 10+15+35, 15+20+25…): весы выравниваются, замок открыт
## (лампы зелёные). Потом ВДВОЁМ потянуть два рычага по краям тропы (~1.5 с) — плита поднимается на цепях.
## Перевес/недовес — коромысло наклоняется, стрелка показывает «легче/тяжелее», рычаги заперты (лязг).
## Гири ставятся в гнёзда (mountain_mech): опустить на чашу → повернуть; снять — E пустыми руками.

const M := preload("res://scenes/world/mountain_layout.gd")
const PART := preload("res://scenes/world/peak_part.gd")
const SFX := preload("res://scripts/sfx.gd")
const U := 0.2
const TARGET := 60
const PULL_T := 1.5
const RISE_T := 3.2
const LIFT := 3.4
const ARM := 1.15                 ## пол-коромысла (м)
const W_LIST := [[10, 0.172], [15, 0.186], [20, 0.162], [25, 0.145], [35, 0.132]]

var mtn: Node
var is_open := false              ## для ботов (coop_gate)
var opened := false
var _open_t := -1.0
var _pull_t := 0.0
var _tilt := 0.0
var _tilt_v := 0.0
var _c := Vector3.ZERO
var _t := Vector3.FORWARD
var _out := Vector3.RIGHT
var _y := 0.0
var _slab: AnimatableBody3D
var _slab0 := Vector3.ZERO
var _beam: Node3D
var _pans: Array[Node3D] = []
var _needle: Node3D
var _pivot := Vector3.ZERO
var _lev: Array[Node3D] = []
var _lev_pos: Array[Vector3] = []
var _lamps: Array[MeshInstance3D] = []
var _chain: ImmediateMesh
var _chain_mi: MeshInstance3D
var _pulley := Vector3.ZERO
var _drum := Vector3.ZERO
var _slots: Array[String] = []
var _status: Label3D
var _parts: Array = []
var _lock_t := 0.0
var _tsign := 1.0


func build() -> void:
	var b: Node3D = mtn.builder
	_c = M.point(U)
	_t = M.tangent(U)
	_out = M.outward(U)
	_y = M.height(U)
	_c.y = _y
	var hin := M.half_in(U)
	var hout := M.half_out(U)
	var bas := Basis(_out, Vector3.UP, -_t)
	var mid := (hout - hin) * 0.5
	# чаша 1 (с гирями) — в сторону +t; наклон коромысла вокруг _out: знак, чтобы тяжёлая шла вниз
	_tsign = -signf(_out.cross(_t).y) if absf(_out.cross(_t).y) > 0.01 else 1.0
	var wid := hin + hout
	# рама: столбы (внутренний — в скалу), опора внешнего столба до низа обрыва, перекладина со шкивом
	var pin := _c - _out * (hin + 0.5)
	var pout := _c + _out * (hout + 0.6)
	_rockbox(Vector3(1.4, 6.2, 1.4), pin + Vector3.UP * 3.0, bas)
	_rockbox(Vector3(1.3, 18.0, 1.3), pout + Vector3.UP * -5.9, bas)
	_rockbox(Vector3(wid + 3.4, 1.0, 1.5), _c + _out * mid + Vector3.UP * 5.9, bas)
	b.box(Vector3(wid + 3.6, 0.25, 1.7), _c + _out * mid + Vector3.UP * 6.5, bas, "snowblock")
	for k in 3:
		b.box(Vector3(0.12, 0.2, 1.55), _c + _out * (mid - wid * 0.4 + k * wid * 0.4) + Vector3.UP * 5.45, bas, "iron")
	# плита (поднимается)
	_slab = AnimatableBody3D.new()
	_slab.name = "ScaleSlab"
	_slab.sync_to_physics = true
	add_child(_slab)
	_slab0 = _c + _out * mid + Vector3.UP * 1.8
	_slab.global_transform = Transform3D(bas, _slab0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(wid + 0.3, 3.6, 0.55)
	cs.shape = bs
	_slab.add_child(cs)
	var smb = PART.ModelBuilder.new()
	smb.box(Vector3(wid + 0.3, 3.6, 0.55), Vector3.ZERO, Basis.IDENTITY, "stone")
	for yy in [-1.1, 1.1]:
		smb.box(Vector3(wid + 0.36, 0.16, 0.6), Vector3(0, yy, 0), Basis.IDENTITY, "iron")
		for xx in range(-int(wid * 0.5), int(wid * 0.5) + 1, 2):
			smb.cyl(0.04, 0.04, 0.64, Vector3(xx, yy, 0), Basis(Vector3.RIGHT, PI * 0.5), "steel", 6)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.08
	tm.outer_radius = 0.14
	tm.rings = 12
	tm.ring_segments = 6
	smb.add(tm, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 1.9, 0)), "iron")
	smb.commit(_slab, func(k: String) -> Material: return mtn.rock_mat() if k == "stone" else PART.mat(k))
	# шкив на перекладине и барабан-противовес у весов
	_pulley = _c + _out * mid + Vector3.UP * 6.6 + _t * 0.0
	b.cyl(0.35, 0.35, 0.25, _pulley, Basis(_t, PI * 0.5) * Basis(Vector3.UP, atan2(_out.x, _out.z)), "iron", 14)
	# весы — у скалы, ниже плиты по тропе
	var sp := _c - _t * 6.0 - _out * (hin - 1.5)
	sp.y = M.height(M.u_at(sp))
	_pivot = sp + Vector3.UP * 2.35
	b.box(Vector3(0.9, 0.3, 0.9), sp + Vector3.UP * 0.15, bas, "slab", true)
	b.box(Vector3(0.22, 2.2, 0.22), sp + Vector3.UP * 1.25, bas, "iron", true)
	b.box(Vector3(0.5, 0.35, 0.3), _pivot + Vector3.UP * 0.05, bas, "iron")
	# шкала стрелки
	b.box(Vector3(0.05, 0.5, 0.8), _pivot + Vector3.DOWN * 0.7 + _out * 0.16, bas, "w_white")
	for k in 5:
		var z := -0.32 + k * 0.16
		b.box(Vector3(0.06, 0.14 if k == 2 else 0.07, 0.025), _pivot + Vector3.DOWN * 0.5 + _out * 0.19 - _t * z, bas, "paint_red" if k == 2 else "dark")
	_beam = Node3D.new()
	add_child(_beam)
	_beam.global_transform = Transform3D(Basis.looking_at(_t, Vector3.UP), _pivot)
	var bmb = PART.ModelBuilder.new()
	bmb.box(Vector3(0.12, 0.14, ARM * 2.0 + 0.2), Vector3.ZERO, Basis.IDENTITY, "brass")
	bmb.cyl(0.06, 0.06, 0.3, Vector3.ZERO, Basis(Vector3.FORWARD, PI * 0.5), "steel", 10)
	for sz in [-ARM, ARM]:
		bmb.sph(0.07, Vector3(0, 0, sz), Basis.IDENTITY, "brass", 8)
	bmb.commit(_beam, Callable(PART, "mat"))
	_needle = Node3D.new()
	add_child(_needle)
	var nmb = PART.ModelBuilder.new()
	nmb.box(Vector3(0.03, 0.62, 0.04), Vector3(0, -0.31, 0), Basis.IDENTITY, "paint_r")
	nmb.commit(_needle, Callable(PART, "mat"))
	for i in 2:
		var pan := Node3D.new()
		add_child(pan)
		var pmb = PART.ModelBuilder.new()
		pmb.cyl(0.55, 0.46, 0.08, Vector3.ZERO, Basis.IDENTITY, "brass", 20)
		for k in 3:
			var a := TAU * k / 3.0
			pmb.beam(Vector3(cos(a) * 0.48, 0.04, sin(a) * 0.48), Vector3(0, 1.05, 0), 0.012, "steel", 4)
		if i == 0:
			pmb.box(Vector3(0.55, 0.42, 0.5), Vector3(0, 0.25, 0), Basis(Vector3.UP, 0.3), "dark")
		pmb.commit(pan, Callable(PART, "mat"))
		_pans.append(pan)
	var stone_lbl := Label3D.new()
	stone_lbl.text = "60 кг"
	stone_lbl.font_size = 40
	stone_lbl.outline_size = 10
	stone_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stone_lbl.position = Vector3(0, 0.75, 0)
	stone_lbl.visibility_range_end = 25.0
	_pans[0].add_child(stone_lbl)
	# места для гирь на правой чаше (3) — гнёзда
	var stand := sp - _t * ARM + _out * 1.3
	stand.y = M.height(M.u_at(stand))
	for k in 3:
		var id := "SC_W%d" % k
		_slots.append(id)
		mtn.mech.add_socket(id, self, _slot_xf(k), Vector3.UP, stand,
			{"slide": 0.55, "turn": 0.5, "bolts": 0, "time": 0.9, "removable": true, "title": "чаша весов"})
	# рычаги по краям тропы (ниже плиты)
	for sgn in [-1.0, 1.0]:
		var lat := -hin + 0.9 if sgn < 0.0 else hout - 0.9
		var lp := _c - _t * 2.4 + _out * lat
		lp.y = M.height(M.u_at(lp))
		b.box(Vector3(0.5, 1.0, 0.5), lp + Vector3.UP * 0.5, bas, "slab", true)
		b.box(Vector3(0.6, 0.08, 0.6), lp + Vector3.UP * 1.02, bas, "iron")
		var arm := Node3D.new()
		add_child(arm)
		arm.global_position = lp + Vector3.UP * 1.05
		var amb = PART.ModelBuilder.new()
		amb.cyl(0.035, 0.035, 1.1, Vector3(0, 0.55, 0), Basis.IDENTITY, "steel", 8)
		amb.cyl(0.05, 0.05, 0.28, Vector3(0, 1.12, 0), Basis(Vector3.FORWARD, PI * 0.5), "rubber", 8)
		amb.cyl(0.08, 0.08, 0.16, Vector3.ZERO, Basis(Vector3.FORWARD, PI * 0.5), "iron", 10)
		amb.commit(arm, Callable(PART, "mat"))
		arm.global_basis = Basis(Vector3.UP, atan2(_out.x, _out.z))
		_lev.append(arm)
		var stand_l := lp - _t * 1.0
		_lev_pos.append(stand_l)
		mtn.add_hold("SC_L%d" % (0 if sgn < 0.0 else 1), stand_l, 1.1)
		var lm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		sm.radial_segments = 8
		sm.rings = 4
		lm.mesh = sm
		lm.material_override = PART.mat("glow_r")
		lm.position = lp + Vector3.UP * 1.2 + _t * 0.3
		add_child(lm)
		_lamps.append(lm)
	_drum = sp + Vector3.UP * 0.4 + _t * 0.6
	# цепь: от кольца плиты к шкиву и вниз к весам
	_chain = ImmediateMesh.new()
	_chain_mi = MeshInstance3D.new()
	_chain_mi.mesh = _chain
	_chain_mi.material_override = PART.mat("iron")
	_chain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chain_mi)
	_status = Label3D.new()
	_status.font_size = 30
	_status.outline_size = 9
	_status.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_status.position = _pivot + Vector3.UP * 1.1
	_status.visibility_range_end = 40.0
	add_child(_status)
	mtn.sign_at(sp + _out * 2.6 + _t * 1.5, "ВЕСЫ-ЗАМОК\nНа левой чаше — камень 60 кг.\nПоложите гири на правую чашу\n(не больше трёх) — ровно 60 кг.\nПотом ВДВОЁМ — оба рычага (E)", Color(1.0, 0.85, 0.5))
	_spawn_weights.call_deferred()
	var gate := Node3D.new()
	gate.set_script(load("res://scenes/world/mountain_gate.gd"))
	gate.set("mod", self)
	gate.add_to_group("coop_gate")
	add_child(gate)
	gate.global_position = _c - _t * 3.0
	_update(0.0)


## Каменный блок (тот же камень, что у горы) с коллизией
func _rockbox(size: Vector3, pos: Vector3, bas: Basis) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mtn.rock_mat()
	add_child(mi)
	mi.global_transform = Transform3D(bas, pos)
	mtn.builder.solid_box(pos, size, bas)


func _spawn_weights() -> void:
	for e in W_LIST:
		var kg: int = e[0]
		var u: float = e[1]
		var side := -1.0 if kg in [10, 20] else 1.0
		var lat := (-M.half_in(u) + 1.2) if side < 0.0 else (M.half_out(u) - 1.0)
		var pos := M.point(u) + M.outward(u) * lat
		pos.y = M.height(u) + 0.5
		var part := PART.make("w%d" % kg, "Гиря %d кг" % kg, pos)
		add_child(part)
		_parts.append(part)


## Где стоит гиря k на правой чаше (чаша качается)
func _slot_xf(k: int) -> Transform3D:
	var pan_c := _pan_pos(1)
	var off := [Vector3(-0.2, 0, 0.12), Vector3(0.2, 0, 0.12), Vector3(0.0, 0, -0.2)][k] as Vector3
	var yaw := atan2(_out.x, _out.z)
	var bas := Basis(Vector3.UP, yaw)
	var part = null
	if mtn and mtn.mech and mtn.mech.sockets.has("SC_W%d" % k):
		part = mtn.mech.sockets["SC_W%d" % k]["part"]
	var kg := int(part.get("mass_kg")) if part != null else 20
	var s := 0.1 + kg * 0.0034
	return Transform3D(bas, pan_c + bas * off + Vector3.UP * (0.04 + s * 0.86))


func _pan_pos(i: int) -> Vector3:
	var end := _pivot + (_beam.global_basis.z if _beam else -_t) * (ARM if i == 0 else -ARM)
	return end + Vector3.DOWN * 1.05


func load_kg() -> int:
	var s := 0
	for id in _slots:
		var part = mtn.mech.part_in(id)
		if part != null:
			s += int(part.get("mass_kg"))
	return s


func balanced() -> bool:
	return load_kg() == TARGET


# --- гнёзда ---
func socket_accept(_id: String, part: Node) -> String:
	if opened:
		return "Плита уже открыта"
	return "" if String(part.get("kind")).begins_with("w") else "На чашу — только гири"


func can_remove(_id: String) -> bool:
	return not opened


func on_socket(_id: String, part: Node) -> void:
	SFX.play(self, _pivot, "creak", -4.0)
	var me = Network.local_player
	if me and me.global_position.distance_to(_pivot) < 12.0:
		var kg := load_kg()
		mtn.say("На чаше %d кг из %d — %s" % [kg, TARGET, "РАВНОВЕСИЕ! Замок открыт — тяните рычаги вдвоём" if kg == TARGET else ("мало" if kg < TARGET else "перевес")])
	if balanced():
		SFX.play(self, _pivot, "latch", 2.0)
		SFX.play(self, _pivot, "ding", -4.0, 1.2)


func on_unsocket(_id: String, _part: Node) -> void:
	SFX.play(self, _pivot, "creak", -6.0, 1.2)


# --- каждый кадр ---
func server(delta: float) -> void:
	if opened:
		return
	var h0: Array = mtn.holders("SC_L0")
	var h1: Array = mtn.holders("SC_L1")
	if balanced() and not h0.is_empty() and not h1.is_empty() and h0[0] != h1[0]:
		_pull_t += delta
		if _pull_t >= PULL_T:
			if mtn._online():
				_open.rpc(mtn.now())
			else:
				_open(mtn.now())
	else:
		_pull_t = maxf(_pull_t - delta * 2.0, 0.0)


@rpc("authority", "call_local", "reliable")
func _open(t0: float) -> void:
	if opened:
		return
	opened = true
	is_open = true
	_open_t = t0
	SFX.play(self, _slab0, "chain", 2.0, 0.8)
	SFX.play(self, _slab0, "thunk", 0.0, 0.6)
	var me = Network.local_player
	if me and me.global_position.distance_to(_c) < 40.0:
		me.add_shake(0.15)
		get_tree().call_group("level", "show_banner", "Плита поднимается!", "Весы в равновесии, рычаги сработали — путь открыт")


func local(d: Node3D, hp: String, _holding: bool, _delta: float) -> void:
	if hp.begins_with("SC_L") and not opened:
		var i := int(hp.substr(4))
		var top: Vector3 = _lev[i].global_position + _lev[i].global_basis.y * 1.1
		var to := top - d.global_position
		d.visual.rotation.y = lerp_angle(d.visual.rotation.y, atan2(-to.x, -to.z), 0.3)
		d.snow.set_mpose(15, clampf(_pull_t / PULL_T, 0.0, 1.0) if balanced() else 0.15 * absf(sin(mtn.now() * 9.0)), top, _t)
		if not balanced():
			_lock_t -= _delta
			if _lock_t <= 0.0 and d == Network.local_player:
				_lock_t = 0.6
				SFX.play(self, top, "latch", -6.0, 0.7)
	elif d.snow.mpose == 15 and not hp.begins_with("SC_L") and d.global_position.distance_to(_c) < 20.0:
		d.snow.set_mpose(0)


func visual(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	# коромысло: перевес — правая (с гирями) вниз; пружинка с затуханием
	var diff := float(load_kg() - TARGET) if mtn.mech else -float(TARGET)
	var want := clampf(diff / 30.0, -1.0, 1.0) * 0.24
	_tilt_v += (90.0 * (want - _tilt) - 7.0 * _tilt_v) * delta
	_tilt += _tilt_v * delta
	if _beam:
		_beam.global_transform = Transform3D(Basis(_out, _tilt * _tsign) * Basis.looking_at(_t, Vector3.UP), _pivot)
		for i in 2:
			_pans[i].global_transform = Transform3D(Basis(Vector3.UP, atan2(_out.x, _out.z)), _pan_pos(i))
		_needle.global_transform = Transform3D(Basis(_out, _tilt * _tsign * 2.2) * Basis(Vector3.UP, atan2(_out.x, _out.z)), _pivot + _out * 0.2)
		for k in 3:
			mtn.mech.move_seat(_slots[k], _slot_xf(k))
	var ok := balanced()
	for i in _lamps.size():
		var pulling: bool = mtn.is_active("SC_L%d" % i)
		_lamps[i].material_override = PART.mat("glow_g" if ok or opened else ("glow_y" if pulling and fmod(mtn.now(), 0.4) < 0.2 else "glow_r"))
		var ang := 0.55 if (pulling and ok) or opened else (0.12 if pulling else 0.0)
		var cur := _lev[i].get_meta("ang", 0.0) as float
		cur = move_toward(cur, ang, delta * 2.0)
		_lev[i].set_meta("ang", cur)
		_lev[i].global_basis = Basis(_t.cross(Vector3.UP).normalized(), cur) * Basis(Vector3.UP, atan2(_out.x, _out.z))
	# плита
	var k2 := 0.0
	if opened:
		k2 = smoothstep(0.0, 1.0, clampf((mtn.now() - _open_t) / RISE_T, 0.0, 1.0))
	var sp := _slab0 + Vector3.UP * LIFT * k2
	if _slab and _slab.global_position.distance_to(sp) > 0.001:
		_slab.global_position = sp
	# цепь
	if _chain:
		_chain.clear_surfaces()
		var ring := sp + Vector3.UP * 1.9
		_chain_line(ring, _pulley)
		_chain_line(_pulley + _out * 0.0, _pulley - _t * 0.3 + Vector3.DOWN * 0.1)
		_chain_line(_pulley - _t * 0.3, _drum + Vector3.UP * 0.2)
	if _status:
		var kg := load_kg()
		_status.text = "ОТКРЫТО" if opened else ("%d / %d кг — %s" % [kg, TARGET, "РАВНО" if kg == TARGET else ("легче" if kg < TARGET else "тяжелее")])
		_status.modulate = Color(0.5, 1.0, 0.6) if ok or opened else Color(1.0, 0.8, 0.5)


func _chain_line(a: Vector3, b: Vector3) -> void:
	# цепь — полоска из звеньев (две плоскости крест-накрест)
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var f := d / len
	var s1 := f.cross(Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT).normalized() * 0.035
	var s2 := f.cross(s1).normalized() * 0.035
	_chain.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [s1, s2]:
		var sv: Vector3 = s
		var n := f.cross(sv).normalized()
		_chain.surface_set_normal(n)
		_chain.surface_add_vertex(a - sv)
		_chain.surface_add_vertex(b - sv)
		_chain.surface_add_vertex(b + sv)
		_chain.surface_add_vertex(a - sv)
		_chain.surface_add_vertex(b + sv)
		_chain.surface_add_vertex(a + sv)
	_chain.surface_end()


func hint(me: Node3D) -> String:
	var p := me.global_position
	if opened or p.distance_to(_c) > 16.0:
		return ""
	var hp: String = mtn._hold_point_of(me)
	if hp.begins_with("SC_L"):
		if not balanced():
			return "Рычаг заперт — весы не в равновесии (%d из %d кг)" % [load_kg(), TARGET]
		var other := "SC_L1" if hp == "SC_L0" else "SC_L0"
		return "Тяну рычаг… нужен второй — у другого края тропы!" if not mtn.is_active(other) else "Тянете вдвоём — плита идёт вверх!"
	return ""


# --- бот: второй рычаг ---
func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	if opened or not balanced():
		return Vector3.INF
	var o := owner_node.global_position
	if o.distance_to(_c) > 20.0:
		return Vector3.INF
	var d0 := Vector2(o.x - _lev_pos[0].x, o.z - _lev_pos[0].z).length()
	var d1 := Vector2(o.x - _lev_pos[1].x, o.z - _lev_pos[1].z).length()
	if minf(d0, d1) > 3.0:
		return Vector3.INF
	return _lev_pos[1] if d0 < d1 else _lev_pos[0]


func bot_crank(bot: Node3D, owner_node: Node3D) -> bool:
	var t := bot_target(bot, owner_node)
	if t == Vector3.INF:
		return false
	var b := bot.global_position
	return Vector2(t.x - b.x, t.z - b.z).length() < 0.9 and absf(t.y - b.y) < 1.6
