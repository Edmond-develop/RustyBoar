extends Node3D
## Шаг 67: подъёмный мост через разлом в конце Лавинной долины — командный квест.
## Мост висит на шарнире у дальнего края разлома; противовес держит его поднятым.
## Опускают его лебёдки: одна на этом берегу, вторая — на том. Пока кто-то крутит (держит E у лебёдки),
## мост опускается (~3 с); отпустил — противовес быстро поднимает его (~1.4 с). Один не успеет:
## пока один крутит — остальные бегут, потом с того берега крутят для него.
##
## По сети: каждый сообщает хосту, крутит ли он (и его боты); хост считает угол и рассылает.
## Боты (группа coop_gate, как у «Живых зеркал»): хозяин у моста — бот крутит; хозяин на той стороне —
## бот ждёт у моста и перебегает, когда мост опущен.

const W := preload("res://scenes/world/avalanche_layout.gd")

const UP_DEG := 78.0               ## поднят
const LOWER_TIME := 3.0            ## за сколько опускается целиком
const RAISE_TIME := 1.4            ## за сколько поднимается
const DECK_W := 3.2
const CRANK_R := 1.7               ## на каком расстоянии от лебёдки можно крутить

var is_open := false               ## для мозга ботов (coop_gate): мост не «открывается» навсегда
var angle := UP_DEG
var _net_angle := UP_DEG
var _send_t := 0.0
var _remote := {}                  ## хост: id дрона → номер лебёдки (кто крутит у других)
var _mine := {}                    ## мои дроны (я и мои боты) → номер лебёдки
var _sent := {}
var _hinge := Vector3.ZERO
var _fwd := Vector3.FORWARD        ## вдоль тропы, на тот берег
var _lat := Vector3.RIGHT
var _len := 16.0
var _k := 1.0
var _body: AnimatableBody3D
var _deck: Node3D
var _chains: Array = []            ## [MeshInstance3D, точка на столбе, точка на мосту (локально)]
var _handles: Array = []           ## ручки лебёдок (крутятся)
var _stand: Array[Vector3] = []    ## где стоять, чтобы крутить (0 — этот берег, 1 — тот)
var head := Vector3.ZERO           ## начало моста на этом берегу (на оси)
var land := Vector3.ZERO           ## куда сходить на том берегу
var _cranking := [false, false]
var _ter: Node
var _creak: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("coop_gate")
	_ter = get_tree().get_first_node_in_group("terrain")
	var s_far := W.RIFT_S + W.RIFT_HW
	var s_near := W.RIFT_S - W.RIFT_HW
	_fwd = W.path_dir(W.RIFT_S)
	_fwd.y = 0.0
	_fwd = _fwd.normalized()
	_lat = Vector3(-_fwd.z, 0.0, _fwd.x)
	var c := W.path_point(W.RIFT_S)
	# разлом поперёк долины (по s), а тропа тут идёт наискось — мост длиннее на 1/cos
	_k = 1.0 / maxf(absf(_fwd.z), 0.5)
	var reach := (W.RIFT_HW + 2.5) * _k       # концы моста — на 2.5 м за кромками (по s)
	var pf := c + _fwd * reach
	var pn := c - _fwd * reach
	var yf := _gy(pf.x, pf.z)
	var yn := _gy(pn.x, pn.z)
	_hinge = Vector3(pf.x, maxf(yf, yn) + 0.05, pf.z)
	_len = 2.0 * reach
	global_position = c
	head = c - _fwd * (W.RIFT_HW + 4.0) * _k
	head.y = _gy(head.x, head.z) + 0.6
	land = c + _fwd * (W.RIFT_HW + 6.0) * _k
	land.y = _gy(land.x, land.z) + 0.6
	_build(yf, yn, s_far, s_near)
	_apply()


