extends Node3D
## Лавинная долина (шаг 56). План — avalanche_layout.gd, одна лавина — avalanche_flow.gd.
##
##  * Тихий участок (s < 330): «напряжение снега» растёт от шума — бег, прыжки, удары, драка
##    с роботами. Обычный и тихий шаг не тревожат снег. Дошло до предела — со склона сбоку,
##    прямо над самым шумным дроном, срывается лавина: от неё не убежать.
##  * Середина пути (s = 330): с перевала за спиной сходит большая лавина — в любом случае.
##    Её скорость подстраивает хост: фронт держится в ~12 м за последним бегущим (но не медленнее
##    7 м/с — быстрее шага). Бежишь без остановки — успеваешь впритык; встал — накрыло.
##    У скального гребня (s ≈ 668) она выдыхается.
##  * После лавины остаётся толстый слой рыхлого снега (snow_layer.gd) — до конца забега.
##  * Кого накрыло — несёт десятки метров и заваливает: торчит из сугроба с маячком,
##    пока друг не откопает (snow_state.gd). Завалило всех — через 20 с все у входа в долину.
##  * Снежные роботы-воришки (snow_robot.gd) — в гнёздах вдоль тихого участка.
##
## По сети: напряжение и запуск лавин решает хост (RPC с зерном — у всех одинаковая лавина),
## попадание по своим дронам каждый проверяет у себя.
##
## Шаг 62:
##  * Тихий участок очень чуткий: один рывок бегом, прыжок, удар или бросок — и склон срывается.
##    Обычный и тихий шаг по-прежнему безопасны.
##  * Укрытия — ниши в скалах у подножия склонов, ровно на одного дрона: внутри лавина не берёт.
##    Кто глубже — тот и в укрытии, второго выталкивает наружу.
##  * Перед головой лавины — стена снежной пыли с ударным ветром (толкает, белеет экран), нарастающий
##    гул и тряска ещё до срыва; со склонов вокруг сыплются струйки снега.
##  * Всё, чем рисуется лавина, прогревается при загрузке уровня — первая лавина больше не подвисает.
##
## Шаг 137:
##  * Лавины сходят с дальних высоких гор (рельеф за склонами — до ~250 м): белое облако на склоне и далёкий
##    раскат — единственное предупреждение (ни надписи, ни тряски). До удара ~12 с: заметил сразу — добежишь
##    до капсулы (их пять, каждые ~175 м), замешкался — нет. Большая лавина с s = 330 — тоже дальняя, повторяется.
##  * Ниши-пещеры и стена с тоннелем убраны. Воздух в долине прозрачнее (туман реже).
##  * Облако — фото-флипбуки (Unity Labs, CC0), вал и снег — фото-текстуры (ambientCG), звук — freesound (CC0).
##  * После лавины — снег по пояс: вязнешь, бежать нельзя, за тобой остаётся траншея; по траншее идти легче.
##  * Завалило у края потока — откапываешься сам (ЛКМ/ПКМ по очереди), посередине — только друг.

const W := preload("res://scenes/world/avalanche_layout.gd")
const FLOW := preload("res://scenes/world/avalanche_flow.gd")
const ROBOT := preload("res://scenes/world/snow_robot.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")
const CHUNK := preload("res://scenes/player/ice_chunk.gd")

const NOISE_FLOOR := 0.38          ## шум ниже этого (шаг, тихий шаг) снег не тревожит
const GAIN := 2.2                  ## как быстро шум раскачивает снег (бег: ~0.7 с — и срыв)
const SPIKE := 0.42                ## резкий звук (прыжок, удар, бросок) — сразу срыв
const DECAY := 0.05
const SIDE_COOLDOWN := 40.0       ## после срыва сбоку — 40 с тишины (шаг 66)
const DISCHARGE := 75.0            ## склон там, где сорвалось, «разряжен»: в ±75 м по долине больше не срывается
const GRACE := 3.0                 ## откопали / вылез из капсулы / ожил — 3 с шум не считается
const ALL_BURIED_TIME := 20.0
const NICHES := []                ## шаг 137: ниши-пещеры убраны — укрытия только капсулы
const ROBOTS_BASE := 8             ## роботов на одного игрока
const ROBOTS_PER := 5              ## +за каждого следующего
const ROBOTS_MAX := 23

## Капсулы-убежища: (s, сбоку от тропы, м)
## Шаг 65: всего три — далеко друг от друга (~200 м): спасётся тот, кто добежит
## Шаг 67: зона погони длиннее — капсул четыре (в зоне — три, ~175 м друг от друга)
## шаг 137: капсулы — каждые ~175 м, по очереди у разных склонов: до ближайшей бывает и 90 м — заметил лавину
## сразу (до удара ~13 с), добежишь; замешкался — нет
const CAPSULES := [[80.0, 16.0], [255.0, -16.0], [430.0, 16.0], [605.0, -16.0], [780.0, 16.0]]
const FAR_REPEAT := 35.0           ## шаг 137: после большой лавины — через столько секунд следующая (если в зоне кто-то есть)
const SNOW_LAYER := preload("res://scenes/world/snow_layer.gd")
const BRIDGE := preload("res://scenes/world/drawbridge.gd")
const BOULDERS := preload("res://scenes/world/boulder_spawner.gd")
const CARRY_CHASE := Vector2(30.0, 60.0)   ## шаг 67: большая лавина уносит недалеко (не подвозит) и заваливает
const ROLL_EVERY := Vector2(1.4, 2.8)      ## шаг 67: глыбы со склонов во время погони — как часто
const ROLL_MAX := 12
const ROLL_LIFE := 14.0
const ROLL_SPEED := 17.0                   ## шаг 68: глыбы быстрые
const ROLL_VMAX := 20.0
const ROLL_ACCEL := 14.0
const CHASE_GAP := 7.0             ## (до шага 66) на сколько метров голова держалась за последним бегущим
const CHASE_MIN := 12.5            ## шаг 66: быстрее бега по снегу — убежать нельзя, спасает только капсула
const CHASE_MAX := 20.0
const CHASE_GAIN := 4.0            ## на столько м/с быстрее самого отстающего бегущего — догоняет всегда
const CHASE_FIRST_S := 255.0       ## откуда сходит первая волна (близко — до первой капсулы добежать можно, дальше нет)
const CHASE_REPEAT := 15.0         ## волна встала — через столько секунд следующая, если в зоне кто-то есть
const CHASE_BEHIND := 110.0        ## следующая волна срывается за столько метров позади самого отстающего

var tension := 0.0
var bridge: Node3D                 ## шаг 67: подъёмный мост через разлом
var _rolls: Array = []             ## [RigidBody3D, возраст, радиус, перезарядка удара]
var _roll_t := 2.0
var _roll_meshes := {}
var _roll_mat: StandardMaterial3D
var _env: Environment              ## шаг 68: в тоннеле гасим рассеянный свет
var _amb0 := 1.0
var _fogl0 := 1.0
var _dark_k := 0.0
var _dark_set := false
var flows: Array = []
var chase_armed := true
var chase_count := 0
var side_count := 0

var _side_cd := 0.0
var _chase_flow: Node3D = null
var _carry := {}                   ## peer_id → [откуда понесло, сколько нести, лавина]
var _all_buried_t := 0.0
var _air := {}                     ## peer_id → сколько в воздухе (приземление после прыжка тревожит снег)
const LAND_KICK := 1.0
var _sync_t := 0.0
var _time := 0.0
var _seed := 0
var _player: Node3D
var layer: Node3D                  ## snow_layer.gd — слой снега после лавин
var _pspeed := {}                  ## peer_id → сглаженная скорость вниз по долине
var _ps_prev := {}
var _chase_sync := 0.0
var _warn_t := 0.0
var _thump := 0.0
var _robot_t := 0.0
var _burst_prev := {}              ## peer_id → прошлый «всплеск» шума (ловлю резкие звуки)
var _discharged: Array[float] = [] ## z мест, где склон уже сорвался (там больше не срывается)
var _grace := {}                   ## peer_id → сколько ещё не слушать его шум
var _was_busy := {}
var niches: Array = []             ## укрытия: [Transform3D у входа (+Z — наружу)]
var capsules: Array = []           ## капсулы-убежища: [Transform3D (+Z — к люку), петля люка, RID опоры, материал мигалки]
var _shelter_lbl: Label
var _shelter_msg := ""
var _shelter_t := 0.0
var _prewarmed := false

var _hud: CanvasLayer
var _hud_box: Control
var _bar: ProgressBar
var _warn: Label
var _white: ColorRect
var _audio: AudioStreamPlayer
var _snd_roar: AudioStreamPlayer
var _snd_wind: AudioStreamPlayer
var _rumble_stream: AudioStream
var _gen: AudioStreamGeneratorPlayback
var _lp1 := 0.0
var _lp2 := 0.0
var _rumble := 0.0
var _throb := 0.0
var _lk := 0.0                     ## стук комьев по корпусу капсулы (звук)
var _kenv := 0.0
var _knock_t := 0.0
var _ter: Node


func _ready() -> void:
	add_to_group("avalanche_valley")
	_ter = get_tree().get_first_node_in_group("terrain")
	layer = Node3D.new()
	layer.set_script(SNOW_LAYER)
	layer.name = "SnowLayer"
	add_child(layer)
	_build_hud()
	_build_audio()
	_decor.call_deferred()
	layer.prefill.call_deferred()        # шаг 138: старый снег по всей долине (после капсул — у них не насыпаю)
	_prewarm.call_deferred()


# ---------------------------------------------------------------------------
#  Для других
# ---------------------------------------------------------------------------

func add_tension(v: float) -> void:
	if multiplayer.is_server():
		tension = minf(tension + v, 1.2)


func s_of(p: Vector3) -> float:
	return W.s_of(p.z)


func _in_valley(p: Vector3) -> bool:
	return W.inside(p, 5.0)


func _online() -> bool:
	return Network.in_game and Network.is_online()


func _bcast(method: String, args: Array) -> void:
	if _online():
		callv("rpc", [method] + args)
	else:
		callv(method, args)


# ---------------------------------------------------------------------------
#  Каждый кадр
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	_player = Network.local_player
	if multiplayer.is_server():
		_server(delta)
	_local_hits(delta)
	_robot_t -= delta
	if _robot_t <= 0.0:
		_robot_t = 1.0
		_update_robot_count()
	_capsule_input()
	_update_capsules(delta)
	_update_rolls(delta)
	_update_tunnel_dark(delta)
	var keep: Array = []
	for f in flows:
		if not is_instance_valid(f):
			continue
		if f.done:
			f.queue_free()
			continue
		keep.append(f)
	flows = keep
	_update_hud(delta)


func _players_alive() -> Array:
	var out := []
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_dead:
			out.append(d)
	return out


