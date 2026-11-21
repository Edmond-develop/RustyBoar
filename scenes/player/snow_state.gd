extends Node3D
## Лавинная долина (шаг 56) — всё, что у дрона связано со снегом и снежными роботами.
## Узел "SnowState" внутри дрона (player.gd создаёт его в _ready), у всех копий один путь.
##
##  * Лавина несёт (swept, шаг 64): дрон едет на спине по снежному валу — полулёжа, ногами вперёд,
##    наполовину в снегу, руками цепляется за снег; его покачивает на буграх. Уносит на сотни метров.
##  * Капсула-убежище (шаг 64): E у люка — залез, люк захлопнулся, лавина проходит над тобой; E — вылезти.
##  * Завалило (buried): над снегом — бугорок и мигающий маячок. Камера — в снегу:
##    синеватая темнота, свет сверху, комья на стекле, звук глухой. Сам не выбраться —
##    друг (или бот) держит E рядом ~3 с и откапывает — становится светлее, снег осыпается.
##  * Рыхлый снег после лавины: дрон проваливается по колено, из-под ног летит снег.
##  * Откапываю друга (держу E рядом с сугробом).
##  * Схватил снежного робота (E): несу перед собой, Q — швырнуть (разобьётся), E — поставить.
##  * В руке оторванная рука/нога: ЛКМ — махнуть, как дубинкой (сбивает и разбивает роботов).

const SUIT := preload("res://scenes/player/exo_suit.gd")
const KEYS := ["jump", "move_forward", "move_back", "move_left", "move_right", "interact", "shake_ice", "sprint"]
const DIG_TIME := 3.0
const DIG_REACH := 2.4
const SWEEP_MAX := 45.0           ## дольше не несёт — заваливает где есть
const SWING_TIME := 0.38

var p: CharacterBody3D             ## player.gd
var swept := false
var buried := false
var dig_progress := 0.0            ## как меня откапывают (0…1) — для подсказки и сугроба
var held_bot: Node3D = null        ## снежный робот у меня в руках
var buried_time := 0.0
var capsule := -1                  ## в какой капсуле-убежище сижу (−1 — ни в какой)
var _cap_xf := Transform3D.IDENTITY
var _cap_rid := RID()
var _ride_y := NAN                 ## верх вала подо мной (едем по нему); NAN — вала нет, падаю как был
var _ride_t := 0.0
var _cap_t := 0.0
var cap_exit_ms := -100000         ## когда вылез (чтобы та же E не загнала обратно)

var _sweep_vel := Vector3.ZERO
var _sweep_t := 0.0
var _tum := 0.0
var _dig_target: Node3D = null
var _dig_t := 0.0
var _dig_send := 0.0
var _dig_fx_t := 0.0
var _swing_t := -1.0
var _swing_hit := false
var _jolt := 0.0
var _vis_k := 0.0                  ## насколько «утонул» в сугробе (для плавности)

var _mound: Node3D
var _mound_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _beacon_light: OmniLight3D
var _label: Label3D
var _dig_fx: GPUParticles3D
var _feet_fx: GPUParticles3D
var _sink := 0.0
var shallow := false               ## шаг 137: завалило неглубоко (у края лавины) — можно откопаться самому
var _dig_hand := -1
var _screen: ColorRect
var _screen_mat: ShaderMaterial
var _screen_k := 0.0
var _swept_k := 0.0
var _tum2 := 0.0
var _swept_vis := 0.0

