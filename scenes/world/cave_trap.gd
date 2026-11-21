extends Node3D
## Пещера-ловушка «Убежище» (каньон, западная дорога от развилки A).
##
## Снаружи: табличка «Убежище», внутри видно тёплый свет и кристаллы — манит зайти.
## Стоит дрону пройти внутрь, как сверху у входа падает огромный камень и запирает выход.
## Внутри — ядовитый воздух: корпус медленно слабеет (целый — за ~4 мин).
## Камень раскачивают, стоя у него и держа E — дроны упираются в него руками;
## камень качается всё сильнее и понемногу кренится наружу, сверху появляется щель со светом.
##   снаружи: один дрон — ~2.5 мин, вдвоём — ~1 мин, втроём — ~35 с;
##   изнутри (если застрял один) — ~3 мин: яд за это время съедает почти весь корпус.
## В зале пещеры лежит деталь подъёмника (шестерня) — за ней приходится лезть в ловушку.
## Раскачанный камень переваливается наружу и срывается в пропасть. Когда в пещере никого не осталось,
## ловушка снова взводится (новый камень прячется в потолке).
## Решает хост, остальным рассылает: закрыто / сколько отодвинули / открыто.

const HUMMOCKS := preload("res://scenes/world/hummock_builder.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const HEATER := preload("res://scenes/world/heat_source.gd")

const POISON_TIME := 240.0       ## За сколько секунд яд ломает целый корпус
const PUSH_TIME := [0.0, 150.0, 60.0, 35.0, 25.0]   ## Сколько раскачивать: 1, 2, 3, 4+ дронов
const TILT := 0.3                ## Насколько камень кренится наружу к концу
const STONE_SIZE := Vector3(6.5, 10.5, 12.5)
const INSIDE_TIME := 180.0       ## Один дрон изнутри раскачивает камень за столько секунд
const TRIGGER_DEPTH := 7.0       ## Насколько глубоко зайти, чтобы камень упал

enum { OPEN, CLOSED, CLEARED }
var state := OPEN
var progress := 0.0
var pushers := 0                 ## сколько сейчас толкают (для вида)
var pusher_ids: Array = []       ## кто толкает (имена узлов дронов) — для позы
var _rock := 0.0                 ## раскачка (фаза)
var _rock_amp := 0.0
var _chips: GPUParticles3D

var _mouth: Vector2
var _y := 0.0
var _rest := Vector3.ZERO        ## где камень стоит, когда закрыл вход
var _hidden := Vector3.ZERO      ## где прячется в потолке (точка опоры)
var _pivot := Vector3.ZERO       ## точка опоры камня: низ наружной грани
var _stone: Node3D
var _stone_col: CollisionShape3D
var _anim := 0.0                 ## > 0 — идёт анимация (падение / подъём / срыв)
var _anim_kind := ""
var _clock := 0.0
var _push_seen := {}             ## хост: кто толкал (peer или имя бота) → время
var _ping_t := 0.0
var _sync_t := 0.0
var _empty_t := 0.0
var _poison := {}                ## дрон → накопленный яд (до целой единицы)
var _gas: GPUParticles3D
var _gas_mat: StandardMaterial3D
var _dust: GPUParticles3D
var _hud: CanvasLayer
var _label: Label
var _tint: ColorRect
var _hint3d: Label3D


func _ready() -> void:
	_mouth = CanyonLayout.CAVE_MOUTH
	_y = CanyonLayout.CAVE_Y
	_rest = Vector3(_mouth.x - STONE_SIZE.x * 0.5 + 0.2, _y, _mouth.y)
	_pivot = _rest + Vector3(STONE_SIZE.x * 0.5, 0.0, 0.0)
	_hidden = _pivot + Vector3(0.0, CanyonLayout.CAVE_CEIL + 2.0, 0.0)
	_build_roof()
	_build_inside()
	_build_stone()
	_build_hud()


# ---------------------------------------------------------------------------
#  Постройка
# ---------------------------------------------------------------------------

func _ice_mat(deep: Color, mid: Color, snow: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ICE_SHADER
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("mid", mid)
	m.set_shader_parameter("edge", Color(0.55, 0.75, 0.9))
	m.set_shader_parameter("snow_amount", snow)
	m.set_shader_parameter("band_scale", 0.8)
	m.set_shader_parameter("band_amount", 0.5)
	return m


## Ледяная крыша над тоннелем и залом (пол и стены — рельеф)
func _build_roof() -> void:
	var mat := _ice_mat(Color(0.02, 0.08, 0.16), Color(0.08, 0.22, 0.36), 1.0)
	var body := StaticBody3D.new()
	body.name = "CaveRoof"
	add_child(body)
	var bottom := _y + CanyonLayout.CAVE_CEIL
	var top := CanyonLayout.PLATEAU + 2.0
	var a := Vector2(_mouth.x + 0.6, _mouth.y)
	var b := CanyonLayout.CAVE_END + (CanyonLayout.CAVE_END - _mouth).normalized() * 6.0
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	var yaw := atan2(-(b.y - a.y), b.x - a.x)
	var box := BoxMesh.new()
	box.size = Vector3(len, top - bottom, CanyonLayout.CAVE_HALF * 2.0 + 3.0)
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(mid.x, (top + bottom) * 0.5, mid.y)
	mi.rotation.y = yaw
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = box.size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = mi.position
	col.rotation = mi.rotation
	body.add_child(col)
	var h := CanyonLayout.CAVE_HALL
	var cyl := CylinderMesh.new()
	cyl.top_radius = h.z + 2.0
	cyl.bottom_radius = h.z + 2.0
	cyl.height = top - bottom - 1.5          # в зале потолок чуть выше — купол
	cyl.radial_segments = 24
	cyl.material = mat
	var ci := MeshInstance3D.new()
	ci.mesh = cyl
	ci.position = Vector3(h.x, bottom + 1.5 + cyl.height * 0.5, h.y)
	add_child(ci)
	var cs := CylinderShape3D.new()
	cs.radius = cyl.top_radius
	cs.height = cyl.height
	var cc := CollisionShape3D.new()
	cc.shape = cs
	cc.position = ci.position
	body.add_child(cc)
	# сосульки с потолка
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var ic_mat := StandardMaterial3D.new()
	ic_mat.albedo_color = Color(0.7, 0.88, 1.0, 0.85)
	ic_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ic_mat.roughness = 0.1
	for i in 26:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * h.z
		var p := Vector3(h.x + cos(ang) * r, bottom + 1.5, h.y + sin(ang) * r)
		var cone := CylinderMesh.new()
		cone.top_radius = rng.randf_range(0.12, 0.3)
		cone.bottom_radius = 0.0
		cone.height = rng.randf_range(0.8, 2.6)
		cone.radial_segments = 6
		cone.material = ic_mat
		var icm := MeshInstance3D.new()
		icm.mesh = cone
		icm.position = p - Vector3(0, cone.height * 0.5, 0)
		icm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(icm)


## Внутри: тёплый свет и кристаллы (приманка), ядовитая дымка, жаровня, табличка у входа
func _build_inside() -> void:
	var h := CanyonLayout.CAVE_HALL
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	var cr_mat := StandardMaterial3D.new()
	cr_mat.albedo_color = Color(0.45, 1.0, 0.85)
	cr_mat.emission_enabled = true
	cr_mat.emission = Color(0.3, 1.0, 0.75)
	cr_mat.emission_energy_multiplier = 2.5
	for i in 9:
		var ang := PI * 0.6 + rng.randf_range(-1.2, 1.2)
		var p := Vector3(h.x + cos(ang) * (h.z - 2.0), _y, h.y + sin(ang) * (h.z - 2.0))
		var pm := PrismMesh.new()
		pm.size = Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(1.4, 3.2), rng.randf_range(0.5, 0.9))
		pm.material = cr_mat
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.position = p + Vector3(0, pm.size.y * 0.5, 0)
		mi.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.45, 1.0, 0.8)
	glow.light_energy = 2.2
	glow.omni_range = 22.0
	glow.position = Vector3(h.x - 6.0, _y + 3.0, h.y)
	add_child(glow)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 1.6
	warm.omni_range = 14.0
	warm.position = Vector3(h.x + 3.0, _y + 2.0, h.y + 4.0)
	add_child(warm)
	var heater := Node3D.new()
	heater.set_script(HEATER)
	heater.name = "CaveHeater"
	heater.position = Vector3(h.x + 3.0, _y, h.y + 4.0)
	add_child(heater)
	# ядовитая дымка: слабая всегда (намёк), густая — когда вход завален
	_gas = FX.particles(Color(0.55, 0.95, 0.35, 0.22), 160, 6.0, 1.4, 0.1, 0.4, Vector3(0, 0.03, 0), 180.0, false)
	FX.set_box(_gas, Vector3(h.z * 0.8, 1.6, h.z * 0.8))
	_gas.position = Vector3(h.x, _y + 1.6, h.y)
	_gas.amount_ratio = 0.25
	_gas.emitting = true
	_gas_mat = (_gas.draw_pass_1 as SphereMesh).material as StandardMaterial3D
	add_child(_gas)
	_dust = FX.particles(Color(0.85, 0.9, 0.95, 0.8), 140, 1.8, 0.35, 2.0, 7.0, Vector3(0, -6, 0))
	FX.set_box(_dust, Vector3(3.0, 1.0, 6.0))
	add_child(_dust)
	# табличка у входа — приманка
	var sign := Label3D.new()
	sign.text = "УБЕЖИЩЕ\nтепло и укрытие от ветра"
	sign.font_size = 48
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.82, 0.5)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(_mouth.x + 1.5, _y + CanyonLayout.CAVE_CEIL + 1.2, _mouth.y)
	add_child(sign)