func _server(delta: float) -> void:
	_side_cd -= delta
	# 1) шум на тихом участке
	var loud: Node3D = null
	var loud_n := 0.0
	for d in _players_alive():
		var p: Vector3 = d.global_position
		var s := s_of(p)
		var pid0 := int(d.peer_id)
		var busy_now: bool = d.snow.busy()
		if bool(_was_busy.get(pid0, false)) and not busy_now:
			_grace[pid0] = GRACE           # только что откопали / вылез — встаёт, отряхивается: это не шум
		_was_busy[pid0] = busy_now
		_grace[pid0] = maxf(float(_grace.get(pid0, 0.0)) - delta, 0.0)
		if s < 8.0 or s > W.QUIET_END or not _in_valley(p) or busy_now:
			continue
		if float(_grace[pid0]) > 0.0 or _side_cd > 0.0 or _is_discharged(p.z):
			_burst_prev[pid0] = float(d.get("_noise_burst"))
			_air[pid0] = 0.0
			continue
		var n: float = d.get_noise()
		tension += maxf(n - NOISE_FLOOR, 0.0) * GAIN * delta
		var pid := int(d.peer_id)
		# резкий звук (прыжок, удар, взмах дубинкой, бросок) — снег срывается сразу
		var b: float = float(d.get("_noise_burst"))
		if b - float(_burst_prev.get(pid, 0.0)) > SPIKE:
			tension += 1.1
			n = maxf(n, 1.0)
		_burst_prev[pid] = b
		# прыжки: каждое приземление — толчок по снегу
		var air: float = _air.get(pid, 0.0)
		if d.is_grounded():
			if air > 0.6:
				tension += LAND_KICK
				n = maxf(n, 0.9)
			_air[pid] = 0.0
		else:
			_air[pid] = air + delta
		if n > loud_n:
			loud_n = n
			loud = d
	tension = maxf(tension - DECAY * delta, 0.0)
	if tension >= 1.0 and _side_cd <= 0.0:
		var who: Node3D = loud
		if who == null:
			for d in _players_alive():
				var s2 := s_of(d.global_position)
				if s2 > 8.0 and s2 < W.QUIET_END:
					who = d
					break
		if who != null:
			var wp := who.global_position
			var s3 := s_of(wp)
			var side := 1.0 if wp.x > W.center_x(s3) else -1.0
			_seed += 1
			var zc: float = wp.z + who.velocity.z * 1.5
			_discharged.append(zc)
			_bcast("_start_side", [zc, side, _seed + int(Time.get_ticks_msec() % 1000) * 7, true, false])
		tension = 0.0
		_side_cd = SIDE_COOLDOWN
	if _side_cd > 0.0:
		tension = 0.0
	# 2) большая лавина в середине пути
	_chase_control(delta)
	_roll_server(delta)
	if chase_armed:
		for d in _players_alive():
			var s4 := s_of(d.global_position)
			if s4 >= W.TRIGGER_S and s4 < W.SAFE_S and _in_valley(d.global_position):
				chase_armed = false
				_seed += 1
				# шаг 137: большая лавина — тоже с дальнего склона, впереди по ходу
				var zf := W.z_of(minf(s4 + 60.0, W.SAFE_S - 40.0))
				_bcast("_start_side", [zf, 1.0 if randf() < 0.5 else -1.0, _seed * 31 + 5, true, true])
				break
	elif _chase_flow != null and is_instance_valid(_chase_flow) and _chase_flow.stopped \
			and _chase_flow._age_after > FAR_REPEAT and _zone_rear() < INF:
		# шаг 137: лавина сошла, а в зоне ещё кто-то есть — следующая, снова с дальнего склона, над кем-то из идущих
		_seed += 1
		var cand: Array = []
		for d in _players_alive():
			var sc := s_of(d.global_position)
			if sc >= W.TRIGGER_S - 25.0 and sc < W.SAFE_S - 2.0 and _in_valley(d.global_position) and not d.snow.busy():
				cand.append(sc)
		if not cand.is_empty():
			var sp0: float = cand.pick_random()
			_bcast("_start_side", [W.z_of(clampf(sp0 + 70.0, W.TRIGGER_S, W.SAFE_S - 40.0)), 1.0 if randf() < 0.5 else -1.0, _seed * 31 + 5, true, true])
	elif _chase_flow == null or not is_instance_valid(_chase_flow) or (_chase_flow.stopped and _chase_flow._age_after > 15.0):
		# снова зарядить, когда кто-то опять идёт по долине сначала, а в середине никого
		var someone_back := false
		var someone_mid := false
		for d in _players_alive():
			var s5 := s_of(d.global_position)
			if s5 < W.TRIGGER_S - 30.0 and s5 > -40.0:
				someone_back = true
			elif s5 >= W.TRIGGER_S - 30.0 and s5 < W.SAFE_S and _in_valley(d.global_position):
				someone_mid = true
		if someone_back and not someone_mid:
			chase_armed = true
			_bcast("_clear_layer", [])
	# все прошли долину — слой снега больше не нужен
	if layer.any_snow:
		var all_past := true
		for d in _players_alive():
			if s_of(d.global_position) < W.LENGTH + 5.0:
				all_past = false
		if all_past and not _players_alive().is_empty():
			_bcast("_clear_layer", [])
	# 3) лавины сбивают роботов и уносят посылки
	for f in flows:
		if not is_instance_valid(f) or f.t < 0.0:
			continue
		for r in get_tree().get_nodes_in_group("snow_robot"):
			if r.alive() and f.hit_test(r.global_position)[0]:
				r.request_hit(f.flow_dir * 12.0 + Vector3.UP * 5.0, 0, 9)
		for node in get_tree().get_nodes_in_group("parcel"):
			var parcel := node as Parcel
			if parcel == null or parcel.is_held:
				continue
			var hit: Array = f.hit_test(parcel.global_position)
			if hit[0]:
				var v: Vector3 = hit[1]
				parcel.linear_velocity = parcel.linear_velocity.lerp(v * 0.8 + Vector3.UP * 2.0, 0.2)
	# 4) завалило всех
	var alive := _players_alive()
	var all_busy := not alive.is_empty()
	for d in alive:
		if not d.snow.buried:
			all_busy = false
	_all_buried_t = _all_buried_t + delta if all_busy else 0.0
	if _all_buried_t > ALL_BURIED_TIME:
		_all_buried_t = 0.0
		var at := W.path_point(-35.0)
		var k := 0
		for d in alive:
			var q := at + Vector3((k % 3 - 1) * 2.0, 0.0, -float(k / 3) * 2.0)
			q.y = (_ter.height_at(q.x, q.z) if _ter else q.y) + 0.6
			d.snow.rescue_respawn(q)
			k += 1
		get_tree().call_group("level", "show_banner", "Всех завалило…", "Выбрались к «Передышке» перед долиной. Идите тише!")
	# напряжение — всем
	_sync_t -= delta
	if _sync_t <= 0.0 and _online():
		_sync_t = 0.2
		_sync_tension.rpc(tension)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_tension(v: float) -> void:
	tension = v


@rpc("authority", "call_local", "reliable")
func _clear_layer() -> void:
	layer.clear()
	_discharged.clear()                # новый забег — склоны снова заряжены


func _is_discharged(z: float) -> bool:
	for dz in _discharged:
		if absf(z - dz) < DISCHARGE:
			return true
	return false


## Хост: большая лавина держится в CHASE_GAP м за последним бегущим
func _chase_control(delta: float) -> void:
	# сглаженные скорости дронов вдоль долины (окно ~6 с: средний темп, рывки и шаг вперемешку)
	for d in _players_alive():
		var pid := int(d.peer_id)
		var sp := s_of(d.global_position)
		var prev: float = _ps_prev.get(pid, sp)
		var v := clampf((sp - prev) / maxf(delta, 0.001), -5.0, 20.0)
		_ps_prev[pid] = sp
		_pspeed[pid] = lerpf(float(_pspeed.get(pid, 0.0)), v, clampf(delta / 6.0, 0.0, 1.0))
	var f := _chase_flow
	if f == null or not is_instance_valid(f) or f.stopped or f.t < 0.0 or f.kind != FLOW.K.CHASE:
		return
	var rear := INF
	var rear_v := 0.0
	for d in _players_alive():
		if d.snow.busy() or niche_at(d.global_position) >= 0 or capsule_at(d.global_position) >= 0:
			continue
		var sp2 := s_of(d.global_position)
		if sp2 < f.s_front - 3.0 or sp2 > W.SAFE_S or not _in_valley(d.global_position):
			continue
		if sp2 < rear:
			rear = sp2
			rear_v = _pspeed.get(int(d.peer_id), 0.0)
	var want := 14.0
	if rear < INF:
		# всегда догоняет: быстрее отстающего на CHASE_GAIN; далеко отстала — разгоняется до максимума
		want = clampf(maxf(rear_v + CHASE_GAIN, CHASE_MIN), CHASE_MIN, CHASE_MAX)
		if rear - (f.s_front + 10.0) > 90.0:
			want = CHASE_MAX
	f.ext_speed = want
	_chase_sync -= delta
	if _chase_sync <= 0.0 and _online():
		_chase_sync = 0.1
		_sync_chase.rpc(f.s_front, f.speed)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_chase(sf: float, sp: float) -> void:
	if _chase_flow and is_instance_valid(_chase_flow):
		_chase_flow.net_s = sf
		_chase_flow.ext_speed = sp


@rpc("authority", "call_local", "reliable")
func _start_side(z: float, side: float, seed: int, far := false, big := false) -> void:
	var f := Node3D.new()
	f.set_script(FLOW)
	f.setup_side(z, side, seed, far)
	add_child(f)
	flows.append(f)
	side_count += 1
	tension = 0.0
	if big:
		_chase_flow = f
		chase_count += 1
	if far:
		# шаг 137: далёкий срыв — ни надписи, ни тряски: только далёкий гул и белое облако на склоне.
		# Заметил — беги к капсуле; не заметил — поздно
		_far_sound(f)
	else:
		_alarm()


## Шаг 67/68: пока идёт большая лавина — со склонов скатываются глыбы (впереди бегущих, наперерез).
## Шаг 68: быстрые (до ~20 м/с) и прыгучие — подскакивают на кочках, при ударе о снег — всплеск.
func _roll_server(delta: float) -> void:
	var f := _chase_flow
	if f == null or not is_instance_valid(f) or f.t < 0.0 or f.stopped or f.kind != FLOW.K.CHASE:
		_roll_t = minf(_roll_t, 1.5)
		return
	_roll_t -= delta
	if _roll_t > 0.0 or _rolls.size() >= ROLL_MAX:
		return
	_roll_t = randf_range(ROLL_EVERY.x, ROLL_EVERY.y)
	var cand: Array = []
	for d in _players_alive():
		var sp := s_of(d.global_position)
		if not d.snow.busy() and sp > W.TRIGGER_S - 10.0 and sp < W.RIFT_S - W.RIFT_HW and _in_valley(d.global_position):
			cand.append(d)
	if cand.is_empty():
		return
	var who: Node3D = cand.pick_random()
	var ws := s_of(who.global_position)
	# куда метим: туда, где бегущий будет через пару секунд (± разброс)
	var st := minf(ws + randf_range(14.0, 34.0), W.RIFT_S - W.RIFT_HW - 4.0)
	var lt := who.global_position.x - W.center_x(ws) + randf_range(-14.0, 14.0)
	var tgt := Vector3(W.center_x(st) + lt, 0.0, W.z_of(st))
	var side := 1.0 if randf() < 0.5 else -1.0
	var r := randf_range(0.8, 1.4)
	# старт — выше по склону, чуть позади точки прицела (пока скатится, бегущий подбежит)
	var sb := maxf(st - randf_range(4.0, 14.0), W.TRIGGER_S - 20.0)
	var x := W.center_x(sb) + side * (W.half_w(sb) + randf_range(26.0, 40.0))
	var z := W.z_of(sb)
	var pos := Vector3(x, _gy(x, z) + r + 0.5, z)
	var hd := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z).normalized()
	var vel := hd * randf_range(9.0, 12.0) + Vector3.DOWN * 3.0
	_bcast("_spawn_roll", [pos, vel, r, randi() % 1000])


@rpc("authority", "call_local", "reliable")
func _spawn_roll(pos: Vector3, vel: Vector3, r: float, sd: int) -> void:
	if _roll_mat == null:
		_roll_mat = StandardMaterial3D.new()
		_roll_mat.albedo_color = Color(0.62, 0.74, 0.88)
		_roll_mat.roughness = 0.35
		_roll_mat.metallic_specular = 0.7
	var key := snappedf(r, 0.2)
	if not _roll_meshes.has(key):
		var m: ArrayMesh = BOULDERS._make_rock_mesh(key)
		m.surface_set_material(0, _roll_mat)
		_roll_meshes[key] = m
	var b := RigidBody3D.new()
	b.mass = 150.0
	b.continuous_cd = true
	b.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	b.linear_damp = 0.0
	b.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	b.angular_damp = 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.45
	b.physics_material_override = pm
	var mi := MeshInstance3D.new()
	mi.mesh = _roll_meshes[key]
	mi.scale = Vector3.ONE * (r / key)
	mi.rotation = Vector3(float(sd % 7), float(sd % 11), 0.0)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = r
	cs.shape = sp
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	b.linear_velocity = vel
	var hd := Vector3(vel.x, 0.0, vel.z).normalized()
	# катится вперёд: ось вращения — поперёк движения
	b.angular_velocity = Vector3.UP.cross(hd) * (vel.length() / r)
	# [тело, возраст, радиус, перезарядка удара, направление, прошлая vy, перезарядка подскока]
	_rolls.append([b, 0.0, r, 0.0, hd, 0.0, 0.0])


func _update_rolls(delta: float) -> void:
	if _rolls.is_empty():
		return
	var keep: Array = []
	for e in _rolls:
		var b := e[0] as RigidBody3D
		e[1] = float(e[1]) + delta
		e[3] = float(e[3]) - delta
		e[6] = float(e[6]) - delta
		if not is_instance_valid(b):
			continue
		if float(e[1]) > ROLL_LIFE or b.global_position.y < W.floor_y(s_of(b.global_position)) - 30.0:
			b.queue_free()
			continue
		keep.append(e)
		var r: float = e[2]
		var v := b.linear_velocity
		var hd: Vector3 = e[4]
		# не вязнет в снегу: тянет по своему направлению до ~17 м/с (первые 9 с), быстрее 20 — не разгоняется
		var along := Vector3(v.x, 0.0, v.z).dot(hd)
		if float(e[1]) < 9.0 and along < ROLL_SPEED:
			b.linear_velocity += hd * minf(ROLL_ACCEL * delta, ROLL_SPEED - along)
		var hv := Vector3(v.x, 0.0, v.z)
		if hv.length() > ROLL_VMAX:
			b.linear_velocity = hv.normalized() * ROLL_VMAX + Vector3.UP * v.y
		# удар о снег: был быстро вниз — стал вверх; всплеск и подскок
		var pvy: float = e[5]
		if pvy < -3.0 and b.linear_velocity.y > pvy + 3.0:
			_snow_splash(b.global_position + Vector3.DOWN * r * 0.8, clampf(-pvy / 8.0, 0.4, 1.3))
		var gy := _gy(b.global_position.x, b.global_position.z)
		var on_ground := b.global_position.y - gy < r + 0.25
		if on_ground and float(e[6]) <= 0.0 and hv.length() > 6.0 and absf(b.linear_velocity.y) < 2.0:
			# кочка — подбрасывает
			e[6] = randf_range(0.45, 1.1)
			b.linear_velocity.y = randf_range(3.0, 5.5)
			_snow_splash(b.global_position + Vector3.DOWN * r * 0.8, 0.6)
		e[5] = b.linear_velocity.y
		var speed := b.linear_velocity.length()
		if speed < 2.5 or float(e[3]) > 0.0:
			continue
		for d in get_tree().get_nodes_in_group("player"):
			if not d.is_local or d.is_dead or d.snow.busy():
				continue
			var to: Vector3 = (d as Node3D).global_position + Vector3.UP * 0.9 - b.global_position
			if to.length() > r * 1.15 + 0.6:
				continue
			e[3] = 1.0
			var push := Vector3(to.x, 0.0, to.z).normalized()
			d.receive_hit(push + hd * 0.6, clampf(speed, 8.0, 14.0), b.global_position + to * 0.5)
	_rolls = keep