const SCREEN_SHADER := """
shader_type canvas_item;
// Края экрана засыпаны снегом (в сугробе), в потоке — несущаяся по краям снежная пыль.
uniform float buried = 0.0;
uniform float swept = 0.0;
uniform float dig = 0.0;
uniform float jolt = 0.0;
uniform float fp = 0.0;            // шаг 69: от 1-го лица в потоке — сплошная снежная пелена
uniform sampler2D noise : repeat_enable, filter_linear;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = UV + vec2(sin(TIME * 47.0), cos(TIME * 39.0)) * jolt * 0.004;
	vec2 c = uv - 0.5;
	// снег налип по краям и особенно снизу; неровная кромка
	float edge = max(abs(c.x) * 1.15, 0.0) + max(c.y, 0.0) * 1.35 + max(-c.y, 0.0) * 0.55;
	float n = texture(noise, uv * vec2(2.2, 1.6) + 0.13).r;
	float n2 = texture(noise, uv * 6.5 + 0.57).r;
	float reach = mix(0.75, 0.56, buried) + dig * 0.2;       // откапывают — снег осыпается с краёв
	float m = smoothstep(reach - 0.04, reach + 0.05, edge + (n - 0.5) * 0.28 + (n2 - 0.5) * 0.08);
	float shade = 0.9 + 0.1 * n2 - smoothstep(0.0, 0.3, edge - reach) * 0.08;
	vec3 snow = vec3(0.93, 0.96, 1.0) * shade;
	// искорки на налипшем снегу
	vec2 cell = floor(FRAGCOORD.xy / 3.0);
	float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	snow += vec3(0.08) * step(0.985, hsh);
	float a_b = buried * m * 0.95;
	// поток: по краям несутся струи снега, середина видна
	float s1 = texture(noise, vec2(uv.x * 2.0, uv.y * 0.35 - TIME * 0.9)).r;
	float s2 = texture(noise, vec2(uv.x * 4.0 + 0.5, uv.y * 0.6 - TIME * 1.4)).r;
	float streak = smoothstep(0.45, 0.8, s1) * 0.7 + smoothstep(0.55, 0.85, s2) * 0.5;
	float ring = smoothstep(0.18, 0.55, length(c * vec2(1.3, 1.0)));
	float a_s = swept * clamp(ring * (0.3 + 0.3 * streak) + 0.06 * streak, 0.0, 0.6);
	vec3 col = mix(vec3(0.93, 0.96, 1.0), snow, step(a_s, a_b));
	float veil = swept * fp;
	if (veil > 0.001) {
		// пелена: за ней всё размыто (несколько выборок вокруг) и почти не видно; по ней несутся струи снега
		vec3 bg = vec3(0.0);
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.785398 + 0.4;
			bg += textureLod(screen, SCREEN_UV + vec2(cos(a), sin(a)) * vec2(0.018, 0.032), 2.5).rgb;
		}
		bg *= 0.125;
		float w1 = texture(noise, vec2(uv.x * 1.3 + TIME * 0.05, uv.y * 0.5 - TIME * 0.7)).r;
		float w2 = texture(noise, vec2(uv.x * 3.1 - TIME * 0.08, uv.y * 1.1 - TIME * 1.6)).r;
		float dens = 0.74 + 0.12 * smoothstep(0.35, 0.8, w1) + 0.08 * smoothstep(0.5, 0.85, w2) + 0.1 * ring;
		vec3 white = vec3(0.9, 0.94, 1.0) * (0.93 + 0.07 * w2) - vec3(0.06, 0.04, 0.0) * (1.0 - w1) * 0.5;
		vec3 v = mix(bg, white, clamp(dens, 0.0, 0.97));
		v = mix(v, snow, a_b);
		COLOR = vec4(v, veil);
	} else {
		COLOR = vec4(col, max(a_b, a_s));
	}
}
"""


func _ready() -> void:
	p = get_parent() as CharacterBody3D
	_mound = Node3D.new()
	_mound.visible = false
	add_child(_mound)
	_mound_mat = StandardMaterial3D.new()
	_mound_mat.albedo_color = Color(0.84, 0.89, 0.97)
	_mound_mat.roughness = 0.95
	var blobs := [[Vector3(0, 0.1, 0), Vector3(1.2, 0.55, 1.1)], [Vector3(0.6, 0.05, 0.35), Vector3(0.7, 0.4, 0.65)],
		[Vector3(-0.55, 0.08, -0.3), Vector3(0.75, 0.42, 0.7)], [Vector3(0.1, 0.0, -0.75), Vector3(0.6, 0.35, 0.5)],
		[Vector3(-0.35, 0.0, 0.7), Vector3(0.55, 0.3, 0.5)]]
	for bl in blobs:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 12
		sm.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _mound_mat
		mi.position = bl[0]
		mi.scale = bl[1]
		_mound.add_child(mi)
	# маячок на антенне — мигает красным
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1, 0.2, 0.15)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1, 0.15, 0.1)
	var bs := SphereMesh.new()
	bs.radius = 0.09
	bs.height = 0.18
	var bmi := MeshInstance3D.new()
	bmi.mesh = bs
	bmi.material_override = _beacon_mat
	bmi.position = Vector3(0.25, 1.35, 0.1)
	_mound.add_child(bmi)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.015
	stick.bottom_radius = 0.015
	stick.height = 0.7
	var smi := MeshInstance3D.new()
	smi.mesh = stick
	smi.material_override = _beacon_mat
	smi.position = Vector3(0.25, 1.0, 0.1)
	_mound.add_child(smi)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = Color(1, 0.25, 0.15)
	_beacon_light.omni_range = 6.0
	_beacon_light.position = Vector3(0.25, 1.45, 0.1)
	_mound.add_child(_beacon_light)
	_label = Label3D.new()
	_label.font_size = 30
	_label.outline_size = 9
	_label.modulate = Color(1.0, 0.75, 0.6)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, 2.0, 0)
	_mound.add_child(_label)
	_dig_fx = FX.particles(Color(0.95, 0.97, 1.0, 0.9), 26, 0.7, 0.07, 2.0, 4.5, Vector3(0, -9, 0), 50.0, true)
	_dig_fx.position = Vector3(0, 0.5, 0)
	add_child(_dig_fx)
	_feet_fx = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 24, 0.6, 0.07, 1.0, 2.6, Vector3(0, -6, 0), 55.0, false)
	_feet_fx.position = Vector3(0, 0.15, 0)
	add_child(_feet_fx)


