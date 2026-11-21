extends Node3D
## Шаг 119: ночь на Плече и ночная дорога к стене.
##   * кто первым ступил на Плечо — темнеет и до самой вершины ночь (на вершине — рассвет);
##   * у всех налобные фонари (T — вкл/выкл); вдоль дороги — вешки с огоньками; в стороне — тьма и обрывы;
##   * обледенелые подъёмы: бегом — укатишься вниз по дороге, медленно (Ctrl) — пройдёшь;
##   * приколы: снежки (Q, руки пустые) — попал в того, кто лезет, — силы долой, на дороге — фонарь гаснет;
##     R рядом с другом — сорвать ему фонарь (он включит снова — T).
## Приют на Плече — просто укрытие (печки и дров больше нет).
## Решает хост (ночь/рассвет); фонари и снежки — у всех (кто бросил — тот и считает попадание).

const M := preload("res://scenes/world/mountain_layout.gd")
const GATE := preload("res://scenes/world/mountain_gate.gd")
const SFX := preload("res://scripts/sfx.gd")
const PK := "res://assets/peak/"   ## шаг 122: ассеты Пика (лёд, скала, снег, Kenney)
const FADE_IN := 8.0
const FADE_OUT := 20.0
const POLE_STEP := 9.0             ## вешки — через столько метров (по очереди с разных сторон)
const BALL_CD := 0.7
const SCOOP_T := 0.95              ## шаг 122: слепить снежок
const THROW_T := 0.55              ## шаг 122: бросок (замах + хлёст + доводка)
const BALL_V := 17.0
const SLIDE_V := 11.0              ## шаг 121: на ледяном пятне — качусь вниз (управления нет)

var mtn: Node
var phase := 0                     ## 0 — ещё не было, 1 — ночь, 2 — рассвело (на вершине)
var is_open := false               ## для ботов: «ворота» дороги всегда в деле (bot_target сам решает)
var _t := 0.0                      ## сколько длится фаза
var _sync_t := 0.0
var lamp_off := {}                 ## дрон → фонарь выключен (у всех)
var _lamps := {}                   ## дрон → SpotLight3D (у всех)
var _ball_cd := 0.0
var has_ball := {}                 ## шаг 122: дрон → снежок в руке (узел)
var _throw_t := -1.0               ## свой бросок идёт (сек), −1 — нет
var _balls: Array = []             ## [узел, скорость, кто бросил, время]
var _slide := 0.0
var _t_prev := false
var _ice_mat: StandardMaterial3D


func build() -> void:
	var hut: Node3D = mtn.hut_top
	if hut and hut.has_method("set_fire"):
		hut.set_fire(1.0)
	_build_poles()
	_build_ice()
	_build_ledge_lights()
	mtn.sign_at(Vector3(M.BX - 6.0, M.SH_Y, M.SH_ZN + 2.0), "НОЧНАЯ ДОРОГА К СТЕНЕ — 240 м\nИди по вешкам с огоньками.\nФонарь — T. Голубой лёд — обходи:\nнаступишь — укатишься вниз!\nE — слепить снежок, Q — бросить.\nR — сорвать фонарь другу.", Color(0.95, 0.85, 0.5))
	GATE.make(self, Vector3(M.BX, M.SH_Y, (M.SH_ZS + M.SH_ZN) * 0.5))
	var L := M.road_len()
	var s := 30.0
	while s < L:
		GATE.make(self, M.road_at(s))
		s += 35.0