static var _splash_mat: StandardMaterial3D
static var _splash_mesh: QuadMesh
static var _splash_curve: Curve
static var _splash_ramp: Gradient

## Снежный всплеск: круглые мягкие хлопья (не квадраты), разлетаются и тают
func _snow_splash(at: Vector3, power: float) -> void:
	if _splash_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_splash_mat = StandardMaterial3D.new()
		_splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_splash_mat.albedo_texture = tex
		_splash_mat.albedo_color = Color(0.96, 0.98, 1.0, 0.85)
		_splash_mat.vertex_color_use_as_albedo = true
		_splash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_splash_mesh = QuadMesh.new()
		_splash_mesh.size = Vector2(1.0, 1.0)
		_splash_mesh.material = _splash_mat
		_splash_curve = Curve.new()
		_splash_curve.add_point(Vector2(0.0, 0.5))
		_splash_curve.add_point(Vector2(0.3, 1.0))
		_splash_curve.add_point(Vector2(1.0, 1.3))
		_splash_ramp = Gradient.new()
		_splash_ramp.set_color(0, Color(1, 1, 1, 0.9))
		_splash_ramp.set_color(1, Color(1, 1, 1, 0.0))
	var p := CPUParticles3D.new()
	p.mesh = _splash_mesh
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = int(10 + 10 * power)
	p.lifetime = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5 * power
	p.initial_velocity_max = 5.0 * power
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.5 * power + 0.3
	p.scale_amount_max = 1.1 * power + 0.5
	p.scale_amount_curve = _splash_curve
	p.color_ramp = _splash_ramp
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Самый отстающий в зоне большой лавины (s), INF — никого
func _zone_rear() -> float:
	var rear := INF
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead:
			continue
		var p: Vector3 = (d as Node3D).global_position
		var s := s_of(p)
		if s >= W.TRIGGER_S - 25.0 and s < W.SAFE_S - 2.0 and _in_valley(p):
			rear = minf(rear, s)
	return rear


@rpc("authority", "call_local", "reliable")
func _start_chase(seed: int, from_s := 215.0) -> void:
	var f := Node3D.new()
	f.set_script(FLOW)
	f.setup_chase(seed, from_s)
	add_child(f)
	flows.append(f)
	_chase_flow = f
	chase_armed = false
	chase_count += 1
	tension = 0.0
	_alarm()


## Срыв: глухой удар («вумф»), толчок, надпись — один раз на полторы секунды
func _alarm() -> void:
	_thump = 1.0
	if _player and is_instance_valid(_player) and _in_valley(_player.global_position):
		_warn_t = 1.6
		if not bool(_player.get("fp_view")):
			_player.add_shake(0.18)


## Свои дроны (и боты на хосте): накрыло ли, несёт, завалило
## Шаг 67: сорвался в разлом — выбирается на этот берег (у моста)
func _rift_fall(d: Node3D) -> bool:
	var s := s_of(d.global_position)
	if absf(s - W.RIFT_S) > W.RIFT_HW + 1.0:
		return false
	if d.global_position.y > W.floor_y(s) - 6.0 or not _in_valley(d.global_position):
		return false
	if d.snow.busy():
		d.snow.reset()
	var at := W.path_point(W.RIFT_S - W.RIFT_HW - 7.0) + Vector3(randf_range(-3.0, 3.0), 0.0, 0.0)
	at.y = _gy(at.x, at.z) + 0.8
	d.teleport_to(at)
	d.velocity = Vector3.ZERO
	if d == _player:
		get_tree().call_group("level", "show_banner", "Сорвался в разлом!",
			"Мост опускает лебёдка: один держит E и крутит, остальные бегут по мосту")
	return true


func _local_hits(_delta: float) -> void:
	# оторванные детали (у каждого своя физика) — поток уносит
	for f in flows:
		if not is_instance_valid(f) or f.t < 0.0 or f.stopped:
			continue
		for pt in get_tree().get_nodes_in_group("limb_part"):
			if pt.holder != null and is_instance_valid(pt.holder):
				continue
			var hp: Array = f.hit_test((pt as Node3D).global_position)
			if hp[0]:
				var rb := pt as RigidBody3D
				rb.linear_velocity = rb.linear_velocity.lerp((hp[1] as Vector3) * 0.9 + Vector3.UP * 3.0, 0.25)
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_local or d.is_dead or d.get("snow") == null:
			continue
		var sn: Node = d.snow
		var key := int(d.peer_id)
		if _rift_fall(d):
			_carry.erase(key)
			continue
		if sn.buried:
			_carry.erase(key)
			continue
		if int(sn.get("capsule")) >= 0:
			continue                       # в капсуле — лавина не достанет
		if sn.swept:
			var info: Array = _carry.get(key, [])
			if info.is_empty():
				continue
			var f: Node3D = info[2]
			var from: Vector3 = info[0]
			var went := Vector2(d.global_position.x - from.x, d.global_position.z - from.z).length()
			if not is_instance_valid(f) or f.stopped or went > float(info[1]):
				# шаг 137: у края потока заваливает по грудь (откопаешься сам), посередине — с головой (только друг)
				sn.bury(is_instance_valid(f) and f.edge_k(d.global_position) > 0.5)
				_carry.erase(key)
				continue
			var hit: Array = f.hit_test(d.global_position)
			var fv: Vector3 = hit[1] if hit[0] else f.flow_dir * maxf(f.speed, 6.0)
			# еду на спине по валу: держусь ~9 м позади фронта (впереди — круче, сзади — тоньше слой)
			var bh: float = f.behind_front(d.global_position)
			fv *= clampf(1.0 + (bh - 9.5) * 0.08, 0.75, 1.3)
			sn.flow(fv, f.surface_at(d.global_position))
			continue
		# укрытие: кто глубже в нише — тот в безопасности, второго выталкивает
		var ni := niche_at(d.global_position)
		if ni >= 0:
			if _shelter_owner(ni, d):
				if d == _player:
					_shelter_say("В укрытии — лавина пройдёт над тобой")
				continue
			var out: Vector3 = (niches[ni] as Transform3D).basis.z
			d.velocity.x = out.x * 5.0
			d.velocity.z = out.z * 5.0
			if d == _player:
				_shelter_say("Занято! В укрытии место только на одного")
		for f2 in flows:
			if not is_instance_valid(f2):
				continue
			# стена пыли впереди головы: ударный ветер толкает, трясёт
			var ck: float = f2.cloud_test(d.global_position)
			if ck > 0.0:
				# порывы швыряют вбок, сбивают с шага (вперёд не толкают — убежать не помогают)
				var sv := Vector3(f2.flow_dir.z, 0.0, -f2.flow_dir.x)
				var gust := sin(_time * 7.3 + float(key)) * (0.6 + 0.4 * sin(_time * 2.1))
				d.apply_wind(sv * gust * 7.0 * ck)
				if not bool(d.get("fp_view")):
					d.add_shake(0.015 + 0.03 * ck)
			var h2: Array = f2.hit_test(d.global_position)
			if h2[0]:
				# уносит далеко: друзьям придётся бежать искать по маячку
				var far := randf_range(CARRY_CHASE.x, CARRY_CHASE.y) if f2.kind == FLOW.K.CHASE or f2.far else randf_range(150.0, 220.0)
				_carry[key] = [d.global_position, far, f2]
				sn.sweep(h2[1])
				break


# ---------------------------------------------------------------------------
#  Интерфейс, тряска, гул
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 3
	add_child(_hud)
	_white = ColorRect.new()
	_white.color = Color(0.93, 0.96, 1.0, 0.0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_white)
	var box := VBoxContainer.new()
	box.position = Vector2(20, 140)
	box.custom_minimum_size = Vector2(260, 0)
	_hud.add_child(box)
	_hud_box = box
	var caption := Label.new()
	caption.text = "Напряжение снега"
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	caption.add_theme_constant_override("outline_size", 6)
	box.add_child(caption)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(260, 14)
	box.add_child(_bar)
	var hint := Label.new()
	hint.text = "Один рывок, прыжок или удар — и снег сорвётся! Только шагом"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.75)
	box.add_child(hint)
	_warn = Label.new()
	_warn.text = "ЛАВИНА!"
	_warn.add_theme_font_size_override("font_size", 56)
	_warn.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_warn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_warn.add_theme_constant_override("outline_size", 14)
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warn.offset_left = -420.0
	_warn.offset_right = 420.0
	_warn.offset_top = 96.0
	_warn.offset_bottom = 230.0
	_warn.visible = false
	_hud.add_child(_warn)
	_shelter_lbl = Label.new()
	_shelter_lbl.add_theme_font_size_override("font_size", 26)
	_shelter_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	_shelter_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_shelter_lbl.add_theme_constant_override("outline_size", 8)
	_shelter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shelter_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_shelter_lbl.offset_left = -400.0
	_shelter_lbl.offset_right = 400.0
	_shelter_lbl.offset_top = -190.0
	_shelter_lbl.offset_bottom = -150.0
	_shelter_lbl.visible = false
	_hud.add_child(_shelter_lbl)


func _build_audio() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_audio = AudioStreamPlayer.new()
	_audio.stream = gen
	_audio.volume_db = -60.0
	add_child(_audio)
	# шаг 137: записанные звуки (freesound, CC0): рёв лавины рядом, ветер из снежной пыли
	_snd_roar = _loop_player("res://assets/avalanche/roar.ogg")
	if ResourceLoader.exists("res://assets/avalanche/rumble.ogg"):
		_rumble_stream = load("res://assets/avalanche/rumble.ogg")     # шаг 137: заранее, не в момент срыва
	_snd_wind = _loop_player("res://assets/avalanche/wind.ogg")


func _loop_player(path: String) -> AudioStreamPlayer:
	var ap := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var st = load(path)
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		ap.stream = st
	ap.volume_db = -80.0
	add_child(ap)
	return ap


## Шаг 137: далёкий срыв — глухой раскат с того склона (3D: слышно, откуда)
func _far_sound(f: Node3D) -> void:
	if _rumble_stream == null:
		return
	var ap := AudioStreamPlayer3D.new()
	ap.stream = _rumble_stream
	ap.unit_size = 160.0
	ap.max_distance = 2000.0
	ap.volume_db = 6.0
	ap.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	f.add_child(ap)
	ap.global_position = (f as Node3D).call("front_center") + Vector3.UP * 20.0
	ap.play()


func _update_hud(delta: float) -> void:
	var me := _player
	var inside := me != null and is_instance_valid(me) and _in_valley(me.global_position)
	var s := s_of(me.global_position) if inside else -1.0
	_hud_box.visible = inside and s < W.QUIET_END and s > 0.0 and (_chase_flow == null or not is_instance_valid(_chase_flow))
	_bar.value = tension
	_bar.modulate = Color(0.6, 0.85, 1.0).lerp(Color(1, 0.3, 0.25), clampf(tension, 0.0, 1.0))
	# ближайшая лавина
	var near := 1e9
	var inside_flow := false
	var chase_on := false
	var cloud := 0.0
	var pre := 0.0                         # гул перед срывом (ещё до того, как поток пошёл)
	for f in flows:
		if not is_instance_valid(f) or (f.stopped and f._age_after > 3.0):
			continue
		if me:
			near = minf(near, me.global_position.distance_to(f.front_center()))
			if f.hit_test(me.global_position)[0]:
				inside_flow = true
			cloud = maxf(cloud, f.cloud_test(me.global_position))
		if f.t < 0.0:
			pre = maxf(pre, 1.0 - (-f.t) / maxf(f.warn, 0.1))
		if f.kind == FLOW.K.CHASE and not f.stopped:
			chase_on = true
	var swept: bool = me != null and me.get("snow") != null and me.snow.swept
	var buried: bool = me != null and me.get("snow") != null and me.snow.buried
	var wt := 0.0
	if swept or buried:
		wt = 0.0                          # в потоке и в сугробе — свой экран (snow_state.gd)
	elif inside_flow:
		wt = 0.12
	elif near < 40.0:
		wt = (1.0 - near / 40.0) * 0.15
	wt = maxf(wt, cloud * 0.15) if not (swept or buried) else wt
	_white.color.a = move_toward(_white.color.a, wt, delta * 2.5)
	if me and _in_valley(me.global_position):
		# земля дрожит: чем ближе поток, тем сильнее; перед срывом — нарастает
		# шаг 137: тряска — только когда лавина совсем рядом и слабая (раньше экран дрожал с 240 м)
		var shk := 0.05 * (1.0 - near / 70.0) if near < 70.0 else 0.0
		shk = maxf(shk, pre * 0.03)
		if shk > 0.0:
			if not bool(me.get("fp_view")):
				me.add_shake(shk)
	_warn_t -= delta
	_warn.visible = _warn_t > 0.0 and not buried
	_warn.modulate.a = clampf(_warn_t / 0.4, 0.0, 1.0)
	_warn.text = "ЛАВИНА!"
	_rumble = move_toward(_rumble, maxf(clampf(1.0 - near / 320.0, 0.0, 1.0), pre * 0.7), delta * 0.9)
	# шаг 137: рёв лавины нарастает по мере приближения; ветер — в снежной пыли и в потоке
	var roar_k := clampf(1.0 - near / 260.0, 0.0, 1.0)
	roar_k = roar_k * roar_k
	if swept:
		roar_k = 1.0
	elif buried:
		roar_k = 0.0
	_set_loop(_snd_roar, roar_k * 0.95, delta)
	_set_loop(_snd_wind, clampf(maxf(cloud, 1.0 if (inside_flow or swept) else 0.0) * 0.8 + roar_k * 0.25, 0.0, 1.0), delta)
	if buried:
		var sh: bool = me.snow.shallow
		_shelter_say(("Завалило по грудь! ЛКМ / ПКМ по очереди — откапывайся  %d%%" % roundi(me.snow.dig_progress * 100.0)) if sh \
			else "Завалило с головой — самому не выбраться. Маячок мигает: жди, друг откопает (E)")
	_shelter_t -= delta
	_shelter_lbl.visible = _shelter_t > 0.0
	_shelter_lbl.text = _shelter_msg
	_thump = maxf(_thump - delta * 0.7, 0.0)
	_pump_audio()


