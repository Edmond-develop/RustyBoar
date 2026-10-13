extends Node
## ВРЕМЕННО, для проверки: «мозг» бота-курьера — такого же дрона в скафандре,
## как у игроков (узел "Brain" внутри дрона). Есть только у хоста.
## Бот «жмёт кнопки» сам: ходит, бегает, прыгает, берёт грузы, кидает верёвку.
##
## Команды — панель ботов (B) или клавиши 1–6 (выбранному боту):
##  за мной · стой тут · иди ко мне · иди туда, куда смотрю · помоги нести ·
##  прыгай в полынью (и зови на помощь) · подними меня и кинь · без сил (обмякни) ·
##  замёрзни в глыбу.  G — переселиться в бота и управлять им самому.
## Сам по себе: если ты в воде — бежит спасать (рукой с края или верёвкой);
## если тащишь тяжёлый ящик один — подходит и берётся за другой конец;
## у Ледяного вала — сам встаёт в луч маяка (помогает с «Живыми зеркалами»).

const LINES := {
	"hello": ["Курьер на связи!", "Бот прибыл. Где груз?", "Готов работать!"],
	"follow": ["Иду за тобой.", "Не отстаю!", "Веди."],
	"stay": ["Стою тут.", "Жду здесь.", "Ок, никуда не ухожу."],
	"carry": ["Беру с другой стороны!", "Раз-два — взяли!", "Держу свой край."],
	"water": ["Ныряю!", "А вода холодная?..", "Спасай меня потом!"],
	"help": ["ПОМОГИТЕ!", "Тону-у-у!", "Вытащи меня!", "Холодно!!"],
	"throw": ["Сейчас полетаешь!", "Держись крепче!", "Раз, два… ТРИ!"],
	"goto": ["Иду туда.", "Понял, бегу.", "Есть!"],
	"lifted": ["Эй! Поставь!", "Ой-ой-ой, высоко!", "Ну всё, кидай уже!"],
	"roped": ["Хватаюсь!", "Тяни!", "Держу верёвку!"],
	"rescue": ["Держись, вытащу!", "Сейчас, сейчас!", "Хватай руку!"],
	"no_hole": ["Полыньи рядом нет.", "Тут не во что нырнуть."],
	"thanks": ["Спасибо! Брр…", "Спас! С меня запчасть.", "Ух, живой!"],
	"come": ["Бегу!", "Уже иду!", "Тут я, тут!"],
	"faint": ["Всё… сил нет…", "Я полежу…", "Батарейка на нуле…"],
	"freeze": ["Брррр…", "Хо-хо-холодно…", "Застыва-а-аю…"],
	"gate": ["Встаю в луч!", "Отражу куда надо!", "Горячо, но держусь!"],
	"wait": ["Жду спасения!", "Я тут побарахтаюсь…"],
	"repair": ["Держись, прикручу!", "Сейчас как новенький будешь!", "Где тут резьба…", "Крути-верти!"],
	"iced": ["Разбей лёд! Жми R рядом!", "Я в глыбе… выручай!", "Брр… постучи по мне!", "Катни меня к жаровне!"],
}

var bot: CharacterBody3D          ## дрон бота (player.gd)
var index := 1
var command := "follow"
var calling_help := false         ## машет рукой из воды
var _goto := Vector3.INF
var _stuck_t := 0.0
var _jump_cool := 0.0
var _carry_dist := 2.6
var _crate: Parcel = null
var _phase_t := 0.0
var _water_spot := Vector3.INF
var _help_t := 0.0
var _was_wet := false
var _bubble: Label3D
var _bubble_t := 0.0


func _ready() -> void:
	bot = get_parent() as CharacterBody3D
	_bubble = Label3D.new()
	_bubble.font_size = 34
	_bubble.outline_size = 9
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.position = Vector3(0, 2.55, 0)
	bot.add_child.call_deferred(_bubble)
	say("hello")


func say(key: String) -> void:
	if _bubble and LINES.has(key):
		_bubble.text = LINES[key].pick_random()
		_bubble_t = 3.0