## Шаг 120: всё одинаковое — одной пачкой (MultiMesh): шесты, полоски, огоньки — 3 вызова отрисовки на всю дорогу
func _mm(mesh: Mesh, mat: Material, xs: Array, vis := 220.0) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, xs[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = vis
	add_child(mi)


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * e
	return m


## Свет без теней, гаснет вдали (дальше begin — не считается вовсе)
func _omni(p: Vector3, col: Color, e: float, r: float, fade := 45.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = e
	l.omni_range = r
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = fade
	l.distance_fade_length = 10.0
	add_child(l)
	l.global_position = p


## Вешки вдоль дороги: тёмный шест, красная полоска, наверху — оранжевый огонёк; через три — фонарик светит на дорогу
func _build_poles() -> void:
	var L := M.road_len()
	var rod := StandardMaterial3D.new()
	rod.albedo_color = Color(0.12, 0.1, 0.08)
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.9, 0.15, 0.1)
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	sph.radial_segments = 8
	sph.rings = 4
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.045
	cyl.height = 1.7
	cyl.radial_segments = 6
	cyl.rings = 1
	var bnd := CylinderMesh.new()
	bnd.top_radius = 0.05
	bnd.bottom_radius = 0.05
	bnd.height = 0.22
	bnd.radial_segments = 6
	bnd.rings = 1
	var xr: Array = []
	var xb: Array = []
	var xg: Array = []
	var k := 0
	var s := 4.0
	while s < L - 2.0:
		var c := M.road_at(s)
		var dir := M.road_dir(s)
		var lat := Vector3(-dir.z, 0.0, dir.x).normalized()
		var side := 1.0 if k % 2 == 0 else -1.0
		var p := c + lat * side * (M.ROAD_HALF + 0.25)
		p.y = mtn._gy(p.x, p.z)
		xr.append(p + Vector3.UP * 0.85)
		xb.append(p + Vector3.UP * 1.25)
		xg.append(p + Vector3.UP * 1.78)
		if k % 3 == 0:
			_omni(p + Vector3.UP * 1.8, Color(1.0, 0.65, 0.3), 0.9, 7.0)
		k += 1
		s += POLE_STEP
	_mm(cyl, rod, xr, 120.0)
	_mm(bnd, band, xb, 120.0)
	_mm(sph, _glow(Color(1.0, 0.6, 0.15), 3.0), xg, 400.0)


## Огоньки на полках стены: видно в темноте, где можно отдохнуть (и до вершины ещё сколько)
func _build_ledge_lights() -> void:
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	sph.radial_segments = 8
	sph.rings = 4
	var rod := CylinderMesh.new()
	rod.top_radius = 0.03
	rod.bottom_radius = 0.04
	rod.height = 1.0
	rod.radial_segments = 6
	rod.rings = 1
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.15, 0.15, 0.17)
	var xr: Array = []
	var xg: Array = []
	for k in M.PITCHES.size() - 1:
		var y := M.pitch_top(k)
		var z := M.face_z(k) - M.LEDGE_D * 0.5
		for sx in [-1.0, 1.0]:
			var p := Vector3(M.BX + sx * (M.FACE_W + 0.6), y, z)
			xr.append(p + Vector3.UP * 0.5)
			xg.append(p + Vector3.UP * 1.05)
		_omni(Vector3(M.BX, y + 1.6, M.face_z(k) - 0.6), Color(0.4, 0.85, 1.0), 1.4, 9.0, 60.0)
	_mm(rod, rm, xr, 120.0)
	_mm(sph, _glow(Color(0.3, 0.9, 1.0), 3.0), xg, 400.0)


## Ледяные подъёмы: голубоватая корка поверх дороги (одной сеткой на все три)
func _build_ice() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/peak_ice.gdshader")
	for kv in [["tex_color", "ice_color.jpg"], ["tex_normal", "ice_normal.png"], ["tex_rough", "ice_rough.jpg"]]:
		var p: String = PK + "tex/" + String(kv[1])
		if ResourceLoader.exists(p):
			sm.set_shader_parameter(kv[0], load(p))
	var L := M.road_len()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in M.ROAD_ICE:
		var s0: float = float(r[0]) * L
		var s1: float = float(r[1]) * L
		var ctr := float(r[2])
		var prev: Array = []
		var s := s0
		while s <= s1 + 0.01:
			var c := M.road_at(s)
			var dir := M.road_dir(s)
			var lat := Vector3(-dir.z, 0.0, dir.x).normalized()
			# край неровный, к концам пятно сужается (лёд «натёк» языками)
			var ends := smoothstep(0.0, 3.0, s - s0) * smoothstep(0.0, 3.0, s1 - s)
			var hw := float(r[3]) * (0.55 + 0.45 * ends) * (1.0 + 0.07 * sin(s * 1.3) + 0.04 * sin(s * 3.7))
			var row: Array = []
			for k in 5:
				var q := c + lat * (ctr - hw + 2.0 * hw * k / 4.0)
				q.y = mtn._gy(q.x, q.z) + 0.06
				row.append(q)
			if not prev.is_empty():
				for k in 4:
					for q2 in [prev[k], row[k + 1], prev[k + 1], prev[k], row[k], row[k + 1]]:
						st.set_normal(Vector3.UP)
						st.set_uv(Vector2((q2 as Vector3).x, (q2 as Vector3).z) * 0.22)
						st.add_vertex(q2)
			prev = row
			s += 1.5
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 200.0
	add_child(mi)