func _set_loop(ap: AudioStreamPlayer, k: float, delta: float) -> void:
	if ap == null or ap.stream == null:
		return
	var cur := db_to_linear(ap.volume_db)
	var v := move_toward(cur, k, delta * 0.8)
	ap.volume_db = linear_to_db(maxf(v, 0.0001))
	if v > 0.002 and not ap.playing:
		ap.play(randf() * 10.0)
	elif v <= 0.002 and ap.playing:
		ap.stop()


func _pump_audio() -> void:
	var lvl := maxf(_rumble, _thump)
	if lvl < 0.01:
		if _audio.playing:
			_audio.stop()
			_gen = null
		return
	if not _audio.playing:
		_audio.play()
		_gen = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _gen == null:
		return
	_audio.volume_db = linear_to_db(clampf(lvl, 0.001, 1.0)) - 2.0
	var n := _gen.get_frames_available()
	var me = _player
	var in_cap: bool = me != null and is_instance_valid(me) and me.get("snow") != null and int(me.snow.capsule) >= 0
	var muffle: bool = in_cap or (me != null and is_instance_valid(me) and me.get("snow") != null and me.snow.buried)
	var cut := (0.005 if in_cap else 0.008) if muffle else 0.02
	var gain := 0.55 if in_cap else 1.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		_lp1 += (w - _lp1) * cut
		_lp2 += (_lp1 - _lp2) * 0.03
		_lk += (w - _lk) * 0.06
		_kenv *= 0.99865
		_throb += 1.0 / 22050.0
		var am := 0.8 + 0.2 * sin(_throb * TAU * 5.5) * sin(_throb * TAU * 0.7)
		var v := clampf(_lp2 * (16.0 + 30.0 * _thump) * am * gain + _lk * _kenv * 2.2, -1.0, 1.0)
		_gen.push_frame(Vector2(v, v))


# ---------------------------------------------------------------------------
#  Обстановка долины (у всех одинаковая — по зерну)
# ---------------------------------------------------------------------------

func _decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5606
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.95, 0.4, 0.08)
	pole_mat.roughness = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	var rock_mat: Material = _ter.get("terrain_material") if _ter else null
	var rock_std := StandardMaterial3D.new()
	rock_std.albedo_color = Color(0.36, 0.38, 0.43)
	rock_std.roughness = 0.95
	var snowm := StandardMaterial3D.new()
	snowm.albedo_color = Color(0.92, 0.95, 1.0)
	snowm.roughness = 0.95
	# вешки вдоль тропы (оранжевые с чёрными полосами) — через 20 м, по очереди слева/справа
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 2.2
	pm.material = pole_mat
	var bm := CylinderMesh.new()
	bm.top_radius = 0.065
	bm.bottom_radius = 0.065
	bm.height = 0.18
	bm.material = dark
	var k := 0
	var s := -W.CALM + 6.0
	while s < W.LENGTH - 5.0:
		var pp := W.path_point(s)
		var dir := W.path_dir(s)
		var side_v := Vector3(dir.z, 0.0, -dir.x)
		var q := pp + side_v * (4.5 if k % 2 == 0 else -4.5)
		q.y = _gy(q.x, q.z)
		if absf(s - W.RIFT_S) < W.RIFT_HW + 3.0:
			k += 1
			s += 20.0
			continue
		var pole := MeshInstance3D.new()
		pole.mesh = pm
		pole.position = q + Vector3.UP * 1.0
		add_child(pole)
		for b in 3:
			var band := MeshInstance3D.new()
			band.mesh = bm
			band.position = q + Vector3.UP * (0.6 + b * 0.55)
			add_child(band)
		k += 1
		s += 20.0
	# скалы на склонах (выходы породы) и валуны у подножия
	for i in 90:
		var s2 := rng.randf_range(5.0, W.LENGTH - 10.0)
		if absf(s2 - W.RIFT_S) < W.RIFT_HW + 6.0:
			continue
		var sd := 1.0 if rng.randf() < 0.5 else -1.0
		var d := rng.randf_range(2.0, 70.0)
		var x := W.center_x(s2) + sd * (W.half_w(s2) + d)
		var z := W.z_of(s2)
		var sz := rng.randf_range(1.5, 4.5) * (1.0 + d / 60.0)
		_rock(Vector3(x, _gy(x, z) - sz * 0.3, z), sz, rng, rock_mat if rock_mat else rock_std, d < 6.0)
	# скальный гребень в конце: тут лавина выдыхается
	for i in 26:
		var u := float(i) / 25.0 * 2.0 - 1.0
		if absf(u) < 0.14:
			continue
		var s3 := W.SAFE_S + 14.0 + rng.randf_range(-3.0, 3.0)
		var x3 := W.center_x(s3) + u * (W.half_w(s3) + 20.0)
		var z3 := W.z_of(s3)
		var sz3 := rng.randf_range(2.5, 4.5)
		_rock(Vector3(x3, _gy(x3, z3) - 0.6, z3), sz3, rng, rock_mat if rock_mat else rock_std, true)
	# таблички
	_sign(W.path_point(12.0), "ЛАВИНООПАСНО!\nОдин рывок, прыжок или удар —\nи склон сорвётся. Только шагом!\nКапсулы у тропы и ниши в скалах —\nукрытие на одного (E)")
	_sign(W.path_point(W.TRIGGER_S - 12.0), "ДАЛЬШЕ СНЕГ СОЙДЁТ САМ —\nи будет сходить снова!\nБегом не спастись:\nпрячься в капсулу (E).\nВ конце — разлом и мост:\nопускать лебёдкой вдвоём")
	_sign(W.path_point(W.SAFE_S + 12.0), "ЗА РАЗЛОМОМ ЛАВИНА\nНЕ ДОСТАЁТ")
	_sign(W.path_point(W.RIFT_S - W.RIFT_HW - 9.0), "РАЗЛОМ! Мост опускает лебёдка:\nодин держит E и крутит —\nостальные бегут по мосту.\nОтпустил — мост поднимается.\nНа том берегу — вторая лебёдка")
	bridge = Node3D.new()
	bridge.set_script(BRIDGE)
	bridge.name = "Drawbridge"
	add_child(bridge)
	# контрольные точки: у входа и за гребнем
	_checkpoint(-W.CALM * 0.6, "Передышка", "Дальше Лавинная долина: иди шагом и смотри на горы. Сошла лавина — сразу беги к капсуле")
	_checkpoint(W.SAFE_S + 20.0, "Скальный гребень", "Лавина позади. Контрольная точка")
	# укрытия: ниши в скалах у подножия склонов (на одного)
	var ni := 0
	for sn2 in NICHES:
		_niche(float(sn2), 1.0 if ni % 2 == 0 else -1.0, rng, rock_mat if rock_mat else rock_std, pole_mat)
		ni += 1
	# капсулы-убежища у тропы
	for cp2 in CAPSULES:
		_capsule(float(cp2[0]), float(cp2[1]))
	# гнёзда снежных роботов
	# шаг 66: гнёзд — на самую большую компанию; спят лишние (сколько роботов — по числу игроков)
	var idx := 0
	for kk in ROBOTS_MAX:
		var s4: float = 40.0 + kk * (270.0 / (ROBOTS_MAX - 1))
		var sd4 := 1.0 if idx % 2 == 0 else -1.0
		var x4 := W.center_x(s4) + sd4 * W.half_w(s4) * (0.35 + 0.25 * float((kk * 7) % 5) / 4.0)
		var z4 := W.z_of(s4)
		var r := CharacterBody3D.new()
		r.set_script(ROBOT)
		r.name = "SnowRobot%d" % idx
		r.set("index", idx)
		var home := Vector3(x4, _gy(x4, z4), z4)
		r.set("home", home)
		r.position = home
		add_child(r)
		idx += 1
	# шаг 66: зона погони — скальные гряды с проходами, валуны, ледяные проплешины (трещины — в рельефе)
	_chase_zone(rock_mat if rock_mat else rock_std)