func set_command(cmd: String, point := Vector3.INF) -> void:
	command = cmd
	_goto = point
	_phase_t = 0.0
	_water_spot = Vector3.INF
	_was_wet = false
	bot.downed = cmd == "faint"
	if cmd == "freeze" and not bot.is_frozen:
		bot.frost = bot.frost_max
		bot._freeze_solid()
	if cmd != "carry" and bot.held_parcel != null:
		bot.bot_press("interact")        # отпустить груз
	if bot.rope.state != bot.rope.S.NONE:
		bot.rope._detach()
	say(cmd)


func on_lifted(_holder: Node) -> void:
	say("lifted")


func on_roped(_owner: Node, _mode: int) -> void:
	say("roped")


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		_bubble.modulate.a = clampf(_bubble_t, 0.0, 1.0)


func _owner() -> Node3D:
	return Network.local_player as Node3D


## Человек отдал управление обратно: в воде — ждём спасения, иначе стоим
func on_released() -> void:
	if bot.is_swimming or bot.is_diving:
		command = "water"
		_was_wet = true
		say("wait")
	else:
		command = "stay"
	_phase_t = 0.0


func _physics_process(delta: float) -> void:
	if bot.controlled:
		return
	bot.bot_held.clear()
	bot.bot_move = Vector2.ZERO
	calling_help = false
	_jump_cool -= delta
	# брошенная верёвка лежит — сматываем (ПКМ)
	if bot.rope.state == bot.rope.S.LYING or bot.rope.state == bot.rope.S.RETURN:
		bot.bot_held["use_alt"] = true
	var o := _owner()
	if o == bot:
		return
	if o == null or bot.is_dead or bot.carried_by != null or bot.rescue_role != 0 or bot.is_frozen or bot.downed:
		if bot.is_frozen and _bubble_t <= 0.0 and randf() < 0.008:
			# изнутри лёд не разбить — зовём на помощь
			say("iced")
		if command == "freeze" and not bot.is_frozen:
			command = "follow"
			say("thanks")
		return
	_phase_t += delta
	var far: float = _flat(o.global_position, bot.global_position)
	if far > 70.0 and command in ["follow", "carry", "throw"]:
		_teleport_near(o)
		return

	# сам упал в воду (не по команде) — выбираемся
	if (bot.is_swimming or bot.is_diving) and command != "water":
		_self_rescue(o)
		return
	# у хозяина нет руки/ноги — находим деталь, несём и прикручиваем
	if command in ["follow", "carry", "stay"] and int(o.limb_mask) != 15 and bot.arms_count() > 0 \
			and not bot.is_swimming and not bot.is_diving and not o.is_frozen:
		if _repair_owner(o, delta):
			return
	if bot.held_limb != null and (o.limb_mask == 15 or int(bot.held_limb.owner_id) != int(o.peer_id)):
		bot._drop_limb(Vector3.ZERO)       # чужая/лишняя деталь — кладём
	# хозяин вмёрз в глыбу на суше — подбегаем и бьём по льду
	if command in ["follow", "carry", "stay"] and o.is_frozen and not o.is_diving \
			and not bot.is_swimming and not bot.is_diving:
		if _walk_to(o.global_position, true, 2.05, delta):
			var tf := o.global_position - bot.global_position
			bot.visual.rotation.y = atan2(-tf.x, -tf.z)
			if _jump_cool <= 0.0:
				_jump_cool = 0.4
				bot.bot_press("shake_ice")
				if _bubble_t <= 0.0:
					say("rescue")
		return
	# хозяин в воде — спасаем
	if command in ["follow", "carry", "stay"] and (o.is_swimming or o.is_diving) and o.rescue_role == 0 \
			and not bot.is_swimming and not bot.is_diving:
		_rescue_owner(o, delta)
		return
	if bot.rope.state == bot.rope.S.ATTACHED and bot.rope.mode == bot.rope.M.RESCUE and command != "water":
		bot.bot_held["use_alt"] = true
		return

	match command:
		"follow":
			if not _gate_duty(o, delta):
				_follow(o, delta)
		"come":
			if _walk_to(o.global_position, true, 1.6, delta):
				command = "stay"
		"stay":
			pass
		"carry":
			_carry(o, delta)
		"water":
			_water(delta)
		"throw":
			_throw_owner(o, delta)
		"goto":
			if _goto == Vector3.INF or _walk_to(_goto, true, 0.8, delta):
				command = "stay"