func _online() -> bool:
	return Network.in_game and Network.is_online()


func reset() -> void:
	climb = 0
	_cl_data = {}
	set_mpose(0)
	if capsule >= 0:
		exit_capsule()
	swept = false
	buried = false
	dig_progress = 0.0
	buried_time = 0.0
	_dig_target = null
	_swing_t = -1.0
	if held_bot != null:
		release_bot(Vector3.ZERO)


func busy() -> bool:
	return swept or buried or capsule >= 0 or climb > 0


# ---------------------------------------------------------------------------
#  Шаг 72–73: подъём на Пике.
#   climb 1 — верёвочная лестница (сам едет вверх, пока её держат наверху);
#   climb ≥ 3 — движение ведёт модуль горы (_cl_mtn.drive): 3 — скалолазание по стене, 4 — подсадка,
#   5 — вылезти на уступ, 6 — меня подтягивают за руку, 7 — еду в кабинке/корзине и т. п.
#  Поза для анимации (mpose) — у своего дрона ставит гора, остальным рассылается (_net_mpose).
# ---------------------------------------------------------------------------

var climb := 0
var climb_obs := -1                ## номер уступа (лестница)
var _cl_base := Vector3.ZERO
var _cl_h := 0.0
var _cl_H := 0.0
var _cl_n := Vector3.FORWARD
var _cl_top := Vector3.ZERO
var _cl_mtn: Node
var _cl_t := 0.0
var _cl_data := {}
var _cl_moving := false
const ROPE_UP := 1.6               ## по лестнице

## Поза на горе: 0 — нет; 1 — лестница; 2 — стена; 3 — подсаживаю (ладони «ступенькой»); 4 — поднимаю;
## 5 — меня подсаживают (стою в ладонях, лечу); 6 — вылезаю на край; 7 — подтягиваю друга (лёг у края, рука вниз);
## 8 — меня подтягивают; 9 — кручу ворот; 10 — держу оттяжку; 11 — страхую / держу верёвку; 12 — вцепился в стену;
## 13 — несу дрова; 14 — ставлю деталь в гнездо (k — ход установки); 15 — тяну рычаг; 16 — качаю мехи (шаг 74)
var mpose := 0
var mpose_k := 0.0
var mpose_pt := Vector3.ZERO       ## точка (куда руки)
var mpose_dir := Vector3.FORWARD   ## направление (к стене / к уступу)
var mpose_moving := false
var _mp_sent := -1
var _mp_t := 0.0


func set_mpose(pose: int, k := 0.0, pt := Vector3.ZERO, dir := Vector3.FORWARD, moving := false) -> void:
	mpose = pose
	mpose_k = k
	mpose_pt = pt
	mpose_dir = dir
	mpose_moving = moving


## Своя поза — остальным (10 раз в секунду, пока есть; один раз — когда кончилась)
func _send_mpose(delta: float) -> void:
	if not _online() or not p.is_local:
		return
	_mp_t -= delta
	if mpose == 0 and _mp_sent == 0:
		return
	if _mp_t > 0.0 and mpose == _mp_sent:
		return
	_mp_t = 0.1
	_mp_sent = mpose
	_net_mpose.rpc(mpose, mpose_k, mpose_pt, mpose_dir, mpose_moving, climb)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_mpose(pose: int, k: float, pt: Vector3, dir: Vector3, moving: bool, cl: int) -> void:
	if p.is_local:
		return
	mpose = pose
	mpose_k = k
	mpose_pt = pt
	mpose_dir = dir
	mpose_moving = moving
	climb = cl


func start_climb(kind: int, base: Vector3, h: float, n: Vector3, top: Vector3, obs: int, mtn: Node) -> void:
	if not p.is_local or busy() or p.is_dead:
		return
	_prep_climb()
	climb = kind
	climb_obs = obs
	_cl_base = base
	_cl_H = h
	_cl_h = 0.15
	_cl_n = Vector3(n.x, 0.0, n.z).normalized()
	_cl_top = top
	_cl_mtn = mtn
	p.velocity = Vector3.ZERO
	p.visual.rotation.y = atan2(_cl_n.x, _cl_n.z)
	set_mpose(1, 0.0, top, -_cl_n)


## Движение по сценарию модуля горы (он зовёт drive(дрон, вид, время, данные, delta) каждый кадр)
func start_scripted(kind: int, mtn: Node, data: Dictionary) -> void:
	if not p.is_local or busy() or p.is_dead:
		return
	_prep_climb()
	climb = kind
	_cl_mtn = mtn
	_cl_data = data
	_cl_t = 0.0
	p.velocity = Vector3.ZERO


func end_scripted() -> void:
	climb = 0
	_cl_data = {}


func _prep_climb() -> void:
	if p.held_limb != null:
		p._drop_limb(Vector3.ZERO)
	if held_bot != null:
		release_bot(Vector3.ZERO)
	if p.sitting:
		p._stand_up()


