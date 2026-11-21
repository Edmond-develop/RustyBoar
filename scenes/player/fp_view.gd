extends Node
## Вид от первого лица (шаг 59). L — переключить. Узел "FPView" в каждом дроне, работает у того,
## которым управляет человек за этим компьютером.
##
##  * Камера — в голове дрона, за стеклом шлема (голова и всё на ней скрыты только для своей камеры:
##    слой 20; другие игроки голову видят, тень от неё есть).
##  * Видно всё своё тело: посмотришь вниз — ноги, корпус, руки с посылкой, деталью или роботом над головой.
##    Тело всегда смотрит туда же, куда камера; ноги шагают в сторону движения (вбок, назад).
##  * Мягкое покачивание: камера едет за головой, но шаг сглажен; при приземлении — толчок вниз.
##  * В особых состояниях (бросили, кувырок, на руках у друга, лавина, сугроб, поломка, на пузе) —
##    тоже от первого лица: взгляд ведёт голова, мышь поворачивает его относительно головы.

const HIDE_LAYER := 1 << 19        ## слой 20: голова своего дрона (своя камера в FP его не рисует)
const ALL_LAYERS := 0xFFFFF

static var enabled := false        ## общий для всех дронов на этом компьютере (переселился в бота — вид тот же)

var p: CharacterBody3D             ## player.gd
var _active := false
var _eye := Vector3.ZERO
var _eye_y := 0.0
var _head_b := Basis.IDENTITY
var _follow_k := 0.0
var _hide_t := 0.0
var _hidden := false
var _dip := 0.0
var _dip_v := 0.0
var _saved_near := 0.05
var _saved_pitch := Vector2(-70.0, 35.0)
var _rel_s := Vector3.ZERO             ## сглаженное положение глаза относительно дрона (лавина, капсула)
var _labels: Array[Label3D] = []       ## надписи посылки в руках (цена…) — для своей камеры спрятаны
var _label_parcel: Node = null
var phys_cam := Transform3D.IDENTITY     ## шаг 93: камера на шаге физики (без сглаживания между кадрами) — для рук


func _ready() -> void:
	p = get_parent() as CharacterBody3D
	process_physics_priority = 60          # после дрона и анимации скафандра
	process_priority = 60
	p.landed.connect(_on_landed)
	get_tree().physics_frame.connect(_restore_visual)


## Плавность при любой частоте экрана: физика идёт 60 раз в секунду, а кадров может быть больше —
## между шагами физики сдвигаю камеру и своё тело вместе на долю шага назад (как будто они двигаются
## непрерывно). Перед каждым шагом физики тело возвращается на место.
var _root_prev := Vector3.ZERO
var _root_cur := Vector3.ZERO
var _vis_off := Vector3.ZERO


func _restore_visual() -> void:
	if _vis_off != Vector3.ZERO and is_instance_valid(p) and p.visual:
		p.visual.global_position -= _vis_off
	_vis_off = Vector3.ZERO


func _on_landed(fall_speed: float) -> void:
	if _active:
		_dip_v -= clampf(fall_speed * 0.05, 0.0, 0.7)


func _special() -> bool:
	# лавина несёт и сугроб — НЕ особое: смотрю мышью свободно, горизонт ровный (камера не следует за телом)
	return p.carried_by != null or p._tumble or p._flop_t > 0.0 or p.is_dead or p.belly or p._belly_k > 0.05 \
		or p.rescue_role == 2 or p.is_frozen