func _build_stone() -> void:
	_stone = StaticBody3D.new()
	_stone.name = "CaveStone"
	add_child(_stone)
	var b = HUMMOCKS.new(9)
	var mesh: Mesh = null
	var ab := AABB()
	if b != null and HUMMOCKS._rocks.has("nature_rock_big_1"):
		mesh = HUMMOCKS._rocks["nature_rock_big_1"][0]
		ab = HUMMOCKS._rocks["nature_rock_big_1"][1]
	var mi := MeshInstance3D.new()
	if mesh:
		mi.mesh = mesh
		var s := Vector3(STONE_SIZE.x / ab.size.x, STONE_SIZE.y / ab.size.y, STONE_SIZE.z / ab.size.z) * 1.08
		mi.scale = s
		mi.position = -Vector3((ab.position.x + ab.size.x * 0.5) * s.x, ab.position.y * s.y, (ab.position.z + ab.size.z * 0.5) * s.z) - Vector3(STONE_SIZE.x * 0.5, 0, 0)
	else:
		var bm := BoxMesh.new()
		bm.size = STONE_SIZE
		mi.mesh = bm
		mi.position = Vector3(-STONE_SIZE.x * 0.5, STONE_SIZE.y * 0.5, 0)
	mi.material_override = _ice_mat(Color(0.12, 0.13, 0.16), Color(0.3, 0.32, 0.36), 0.8)
	_stone.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = STONE_SIZE
	_stone_col = CollisionShape3D.new()
	_stone_col.shape = shape
	_stone_col.position = Vector3(-STONE_SIZE.x * 0.5, STONE_SIZE.y * 0.5, 0)
	_stone_col.disabled = true
	# ледяная крошка из-под камня, когда его раскачивают
	_chips = FX.particles(Color(0.82, 0.9, 1.0), 40, 0.9, 0.09, 1.2, 3.5, Vector3(0, -9, 0), 60.0, false)
	FX.set_box(_chips, Vector3(0.3, 0.2, STONE_SIZE.z * 0.45))
	_chips.position = Vector3(0.2, 0.2, 0)
	_chips.emitting = false
	_stone.add_child(_chips)
	_stone.add_child(_stone_col)
	_stone.position = _hidden
	_hint3d = Label3D.new()
	_hint3d.font_size = 40
	_hint3d.outline_size = 12
	_hint3d.modulate = Color(1.0, 0.85, 0.4)
	_hint3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint3d.position = Vector3(_mouth.x + 2.0, _y + 4.0, _mouth.y)
	_hint3d.visible = false
	add_child(_hint3d)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_tint = ColorRect.new()
	_tint.color = Color(0.25, 0.75, 0.15, 0.0)
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_tint)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 10)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -520.0
	_label.offset_right = 520.0
	_label.offset_top = 170.0
	_label.offset_bottom = 260.0
	_label.visible = false
	_hud.add_child(_label)


