extends Node3D
## Ворота в Ледяном валу — командное испытание «Живые зеркала».
##
## Древний маяк в нише у западного края бьёт лучом вдоль площадки. Ворота откроет
## луч, попавший в печать на воротах. Напрямую не выйдет: между лучом маяка и
## воротами — длинный ледяной барьер, а на востоке луч упирается в глыбу.
##  * луч отражается от корпуса дрона (силовое поле корпуса вспыхивает). Куда уйдёт
##    отражение — зависит от того, каким боком дрон стоит к лучу: луч в самый центр
##    отскакивает назад; чем дальше от центра — тем сильнее он только отклоняется
##    (от 180° до 50°). Направление настраиваешь, переступая в сторону
##    (Ctrl — тихий шаг, удобно для точной подстройки): ~10 см ≈ 8°;
##  * луч ЖЖЁТ: каждый дрон в луче теряет корпус (полный — за ~10 секунд).
##    Значит, действовать надо быстро и слаженно;
##  * нужна цепочка минимум из двух дронов: один ловит луч маяка, второй — за
##    концом барьера — переправляет его в печать;
##  * печать заряжается, пока в неё бьёт луч (CHARGE_TIME с); без луча заряд
##    медленно утекает — передышка не обнуляет прогресс;
##  * ветер мешает: порывы долетают и сюда — сносят дронов, луч «гуляет»;
##  * зарядилась печать — ворота открываются насовсем.
##  * сгоревший дрон появляется у входа в лабиринт (контрольная точка).
##
## Сеть: луч каждый игрок считает сам по положению дронов; урон свой дрон получает
## сам. Заряд печати считает хост и рассылает всем.

const CATCH_R := 1.6                ## Как далеко от центра дрона луч ещё отражается (м)
const TURN_CENTER := deg_to_rad(180.0)   ## Поворот луча при попадании в центр (назад)
const TURN_EDGE := deg_to_rad(50.0)      ## …и у самого края
const BODY_H := 1.1                 ## Высота центра дрона над ногами (= высота луча)
const BURN_DPS := 10.0              ## Урон корпусу в секунду, пока дрон в луче
const SEAL_HALF := 1.4
const SEAL_FWD := 3.0               ## Печать вынесена вперёд от ворот (перед толщей вала)
const CHARGE_TIME := 4.0
const CHARGE_LEAK := 0.05           ## Сколько заряда утекает в секунду без луча
const SEND_INTERVAL := 0.1
const MAX_BOUNCES := 10
const MAX_DIST := 160.0

@export var gate_width := 9.0
@export var gate_height := 9.0
@export var beam_y := 1.1                        ## Высота луча (мировая) = высота центра дронов
@export var beacon_pos := Vector3.ZERO           ## Откуда выходит луч
@export var beacon_dir := Vector3(1, 0, 0)       ## Куда светит маяк
@export var zone := Rect2()                      ## Площадка (x, z) — где луч отражается от дронов
## Для бота-помощника: точка на луче маяка и точка за концом барьера
@export var bot_spot_a := Vector3.ZERO
@export var bot_spot_b := Vector3.ZERO

var charge := 0.0
var is_open := false
var chain: Array = []                            ## id дронов в цепочке (по порядку) — последний расчёт

var _seal_hit := false
var _lit := {}                                   ## id -> номер отражения (0 — первый)
var _hits := {}                                  ## id -> [откуда пришёл луч, направление луча]
var _door: AnimatableBody3D
var _seal_mat: StandardMaterial3D
var _seal: Node3D
var _sign: Label3D
var _lift := 0.0
var _beam_parts: Array[MeshInstance3D] = []
var _beam_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _hit_light: OmniLight3D
var _sparks: GPUParticles3D
var _send := 0.0
var _pulse := 0.0
var _hud_hint: Label
var _auras := {}                                 ## узел дрона -> [сфера, материал]
var _aura_mesh: SphereMesh


func _ready() -> void:
	add_to_group("coop_gate")
	_build_door()
	_build_seal()
	_build_beacon()
	_build_beam()
	_sign = Label3D.new()
	_sign.font_size = 56
	_sign.outline_size = 14
	_sign.modulate = Color(1.0, 0.9, 0.6)
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = Vector3(0.0, gate_height + 2.4, 2.0)
	add_child(_sign)
	_aura_mesh = SphereMesh.new()
	_aura_mesh.radius = 1.0
	_aura_mesh.height = 2.0
	_aura_mesh.radial_segments = 24
	_aura_mesh.rings = 12
	_make_hud()