func running() -> bool:
	return phase == 1


## Насколько темно (0 — день, 1 — ночь)
func dark_k() -> float:
	if phase == 1:
		return clampf(_t / FADE_IN, 0.0, 1.0)
	if phase == 2:
		return 1.0 - clampf(_t / FADE_OUT, 0.0, 1.0)
	return 0.0


## Снежок метёт слегка (туман у дороги)
func storm_k() -> float:
	return 0.22 * dark_k()


func cold_inside() -> bool:
	return false


func cold_at(_p: Vector3) -> float:
	return -1.0


## Верх горы: Плечо, дорога, стена, вершина
func _near_shoulder(p: Vector3) -> bool:
	return absf(p.x - M.BX) < 120.0 and p.z < M.SH_ZS + 25.0 and p.z > M.BZ - 40.0 and p.y > M.SH_Y - 60.0


func server(delta: float) -> void:
	_t += delta
	if phase == 0:
		for d in get_tree().get_nodes_in_group("player"):
			if not d.is_dead and M.on_shoulder(d.global_position):
				_set_phase_all(1)
				return
		return
	if phase == 1:
		for d in get_tree().get_nodes_in_group("player"):
			if not d.is_dead and d.global_position.y > M.PEAK - 4.0 and Vector2(d.global_position.x - M.BX, d.global_position.z - M.BZ).length() < 30.0:
				_set_phase_all(2)
				return
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 1.0
		if mtn._online():
			_sync.rpc(phase, _t)


func _set_phase_all(ph: int) -> void:
	if mtn._online():
		_set_phase.rpc(ph)
	else:
		_set_phase(ph)


@rpc("authority", "call_local", "reliable")
func _set_phase(ph: int) -> void:
	phase = ph
	_t = 0.0
	pass
	var me = Network.local_player
	var close: bool = me != null and _near_shoulder(me.global_position)
	if ph == 1 and close:
		get_tree().call_group("level", "show_banner", "Наступает ночь…",
			"Дорога к стене — по вешкам. Фонарь — T. Голубой лёд обходи!")
	elif ph == 2 and close:
		get_tree().call_group("level", "show_banner", "Рассвет на вершине!", "Поднимайте посылку лебёдкой")


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(ph: int, t: float) -> void:
	if ph != phase:
		phase = ph
	_t = t


# ---------------------------------------------------------------------------
#  Фонари
# ---------------------------------------------------------------------------

func _lamp_all(pid: int, off: bool) -> void:
	if mtn._online():
		_lamp.rpc(pid, off)
	else:
		_lamp(pid, off)


@rpc("any_peer", "call_local", "reliable")
func _lamp(pid: int, off: bool) -> void:
	if off:
		lamp_off[pid] = true
	else:
		lamp_off.erase(pid)
	var d: Node3D = mtn.drone_by_id(pid)
	if d:
		SFX.play(self, d.global_position + Vector3.UP * 1.7, "click", -6.0, 1.4 if not off else 0.9)