# ---------------------------------------------------------------------------
func _follow(o: Node3D, delta: float) -> void:
	# хозяин тащит тяжёлый ящик один — помогаем
	var hp: Parcel = o.get("held_parcel")
	if hp != null and hp.required_carriers > 1 and not hp.is_lifted():
		command = "carry"
		say("carry")
		return
	var ob: Basis = o.get("visual").global_basis
	var back := ob.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var side := Vector3(-back.z, 0.0, back.x)
	var offs: float = [-1.7, 1.7, 0.0][(index - 1) % 3]
	var target := o.global_position + back * (2.2 + (1.4 if offs == 0.0 else 0.0)) + side * offs
	var d := _flat(target, bot.global_position)
	_walk_to(target, d > 6.0, 0.9, delta)


func _carry(o: Node3D, delta: float) -> void:
	if bot.held_parcel != null:
		var c: Parcel = bot.held_parcel
		if c.is_lifted():
			# несём вдвоём: держим расстояние до хозяина
			var away := bot.global_position - o.global_position
			away.y = 0.0
			var desired := o.global_position + away.normalized() * _carry_dist
			_walk_to(desired, false, 0.2, delta)
		elif _phase_t > 1.0 and not c.holders.has(o.get("peer_id")):
			pass   # ждём, пока хозяин возьмётся с другой стороны
		return
	# ещё не держим: ищем тяжёлый ящик рядом с хозяином
	if _crate == null or not is_instance_valid(_crate) or _crate.is_delivered or _crate.holders.size() >= 2:
		_crate = _find_crate(o)
		if _crate == null:
			command = "follow"
			return
	if _crate.holders.size() >= 2:
		_crate = null
		command = "follow"
		return
	var ext: Vector3 = bot.suit.extents(_crate)
	var px: Vector3 = _crate.global_basis.x.normalized()
	var ref: Vector3 = o.global_position if _crate.holders.has(o.get("peer_id")) else bot.global_position
	var sg := signf((ref - _crate.global_position).dot(px))
	if sg == 0.0:
		sg = 1.0
	if _crate.holders.has(o.get("peer_id")):
		sg = -sg            # хозяин держит свой конец — идём к другому
	var spot := _crate.global_position + px * sg * (ext.x + 0.8)
	if _walk_to(spot, true, 0.35, delta):
		var to := _crate.global_position - bot.global_position
		bot.visual.rotation.y = atan2(-to.x, -to.z)
		if _phase_t > 0.3:
			_phase_t = 0.0
			bot.bot_press("interact")
			_carry_dist = maxf(_flat(o.global_position, bot.global_position), 2.0)


func _find_crate(o: Node3D) -> Parcel:
	var best: Parcel = null
	var bd := 16.0
	for p in get_tree().get_nodes_in_group("parcel"):
		var c := p as Parcel
		if c.required_carriers < 2 or c.is_delivered:
			continue
		var d := _flat(c.global_position, o.global_position)
		if c.holders.has(o.get("peer_id")):
			d -= 10.0
		if d < bd:
			bd = d
			best = c
	return best