# ---------------------------------------------------------------------------
#  Построение
# ---------------------------------------------------------------------------
func _build_door() -> void:
	_door = AnimatableBody3D.new()
	_door.sync_to_physics = true
	add_child(_door)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(gate_width + 0.6, gate_height, 2.2)
	col.shape = box
	col.position.y = gate_height * 0.5
	_door.add_child(col)
	var ice := ShaderMaterial.new()
	ice.shader = preload("res://shaders/pressure_ice.gdshader")
	ice.set_shader_parameter("polish", 0.6)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(gate_width + 0.4, gate_height, 1.8)
	bm.material = ice
	slab.mesh = bm
	slab.position.y = gate_height * 0.5
	_door.add_child(slab)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.12, 0.13, 0.16)
	frame.metallic = 0.7
	frame.roughness = 0.5
	for k in 3:
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(gate_width + 0.6, 0.35, 2.0)
		b.material = frame
		bar.mesh = b
		bar.position.y = 2.4 + k * (gate_height - 2.8) / 2.0
		_door.add_child(bar)


## Печать на воротах — круглая мишень на высоте щитов
func _build_seal() -> void:
	_seal = Node3D.new()
	_seal.position = Vector3(0.0, beam_y - global_position.y, SEAL_FWD - 0.1)
	_door.add_child(_seal)
	# кронштейн: печать на балке перед воротами
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = Color(0.12, 0.13, 0.16)
	arm_mat.metallic = 0.7
	for sx in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.18, 0.18, SEAL_FWD - 0.9)
		am.material = arm_mat
		arm.mesh = am
		arm.position = Vector3(sx * 1.3, beam_y - global_position.y + 1.3, (SEAL_FWD + 0.9) * 0.5 - 0.1)
		_door.add_child(arm)
	_seal_mat = StandardMaterial3D.new()
	_seal_mat.albedo_color = Color(0.25, 0.2, 0.15)
	_seal_mat.emission_enabled = true
	_seal_mat.emission = Color(1.0, 0.6, 0.2)
	_seal_mat.emission_energy_multiplier = 0.3
	_seal_mat.metallic = 0.5
	for k in 3:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3 + k * 0.38
		tm.outer_radius = 0.44 + k * 0.38
		tm.rings = 32
		tm.material = _seal_mat
		t.mesh = tm
		t.rotation.x = PI * 0.5
		_seal.add_child(t)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	sm.material = _seal_mat
	core.mesh = sm
	_seal.add_child(core)
	# шкала заряда над печатью
	var lbl := Label3D.new()
	lbl.name = "ChargeLabel"
	lbl.font_size = 64
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0.0, 1.9, 0.2)
	lbl.modulate = Color(1.0, 0.75, 0.3)
	_seal.add_child(lbl)


## Маяк: каменный столб с горящим кристаллом на высоте щитов
func _build_beacon() -> void:
	var root := Node3D.new()
	add_child(root)
	root.top_level = true
	root.global_position = Vector3(beacon_pos.x, global_position.y, beacon_pos.z)
	root.rotation.y = atan2(-beacon_dir.x, -beacon_dir.z)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.22, 0.24, 0.3)
	stone.roughness = 0.8
	var body := StaticBody3D.new()
	root.add_child(body)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 3.2, 1.8)
	col.shape = bs
	col.position = Vector3(0, 1.6, 0.9)
	body.add_child(col)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	bm.material = stone
	base.mesh = bm
	base.position = col.position
	root.add_child(base)
	var crystal_mat := StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(1.0, 0.8, 0.4)
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(1.0, 0.7, 0.3)
	crystal_mat.emission_energy_multiplier = 5.0
	var crystal := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.material = crystal_mat
	crystal.mesh = sm
	crystal.position = Vector3(0, beam_y - global_position.y, 0.0)
	root.add_child(crystal)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.position = crystal.position
	root.add_child(light)
	var lbl := Label3D.new()
	lbl.text = "ДРЕВНИЙ МАЯК"
	lbl.font_size = 56
	lbl.outline_size = 12
	lbl.modulate = Color(1.0, 0.85, 0.5)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 4.2, 0.9)
	root.add_child(lbl)