func _climb_drop(push: float) -> void:
	climb = 0
	set_mpose(0)
	p.velocity = _cl_n * push + Vector3.DOWN * 1.0
	p.global_position = _cl_base + Vector3.UP * _cl_h + _cl_n * 0.6


func _climb_process(delta: float) -> void:
	_cl_moving = false
	if climb >= 3:
		_cl_t += delta
		if _cl_mtn == null or not is_instance_valid(_cl_mtn):
			end_scripted()
			return
		_cl_mtn.drive(p, climb, _cl_t, _cl_data, delta)
		_cl_moving = mpose_moving
		# на стене и в кабинке тоже холодно
		if p.has_method("_frost_tick"):
			p._frost_tick(delta, -1.0)
		return
	# лестница (держат наверху)
	if _cl_mtn != null and not _cl_mtn.ladder_down(climb_obs):
		_climb_drop(0.5)            # лестницу отпустили — сорвался
		return
	_cl_h += ROPE_UP * delta
	_cl_moving = true
	set_mpose(1, _cl_h / maxf(_cl_H, 0.1), _cl_top, -_cl_n, true)
	if _cl_h >= _cl_H - 0.2:
		climb = 0
		set_mpose(0)
		p.global_position = _cl_top
		p.velocity = Vector3.ZERO
		return
	p.velocity = Vector3.ZERO
	p.global_position = _cl_base + Vector3.UP * _cl_h + _cl_n * 0.42
	p.visual.rotation.y = atan2(_cl_n.x, _cl_n.z)


# ---------------------------------------------------------------------------
#  Капсула-убежище (капсулы строит avalanche.gd): сижу внутри, лавина не достаёт
# ---------------------------------------------------------------------------

func enter_capsule(i: int, xf: Transform3D, rid: RID) -> void:
	if not p.is_local or busy() or p.is_dead:
		return
	if p.held_parcel != null:
		p._put_down()
	if p.held_limb != null:
		p._drop_limb(Vector3.ZERO)
	if held_bot != null:
		release_bot(Vector3.ZERO)
	if p.sitting:
		p._stand_up()
	capsule = i
	_cap_t = 0.0
	_cap_xf = xf
	_cap_rid = rid
	p.velocity = Vector3.ZERO
	p.global_position = xf * Vector3(0.0, 0.02, 0.0)
	p.visual.rotation.y = atan2(-xf.basis.z.x, -xf.basis.z.z)          # лицом к люку (к иллюминатору)
	p.camera_pivot.global_rotation.y = p.visual.rotation.y
	p.camera_pivot.rotation.x = -0.05
	if rid.is_valid():
		p.spring_arm.add_excluded_object(rid)
	p._noise_burst = 0.0


func exit_capsule() -> void:
	if capsule < 0:
		return
	capsule = -1
	cap_exit_ms = Time.get_ticks_msec()
	if _cap_rid.is_valid():
		p.spring_arm.remove_excluded_object(_cap_rid)
	var out := _cap_xf * Vector3(0.0, 0.0, 2.3)
	out.y = _surface(out) + 0.35
	p.global_position = out
	p.velocity = _cap_xf.basis.z * 2.0 + Vector3.UP * 3.0
	p._was_on_floor = false


# ---------------------------------------------------------------------------
#  Лавина: несёт и заваливает (зовёт avalanche.gd у своих дронов)
# ---------------------------------------------------------------------------

## Лавина накрыла: дальше несёт со скоростью vel (пока не bury)
func sweep(vel: Vector3) -> void:
	if not p.is_local or p.is_dead or buried or p.is_frozen:
		return
	_sweep_vel = vel
	if swept:
		return
	swept = true
	_sweep_t = 0.0
	_tum = 0.0
	_ride_y = NAN
	_ride_t = 0.0
	_dig_target = null
	if p.held_parcel != null:
		p._fumble()
	if p.held_friend != null:
		p._lift_call(p.held_friend, false, Vector3.ZERO)
	if p.held_limb != null:
		p._drop_limb(vel * 0.5 + Vector3.UP * 3.0)
	if held_bot != null:
		release_bot(vel * 0.6 + Vector3.UP * 2.0)
	if p.sitting:
		p._stand_up()
	if p.belly:
		p._belly_end()
	p._tumble = false
	p._flop_t = 0.0
	p.is_sprinting = false
	p.take_damage(10.0, "thrown")
	p.suit.emote(SUIT.Mood.PANIC, 6.0)
	p.suit.set("_snow", 0.9)
	p._shake = maxf(p._shake, 0.6)


## Каждый кадр, пока несёт: куда течёт снег вокруг меня и где верх вала
func flow(vel: Vector3, ride_y := NAN) -> void:
	if swept:
		_sweep_vel = vel
		_ride_y = ride_y