func _physics_process(delta: float) -> void:
	if p.controlled and not p.input_blocked and Input.is_action_just_pressed("view_toggle"):
		enabled = not enabled
	var want: bool = enabled and p.controlled and p.suit != null and p.suit.get("head") != null
	if want != _active:
		_set_active(want)
	if not _active:
		if _hidden and not p.controlled:
			_hide_head(false)
		if _label_parcel != null:
			_hide_parcel_labels(null)
		return
	_hide_parcel_labels(_held_parcel())
	_hide_t -= delta
	if _hide_t <= 0.0:
		_hide_t = 0.3                   # новые сосульки, иней на шлеме — тоже прячем
		_hide_head(true)
	var head: Node3D = p.suit.head
	var hx := head.global_transform.orthonormalized()
	var special := _special()
	# смотрю вниз — «наклоняюсь» вперёд над грудью (иначе вид закрывают свои плечи и грудь), видны ноги
	var down := smoothstep(0.15, 1.35, -float(p.camera_pivot.rotation.x)) if not special else 0.0
	var fwd_b := Basis(Vector3.UP, p.camera_pivot.global_rotation.y)
	# шаг 70: наклоняюсь дальше (0.35 м) — видно грудь, пояс, обе ноги и руки по бокам
	var eye := hx.origin + hx.basis * Vector3(0.0, 0.03, -0.06) + fwd_b * Vector3(0.0, 0.06 * down, -0.35 * down)
	if p.snow.swept:
		eye += fwd_b * Vector3(0.0, 0.16, -0.28)
	# шаг 106: кручу лебёдку / обвязываюсь — руки впереди, наплечники поднялись: глаз чуть вперёд и выше
	var mp0 := int(p.snow.get("mpose"))
	if mp0 == 25 or mp0 == 26 or mp0 == 29:
		var bf: Vector3 = -(p.visual.global_basis.z)
		bf.y = 0.0
		eye += bf.normalized() * 0.2 + Vector3.UP * 0.07       # еду полулёжа: глаз чуть выше и впереди — воротник и грудь не заслоняют
	# шаг 123: вишу на ледорубах / вылезаю / на ноге друга — лицо у самой скалы: глаз отодвигаю от стены
	# (иначе камера оказывалась в скале — «вид под текстурой»), видно стену, ледорубы и руки
	if mp0 == 17 or mp0 == 19 or mp0 == 32:
		var bz: Vector3 = p.visual.global_basis.z
		bz.y = 0.0
		eye += bz.normalized() * (0.42 if mp0 != 19 else 0.25) + Vector3.UP * 0.04
	# шаг 140: на сноуборде тело боком к ходу — глаз чуть вперёд к носкам и выше (видно доску и трассу,
	# плечо и рука не лезут в кадр); вниз «наклоняюсь» тоже к носкам, а не по взгляду
	if mp0 == 51:
		# шаг 143: глаз над серединой доски, чуть ближе к хвосту — вниз-вперёд видно доску носом по ходу,
		# обе ноги в креплениях; «наклон вниз» по взгляду не делаю (иначе глаз уезжает в колени)
		var bfz: Vector3 = -(p.visual.global_basis.z)
		bfz.y = 0.0
		var nose: Vector3 = p.visual.global_basis.x
		nose.y = 0.0
		eye -= fwd_b * Vector3(0.0, 0.06 * down, -0.35 * down)
		# глаз — над носками (корпус в стойке подан вперёд): таз остаётся за кадром, ноги растут из-под края
		eye += bfz.normalized() * board_eye.x + nose.normalized() * board_eye.z + Vector3.UP * board_eye.y
	# шаг 140: вишу на перекладине — глаз чуть вперёд (руки над головой не закрывают обзор)
	if mp0 == 50:
		var bf50: Vector3 = -(p.visual.global_basis.z)
		bf50.y = 0.0
		eye += bf50.normalized() * 0.08
	# шаг 128: глаз отодвинут от стены — значит, он внутри своего корпуса/рюкзака: их своей камере не рисую (руки — рисую)
	# шаг 142: на подъёмнике руки целиком (без наплечника) — видно, как держишься; на доске руки не показываю
	# вовсе (вниз — ноги и доска, ничего не «висит в воздухе»)
	_hide_body(mp0 == 17 or mp0 == 19 or mp0 == 32 or mp0 == 50 or mp0 == 51 or mp0 == 52, 2 if mp0 == 50 else (3 if mp0 >= 51 else 1))
	_follow_k = move_toward(_follow_k, 1.0 if special else 0.0, delta * 3.0)
	# покачивание шага сглажено (голова при ходьбе качается сильнее, чем приятно глазу).
	# Сглаживаю высоту головы ОТНОСИТЕЛЬНО ТЕЛА, а не в мире: иначе в прыжке и на подъёме
	# камера отставала вниз — внутрь корпуса.
	var base_y: float = p.visual.global_position.y
	var rel_y := eye.y - base_y
	if special or absf(rel_y - _eye_y) > 0.4:
		_eye_y = rel_y
	else:
		_eye_y = lerpf(_eye_y, rel_y, clampf(delta * 9.0, 0.0, 1.0))
	# толчок при приземлении: пружинка (небольшая — тело и так приседает)
	_dip_v += (-_dip * 60.0 - _dip_v * 9.0) * delta
	_dip += _dip_v * delta
	_dip = clampf(_dip, -0.08, 0.04)
	var ey := base_y + _eye_y + _dip
	# страховка: глаз не ниже середины шлема — ниже уже воротник и грудь
	ey = clampf(ey, eye.y - 0.05, eye.y + 0.06)
	_eye = Vector3(eye.x, ey, eye.z)
	# несёт лавина / сижу в капсуле: глаз ещё и плавно тянется за головой (тело качается — камера нет)
	var rel := _eye - p.global_position
	if p.snow.swept or p.snow.buried or int(p.snow.capsule) >= 0:
		_rel_s = _rel_s.lerp(rel, clampf(delta * 3.5, 0.0, 1.0))
		_eye = p.global_position + _rel_s
	else:
		_rel_s = rel
	_head_b = hx.basis
	_root_prev = _root_cur
	_root_cur = p.global_position
	# в кувырке и на руках у друга свои руки-ноги бывают у самого стекла — их не рисуем
	p.camera.near = lerpf(0.03, 0.14, _follow_k)
	_place()
	phys_cam = p.camera.global_transform