func _build_beam() -> void:
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = Color(1.0, 0.5, 0.08, 0.45)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := CylinderMesh.new()
	glow.top_radius = 0.2
	glow.bottom_radius = 0.2
	glow.height = 1.0
	glow.radial_segments = 8
	glow.cap_top = false
	glow.cap_bottom = false
	glow.material = _beam_mat
	var core := CylinderMesh.new()
	core.top_radius = 0.07
	core.bottom_radius = 0.07
	core.height = 1.0
	core.radial_segments = 6
	core.material = _core_mat
	for k in MAX_BOUNCES + 2:
		var mi := MeshInstance3D.new()
		mi.mesh = glow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		var c := MeshInstance3D.new()
		c.mesh = core
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(c)
		add_child(mi)
		_beam_parts.append(mi)
	_hit_light = OmniLight3D.new()
	_hit_light.top_level = true
	_hit_light.light_color = Color(1.0, 0.75, 0.4)
	_hit_light.light_energy = 2.0
	_hit_light.omni_range = 4.0
	add_child(_hit_light)
	_sparks = FX.particles(Color(1.0, 0.8, 0.4), 40, 0.5, 0.05, 1.5, 4.0, Vector3(0, -6, 0), 120.0, false, true)
	_sparks.top_level = true
	add_child(_sparks)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud_hint = Label.new()
	_hud_hint.anchor_left = 0.5
	_hud_hint.anchor_right = 0.5
	_hud_hint.anchor_top = 1.0
	_hud_hint.anchor_bottom = 1.0
	_hud_hint.offset_left = -400.0
	_hud_hint.offset_right = 400.0
	_hud_hint.offset_top = -165.0
	_hud_hint.offset_bottom = -110.0
	_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud_hint.add_theme_constant_override("outline_size", 6)
	_hud_hint.add_theme_font_size_override("font_size", 18)
	_hud_hint.visible = false
	layer.add_child(_hud_hint)


# ---------------------------------------------------------------------------
#  Дроны-зеркала
# ---------------------------------------------------------------------------
func in_zone(p: Vector3) -> bool:
	return zone.has_point(Vector2(p.x, p.z)) and absf(p.y - global_position.y) < 4.0


## Все дроны на площадке: [узел, id, центр корпуса]
func _reflectors() -> Array:
	var out := []
	if is_open:
		return out
	var nodes: Array = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("coop_helper")
	for d in nodes:
		var n := d as Node3D
		if bool(n.get("is_dead")) or not in_zone(n.global_position):
			continue
		out.append([n, int(n.get("peer_id")), n.global_position + Vector3.UP * BODY_H])
	return out


func seal_center() -> Vector3:
	return Vector3(global_position.x, beam_y, global_position.z + SEAL_FWD)


## Куда повернёт луч, если центр дрона смещён от линии луча на b (со знаком):
## b = 0 — назад (180°), |b| = CATCH_R — на TURN_EDGE. Знак — в сторону от дрона.
static func turn_for_offset(b: float) -> float:
	var k := clampf(absf(b) / CATCH_R, 0.0, 1.0)
	return signf(b if b != 0.0 else 1.0) * lerpf(TURN_CENTER, TURN_EDGE, k)


## Обратное: на сколько сместиться от линии луча, чтобы он повернул на angle (рад, со знаком)
static func offset_for_turn(angle: float) -> float:
	var a := clampf(absf(angle), TURN_EDGE, TURN_CENTER)
	return signf(angle) * CATCH_R * (TURN_CENTER - a) / (TURN_CENTER - TURN_EDGE)


## Сторона «вбок» от луча (для знака смещения)
static func side_of(d: Vector3) -> Vector3:
	return Vector3(-d.z, 0.0, d.x)