## Поток встал — я в сугробе
func bury(shallow_ := false) -> void:
	if not p.is_local or buried:
		return
	swept = false
	buried = true
	shallow = shallow_
	_dig_hand = -1
	buried_time = 0.0
	dig_progress = 0.0
	p.velocity = Vector3.ZERO
	var ter = get_tree().get_first_node_in_group("terrain")
	if ter:
		var gp: Vector3 = p.global_position
		p.global_position = Vector3(gp.x, ter.height_at(gp.x, gp.z) + 0.05, gp.z)
	p._shake = maxf(p._shake, 0.4)
	p.suit.emote(SUIT.Mood.DIZZY, 4.0)


## Откопали (у хозяина дрона)
func unbury(push := Vector3.ZERO) -> void:
	if not buried:
		return
	buried = false
	swept = false
	dig_progress = 0.0
	p.global_position.y = _surface(p.global_position) + 0.35
	p.velocity = push + Vector3.UP * 5.0
	p.camera_pivot.rotation.x = -0.25
	p._was_on_floor = false
	p._invuln_timer = 1.5
	p.body.scale = Vector3(0.85, 1.2, 0.85)
	p.suit.emote(SUIT.Mood.HAPPY, 2.0)
	p._noise_burst += 0.4
	_dig_fx.restart()


## Друг докопал — снять меня (зовёт копающий, на любом компьютере)
func request_unbury(push: Vector3) -> void:
	if p.is_local:
		unbury(push)
	elif _online():
		_rpc_unbury.rpc_id(p.get_multiplayer_authority(), push)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_unbury(push: Vector3) -> void:
	if p.is_local:
		unbury(push)


## Как продвигается раскопка (для подсказки у заваленного)
func report_dig(k: float) -> void:
	if p.is_local:
		dig_progress = maxf(dig_progress, k)
		_jolt = 1.0
	elif _online():
		_rpc_dig.rpc_id(p.get_multiplayer_authority(), k)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_dig(k: float) -> void:
	if p.is_local:
		dig_progress = maxf(dig_progress, k)
		_jolt = 1.0


## Все в долине завалены слишком долго — вылезаю у начала долины (зовёт хост)
func rescue_respawn(at: Vector3) -> void:
	if p.is_local:
		_do_rescue_respawn(at)
	elif _online():
		_rpc_rescue_respawn.rpc_id(p.get_multiplayer_authority(), at)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rescue_respawn(at: Vector3) -> void:
	if p.is_local:
		_do_rescue_respawn(at)


func _do_rescue_respawn(at: Vector3) -> void:
	buried = false
	swept = false
	dig_progress = 0.0
	p.global_position = at
	p.velocity = Vector3.ZERO
	p._invuln_timer = 2.0
	p._shake = 0.3


## Свой дрон в лавине/сугробе — вместо обычного кадра
func locked_process(delta: float) -> void:
	if climb > 0:
		_climb_process(delta)
		p.noise = 0.0
	elif capsule >= 0:
		# сижу в капсуле: не двигаюсь; E — вылезти
		p.velocity = Vector3.ZERO
		p.global_position = _cap_xf * Vector3(0.0, 0.02, 0.0)
		p.noise = 0.0
		_cap_t += delta
		if p.controlled and _cap_t > 0.4 and p._just("interact"):
			exit_capsule()
	elif swept:
		_sweep_t += delta
		_tum += delta * (1.0 + _sweep_vel.length() * 0.08)
		var v := p.velocity
		v.x = lerpf(v.x, _sweep_vel.x, clampf(delta * 4.0, 0.0, 1.0))
		v.z = lerpf(v.z, _sweep_vel.z, clampf(delta * 4.0, 0.0, 1.0))
		if not is_nan(_ride_y):
			# еду по валу: вперёд — с потоком, по высоте — по его поверхности (с покачиванием на буграх)
			_ride_t += delta
			var bump := sin(_ride_t * 1.6) * 0.12 + sin(_ride_t * 0.7 + 1.0) * 0.06
			var gp := p.global_position + Vector3(v.x, 0.0, v.z) * delta
			var ty := _ride_y - 0.2 + bump
			var ny := lerpf(gp.y, ty, clampf(delta * 3.0, 0.0, 1.0))
			v.y = (ny - gp.y) / maxf(delta, 0.001)
			p.velocity = v
			p.global_position = Vector3(gp.x, ny, gp.z)
		else:
			v.y += -9.8 * 1.6 * delta
			p.velocity = v
			p.move_and_slide()
		p.noise = 0.0
		if _sweep_t > SWEEP_MAX:
			bury()
	else:
		buried_time += delta
		p.velocity = Vector3.ZERO
		p.noise = 0.0
		for a in KEYS:
			if p._just(a):
				_jolt = maxf(_jolt, 0.4)
		# шаг 137: по грудь — откапываюсь сам: ЛКМ/ПКМ по очереди (~20 гребков); с головой — только друг
		if shallow and p.controlled and buried_time > 0.8:
			for hh in 2:
				if p._just("use_item" if hh == 0 else "use_alt") and hh != _dig_hand:
					_dig_hand = hh
					dig_progress = minf(dig_progress + 0.05, 1.0)
					_jolt = 1.0
					_dig_fx.restart()
			if dig_progress >= 1.0:
				unbury(Vector3.ZERO)
	p._update_visual(delta, Vector3.ZERO, 0.0, false)
	p._update_camera(delta)
	if buried and p.controlled and not p.fp_view:
		# камера рядом, чуть сверху: видно, как дрон полулежит в снегу
		p.spring_arm.spring_length = lerpf(p.spring_arm.spring_length, 3.2, clampf(delta * 3.0, 0.0, 1.0))
		p.camera_pivot.rotation.x = lerp_angle(p.camera_pivot.rotation.x, -0.38, clampf(delta * 2.0, 0.0, 1.0))
	elif swept and p.controlled and not p.fp_view:
		p.spring_arm.spring_length = lerpf(p.spring_arm.spring_length, 3.6, clampf(delta * 3.0, 0.0, 1.0))
	p._update_hud()
	p._prev_velocity = p.velocity
	p._send_state(delta)