func _process(_delta: float) -> void:
	if not _active:
		return
	var step := _root_cur - _root_prev
	var off := Vector3.ZERO
	if step.length() < 3.0:
		off = step * (Engine.get_physics_interpolation_fraction() - 1.0)
	if p.visual:
		p.visual.global_position += off - _vis_off
	_vis_off = off
	_place(off)


func _place(off := Vector3.ZERO) -> void:
	var yaw: float = p.camera_pivot.global_rotation.y
	var pitch: float = p.camera_pivot.rotation.x
	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var b := look
	# шаг 106: кручу лебёдку / обвязываюсь — тело стоит лицом к делу: взгляд не дальше ±80° от груди
	# (иначе камера смотрит себе в спину — видно рюкзак и наплечники изнутри)
	var mp := int(p.snow.get("mpose"))
	if _follow_k <= 0.001 and (mp == 25 or mp == 26 or mp == 27 or mp == 28 or mp == 29 or mp == 17 or mp == 32):
		var vy: float = p.visual.global_rotation.y
		var r0 := wrapf(yaw - vy, -PI, PI)
		var lim := 1.4
		if absf(r0) > lim:
			yaw = vy + clampf(r0, -lim, lim)
			p.camera_pivot.rotation.y = yaw
			look = Basis.from_euler(Vector3(pitch, yaw, 0.0))
			b = look
	if _follow_k > 0.001:
		# голова ведёт взгляд (кувыркаюсь — и камера со мной), мышь — поворот относительно головы
		var vis_yaw: float = p.visual.global_rotation.y
		var rel0 := wrapf(yaw - vis_yaw, -PI, PI)
		var rel_yaw := clampf(rel0, -1.3, 1.3)
		if absf(rel0) > 1.3 and _follow_k > 0.5:
			# мышь упёрлась в край обзора головы — держу и саму мышь (иначе за спиной взгляд «перескакивал»)
			p.camera_pivot.rotation.y = vis_yaw + rel_yaw
		var hb := _head_b * Basis.from_euler(Vector3(pitch * 0.7, rel_yaw, 0.0))
		b = Basis(look.get_rotation_quaternion().slerp(hb.get_rotation_quaternion(), smoothstep(0.0, 1.0, _follow_k)))
	# шаг 124: бегу — камера чуть «дышит» в такт шагам (крен с ноги на ногу и лёгкий кивок на касании), едва заметно
	if p.suit != null and p.is_on_floor() and _follow_k <= 0.001:
		var ph := float(p.suit.get("_phase"))
		var rk := clampf((Vector2(p.velocity.x, p.velocity.z).length() - 3.0) / 8.5, 0.0, 1.0) * float(p.suit.get("_amp"))
		if rk > 0.01:
			b = b * Basis(Vector3(0.0, 0.0, 1.0), sin(TAU * ph) * 0.011 * rk) * Basis(Vector3(1.0, 0.0, 0.0), -absf(sin(TAU * ph)) * 0.007 * rk)
	if absf(float(p.fp_roll)) > 0.0005:
		b = b * Basis(Vector3(0.0, 0.0, 1.0), float(p.fp_roll))      # шаг 89: крен (тащит по снегу)
	p.camera.global_transform = Transform3D(b, _eye + off)


func _set_active(on: bool) -> void:
	_active = on
	var cam: Camera3D = p.camera
	if on:
		_saved_near = cam.near
		_saved_pitch = Vector2(p.min_pitch_deg, p.max_pitch_deg)
		# камеру — из «пружины» (она двигает своих детей) прямо в дрона, сама по себе
		cam.reparent(p, false)
		cam.top_level = true
		cam.make_current()
		cam.near = 0.03
		cam.cull_mask = ALL_LAYERS & ~HIDE_LAYER
		p.min_pitch_deg = -84.0
		p.max_pitch_deg = 80.0
		p.camera_pivot.rotation.x = clampf(p.camera_pivot.rotation.x + 0.25, deg_to_rad(-84.0), deg_to_rad(80.0))
		_eye_y = p.suit.head.global_position.y - p.visual.global_position.y
		_follow_k = 1.0 if _special() else 0.0
		_hide_head(true)
		p.fp_view = true
	else:
		cam.top_level = false
		cam.reparent(p.spring_arm, false)
		cam.transform = Transform3D.IDENTITY
		if p.controlled:
			cam.make_current()
		cam.near = _saved_near
		cam.cull_mask = ALL_LAYERS
		p.min_pitch_deg = _saved_pitch.x
		p.max_pitch_deg = _saved_pitch.y
		p.camera_pivot.rotation.x = clampf(p.camera_pivot.rotation.x, deg_to_rad(_saved_pitch.x), deg_to_rad(_saved_pitch.y))
		_hide_body(false)
		_hide_head(false)
		p.fp_view = false