## Пустить луч. Возвращает точки ломаной; заполняет _lit, _hits, chain, _seal_hit.
func trace() -> Array[Vector3]:
	var refl := _reflectors()
	var pts: Array[Vector3] = [beacon_pos]
	var o := beacon_pos
	var d := Vector3(beacon_dir.x, 0.0, beacon_dir.z).normalized()
	_lit.clear()
	_hits.clear()
	chain.clear()
	_seal_hit = false
	var skip: Array[RID] = []
	for r in refl:
		if r[0] is CollisionObject3D:
			skip.append((r[0] as CollisionObject3D).get_rid())
	var space := get_world_3d().direct_space_state
	var used := {}
	for bounce in MAX_BOUNCES:
		var best_t := MAX_DIST
		var best: Array = []
		var best_b := 0.0
		for r in refl:
			if used.has(r[0]):
				continue
			var c: Vector3 = r[2]
			var t := (c - o).dot(d)
			if t < 0.3 or t > best_t:
				continue
			var off := c - (o + d * t)
			var b := off.dot(side_of(d))
			if absf(b) < CATCH_R and absf(off.y) < 1.0:
				best_t = t
				best = r
				best_b = b
		var den := d.z
		if not is_open and absf(den) > 0.001:
			var st := (seal_center().z - o.z) / den
			if st > 0.2 and st < best_t:
				var sp := o + d * st
				if absf(sp.x - seal_center().x) < SEAL_HALF and d.z < 0.0:
					best_t = st
					best = ["seal"]
		var q := PhysicsRayQueryParameters3D.create(o + d * 0.05, o + d * best_t, 1)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pts.append(hit["position"])
			break
		if best.is_empty():
			pts.append(o + d * best_t)
			break
		if best[0] is String:
			pts.append(o + d * best_t)
			_seal_hit = true
			break
		# отражение от корпуса дрона
		var c: Vector3 = best[2]
		var id: int = best[1]
		pts.append(c)
		_lit[id] = bounce
		_hits[id] = [o, d]
		chain.append(id)
		used[best[0]] = true
		d = d.rotated(Vector3.UP, turn_for_offset(best_b))
		o = c
	return pts


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_pulse += delta
	var pts := trace()
	if multiplayer.is_server():
		_host_step(delta)
	_update_auras(delta)
	_local_burn(delta)
	# луч
	for k in _beam_parts.size():
		var part := _beam_parts[k]
		if k < pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var seg := a.distance_to(b)
			part.visible = seg > 0.01
			var dir := (b - a) / maxf(seg, 0.001)
			var x := Vector3.UP.cross(dir).normalized()
			if x.length() < 0.5:
				x = Vector3.RIGHT
			var bas := Basis(x, dir, x.cross(dir).normalized())
			var w := 1.0 + 0.15 * sin(_pulse * 8.0 + k)
			part.global_transform = Transform3D(bas.scaled_local(Vector3(w, seg, w)), (a + b) * 0.5)
		else:
			part.visible = false
	var end := pts[pts.size() - 1]
	_hit_light.global_position = end
	_sparks.global_position = end
	_sparks.emitting = not is_open
	# печать
	_seal_mat.emission_energy_multiplier = 0.3 + charge * 6.0 + (2.0 if _seal_hit else 0.0)
	_seal.rotation.z += delta * (0.3 + charge * 4.0)
	var cl := _seal.get_node("ChargeLabel") as Label3D
	cl.text = "" if is_open else "%d%%" % roundi(charge * 100.0)
	if is_open:
		_sign.text = "ПУТЬ ОТКРЫТ"
	elif _seal_hit:
		_sign.text = "ЛУЧ В ПЕЧАТИ! ДЕРЖИТЕ!  %d%%" % roundi(charge * 100.0)
	else:
		_sign.text = "ОТРАЗИТЕ ЛУЧ МАЯКА КОРПУСАМИ В ПЕЧАТЬ  ·  %d%%" % roundi(charge * 100.0)
	if is_open:
		_lift = minf(_lift + delta / 2.5, 1.0)
	_door.position.y = -_lift * (gate_height + 0.3)


## Силовое поле корпуса: вспыхивает, когда дрон в луче
func _update_auras(_delta: float) -> void:
	var nodes: Array = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("coop_helper")
	for n in nodes:
		var node := n as Node3D
		var id := int(node.get("peer_id"))
		if not _auras.has(node) or not is_instance_valid(_auras[node][0]):
			_auras[node] = _make_aura(node)
		var sph: MeshInstance3D = _auras[node][0]
		var mat: StandardMaterial3D = _auras[node][1]
		var on := _lit.has(id) and not is_open
		sph.visible = on
		if on:
			var flick := 0.75 + 0.25 * sin(_pulse * 23.0 + float(id))
			mat.albedo_color = Color(1.0, 0.55, 0.15, 0.13 * flick)
			mat.emission_energy_multiplier = 1.2 + flick
			sph.scale = Vector3(0.62, 0.9, 0.62) * (0.96 + 0.04 * sin(_pulse * 17.0))


func _make_aura(node: Node3D) -> Array:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 2.0
	mat.rim_enabled = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = _aura_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3.UP * BODY_H
	mi.visible = false
	node.add_child(mi)
	return [mi, mat]