## Фонари у всех: налобный (на голове), светит, куда смотрит голова
func visual(delta: float) -> void:
	var dk := dark_k()
	var me = Network.local_player
	var cam := get_viewport().get_camera_3d()
	for d in get_tree().get_nodes_in_group("player"):
		var pid := int(d.peer_id)
		var zone: bool = _near_shoulder(d.global_position)
		var want: bool = dk > 0.05 and not bool(d.get("is_dead")) and not lamp_off.has(pid) and zone
		var head: Node3D = d.suit.get("head") if d.get("suit") else null
		# шаг 122: свой фонарик костюма (слабый) в ночной зоне — выкл: светит только наш налобный, по T
		var sl: SpotLight3D = d.suit.get("_lamp_light") if d.get("suit") else null
		if sl:
			sl.light_energy = 0.0 if zone and dk > 0.05 else 1.4
		var lt: SpotLight3D = _lamps.get(pid)
		if want and (lt == null or not is_instance_valid(lt)):
			if head == null:
				continue
			# шаг 122: фонарь — НЕ на голове: от 1-го лица голову прячут слоем, и свет пропадал вместе с ней
			lt = SpotLight3D.new()
			lt.light_color = Color(1.0, 0.95, 0.85)
			lt.spot_range = 55.0              # шаг 123: мощный и широкий — без него тьма
			lt.spot_angle = 40.0
			lt.spot_angle_attenuation = 0.7
			lt.spot_attenuation = 0.75
			lt.shadow_enabled = false
			lt.distance_fade_enabled = true          # чужие фонари вдали не считаются
			lt.distance_fade_begin = 60.0
			lt.distance_fade_length = 15.0
			d.add_child(lt)
			lt.top_level = true
			_lamps[pid] = lt
		if lt and is_instance_valid(lt):
			lt.visible = want
			if want and head:
				var hb := head.global_basis.orthonormalized()
				var b := hb
				if d == me and cam:
					b = cam.global_basis.orthonormalized()     # у своего — куда смотрю
				lt.global_transform = Transform3D(b, head.global_position + hb * Vector3(0.14, 0.1, -0.2))
				lt.light_energy = 16.0 * dk
	# снежки
	for i in range(_balls.size() - 1, -1, -1):
		var B: Array = _balls[i]
		var n: Node3D = B[0]
		var v: Vector3 = B[1]
		B[3] = float(B[3]) + delta
		v += Vector3.DOWN * 9.0 * delta
		var from := n.global_position
		var to := from + v * delta
		B[1] = v
		var hit := _ball_hit(from, to, int(B[2]))
		if hit != null or float(B[3]) > 3.0 or to.y < mtn._gy(to.x, to.z):
			if hit != null and int(B[2]) == _my_pid():
				_hit_all(int(hit.peer_id), int(B[2]))
			_splash(to)
			n.queue_free()
			_balls.remove_at(i)
			continue
		n.global_position = to


func _my_pid() -> int:
	var me = Network.local_player
	return int(me.peer_id) if me else -1


func _ball_hit(a: Vector3, b: Vector3, from_pid: int) -> Node3D:
	for d in get_tree().get_nodes_in_group("player"):
		if int(d.peer_id) == from_pid or bool(d.get("is_dead")):
			continue
		var c: Vector3 = d.global_position + Vector3.UP * 1.0
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < 0.75:
			return d
	return null


func _splash(p: Vector3) -> void:
	var sp := FX.particles(Color(0.95, 0.97, 1.0), 14, 0.5, 0.05, 1.0, 3.0, Vector3(0, -9, 0), 160.0, true, true)
	add_child(sp)
	sp.global_position = p
	sp.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sp.queue_free)
	SFX.play(self, p, "puff", -4.0, 1.5, 30.0)


func _throw_all(pid: int, from: Vector3, v: Vector3) -> void:
	if mtn._online():
		_throw.rpc(pid, from, v)
	else:
		_throw(pid, from, v)


@rpc("any_peer", "call_local", "reliable")
func _throw(pid: int, from: Vector3, v: Vector3) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _ball_mesh()
	n.material_override = _ball_mat()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	n.global_position = from
	_balls.append([n, v, pid, 0.0])
	SFX.play(self, from, "swish", -6.0, 1.3, 25.0)