func _water(delta: float) -> void:
	if _was_wet and not bot.is_swimming and not bot.is_diving:
		# вытащили — спасибо, идём за хозяином
		_was_wet = false
		command = "follow"
		say("thanks")
		return
	if bot.is_swimming or bot.is_diving:
		_was_wet = true
		if bot.is_diving:
			bot.bot_held["jump"] = true    # всплываем
		else:
			calling_help = true
			_help_t -= delta
			if _help_t <= 0.0:
				_help_t = 3.5
				say("help")
		return
	if _water_spot == Vector3.INF:
		var lake := get_tree().get_first_node_in_group("ice_lake")
		var best := Vector3.INF
		var bd := 160.0
		if lake:
			var thin: Array = lake.get("thin_patches")
			var bp := bot.global_position
			for c in lake.get("circles"):
				var cv: Vector3 = c
				if thin.has(cv):
					continue          # тонкий лёд ещё цел — это не полынья
				var d := Vector2(cv.x - bp.x, cv.y - bp.z).length()
				if d < bd:
					bd = d
					best = Vector3(cv.x, bp.y, cv.y)
			for r in lake.get("rects"):
				var rv: Vector4 = r
				var q := Vector3(clampf(bp.x, rv.x + 1.5, rv.y - 1.5), bp.y, clampf(bp.z, rv.z + 1.5, rv.w - 1.5))
				var d := Vector2(q.x - bp.x, q.z - bp.z).length()
				if d < bd:
					bd = d
					best = q
		if best == Vector3.INF:
			say("no_hole")
			command = "follow"
			return
		_water_spot = best
	_walk_to(_water_spot, true, 0.1, delta)
	if _phase_t > 25.0:
		command = "follow"


func _throw_owner(o: Node3D, delta: float) -> void:
	if bot.held_friend == o:
		# несём пару шагов вперёд и бросаем
		var fwd: Vector3 = -bot.visual.global_basis.z
		_walk_to(bot.global_position + fwd * 3.0, false, 0.1, delta)
		if _phase_t > 1.3:
			bot.bot_press("throw")
			command = "follow"
		return
	if _walk_to(o.global_position, false, 1.25, delta):
		var to := o.global_position - bot.global_position
		bot.visual.rotation.y = atan2(-to.x, -to.z)
		if _phase_t > 0.4:
			_phase_t = 0.0
			bot.bot_press("interact")
			say("throw")
	if _phase_t > 12.0:
		command = "follow"


## У Ледяного вала: встать в луч маяка (как раньше делал летающий бот)
func _gate_duty(o: Node3D, delta: float) -> bool:
	for g in get_tree().get_nodes_in_group("coop_gate"):
		if bool(g.get("is_open")):
			continue
		if (g as Node3D).global_position.distance_to(o.global_position) > 70.0:
			continue
		var t: Vector3 = g.bot_target(bot, o)
		if t == Vector3.INF:
			return false
		if _phase_t > 0.0 and _flat(t, bot.global_position) > 6.0 and _bubble_t <= 0.0:
			say("gate")
		_walk_to(t, _flat(t, bot.global_position) > 5.0, 0.1, delta)
		return true
	return false


## Сам в воде: из-подо льда — к полынье, на поверхности — к краю и на лёд
func _self_rescue(o: Node3D) -> void:
	if bot.rope.roped_by(bot) != null:
		return                         # держусь за верёвку — меня тянут
	if bot.is_diving:
		bot.bot_held["jump"] = true
		var hole: Vector3 = bot._nearest_hole()
		if hole != Vector3.INF:
			var to := hole - bot.global_position
			to.y = 0.0
			if to.length() > 0.5:
				bot.camera_pivot.rotation.y = atan2(-to.x, -to.z)
				bot.bot_move = Vector2(0.0, -1.0)
		return
	var lake := get_tree().get_first_node_in_group("ice_lake")
	var dir := o.global_position - bot.global_position
	dir.y = 0.0
	var edge: Vector3 = lake.nearest_ice(bot.global_position, 8.0, dir.normalized()) if lake else Vector3.INF
	if edge != Vector3.INF:
		var to := edge - bot.global_position
		to.y = 0.0
		bot.camera_pivot.rotation.y = atan2(-to.x, -to.z)
		bot.bot_move = Vector2(0.0, -1.0)
	if Engine.get_physics_frames() % 20 == 0:
		bot.bot_press("jump")