## Поза в потоке и в сугробе (зовёт _update_visual); true — поза моя
func pose_visual(delta: float) -> bool:
	var target := 1.0 if buried else 0.0
	_vis_k = move_toward(_vis_k, target, delta * 2.5)
	var vis: Node3D = p.visual
	if swept:
		# еду на спине ногами вперёд: полулёжа, наполовину в снегу; покачивает, медленно разворачивает
		var hv := Vector3(_sweep_vel.x, 0.0, _sweep_vel.z)
		var yaw: float = vis.rotation.y
		if hv.length() > 0.5:
			yaw = lerp_angle(yaw, atan2(-hv.x, -hv.z) + sin(_tum * 0.35) * 0.3, clampf(delta * 1.5, 0.0, 1.0))
		_tum2 += delta
		_swept_vis = minf(_swept_vis + delta * 2.0, 1.0)
		var k := smoothstep(0.0, 1.0, _swept_vis)
		var rock := sin(_tum2 * 1.6) * 0.06 + sin(_tum2 * 0.7 + 1.0) * 0.03
		var roll := sin(_tum2 * 1.1) * 0.08
		var b := Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3((0.6 + rock) * k, 0.0, roll * k))
		vis.transform = Transform3D(b, Vector3(0, -0.25 * k, 0))
		return true
	_swept_vis = 0.0
	if buried or _vis_k > 0.01:
		var yaw2: float = vis.rotation.y
		var wig := _jolt * sin(p._time * 40.0) * 0.08
		# полулежу в снегу: сижу (ноги вперёд, под снегом), откинулся назад, наружу — корпус и голова
		var b2 := Basis.from_euler(Vector3(0.55 * _vis_k + wig, yaw2, 0.12 * _vis_k + wig * 0.5))
		var top: float = _surface(p.global_position) - p.global_position.y
		vis.transform = Transform3D(b2, Vector3(0, (top - 0.45) * _vis_k, 0))
		return true
	return false


# ---------------------------------------------------------------------------
#  Обычный кадр: копаю друга, машу деталью, несу робота
# ---------------------------------------------------------------------------

func tick(delta: float) -> void:
	_jolt = maxf(_jolt - delta * 3.0, 0.0)
	# копаю
	if _dig_target != null:
		var ok: bool = is_instance_valid(_dig_target) and _dig_target.get("snow") != null and _dig_target.snow.buried \
			and p._held("interact") and _flat_dist(_dig_target) < DIG_REACH + 0.4 and not p.is_dead and p.arms_count() > 0
		if not ok:
			_dig_target = null
			_dig_t = 0.0
		else:
			_dig_t += delta
			var to: Vector3 = _dig_target.global_position - p.global_position
			to.y = 0.0
			if to.length() > 0.1:
				p.visual.rotation.y = lerp_angle(p.visual.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))
			_dig_fx_t -= delta
			if _dig_fx_t <= 0.0:
				_dig_fx_t = 0.32
				p.suit.punch()
				_dig_fx.global_position = _dig_target.global_position + Vector3.UP * 0.6
				_dig_fx.restart()
				p._noise_burst += 0.05
			_dig_send -= delta
			if _dig_send <= 0.0:
				_dig_send = 0.2
				_dig_target.snow.report_dig(_dig_t / DIG_TIME)
				_dig_target.snow._jolt = 1.0
			if _dig_t >= DIG_TIME:
				var push := to.normalized() * 1.5 if to.length() > 0.1 else Vector3.ZERO
				_dig_target.snow.request_unbury(push)
				_dig_target = null
				_dig_t = 0.0
	# R — стряхнуть вцепившегося робота
	if p._just("shake_ice"):
		for r in get_tree().get_nodes_in_group("snow_robot"):
			if is_instance_valid(r) and r.latched_on(p):
				var back: Vector3 = p.visual.global_basis.z
				r.request_hit(back * 6.0 + Vector3.UP * 5.0, int(p.peer_id), 0)
				p.suit.punch()
				p._noise_burst += 0.6
	# машу деталью
	if _swing_t >= 0.0:
		_swing_t += delta
		if not _swing_hit and _swing_t > 0.12:
			_swing_hit = true
			_swing_strike()
		if _swing_t > SWING_TIME:
			_swing_t = -1.0
	elif p.held_limb != null and p._just("use_item") and not (p.rope and bool(p.rope.get("equipped"))) \
			and p.held_parcel == null and p._repair_target == null:
		_swing_t = 0.0
		_swing_hit = false
		p.suit.punch()
		p.suit.throw_anim()
		p._noise_burst += 0.6
	if held_bot != null and not is_instance_valid(held_bot):
		held_bot = null