## Луч жжёт свой дрон (и ботов-курьеров у хоста); подсказка внизу экрана
func _local_burn(delta: float) -> void:
	for b in get_tree().get_nodes_in_group("player"):
		if b.get("is_bot") and _lit.has(int(b.get("peer_id"))):
			var at: Vector3 = (b as Node3D).global_position + Vector3.UP * BODY_H
			if _hits.has(int(b.get("peer_id"))):
				at -= (_hits[int(b.get("peer_id"))][1] as Vector3) * 0.3
			b.take_damage(BURN_DPS * delta, "burn", at)
	var me: Node3D = Network.local_player
	if me == null or is_open or not in_zone(me.global_position):
		_hud_hint.visible = false
		return
	_hud_hint.visible = true
	var id := int(me.get("peer_id"))
	if _lit.has(id):
		var hit_at: Vector3 = me.global_position + Vector3.UP * BODY_H
		if _hits.has(id):
			hit_at -= (_hits[id][1] as Vector3) * 0.3     # след — на боку, куда бьёт луч
		me.take_damage(BURN_DPS * delta, "burn", hit_at)
		me.add_shake(0.04)
		var role := "первый в цепочке" if int(_lit[id]) == 0 else "отражение №%d" % (int(_lit[id]) + 1)
		_hud_hint.text = "ЛУЧ ЖЖЁТ КОРПУС! (%s)  Переступай вбок — отражение повернёт. Ctrl — точный шаг" % role
	else:
		_hud_hint.text = "Поймайте луч маяка корпусом и отразите в печать. Центр — луч назад, край — вбок"


func _host_step(delta: float) -> void:
	if not is_open:
		if _seal_hit:
			charge = minf(charge + delta / CHARGE_TIME, 1.0)
			if charge >= 1.0:
				_open.rpc()
		else:
			charge = maxf(charge - delta * CHARGE_LEAK, 0.0)
	_send -= delta
	if _send <= 0.0:
		_send = SEND_INTERVAL
		_state.rpc(charge)


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(new_charge: float) -> void:
	charge = new_charge


@rpc("authority", "call_local", "reliable")
func _open() -> void:
	if is_open:
		return
	is_open = true
	charge = 1.0
	var me = Network.local_player
	if me and me.global_position.distance_to(global_position) < 80.0:
		me.add_shake(0.3)
	get_tree().call_group("level", "show_banner", "Луч дошёл до печати!", "Ледяной вал открыт — путь на север свободен")


# ---------------------------------------------------------------------------
#  Для бота-помощника (только у хоста). Бот встаёт либо на луч маяка (точка A)
#  и отражает его на игрока (или в точку B), либо — если луч уже ловит игрок —
#  за конец барьера (точка B) и отражает луч в печать. Целится бот, как и игрок, —
#  смещаясь вбок от линии луча.
# ---------------------------------------------------------------------------
func _bot_role(bot: Node) -> int:
	var human := not chain.is_empty() and int(chain[0]) >= 0
	var want := 1 if human else 0
	for b in get_tree().get_nodes_in_group("coop_helper"):
		if b != bot and int(b.get("_claimed_slot")) == 0:
			want = 1
	var cur := int(bot.get("_claimed_slot"))
	if cur < 0 or cur == want:
		bot.set_meta("role_wait", 0.0)
		return want
	var waited: float = bot.get_meta("role_wait", 0.0) + 0.4
	bot.set_meta("role_wait", waited)
	return want if waited >= 2.0 else cur


## Куда боту встать: в свою точку, но со сдвигом поперёк луча — чтобы отражение ушло к цели
func bot_target(bot: Node3D, _owner_node: Node3D) -> Vector3:
	if is_open:
		return Vector3.INF
	var role := _bot_role(bot)
	bot.set("_claimed_slot", role)
	var id := int(bot.get("peer_id"))
	var spot := bot_spot_a if role == 0 else bot_spot_b
	var o: Vector3
	var d: Vector3
	if _hits.has(id):
		o = _hits[id][0]
		d = _hits[id][1]
	elif role == 0:
		o = beacon_pos
		d = Vector3(beacon_dir.x, 0, beacon_dir.z).normalized()
	else:
		return spot            # ждём, пока луч дойдёт
	var target: Vector3
	if role == 0:
		target = bot_spot_b + Vector3.UP * BODY_H
		for p in get_tree().get_nodes_in_group("player"):
			var pn := p as Node3D
			if in_zone(pn.global_position) and not bool(pn.get("is_dead")) and pn.global_position.z < spot.z - 3.0:
				target = pn.global_position + Vector3.UP * BODY_H
				break
	else:
		target = seal_center()
	# точка на линии луча возле своей точки
	var t := (spot + Vector3.UP * BODY_H - o).dot(d)
	var on_line := o + d * t
	var out := target - on_line
	out.y = 0.0
	var angle := d.signed_angle_to(out.normalized(), Vector3.UP)
	var b := offset_for_turn(angle)
	var pos := on_line + side_of(d) * b
	return Vector3(pos.x, spot.y, pos.z)


func bot_work(_bot: Node3D, _delta: float) -> void:
	pass


func bot_release(_bot: Node) -> void:
	pass