## Хозяин в воде: с поверхности — за руку с края, из-подо льда — верёвкой
func _repair_owner(o: Node3D, delta: float) -> bool:
	var part: Node3D = bot.held_limb
	if part != null and int(part.owner_id) == int(o.peer_id) and not o.has_limb(part.kind):
		if _walk_to(o.global_position, true, 1.5, delta):
			var to := o.global_position - bot.global_position
			bot.visual.rotation.y = atan2(-to.x, -to.z)
			bot.bot_held["interact"] = true
			if bot._repair_target == null and _jump_cool <= 0.0:
				_jump_cool = 0.5
				bot.bot_press("interact")
				if _bubble_t <= 0.0:
					say("repair")
		return true
	# ищем лежащую деталь хозяина
	var best: Node3D = null
	var bd := 60.0
	for p in get_tree().get_nodes_in_group("limb_part"):
		if int(p.owner_id) != int(o.peer_id) or o.has_limb(p.kind):
			continue
		if p.holder != null and is_instance_valid(p.holder):
			continue
		var d := (p as Node3D).global_position.distance_to(bot.global_position)
		if d < bd:
			bd = d
			best = p
	if best == null:
		return false
	if _walk_to(best.global_position, true, 0.9, delta):
		if _jump_cool <= 0.0:
			_jump_cool = 0.4
			bot.bot_press("interact")
	return true


func _rescue_owner(o: Node3D, delta: float) -> void:
	var rope = bot.rope
	if rope.state == rope.S.ATTACHED and rope.target == o:
		bot.bot_held["use_alt"] = true
		return
	if rope.state != rope.S.NONE:
		return
	var lake := get_tree().get_first_node_in_group("ice_lake")
	if lake == null:
		return
	var from_owner := bot.global_position - o.global_position
	from_owner.y = 0.0
	var dir := from_owner.normalized() if from_owner.length() > 0.1 else Vector3.BACK
	var dist := _flat(o.global_position, bot.global_position)
	var to := o.global_position - bot.global_position
	# рядом с краем и друг на поверхности — за руку
	if o.is_swimming and dist < 4.6 and bot.is_on_floor():
		bot.visual.rotation.y = atan2(-to.x, -to.z)
		if _jump_cool <= 0.0:
			_jump_cool = 0.6
			bot.bot_press("interact")
			say("rescue")
		return
	# не подойти (подо льдом, большая полынья) — верёвкой
	if dist < 12.5 and (bot.is_on_floor() or _phase_t > 4.0) and (o.is_diving or _phase_t > 2.5):
		bot.visual.rotation.y = atan2(-to.x, -to.z)
		rope.throw_at(o)
		say("rescue")
		_phase_t = 0.0
		return
	var edge: Vector3 = lake.nearest_ice(o.global_position, 5.0, dir)
	var stand := o.global_position + dir * 7.0
	if edge != Vector3.INF and _flat(edge, o.global_position) < 4.2:
		stand = edge + dir * 0.6
	if _walk_to(stand, true, 0.3, delta):
		pass


# ---------------------------------------------------------------------------
## Идти к точке. true — уже на месте.
func _walk_to(p: Vector3, run: bool, stop: float, delta: float) -> bool:
	var to := p - bot.global_position
	to.y = 0.0
	var d := to.length()
	if d < stop:
		_stuck_t = 0.0
		return true
	bot.camera_pivot.rotation.y = atan2(-to.x, -to.z)
	bot.bot_move = Vector2(0.0, -clampf(d / 1.2, 0.12 if stop < 0.3 else 0.35, 1.0))
	if run and d > 5.0:
		bot.bot_held["sprint"] = true
	var hv := Vector2(bot.velocity.x, bot.velocity.z).length()
	if hv < 0.5 and d > 1.0:
		_stuck_t += delta
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	if _stuck_t > 0.5 and _jump_cool <= 0.0 and bot.is_on_floor():
		_jump_cool = 1.2
		bot.bot_press("jump")
	if _stuck_t > 4.0 and d > 5.0:
		_stuck_t = 0.0
		bot.global_position = p + Vector3.UP * 0.6
		bot.velocity = Vector3.ZERO
	return false


func _teleport_near(o: Node3D) -> void:
	var back: Vector3 = o.get("visual").global_basis.z
	back.y = 0.0
	bot.global_position = o.global_position + back.normalized() * 2.5 + Vector3.UP * 0.8
	bot.velocity = Vector3.ZERO


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