func _hit_all(pid: int, by: int) -> void:
	if mtn._online():
		_hit.rpc(pid, by)
	else:
		_hit(pid, by)


## Попали снежком: кто лезет — силы долой и вздрогнул; на дороге — фонарь гаснет, чуть толкнуло
@rpc("any_peer", "call_local", "reliable")
func _hit(pid: int, by: int) -> void:
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or not d.is_local:
		return
	if d == Network.local_player:
		d.add_shake(0.25)
	if int(d.snow.climb) == 3:
		d.stamina = maxf(float(d.stamina) - 14.0, 0.0)
		if d == Network.local_player:
			mtn.say("Снежком в спину! Силы −14")
	else:
		if not lamp_off.has(pid) and dark_k() > 0.3:
			_lamp_all(pid, true)
		var src: Node3D = mtn.drone_by_id(by)
		if src:
			var dir := d.global_position - src.global_position
			dir.y = 0.0
			d.wind_shove(dir.normalized(), 1.6)
		if d == Network.local_player:
			mtn.say("Снежком! Фонарь погас — T, чтобы включить")


# ---------------------------------------------------------------------------
#  Свой дрон: фонарь (T), снежок (Q), сорвать фонарь (R), лёд
# ---------------------------------------------------------------------------

func local(d: Node3D, _hp: String, _holding: bool, delta: float) -> void:
	var p := d.global_position
	if not _near_shoulder(p) or bool(d.get("is_bot")):
		return
	var pid := int(d.peer_id)
	_ball_cd = maxf(_ball_cd - delta, 0.0)
	if d == Network.local_player and d.controlled and not d.input_blocked:
		var tk := Input.is_physical_key_pressed(KEY_T)
		if tk and not _t_prev:
			_lamp_all(pid, not lamp_off.has(pid))
		_t_prev = tk
	# шаг 122: снежок — E (руки пустые, на снегу): присел, слепил; Q — бросок (замах, хлёст, отпускаю на .55)
	var free: bool = d.held_parcel == null and d.held_friend == null and d.get("held_limb") == null \
		and int(d.snow.climb) == 0 and not bool(d.get("ice_axes"))
	if free and not has_ball.has(pid) and _throw_t < 0.0 and d._just("interact") and _hp == "" and d.is_on_floor() \
			and _scoop_ok(d) and not M.ice_at(p.x, p.z):
		d.snow.start_scripted(41, self, {"t": 0.0})
		SFX.play(self, p, "crunch", -6.0, 1.3)
		return
	if has_ball.has(pid) and _throw_t < 0.0 and d._just("throw") and (not free or d.held_parcel != null):
		_ball_all(pid, false)            # взял что-то в руки — снежок выронил
	elif has_ball.has(pid) and _throw_t < 0.0 and d._just("throw"):
		_throw_t = 0.0
	if _throw_t >= 0.0:
		var mv: bool = Vector2(d.velocity.x, d.velocity.z).length() > 1.0
		var k0 := _throw_t / THROW_T
		_throw_t += delta
		var k1 := _throw_t / THROW_T
		d.snow.set_mpose(31, minf(k1, 1.0), Vector3.ZERO, Vector3.FORWARD, mv)
		if k0 < 0.55 and k1 >= 0.55 and has_ball.has(pid):
			var cam := get_viewport().get_camera_3d()
			var look: Vector3 = -cam.global_basis.z if cam and d == Network.local_player else -(d.get("visual") as Node3D).global_basis.z
			var from: Vector3 = d.suit.fist_pos(1) if d.suit.has_method("fist_pos") else p + Vector3.UP * 1.6
			# летит туда, куда смотрит прицел (камера), из кулака
			var aim := (cam.global_position + look * 30.0) if cam else from + look * 30.0
			var dir2 := (aim - from).normalized()
			_ball_all(pid, false)
			_throw_all(pid, from + dir2 * 0.2, dir2 * BALL_V + Vector3.UP * 2.2 + Vector3(d.velocity.x, 0.0, d.velocity.z) * 0.5)
		if k1 >= 1.0:
			_throw_t = -1.0
			d.snow.set_mpose(0)
	# сорвать фонарь другу: R рядом (спереди или сзади), у него горит
	if d._just("shake_ice") and phase == 1:
		for o in get_tree().get_nodes_in_group("player"):
			if o == d or bool(o.get("is_dead")):
				continue
			var op := int(o.peer_id)
			if not lamp_off.has(op) and o.global_position.distance_to(p) < 1.8:
				_lamp_all(op, true)
				SFX.play(self, o.global_position + Vector3.UP * 1.7, "clank", -6.0, 1.6)
				if d == Network.local_player:
					mtn.say("Сорвал другу фонарь! Пусть ищет T в темноте")
				break
	# шаг 121: наступил на ледяное пятно — не удержаться: ноги разъезжаются, качусь вниз, пока не съеду со льда
	if d.is_on_floor() and int(d.snow.climb) == 0 and M.ice_at(p.x, p.z):
		var rn := M.road_near(p.x, p.z, 8.0)
		var dir := M.road_dir(rn.z)
		var down := Vector3(-dir.x, 0.0, -dir.z).normalized()
		if _slide <= 0.0:
			d.velocity += down * 4.0              # поскользнулся
			SFX.play(self, p, "slide", -4.0, 1.2)
			if d == Network.local_player:
				d.add_shake(0.2)
				mtn.say("Лёд! Ноги разъехались — качусь вниз!")
		_slide = minf(_slide + delta * 14.0, SLIDE_V)
		d.apply_wind(down * _slide)
		d.set("_stagger_timer", 0.15)          # управления нет, дрон шатается
		d.set("_stagger_total", 0.15)
		d.set("_stagger_strength", 0.8)
	else:
		_slide = 0.0