func _flat_dist(n: Node3D) -> float:
	var d: Vector3 = n.global_position - p.global_position
	return Vector2(d.x, d.z).length()


## Удар деталью: роботы перед собой — отлетают (и разбиваются)
func _swing_strike() -> void:
	var fwd: Vector3 = -p.visual.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for r in get_tree().get_nodes_in_group("snow_robot"):
		if not is_instance_valid(r) or not r.alive():
			continue
		var to: Vector3 = (r as Node3D).global_position - p.global_position
		to.y = 0.0
		if to.length() < 2.3 and (to.length() < 0.8 or to.normalized().dot(fwd) > 0.25):
			r.request_hit(fwd * 9.0 + Vector3.UP * 4.0, int(p.peer_id))
	p._shake = maxf(p._shake, 0.15)


## Заваленный друг рядом
func buried_buddy() -> Node3D:
	var best: Node3D = null
	var bd := DIG_REACH
	for d in get_tree().get_nodes_in_group("player"):
		if d == p or d.get("snow") == null or not d.snow.buried:
			continue
		var dist := _flat_dist(d)
		if dist < bd:
			bd = dist
			best = d
	return best


## Снежный робот рядом, которого можно схватить
func robot_near(max_d := 1.9) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for r in get_tree().get_nodes_in_group("snow_robot"):
		if not is_instance_valid(r) or not r.can_grab():
			continue
		var dist := _flat_dist(r)
		if dist < bd and absf((r as Node3D).global_position.y - p.global_position.y) < 2.0:
			bd = dist
			best = r
	return best


## E: копать друга / взять или поставить робота. true — нажатие моё
func try_interact() -> bool:
	if held_bot != null:
		var fwd: Vector3 = -p.visual.global_basis.z
		release_bot(Vector3(p.velocity.x, 0.0, p.velocity.z) * 0.5 + fwd * 1.0)
		return true
	if p.arms_count() == 0 or p.held_parcel != null or p.held_friend != null or p.held_limb != null:
		return false
	var bud := buried_buddy()
	if bud != null:
		_dig_target = bud
		_dig_t = 0.0
		_dig_send = 0.0
		return true
	var r := robot_near()
	if r != null:
		held_bot = r
		r.request_grab(int(p.peer_id))
		p.suit.reach()
		return true
	return false


## Где держу робота: над головой на поднятых руках (корень робота), он брыкается
func hold_xform() -> Transform3D:
	var yaw: float = p.visual.global_rotation.y
	var b := Basis(Vector3.UP, yaw)
	var wig := sin(p._time * 17.0) * 0.07
	var wig2 := sin(p._time * 23.0 + 1.0) * 0.05
	var pos: Vector3 = p.global_position + b * Vector3(wig, 1.6 + absf(wig2), 0.05)
	return Transform3D(b * Basis(Vector3.FORWARD, wig * 3.5) * Basis(Vector3.RIGHT, wig2 * 3.0), pos)


## Держу ли робота (и у копий чужого дрона — по роботам)
func holding_bot() -> bool:
	if held_bot != null:
		return true
	for r in get_tree().get_nodes_in_group("snow_robot"):
		if int(r.holder_id) == int(p.peer_id) and r.state == r.S.HELD:
			return true
	return false


func release_bot(vel: Vector3) -> void:
	if held_bot != null and is_instance_valid(held_bot):
		held_bot.request_release(int(p.peer_id), hold_xform().origin, vel)
	held_bot = null


func throw_bot(power: float) -> void:
	p.suit.throw_anim()
	release_bot(bot_throw_vel(power))
	p._noise_burst += 0.3


func bot_throw_vel(power: float) -> Vector3:
	return p._throw_aim_dir() * (7.0 + 9.0 * power) + Vector3.UP * (3.0 + 2.5 * power) + Vector3(p.velocity.x, 0.0, p.velocity.z) * 0.5