func _held_parcel() -> Node:
	if int(p.get("_vis_mode")) == 0:
		return null
	var hp: Node = p.held_parcel
	if hp == null or not is_instance_valid(hp):
		hp = p.get("_vis_parcel")
	if hp == null or not is_instance_valid(hp):
		return null
	return hp


## Надписи над посылкой у меня в руках (цена, «тяжёлая»…) — на скрытый слой, другие их видят
func _hide_parcel_labels(parcel: Node) -> void:
	if parcel == _label_parcel:
		return
	for l in _labels:
		if is_instance_valid(l):
			l.layers = 1
	_labels.clear()
	_label_parcel = parcel
	if parcel == null:
		return
	for l in parcel.find_children("*", "Label3D", true, false):
		var lb := l as Label3D
		lb.layers = HIDE_LAYER
		_labels.append(lb)


## Голову (и подпись над дроном) — на отдельный слой, его своя камера в FP не рисует
func _hide_head(on: bool) -> void:
	_hidden = on
	var layer := HIDE_LAYER if on else 1
	if p.suit and p.suit.get("head"):
		_set_layers(p.suit.head, layer)
		var col: Node = p.suit.torso.get_node_or_null("Collar") if p.suit.get("torso") else null
		if col:
			_set_layers(col, layer)
	for c in p.get_children():
		if c is Label3D:
			(c as Label3D).layers = layer


## шаг 143: глаз на доске (к носкам, вверх, к носу доски)
static var board_eye := Vector3(0.12, 0.3, -0.35)
var _body_hidden := false
var _body_mode := 1
## mode 1 — прячу и плечо целиком (рука от локтя); 2 — только толстую «мышцу» у плеча (рука цельная);
## 3 — руки целиком
func _hide_body(on: bool, mode := 1) -> void:
	if p.suit == null or p.suit.get("torso") == null:
		return
	if on == _body_hidden and (not on or mode == _body_mode):
		return
	if _body_hidden and on and mode != _body_mode:
		_hide_body(false)
	_body_hidden = on
	_body_mode = mode
	var layer := HIDE_LAYER if on else 1
	var keep: Array = []
	for am in p.suit.get("_arms"):
		keep.append(am["upper"])
	var torso: Node3D = p.suit.torso
	for c in torso.get_children():
		if c == p.suit.head or c.name == "Collar" or c in keep:
			continue
		var has_arm := false
		for u in keep:
			if c.is_ancestor_of(u):
				has_arm = true
		if has_arm:
			# в узле есть рука — прячу только его собственные меши, а не детей-рук
			for cc in c.get_children():
				if cc is VisualInstance3D and not (cc in keep):
					(cc as VisualInstance3D).layers = layer
			continue
		_set_layers(c, layer)
	if torso is VisualInstance3D:
		(torso as VisualInstance3D).layers = layer
	# плечи (наплечники, бицепс) — у самой камеры, закрывают пол-экрана: прячу их собственные меши, предплечья и кисти остаются
	for u in keep:
		var idx := 0
		for cc in (u as Node).get_children():
			if cc is VisualInstance3D:
				if mode != 2 or idx == 1 or not on:
					(cc as VisualInstance3D).layers = layer
				idx += 1
	for am2 in p.suit.get("_arms"):
		for key in ["fore", "hand"]:
			var nd: Node = am2.get(key)
			if nd != null:
				_set_layers(nd, layer if (mode == 3 or not on) else 1)
	var pel: Node = p.suit.get("pelvis")
	if pel:
		for cc in pel.get_children():
			if cc is VisualInstance3D:
				(cc as VisualInstance3D).layers = layer
			elif cc is Node3D:
				# моток верёвки и снаряжение на поясе — у самой камеры, прячу
				_set_layers(cc, layer)
	# шаг 143: на доске бёдра (у самой камеры, закрывали доску) прячу — видно голени, ботинки и доску
	for lg in p.suit.get("_legs"):
		var th: Node = lg.get("thigh")
		if th != null:
			_set_layers(th, layer if (mode == 3 or not on) else 1)
	# шланг от рюкзака к шлему — проходит у самого глаза
	var hose = p.suit.get("_hose")
	if hose != null:
		for hm in hose:
			(hm as VisualInstance3D).layers = layer


func _set_layers(n: Node, layer: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layer
	for c in n.get_children():
		_set_layers(c, layer)