## Шаг 122: тут можно слепить снежок — рядом нет посылки, друга перед носом, стойки с ледорубами
func _scoop_ok(d: Node3D) -> bool:
	if d.has_method("_find_nearest_parcel"):
		var pc = d.call("_find_nearest_parcel")
		if pc != null and (pc as Node3D).global_position.distance_to(d.global_position) < 2.2:
			return false
	if d.has_method("_friend_in_front") and d.call("_friend_in_front", 1.9) != null:
		return false
	var fc: Node = mtn.get("face")
	if fc and Vector3(fc.get("rack_pos")).distance_to(d.global_position) < 2.6:
		return false
	if fc and int(fc.call("_start_cell", d.global_position)) >= 0:
		return false                     # у самой стены E — лезть, а не лепить
	return true


## Леплю снежок (сценарий 41): 0.95 с — поза 30, потом снежок в правой руке
func drive(d: Node3D, kind: int, t: float, data: Dictionary, _delta: float) -> void:
	if kind != 41:
		d.snow.end_scripted()
		return
	d.velocity = Vector3(0.0, d.velocity.y, 0.0)
	var k := clampf(t / SCOOP_T, 0.0, 1.0)
	d.snow.set_mpose(30, k)
	if k > 0.3 and not bool(data.get("snd", false)):
		data["snd"] = true
		SFX.play(self, d.global_position, "crunch", -8.0, 1.6)
	if k >= 0.72 and not has_ball.has(int(d.peer_id)):
		_ball_all(int(d.peer_id), true)
	if k >= 1.0:
		d.snow.end_scripted()
		d.snow.set_mpose(0)
		if d == Network.local_player:
			mtn.say("Снежок готов! Q — бросить")


func ladder_down(_o) -> bool:
	return true


func _ball_all(pid: int, on: bool) -> void:
	if mtn._online():
		_ball.rpc(pid, on)
	else:
		_ball(pid, on)