# ---------------------------------------------------------------------------
#  Кто где
# ---------------------------------------------------------------------------

## Дрон внутри, за камнем
func is_inside(p: Vector3) -> bool:
	return CanyonLayout.in_cave(p.x, p.z) and p.x < _rest.x - STONE_SIZE.x * 0.5 + 1.2 and p.y < _y + CanyonLayout.CAVE_CEIL


## Дрон внутри у камня (толкает изнутри — медленно)
func is_at_stone_inside(p: Vector3) -> bool:
	var inner := _pivot.x - STONE_SIZE.x
	return p.x < inner + 1.2 and p.x > inner - 3.5 and absf(p.z - _mouth.y) < STONE_SIZE.z * 0.5 + 1.0 \
		and absf(p.y - _y) < 3.0


## Дрон снаружи у камня (может толкать)
func is_at_stone(p: Vector3) -> bool:
	var front := _pivot.x + 0.3
	return p.x > front - 1.0 and p.x < front + 4.5 and absf(p.z - _mouth.y) < STONE_SIZE.z * 0.5 + 1.0 \
		and absf(p.y - _y) < 3.0


# ---------------------------------------------------------------------------
#  Ход игры
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_animate(delta)
	if multiplayer.is_server():
		_server_tick(delta)
	_local_tick(delta)