func _gy(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else 0.0


## Шаг 66: препятствия в зоне погони (раскладка одинаковая у всех — свой seed)
func _chase_zone(mat: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 660066
	# гряды поперёк дна: у тропы узкий проход, у одного из склонов — широкий обход
	for rg in W.RIDGES:
		var s0: float = rg[0]
		var side: float = rg[1]
		var hw := W.half_w(s0)
		var g0 := hw - 30.0
		var g1 := hw - 12.0
		for sx: float in [-1.0, 1.0]:
			var d := W.PASS_HALF
			while d < hw + 8.0:
				var sz := rng.randf_range(3.4, 5.2)
				var r := sz * 0.65
				var c := d + r
				if sx == side and c + r > g0 and c - r < g1:
					d = g1
					continue
				var s1 := s0 + rng.randf_range(-1.2, 1.2) + 1.8 * sin(c * 0.06 + s0)
				var x: float = W.center_x(s1) + sx * c
				var z := W.z_of(s1)
				_rock(Vector3(x, _gy(x, z) - sz * 0.25, z), sz, rng, mat, true)
				d = c + r * 0.75
	# валуны на дне (тропа свободна)
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 900:
		tries += 1
		var s2 := rng.randf_range(342.0, W.RIFT_S - W.RIFT_HW - 10.0)
		var hw2 := W.half_w(s2)
		var dx2 := rng.randf_range(-hw2 + 5.0, hw2 - 5.0)
		var sz2 := rng.randf_range(1.8, 3.6)
		if absf(dx2) < 5.0 + sz2 * 0.65 or _near_feature(s2, dx2, sz2 * 0.65 + 4.0):
			continue
		var x2 := W.center_x(s2) + dx2
		var z2 := W.z_of(s2)
		_rock(Vector3(x2, _gy(x2, z2) - sz2 * 0.3, z2), sz2, rng, mat, true)
		placed += 1
	# ледяные проплешины
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05
	for ic in W.ICE:
		_ice_patch(float(ic[0]), float(ic[1]), float(ic[2]), float(ic[3]), pm, rng)
	# трещины видно: стенки — голубой лёд, в глубине темнее
	for c in W.CRACKS:
		_crack_lining(float(c[0]), float(c[1]), float(c[2]))
	var hr := W.half_w(W.RIFT_S) + 52.0
	_crack_lining(W.RIFT_S, -hr, hr, W.RIFT_HW + 4.0)
	pass                               # шаг 137: стена с ледяным тоннелем (пещера) убрана


## Шаг 67/68: высокая скальная стена поперёк дна; на тропе — ледяной тоннель, у склона — обход.
## Шаг 68: тоннель длиннее (30 м) и плавно изгибается — выхода из середины не видно, внутри почти темно.
func _tunnel_wall(mat: Material, rng: RandomNumberGenerator) -> void:
	var ts := W.TUNNEL_S
	var thw := W.half_w(ts)
	var g0 := thw - 34.0
	var g1 := thw - 14.0
	var L := W.TUNNEL_LEN
	var inner := W.TUNNEL_HALF + 1.3
	for row: float in [-1.0, 0.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var d := 0.0
			while d < thw + 14.0:
				var sz := rng.randf_range(7.0, 9.5)
				var r := sz * 0.65
				var c := d + r * 0.6
				if sx == W.TUNNEL_SIDE and c + r > g0 and c - r < g1:
					d = g1 + 2.6           # 0.4·r самой большой скалы — следующая не залезет в обход
					continue
				var s1 := ts + row * (L * 0.5 - 4.5) + rng.randf_range(-1.0, 1.0)
				var x: float = W.center_x(s1) + sx * c
				var z := W.z_of(s1)
				# скала не должна заходить внутрь тоннеля (её опора — шар радиусом r)
				if (_tun_near(x, z) as Vector2).x - r < inner:
					d = c + r * 0.4
					continue
				_rock(Vector3(x, _gy(x, z) - sz * 0.15, z), sz, rng, mat, true)
				d = c + r * 0.75
	_tunnel(mat, rng)


## (расстояние по горизонтали до оси тоннеля, t на оси)
func _tun_near(x: float, z: float) -> Vector2:
	var best := Vector2(INF, 0.0)
	var t := -W.TUNNEL_LEN * 0.5
	while t <= W.TUNNEL_LEN * 0.5 + 0.01:
		var p := W.tunnel_point(t)
		var dd := Vector2(p.x - x, p.z - z).length()
		if dd < best.x:
			best = Vector2(dd, t)
		t += 0.5
	return best


const TUNNEL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 cry[12];
uniform int cry_n = 0;
uniform float len = 30.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// свет с улицы — только у входов, к середине (за изгибом) почти темно
	float m = min(UV.y, 1.0 - UV.y) * len;
	float day = exp(-m * 0.3);
	float n = texture(noise_tex, wp.xz * 0.09 + vec2(wp.y * 0.11, 0.0)).r;
	float n2 = texture(noise_tex, vec2(wp.z, wp.y) * 0.31 + vec2(wp.x * 0.2, 0.0)).r;
	vec3 ice = mix(vec3(0.04, 0.1, 0.2), vec3(0.32, 0.6, 0.9), clamp(n * 0.75 + n2 * 0.4 - 0.1, 0.0, 1.0));
	if (COLOR.r > 0.5) {
		ice = vec3(0.5, 0.58, 0.68) * (0.75 + 0.3 * n);   // утоптанный снег на полу
	}
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		if (i >= cry_n) { break; }
		float d = distance(wp, cry[i]);
		glow += vec3(0.25, 0.62, 1.0) * 1.1 / (1.0 + d * d * 3.0);
	}
	// искорки инея — вспыхивают в свете кристаллов
	float sp = step(0.94, texture(noise_tex, wp.xz * 1.9 + vec2(wp.y * 1.3, wp.y)).r);
	vec3 col = ice * (0.012 + day * 1.1) + ice * glow * 0.7 + glow * 0.03;
	col += vec3(0.7, 0.9, 1.0) * sp * (glow.b * 0.5 + day * 0.3);
	ALBEDO = col;
}
"""
static var _tun_shader: Shader


func _tunnel(mat: Material, rng: RandomNumberGenerator) -> void:
	var L := W.TUNNEL_LEN
	var WALL := 1.3
	var WO := 8.0                     # полуширина скального массива вокруг тоннеля
	var TO := 9.5                     # его высота
	var seg := 40
	var ring := 14
	var bump := FastNoiseLite.new()
	bump.seed = 6868
	bump.frequency = 0.35
	var big := FastNoiseLite.new()
	big.seed = 6869
	big.frequency = 0.12
	# сечение: [0] низ слева, стенка вверх, свод, стенка вниз, [последний] низ справа
	var prof: Array[Vector2] = []
	prof.append(Vector2(-1.0, 0.0))
	prof.append(Vector2(-1.0, WALL))
	for k in ring + 1:
		var a := PI - PI * float(k) / ring
		prof.append(Vector2(cos(a), WALL + sin(a) * 0.95))
	prof.append(Vector2(1.0, 0.0))
	var np := prof.size()
	var iv := PackedVector3Array()       # внутри
	var iuv := PackedVector2Array()
	var icol := PackedColorArray()
	var fl := PackedVector3Array()       # пол
	var fuv := PackedVector2Array()
	var outer: Array = []                # снаружи: кольца точек
	var frames: Array = []               # [центр (на земле), dir, lat, h]
	for i in seg + 1:
		var t := -L * 0.5 + L * float(i) / seg
		var c := W.tunnel_point(t)
		var c2 := W.tunnel_point(t + 0.2) - W.tunnel_point(t - 0.2)
		var dir := Vector3(c2.x, 0.0, c2.z).normalized()
		var lat := Vector3(-dir.z, 0.0, dir.x)
		var h := W.tunnel_half(t)
		var gy := _gy(c.x, c.z)
		c.y = gy
		frames.append([c, dir, lat, h])
		var ring_o: Array[Vector3] = []
		for j in np:
			var q: Vector2 = prof[j]
			var px := q.x * h
			var py := q.y
			if j > 1 and j < np - 2:
				py = WALL + (q.y - WALL) * h
			var base := c + lat * px + Vector3.UP * py
			# неровный лёд: бугры только наружу (опора — по гладкому сечению, ближе к оси)
			var out_dir := (lat * px + Vector3.UP * maxf(py - WALL, 0.0)).normalized()
			var nb := (bump.get_noise_3dv(base) * 0.5 + 0.5) * 0.28 * h + (big.get_noise_3dv(base) * 0.5 + 0.5) * 0.22 * h
			if j == 0 or j == np - 1:
				nb *= 0.4
			var v := base + out_dir * nb
			if j == 0 or j == np - 1:
				v.y = gy - 0.05
			iv.append(v)
			iuv.append(Vector2(float(j) / (np - 1), (t + L * 0.5) / L))
			icol.append(Color(0, 0, 0))
			# снаружи — скальный горб
			var oq := Vector2(q.x * WO, (q.y / (WALL + 0.95)) * TO)
			var ob := c + lat * oq.x + Vector3.UP * oq.y
			var on := (big.get_noise_3dv(ob * 0.5) * 0.5 + 0.5) * 2.2
			var od := (lat * q.x + Vector3.UP * maxf(q.y - WALL, 0.0) * 1.5).normalized()
			var ov := ob + od * on
			if j == 0 or j == np - 1:
				ov.y = gy - 1.5
			ring_o.append(ov)
		outer.append(ring_o)
		for k2 in 5:
			var u := -1.0 + 2.0 * float(k2) / 4.0
			var fp := c + lat * u * h * 1.4          # пол уходит под стенки (у стен — бугры наружу)
			fp.y = _gy(fp.x, fp.z) + 0.03
			fl.append(fp)
			fuv.append(Vector2(float(k2) / 4.0, (t + L * 0.5) / L))
	# внутренняя поверхность + пол — одна сетка, тёмный шейдер
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		for j in np - 1:
			var a0 := i * np + j
			for idx in [a0, a0 + np, a0 + 1, a0 + 1, a0 + np, a0 + np + 1]:
				st.set_color(Color(0, 0, 0))
				st.set_uv(iuv[idx])
				st.add_vertex(iv[idx])
		for k3 in 4:
			var f0 := i * 5 + k3
			for idx2 in [f0, f0 + 5, f0 + 1, f0 + 1, f0 + 5, f0 + 6]:
				st.set_color(Color(1, 0, 0))
				st.set_uv(fuv[idx2])
				st.add_vertex(fl[idx2])
	var imesh := st.commit()
	if _tun_shader == null:
		_tun_shader = Shader.new()
		_tun_shader.code = TUNNEL_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _tun_shader
	var nz := FastNoiseLite.new()
	nz.seed = 77
	nz.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = nz
	sm.set_shader_parameter("noise_tex", nt)
	sm.set_shader_parameter("len", L)
	imesh.surface_set_material(0, sm)
	var imi := MeshInstance3D.new()
	imi.name = "IceTunnel"
	imi.mesh = imesh
	imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(imi)
	# снаружи — скальный массив (горб) и торцы вокруг входов
	var so := SurfaceTool.new()
	so.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var r0: Array = outer[i]
		var r1: Array = outer[i + 1]
		for j in np - 1:
			for v3 in [r0[j], r1[j], r0[j + 1], r0[j + 1], r1[j], r1[j + 1]]:
				so.add_vertex(v3)
	for e in [0, seg]:
		var ro: Array = outer[e]
		for j in np - 1:
			var i0: Vector3 = iv[e * np + j]
			var i1: Vector3 = iv[e * np + j + 1]
			var o0: Vector3 = ro[j]
			var o1: Vector3 = ro[j + 1]
			if e == 0:
				for v4 in [i0, o0, i1, i1, o0, o1]:
					so.add_vertex(v4)
			else:
				for v5 in [i0, i1, o0, i1, o1, o0]:
					so.add_vertex(v5)
	so.generate_normals()
	var omesh := so.commit()
	omesh.surface_set_material(0, mat)
	var omi := MeshInstance3D.new()
	omi.name = "TunnelRock"
	omi.mesh = omesh
	add_child(omi)
	# опора: по кускам 2 м — стенки (от гладкого сечения до края массива) и свод
	var pieces := 15
	for pc in pieces:
		var i0 := pc * seg / pieces
		var i1 := (pc + 1) * seg / pieces
		var fa: Array = frames[i0]
		var fb: Array = frames[i1]
		var ca: Vector3 = fa[0]
		var cb: Vector3 = fb[0]
		var mid := (ca + cb) * 0.5
		var dv := Vector3(cb.x - ca.x, 0.0, cb.z - ca.z)
		var ln := dv.length() + 0.15
		var dir2 := dv.normalized()
		var lat2 := Vector3(-dir2.z, 0.0, dir2.x)
		var hmin := minf(float(fa[3]), float(fb[3]))
		var hmax := maxf(float(fa[3]), float(fb[3]))
		var body := StaticBody3D.new()
		body.transform = Transform3D(Basis(lat2, Vector3.UP, -dir2), Vector3(mid.x, minf(ca.y, cb.y), mid.z))
		for sx2: float in [-1.0, 1.0]:
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			var wx := WO - hmin - 0.1
			bx.size = Vector3(wx, TO + 2.0, ln)
			cs.shape = bx
			cs.position = Vector3(sx2 * (hmin + 0.1 + wx * 0.5), (TO + 2.0) * 0.5 - 1.0, 0.0)
			body.add_child(cs)
		var cr := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		var roof0 := WALL + hmax * 0.95 + 0.05
		rb.size = Vector3(2.0 * hmax + 0.4, TO + 1.0 - roof0, ln)
		cr.shape = rb
		cr.position = Vector3(0.0, roof0 + rb.size.y * 0.5 + absf(ca.y - cb.y), 0.0)
		body.add_child(cr)
		add_child(body)
	# внутри — светящиеся кристаллы (вмёрзли в стены); от них — синие пятна света
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.5, 0.85, 1.0)
	cm.emission_enabled = true
	cm.emission = Color(0.3, 0.75, 1.0)
	cm.emission_energy_multiplier = 2.2
	var pr := PrismMesh.new()
	pr.size = Vector3(0.16, 0.45, 0.16)
	pr.material = cm
	var cry := PackedVector3Array()
	for i in 10:
		var t3 := -L * 0.5 + 2.5 + (L - 5.0) * (float(i) + rng.randf_range(0.0, 0.6)) / 10.0
		var c3 := W.tunnel_point(t3)
		var c4 := W.tunnel_point(t3 + 0.2) - W.tunnel_point(t3 - 0.2)
		var dir3 := Vector3(c4.x, 0.0, c4.z).normalized()
		var lat3 := Vector3(-dir3.z, 0.0, dir3.x)
		var sx3 := 1.0 if i % 2 == 0 else -1.0
		var h3 := W.tunnel_half(t3)
		var p3 := c3 + lat3 * sx3 * (h3 + 0.1)
		p3.y = _gy(c3.x, c3.z) + rng.randf_range(0.4, 1.9)
		var grp := Node3D.new()
		grp.position = p3
		add_child(grp)
		for k4 in 3:
			var cry_mi := MeshInstance3D.new()
			cry_mi.mesh = pr
			cry_mi.scale = Vector3.ONE * rng.randf_range(0.6, 1.3)
			cry_mi.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, -sx3 * rng.randf_range(0.7, 1.3))
			cry_mi.position = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.15))
			grp.add_child(cry_mi)
		cry.append(p3 - lat3 * sx3 * 0.25)
		if i % 3 == 1:
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(0.4, 0.72, 1.0)
			lamp.light_energy = 0.55
			lamp.omni_range = 4.5
			lamp.position = p3 - lat3 * sx3 * 0.5
			add_child(lamp)
	sm.set_shader_parameter("cry", cry)
	sm.set_shader_parameter("cry_n", cry.size())
	# снег внутрь не насыпается (иначе завалит тоннель)
	var t5 := -L * 0.5 - 2.0
	while t5 <= L * 0.5 + 2.0:
		var p5 := W.tunnel_point(t5)
		layer.no_zones.append([Vector2(p5.x, p5.z), W.TUNNEL_HALF + 1.0, W.TUNNEL_HALF + 3.0])
		t5 += 2.5


## Камера в тоннеле — гасим рассеянный свет (внутри почти темно; у входов — плавно)
## Шаг 137: тоннеля больше нет. В долине воздух прозрачнее (туман втрое реже) — лавину на дальнем склоне
## видно за 250 м; ушёл из долины — туман как был
func _update_tunnel_dark(delta: float) -> void:
	if _env == null:
		var found := get_tree().root.find_children("*", "WorldEnvironment", true, false)
		if found.is_empty():
			return
		_env = (found[0] as WorldEnvironment).environment
		if _env == null:
			return
		_amb0 = _env.ambient_light_energy
		_fogl0 = _env.fog_density
	var cam := get_viewport().get_camera_3d()
	var want := 0.0
	if cam:
		var cp := cam.global_position
		var sc := s_of(cp)
		want = smoothstep(-W.CALM, -W.CALM + 40.0, sc) * (1.0 - smoothstep(W.LENGTH - 30.0, W.LENGTH + 20.0, sc))
	_dark_k = move_toward(_dark_k, want, delta * 0.35)
	if _dark_k > 0.001 or _dark_set:
		_env.fog_density = _fogl0 * lerpf(1.0, 0.34, _dark_k)
		_dark_set = _dark_k > 0.001


## Рядом с капсулой, нишей, грядой, трещиной или льдом? (s, dx — от тропы)
func _near_feature(s: float, dx: float, r: float) -> bool:
	for cp in CAPSULES:
		if Vector2(s - float(cp[0]), dx - float(cp[1])).length() < r + 10.0:
			return true
	var ni := 0
	for sn in NICHES:
		var nd := (1.0 if ni % 2 == 0 else -1.0) * W.half_w(float(sn))
		if Vector2(s - float(sn), dx - nd).length() < r + 8.0:
			return true
		ni += 1
	for rg in W.RIDGES:
		if absf(s - float(rg[0])) < r + 5.0:
			return true
	if absf(s - W.TUNNEL_S) < r + W.TUNNEL_LEN * 0.5 + 3.0 or s > W.RIFT_S - W.RIFT_HW - 8.0 - r:
		return true
	for c in W.CRACKS:
		if absf(s - float(c[0])) < r + W.CRACK_W + 4.0 and dx > float(c[1]) - r and dx < float(c[2]) + r:
			return true
	for ic in W.ICE:
		var e := Vector2((s - float(ic[0])) / (float(ic[3]) + r), (dx - float(ic[1])) / (float(ic[2]) + r))
		if e.length() < 1.3:
			return true
	return false


static var _ice_mat: StandardMaterial3D

static func ice_material() -> StandardMaterial3D:
	if _ice_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.16, 0.4, 0.72)
		m.roughness = 0.15
		m.metallic_specular = 0.35
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_CELLULAR
		nz.frequency = 0.03
		nz.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		nt.noise = nz
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = 0.6
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.12, 0.12, 0.12)
		_ice_mat = m
	return _ice_mat


static var _crack_mat: StandardMaterial3D

## Стенки трещины: тонкая плёнка по рельефу (узлы сетки рельефа, +3 см), цвет — по глубине
func _crack_lining(cs: float, a: float, b: float, ds := 8.0) -> void:
	if _crack_mat == null:
		_crack_mat = StandardMaterial3D.new()
		_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_crack_mat.vertex_color_use_as_albedo = true
		_crack_mat.roughness = 0.25
		_crack_mat.metallic_specular = 0.7
		_crack_mat.emission_enabled = true
		_crack_mat.emission = Color(0.04, 0.12, 0.25)
		_crack_mat.emission_energy_multiplier = 0.3
	var cell := 1.5
	var tx0 := -270.0
	var tz0 := -2811.0 + 4026.0
	if _ter:
		cell = float(_ter.get("cell"))
		tx0 = -float(_ter.get("size_x")) * 0.5
		tz0 = float(_ter.get("north_edge_z")) + float(_ter.get("size_z"))
	var cx := W.center_x(cs)
	var cz := W.z_of(cs)
	var cy := _gy(cx, cz)
	var ix0 := int(floor((cx + a - 6.0 - tx0) / cell))
	var ix1 := int(ceil((cx + b + 6.0 - tx0) / cell))
	var iz0 := int(floor((tz0 - (cz + ds)) / cell))
	var iz1 := int(ceil((tz0 - (cz - ds)) / cell))
	var w := ix1 - ix0 + 1
	var hh := iz1 - iz0 + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var al := PackedFloat32Array()
	var lip := Color(0.7, 0.85, 0.97)
	var deep := Color(0.1, 0.27, 0.52)
	for j in hh:
		for i in w:
			var x := tx0 + (ix0 + i) * cell
			var z := tz0 - (iz0 + j) * cell
			var dep := -W.crack_off(x, W.s_of(z))
			var y := _gy(x, z)
			verts.append(Vector3(x - cx, y + 0.03 - cy, z - cz))
			var hl := _gy(x - cell, z)
			var hr := _gy(x + cell, z)
			var hs := _gy(x, z + cell)
			var hn := _gy(x, z - cell)
			norms.append(Vector3(-(hr - hl) / (2.0 * cell), 1.0, -(hs - hn) / (2.0 * cell)).normalized())
			var k := smoothstep(0.03, 0.4, dep)
			var col := lip.lerp(deep, smoothstep(0.2, 1.6, dep)).lerp(Color(0.02, 0.05, 0.12), smoothstep(3.0, 20.0, dep))
			col.a = k
			cols.append(col)
			al.append(k)
	var idx := PackedInt32Array()
	for j in hh - 1:
		for i in w - 1:
			var a0 := j * w + i
			var b0 := a0 + 1
			var c0 := a0 + w
			var d0 := c0 + 1
			if maxf(maxf(al[a0], al[b0]), maxf(al[c0], al[d0])) <= 0.0:
				continue
			idx.append_array(PackedInt32Array([a0, c0, b0, b0, c0, d0]))
	if idx.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _crack_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Crack%d" % int(cs)
	mi.mesh = mesh
	mi.position = Vector3(cx, cy, cz)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Ледяная проплешина: тонкая корка по рельефу (вершины — в узлах сетки рельефа, на 5 см выше),
## края тают в прозрачность; опора скользкая (трение 0.05)
func _ice_patch(s0: float, dx0: float, ax: float, az: float, pm: PhysicsMaterial, rng: RandomNumberGenerator) -> void:
	var cx := W.center_x(s0) + dx0
	var cz := W.z_of(s0)
	var cy := _gy(cx, cz)
	var cell := 1.5
	var tx0 := -270.0
	var tz0 := -2811.0 + 4026.0
	if _ter:
		cell = float(_ter.get("cell"))
		tx0 = -float(_ter.get("size_x")) * 0.5
		tz0 = float(_ter.get("north_edge_z")) + float(_ter.get("size_z"))
	var ix0 := int(floor((cx - ax - 3.0 - tx0) / cell))
	var ix1 := int(ceil((cx + ax + 3.0 - tx0) / cell))
	var iz0 := int(floor((tz0 - (cz + az + 3.0)) / cell))
	var iz1 := int(ceil((tz0 - (cz - az - 3.0)) / cell))
	var w := ix1 - ix0 + 1
	var hh := iz1 - iz0 + 1
	var ph := rng.randf() * TAU
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var al := PackedFloat32Array()
	for j in hh:
		for i in w:
			var x := tx0 + (ix0 + i) * cell
			var z := tz0 - (iz0 + j) * cell
			var q := Vector2((x - cx) / ax, (z - cz) / az)
			var ang := q.angle()
			var rr := 1.0 + 0.16 * sin(ang * 3.0 + ph) + 0.09 * sin(ang * 5.0 + ph * 2.0)
			var a := 1.0 - smoothstep(0.72, 1.0, q.length() / rr)
			var y := _gy(x, z)
			verts.append(Vector3(x - cx, y + 0.05 - cy, z - cz))
			var hl := _gy(x - cell, z)
			var hr := _gy(x + cell, z)
			var hs := _gy(x, z + cell)
			var hn := _gy(x, z - cell)
			norms.append(Vector3(-(hr - hl) / (2.0 * cell), 1.0, -(hs - hn) / (2.0 * cell)).normalized())
			cols.append(Color(1.0, 1.0, 1.0, a * 0.95))
			al.append(a)
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for j in hh - 1:
		for i in w - 1:
			var a0 := j * w + i
			var b0 := a0 + 1
			var c0 := a0 + w
			var d0 := c0 + 1
			if maxf(maxf(al[a0], al[b0]), maxf(al[c0], al[d0])) <= 0.0:
				continue
			idx.append_array(PackedInt32Array([a0, c0, b0, b0, c0, d0]))
			if minf(minf(al[a0], al[b0]), minf(al[c0], al[d0])) > 0.35:
				faces.append_array(PackedVector3Array([verts[a0], verts[c0], verts[b0], verts[b0], verts[c0], verts[d0]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ice_material())
	var body := StaticBody3D.new()
	body.name = "IcePatch%d" % int(s0)
	body.position = Vector3(cx, cy, cz)
	body.physics_material_override = pm
	body.add_to_group("valley_ice")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _rock(at: Vector3, size: float, rng: RandomNumberGenerator, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = CHUNK.build(rng.randi(), mat)
	mi.scale = Vector3(size, size * rng.randf_range(0.5, 0.9), size * rng.randf_range(0.7, 1.1))
	mi.rotation.y = rng.randf() * TAU
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.position = at + Vector3.UP * size * 0.35
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = size * 0.65
		cs.shape = sp
		body.add_child(cs)
		add_child(body)


func _sign(at: Vector3, text: String) -> void:
	var q := at + Vector3(5.5, 0.0, 0.0)
	q.y = _gy(q.x, q.z)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.24, 0.14)
	for sx in [-0.8, 0.8]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.07
		cm.height = 2.4
		cm.material = wood
		post.mesh = cm
		post.position = q + Vector3(sx, 1.2, 0)
		add_child(post)
	var board := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(2.2, 1.2, 0.08)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.95, 0.75, 0.1)
	bx.material = bmat
	board.mesh = bx
	board.position = q + Vector3(0, 2.0, 0)
	add_child(board)
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 28
	lb.outline_size = 8
	lb.modulate = Color(1, 1, 1)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lb.position = q + Vector3(0, 2.0, 0.1)
	add_child(lb)


func _checkpoint(s: float, title: String, sub: String) -> void:
	var cp := Area3D.new()
	cp.set_script(CHECKPOINT)
	cp.name = "AvalancheCP_%d" % int(s)
	var pp := W.path_point(s)
	pp.y = _gy(pp.x, pp.z)
	cp.set("snap_to_terrain", false)
	cp.set("size", Vector3(70.0, 12.0, 14.0))
	cp.set("respawn_offset", Vector3(0.0, 0.6, -2.0))
	cp.set("title", title)
	cp.set("subtitle", sub)
	cp.position = pp
	add_child(cp)


# ---------------------------------------------------------------------------
#  Укрытия: ниши в скалах на одного
# ---------------------------------------------------------------------------

const NICHE_IN := Vector3(0.62, 2.3, 1.45)     ## полуширина, высота, глубина ниши

## В какой нише точка (−1 — ни в какой)
func niche_at(p: Vector3) -> int:
	for i in niches.size():
		var l: Vector3 = (niches[i] as Transform3D).affine_inverse() * p
		if absf(l.x) < NICHE_IN.x and l.z < 0.1 and l.z > -NICHE_IN.z and l.y > -0.6 and l.y < NICHE_IN.y:
			return i
	return -1


## Этот дрон — хозяин ниши? (глубже всех остальных в ней)
func _shelter_owner(i: int, d: Node3D) -> bool:
	var inv := (niches[i] as Transform3D).affine_inverse()
	var my_z := (inv * d.global_position).z
	for o in get_tree().get_nodes_in_group("player"):
		if o == d or o.is_dead:
			continue
		var op: Vector3 = (o as Node3D).global_position
		if niche_at(op) != i:
			continue
		var oz := (inv * op).z
		if oz < my_z - 0.05 or (absf(oz - my_z) <= 0.05 and int(o.peer_id) < int(d.peer_id)):
			return false
	return true


func _shelter_say(msg: String) -> void:
	_shelter_msg = msg
	_shelter_t = 0.25


func _niche(s: float, sd: float, rng: RandomNumberGenerator, mat: Material, flag_mat: Material) -> void:
	var cx := W.center_x(s)
	var hw := W.half_w(s)
	var z := W.z_of(s)
	var mouth := Vector3(cx + sd * (hw - 0.6), 0.0, z)
	var bz := Vector3(-sd, 0.0, 0.0)              # наружу из ниши — к середине долины
	var bx := Vector3.UP.cross(bz)
	var back := mouth - bz * NICHE_IN.z
	mouth.y = minf(_gy(mouth.x, mouth.z), _gy(back.x, back.z)) - 0.02
	var xf := Transform3D(Basis(bx, Vector3.UP, bz), mouth)
	niches.append(xf)
	var root := Node3D.new()
	root.name = "Niche%d" % niches.size()
	root.transform = xf
	add_child(root)
	# стены, задник, крыша и глыбы вокруг — внутри ровно на одного
	var pieces := [
		[Vector3(-1.2, 1.3, -0.75), Vector3(1.15, 3.8, 2.7)],
		[Vector3(1.2, 1.3, -0.75), Vector3(1.15, 3.8, 2.7)],
		[Vector3(0.0, 1.3, -2.05), Vector3(3.5, 3.8, 1.2)],
		[Vector3(0.0, 2.9, -0.8), Vector3(3.5, 1.2, 2.9)],
		[Vector3(0.1, 2.6, -2.9), Vector3(4.6, 4.4, 2.2)],
		[Vector3(-2.3, 1.0, -1.4), Vector3(1.8, 3.0, 3.2)],
		[Vector3(2.3, 0.9, -1.2), Vector3(1.7, 2.8, 3.0)],
	]
	for pc in pieces:
		_rock_piece(root, pc[0], pc[1], rng.randi(), mat, pc[0].y < 2.5 or pc[1].x < 4.0)
	# сверху и по бокам — округлые валуны: выход скалы, а не ящик
	for bl in [[Vector3(-2.1, 3.3, -1.9), 2.7], [Vector3(2.2, 3.1, -2.3), 2.5], [Vector3(0.0, 4.1, -2.7), 3.2], [Vector3(-0.4, 3.6, -0.9), 2.2]]:
		var mi := MeshInstance3D.new()
		mi.mesh = CHUNK.build(rng.randi(), mat)
		var sz: float = bl[1]
		mi.scale = Vector3(sz, sz * rng.randf_range(0.55, 0.75), sz * rng.randf_range(0.8, 1.05))
		mi.rotation.y = rng.randf() * TAU
		mi.position = bl[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# снежная шапка на крыше
	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 0.6
	cap.mesh = cm
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.93, 0.96, 1.0)
	snow.roughness = 0.9
	cap.material_override = snow
	cap.scale = Vector3(2.2, 1.0, 2.0)
	cap.position = Vector3(0.0, 3.55, -1.2)
	root.add_child(cap)
	# вешка с флажком и надпись — видно издалека
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.05
	pm.height = 2.0
	pm.material = flag_mat
	pole.mesh = pm
	pole.position = Vector3(1.5, 4.3, -0.6)
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.03, 0.4, 0.6)
	fm.material = flag_mat
	flag.mesh = fm
	flag.position = Vector3(1.5, 5.05, -0.3)
	root.add_child(flag)
	var lb := Label3D.new()
	lb.text = "УКРЫТИЕ\nна одного"
	lb.font_size = 40
	lb.outline_size = 10
	lb.modulate = Color(1.0, 0.62, 0.2)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position = Vector3(0.0, 4.6, 0.4)
	lb.visibility_range_end = 110.0
	root.add_child(lb)
	# внутри и у входа снег не насыпается (иначе завалит того, кто спрятался)
	if layer:
		var c := xf * Vector3(0.0, 0.0, -0.7)
		layer.no_zones.append([Vector2(c.x, c.z), 1.8, 4.5])


## Кусок скалы: бугристый «ящик» (рёбра скруглены шумом); грани, что смотрят внутрь ниши, — ровные
func _rock_piece(parent: Node3D, center: Vector3, size: Vector3, seed: int, mat: Material, solid: bool) -> void:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = 0.42
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var lo := Vector3(-NICHE_IN.x, 0.0, -NICHE_IN.z)
	var hi := Vector3(NICHE_IN.x, NICHE_IN.y, 0.3)
	var n := 8
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for ax in axes:
		var nrm: Vector3 = ax
		var u := Vector3.UP if absf(nrm.y) < 0.5 else Vector3.RIGHT
		var v := nrm.cross(u)
		var grid := []
		for a in n + 1:
			var row := []
			for b in n + 1:
				var fa := float(a) / n * 2.0 - 1.0
				var fb := float(b) / n * 2.0 - 1.0
				var p := nrm * h + u * h * fa + v * h * fb
				p = Vector3(clampf(p.x, -h.x, h.x), clampf(p.y, -h.y, h.y), clampf(p.z, -h.z, h.z))
				var wp := center + p
				# внутрь ниши не выпирает
				var dist := (wp - wp.clamp(lo, hi)).length()
				var amp := 0.55 * smoothstep(0.05, 0.6, dist)
				var out := p.normalized()
				var k := fn.get_noise_3dv(wp * 1.3) * 0.5 + 0.5
				row.append(wp + out * amp * k - out * 0.12 * (1.0 - k) * smoothstep(0.05, 0.6, dist))
			grid.append(row)
		for a in n:
			for b in n:
				var p00: Vector3 = grid[a][b]
				var p10: Vector3 = grid[a + 1][b]
				var p01: Vector3 = grid[a][b + 1]
				var p11: Vector3 = grid[a + 1][b + 1]
				var tri1 := [p00, p10, p11]
				var tri2 := [p00, p11, p01]
				for tri in [tri1, tri2]:
					var fnrm := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3))
					if fnrm.dot(nrm) > 0.0:          # лицевая сторона в Godot — по часовой
						tri = [tri[0], tri[2], tri[1]]
					for q in tri:
						st.add_vertex(q)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = center
		body.add_child(cs)
		parent.add_child(body)


# ---------------------------------------------------------------------------
#  Прогрев шейдеров лавины (иначе первая подвисала)
# ---------------------------------------------------------------------------

func _prewarm() -> void:
	var cam: Camera3D = null
	for k in 600:
		cam = get_viewport().get_camera_3d()
		if cam != null:
			break
		await get_tree().process_frame
	if cam == null or _prewarmed:
		return
	_prewarmed = true
	var root := Node3D.new()
	root.name = "AvalanchePrewarm"
	cam.add_child(root)
	root.position = Vector3(0.0, 0.0, -1.0)
	var a := FLOW.prewarm_node()
	root.add_child(a)
	if layer:
		root.add_child(layer.prewarm_node())
	# капсулы (корпус, обивка, стекло, плед) и снежный экран «несёт лавина» — тоже заранее
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plaid := StandardMaterial3D.new()
	plaid.albedo_texture = plaid_texture()
	for m in [hull_material(Color(0.5, 0.5, 0.5), 0.7, 0.4, Vector3(0, 0, 99), 0.0), quilt_material(Vector3(0, 0, 99), 0.0), glass, plaid]:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.rotation.y = PI if m is ShaderMaterial and (m as ShaderMaterial).shader == _sh_quilt else 0.0
		root.add_child(mi)
	var me = Network.local_player
	if me and me.get("snow") != null:
		me.snow.prewarm_screen()
	for k in 4:
		await get_tree().process_frame
	root.queue_free()


# ---------------------------------------------------------------------------
#  Капсулы-убежища на одного (шаг 64): у тропы, люк к тропе. E — залезть, E — вылезти.
#  Внутри лавина не достаёт; занято — второй не залезет. Кто внутри, видно по положению дрона
#  (у всех одинаково) — по нему же люк открыт/закрыт.
# ---------------------------------------------------------------------------

## В какой капсуле точка (−1 — ни в какой)
func capsule_at(p: Vector3) -> int:
	for i in capsules.size():
		var l: Vector3 = (capsules[i][0] as Transform3D).affine_inverse() * p
		if absf(l.x) < 1.3 and absf(l.z) < 0.9 and l.y > -0.6 and l.y < 1.7:
			return i
	return -1


func _capsule_taken(i: int, except: Node3D = null) -> bool:
	for o in get_tree().get_nodes_in_group("player"):
		if o != except and not o.is_dead and capsule_at((o as Node3D).global_position) == i:
			return true
	return false


func _capsule_input() -> void:
	var me := _player
	if me == null or not is_instance_valid(me) or me.get("snow") == null or me.is_dead:
		return
	if int(me.snow.capsule) >= 0:
		_shelter_say("Капсула: лавина сюда не достанет.   E — вылезти")
		return
	if me.snow.busy() or Time.get_ticks_msec() - int(me.snow.cap_exit_ms) < 600:
		return
	var best := -1
	var bd := 2.6
	for i in capsules.size():
		var hp: Vector3 = (capsules[i][0] as Transform3D) * Vector3(0.0, 0.3, 1.8)
		var dd := Vector2(hp.x - me.global_position.x, hp.z - me.global_position.z).length()
		if dd < bd and absf(hp.y - me.global_position.y) < 3.0:
			bd = dd
			best = i
	if best < 0:
		return
	if _capsule_taken(best, me):
		_shelter_say("Капсула занята — место только на одного")
		return
	_shelter_say("E — залезть в капсулу-убежище")
	if me._just("interact"):
		me.snow.enter_capsule(best, capsules[best][0], capsules[best][2])


func _update_capsules(delta: float) -> void:
	for i in capsules.size():
		var c: Array = capsules[i]
		var taken := _capsule_taken(i)
		var pv: Node3D = c[1]
		pv.rotation.x = move_toward(pv.rotation.x, 0.0 if taken else -1.85, delta * 3.5)
		var bm: StandardMaterial3D = c[3]
		bm.emission_energy_multiplier = 0.4 + 3.0 * maxf(sin(_time * 4.0 + i), 0.0)
		(c[4] as OmniLight3D).light_energy = lerpf((c[4] as OmniLight3D).light_energy, 1.3, clampf(delta * 3.0, 0.0, 1.0))
	# сижу в капсуле, а снаружи идёт лавина: по корпусу глухо стучат комья, лампа вздрагивает
	var me := _player
	if me == null or not is_instance_valid(me) or me.get("snow") == null or int(me.snow.capsule) < 0:
		return
	var close := false
	for f in flows:
		if is_instance_valid(f) and f.t >= 0.0 and not (f.stopped and f._age_after > 1.0):
			var bh: float = f.behind_front(me.global_position)
			if bh > -25.0 and bh < 40.0:
				close = true
	_knock_t -= delta
	if close and _knock_t <= 0.0:
		_knock_t = randf_range(0.12, 0.55)
		_kenv = randf_range(0.5, 1.0)
		var lc: OmniLight3D = capsules[int(me.snow.capsule)][4]
		lc.light_energy = randf_range(0.7, 1.0)


const HULL_SHADER := """
shader_type spatial;
// Металл корпуса капсулы; круглая дырка под иллюминатор (в координатах меша)
uniform vec3 albedo : source_color = vec3(0.56, 0.6, 0.64);
uniform float metallic = 0.75;
uniform float roughness = 0.38;
uniform vec3 hole = vec3(0.0, 0.0, 99.0);
uniform float hole_r = 0.0;
uniform float cut_y = -99.0;
varying vec3 mp;
void vertex() { mp = VERTEX; }
void fragment() {
	if (distance(mp, hole) < hole_r || mp.y < cut_y) { discard; }
	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
"""

const QUILT_SHADER := """
shader_type spatial;
render_mode cull_front;
// Изнутри капсулы: мягкая стёганая кожаная обивка с пуговками, тёплый свет; дырка под иллюминатор
uniform vec3 hole = vec3(0.0, 0.0, 99.0);
uniform float hole_r = 0.0;
uniform float cut_y = -99.0;
varying vec3 mp;
void vertex() { mp = VERTEX; }
void fragment() {
	if (distance(mp, hole) < hole_r || mp.y < cut_y) { discard; }
	float a = atan(mp.x, mp.z);
	vec2 uv = vec2(a * 3.2, mp.y * 3.2);
	vec2 d = vec2(uv.x + uv.y, uv.x - uv.y);
	vec2 f = fract(d) - 0.5;
	float seam = smoothstep(0.43, 0.5, max(abs(f.x), abs(f.y)));
	float puff = 1.0 - dot(f, f) * 1.6;
	float btn = 1.0 - smoothstep(0.035, 0.06, length(abs(f) - 0.5));
	vec3 leather = vec3(0.46, 0.21, 0.12);
	vec3 c = leather * (0.62 + 0.42 * puff) * (1.0 - seam * 0.45);
	c = mix(c, vec3(0.75, 0.6, 0.35), btn * 0.8);
	ALBEDO = c;
	ROUGHNESS = mix(0.5, 0.3, btn);
	METALLIC = btn * 0.6;
}
"""

static var _sh_hull: Shader
static var _sh_quilt: Shader


static func hull_material(col: Color, metal: float, rough: float, hole: Vector3, hole_r: float) -> ShaderMaterial:
	if _sh_hull == null:
		_sh_hull = Shader.new()
		_sh_hull.code = HULL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sh_hull
	m.set_shader_parameter("albedo", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("hole", hole)
	m.set_shader_parameter("hole_r", hole_r)
	return m


static func quilt_material(hole: Vector3, hole_r: float) -> ShaderMaterial:
	if _sh_quilt == null:
		_sh_quilt = Shader.new()
		_sh_quilt.code = QUILT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sh_quilt
	m.set_shader_parameter("hole", hole)
	m.set_shader_parameter("hole_r", hole_r)
	return m


static var _plaid: ImageTexture


## Клетчатый плед
static func plaid_texture() -> ImageTexture:
	if _plaid == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		for y in 16:
			for x in 16:
				var a := (x / 4) % 2 == 0
				var b := (y / 4) % 2 == 0
				var c := Color(0.62, 0.12, 0.1)
				if a and b:
					c = Color(0.18, 0.32, 0.2)
				elif a or b:
					c = Color(0.42, 0.16, 0.12)
				if x % 4 == 0 or y % 4 == 0:
					c = c.lerp(Color(0.9, 0.8, 0.5), 0.35)
				img.set_pixel(x, y, c)
		_plaid = ImageTexture.create_from_image(img)
	return _plaid


func _capsule(s: float, lat: float) -> void:
	var cx := W.center_x(s)
	var z := W.z_of(s)
	var pos := Vector3(cx + lat, 0.0, z)
	# стоит на полозьях чуть над снегом: пол внутри выше земли (снег не лезет внутрь)
	pos.y = maxf(_gy(pos.x, pos.z), maxf(_gy(pos.x + 1.6, pos.z), _gy(pos.x - 1.6, pos.z))) + 0.22
	var bz := Vector3(-signf(lat), 0.0, 0.0)          # люк смотрит на тропу
	var bx := Vector3.UP.cross(bz)
	var xf := Transform3D(Basis(bx, Vector3.UP, bz), pos)
	var root := Node3D.new()
	root.name = "Capsule%d" % (capsules.size() + 1)
	root.transform = xf
	add_child(root)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.45, 0.08)
	orange.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.15)
	dark.roughness = 0.7
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.6, 0.3)
	brass.metallic = 0.8
	brass.roughness = 0.35
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# корпус: цилиндр с полусферами на концах, лежит вдоль долины; в нём — иллюминатор (дырка + стекло)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 1.05
	cyl.height = 2.6
	cyl.radial_segments = 40
	cyl.cap_top = false
	cyl.cap_bottom = false
	var hull := hull_material(Color(0.56, 0.6, 0.64), 0.75, 0.38, Vector3(0.08, 0.0, 1.05), 0.2)
	_part_mi(root, cyl, hull, Vector3(0.0, 0.85, 0.0), Vector3(0.0, 0.0, PI * 0.5), Vector3.ONE)
	# торцы — полусферы куполом наружу (целые сферы торчали бы внутрь)
	var cap := SphereMesh.new()
	cap.radius = 1.05
	cap.height = 2.1
	cap.radial_segments = 32
	cap.rings = 10
	var hull2 := hull_material(Color(0.56, 0.6, 0.64), 0.75, 0.38, Vector3(0.0, 0.0, 99.0), 0.0)
	hull2.set_shader_parameter("cut_y", 0.0)          # внутреннюю половину не рисую
	for sx in [-1.3, 1.3]:
		_part_mi(root, cap, hull2, Vector3(sx, 0.85, 0.0), Vector3(0.0, 0.0, -PI * 0.5 * signf(sx)), Vector3(1.0, 0.45, 1.0))
	# полосы
	var band := CylinderMesh.new()
	band.top_radius = 1.08
	band.bottom_radius = 1.08
	band.height = 0.2
	band.radial_segments = 32
	band.cap_top = false                 # трубки без донышек — изнутри не перегораживают
	band.cap_bottom = false
	for sx in [-0.95, 0.95]:
		_part_mi(root, band, orange, Vector3(sx, 0.85, 0.0), Vector3(0.0, 0.0, PI * 0.5), Vector3.ONE)
	var band2 := band.duplicate() as CylinderMesh
	band2.height = 0.07
	for sx in [-1.1, 1.1]:
		_part_mi(root, band2, dark, Vector3(sx, 0.85, 0.0), Vector3(0.0, 0.0, PI * 0.5), Vector3.ONE)
	# изнутри — стёганая обивка (с дыркой под иллюминатор)
	var icyl := CylinderMesh.new()
	icyl.top_radius = 1.0
	icyl.bottom_radius = 1.0
	icyl.height = 2.6
	icyl.radial_segments = 40
	icyl.rings = 6
	icyl.cap_top = false
	icyl.cap_bottom = false
	_part_mi(root, icyl, quilt_material(Vector3(0.08, 0.0, 1.0), 0.19), Vector3(0.0, 0.85, 0.0), Vector3(0.0, 0.0, PI * 0.5), Vector3.ONE)
	var qcap := quilt_material(Vector3(0.0, 0.0, 99.0), 0.0)
	qcap.set_shader_parameter("cut_y", 0.0)
	for sx in [-1.3, 1.3]:
		_part_mi(root, cap, qcap, Vector3(sx, 0.85, 0.0), Vector3(0.0, 0.0, -PI * 0.5 * signf(sx)), Vector3(0.965, 0.42, 0.965))
	# иллюминатор в корпусе: стекло и латунная рамка
	var gd := CylinderMesh.new()
	gd.top_radius = 0.2
	gd.bottom_radius = 0.2
	gd.height = 0.01
	_part_mi(root, gd, glass, Vector3(0.0, 0.93, 1.03), Vector3(PI * 0.5, 0.0, 0.0), Vector3.ONE)
	var pr := TorusMesh.new()
	pr.inner_radius = 0.19
	pr.outer_radius = 0.25
	pr.rings = 20
	_part_mi(root, pr, brass, Vector3(0.0, 0.93, 0.985), Vector3(PI * 0.5, 0.0, 0.0), Vector3(1.0, 0.5, 1.0))
	# рама люка и люк на петле сверху (в люке — тоже окошко)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.6
	ring.outer_radius = 0.74
	ring.rings = 24
	_part_mi(root, ring, orange, Vector3(0.0, 0.93, 1.09), Vector3(PI * 0.5, 0.0, 0.0), Vector3(1.0, 0.6, 1.0))
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 1.55, 1.07)
	root.add_child(pivot)
	var door := CylinderMesh.new()
	door.top_radius = 0.62
	door.bottom_radius = 0.62
	door.height = 0.1
	door.radial_segments = 28
	_part_mi(pivot, door, hull_material(Color(0.6, 0.63, 0.67), 0.75, 0.35, Vector3(0.0, 0.0, -0.07), 0.17), Vector3(0.0, -0.62, 0.03), Vector3(PI * 0.5, 0.0, 0.0), Vector3.ONE)
	var gd2 := CylinderMesh.new()
	gd2.top_radius = 0.18
	gd2.bottom_radius = 0.18
	gd2.height = 0.01
	_part_mi(pivot, gd2, glass, Vector3(0.0, -0.55, 0.03), Vector3(PI * 0.5, 0.0, 0.0), Vector3.ONE)
	var pr2 := TorusMesh.new()
	pr2.inner_radius = 0.17
	pr2.outer_radius = 0.23
	pr2.rings = 20
	for zz in [-0.03, 0.09]:
		_part_mi(pivot, pr2, brass, Vector3(0.0, -0.55, zz), Vector3(PI * 0.5, 0.0, 0.0), Vector3(1.0, 0.5, 1.0))
	var hb := BoxMesh.new()
	hb.size = Vector3(0.36, 0.06, 0.08)
	_part_mi(pivot, hb, dark, Vector3(0.0, -1.0, 0.12), Vector3.ZERO, Vector3.ONE)
	# уют: подушка-сиденье, плед в клетку, термос с кружкой, лампа в сеточке, фото на стенке
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color(0.5, 0.16, 0.12)
	fabric.roughness = 0.9
	var floor_b := BoxMesh.new()
	floor_b.size = Vector3(2.5, 0.08, 1.5)
	_part_mi(root, floor_b, dark, Vector3(0.0, -0.1, 0.0), Vector3.ZERO, Vector3.ONE)
	var skid := BoxMesh.new()
	skid.size = Vector3(2.6, 0.3, 0.14)
	for sz in [-0.6, 0.6]:
		_part_mi(root, skid, dark, Vector3(0.0, -0.32, sz), Vector3.ZERO, Vector3.ONE)
	var cush := BoxMesh.new()
	cush.size = Vector3(1.5, 0.16, 1.2)
	_part_mi(root, cush, fabric, Vector3(0.0, -0.06, -0.05), Vector3.ZERO, Vector3.ONE)
	var plaid := StandardMaterial3D.new()
	plaid.albedo_texture = plaid_texture()
	plaid.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plaid.uv1_scale = Vector3(2.0, 2.0, 2.0)
	plaid.roughness = 0.95
	var pb := BoxMesh.new()
	pb.size = Vector3(0.55, 0.14, 0.42)
	_part_mi(root, pb, plaid, Vector3(-0.85, 0.09, -0.35), Vector3(0.0, 0.25, 0.0), Vector3.ONE)
	_part_mi(root, pb, plaid, Vector3(-0.83, 0.2, -0.33), Vector3(0.0, 0.1, 0.0), Vector3(0.95, 0.8, 0.95))
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.16, 0.36, 0.22)
	green.metallic = 0.5
	green.roughness = 0.4
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.8, 0.82, 0.85)
	silver.metallic = 0.9
	silver.roughness = 0.25
	var th := CylinderMesh.new()
	th.top_radius = 0.065
	th.bottom_radius = 0.07
	th.height = 0.34
	_part_mi(root, th, green, Vector3(0.9, 0.19, 0.45), Vector3.ZERO, Vector3.ONE)
	var thc := CylinderMesh.new()
	thc.top_radius = 0.072
	thc.bottom_radius = 0.072
	thc.height = 0.08
	_part_mi(root, thc, silver, Vector3(0.9, 0.4, 0.45), Vector3.ZERO, Vector3.ONE)
	var cup := CylinderMesh.new()
	cup.top_radius = 0.055
	cup.bottom_radius = 0.045
	cup.height = 0.08
	_part_mi(root, cup, silver, Vector3(0.74, 0.06, 0.55), Vector3.ZERO, Vector3.ONE)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.85, 0.55)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.72, 0.38)
	bulb_mat.emission_energy_multiplier = 2.5
	var bulb2 := SphereMesh.new()
	bulb2.radius = 0.06
	bulb2.height = 0.12
	_part_mi(root, bulb2, bulb_mat, Vector3(0.0, 1.66, -0.45), Vector3.ZERO, Vector3.ONE)
	var cage := TorusMesh.new()
	cage.inner_radius = 0.075
	cage.outer_radius = 0.09
	_part_mi(root, cage, brass, Vector3(0.0, 1.66, -0.45), Vector3.ZERO, Vector3.ONE)
	_part_mi(root, cage, brass, Vector3(0.0, 1.66, -0.45), Vector3(PI * 0.5, 0.0, 0.0), Vector3.ONE)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.3
	lamp.omni_range = 3.2
	lamp.position = Vector3(0.0, 1.5, -0.4)
	root.add_child(lamp)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.26, 0.14)
	var frame := BoxMesh.new()
	frame.size = Vector3(0.26, 0.2, 0.02)
	var ph := MeshInstance3D.new()
	ph.mesh = frame
	ph.material_override = wood
	root.add_child(ph)
	# фото — на стенке справа от люка, смотрит внутрь
	var wall_p := Vector3(0.62, 1.05, 0.78)
	ph.position = wall_p
	ph.basis = Basis.looking_at(Vector3(0.0, 0.18, 1.0).normalized(), Vector3.UP)
	var pic := Label3D.new()
	pic.text = "Борея-7\nдома ждут"
	pic.font_size = 11
	pic.outline_size = 0
	pic.modulate = Color(0.25, 0.18, 0.12)
	pic.pixel_size = 0.004
	pic.position = wall_p + ph.basis.z * 0.013
	pic.basis = ph.basis
	var pic_bg := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(0.22, 0.16)
	pic_bg.mesh = pq
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.92, 0.86, 0.72)
	pic_bg.material_override = paper
	pic_bg.position = wall_p + ph.basis.z * 0.011
	pic_bg.basis = ph.basis
	root.add_child(pic_bg)
	root.add_child(pic)
	# мачта с мигалкой и надпись — видно издалека
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.06
	pole.height = 2.4
	_part_mi(root, pole, orange, Vector3(0.9, 2.9, -0.4), Vector3.ZERO, Vector3.ONE)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.55, 0.1)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.5, 0.1)
	var bulb := SphereMesh.new()
	bulb.radius = 0.13
	bulb.height = 0.26
	_part_mi(root, bulb, bmat, Vector3(0.9, 4.15, -0.4), Vector3.ZERO, Vector3.ONE)
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.55, 0.15)
	bl.light_energy = 1.2
	bl.omni_range = 7.0
	bl.position = Vector3(0.9, 4.3, -0.4)
	root.add_child(bl)
	var lb := Label3D.new()
	lb.text = "КАПСУЛА\nна одного"
	lb.font_size = 44
	lb.outline_size = 10
	lb.modulate = Color(1.0, 0.7, 0.25)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position = Vector3(0.0, 3.3, 0.3)
	lb.visibility_range_end = 220.0
	root.add_child(lb)
	# опора: сплошная «пилюля»
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := CapsuleShape3D.new()
	shp.radius = 1.05
	shp.height = 4.7
	cs.shape = shp
	cs.position = Vector3(0.0, 0.85, 0.0)
	cs.rotation = Vector3(0.0, 0.0, PI * 0.5)
	body.add_child(cs)
	root.add_child(body)
	capsules.append([xf, pivot, body.get_rid(), bmat, lamp])
	# у капсулы снег не насыпается — люк не завалит
	if layer:
		layer.no_zones.append([Vector2(pos.x, pos.z), 3.0, 7.0])


func _part_mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3, sc: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	parent.add_child(mi)
	return mi



## Сколько роботов не спят — по числу игроков (людей): 1 — 8, 2 — 13, 3 — 18, 4 — 23. Гнёзда выбираются
## равномерно вдоль тихого участка. Считают все одинаково (по составу игроков).
func _update_robot_count() -> void:
	var humans := 0
	for d in get_tree().get_nodes_in_group("player"):
		if not bool(d.get("is_bot")):
			humans += 1
	humans = maxi(humans, 1)
	var active := clampi(ROBOTS_BASE + ROBOTS_PER * (humans - 1), ROBOTS_BASE, ROBOTS_MAX)
	ROBOT.max_awake = 3 + 2 * humans
	var on := {}
	for i in active:
		on[roundi(float(i) * (ROBOTS_MAX - 1) / maxf(active - 1, 1.0))] = true
	for rb in get_tree().get_nodes_in_group("snow_robot"):
		var want_sleep := not on.has(int(rb.index))
		if bool(rb.dormant) != want_sleep:
			rb.set_dormant(want_sleep)