## Подсказка внизу экрана (пусто — обычная)
func hud_text() -> String:
	if swept:
		return "ЛАВИНА! Тебя несёт на спине… Куда вынесет — там и завалит"
	if buried:
		var t := "ЗАВАЛИЛО СНЕГОМ! Сам не выбраться — друг откопает (держать E рядом)"
		if dig_progress > 0.02:
			t += "\nТебя откапывают… %d%%" % roundi(dig_progress * 100.0)
		return t
	if _dig_target != null:
		return "Откапываю друга… держи E  (%d%%)" % roundi(_dig_t / DIG_TIME * 100.0)
	if held_bot != null:
		return "Снежный робот брыкается в руках!  Q (держать) — швырнуть (разобьётся)     E — поставить"
	if p.held_parcel == null and p.held_friend == null and p.held_limb == null and p.arms_count() > 0:
		if buried_buddy() != null:
			return "Держи E — откопать друга из-под снега"
		if robot_near() != null:
			return "E — схватить снежного робота"
	return ""


# ---------------------------------------------------------------------------
#  Вид (у всех копий): сугроб с маячком, когда завален
# ---------------------------------------------------------------------------

func _surface(at: Vector3) -> float:
	var lay = get_tree().get_first_node_in_group("snow_layer")
	if lay:
		return lay.surface(at.x, at.z)
	var ter = get_tree().get_first_node_in_group("terrain")
	return ter.height_at(at.x, at.z) if ter else at.y


var _screen_warm := 0


func _update_screen(delta: float) -> void:
	if _screen_warm > 0:
		_screen_warm -= 1
		return
	if not p.controlled:
		if _screen:
			_screen.visible = false
		return
	_screen_k = move_toward(_screen_k, 1.0 if buried else 0.0, delta * (1.2 if buried else 2.0))
	# от 1-го лица пелена наплывает быстро (чтобы в момент удара не мелькал вал вблизи)
	_swept_k = move_toward(_swept_k, 1.0 if swept else 0.0, delta * (7.0 if p.fp_view else 3.0))
	if _screen_k < 0.01 and _swept_k < 0.01:
		if _screen:
			_screen.visible = false
		return
	_make_screen()
	_screen.visible = true
	_screen_mat.set_shader_parameter("buried", _screen_k)
	_screen_mat.set_shader_parameter("swept", _swept_k)
	_screen_mat.set_shader_parameter("dig", dig_progress)
	_screen_mat.set_shader_parameter("jolt", _jolt)
	_screen_mat.set_shader_parameter("fp", 1.0 if p.fp_view else 0.0)


## Снег на экране (свой дрон) — создаётся заранее и «прогревается» (avalanche._prewarm), чтобы первая лавина не подвисала
func prewarm_screen() -> void:
	if not p.controlled or _screen != null:
		return
	_make_screen()
	_screen.visible = true
	_screen_mat.set_shader_parameter("buried", 0.0)
	_screen_mat.set_shader_parameter("swept", 0.001)
	_screen_warm = 4


func _make_screen() -> void:
	if _screen == null:
		# под надписями дрона (в его же интерфейсе, самым нижним слоем)
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SCREEN_SHADER
		_screen_mat.shader = sh
		_screen_mat.set_shader_parameter("noise", preload("res://scenes/world/avalanche_flow.gd")._noise_tex())
		r.material = _screen_mat
		p.carry_hud.add_child(r)
		p.carry_hud.move_child(r, 0)
		_screen = r


func _process(delta: float) -> void:
	_update_screen(delta)
	_send_mpose(delta)
	# рыхлый снег: проваливаюсь по колено, из-под ног летит снег
	var deep: bool = p.on_deep_snow and not swept and not buried and not p.is_dead and not p.belly and not p.sitting
	_sink = move_toward(_sink, 0.3 if deep else 0.0, delta * 2.0)
	var moving: bool = Vector2(p.velocity.x, p.velocity.z).length() > 1.0
	_feet_fx.emitting = deep and moving
	_mound.visible = buried
	if not buried:
		return
	_mound.global_rotation = Vector3.ZERO
	_mound.global_position = Vector3(p.global_position.x, _surface(p.global_position) - 0.25, p.global_position.z)
	var blink := 1.0 if fmod(p._time, 0.8) < 0.4 else 0.15
	_beacon_mat.emission_energy_multiplier = 3.0 * blink
	_beacon_light.light_energy = 1.6 * blink
	_mound.scale = Vector3.ONE * (1.0 - dig_progress * 0.55) + Vector3(0.04, -0.06, 0.04) * _jolt * sin(p._time * 35.0)
	var me = Network.local_player
	if me == p:
		_label.text = ""
	else:
		_label.text = "ЗАВАЛЕН!\nдержи E — откопать" + ("  %d%%" % roundi(dig_progress * 100.0) if dig_progress > 0.02 else "")
	_label.visible = me != p and me != null and is_instance_valid(me) and me.global_position.distance_to(p.global_position) < 30.0
	if not p.is_local:
		dig_progress = maxf(dig_progress - delta * 0.05, 0.0)