## Снежок в правой руке (у всех)
@rpc("any_peer", "call_local", "reliable")
func _ball(pid: int, on: bool) -> void:
	var old: Node3D = has_ball.get(pid)
	if old and is_instance_valid(old):
		old.queue_free()
	has_ball.erase(pid)
	if not on:
		return
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or d.get("suit") == null or not d.suit.has_method("attach_to_hand"):
		return
	var n := MeshInstance3D.new()
	n.mesh = _ball_mesh()
	n.material_override = _ball_mat()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.add_child(n)
	n.position = Vector3(0.0, -0.04, 0.0)
	d.suit.attach_to_hand(1, holder)
	has_ball[pid] = holder


var _bmesh: Mesh
var _bmat: Material
func _ball_mesh() -> Mesh:
	if _bmesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.085
		sm.height = 0.16
		sm.radial_segments = 12
		sm.rings = 6
		_bmesh = sm
	return _bmesh


## Снег — фототекстура Snow 005 (комковатый), чуть светится, чтобы было видно ночью
func _ball_mat() -> Material:
	if _bmat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.97, 1.0)
		if ResourceLoader.exists(PK + "tex/snow_color.jpg"):
			m.albedo_texture = load(PK + "tex/snow_color.jpg")
			m.normal_enabled = true
			m.normal_texture = load(PK + "tex/snow_normal.png")
			m.normal_scale = 1.5
			m.uv1_scale = Vector3(0.6, 0.6, 0.6)
		m.roughness = 0.85
		m.emission_enabled = true
		m.emission = Color(0.06, 0.07, 0.09)
		_bmat = m
	return _bmat


func hint(me: Node3D) -> String:
	var p := me.global_position
	if phase != 1 or not _near_shoulder(p):
		return ""
	if has_ball.has(int(me.peer_id)):
		return "Снежок в руке — Q: бросить (целься камерой)"
	if M.on_road(p, 1.0):
		var rn := M.road_near(p.x, p.z, 6.0)
		if M.ice_at(p.x, p.z):
			return "ЛЁД! Не удержаться — качусь вниз"
		if rn.x != INF and M.road_icy(rn.z + 6.0):
			return "Впереди лёд (блестит голубым) — обходи сбоку, наступишь — укатишься вниз"
		if lamp_off.has(int(me.peer_id)):
			return "Фонарь погас — T. Иди по вешкам с огоньками"
		return "Ночная дорога к стене: %d м · фонарь — T · E — слепить снежок · R — сорвать фонарь другу" % int(maxf(M.road_len() - rn.z, 0.0))
	if M.on_shoulder(p) and lamp_off.has(int(me.peer_id)):
		return "Темно! Фонарь — T. Дорога к стене — на север, по вешкам"
	return ""


# --- бот: идёт по дороге за хозяином ---
func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	var b := bot.global_position
	var o := owner_node.global_position
	if not _near_shoulder(o):
		return Vector3.INF
	var rb := M.road_near(b.x, b.z, 12.0)
	var ro := M.road_near(o.x, o.z, 12.0)
	var sb := 0.0 if M.on_shoulder(b) else (rb.z if rb.x != INF else -1.0)
	var so := 0.0 if M.on_shoulder(o) else (ro.z if ro.x != INF else -1.0)
	if M.on_foot(o) or o.y > M.FOOT_Y + 2.0 and o.z < M.FOOT_ZS:
		so = M.road_len() + 5.0
	if sb < 0.0 or so < 0.0:
		return Vector3.INF
	if so > sb + 5.0:
		if sb > M.road_len() - 3.0:
			return Vector3.INF
		return _lane(minf(sb + 6.0, M.road_len()))
	if so < sb - 8.0:
		return _lane(maxf(sb - 6.0, 0.0))
	return Vector3.INF


## Шаг 121: точка дороги на длине s — сбоку от льда (бот обходит пятна)
func _lane(s: float) -> Vector3:
	var c := M.road_at(s)
	var d := M.road_dir(s)
	var lat := Vector3(-d.z, 0.0, d.x).normalized()
	return c + lat * M.safe_lat(s)


func bot_crank(_bot: Node3D, _owner_node: Node3D) -> bool:
	return false