func _gy(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else 0.0


# ---------------------------------------------------------------------------
#  Постройка
# ---------------------------------------------------------------------------

func _mat(col: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


func _deck_basis(a: float) -> Basis:
	# z — вдоль настила от шарнира к этому берегу, x — поперёк, y — вверх от настила
	var d := (-_fwd) * cos(a) + Vector3.UP * sin(a)
	var x := _lat
	var y := d.cross(x)
	return Basis(x, y, d)


func _build(yf: float, yn: float, _s_far: float, _s_near: float) -> void:
	var wood := _mat(Color(0.42, 0.29, 0.18))
	var wood_dark := _mat(Color(0.26, 0.18, 0.11))
	var iron := _mat(Color(0.2, 0.21, 0.23), 0.5, 0.7)
	var yellow := _mat(Color(0.95, 0.72, 0.1), 0.6)
	# мост: тело двигается (дроны на нём едут вместе с ним)
	_body = AnimatableBody3D.new()
	_body.name = "BridgeBody"
	_body.sync_to_physics = true
	add_child(_body)
	_body.top_level = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(DECK_W, 0.35, _len)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.175, _len * 0.5)
	_body.add_child(cs)
	_deck = Node3D.new()
	_body.add_child(_deck)
	# настил из досок + две продольные балки + перила
	var n := int(_len / 0.55)
	for i in n:
		var z := 0.3 + i * (_len - 0.6) / float(n - 1)
		_box(_deck, Vector3(DECK_W, 0.12, 0.5), Vector3(0.0, -0.06, z), wood if i % 3 else wood_dark)
	for sx in [-1.0, 1.0]:
		_box(_deck, Vector3(0.22, 0.3, _len), Vector3(sx * (DECK_W * 0.5 - 0.11), -0.25, _len * 0.5), wood_dark)
		_box(_deck, Vector3(0.08, 0.08, _len), Vector3(sx * (DECK_W * 0.5 - 0.06), 0.85, _len * 0.5), iron)
		var k := 0
		while k <= 8:
			_box(_deck, Vector3(0.08, 0.85, 0.08), Vector3(sx * (DECK_W * 0.5 - 0.06), 0.42, 0.5 + k * (_len - 1.0) / 8.0), iron)
			k += 1
	# жёлто-чёрные полосы на конце
	_box(_deck, Vector3(DECK_W, 0.13, 0.4), Vector3(0.0, -0.05, _len - 0.2), yellow)
	# рама на том берегу: два столба, балка, блоки
	var frame := Node3D.new()
	frame.top_level = true
	add_child(frame)
	frame.global_position = Vector3(_hinge.x, yf, _hinge.z) + _fwd * 0.4
	frame.basis = Basis(_lat, Vector3.UP, -_fwd)
	var post_h := 8.5
	for sx in [-1.0, 1.0]:
		_box(frame, Vector3(0.5, post_h, 0.5), Vector3(sx * (DECK_W * 0.5 + 0.6), post_h * 0.5, -0.6), wood_dark)
		_box(frame, Vector3(0.65, 0.4, 0.65), Vector3(sx * (DECK_W * 0.5 + 0.6), post_h - 0.3, -0.6), iron)
	_box(frame, Vector3(DECK_W + 2.0, 0.5, 0.5), Vector3(0.0, post_h - 0.6, -0.6), wood_dark)
	_box(frame, Vector3(DECK_W + 2.4, 0.18, 0.7), Vector3(0.0, 0.0, -0.8), iron)     # ось шарнира
	# противовес — тяжёлый ящик, висит за рамой
	_box(frame, Vector3(1.8, 1.4, 1.2), Vector3(0.0, 3.0, -2.2), _mat(Color(0.3, 0.32, 0.35), 0.7, 0.4))
	var lb := Label3D.new()
	lb.text = "ПРОТИВОВЕС"
	lb.font_size = 40
	lb.outline_size = 8
	lb.position = Vector3(0.0, 3.0, -1.55)
	frame.add_child(lb)
	# цепи: от верха столбов к концу моста
	for sx in [-1.0, 1.0]:
		var top := frame.global_transform * Vector3(sx * (DECK_W * 0.5 + 0.6), post_h - 0.4, -0.6)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.045
		cm.height = 1.0
		cm.radial_segments = 6
		cm.material = iron
		mi.mesh = cm
		mi.top_level = true
		add_child(mi)
		_chains.append([mi, top, Vector3(sx * (DECK_W * 0.5 - 0.1), 0.0, _len - 0.4)])
	# лебёдки: на этом берегу слева от моста, на том — справа
	var wa := (W.path_point(W.RIFT_S) - _fwd * (W.RIFT_HW + 5.5) * _k) - _lat * 4.2
	var wb := (W.path_point(W.RIFT_S) + _fwd * (W.RIFT_HW + 5.5) * _k) + _lat * 4.2
	for wi in 2:
		var p: Vector3 = wa if wi == 0 else wb
		p.y = _gy(p.x, p.z)
		_winch(p, wi == 0, wood_dark, iron, yellow)
	_creak = AudioStreamPlayer3D.new()
	_creak.max_distance = 40.0
	add_child(_creak)


func _winch(p: Vector3, near: bool, wood: Material, iron: Material, yellow: Material) -> void:
	var w := Node3D.new()
	w.top_level = true
	add_child(w)
	w.global_position = p
	# лицом к тропе
	var face := _lat if near else -_lat
	w.basis = Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
	for sx in [-1.0, 1.0]:
		_box(w, Vector3(0.18, 1.3, 0.9), Vector3(sx * 0.65, 0.65, 0.0), wood)
	_box(w, Vector3(1.6, 0.15, 1.1), Vector3(0.0, 0.07, 0.0), wood)
	var drum := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 1.1
	cm.material = iron
	drum.mesh = cm
	drum.position = Vector3(0.0, 1.0, 0.0)
	drum.rotation.z = PI * 0.5
	w.add_child(drum)
	# ручка-кривошип сбоку
	var hub := Node3D.new()
	hub.position = Vector3(0.82, 1.0, 0.0)
	w.add_child(hub)
	_box(hub, Vector3(0.08, 0.6, 0.08), Vector3(0.0, 0.3, 0.0), iron)
	_box(hub, Vector3(0.35, 0.09, 0.09), Vector3(0.17, 0.6, 0.0), yellow)
	_handles.append(hub)
	var lb := Label3D.new()
	lb.text = "ЛЕБЁДКА МОСТА\nдержи E — крутить"
	lb.font_size = 30
	lb.outline_size = 8
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.position = Vector3(0.0, 2.1, 0.0)
	w.add_child(lb)
	var st := p + face * 1.1
	st.y = _gy(st.x, st.z)
	_stand.append(st)


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_scan_local()
	var any := false
	_cranking = [false, false]
	if multiplayer.is_server():
		for k in _mine:
			_cranking[int(_mine[k])] = true
		for k2 in _remote:
			_cranking[int(_remote[k2])] = true
		any = _cranking[0] or _cranking[1]
		var a0 := angle
		if any:
			angle = move_toward(angle, 0.0, UP_DEG / LOWER_TIME * delta)
		else:
			angle = move_toward(angle, UP_DEG, UP_DEG / RAISE_TIME * delta)
		_send_t -= delta
		if Network.in_game and Network.is_online() and (_send_t <= 0.0 or (absf(angle - a0) > 0.0 and _send_t <= 0.05)):
			_send_t = 0.1
			_sync_angle.rpc(angle, _cranking[0], _cranking[1])
	else:
		angle = move_toward(angle, _net_angle, UP_DEG / RAISE_TIME * 1.3 * delta)
	_apply()
	for i in _handles.size():
		if _cranking[i]:
			(_handles[i] as Node3D).rotation.x -= 7.0 * delta
	_prompt()


func _apply() -> void:
	if _body == null:
		return
	var b := _deck_basis(deg_to_rad(angle))
	_body.global_transform = Transform3D(b, _hinge)
	for ch in _chains:
		var mi := ch[0] as MeshInstance3D
		var a: Vector3 = ch[1]
		var e: Vector3 = _body.global_transform * (ch[2] as Vector3)
		var mid := (a + e) * 0.5
		var dir := e - a
		var l := dir.length()
		if l < 0.01:
			continue
		var yb := dir / l
		var xb := yb.cross(Vector3.FORWARD if absf(yb.z) < 0.9 else Vector3.RIGHT).normalized()
		var zb := xb.cross(yb)
		mi.global_transform = Transform3D(Basis(xb, yb * l, zb), mid)


## Кто из моих дронов крутит лебёдку (держит E рядом с ней)
func _scan_local() -> void:
	var now := {}
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_local or d.is_dead or d.get("snow") == null or d.snow.busy():
			continue
		var w := crank_of(d)
		if w >= 0 and d._held("interact"):
			now[int(d.peer_id)] = w
	if multiplayer.is_server():
		_mine = now
		return
	# клиент: сообщаю хосту об изменениях
	for k in now:
		if int(_sent.get(k, -1)) != int(now[k]):
			_report.rpc_id(1, int(k), int(now[k]))
	for k2 in _sent:
		if not now.has(k2):
			_report.rpc_id(1, int(k2), -1)
	_sent = now
	_mine = now


## У какой лебёдки стоит дрон (−1 — ни у какой)
func crank_of(d: Node3D) -> int:
	for i in _stand.size():
		var st: Vector3 = _stand[i]
		if Vector2(st.x - d.global_position.x, st.z - d.global_position.z).length() < CRANK_R \
				and absf(st.y - d.global_position.y) < 2.5:
			return i
	return -1


@rpc("any_peer", "call_remote", "reliable")
func _report(id: int, w: int) -> void:
	if w < 0:
		_remote.erase(id)
	else:
		_remote[id] = w


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_angle(a: float, c0: bool, c1: bool) -> void:
	_net_angle = a
	_cranking = [c0, c1]


func _prompt() -> void:
	var me = Network.local_player
	if me == null or not is_instance_valid(me) or me.is_dead:
		return
	var av := get_parent()
	if crank_of(me) >= 0:
		if me._held("interact"):
			av.call("_shelter_say", "Крутишь лебёдку — мост опускается. Отпустишь — поднимется!")
		else:
			av.call("_shelter_say", "Держи E — крутить лебёдку (мост опускается, пока крутишь)")


## Мост опущен (по нему можно идти)
func is_down() -> bool:
	return angle < 4.0


# ---------------------------------------------------------------------------
#  Боты
# ---------------------------------------------------------------------------

## 0 — этот берег (или ещё на мосту), 1 — уже на том берегу
func _side(p: Vector3) -> int:
	return 0 if W.s_of(p.z) < W.RIFT_S + W.RIFT_HW + 1.5 else 1


func bot_target(bot: Node3D, o: Node3D) -> Vector3:
	var bs := W.s_of(bot.global_position.z)
	var os := W.s_of(o.global_position.z)
	if bs < W.RIFT_S - 80.0 or bs > W.RIFT_S + 60.0 or os < W.RIFT_S - 80.0 or os > W.RIFT_S + 60.0:
		return Vector3.INF
	var b := _side(bot.global_position)
	var ow := _side(o.global_position)
	if b == 0 and ow == 0:
		# хозяин у моста — крутим лебёдку, пока он бежит
		if os > W.RIFT_S - W.RIFT_HW - 30.0:
			return _stand[0]
		return Vector3.INF
	if b == 0 and ow == 1:
		# хозяин на той стороне — ждём у моста; опущен — бежим по оси
		var rel := bot.global_position - head
		var on_axis := absf(rel.dot(_lat)) < 0.9 and rel.dot(_fwd) > -1.5
		if is_down() and on_axis:
			return land
		return head
	if b == 1 and ow == 0:
		return _stand[1]
	return Vector3.INF


## Бот у лебёдки и должен крутить
func bot_crank(bot: Node3D, o: Node3D) -> bool:
	var t := bot_target(bot, o)
	if t == Vector3.INF:
		return false
	var w := crank_of(bot)
	return w >= 0 and (t as Vector3).distance_to(_stand[w]) < 0.5