func _server_tick(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	match state:
		OPEN:
			if _anim > 0.0:
				return
			for d in players:
				var p: Vector3 = d.global_position
				if not d.is_dead and CanyonLayout.in_cave(p.x, p.z) and p.x < _mouth.x - TRIGGER_DEPTH:
					_close.rpc()
					return
		CLOSED:
			if _anim > 0.0:
				return
			# боты, которым велено держать E, тоже толкают
			for d in players:
				if d.has_method("_ai_driven") and d._ai_driven() and not d.is_dead and (is_at_stone(d.global_position) or is_at_stone_inside(d.global_position)) and d._held("interact"):
					_push_seen[String(d.name)] = _clock
			var n := 0
			var n_in := 0
			var ids: Array = []
			for k in _push_seen.keys():
				if _clock - float(_push_seen[k]) < 0.45:
					if _pushes_inside(String(k)):
						n_in += 1
					else:
						n += 1
					ids.append(k)
				else:
					_push_seen.erase(k)
			pushers = n + n_in
			pusher_ids = ids
			if n > 0:
				progress += delta / float(PUSH_TIME[mini(n, 4)])
			progress = minf(progress + delta * n_in / INSIDE_TIME, 1.0)
			_sync_t -= delta
			if _sync_t <= 0.0:
				_sync_t = 0.1
				_sync.rpc(progress, pushers, pusher_ids)
			if progress >= 1.0:
				_clear.rpc()
				return
			# внутри никого живого — камень уходит обратно в потолок
			var anyone := false
			for d in players:
				if not d.is_dead and is_inside(d.global_position):
					anyone = true
			_empty_t = 0.0 if anyone else _empty_t + delta
			if _empty_t > 6.0:
				_rearm.rpc()
		CLEARED:
			if _anim > 0.0:
				return
			var anyone2 := false
			for d in players:
				if CanyonLayout.in_cave(d.global_position.x, d.global_position.z, 3.0):
					anyone2 = true
			_empty_t = 0.0 if anyone2 else _empty_t + delta
			if _empty_t > 3.0:
				_rearm.rpc()


func _local_tick(delta: float) -> void:
	var me = Network.local_player
	# яд — каждому, кого считает этот компьютер (take_damage сам пропустит чужих)
	if state == CLOSED:
		for d in get_tree().get_nodes_in_group("player"):
			if d.is_dead or not is_inside(d.global_position):
				continue
			var acc: float = _poison.get(d, 0.0) + delta * d.max_health / POISON_TIME
			if acc >= 1.0:
				d.take_damage(floorf(acc), "poison")
				acc -= floorf(acc)
			_poison[d] = acc
	# подсказки
	var txt := ""
	var col := Color(1.0, 0.85, 0.4)
	var tint := 0.0
	if me and is_instance_valid(me) and not me.is_dead:
		var p: Vector3 = me.global_position
		if state == CLOSED and is_inside(p):
			txt = "Вход завалило! Ядовитый воздух — корпус слабеет (%d%%)" % int(me.health / me.max_health * 100.0)
			if is_at_stone_inside(p):
				txt += "\nДержите E — упереться в камень изнутри (одному очень долго, друзья снаружи — быстрее)"
			else:
				txt += "\nПодойдите к камню и держите E — или ждите друзей снаружи"
			if progress > 0.01:
				txt += "\nКамень сдвигают: %d%%" % int(progress * 100.0)
			col = Color(0.6, 1.0, 0.45)
			tint = 0.1 + 0.06 * sin(_clock * 3.0)
			if is_at_stone_inside(p) and me._held("interact"):
				_ping_t -= delta
				if _ping_t <= 0.0:
					_ping_t = 0.2
					if multiplayer.is_server():
						_push_seen[str(multiplayer.get_unique_id())] = _clock
					else:
						_push.rpc_id(1)
		elif state == CLOSED and is_at_stone(p):
			if pushers > 0:
				txt = "Раскачиваете камень: %d%%   (толкают: %d)\nВдвоём — вдвое с лишним быстрее" % [int(progress * 100.0), pushers]
			else:
				txt = "Держите E — упереться и раскачать камень: %d%%\n(одному — очень долго, вдвоём — быстрее)" % int(progress * 100.0)
			if me._held("interact"):
				_ping_t -= delta
				if _ping_t <= 0.0:
					_ping_t = 0.2
					if multiplayer.is_server():
						_push_seen[str(multiplayer.get_unique_id())] = _clock
					else:
						_push.rpc_id(1)
	_label.visible = txt != ""
	_label.text = txt
	_label.add_theme_color_override("font_color", col)
	_tint.color.a = move_toward(_tint.color.a, tint, delta * 0.5)
	_hint3d.visible = state == CLOSED
	if state == CLOSED:
		_hint3d.text = "E — раскачать камень  %d%%" % int(progress * 100.0)
	_gas.amount_ratio = move_toward(_gas.amount_ratio, 1.0 if state == CLOSED else 0.25, delta * 0.3)
	# поза: кто толкает — упирается ладонями в камень
	for d in get_tree().get_nodes_in_group("player"):
		var outside: bool = is_at_stone(d.global_position)
		var inside: bool = is_at_stone_inside(d.global_position)
		var pushing: bool = state == CLOSED and (outside or inside) and (pusher_ids.has(String(d.name)) or pusher_ids.has(str(d.get_multiplayer_authority())))
		if d == me and state == CLOSED and (outside or inside) and me._held("interact"):
			pushing = true
		var face_pt := Vector3.ZERO
		if pushing:
			var zz := clampf(d.global_position.z, _pivot.z - STONE_SIZE.z * 0.4, _pivot.z + STONE_SIZE.z * 0.4)
			var fx := _pivot.x + 0.15 + sin(_rock) * 0.25 if outside else _pivot.x - STONE_SIZE.x - 0.15 + progress * 0.35
			face_pt = Vector3(fx, d.global_position.y + 1.25, zz)
		d.set("external_push", face_pt)


## Толкающий (по имени узла или peer id) стоит внутри пещеры?
func _pushes_inside(key: String) -> bool:
	for d in get_tree().get_nodes_in_group("player"):
		if String(d.name) == key or str(d.get_multiplayer_authority()) == key:
			return is_inside(d.global_position)
	return false


@rpc("any_peer", "call_remote", "unreliable")
func _push() -> void:
	if multiplayer.is_server():
		_push_seen[str(multiplayer.get_remote_sender_id())] = _clock


@rpc("authority", "call_local", "reliable")
func _close() -> void:
	state = CLOSED
	progress = 0.0
	pushers = 0
	_empty_t = 0.0
	_poison.clear()
	_anim_kind = "drop"
	_anim = 0.5
	_stone.position = _hidden
	_stone.rotation = Vector3.ZERO
	_stone.visible = true


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(p: float, n: int, ids: Array) -> void:
	progress = p
	pushers = n
	pusher_ids = ids


@rpc("authority", "call_local", "reliable")
func _clear() -> void:
	state = CLEARED
	progress = 1.0
	_empty_t = 0.0
	_anim_kind = "fall"
	_anim = 3.2
	_dust.global_position = _pivot + Vector3(2.0, 1.0, 0.0)
	_dust.restart()
	# кто стоит перед камнем — отпрыгнуть! (его задевает)
	for d in get_tree().get_nodes_in_group("player"):
		var p: Vector3 = d.global_position
		if p.x > _pivot.x and p.x < _pivot.x + 9.0 and absf(p.z - _pivot.z) < STONE_SIZE.z * 0.5 + 0.5 and absf(p.y - _y) < 3.0:
			d.receive_hit(Vector3(0.3, 0.2, signf(p.z - _pivot.z + 0.01)).normalized(), 1.5, _pivot + Vector3(1.0, 3.0, 0.0))
	_stone_col.set_deferred("disabled", true)


@rpc("authority", "call_local", "reliable")
func _rearm() -> void:
	_empty_t = 0.0
	if state == CLOSED:
		_anim_kind = "rise"
		_anim = 2.0
		_stone_col.set_deferred("disabled", true)
	else:
		_stone.position = _hidden
		_stone.rotation = Vector3.ZERO
		_stone.visible = true
	state = OPEN
	progress = 0.0


func _animate(delta: float) -> void:
	if _anim <= 0.0:
		if state == CLOSED:
			# раскачивают: качается всё сильнее и понемногу кренится наружу (сверху — щель)
			_rock_amp = move_toward(_rock_amp, (0.025 + 0.05 * progress) if pushers > 0 else 0.0, delta * 0.08)
			_rock += delta * (2.6 + 0.6 * pushers)
			var lean := progress * TILT + _rock_amp * (0.5 + 0.5 * sin(_rock))
			_stone.position = _pivot + Vector3(progress * 0.35, 0.0, 0.0)
			_stone.rotation = Vector3(0.03 * sin(_rock * 0.5) * _rock_amp * 10.0, 0.0, -lean)
			_chips.emitting = pushers > 0
			var me = Network.local_player
			if pushers > 0 and me and me.global_position.distance_to(_pivot) < 14.0 and fposmod(_rock, TAU) < delta * 3.5:
				me.add_shake(0.04 + 0.08 * progress)
		return
	_anim = maxf(_anim - delta, 0.0)
	match _anim_kind:
		"drop":
			var k := 1.0 - _anim / 0.5
			_stone.position = _hidden.lerp(_pivot, k * k)
			if _anim <= 0.0:
				_stone.position = _pivot
				_land()
		"rise":
			var k2 := 1.0 - _anim / 2.0
			_stone.position = _pivot.lerp(_hidden, smoothstep(0.0, 1.0, k2))
			_stone.rotation = _stone.rotation.lerp(Vector3.ZERO, smoothstep(0.0, 1.0, k2))
		"fall":
			# переваливается наружу (на площадку), скользит к краю и срывается в пропасть
			var t := 3.2 - _anim
			var base := _pivot + Vector3(0.35, 0.0, 0.0)
			_chips.emitting = false
			if t < 1.1:
				var k3 := t / 1.1
				_stone.position = base
				_stone.rotation = Vector3(0.0, 0.0, -lerpf(TILT, PI * 0.5, k3 * k3))
			elif t < 2.0:
				var u := (t - 1.1) / 0.9
				_stone.position = base + Vector3(u * u * 7.0, 0.0, 0.0)
				_stone.rotation = Vector3(0.0, 0.0, -PI * 0.5 - u * 0.4)
			else:
				var u2 := t - 2.0
				_stone.position = base + Vector3(7.0 + u2 * 5.0, -u2 * u2 * 22.0, 0.0)
				_stone.rotation = Vector3(u2 * 0.7, 0.0, -PI * 0.5 - 0.4 - u2 * 1.8)
			if _anim <= 0.0:
				_stone.visible = false


## Камень встал: включаем твёрдость, кто оказался под ним — выталкиваем, всех трясёт
func _land() -> void:
	_stone_col.disabled = false
	_dust.global_position = Vector3(_rest.x, _y + 1.0, _rest.z)
	_dust.restart()
	var x0 := _rest.x - STONE_SIZE.x * 0.5
	var x1 := _rest.x + STONE_SIZE.x * 0.5
	for d in get_tree().get_nodes_in_group("player"):
		var p: Vector3 = d.global_position
		if p.x > x0 - 0.6 and p.x < x1 + 0.6 and absf(p.z - _rest.z) < STONE_SIZE.z * 0.5 and absf(p.y - _y) < 3.0:
			# под камнем: внутрь, если ближе к пещере, иначе наружу
			var nx := x0 - 1.2 if p.x < _rest.x else x1 + 1.2
			if d.is_local:
				d.teleport_to(Vector3(nx, p.y + 0.2, p.z))
		var me = Network.local_player
		if d == me and Vector2(p.x - _rest.x, p.z - _rest.z).length() < 40.0:
			me.add_shake(0.45)
